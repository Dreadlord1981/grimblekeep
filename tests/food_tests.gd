extends SceneTree
## Food/source data contracts, bounded production and physical ledger transactions.

const RAW := &"food_test.raw"
const MEAL := &"food_test.meal"
const PEN := &"food_test.pen"
const HALL := &"food_test.output"
const CELL := Vector2i(2, 2)
const FoodFeature = preload("res://content/features/food_feature.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_validation()
	_test_production()
	_test_transactions_and_output_extension()
	print("FOOD RULES: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(description)


func _fixture() -> GameContext:
	var grid := DungeonGrid.new(7, 6)
	for y in range(1, 5):
		for x in range(1, 6):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	var raw := FoodDefinition.new()
	raw.id = RAW
	raw.tags = [&"raw", &"meat"]
	var meal := FoodDefinition.new()
	meal.id = MEAL
	meal.tags = [&"prepared", &"meat"]
	meal.nutrition_per_unit = 0.95
	var pen := RoomDefinition.new()
	pen.id = PEN
	pen.food_type = RAW
	pen.food_capacity_per_tile = 2
	pen.food_production_seconds = 12.0
	var output := RoomDefinition.new()
	output.id = HALL
	output.food_type = MEAL
	output.food_capacity_per_tile = 4
	var eater := CreatureDefinition.new()
	eater.id = &"food_test.eater"
	eater.capabilities = [&"eat"]
	eater.food_tags = [&"meat"]
	var module := ContentModule.new()
	module.id = &"food_test"
	# The room appears before its food: same-manifest reference order is irrelevant.
	module.definitions = [pen, output, eater, raw, meal]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Food and producer/output room definitions register atomically in any local order")
	var context := GameContext.new(grid, registry)
	context.rooms.place_initial(PEN, [CELL])
	return context


func _test_validation() -> void:
	var food := FoodDefinition.new()
	food.id = &"bad.food"
	food.nutrition_per_unit = NAN
	_check(not food.validation_error().is_empty(), "Nonfinite food nutrition is rejected")
	food.nutrition_per_unit = 0.0
	_check(not food.validation_error().is_empty(), "Nutrition must have positive value")
	var room := RoomDefinition.new()
	room.id = &"bad.producer"
	room.food_capacity_per_tile = 1
	_check(not room.validation_error().is_empty(), "Storage requires an explicit food reference")
	room.food_type = &"missing.food"
	room.food_production_seconds = INF
	_check(not room.validation_error().is_empty(), "Nonfinite producer timing is rejected")
	room.food_production_seconds = 1.0
	var module := ContentModule.new()
	module.id = &"bad.module"
	module.definitions = [room]
	var registry := ContentRegistry.new()
	_check(not registry.register_module(module).is_empty() and registry.get_room(room.id) == null and registry.module_count() == 0, "Unknown output type rejects the whole manifest without partial registration")
	food.nutrition_per_unit = 1.0
	food.id = room.id
	module.definitions = [room, food]
	_check(not registry.register_module(module).is_empty(), "Food shares the stable-ID namespace with room/creature definitions")


func _test_production() -> void:
	var context := _fixture()
	var food := context.food
	var feature := FoodFeature.new()
	feature.setup(context)
	_check(food.total_units == 0 and food.total_capacity == 2, "New Pig Pen source starts empty with bounded storage")
	feature.tick(11.9)
	_check(food.total_units == 0, "Partial breeding cycle produces no premature food")
	context.rooms.place_initial(PEN, [Vector2i(3, 2)])
	_check(is_equal_approx(food.sources[CELL].progress, 11.9), "Harmless connected room expansion preserves existing production progress")
	feature.tick(0.2)
	_check(food.get_stock(CELL, RAW) == 1 and food.get_stock(Vector2i(3, 2), RAW) == 0, "Existing tile completes its cycle while a new tile starts its own")
	feature.tick(1200.0)
	_check(food.total_units == 4 and food.produced_units == 4 and food.sources[CELL].progress == 0.0, "Large simulation steps cap output without an accumulated full-storage backlog")
	var actor := context.spawn_creature(&"food_test.eater", CELL)
	food.reserve_meal(actor)
	_check(food.consume(actor) > 0.0 and food.total_units == 3, "Physical meal consumption creates free source capacity")
	feature.tick(0.5)
	_check(food.total_units == 3, "Freed storage does not instantly replay old full-source cycles")
	feature.tick(11.6)
	_check(food.total_units == 4 and food.accounted_units() == food.produced_units, "Ordinary production resumes and stock plus consumption equals production")
	var before := food.produced_units
	feature.tick(-1.0)
	feature.tick(NAN)
	_check(food.produced_units == before, "Invalid simulation deltas cannot produce food")
	feature.free()


func _test_transactions_and_output_extension() -> void:
	var context := _fixture()
	var food := context.food
	_check(food.produce(CELL, RAW, 99) == 2 and food.produce(CELL, MEAL, 1) == 0, "Explicit producers respect physical capacity and declared output type")
	var actor := context.spawn_creature(&"food_test.eater", Vector2i(5, 4))
	var held := food.reserve_meal(actor)
	_check(held != null and food.total_units == 2 and food.consumed_units == 0, "Meal reservation does not consume food remotely")
	_check(food.consume(actor) == 0.0 and food.total_units == 2, "Physical consumption command rejects remote actors")
	var rival := context.spawn_creature(actor.definition_id, CELL)
	_check(food.reserve_meal(rival) == null, "Two pigs on one tile do not allow overlapping feeding workplaces")
	context.rooms.remove([CELL])
	_check(food.sources.is_empty() and food.total_units == 2 and food.is_valid(held), "Selling the pen stops production but retains edible stock and valid local feeding targets")
	actor.position = context.grid.cell_to_world(CELL)
	_check(is_equal_approx(food.consume(actor), 0.65) and food.total_units == 1 and food.consume(actor) == 0.0, "Meal is consumed exactly once at its physical tile")
	context.rooms.place_initial(HALL, [CELL])
	var feature := FoodFeature.new()
	feature.setup(context)
	feature.tick(1000.0)
	_check(food.get_stock(CELL, MEAL) == 0, "Storage-only prepared-meal output does not generate free cooked food")
	_check(food.produce(CELL, MEAL, 4) == 3 and food.total_units == 4, "A later explicit cooking module can produce another food type through the same output API")
	_check(food.get_stock(CELL, RAW) == 1 and food.get_stock(CELL, MEAL) == 3 and food.accounted_units() == food.produced_units, "Old raw stock and new prepared meals coexist without loss or exceeding total cell capacity")
	food.reserve_meal(actor)
	context.despawn_creature(actor.id)
	_check(food.get_reservation(actor.id) == null and food.reserve_meal(rival) != null, "Removing an eater immediately releases its meal and position")
	context.grid.set_tile(CELL, DungeonGrid.Tile.BEDROCK)
	_check(food.get_reservation(rival.id) == null and food.total_units == 4 and food.accounted_units() == food.produced_units, "Blocking a source invalidates meals while retaining its physical stock in the ledger")
	feature.free()
