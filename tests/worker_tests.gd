extends SceneTree
## Isolated worker scenarios verify outcomes and gold conservation at every tick.

const WorkerFeature = preload("res://content/features/worker_feature.gd")
const STEP := 1.0 / 30.0
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_excavation_chain()
	_test_finite_gold()
	_test_gems_and_rate()
	_test_cancellation()
	_test_cancel_with_cargo()
	_test_capabilities()
	_test_haul_only_worker()
	_test_reservations()
	_test_shared_workplace()
	_test_route_and_late_work()
	_test_missing_treasury()
	_test_removed_worker()
	_test_removed_worker_without_floor()
	_test_reinserted_worker()
	_test_capability_loss_before_removal()
	for failure in _failures:
		push_error(failure)
	print("WORKER RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(kind: int = DungeonGrid.Tile.ROCK, worker_count: int = 1,
		capabilities: Array[StringName] = [&"excavate", &"haul"], work_rate: float = 4.0) -> Dictionary:
	var grid := DungeonGrid.new(10, 7)
	for y in range(1, 6):
		for x in range(1, 6):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(6, 2), kind)
	var registry := ContentRegistry.new()
	var definition := CreatureDefinition.new()
	definition.id = &"test.worker"
	definition.display_name = "Test worker"
	definition.move_speed = 8.0
	definition.work_rate = work_rate
	definition.capabilities = capabilities
	var module := ContentModule.new()
	module.id = &"test.workers"
	module.definitions = [definition]
	_check(registry.register_module(module).is_empty(), "Test worker definition registers")
	var context := GameContext.new(grid, registry)
	context.economy.treasury_cells = [Vector2i(1, 2)]
	for i in worker_count:
		context.spawn_creature(definition.id, Vector2i(2 + i, 2))
	var feature := WorkerFeature.new()
	feature.setup(context)
	return {"context": context, "feature": feature, "conserved": true}


func _advance(scene: Dictionary, seconds: float) -> void:
	for i in ceili(seconds / STEP):
		scene.feature.tick(STEP)
		var economy: GoldEconomy = scene.context.economy
		if economy.accounted_gold(scene.context.actors) != economy.initial_gold + economy.gem_gold_created:
			scene.conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 30.0) -> bool:
	for i in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _finish(scene: Dictionary, name: String) -> void:
	_check(scene.conserved, "%s preserves gold accounting at every tick" % name)
	scene.feature.free()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _test_excavation_chain() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2)])
	_check(_until(scene, func() -> bool: return context.grid.is_walkable(Vector2i(8, 2))), "Worker digs accessible stone then discovers buried marked chain")
	_check(context.excavation_marks.is_empty(), "Completed excavation clears marks")
	_advance(scene, 1.0)
	_check(scene.feature.job_board.active_job_count() == 0, "Finished dig chain releases jobs")
	_check(context.actors[0].action == &"idle", "Worker idles after last job")
	_finish(scene, "Dig chain")


func _test_finite_gold() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD)
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	var seen_cargo := false
	var cargo_within_capacity := true
	for i in 1200:
		_advance(scene, STEP)
		seen_cargo = seen_cargo or context.actors[0].carried_gold > 0
		cargo_within_capacity = cargo_within_capacity and context.actors[0].carried_gold <= 60
		if context.economy.stored_gold == GoldEconomy.GOLD_PER_SEAM:
			break
	_check(seen_cargo, "Finite gold travels as worker cargo")
	_check(cargo_within_capacity, "Worker never exceeds cargo capacity")
	_check(context.economy.stored_gold == GoldEconomy.GOLD_PER_SEAM, "Finite seam ends entirely in treasury")
	_check(context.grid.is_walkable(Vector2i(6, 2)), "Depleted finite gold becomes floor")
	_check(context.excavation_marks.is_empty(), "Depleted gold mark is removed")
	var stored := context.economy.stored_gold
	_advance(scene, 5.0)
	_check(context.economy.stored_gold == stored, "Depleted seam never awards duplicate gold")
	_finish(scene, "Finite mining")


