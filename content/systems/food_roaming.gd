class_name FoodRoaming
extends RefCounted
## Confined living-food movement; quantity, nutrition and age are owned elsewhere.

const WALK_SPEED := 1.2
const CARDINALS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var _context: GameContext
var _topology := ""
var _components: Dictionary[Vector2i, Dictionary] = {}
var _states: Dictionary[int, Dictionary] = {}


func tick(context: GameContext, delta: float) -> void:
	if context == null or context.food == null or not is_finite(delta) or delta <= 0.0:
		return
	if _context != context:
		_context = context
		_topology = ""
		_states.clear()
	var topology := str([context.grid.navigation_revision, context.rooms.tiles])
	if topology != _topology:
		_topology = topology
		_components.clear()
		for state in _states.values():
			state.path = []
	var serving: Dictionary[int, FoodReservation] = {}
	for reservation in context.food.reservations.values():
		if context.food.is_valid(reservation):
			serving[reservation.unit_id] = reservation
	for unit in context.food.units.values():
		var definition := context.registry.get_food(unit.food_id)
		if definition == null or not definition.wanders:
			continue
		if not _states.has(unit.id):
			_states[unit.id] = {"path": [], "index": 0, "step": 0, "wait": float(unit.id % 3) * 0.25, "goal": unit.cell}
		_tick_unit(unit, _states[unit.id], serving.get(unit.id), delta)
	for id in _states.keys():
		if not context.food.units.has(id):
			_states.erase(id)


func _tick_unit(unit: FoodUnitState, state: Dictionary, reservation: FoodReservation, delta: float) -> void:
	var grid := _context.grid
	var current := grid.world_to_cell(unit.position)
	if not grid.is_walkable(current):
		# Trusted terrain edits can enclose a pig. Leave cardinally and smoothly;
		# never snap it elsewhere or discard its retained physical food stock.
		state.path = []
		_escape_blocked(unit, current, delta)
		return
	var component := _component(unit.cell, unit.food_id)
	var returning: bool = reservation != null or component.is_empty() or not component.cells.has(current)
	var goal := reservation.cell if reservation != null else unit.cell
	if returning:
		if state.goal != goal:
			state.path = []
		state.goal = goal
		if unit.position.distance_to(grid.cell_to_world(goal)) < 0.002:
			state.path = []
			return
		if state.path.is_empty():
			_set_path(state, current, goal, component)
		_move(unit, state, component, delta, false)
		return
	state.wait = maxf(0.0, float(state.wait) - delta)
	if state.path.is_empty() and state.wait <= 0.0:
		var cells: Array = component.sorted
		for attempt in cells.size():
			var index := posmod(unit.id * 13 + int(state.step), cells.size())
			state.step = int(state.step) + 1
			var candidate: Vector2i = cells[index]
			if candidate != current and _set_path(state, current, candidate, component):
				break
	if not state.path.is_empty():
		_move(unit, state, component, delta, true)


func _component(cell: Vector2i, food_id: StringName) -> Dictionary:
	if _components.has(cell):
		var cached := _components[cell]
		return cached if cached.food_id == food_id else {}
	var room := _context.rooms.get_room_at(cell)
	if room == null:
		return {}
	var definition := _context.registry.get_room(room.definition_id)
	if definition == null or definition.food_type != food_id:
		return {}
	var cells: Dictionary[Vector2i, bool] = {}
	var sorted: Array[Vector2i] = []
	for member in room.cells:
		if _context.grid.is_walkable(member):
			cells[member] = true
			sorted.append(member)
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var graph := AStarGrid2D.new()
	graph.region = Rect2i(0, 0, _context.grid.width, _context.grid.height)
	graph.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	graph.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	graph.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	graph.update()
	for y in _context.grid.height:
		for x in _context.grid.width:
			graph.set_point_solid(Vector2i(x, y), not cells.has(Vector2i(x, y)))
	var component := {"cells": cells, "sorted": sorted, "graph": graph, "food_id": food_id}
	for member in sorted:
		_components[member] = component
	return component


func _set_path(state: Dictionary, from: Vector2i, goal: Vector2i, component: Dictionary) -> bool:
	var path: Array[Vector2i] = []
	if not component.is_empty() and component.cells.has(from) and component.cells.has(goal):
		var graph: AStarGrid2D = component.graph
		path = graph.get_id_path(from, goal)
	else:
		path = GridPathfinder.find_path(_context.grid, from, goal)
	state.path = path
	state.index = 0
	state.goal = goal
	return not path.is_empty()


func _move(unit: FoodUnitState, state: Dictionary, component: Dictionary, delta: float, restricted: bool) -> void:
	var path: Array = state.path
	for index in range(int(state.index), path.size()):
		var previous: Vector2i = path[maxi(0, index - 1)]
		var cell: Vector2i = path[index]
		if not GridPathfinder.can_step(_context.grid, previous, cell) or (restricted and not _inside_step(component.cells, previous, cell)):
			state.path = []
			return
	var budget := WALK_SPEED * delta
	while int(state.index) < path.size():
		var target := _context.grid.cell_to_world(path[int(state.index)])
		var offset := target - unit.position
		if offset.length() < 0.002:
			state.index = int(state.index) + 1
			continue
		if budget <= 0.0:
			break
		unit.heading = atan2(offset.x, offset.z)
		var moved := minf(offset.length(), budget)
		unit.position = unit.position.move_toward(target, moved)
		budget -= moved
	if int(state.index) >= path.size():
		state.path = []
		state.wait = 0.8 + float(unit.id % 3) * 0.15


func _inside_step(cells: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if not cells.has(from) or not cells.has(to):
		return false
	var difference := to - from
	return difference.x == 0 or difference.y == 0 or (cells.has(from + Vector2i(difference.x, 0)) and cells.has(from + Vector2i(0, difference.y)))


func _escape_blocked(unit: FoodUnitState, current: Vector2i, delta: float) -> void:
	var nearest := Vector3.ZERO
	var best := INF
	for offset: Vector2i in CARDINALS:
		var cell := current + offset
		if not _context.grid.is_walkable(cell):
			continue
		var target := _context.grid.cell_to_world(cell)
		var distance := unit.position.distance_squared_to(target)
		if distance < best:
			best = distance
			nearest = target
	if is_finite(best):
		var direction := nearest - unit.position
		unit.heading = atan2(direction.x, direction.z)
		unit.position = unit.position.move_toward(nearest, WALK_SPEED * delta)
