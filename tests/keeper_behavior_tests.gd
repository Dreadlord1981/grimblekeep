extends SceneTree
## Keeper interruptions across real worker, home, food and rest loops.

const WorkerFeature = preload("res://content/features/worker_feature.gd")
const ResidentFeature = preload("res://content/features/resident_feature.gd")
const STEP := 1.0 / 30.0
const SPECIES := &"keeper_behavior.actor"
const TARGET := Vector2i(9, 3)
const LAIR := &"keeper_behavior.lair"
const PEN := &"keeper_behavior.pen"
const FOOD := &"keeper_behavior.food"
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_strike_interruption(DungeonGrid.Tile.ROCK)
	_test_strike_interruption(DungeonGrid.Tile.GOLD)
	_test_strike_interruption(DungeonGrid.Tile.GEM)
	_test_cargo_and_reload()
	_test_pending_home_claim()
	_test_established_sleep()
	_test_eating_and_source_removal()
	_test_hybrid_and_repeated_cycles()
	_test_despawn_held_cargo()
	for failure in _failures:
		push_error(failure)
	print("KEEPER BEHAVIOR: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(capabilities: Array[StringName] = [&"excavate", &"haul"], kind: int = DungeonGrid.Tile.GOLD) -> Dictionary:
	var grid := DungeonGrid.new(11, 9)
	for y in range(1, 8):
		for x in range(1, 9):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(TARGET, kind)
	grid.set_tile(Vector2i(1, 4), DungeonGrid.Tile.HEART)
	var definition := CreatureDefinition.new()
	definition.id = SPECIES
	definition.capabilities = capabilities
	definition.move_speed = 6.0
	definition.initial_energy = 0.9
	definition.initial_satiety = 0.9
	definition.energy_drain_per_second = 0.1
	definition.sleep_restore_per_second = 0.8
	definition.hunger_drain_per_second = 0.1
	definition.eating_seconds = 1.5
	var lair := RoomDefinition.new()
	lair.id = LAIR
	lair.tags = [&"lair"]
	var treasury := RoomDefinition.new()
	treasury.id = &"keeper_behavior.treasury"
	treasury.gold_storage_per_tile = 500
	var pen := RoomDefinition.new()
	pen.id = PEN
	pen.food_type = FOOD
	pen.food_capacity_per_tile = 8
	var food := FoodDefinition.new()
	food.id = FOOD
	food.nutrition_per_unit = 1.0
	var module := ContentModule.new()
	module.id = &"keeper_behavior"
	module.definitions = [definition, lair, treasury, pen, food]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Keeper behavior fixture registers modular actor/room/food definitions")
	var context := GameContext.new(grid, registry)
	context.rooms.place_initial(treasury.id, [Vector2i(2, 2)])
	context.spawn_creature(SPECIES, Vector2i(8, 3))
	context.mark_excavation([TARGET])
	var worker := WorkerFeature.new()
	worker.setup(context)
	var resident := ResidentFeature.new()
	resident.setup(context)
	return {"context": context, "definition": definition, "worker": worker, "resident": resident, "gold_ok": true, "food_ok": true}


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.resident.tick(STEP)
		scene.worker.tick(STEP)
		var context: GameContext = scene.context
		if context.economy.accounted_gold(context.actors) != context.economy.initial_gold + context.economy.gem_gold_created:
			scene.gold_ok = false
		if context.food.accounted_units() != context.food.produced_units:
			scene.food_ok = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 35.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _finish(scene: Dictionary, label: String) -> void:
	_check(scene.gold_ok and scene.food_ok, "%s conserves physical gold and food at every tick" % label)
	scene.resident.free()
	scene.worker.free()


func _drop(scene: Dictionary, cell: Vector2i) -> void:
	var context: GameContext = scene.context
	var result := context.keeper.drop(cell)
	_check(result.success and context.keeper.held_actor == null and not context.actors[0].is_held, "Keeper drop returns a single live creature to valid floor")


func _establish_home(scene: Dictionary, cell: Vector2i) -> BedState:
	var context: GameContext = scene.context
	context.rooms.place_initial(LAIR, [cell])
	var actor := context.actors[0]
	var original := actor.position
	var bed := context.beds.reserve(actor, scene.definition)
	actor.position = bed.center(context.grid)
	_check(context.beds.establish(actor), "Fixture home is established with its owner physically present")
	actor.position = original
	return bed


func _test_strike_interruption(kind: int) -> void:
	var scene := _fixture([&"excavate", &"haul"], kind)
	var context: GameContext = scene.context
	var actor := context.actors[0]
	_check(_until(scene, func() -> bool: return actor.work_progress > 0.1), "Worker begins a real dig/mining strike before pickup")
	var previous: WorkerBehavior = scene.worker.behaviors[actor.id]
	var remaining: int = context.economy.remaining_gold.get(TARGET, 0)
	var generated := context.economy.gem_gold_created
	_check(context.keeper.pickup(actor.id), "Keeper can pick up an actively working creature")
	_check(scene.worker.job_board.active_job_count() == 0 and scene.worker.job_board.work_reservations.is_empty(), "Pickup immediately releases worker jobs and workplaces without waiting for a tick")
	var position := actor.position
	previous.tick(10.0, scene.definition)
	_check(scene.worker.job_board.assign(actor, scene.definition) == null, "Held actors cannot acquire jobs through a direct board call")
	_advance(scene, 5.0)
	_check(actor.is_held and actor.position == position and actor.action == &"held" and actor.work_progress == 0.0, "Held worker remains frozen even through stale direct behavior calls")
	_check(context.grid.get_tile(TARGET) == kind and context.economy.remaining_gold.get(TARGET, 0) == remaining and context.economy.gem_gold_created == generated, "Pickup prevents interrupted dig/mining completion and stale mineral rewards")
	_drop(scene, Vector2i(5, 3))
	_check(_until(scene, func() -> bool: return context.grid.get_tile(TARGET) == DungeonGrid.Tile.FLOOR if kind == DungeonGrid.Tile.ROCK else actor.carried_gold > 0), "Dropped creature discovers its retained work from its new position")
	_finish(scene, "Strike pickup/drop")


func _test_cargo_and_reload() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var actor := context.actors[0]
	_check(_until(scene, func() -> bool: return actor.carried_gold > 0), "Cargo fixture obtains real mined gold")
	var cargo := actor.carried_gold
	var previous: WorkerBehavior = scene.worker.behaviors[actor.id]
	context.keeper.pickup(actor.id)
	_check(not previous.drop_cargo() and actor.carried_gold == cargo, "A stale direct cargo-drop call cannot discard a live held worker's cargo")
	scene.worker.setup(context)
	scene.resident.setup(context)
	var position := actor.position
	_advance(scene, 4.0)
	_check(actor.is_held and actor.position == position and actor.carried_gold == cargo and context.economy.ground_gold.is_empty(), "Feature reload while held preserves cargo without dropping or hauling it")
	_check(scene.worker.job_board.active_job_count() == 0 and scene.worker.behaviors.is_empty(), "Reloaded feature never creates active work for a held actor")
	context.clear_excavation_marks()
	_drop(scene, Vector2i(3, 3))
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == cargo), "Dropping near Treasury resumes delivery of exactly the retained cargo")
	_check(actor.carried_gold == 0, "Resumed haul debits carried cargo once")
	_finish(scene, "Held cargo and reload")


