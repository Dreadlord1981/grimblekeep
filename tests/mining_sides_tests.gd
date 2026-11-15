extends SceneTree
## Shared-node jobs reserve cardinal faces, never overlapping workplaces.

const WorkerFeature = preload("res://content/features/worker_feature.gd")
const TARGET := Vector2i(4, 4)
const STEP := 1.0 / 30.0
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_four_sides_and_fifth_waiter()
	_test_blocked_side_and_diagonal_only()
	_test_stone_and_pile_exclusivity()
	_test_shared_workplace()
	_test_finite_gold_completion()
	_test_cancellation_and_removal()
	_test_concurrent_gem_mining()
	for failure in _failures:
		push_error(failure)
	print("MINING SIDES RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(kind: int = DungeonGrid.Tile.GOLD, workers: int = 5) -> Dictionary:
	var grid := DungeonGrid.new(9, 9)
	for y in range(1, 8):
		for x in range(1, 8):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(TARGET, kind)
	var registry := ContentRegistry.new()
	var definition := CreatureDefinition.new()
	definition.id = &"sides.worker"
	definition.display_name = "Side test worker"
	definition.capabilities = [&"excavate", &"haul"]
	definition.move_speed = 8.0
	definition.work_rate = 1.0
	var module := ContentModule.new()
	module.id = &"sides"
	module.definitions = [definition]
	_check(registry.register_module(module).is_empty(), "Mining-side fixture registers a worker")
	var context := GameContext.new(grid, registry)
	context.economy.treasury_cells = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 2)]
	var starts := [Vector2i(4, 2), Vector2i(6, 4), Vector2i(4, 6), Vector2i(2, 4), Vector2i(1, 1)]
	for index in workers:
		context.spawn_creature(definition.id, starts[index])
	var feature := WorkerFeature.new()
	feature.setup(context)
	context.mark_excavation([TARGET], GameContext.MarkOperation.ADD)
	return {"context": context, "feature": feature, "conserved": true}


func _slots(scene: Dictionary) -> Dictionary:
	return scene.feature.job_board.target_reservations.get(TARGET, {})


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.feature.tick(STEP)
		var economy: GoldEconomy = scene.context.economy
		if economy.accounted_gold(scene.context.actors) != economy.initial_gold + economy.gem_gold_created:
			scene.conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 60.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _finish(scene: Dictionary, description: String) -> void:
	_check(scene.conserved, "%s conserves gold at every tick" % description)
	scene.feature.free()


func _test_four_sides_and_fifth_waiter() -> void:
	var scene := _fixture()
	_advance(scene, STEP)
	var board: WorkerJobBoard = scene.feature.job_board
	var slots := _slots(scene)
	_check(slots.size() == 4 and board.active_job_count() == 4, "One gold node accepts four side assignments")
	_check(board.job_for(scene.context.actors[4].id) == null, "Fifth miner waits while all four sides are reserved")
	var workplaces: Dictionary[Vector2i, bool] = {}
	var all_cardinal := true
	var all_owned := true
	for actor_id in slots:
		var cell: Vector2i = slots[actor_id]
		workplaces[cell] = true
		var offset := cell - TARGET
		all_cardinal = all_cardinal and absi(offset.x) + absi(offset.y) == 1
		all_owned = all_owned and board.owns(actor_id, board.job_for(actor_id))
	_check(workplaces.size() == 4 and board.work_reservations.size() == 4, "All miners reserve different work cells")
	_check(all_cardinal and all_owned, "Shared reservations connect each owner to a cardinal face")
	_advance(scene, 0.35)
	var at_faces := true
	for actor_id in slots:
		var job: WorkerJob = board.job_for(actor_id)
		var actor: CreatureState = scene.feature.behaviors[actor_id].actor
		at_faces = at_faces and actor.position.is_equal_approx(scene.context.grid.cell_to_world(job.work_cell))
	_check(at_faces, "All four miners physically reach their reserved cardinal faces")
	var fake_job := WorkerJob.new(&"excavate", TARGET, Vector2i(4, 3))
	_check(not board.owns(scene.context.actors[0].id, fake_job), "A copied target/face does not confer ownership of another job")
	_finish(scene, "Four-side assignment")


