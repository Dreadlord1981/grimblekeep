extends SceneTree
## Independent extension, source replacement and physical meal edge cases.

const Production = preload("res://content/features/food_feature.gd")
const Residents = preload("res://content/features/resident_feature.gd")
const Workers = preload("res://content/features/worker_feature.gd")
const BERRY := &"food_review.berry"
const FUNGUS := &"food_review.fungus"
const GARDEN := &"food_review.garden"
const CELLAR := &"food_review.cellar"
const MANUAL := &"food_review.manual"
const FRUIT_EATER := &"food_review.fruit_eater"
const FUNGUS_EATER := &"food_review.fungus_eater"
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_registry_rollback()
	_source_timers_and_replacement()
	_competition_and_proximity()
	_refetch_after_route_change()
	_sold_source_preserves_meals()
	_hybrid_food_priority()
	for failure in _failures:
		push_error(failure)
	print("FOOD REVIEW RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture() -> GameContext:
	var grid := DungeonGrid.new(9, 8)
	for y in range(1, 7):
		for x in range(1, 8):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(7, 6), DungeonGrid.Tile.GOLD)
	var berry := FoodDefinition.new()
	berry.id = BERRY
	berry.tags = [&"fruit"]
	berry.nutrition_per_unit = 0.7
	var fungus := FoodDefinition.new()
	fungus.id = FUNGUS
	fungus.tags = [&"fungi"]
	fungus.nutrition_per_unit = 0.45
	var garden := RoomDefinition.new()
	garden.id = GARDEN
	garden.food_type = BERRY
	garden.food_capacity_per_tile = 3
	garden.food_production_seconds = 0.5
	var cellar := RoomDefinition.new()
	cellar.id = CELLAR
	cellar.food_type = FUNGUS
	cellar.food_capacity_per_tile = 2
	cellar.food_production_seconds = 0.75
	var manual := RoomDefinition.new()
	manual.id = MANUAL
	manual.food_type = BERRY
	manual.food_capacity_per_tile = 4
	manual.food_production_seconds = 0.0
	var fruit_eater := CreatureDefinition.new()
	fruit_eater.id = FRUIT_EATER
	fruit_eater.capabilities = [&"eat"]
	fruit_eater.food_tags = [&"fruit"]
	fruit_eater.food_per_meal = 2
	var fungus_eater := CreatureDefinition.new()
	fungus_eater.id = FUNGUS_EATER
	fungus_eater.capabilities = [&"eat"]
	fungus_eater.food_tags = [&"fungi"]
	var hybrid := CreatureDefinition.new()
	hybrid.id = &"food_review.hybrid"
	hybrid.capabilities = [&"rest", &"eat", &"haul"]
	hybrid.food_tags = [&"fruit"]
	hybrid.initial_energy = 0.95
	hybrid.energy_drain_per_second = 0.0
	hybrid.initial_satiety = 0.1
	hybrid.hunger_drain_per_second = 0.0
	hybrid.eating_seconds = 0.3
	hybrid.move_speed = 6.0
	var lair := RoomDefinition.new()
	lair.id = &"food_review.lair"
	lair.tags = [&"lair"]
	var vault := RoomDefinition.new()
	vault.id = &"food_review.vault"
	vault.gold_storage_per_tile = 500
	var module := ContentModule.new()
	module.id = &"food_review.extension"
	# Forward food references deliberately precede their definitions.
	module.definitions = [garden, cellar, manual, fruit_eater, fungus_eater, hybrid, lair, vault, berry, fungus]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Independent foods, diets and producers register without built-in IDs or ordering assumptions")
	return GameContext.new(grid, registry)


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _conserved(context: GameContext) -> bool:
	if context.food.accounted_units() != context.food.produced_units:
		return false
	for definition in context.registry.get_foods():
		var remaining := 0
		for cell in context.food.stock:
			remaining += context.food.get_stock(cell, definition.id)
		if remaining + context.food.consumed_by_type.get(definition.id, 0) != context.food.produced_by_type.get(definition.id, 0):
			return false
	return true


func _registry_rollback() -> void:
	var registry := ContentRegistry.new()
	var fresh := FoodDefinition.new()
	fresh.id = &"food_review.uncommitted"
	var broken := RoomDefinition.new()
	broken.id = &"food_review.broken"
	broken.food_type = &"food_review.missing"
	broken.food_capacity_per_tile = 1
	broken.food_production_seconds = 1.0
	var module := ContentModule.new()
	module.id = &"food_review.invalid"
	module.definitions = [fresh, broken]
	_check(not registry.register_module(module).is_empty(), "Missing producer food reference rejects the complete module")
	_check(registry.get_food(fresh.id) == null and registry.get_room(broken.id) == null and registry.module_count() == 0, "Failed food registration publishes no partial definitions")
	fresh.nutrition_per_unit = NAN
	_check(not fresh.validation_error().is_empty(), "Non-finite food nutrition is rejected")
	fresh.nutrition_per_unit = 0.0
	_check(not fresh.validation_error().is_empty(), "Zero nutrition cannot become an endless zero-value meal")
	var invalid_eater := CreatureDefinition.new()
	invalid_eater.id = &"food_review.invalid_eater"
	invalid_eater.food_per_meal = 0
	_check(not invalid_eater.validation_error().is_empty(), "Invalid appetite cannot cause division by zero")
	invalid_eater.food_per_meal = 1
	invalid_eater.eating_seconds = NAN
	_check(not invalid_eater.validation_error().is_empty(), "Invalid meal duration is rejected")