func _test_gems_and_rate() -> void:
	var gold_scene := _fixture(DungeonGrid.Tile.GOLD, 1, [&"excavate", &"haul"], 1.0)
	var gem_scene := _fixture(DungeonGrid.Tile.GEM, 1, [&"excavate", &"haul"], 1.0)
	var gold_context: GameContext = gold_scene.context
	var gem_context: GameContext = gem_scene.context
	gold_context.mark_excavation([Vector2i(6, 2)])
	gem_context.mark_excavation([Vector2i(6, 2)])
	# Both must walk the same route. Before the first gem strike, gold works faster.
	_advance(gold_scene, 2.8)
	_advance(gem_scene, 2.8)
	var extracted_gold: int = GoldEconomy.GOLD_PER_SEAM - gold_scene.context.economy.remaining_gold.get(Vector2i(6, 2), 0)
	_check(extracted_gold > gem_scene.context.economy.gem_gold_created, "Gem mining is slower than finite gold mining")
	_advance(gem_scene, 40.0)
	_check(gem_scene.context.economy.gem_gold_created > GoldEconomy.GOLD_PER_SEAM, "Gem seam can create more than one finite seam's yield")
	_check(gem_scene.context.grid.get_tile(Vector2i(6, 2)) == DungeonGrid.Tile.GEM, "Gem seam remains solid after mining")
	_check(gem_scene.context.excavation_marks.has(Vector2i(6, 2)), "Gem excavation mark persists")
	_check(gem_scene.context.economy.stored_gold > 0, "Gem output is physically hauled and deposited")
	_finish(gold_scene, "Gold rate sample")
	_finish(gem_scene, "Infinite gem mining")


func _test_cancellation() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD)
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	_check(_until(scene, func() -> bool: return context.actors[0].action == &"mining"), "Worker begins a mining action")
	context.clear_excavation_marks()
	var remaining: int = context.economy.remaining_gold[Vector2i(6, 2)]
	_advance(scene, 3.0)
	_check(context.economy.remaining_gold[Vector2i(6, 2)] == remaining, "Unmark cancels work before any further strike")
	_check(scene.feature.job_board.active_job_count() == 0, "Cancellation releases job")
	_check(scene.feature.job_board.target_reservations.is_empty() and scene.feature.job_board.work_reservations.is_empty(), "Cancellation releases target and workplace reservations")
	_finish(scene, "Canceled mining")


func _test_capabilities() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD, 1, [])
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	_advance(scene, 10.0)
	_check(scene.context.economy.remaining_gold[Vector2i(6, 2)] == GoldEconomy.GOLD_PER_SEAM, "Creature without excavation capability cannot mine")
	_check(scene.feature.behaviors.is_empty(), "Nonworker does not receive worker behavior")
	_finish(scene, "Capability exclusion")


func _test_cancel_with_cargo() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD)
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	_check(_until(scene, func() -> bool: return context.actors[0].carried_gold > 0), "Mining produces cargo before cancel")
	var mined: int = GoldEconomy.GOLD_PER_SEAM - context.economy.remaining_gold[Vector2i(6, 2)]
	context.clear_excavation_marks()
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == mined), "Cancellation keeps already earned cargo and delivers it")
	_advance(scene, 2.0)
	_check(context.economy.remaining_gold[Vector2i(6, 2)] == GoldEconomy.GOLD_PER_SEAM - mined, "Canceled miner never extracts another strike while delivering cargo")
	_finish(scene, "Cancel with cargo")


func _test_haul_only_worker() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD, 1, [&"haul"])
	var context: GameContext = scene.context
	var extracted := context.economy.mine(Vector2i(6, 2), 60)
	context.economy.drop_gold(Vector2i(3, 3), extracted)
	context.mark_excavation([Vector2i(6, 2)])
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == extracted), "Haul-only creature collects loose gold and deposits it")
	_advance(scene, 2.0)
	_check(context.economy.remaining_gold[Vector2i(6, 2)] == GoldEconomy.GOLD_PER_SEAM - extracted, "Haul-only creature never mines marked seam")
	_finish(scene, "Haul-only capability")


