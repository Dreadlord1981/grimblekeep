class_name GridPathfinder
extends RefCounted
## Eight-direction A* over authoritative terrain. Used on the main thread.
## A single weak session cache avoids rebuilding the graph for every job candidate.

static var _cached_grid: WeakRef
static var _cached_revision: int = -1
static var _graph: AStarGrid2D


static func find_path(grid: DungeonGrid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if grid == null or not grid.is_walkable(start) or not grid.is_walkable(goal):
		return []
	_prepare_graph(grid)
	return _graph.get_id_path(start, goal)


static func can_step(grid: DungeonGrid, from: Vector2i, to: Vector2i) -> bool:
	if grid == null or not grid.is_walkable(from) or not grid.is_walkable(to):
		return false
	var offset := to - from
	if absi(offset.x) > 1 or absi(offset.y) > 1:
		return false
	if offset.x != 0 and offset.y != 0:
		return grid.is_walkable(from + Vector2i(offset.x, 0)) and grid.is_walkable(from + Vector2i(0, offset.y))
	return true


static func path_cost(path: Array[Vector2i]) -> float:
	var cost := 0.0
	for index in range(1, path.size()):
		cost += Vector2(path[index] - path[index - 1]).length()
	return cost


static func _prepare_graph(grid: DungeonGrid) -> void:
	if _cached_grid != null and _cached_grid.get_ref() == grid and _cached_revision == grid.navigation_revision:
		return
	_graph = AStarGrid2D.new()
	_graph.region = Rect2i(0, 0, grid.width, grid.height)
	_graph.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_graph.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_graph.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_graph.update()
	for y in grid.height:
		for x in grid.width:
			var cell := Vector2i(x, y)
			_graph.set_point_solid(cell, not grid.is_walkable(cell))
	_cached_grid = weakref(grid)
	_cached_revision = grid.navigation_revision
