extends SceneTree
## Core command boundaries, inspection, custody, local needs and live map edits.

const CREATURE := &"keeper_test.creature"
const LOCKED := &"keeper_test.locked"
const PEN := &"keeper_test.pen"
const LAIR := &"keeper_test.lair"
const FOOD := &"keeper_test.food"
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_inspection_and_eligibility()
	_drop_validation()
	_food_bed_cargo()
	_removal_and_fallback()
	_example_module()
	_density_correction()
	for failure in _failures:
		push_error(failure)
	print("KEEPER RULES: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _fixture(heart: bool = true) -> GameContext:
	var grid := DungeonGrid.new(11, 9)
	for y in range(1, 7):
		for x in range(1, 8):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	if heart:
		grid.set_tile(Vector2i(2, 2), DungeonGrid.Tile.HEART)
	grid.set_tile(Vector2i(9, 7), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(6, 2), DungeonGrid.Tile.PORTAL)
	var creature := CreatureDefinition.new()
	creature.id = CREATURE
	creature.capabilities = [&"rest", &"eat", &"haul", &"excavate"]
	var locked := CreatureDefinition.new()
	locked.id = LOCKED
	locked.keeper_pickup_allowed = false
	var food := FoodDefinition.new()
	food.id = FOOD
	var pen := RoomDefinition.new()
	pen.id = PEN
	pen.food_type = FOOD
	pen.food_capacity_per_tile = 2
	var lair := RoomDefinition.new()
	lair.id = LAIR
	lair.tags = [&"lair"]
	var module := ContentModule.new()
	module.id = &"keeper_test.module"
	module.definitions = [creature, locked, food, pen, lair]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Custody uses independent extensible species definitions")
	return GameContext.new(grid, registry)


func _inspection_and_eligibility() -> void:
	var context := _fixture()
	var keeper := context.keeper
	var actor := context.spawn_creature(CREATURE, Vector2i(3, 3))
	var locked := context.spawn_creature(LOCKED, Vector2i(4, 3))
	_check(not keeper.inspect(999) and not keeper.pickup(999) and keeper.held_actor == null, "Unknown IDs cannot inspect or acquire another actor")
	_check(keeper.inspect(actor.id) and keeper.inspected_actor == actor, "Inspection refers to the existing authoritative identity")
	_check(keeper.rename_selected("  Grumble  ") and actor.custom_name == "Grumble", "Creature naming trims outer whitespace")
	_check(not keeper.rename_selected("Bad\nName") and not keeper.rename_selected("x".repeat(33)) and actor.custom_name == "Grumble", "Invalid multiline or overlong names cannot replace a valid name")
	_check(keeper.rename_selected("") and actor.custom_name.is_empty(), "Clearing a custom name restores the species fallback")
	_check(keeper.inspect(locked.id) and not keeper.pickup(locked.id) and not locked.is_held, "Non-pickable definitions remain inspectable")
	_check(keeper.pickup(actor.id) and keeper.held_actor == actor and actor.is_held and keeper.inspected_actor == actor, "Pickup holds and inspects the same live actor")
	_check(not keeper.pickup(locked.id) and not keeper.pickup(actor.id) and context.actors.size() == 2, "An ineligible actor and duplicate held identity cannot enter the queue")
	keeper.clear_inspection()
	_check(keeper.inspected_actor == null and keeper.held_actor == actor, "Closing inspection never discards a held creature")
	var result := keeper.drop(Vector2i(3, 4))
	_check(result.success and not actor.is_held and keeper.held_actor == null and actor.position == context.grid.cell_to_world(Vector2i(3, 4)), "Valid drop moves the original actor to the chosen floor")
	_check(not keeper.drop(Vector2i(3, 5)).success, "A repeated release cannot drop a duplicate")
	var invalid := CreatureDefinition.new()
	invalid.id = &"keeper_test.bad_bounds"
	invalid.keeper_pick_size = Vector3(INF, 1, 1)
	_check(not invalid.validation_error().is_empty(), "Unbounded picking volumes are rejected during definition validation")


func _drop_validation() -> void:
	var context := _fixture()
	var actor := context.spawn_creature(CREATURE, Vector2i(3, 3))
	var other := context.spawn_creature(CREATURE, Vector2i(4, 4))
	context.rooms.place_initial(LAIR, [Vector2i(5, 4)])
	context.beds.reserve(other, context.registry.get_creature(CREATURE))
	context.keeper.pickup(actor.id)
	var blocked: Array[Vector2i] = [Vector2i(-1, 2), Vector2i(0, 0), Vector2i(2, 2), Vector2i(6, 2), Vector2i(9, 7)]
	var rejected := true
	for cell in blocked:
		var quote := context.keeper.quote_drop(cell)
		var result := context.keeper.drop(cell)
		rejected = rejected and not quote.valid and not quote.reason.is_empty() and not result.success and actor.is_held and context.keeper.held_actor == actor
	_check(rejected, "Walls, bounds, Heart, portal and isolated ground reject drops without losing custody")
	_check(context.keeper.quote_drop(Vector2i(4, 4)).valid and context.keeper.quote_drop(Vector2i(5, 4)).valid, "Other creatures and personal beds never forbid otherwise valid shared floor")
	_check(context.keeper.drop(Vector2i(4, 4)).success and actor.position == other.position, "Dropping onto an occupied valid tile preserves both individual creatures")
	context.keeper.pickup(actor.id)
	var target := Vector2i(6, 5)
	_check(context.keeper.quote_drop(target).valid, "Accessible empty floor previews a valid drop")
	context.grid.set_tile(target, DungeonGrid.Tile.BEDROCK)
	_check(not context.keeper.drop(target).success and actor.is_held, "Commit revalidates terrain changed after a valid preview")
	context.grid.set_tile(target, DungeonGrid.Tile.FLOOR)
	_check(context.keeper.drop(target).success, "Restored floor allows the same held creature to be dropped")


func _food_bed_cargo() -> void:
	var context := _fixture()
	var actor := context.spawn_creature(CREATURE, Vector2i(3, 3))
	context.rooms.place_initial(LAIR, [Vector2i(3, 3), Vector2i(4, 3)])
	var bed := context.beds.reserve(actor, context.registry.get_creature(CREATURE))
	actor.position = bed.center(context.grid)
	_check(context.beds.establish(actor), "Fixture establishes its personal bed locally")
	context.rooms.place_initial(PEN, [Vector2i(3, 4)])
	context.food.produce(Vector2i(3, 4), FOOD, 2)
	actor.position = context.grid.cell_to_world(Vector2i(3, 4))
	context.food.reserve_meal(actor)
	actor.carried_gold = 37
	context.economy.initial_gold += 37
	actor.work_progress = 0.8
	actor.rest_requested = true
	actor.food_requested = true
	context.keeper.pickup(actor.id)
	_check(context.food.reservations.is_empty() and context.food.total_units == 2 and context.food.consumed_units == 0, "Picking up an eater releases its exact meal without consuming food")
	_check(context.beds.get_bed(actor.id) == bed and bed.established, "An established personal home survives pickup")
	_check(not actor.needs_requested and actor.work_progress == 0 and actor.action == &"held" and actor.carried_gold == 37, "Held state clears active progress while retaining physical cargo")
	_check(context.food.reserve_meal(actor) == null and context.food.consume(actor) == 0.0 and context.beds.reserve(actor, context.registry.get_creature(CREATURE)) == null and not context.beds.establish(actor), "Core commands forbid remote food and bed actions while held")
	_check(context.economy.accounted_gold(context.actors) == context.economy.initial_gold and context.food.accounted_units() == context.food.produced_units, "Core custody preserves both authoritative ledgers")
	_check(context.keeper.drop(bed.anchor).success and actor.carried_gold == 37, "A creature can be returned to its own established home with its cargo")
	context.beds.release(actor.id)
	var pending := context.beds.reserve(actor, context.registry.get_creature(CREATURE))
	context.keeper.pickup(actor.id)
	_check(pending != null and not pending.established and context.beds.get_bed(actor.id) == null, "Pending claim space is released when its creature is picked up")


func _removal_and_fallback() -> void:
	var context := _fixture(false)
	var actor := context.spawn_creature(CREATURE, Vector2i(3, 3))
	context.keeper.pickup(actor.id)
	_check(context.keeper.quote_drop(Vector2i(6, 5)).valid and not context.keeper.quote_drop(Vector2i(9, 7)).valid, "Heart-less scenarios use pickup-origin connectivity instead of arbitrary remote ground")
	actor.carried_gold = 13
	context.economy.initial_gold += 13
	_check(context.despawn_creature(actor.id) and context.keeper.held_actor == null and context.keeper.inspected_actor == null and not actor.is_held, "Despawn clears held and inspected references immediately")
	_check(context.economy.accounted_gold(context.actors) == context.economy.initial_gold, "Removing a held creature retains cargo for the existing recovery service")
	actor = context.spawn_creature(CREATURE, Vector2i(4, 3))
	actor.carried_gold = 17
	context.economy.initial_gold += 17
	context.keeper.pickup(actor.id)
	context.actors.erase(actor)
	context.simulation_ticked.emit(0.1)
	_check(context.keeper.held_actor == null and context.keeper.inspected_actor == null and not actor.is_held, "Direct actor removal also prunes custody without a stale hidden creature")
	_check(context.economy.accounted_gold(context.actors) == context.economy.initial_gold and context.economy.pending_cargo.has(actor.id), "Raw removal of a held carrier retains its gold even without an active worker behavior")
	context.keeper.prune()
	_check(context.economy.accounted_gold(context.actors) == context.economy.initial_gold, "Repeated custody cleanup cannot duplicate removed cargo")


func _density_correction() -> void:
	var registry := ContentRegistry.new()
	registry.register_module(load("res://content/modules/foundation.tres"))
	var pen := registry.get_room(&"foundation.pig_pen")
	_check(pen.food_minimum_size == Vector2i(2, 1) and pen.food_tiles_per_unit == 2, "Actual Pig Pen definition uses the user's 2x1 minimum and two-tile density")
	var context := GameContext.new(preload("res://content/scenarios/foundation_layout.gd").create(), registry)
	context.rooms.place_initial(pen.id, [Vector2i(9, 11)])
	_check(context.food.total_capacity == 0, "A single actual Pig Pen tile cannot produce a pig")
	context.rooms.place_initial(pen.id, [Vector2i(10, 11)])
	_check(context.food.total_capacity == 1, "A connected 2x1 actual Pig Pen supports one pig")
	context.rooms.place_initial(pen.id, [Vector2i(9, 12), Vector2i(10, 12)])
	_check(context.food.total_capacity == 2, "Four connected actual Pig Pen tiles support two pigs")


func _example_module() -> void:
	var context := _fixture()
	var actor := context.spawn_creature(CREATURE, Vector2i(3, 3))
	var feature := preload("res://content/features/wander_feature.gd").new()
	feature.setup(context)
	feature.tick(0.1)
	context.keeper.pickup(actor.id)
	var position := actor.position
	feature.tick(3.0)
	_check(actor.position == position, "The independent ambient feature also respects keeper custody")
	_check(context.keeper.drop(Vector2i(6, 5)).success and feature.get("_targets").is_empty(), "Dropping clears example-module routes from the previous location")
	feature.tick(0.1)
	_check(actor.position.distance_to(context.grid.cell_to_world(Vector2i(6, 5))) <= 0.121, "A replaceable mechanic resumes locally without stale-target teleportation")
	feature.free()