func _source_timers_and_replacement() -> void:
	var context := _fixture()
	var cell := Vector2i(3, 3)
	context.rooms.place_initial(GARDEN, [cell])
	context.rooms.place_initial(MANUAL, [Vector2i(6, 3)])
	var production := Production.new()
	production.setup(context)
	production.tick(0.3)
	var original_source: FoodSourceState = context.food.sources[cell]
	context.rooms.place_initial(&"food_review.vault", [Vector2i(1, 1)])
	_check(context.food.sources[cell] == original_source and is_equal_approx(original_source.progress, 0.3), "Unrelated room rebuild preserves producer identity and partial progress")
	production.tick(0.21)
	_check(context.food.get_stock(cell, BERRY) == 1 and context.food.total_at(Vector2i(6, 3)) == 0, "Custom producer uses its interval while a manual producer remains inactive")
	production.tick(10.0)
	production.tick(20.0)
	_check(context.food.total_at(cell) == 3 and context.food.produced_units == 3 and is_zero_approx(original_source.progress), "Full source clamps stock and discards accumulated production backlog")
	var eater := context.spawn_creature(FRUIT_EATER, cell)
	context.food.reserve_meal(eater)
	_check(is_equal_approx(context.food.consume(eater), 0.35), "Species appetite scales shared food nutrition without an ID switch")
	production.tick(0.49)
	_check(context.food.total_at(cell) == 2, "Freed capacity does not instantly receive a banked production reward")
	production.tick(0.02)
	_check(context.food.total_at(cell) == 3, "Producer resumes after one real interval with space")
	context.rooms.remove([cell])
	context.rooms.place_initial(CELLAR, [cell])
	production.tick(100.0)
	_check(context.food.get_stock(cell, BERRY) == 3 and context.food.get_stock(cell, FUNGUS) == 0, "Replacing producer preserves old food and counts all food types against new capacity")
	for index in 2:
		context.food.reserve_meal(eater)
		context.food.consume(eater)
	production.tick(0.74)
	_check(context.food.get_stock(cell, FUNGUS) == 0, "Replacement source starts a fresh output timer after old stock frees capacity")
	production.tick(0.02)
	_check(context.food.get_stock(cell, BERRY) == 1 and context.food.get_stock(cell, FUNGUS) == 1 and context.food.total_at(cell) == 2, "Different food types coexist physically under one total tile capacity")
	_check(context.food.produce(cell, BERRY, 5) == 0, "Producer cannot create an unrelated output type")
	_check(context.food.produce(Vector2i(6, 3), BERRY, 2) == 2, "Manual output uses the same authoritative production API for future cooks")
	_check(_conserved(context), "Producer replacement conserves both individual food types and the total ledger")
	production.free()


func _competition_and_proximity() -> void:
	var context := _fixture()
	var berry_cell := Vector2i(3, 3)
	var fungus_cell := Vector2i(6, 3)
	context.rooms.place_initial(GARDEN, [berry_cell])
	context.rooms.place_initial(CELLAR, [fungus_cell])
	context.food.produce(berry_cell, BERRY, 3)
	context.food.produce(fungus_cell, FUNGUS, 2)
	var first := context.spawn_creature(FRUIT_EATER, Vector2i(1, 1))
	var second := context.spawn_creature(FRUIT_EATER, Vector2i(1, 2))
	var fungal := context.spawn_creature(FUNGUS_EATER, Vector2i(5, 3))
	var reservation := context.food.reserve_meal(first)
	_check(reservation != null and reservation.food_id == BERRY and context.food.reserve_meal(first) == reservation, "Compatible reservation is idempotent and respects the species diet")
	_check(context.food.reserve_meal(second) == null, "Multiple food units still allow only one eater at a standing cell")
	_check(context.food.reserve_meal(fungal).food_id == FUNGUS, "A second diet reserves its own compatible food source")
	_check(context.food.consume(first) == 0.0 and context.food.total_units == 5, "Reservation alone cannot consume remote food")
	first.position = context.grid.cell_to_world(berry_cell) + Vector3(0.13, 0, 0)
	_check(context.food.consume(first) == 0.0, "Food cannot be consumed just outside the local eating radius")
	first.position = context.grid.cell_to_world(berry_cell) + Vector3(0.119, 0, 0)
	_check(is_equal_approx(context.food.consume(first), 0.35) and context.food.consume(first) == 0.0, "One local meal debits once and cannot be replayed")
	_check(context.food.reserve_meal(second) != null, "Finishing a meal releases its standing position for another eater")
	context.despawn_creature(second.id)
	_check(context.food.get_reservation(second.id) == null, "Removing an eater immediately releases its meal")
	fungal.definition_id = FRUIT_EATER
	context.food.prune(context.actors)
	_check(context.food.get_reservation(fungal.id) == null and context.food.get_stock(fungus_cell, FUNGUS) == 2, "Diet change releases an incompatible reservation without consuming it")
	_check(_conserved(context), "Food competition and interruption conserve every type")


