class_name DungeonInfrastructure
extends RefCounted
## Physical fixtures and landmark ownership; views never create light sources.

signal changed

const LAMP_SECONDS := 2.0
const CLAIM_SECONDS := 4.0
const LAMP_SPACING := 3.0
const WORK_DISTANCE := 0.12
const INVALID_CELL := Vector2i(-1, -1)
const WALL_DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var enabled := false
## Keys are installation access positions, not occupied floor space.
var lamps: Dictionary[Vector2i, bool] = {}
## Retained for old saves/manual reconstruction; current excavation fits instantly.
var lamp_progress: Dictionary[Vector2i, float] = {}
var lamp_walls: Dictionary[Vector2i, Vector2i] = {}
var portal_progress: Dictionary[Vector2i, float] = {}
var _context_ref: WeakRef


func _init(context: GameContext) -> void:
	_context_ref = weakref(context)
	context.grid.tile_changed.connect(_on_tile_changed)
	context.rooms.changed.connect(_on_rooms_changed)


func enable(initial_lamps: Array[Vector2i] = []) -> void:
	var context := _context()
	enabled = true
	for cell in context.grid.cells_of_type(DungeonGrid.Tile.PORTAL):
		if not portal_progress.has(cell):
			portal_progress[cell] = 0.0
	for cell in initial_lamps:
		var wall := find_lamp_wall(cell)
		if wall != INVALID_CELL:
			lamps[cell] = true
			lamp_walls[cell] = wall
	ensure_room_corner_lamps()
	changed.emit()


func room_corner_cells(room: RoomState) -> Array[Vector2i]:
	var corners: Array[Vector2i] = []
	if room == null:
		return corners
	var members: Dictionary[Vector2i, bool] = {}
	for cell in room.cells:
		members[cell] = true
	for cell in room.cells:
		for index in WALL_DIRECTIONS.size():
			var first: Vector2i = WALL_DIRECTIONS[index]
			var second: Vector2i = WALL_DIRECTIONS[(index + 1) % WALL_DIRECTIONS.size()]
			if not members.has(cell + first) and not members.has(cell + second):
				corners.append(cell)
				break
	return corners


func ensure_room_corner_lamps() -> void:
	var context := _context()
	if not enabled or context == null:
		return
	var changed_any := false
	for room in context.rooms.get_rooms():
		for cell in room_corner_cells(room):
			# Corner coverage is intentional even near a corridor lamp. A light
			# around another wall must not leave the room itself in shadow.
			var wall := get_lamp_wall(cell)
			if lamps.has(cell) or not is_lamp_wall_valid(cell, wall):
				continue
			lamps[cell] = true
			lamp_walls[cell] = wall
			lamp_progress.erase(cell)
			changed_any = true
	if changed_any:
		changed.emit()


func find_lamp_wall(cell: Vector2i) -> Vector2i:
	var context := _context()
	if context == null:
		return INVALID_CELL
	for direction in WALL_DIRECTIONS:
		var wall: Vector2i = cell + direction
		if is_lamp_wall_valid(cell, wall):
			return wall
	return INVALID_CELL


func get_lamp_wall(cell: Vector2i) -> Vector2i:
	if lamp_walls.has(cell):
		var wall := lamp_walls[cell]
		return wall if is_lamp_wall_valid(cell, wall) else INVALID_CELL
	return find_lamp_wall(cell)


func is_lamp_wall_valid(cell: Vector2i, wall: Vector2i) -> bool:
	var context := _context()
	return context != null and context.grid.is_inside(cell) and context.grid.is_inside(wall) and context.grid.get_tile(cell) == DungeonGrid.Tile.FLOOR and context.grid.get_tile(wall) in [DungeonGrid.Tile.ROCK, DungeonGrid.Tile.BEDROCK] and absi(cell.x - wall.x) + absi(cell.y - wall.y) == 1 and context.exploration.is_revealed(cell) and context.exploration.is_revealed(wall)


func is_portal_claimed(cell: Vector2i) -> bool:
	var context := _context()
	return context != null and context.grid.is_inside(cell) and context.grid.get_tile(cell) == DungeonGrid.Tile.PORTAL and (not enabled or portal_progress.get(cell, 0.0) >= 1.0)