func _test_pending_home_claim() -> void:
	var scene := _fixture([&"rest"])
	var context: GameContext = scene.context
	context.rooms.place_initial(LAIR, [Vector2i(6, 3)])
	var actor := context.actors[0]
	_check(_until(scene, func() -> bool: return actor.action == &"claiming_bed" and actor.work_progress > 0.1), "Resident begins a real local bed claim before pickup")
	var pending := context.beds.get_bed(actor.id)
	var old: ResidentBehavior = scene.resident.behaviors[actor.id]
	context.keeper.pickup(actor.id)
	_check(context.beds.get_bed(actor.id) == null and not pending.established, "Pickup releases pending home space without remotely creating a bed")
	var energy := actor.energy
	old.tick(10.0, scene.definition)
	_advance(scene, 3.0)
	_check(actor.energy == energy and actor.work_progress == 0.0 and not pending.established, "Held resident cannot finish a stale claim or drain energy")
	_drop(scene, Vector2i(5, 3))
	_check(_until(scene, func() -> bool:
		var bed := context.beds.get_bed(actor.id)
		return bed != null and bed.established), "Dropped resident makes a fresh local claim")
	_check(context.beds.get_bed(actor.id) != pending, "A dropped unfinished claim uses a fresh reservation")
	_finish(scene, "Pending home pickup/drop")


func _test_established_sleep() -> void:
	var scene := _fixture([&"rest", &"eat"])
	var context: GameContext = scene.context
	var bed := _establish_home(scene, Vector2i(6, 3))
	var actor := context.actors[0]
	actor.energy = 0.1
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Resident is sleeping in its established home before pickup")
	context.keeper.pickup(actor.id)
	scene.resident.setup(context)
	scene.worker.setup(context)
	var energy := actor.energy
	var satiety := actor.satiety
	_advance(scene, 6.0)
	_check(actor.energy == energy and actor.satiety == satiety and actor.action == &"held", "Held sleeper freezes both needs and receives no sleep restoration")
	_check(context.beds.get_bed(actor.id) == bed and bed.established, "Pickup retains the established personal bed")
	_drop(scene, Vector2i(4, 3))
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Dropped tired resident walks back to its existing bed and resumes sleep")
	_finish(scene, "Established sleeper pickup/drop")