func _refetch_after_route_change() -> void:
	var context := _fixture()
	var cell := Vector2i(6, 3)
	context.rooms.place_initial(GARDEN, [cell])
	context.food.produce(cell, BERRY, 1)
	var eater := context.spawn_creature(FRUIT_EATER, Vector2i(1, 3))
	var initial := context.food.reserve_meal(eater)
	_check(initial != null, "Fixture first reserves a reachable meal")
	for y in range(1, 7):
		context.grid.set_tile(Vector2i(4, y), DungeonGrid.Tile.BEDROCK)
	_check(context.food.reserve_meal(eater) == null and context.food.get_reservation(eater.id) == null, "Re-requesting a meal after its route is sealed releases the unreachable reservation")
	context.grid.set_tile(Vector2i(4, 3), DungeonGrid.Tile.FLOOR)
	var reopened := context.food.reserve_meal(eater)
	_check(reopened != null and reopened != initial, "Opening a route permits a fresh reachable reservation")
	eater.position = Vector3(NAN, 0, 0)
	_check(context.food.reserve_meal(eater) == null and context.food.get_reservation(eater.id) == null, "Invalid actor position releases an old meal rather than stranding its cell")
	_check(_conserved(context), "Route and position changes never debit reserved food")


func _sold_source_preserves_meals() -> void:
	var context := _fixture()
	var cell := Vector2i(3, 3)
	context.rooms.place_initial(GARDEN, [cell])
	context.food.produce(cell, BERRY, 2)
	var eater := context.spawn_creature(FRUIT_EATER, Vector2i(2, 3))
	var reserved := context.food.reserve_meal(eater)
	context.rooms.remove([cell])
	_check(not context.food.sources.has(cell) and context.food.total_at(cell) == 2 and context.food.is_valid(reserved), "Selling a source preserves loose food and an otherwise valid meal reservation")
	eater.position = context.grid.cell_to_world(cell)
	_check(context.food.consume(eater) > 0.0 and context.food.total_at(cell) == 1, "A locally reached meal remains edible after its room was sold")
	context.food.reserve_meal(eater)
	context.grid.set_tile(cell, DungeonGrid.Tile.BEDROCK)
	_check(context.food.get_reservation(eater.id) == null and context.food.total_at(cell) == 1, "Blocking a loose-food cell releases the eater while preserving stock")
	context.grid.set_tile(cell, DungeonGrid.Tile.FLOOR)
	_check(context.food.reserve_meal(eater) != null and _conserved(context), "Unblocked loose food is recoverable without rebuilding a producer")


func _hybrid_food_priority() -> void:
	var context := _fixture()
	context.rooms.place_initial(&"food_review.lair", [Vector2i(2, 2)])
	context.rooms.place_initial(&"food_review.vault", [Vector2i(4, 2)])
	context.rooms.place_initial(MANUAL, [Vector2i(6, 2)])
	context.food.produce(Vector2i(6, 2), BERRY, 3)
	var actor := context.spawn_creature(&"food_review.hybrid", Vector2i(2, 2))
	context.beds.reserve(actor, context.registry.get_creature(actor.definition_id))
	context.beds.establish(actor)
	actor.carried_gold = context.economy.mine(Vector2i(7, 6), 60)
	var residents := Residents.new()
	var workers := Workers.new()
	residents.setup(context)
	workers.setup(context)
	var saw_eating := false
	var single_owner := true
	var conserved := true
	for tick in 500:
		var before := actor.position
		residents.tick(0.1)
		workers.tick(0.1)
		saw_eating = saw_eating or actor.action == &"eating"
		if actor.food_requested:
			single_owner = single_owner and workers.job_board.job_for(actor.id) == null
		single_owner = single_owner and actor.position.distance_to(before) <= 0.601
		conserved = conserved and _conserved(context) and context.economy.accounted_gold(context.actors) == context.economy.initial_gold
		if context.economy.stored_gold == 60:
			break
	_check(saw_eating and actor.satiety >= 0.9 and context.food.consumed_units > 0, "A hungry hybrid physically eats compatible food before resuming work")
	_check(single_owner, "Food needs release worker jobs and never move the actor twice per timestep")
	_check(context.economy.stored_gold == 60 and actor.carried_gold == 0 and conserved, "Delivery resumes after food with conserved cargo and food")
	workers.free()
	residents.free()