func ensure_wall_lamps() -> void:
	# Fitting a sconce is part of opening the passage, not a later worker queue.
	var context := _context()
	if not enabled or context == null:
		return
	ensure_room_corner_lamps()
	var changed_any := false
	for cell in context.exploration.connected_cells():
		if not can_install_lamp(cell):
			continue
		lamps[cell] = true
		lamp_walls[cell] = find_lamp_wall(cell)
		lamp_progress.erase(cell)
		changed_any = true
	if changed_any:
		changed.emit()


func can_claim_portal(cell: Vector2i) -> bool:
	var context := _context()
	return enabled and context != null and context.grid.get_tile(cell) == DungeonGrid.Tile.PORTAL and context.exploration.is_reachable(cell) and context.exploration.is_revealed(cell) and not is_portal_claimed(cell)


func can_install_lamp(cell: Vector2i) -> bool:
	var context := _context()
	if not enabled or context == null or lamps.has(cell) or not context.exploration.is_reachable(cell) or get_lamp_wall(cell) == INVALID_CELL:
		return false
	# Use path distance: two passages separated by a wall each need their own light.
	for existing in lamps:
		if existing.distance_to(cell) >= LAMP_SPACING:
			continue
		var path := GridPathfinder.find_path(context.grid, existing, cell)
		if not path.is_empty() and GridPathfinder.path_cost(path) < LAMP_SPACING:
			return false
	return true


func lamp_candidates() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var context := _context()
	if not enabled or context == null:
		return result
	for cell in context.exploration.connected_cells():
		if can_install_lamp(cell):
			result.append(cell)
	return result


func work_portal(actor: CreatureState, cell: Vector2i, delta: float, rate: float) -> bool:
	if not can_claim_portal(cell) or not _can_work(actor, cell, &"claim_portal", delta, rate):
		return false
	portal_progress[cell] = minf(1.0, portal_progress.get(cell, 0.0) + delta * rate / CLAIM_SECONDS)
	changed.emit()
	return is_portal_claimed(cell)


func work_lamp(actor: CreatureState, cell: Vector2i, delta: float, rate: float) -> bool:
	# Compatibility for interrupted pre-sconce state. No live job provider uses it.
	if not can_install_lamp(cell) or not _can_work(actor, cell, &"install_lamp", delta, rate):
		return false
	if not lamp_walls.has(cell):
		lamp_walls[cell] = find_lamp_wall(cell)
	lamp_progress[cell] = minf(1.0, lamp_progress.get(cell, 0.0) + delta * rate / LAMP_SECONDS)
	if lamp_progress[cell] >= 1.0:
		lamps[cell] = true
		lamp_progress.erase(cell)
		for pending in lamp_progress.keys():
			if not can_install_lamp(pending):
				lamp_progress.erase(pending)
				lamp_walls.erase(pending)
	changed.emit()
	return lamps.has(cell)


func _can_work(actor: CreatureState, cell: Vector2i, capability: StringName, delta: float, rate: float) -> bool:
	var context := _context()
	if context == null or actor == null or actor not in context.actors or actor.is_held or actor.needs_requested or actor.carried_gold > 0 or not actor.position.is_finite() or not is_finite(delta) or not is_finite(rate) or delta <= 0.0 or rate <= 0.0:
		return false
	var definition := context.registry.get_creature(actor.definition_id)
	return definition != null and capability in definition.capabilities and actor.position.distance_to(context.grid.cell_to_world(cell)) <= WORK_DISTANCE


func _on_tile_changed(cell: Vector2i) -> void:
	var context := _context()
	if context == null or not enabled:
		return
	for service in lamp_walls.keys():
		if not is_lamp_wall_valid(service, lamp_walls[service]):
			lamps.erase(service)
			lamp_progress.erase(service)
			lamp_walls.erase(service)
	if context.grid.get_tile(cell) != DungeonGrid.Tile.PORTAL:
		portal_progress.erase(cell)
	elif not portal_progress.has(cell):
		portal_progress[cell] = 0.0
	if context.grid.get_tile(cell) == DungeonGrid.Tile.FLOOR:
		ensure_wall_lamps()
	changed.emit()


func _on_rooms_changed() -> void:
	# A sconce occupies a wall face. Rooms/beds remain free to use its access tile.
	ensure_room_corner_lamps()
	changed.emit()


func _context() -> GameContext:
	return _context_ref.get_ref() as GameContext