func _test_eating_and_source_removal() -> void:
	var scene := _fixture([&"eat"])
	var context: GameContext = scene.context
	var food_cell := Vector2i(6, 4)
	context.rooms.place_initial(PEN, [food_cell])
	context.food.produce(food_cell, FOOD, 4)
	var actor := context.actors[0]
	actor.satiety = 0.1
	_check(_until(scene, func() -> bool: return actor.action == &"eating" and actor.work_progress > 0.1), "Resident starts a real local eating action before pickup")
	var old: ResidentBehavior = scene.resident.behaviors[actor.id]
	var feeding: ResidentFeeding = old.get("_feeding")
	var consumed := context.food.consumed_units
	context.keeper.pickup(actor.id)
	_check(context.food.get_reservation(actor.id) == null and not actor.food_requested, "Pickup immediately releases meal ownership and its need movement lock")
	var satiety := actor.satiety
	feeding.update_need(10.0, scene.definition)
	feeding.tick(10.0, scene.definition)
	_check(not feeding.try_begin(), "Held eater rejects direct meal acquisition")
	context.rooms.remove([food_cell])
	context.grid.set_tile(food_cell, DungeonGrid.Tile.BEDROCK)
	_advance(scene, 4.0)
	_check(context.food.consumed_units == consumed and actor.satiety == satiety and context.food.total_units == 4, "Held eating interruption cannot consume or lose food when its source disappears")
	_drop(scene, Vector2i(4, 4))
	_advance(scene, 1.0)
	_check(context.food.reservations.is_empty() and not actor.food_requested, "Dropped eater safely waits while old food is inaccessible")
	context.grid.set_tile(food_cell, DungeonGrid.Tile.FLOOR)
	_check(_until(scene, func() -> bool: return context.food.consumed_units > consumed), "Reopening loose food allows dropped eater to reserve and finish a fresh meal")
	_finish(scene, "Eating pickup/source interruption")


func _test_hybrid_and_repeated_cycles() -> void:
	var scene := _fixture([&"rest", &"eat", &"excavate", &"haul"])
	var context: GameContext = scene.context
	_establish_home(scene, Vector2i(6, 5))
	var actor := context.actors[0]
	scene.definition.energy_drain_per_second = 0.0
	scene.definition.hunger_drain_per_second = 0.0
	_check(_until(scene, func() -> bool: return actor.carried_gold > 0), "Healthy hybrid mines before repeated keeper interruption")
	var cargo := actor.carried_gold
	context.clear_excavation_marks()
	for index in 5:
		_check(context.keeper.pickup(actor.id), "Repeated pickup succeeds for the one live hybrid")
		var position := actor.position
		_advance(scene, 0.5)
		_check(actor.position == position and actor.carried_gold == cargo and context.actors.size() == 1, "Repeated holding never duplicates creatures or changes cargo")
		_drop(scene, Vector2i(4 + index % 2, 3))
		# Let a fresh route/job start, then repick before cargo can be delivered.
		_advance(scene, STEP)
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == cargo), "After repeated drops the hybrid resumes a single correct haul")
	_check(scene.worker.job_board.active_job_count() == 0 and context.food.reservations.is_empty(), "Repeated control handoffs leave no stale job or meal reservations")
	_finish(scene, "Repeated hybrid pickup/drop")


func _test_despawn_held_cargo() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var actor := context.actors[0]
	_check(_until(scene, func() -> bool: return actor.carried_gold > 0), "Held despawn fixture obtains real cargo")
	var cargo := actor.carried_gold
	context.keeper.pickup(actor.id)
	scene.worker.setup(context)
	context.despawn_creature(actor.id)
	_check(context.keeper.held_actor == null and context.actors.is_empty(), "Despawn removes the held reference and single live creature")
	_check(_until(scene, func() -> bool: return context.economy.pending_gold() == 0), "Reloaded worker feature adopts and recovers untracked held cargo from the ledger")
	var loose := 0
	for amount in context.economy.ground_gold.values():
		loose += amount
	_check(loose == cargo and actor.carried_gold == 0, "Held despawn recovers cargo exactly once as physical loose gold")
	_finish(scene, "Held actor despawn")
