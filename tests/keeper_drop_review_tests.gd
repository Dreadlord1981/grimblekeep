extends SceneTree
## Independent shared-floor custody, identity and resumed-economy regressions.

const WorkerFeature = preload("res://content/features/worker_feature.gd")
const ResidentFeature = preload("res://content/features/resident_feature.gd")
const STEP := 1.0 / 30.0
const WORKER := &"drop_review.worker"
const RESIDENT := &"drop_review.resident"
const EATER := &"drop_review.eater"
const LAIR := &"drop_review.lair"
const PEN := &"drop_review.pen"
const FOOD := &"drop_review.food"
const GOLD := Vector2i(9, 5)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_same_origin_now_occupied()
	_repeated_stacked_carriers()
	_other_owners_bed()
	_shared_food_service()
	_invalid_terrain_stays_invalid()
	for failure in _failures:
		push_error(failure)
	print("KEEPER DROP REVIEW: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture() -> Dictionary:
	var grid := DungeonGrid.new(12, 9)
	for y in range(1, 7):
		for x in range(1, 9):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(1, 3), DungeonGrid.Tile.HEART)
	grid.set_tile(GOLD, DungeonGrid.Tile.GOLD)
	var worker := CreatureDefinition.new()
	worker.id = WORKER
	worker.capabilities = [&"haul"]
	worker.move_speed = 6.0
	var resident := CreatureDefinition.new()
	resident.id = RESIDENT
	resident.capabilities = [&"rest"]
	resident.energy_drain_per_second = 0.0
	var eater := CreatureDefinition.new()
	eater.id = EATER
	eater.capabilities = [&"eat"]
	eater.initial_satiety = 0.2
	eater.hunger_drain_per_second = 0.0
	eater.eating_seconds = 0.5
	eater.move_speed = 6.0
	var lair := RoomDefinition.new()
	lair.id = LAIR
	lair.tags = [&"lair"]
	var treasury := RoomDefinition.new()
	treasury.id = &"drop_review.treasury"
	treasury.gold_storage_per_tile = 500
	var pen := RoomDefinition.new()
	pen.id = PEN
	pen.food_type = FOOD
	pen.food_capacity_per_tile = 4
	var food := FoodDefinition.new()
	food.id = FOOD
	food.nutrition_per_unit = 1.0
	var module := ContentModule.new()
	module.id = &"drop_review"
	module.definitions = [worker, resident, eater, lair, treasury, pen, food]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Shared drop scenario uses independent content definitions")
	var context := GameContext.new(grid, registry)
	context.rooms.place_initial(treasury.id, [Vector2i(2, 2)])
	var workers := WorkerFeature.new()
	workers.setup(context)
	var residents := ResidentFeature.new()
	residents.setup(context)
	return {"context": context, "workers": workers, "residents": residents, "conserved": true}


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.residents.tick(STEP)
		scene.workers.tick(STEP)
		var context: GameContext = scene.context
		context.simulation_ticked.emit(STEP)
		if context.economy.accounted_gold(context.actors) != context.economy.initial_gold + context.economy.gem_gold_created or context.food.accounted_units() != context.food.produced_units:
			scene.conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 30.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _finish(scene: Dictionary, label: String) -> void:
	_check(scene.conserved, "%s preserves food and gold through every resumed simulation tick" % label)
	scene.residents.free()
	scene.workers.free()


func _same_origin_now_occupied() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var origin := Vector2i(3, 3)
	var held := context.spawn_creature(WORKER, origin)
	var standing := context.spawn_creature(WORKER, Vector2i(4, 3))
	held.carried_gold = context.economy.mine(GOLD, 20)
	var held_id := held.id
	context.keeper.pickup(held.id)
	context.keeper.rename_selected("Muck the Carrier")
	standing.position = context.grid.cell_to_world(origin)
	_check(context.keeper.quote_drop(origin).valid, "A creature may be returned to its original floor after another creature occupies it")
	var result := context.keeper.drop(origin)
	_check(result.success and held.position == standing.position and not held.is_held and context.keeper.held_actor == null, "Shared-floor drop releases the exact original held creature")
	_check(held.id == held_id and held.custom_name == "Muck the Carrier" and held.carried_gold == 20 and context.actors.size() == 2, "Shared drop preserves instance identity, custom name and cargo")
	_check(not context.keeper.drop(origin).success and context.actors.size() == 2, "A stale second drop cannot duplicate a creature")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 20), "Shared-floor carrier resumes its real Treasury haul")
	_finish(scene, "Occupied pickup origin")