func _test_blocked_side_and_diagonal_only() -> void:
	var scene := _fixture()
	scene.context.grid.set_tile(TARGET + Vector2i.LEFT, DungeonGrid.Tile.ROCK)
	_advance(scene, STEP)
	_check(_slots(scene).size() == 3, "One blocked side limits the node to three miners")
	_check(not scene.feature.job_board.work_reservations.has(TARGET + Vector2i.LEFT), "Blocked side cannot become a workplace")
	_finish(scene, "Blocked side")
	var isolated := _fixture()
	# The upper face is floor, but all four of its entrances are blocked.
	for cell in [Vector2i(3, 3), Vector2i(5, 3), Vector2i(4, 2)]:
		isolated.context.grid.set_tile(cell, DungeonGrid.Tile.ROCK)
	isolated.context.actors[0].position = isolated.context.grid.cell_to_world(Vector2i(1, 3))
	_advance(isolated, STEP)
	_check(_slots(isolated).size() == 3 and not isolated.feature.job_board.work_reservations.has(Vector2i(4, 3)), "An open but unreachable face does not admit a fourth miner")
	_finish(isolated, "Isolated open face")
	var diagonal := _fixture()
	for offset in WorkerJobBoard.DIRECTIONS:
		diagonal.context.grid.set_tile(TARGET + offset, DungeonGrid.Tile.ROCK)
	_advance(diagonal, 0.5)
	_check(diagonal.feature.job_board.active_job_count() == 0, "Diagonal travel never permits digging from a diagonal face")
	_check(diagonal.context.economy.remaining_gold[TARGET] == GoldEconomy.GOLD_PER_SEAM, "Unreachable cardinal faces yield no gold")
	_finish(diagonal, "Diagonal-only access")


func _test_stone_and_pile_exclusivity() -> void:
	var stone := _fixture(DungeonGrid.Tile.ROCK)
	_advance(stone, STEP)
	_check(_slots(stone).size() == 1 and stone.feature.job_board.active_job_count() == 1, "Stone excavation remains exclusive despite four open sides")
	_finish(stone, "Stone exclusivity")
	var pile := _fixture(DungeonGrid.Tile.GOLD)
	pile.context.clear_excavation_marks()
	var extracted: int = pile.context.economy.mine(TARGET, 60)
	var pile_cell := Vector2i(4, 3)
	pile.context.economy.drop_gold(pile_cell, extracted)
	_advance(pile, STEP)
	var pile_slots: Dictionary = pile.feature.job_board.target_reservations.get(pile_cell, {})
	_check(pile_slots.size() == 1 and pile.feature.job_board.active_job_count() == 1, "Loose-gold haul job remains exclusive")
	_finish(pile, "Pile exclusivity")


func _test_shared_workplace() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD, 2)
	var context: GameContext = scene.context
	context.clear_excavation_marks()
	for cell in context.grid.cells_of_type(DungeonGrid.Tile.FLOOR):
		context.grid.set_tile(cell, DungeonGrid.Tile.ROCK)
	for x in range(1, 4):
		context.grid.set_tile(Vector2i(x, 3), DungeonGrid.Tile.FLOOR)
	context.economy.treasury_cells = [Vector2i(1, 3)]
	context.grid.set_tile(Vector2i(4, 3), DungeonGrid.Tile.GOLD)
	context.grid.set_tile(Vector2i(3, 4), DungeonGrid.Tile.GOLD)
	context.actors[0].position = context.grid.cell_to_world(Vector2i(1, 3))
	context.actors[1].position = context.grid.cell_to_world(Vector2i(2, 3))
	context.mark_excavation([Vector2i(4, 3), Vector2i(3, 4)])
	_advance(scene, STEP)
	_check(scene.feature.job_board.active_job_count() == 1, "Different mining nodes cannot share one reserved workplace")
	_check(scene.feature.job_board.work_reservations.size() == 1, "Shared face retains exactly one worker")
	_finish(scene, "Shared workplace")


