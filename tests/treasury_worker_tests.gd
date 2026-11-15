extends SceneTree
## Worker-facing physical storage scenarios, including capacity and interruptions.

const WorkerFeature = preload("res://content/features/worker_feature.gd")
const STEP := 1.0 / 30.0
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_partial_deposit_and_full_storage()
	_test_storage_distribution()
	_test_legacy_storage_distance()
	_test_concurrent_storage()
	_test_removed_treasury_during_delivery()
	for failure in _failures:
		push_error(failure)
	print("TREASURY WORKER RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(capabilities: Array[StringName] = [&"haul"], workers: int = 1) -> Dictionary:
	var grid := DungeonGrid.new(9, 7)
	for y in range(1, 5):
		for x in range(1, 6):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	var registry := ContentRegistry.new()
	var definition := CreatureDefinition.new()
	definition.id = &"treasury.worker"
	definition.display_name = "Treasury test worker"
	definition.capabilities = capabilities
	definition.move_speed = 8.0
	var module := ContentModule.new()
	module.id = &"treasury.workers"
	module.definitions = [definition]
	_check(registry.register_module(module).is_empty(), "Treasury fixture registers its capability-driven worker")
	var context := GameContext.new(grid, registry)
	for index in workers:
		context.spawn_creature(definition.id, Vector2i(2 + index, 2))
	var feature := WorkerFeature.new()
	feature.setup(context)
	return {"context": context, "feature": feature, "definition": definition, "conserved": true}


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.feature.tick(STEP)
		var economy: GoldEconomy = scene.context.economy
		if economy.accounted_gold(scene.context.actors) != economy.initial_gold + economy.gem_gold_created:
			scene.conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 40.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _finish(scene: Dictionary, description: String) -> void:
	_check(scene.conserved, "%s conserves gold at every simulation tick" % description)
	scene.feature.free()


func _give_cargo(scene: Dictionary, actor_index: int, amount: int) -> void:
	# This fixture starts with external cargo rather than running a mining setup.
	scene.context.actors[actor_index].carried_gold += amount
	scene.context.economy.initial_gold += amount


func _test_partial_deposit_and_full_storage() -> void:
	var scene := _fixture([&"haul"])
	var context: GameContext = scene.context
	var economy := context.economy
	economy.configure_treasury({Vector2i(1, 2): 25})
	_give_cargo(scene, 0, 60)
	_check(_until(scene, func() -> bool: return economy.stored_gold == 25 and context.actors[0].carried_gold == 0), "Worker deposits only free tile capacity and safely drops overflow")
	_check(economy.stored_by_cell.get(Vector2i(1, 2), 0) == 25, "Partial transfer is attributed to the actual Treasury tile")
	_check(economy.ground_gold.get(Vector2i(1, 2), 0) == 35, "Capacity overflow remains physical and recoverable")
	_advance(scene, 3.0)
	_check(context.actors[0].carried_gold == 0 and scene.feature.job_board.active_job_count() == 0, "Full treasury does not cause a repeated pickup/drop loop")
	_check(economy.ground_gold.get(Vector2i(1, 2), 0) == 35, "Idle full-storage workers leave loose gold unchanged")
	economy.configure_treasury({Vector2i(1, 2): 25, Vector2i(4, 2): 50})
	_check(_until(scene, func() -> bool: return economy.stored_gold == 60), "Added storage causes loose overflow to be collected automatically")
	_check(economy.stored_by_cell.get(Vector2i(4, 2), 0) == 35 and economy.ground_gold.is_empty(), "Recovered gold physically enters the newly available tile")
	_finish(scene, "Partial deposit and expansion")


func _test_storage_distribution() -> void:
	var scene := _fixture([&"haul"])
	var context: GameContext = scene.context
	var economy := context.economy
	var near := Vector2i(1, 2)
	var far := Vector2i(5, 4)
	economy.configure_treasury({near: 100, far: 100})
	_give_cargo(scene, 0, 60)
	_check(_until(scene, func() -> bool: return economy.stored_gold == 60), "Worker completes first physical storage delivery")
	_check(economy.stored_by_cell.get(near, 0) == 60, "Equal empty storage chooses the nearest weighted route")
	_give_cargo(scene, 0, 60)
	_check(_until(scene, func() -> bool: return economy.stored_gold == 120), "Worker completes second physical storage delivery")
	_check(economy.stored_by_cell.get(far, 0) == 60, "Less-filled storage takes priority so gold spreads across the room")
	_give_cargo(scene, 0, 60)
	_check(_until(scene, func() -> bool: return economy.stored_gold == 180), "Cargo exceeding one tile's free capacity reaches a second tile")
	var tile_limits := true
	for cell in economy.stored_by_cell:
		tile_limits = tile_limits and economy.stored_by_cell[cell] <= economy.storage_capacity(cell)
	_check(tile_limits and economy.stored_by_cell.get(near, 0) > 0 and economy.stored_by_cell.get(far, 0) > 0, "Physical storage remains distributed within each tile's capacity")
	_finish(scene, "Per-tile distribution")


func _test_removed_treasury_during_delivery() -> void:
	var scene := _fixture([&"haul"])
	var context: GameContext = scene.context
	var economy := context.economy
	economy.configure_treasury({Vector2i(5, 4): 500})
	_give_cargo(scene, 0, 60)
	_advance(scene, STEP)
	var board: WorkerJobBoard = scene.feature.job_board
	_check(board.job_for(context.actors[0].id) != null, "Worker reserves a delivery before Treasury removal")
	economy.configure_treasury({})
	_advance(scene, 2.0)
	_check(economy.stored_gold == 0 and context.actors[0].carried_gold == 0, "Removed destination never receives a stale deposit")
	var loose := 0
	for amount in economy.ground_gold.values():
		loose += amount
	_check(loose == 60 and board.active_job_count() == 0, "Removed Treasury releases delivery and preserves all cargo as loose gold")
	_finish(scene, "Treasury removal during haul")


func _test_concurrent_storage() -> void:
	var scene := _fixture([&"haul"], 3)
	var context: GameContext = scene.context
	var economy := context.economy
	economy.configure_treasury({Vector2i(1, 2): 50, Vector2i(5, 4): 50})
	for index in context.actors.size():
		_give_cargo(scene, index, 60)
	_advance(scene, STEP)
	var board: WorkerJobBoard = scene.feature.job_board
	_check(board.active_job_count() == 2 and board.work_reservations.size() == 2, "Concurrent carriers reserve separate storage tiles and a third waits")
	_check(_until(scene, func() -> bool:
		for actor in context.actors:
			if actor.carried_gold > 0:
				return false
		return economy.stored_gold == 100), "Concurrent deliveries fill exactly the available physical storage")
	_check(economy.stored_by_cell.get(Vector2i(1, 2), 0) == 50 and economy.stored_by_cell.get(Vector2i(5, 4), 0) == 50, "Neither concurrently filled tile exceeds its own capacity")
	var loose := 0
	for amount in economy.ground_gold.values():
		loose += amount
	_check(loose == 80, "All concurrent overflow remains recoverable without duplicated cargo")
	_advance(scene, 2.0)
	_check(board.active_job_count() == 0, "Full concurrent storage leaves no leaked worker reservations")
	_finish(scene, "Concurrent finite storage")


func _test_legacy_storage_distance() -> void:
	var scene := _fixture([&"haul"])
	var context: GameContext = scene.context
	var near := Vector2i(1, 2)
	context.economy.treasury_cells = [near, Vector2i(5, 4)]
	context.economy.deposit(near, 20)
	context.economy.initial_gold += 20
	_give_cargo(scene, 0, 20)
	var job: WorkerJob = scene.feature.job_board.assign(context.actors[0], scene.definition)
	_check(job != null and job.target_cell == near, "Legacy unlimited storage preserves nearest-route selection despite existing stock")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 40), "Legacy storage still accepts the full physical cargo transfer")
	_finish(scene, "Legacy storage routing")
