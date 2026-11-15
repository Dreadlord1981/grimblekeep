extends SceneTree
## Independent navigation checks: reference Dijkstra never calls production A*.

const STEP := 1.0 / 30.0
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_open_routes()
	_test_diagonal_flanks()
	_test_endpoints_and_cache()
	_test_world_speed()
	_test_flank_change_while_walking()
	_test_cardinal_workplaces()
	_test_weighted_work_choice()
	_test_seeded_maps()
	for failure in _failures:
		push_error(failure)
	print("PATHFINDING RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _open_grid(width: int, height: int) -> DungeonGrid:
	var grid := DungeonGrid.new(width, height)
	for y in height:
		for x in width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	return grid


func _test_open_routes() -> void:
	var grid := _open_grid(8, 8)
	var path := GridPathfinder.find_path(grid, Vector2i(1, 1), Vector2i(6, 6))
	_check(path.size() == 6, "Open diagonal needs five diagonal moves, not ten cardinal moves")
	_check(absf(GridPathfinder.path_cost(path) - 5.0 * sqrt(2.0)) < 0.0001, "Open diagonal uses Euclidean edge costs")
	var mixed := GridPathfinder.find_path(grid, Vector2i(0, 0), Vector2i(6, 3))
	_check(absf(GridPathfinder.path_cost(mixed) - (3.0 + 3.0 * sqrt(2.0))) < 0.0001, "Open mixed route has exact octile cost")
	_check(_valid_path(grid, mixed), "Open route consists only of legal adjacent steps")
	_check(not GridPathfinder.can_step(grid, Vector2i(0, 0), Vector2i(2, 0)), "A single step cannot skip a tile")


func _test_diagonal_flanks() -> void:
	for delta in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var grid := _open_grid(5, 5)
		var start := Vector2i(2, 2)
		var goal: Vector2i = start + delta
		var horizontal: Vector2i = start + Vector2i(delta.x, 0)
		var vertical: Vector2i = start + Vector2i(0, delta.y)
		_check(GridPathfinder.can_step(grid, start, goal), "Clear diagonal allowed %s" % delta)
		grid.set_tile(horizontal, DungeonGrid.Tile.ROCK)
		_check(not GridPathfinder.can_step(grid, start, goal), "Horizontal flank blocks diagonal %s" % delta)
		var one_flank := GridPathfinder.find_path(grid, start, goal)
		_check(one_flank.size() == 3 and _valid_path(grid, one_flank), "One blocked flank routes around corner %s" % delta)
		grid.set_tile(vertical, DungeonGrid.Tile.ROCK)
		_check(not GridPathfinder.can_step(grid, start, goal), "Both flanks block diagonal %s" % delta)
		var both_flanks := GridPathfinder.find_path(grid, start, goal)
		_check(not both_flanks.is_empty() and _valid_path(grid, both_flanks), "Both flanks require a legal larger detour %s" % delta)
		grid.set_tile(horizontal, DungeonGrid.Tile.FLOOR)
		_check(not GridPathfinder.can_step(grid, start, goal), "Vertical-only flank blocks diagonal %s" % delta)
		grid.set_tile(vertical, DungeonGrid.Tile.FLOOR)
		var reopened := GridPathfinder.find_path(grid, start, goal)
		_check(reopened.size() == 2 and is_equal_approx(GridPathfinder.path_cost(reopened), sqrt(2.0)), "Opening flank-only changes restores diagonal %s" % delta)


func _test_endpoints_and_cache() -> void:
	var grid := _open_grid(5, 5)
	var start := Vector2i(1, 1)
	var goal := Vector2i(3, 3)
	_check(GridPathfinder.find_path(grid, start, start) == [start], "Same walkable start/goal returns one point")
	_check(GridPathfinder.can_step(grid, start, start), "Standing on same floor cell is legal")
	_check(GridPathfinder.find_path(grid, Vector2i(-1, 0), goal).is_empty(), "Off-map start rejected")
	_check(GridPathfinder.find_path(grid, start, Vector2i(5, 5)).is_empty(), "Off-map goal rejected")
	grid.set_tile(start, DungeonGrid.Tile.ROCK)
	_check(GridPathfinder.find_path(grid, start, goal).is_empty(), "Solid start rejected")
	_check(GridPathfinder.find_path(grid, start, start).is_empty(), "Same solid start/goal rejected")
	grid.set_tile(start, DungeonGrid.Tile.FLOOR)
	grid.set_tile(goal, DungeonGrid.Tile.GOLD)
	_check(GridPathfinder.find_path(grid, start, goal).is_empty(), "Gold is not walkable")
	grid.set_tile(goal, DungeonGrid.Tile.GEM)
	_check(GridPathfinder.find_path(grid, start, goal).is_empty(), "Gems are not walkable")
	grid.set_tile(goal, DungeonGrid.Tile.FLOOR)
	var original := GridPathfinder.find_path(grid, start, goal)
	for y in grid.height:
		grid.set_tile(Vector2i(2, y), DungeonGrid.Tile.ROCK)
	_check(GridPathfinder.find_path(grid, start, goal).is_empty(), "Closed separating wall invalidates cached route")
	grid.set_tile(Vector2i(2, 3), DungeonGrid.Tile.FLOOR)
	var reopened := GridPathfinder.find_path(grid, start, goal)
	_check(not reopened.is_empty() and _valid_path(grid, reopened), "Opening wall invalidates cached no-route result")
	_check(GridPathfinder.path_cost(reopened) > GridPathfinder.path_cost(original), "Reopened narrow route respects blocked flanks")
	# A cache from a different map must never supply paths for this map.
	var second := DungeonGrid.new(5, 5)
	second.set_tile(start, DungeonGrid.Tile.FLOOR)
	second.set_tile(goal, DungeonGrid.Tile.FLOOR)
	_check(GridPathfinder.find_path(second, start, goal).is_empty(), "Same-size distinct grid has independent cached navigation")
	_check(not GridPathfinder.find_path(grid, start, goal).is_empty(), "Switching maps does not damage earlier map routes")


func _worker_context(grid: DungeonGrid, start: Vector2i, treasury: Vector2i) -> Dictionary:
	var registry := ContentRegistry.new()
	var definition := CreatureDefinition.new()
	definition.id = &"test.navigator"
	definition.capabilities = [&"excavate", &"haul"]
	definition.move_speed = 2.0
	var module := ContentModule.new()
	module.id = &"test.navigation"
	module.definitions = [definition]
	_check(registry.register_module(module).is_empty(), "Navigation test definition registers")
	var context := GameContext.new(grid, registry)
	context.economy.treasury_cells = [treasury]
	var actor := context.spawn_creature(definition.id, start)
	actor.carried_gold = 1
	var board := WorkerJobBoard.new(context)
	var behavior := WorkerBehavior.new(context, board, actor)
	return {"context": context, "actor": actor, "definition": definition, "board": board, "behavior": behavior}


func _test_world_speed() -> void:
	for goal in [Vector2i(7, 1), Vector2i(7, 7)]:
		var scene := _worker_context(_open_grid(9, 9), Vector2i(1, 1), goal)
		var actor: CreatureState = scene.actor
		var start := actor.position
		for i in 4:
			scene.behavior.tick(0.25, scene.definition)
		_check(absf(actor.position.distance_to(start) - 2.0) < 0.001, "Movement is two world units per second for route %s" % goal)
		if goal.y == 7:
			_check(actor.position.x > start.x and actor.position.z > start.z, "Worker actually uses diagonal movement")
		scene.behavior.cancel()


func _test_flank_change_while_walking() -> void:
	# Exercise both sides of the rounded-cell midpoint while still on the edge.
	for initial_seconds in [0.25, 0.9]:
		var grid := _open_grid(6, 6)
		var scene := _worker_context(grid, Vector2i(1, 1), Vector2i(4, 4))
		var behavior: WorkerBehavior = scene.behavior
		var actor: CreatureState = scene.actor
		behavior.tick(initial_seconds, scene.definition)
		_check(behavior.job != null and actor.position.x > 2.0 and actor.position.z > 2.0, "Worker begins a diagonal path (%.2fs)" % initial_seconds)
		# Change only a diagonal flank, leaving every planned waypoint walkable.
		grid.set_tile(Vector2i(2, 1), DungeonGrid.Tile.ROCK)
		behavior.tick(STEP, scene.definition)
		_check(behavior.job == null or _valid_path(grid, behavior.job.path), "Changed diagonal flank forces legal route replan (%.2fs)" % initial_seconds)
		var reached := false
		for i in 600:
			behavior.tick(STEP, scene.definition)
			if scene.context.economy.stored_gold == 1:
				reached = true
				break
		_check(reached, "Worker completes deposit after a flank-only route change (%.2fs)" % initial_seconds)
		behavior.cancel()


func _test_cardinal_workplaces() -> void:
	var grid := _open_grid(7, 7)
	var target := Vector2i(4, 4)
	grid.set_tile(target, DungeonGrid.Tile.ROCK)
	var scene := _worker_context(grid, Vector2i(1, 1), Vector2i(0, 0))
	var actor: CreatureState = scene.actor
	actor.carried_gold = 0
	var context: GameContext = scene.context
	context.mark_excavation([target])
	var job: WorkerJob = scene.board.assign(actor, scene.definition)
	_check(job != null, "Reachable mine assignment still available")
	if job != null:
		var offset := job.work_cell - target
		_check(absi(offset.x) + absi(offset.y) == 1, "Mining workplace remains cardinal-adjacent despite diagonal navigation")
	scene.board.release(actor.id)


func _test_seeded_maps() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 571912
	for map_index in 16:
		var grid := DungeonGrid.new(7, 7)
		for y in grid.height:
			for x in grid.width:
				if random.randf() > 0.28:
					grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
		for sample in 5:
			var start := Vector2i(random.randi_range(0, 6), random.randi_range(0, 6))
			var goal := Vector2i(random.randi_range(0, 6), random.randi_range(0, 6))
			grid.set_tile(start, DungeonGrid.Tile.FLOOR)
			grid.set_tile(goal, DungeonGrid.Tile.FLOOR)
			var reference := _dijkstra_cost(grid, start, goal)
			var path := GridPathfinder.find_path(grid, start, goal)
			var label := "map %d sample %d" % [map_index, sample]
			if is_inf(reference):
				_check(path.is_empty(), "A* and independent Dijkstra agree no route: %s" % label)
			else:
				_check(not path.is_empty() and path.front() == start and path.back() == goal, "A* returns correct endpoints: %s" % label)
				_check(_valid_path(grid, path), "Every returned edge obeys no-corner rule: %s" % label)
				_check(absf(GridPathfinder.path_cost(path) - reference) < 0.0001, "A* matches independent shortest cost: %s" % label)
			_check(path == GridPathfinder.find_path(grid, start, goal), "Repeated unchanged query is deterministic: %s" % label)


func _test_weighted_work_choice() -> void:
	var grid := _open_grid(10, 10)
	var scene := _worker_context(grid, Vector2i(1, 1), Vector2i(4, 4))
	var context: GameContext = scene.context
	var actor: CreatureState = scene.actor
	var board: WorkerJobBoard = scene.board
	# Diagonal route has fewer nodes but greater travel distance than cardinal.
	context.economy.treasury_cells = [Vector2i(4, 4), Vector2i(5, 1)]
	var deposit := board.assign(actor, scene.definition)
	_check(deposit != null and deposit.target_cell == Vector2i(5, 1), "Treasury choice compares weighted route length, not waypoint count")
	board.release(actor.id)
	actor.carried_gold = 0
	context.economy.ground_gold[Vector2i(4, 4)] = 20
	context.economy.ground_gold[Vector2i(5, 1)] = 20
	var haul := board.assign(actor, scene.definition)
	_check(haul != null and haul.target_cell == Vector2i(5, 1), "Loose-gold choice compares weighted route length, not waypoint count")
	board.release(actor.id)
	context.economy.ground_gold.clear()
	grid.set_tile(Vector2i(5, 5), DungeonGrid.Tile.ROCK)
	grid.set_tile(Vector2i(7, 1), DungeonGrid.Tile.ROCK)
	context.mark_excavation([Vector2i(5, 5), Vector2i(7, 1)])
	var mining := board.assign(actor, scene.definition)
	_check(mining != null and mining.target_cell == Vector2i(7, 1), "Mining choice compares weighted route length, not waypoint count")
	board.release(actor.id)


func _valid_path(grid: DungeonGrid, path: Array[Vector2i]) -> bool:
	if path.is_empty():
		return false
	for cell in path:
		if not grid.is_walkable(cell):
			return false
	for i in range(1, path.size()):
		if not _reference_step(grid, path[i - 1], path[i]):
			return false
	return true


func _reference_step(grid: DungeonGrid, first: Vector2i, second: Vector2i) -> bool:
	if not grid.is_walkable(first) or not grid.is_walkable(second):
		return false
	var delta := second - first
	if absi(delta.x) > 1 or absi(delta.y) > 1:
		return false
	if delta.x != 0 and delta.y != 0:
		return grid.is_walkable(Vector2i(second.x, first.y)) and grid.is_walkable(Vector2i(first.x, second.y))
	return true


func _dijkstra_cost(grid: DungeonGrid, start: Vector2i, goal: Vector2i) -> float:
	var frontier: Array[Vector2i] = [start]
	var costs: Dictionary[Vector2i, float] = {start: 0.0}
	var settled: Dictionary[Vector2i, bool] = {}
	while not frontier.is_empty():
		var cheapest := 0
		for i in range(1, frontier.size()):
			if costs[frontier[i]] < costs[frontier[cheapest]]:
				cheapest = i
		var cell: Vector2i = frontier.pop_at(cheapest)
		if settled.has(cell):
			continue
		if cell == goal:
			return costs[cell]
		settled[cell] = true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next := cell + Vector2i(dx, dy)
				if settled.has(next) or not _reference_step(grid, cell, next):
					continue
				var cost := costs[cell] + (sqrt(2.0) if dx != 0 and dy != 0 else 1.0)
				if cost < costs.get(next, INF):
					costs[next] = cost
					frontier.append(next)
	return INF