func _test_finite_gold_completion() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD, 4)
	var context: GameContext = scene.context
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == GoldEconomy.GOLD_PER_SEAM), "Four miners deposit exactly the finite node's 200 gold")
	_check(context.grid.get_tile(TARGET) == DungeonGrid.Tile.FLOOR, "Final mining stroke converts depleted gold to floor")
	_check(not context.excavation_marks.has(TARGET), "Depletion clears the mining mark")
	_advance(scene, 3.0)
	_check(context.economy.stored_gold == GoldEconomy.GOLD_PER_SEAM, "Other miners never award stale completion gold")
	_check(scene.feature.job_board.target_reservations.is_empty() and scene.feature.job_board.work_reservations.is_empty(), "Depletion releases all sides and completed haul reservations")
	_finish(scene, "Shared finite-gold completion")


func _test_cancellation_and_removal() -> void:
	var canceled := _fixture(DungeonGrid.Tile.GOLD, 4)
	_advance(canceled, STEP)
	canceled.context.clear_excavation_marks()
	_advance(canceled, 0.5)
	_check(canceled.feature.job_board.active_job_count() == 0 and canceled.feature.job_board.target_reservations.is_empty(), "Unmarking a shared node releases every mining job")
	_check(canceled.context.economy.remaining_gold[TARGET] == GoldEconomy.GOLD_PER_SEAM, "Canceled partial mining awards no gold")
	_finish(canceled, "Shared cancellation")
	var removed := _fixture(DungeonGrid.Tile.GOLD, 4)
	_advance(removed, STEP)
	var actor: CreatureState = removed.context.actors.pop_back()
	var removed_cell: Vector2i = _slots(removed)[actor.id]
	_advance(removed, STEP)
	var remaining_owned := true
	for live_actor in removed.context.actors:
		remaining_owned = remaining_owned and removed.feature.job_board.owns(live_actor.id, removed.feature.job_board.job_for(live_actor.id))
	_check(_slots(removed).size() == 3 and not _slots(removed).has(actor.id), "Removing one miner releases only its target slot")
	_check(not removed.feature.job_board.work_reservations.has(removed_cell) and remaining_owned, "Remaining miners retain ownership of their sides")
	var replacement: CreatureState = removed.context.spawn_creature(&"sides.worker", Vector2i(1, 1))
	_advance(removed, 0.3)
	_check(_slots(removed).size() == 4 and _slots(removed).get(replacement.id) == removed_cell, "Replacement miner claims the released side without displacing the others")
	_finish(removed, "Shared miner removal")


func _test_concurrent_gem_mining() -> void:
	var scene := _fixture(DungeonGrid.Tile.GEM, 4)
	_advance(scene, STEP)
	_check(_slots(scene).size() == 4, "Renewable gem node accepts four side miners")
	_advance(scene, 12.0)
	_check(scene.context.economy.gem_gold_created > GoldEconomy.GOLD_PER_SEAM, "Concurrent gem workers produce renewable gold")
	_check(scene.context.economy.stored_gold > 0, "Concurrent gem output reaches treasury physically")
	_check(scene.context.grid.get_tile(TARGET) == DungeonGrid.Tile.GEM and scene.context.excavation_marks.has(TARGET), "Concurrent mining retains gem node and mark")
	scene.context.clear_excavation_marks()
	_advance(scene, 30.0)
	_check(scene.feature.job_board.active_job_count() == 0, "Gem cancellation releases all miners after remaining cargo is deposited")
	_finish(scene, "Shared gem mining")