func _test_reservations() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD, 3)
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	_advance(scene, STEP)
	_check(scene.feature.job_board.target_reservations.size() == 1, "Three workers reserve one mining target once")
	_check(scene.feature.job_board.active_job_count() == 1, "Only one worker assigned to single seam")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == GoldEconomy.GOLD_PER_SEAM), "Multiple workers complete finite seam without duplicate rewards")
	_advance(scene, 1.0)
	_check(scene.feature.job_board.work_reservations.is_empty(), "Shared mining/deposit contention eventually releases workplace reservations")
	_finish(scene, "Multiworker contention")


func _test_route_and_late_work() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	# Disconnect the chamber from the only target-adjacent work cell.
	for y in range(1, 6):
		context.grid.set_tile(Vector2i(4, y), DungeonGrid.Tile.ROCK)
	context.mark_excavation([Vector2i(6, 2)])
	_advance(scene, 2.0)
	_check(scene.feature.job_board.active_job_count() == 0, "Unreachable marked target receives no reservation")
	context.grid.set_tile(Vector2i(4, 2), DungeonGrid.Tile.FLOOR)
	_check(_until(scene, func() -> bool: return context.grid.is_walkable(Vector2i(6, 2))), "Previously unreachable mark becomes workable after route opens")
	context.grid.set_tile(Vector2i(6, 3), DungeonGrid.Tile.FLOOR)
	context.mark_excavation([Vector2i(6, 4)])
	_check(_until(scene, func() -> bool: return scene.feature.job_board.job_for(context.actors[0].id) != null), "Worker reserves next target before route changes")
	var job: WorkerJob = scene.feature.job_board.job_for(context.actors[0].id)
	if job != null:
		context.grid.set_tile(job.work_cell, DungeonGrid.Tile.ROCK)
	_check(_until(scene, func() -> bool: return context.grid.is_walkable(Vector2i(6, 4))), "Worker recovers from a blocked workplace through another adjacent cell")
	context.clear_excavation_marks()
	_advance(scene, 1.0)
	_finish(scene, "Route changes")


func _test_shared_workplace() -> void:
	var scene := _fixture(DungeonGrid.Tile.ROCK, 2)
	var context: GameContext = scene.context
	var corridor: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)]
	for cell in context.grid.cells_of_type(DungeonGrid.Tile.FLOOR):
		if cell not in corridor:
			context.grid.set_tile(cell, DungeonGrid.Tile.ROCK)
	context.grid.set_tile(Vector2i(4, 3), DungeonGrid.Tile.GOLD)
	context.grid.set_tile(Vector2i(3, 4), DungeonGrid.Tile.GOLD)
	context.mark_excavation([Vector2i(4, 3), Vector2i(3, 4)])
	_advance(scene, STEP)
	_check(scene.feature.job_board.active_job_count() == 1, "Different targets sharing one work cell do not assign overlapping workers")
	_check(scene.feature.job_board.work_reservations.size() == 1, "Shared work cell has one reservation")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 2 * GoldEconomy.GOLD_PER_SEAM, 60.0), "Workers eventually process both targets sharing a workplace")
	_finish(scene, "Shared workplace")


func _test_missing_treasury() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD)
	var context: GameContext = scene.context
	context.economy.treasury_cells.clear()
	context.mark_excavation([Vector2i(6, 2)])
	_check(_until(scene, func() -> bool: return context.grid.is_walkable(Vector2i(6, 2))), "Worker can finish mining when treasury is absent")
	_advance(scene, 2.0)
	_check(not context.economy.ground_gold.is_empty(), "No treasury leaves visible loose gold")
	_check(context.economy.stored_gold == 0, "No treasury never grants spendable gold")
	_check(scene.feature.job_board.active_job_count() == 0, "Missing storage does not cause endless pickup/drop jobs")
	context.economy.treasury_cells = [Vector2i(1, 2)]
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == GoldEconomy.GOLD_PER_SEAM), "Returning treasury triggers collection and deposit of loose gold")
	_finish(scene, "Missing/reappearing treasury")