func _repeated_stacked_carriers() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var actors: Array[CreatureState] = []
	var originals: Dictionary[int, CreatureState] = {}
	var cargo: Dictionary[int, int] = {}
	for index in 3:
		var actor := context.spawn_creature(WORKER, Vector2i(3 + index, 3))
		actor.custom_name = "Carrier %d" % index
		actor.carried_gold = context.economy.mine(GOLD, (index + 1) * 20)
		actors.append(actor)
		originals[actor.id] = actor
		cargo[actor.id] = actor.carried_gold
	var shared := Vector2i(4, 4)
	var all_valid := true
	for cycle in 4:
		for actor in actors:
			all_valid = all_valid and context.keeper.pickup(actor.id)
			all_valid = all_valid and context.keeper.quote_drop(shared).valid
			var result := context.keeper.drop(shared)
			all_valid = all_valid and result.success and actor.position == context.grid.cell_to_world(shared)
	_check(all_valid, "Several creatures can repeatedly stack on the same valid floor without losing custody")
	var identities := context.actors.size() == 3
	for actor in context.actors:
		identities = identities and originals.get(actor.id) == actor and cargo.get(actor.id) == actor.carried_gold and not actor.is_held
	_check(identities and context.keeper.held_actor == null, "Repeated multi-creature drops retain every individual ID and cargo balance")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 120), "Stacked carriers independently reserve Treasury positions and deliver all cargo")
	_check(scene.workers.job_board.active_job_count() == 0 and context.actors.size() == 3, "Resumed stacked carriers leave no leaked jobs or duplicated actors")
	_finish(scene, "Repeated stacked carriers")


func _other_owners_bed() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var cell := Vector2i(6, 3)
	context.rooms.place_initial(LAIR, [cell])
	var owner := context.spawn_creature(RESIDENT, cell)
	var bed := context.beds.reserve(owner, context.registry.get_creature(RESIDENT))
	_check(context.beds.establish(owner), "Shared-bed fixture has a locally established personal owner")
	var carrier := context.spawn_creature(WORKER, Vector2i(4, 3))
	carrier.carried_gold = context.economy.mine(GOLD, 40)
	context.keeper.pickup(carrier.id)
	_check(context.keeper.quote_drop(cell).valid, "Another creature's established bed is valid shared floor for keeper dropping")
	_check(context.keeper.drop(cell).success and owner.position == carrier.position, "Drop onto occupied bed floor preserves both existing creature instances")
	_check(context.beds.get_bed(owner.id) == bed and bed.owner_id == owner.id and bed.established and context.beds.get_bed(carrier.id) == null, "Sharing bed floor never transfers or duplicates personal bed ownership")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 40), "Visitor resumes work after dropping on another owner's bed")
	_check(context.beds.get_bed(owner.id) == bed, "Original resident retains its home after visitor movement resumes")
	_finish(scene, "Another owner's bed floor")


func _shared_food_service() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var cell := Vector2i(6, 4)
	context.rooms.place_initial(PEN, [cell])
	context.food.produce(cell, FOOD, 3)
	var first := context.spawn_creature(EATER, Vector2i(2, 3))
	var second := context.spawn_creature(EATER, cell)
	var first_id := first.id
	var second_id := second.id
	context.keeper.pickup(first.id)
	_check(context.keeper.drop(cell).success and first.position == second.position, "Hungry creatures can share the same service floor after a drop")
	_check(_until(scene, func() -> bool: return first.satiety >= 0.9 and second.satiety >= 0.9), "Shared-floor eaters resume autonomous meals with exclusive feeding reservations")
	_check(first.id == first_id and second.id == second_id and first != second and context.actors.size() == 2, "Resumed shared meals preserve individual creature identities")
	_check(context.food.consumed_units == 2 and context.food.total_units == 1 and context.food.reservations.is_empty(), "Shared-floor meals consume separate exact food units without duplication or leaked reservations")
	_finish(scene, "Shared feeding floor")


func _invalid_terrain_stays_invalid() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	context.grid.set_tile(Vector2i(10, 7), DungeonGrid.Tile.FLOOR)
	context.grid.set_tile(Vector2i(8, 2), DungeonGrid.Tile.BEDROCK)
	context.grid.set_tile(Vector2i(7, 2), DungeonGrid.Tile.PORTAL)
	var actor := context.spawn_creature(WORKER, Vector2i(3, 3))
	actor.carried_gold = context.economy.mine(GOLD, 20)
	context.keeper.pickup(actor.id)
	var rejected := true
	for cell in [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 3), GOLD, Vector2i(8, 2), Vector2i(7, 2), Vector2i(10, 7)]:
		var quote := context.keeper.quote_drop(cell)
		var result := context.keeper.drop(cell)
		rejected = rejected and not quote.valid and not result.success and not quote.reason.is_empty() and context.keeper.held_actor == actor and actor.is_held and actor.carried_gold == 20
	_check(rejected, "Shared occupancy permission does not bypass bounds, rock/minerals, landmarks, bedrock or disconnected-floor protection")
	var shared := Vector2i(4, 3)
	context.spawn_creature(WORKER, shared)
	_check(context.keeper.drop(shared).success and context.actors.size() == 2, "After invalid attempts the same held actor can still be dropped on occupied valid floor")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 20), "Retained cargo survives invalid attempts and a later shared-floor drop")
	_finish(scene, "Invalid terrain and later shared drop")
