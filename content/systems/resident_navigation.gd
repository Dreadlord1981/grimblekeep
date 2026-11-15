class_name ResidentNavigation
extends RefCounted
## Shared need movement: actual distance, strict corners and dynamic route checks.

enum Travel { ARRIVED, MOVING, BLOCKED }
var path: Array[Vector2i] = []
var _grid: DungeonGrid
var _actor: CreatureState
var _path_index := 0
var _goal_cell := Vector2i(-1, -1)
var _goal_world := Vector3.ZERO


func _init(grid: DungeonGrid, actor: CreatureState) -> void:
	_grid = grid
	_actor = actor


func set_route(goal_cell: Vector2i, goal_world: Vector3) -> bool:
	path = GridPathfinder.find_path(_grid, _grid.world_to_cell(_actor.position), goal_cell)
	_path_index = 0
	_goal_cell = goal_cell
	_goal_world = goal_world
	return not path.is_empty()


func follow(delta: float, speed: float) -> int:
	if path.is_empty():
		return Travel.BLOCKED
	for index in range(_path_index, path.size()):
		var previous := path[maxi(0, index - 1)]
		if not GridPathfinder.can_step(_grid, previous, path[index]):
			if not set_route(_goal_cell, _goal_world):
				return Travel.BLOCKED
			break
	var budget := speed * delta
	var moved := false
	while _path_index <= path.size():
		var destination := _goal_world if _path_index == path.size() else _grid.cell_to_world(path[_path_index])
		var distance := _actor.position.distance_to(destination)
		if distance < 0.002:
			_actor.position = destination
			_path_index += 1
			continue
		if budget <= 0.0:
			break
		var direction := destination - _actor.position
		_actor.heading = atan2(direction.x, direction.z)
		var traveled := minf(distance, budget)
		_actor.position = _actor.position.move_toward(destination, traveled)
		_actor.phase += traveled * 4.0
		budget -= traveled
		moved = true
	if moved:
		_actor.action = &"walking"
	return Travel.ARRIVED if _path_index > path.size() else Travel.MOVING


func clear() -> void:
	path.clear()
	_path_index = 0