func _test_removed_worker() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD)
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	_check(_until(scene, func() -> bool: return context.actors[0].carried_gold > 0), "Worker holds real mined cargo before removal")
	var removed: CreatureState = context.actors.pop_back()
	var cargo := removed.carried_gold
	_advance(scene, STEP)
	_check(cargo > 0 and removed.carried_gold == 0, "Removing worker transfers cargo into world state")
	_check(not context.economy.ground_gold.is_empty(), "Removed worker cargo survives in loose pile")
	_check(scene.feature.job_board.active_job_count() == 0, "Removed worker releases reserved job")
	context.spawn_creature(&"test.worker", Vector2i(2, 2))
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == GoldEconomy.GOLD_PER_SEAM), "Replacement worker collects cargo and completes remaining seam")
	_finish(scene, "Removed/replaced worker")


func _test_removed_worker_without_floor() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD)
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	_check(_until(scene, func() -> bool: return context.actors[0].carried_gold > 0), "Worker obtains cargo before no-floor removal")
	var removed: CreatureState = context.actors.pop_back()
	for cell in context.grid.cells_of_type(DungeonGrid.Tile.FLOOR):
		context.grid.set_tile(cell, DungeonGrid.Tile.ROCK)
	_advance(scene, 1.0)
	_check(context.economy.accounted_gold(context.actors) == context.economy.initial_gold, "Removed cargo remains accounted while no safe floor exists")
	_check(context.economy.ground_gold.is_empty(), "Cargo is not dropped into solid rock")
	scene.feature.free()
	scene.feature = WorkerFeature.new()
	scene.feature.setup(context)
	_advance(scene, 0.5)
	_check(scene.feature.orphaned_cargo.size() == 1 and context.economy.pending_gold() > 0, "Feature reload adopts authoritative pending cargo without losing gold")
	context.grid.set_tile(Vector2i(1, 2), DungeonGrid.Tile.FLOOR)
	_check(_until(scene, func() -> bool: return not context.economy.ground_gold.is_empty(), 2.0), "Cargo recovers when a safe floor returns")
	_check(removed.carried_gold == 0 and scene.feature.orphaned_cargo.is_empty(), "Successful delayed recovery clears pending worker cargo")
	_finish(scene, "No-floor removal recovery")


func _test_reinserted_worker() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD)
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	_check(_until(scene, func() -> bool: return context.actors[0].carried_gold > 0), "Worker obtains cargo before reinsertion scenario")
	var removed: CreatureState = context.actors.pop_back()
	var cargo := removed.carried_gold
	for cell in context.grid.cells_of_type(DungeonGrid.Tile.FLOOR):
		context.grid.set_tile(cell, DungeonGrid.Tile.ROCK)
	_advance(scene, 0.5)
	context.actors.append(removed)
	for x in range(1, 6):
		context.grid.set_tile(Vector2i(x, 2), DungeonGrid.Tile.FLOOR)
	_check(_until(scene, func() -> bool: return context.economy.pending_cargo.is_empty(), 2.0), "Reinserting actor removes duplicate pending recovery ownership")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold >= cargo), "Reinserted worker delivers retained cargo normally")
	_finish(scene, "Reinserted worker")


func _test_capability_loss_before_removal() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD)
	var context: GameContext = scene.context
	context.mark_excavation([Vector2i(6, 2)])
	_check(_until(scene, func() -> bool: return context.actors[0].carried_gold > 0), "Worker obtains cargo before losing work capability")
	var actor := context.actors[0]
	for cell in context.grid.cells_of_type(DungeonGrid.Tile.FLOOR):
		context.grid.set_tile(cell, DungeonGrid.Tile.ROCK)
	context.registry.get_creature(actor.definition_id).capabilities.clear()
	_advance(scene, 0.5)
	_check(actor.carried_gold > 0 and scene.feature.behaviors.has(actor.id), "Capability loss keeps tracking cargo that cannot safely drop")
	context.actors.clear()
	_advance(scene, 0.5)
	_check(context.economy.pending_cargo.has(actor.id), "Later actor removal transfers tracked cargo to recovery ledger")
	context.grid.set_tile(Vector2i(1, 2), DungeonGrid.Tile.FLOOR)
	_check(_until(scene, func() -> bool: return not context.economy.ground_gold.is_empty(), 2.0), "Former worker cargo recovers after floor returns")
	_finish(scene, "Capability loss before removal")
