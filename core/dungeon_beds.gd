class_name DungeonBeds
extends RefCounted
## Personal bed ownership and fitting space, shared by AI and presentation.

signal changed

const INVALID := Vector2i(-1, -1)
const CLAIM_DISTANCE := 0.08
var beds: Dictionary[int, BedState] = {}
var _occupied: Dictionary[Vector2i, int] = {}
var _grid: DungeonGrid
var _rooms: DungeonRooms
var _registry: ContentRegistry


func _init(grid: DungeonGrid, rooms: DungeonRooms, registry: ContentRegistry) -> void:
	_grid = grid
	_rooms = rooms
	_registry = registry
	_rooms.changed.connect(_invalidate)


func get_bed(actor_id: int) -> BedState:
	return beds.get(actor_id)


func find_space(definition: CreatureDefinition, from_cell: Vector2i) -> Vector2i:
	if definition == null or &"rest" not in definition.capabilities or not _grid.is_walkable(from_cell):
		return INVALID
	var best := INVALID
	var best_cost := INF
	var anchors := _rooms.tiles.keys()
	anchors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for anchor: Vector2i in anchors:
		if not can_place(anchor, definition.bed_size, definition.rest_room_tag):
			continue
		var path := GridPathfinder.find_path(_grid, from_cell, anchor)
		if path.is_empty():
			continue
		var cost := GridPathfinder.path_cost(path)
		if cost < best_cost:
			best_cost = cost
			best = anchor
	return best


func can_place(anchor: Vector2i, footprint: Vector2i, room_tag: StringName) -> bool:
	return _footprint_valid(anchor, footprint, room_tag, -1)


func reserve(actor: CreatureState, definition: CreatureDefinition) -> BedState:
	if actor == null or definition == null or actor.id <= 0 or actor.definition_id != definition.id or &"rest" not in definition.capabilities:
		return null
	var start := _grid.world_to_cell(actor.position)
	var existing := get_bed(actor.id)
	if existing != null:
		if existing.size == definition.bed_size and existing.room_tag == definition.rest_room_tag and _footprint_valid(existing.anchor, existing.size, existing.room_tag, actor.id) and not GridPathfinder.find_path(_grid, start, existing.anchor).is_empty():
			return existing
		release(actor.id)
	var anchor := find_space(definition, start)
	if anchor == INVALID:
		return null
	var bed := BedState.new()
	bed.owner_id = actor.id
	bed.anchor = anchor
	bed.size = definition.bed_size
	bed.room_tag = definition.rest_room_tag
	for y in range(anchor.y, anchor.y + bed.size.y):
		for x in range(anchor.x, anchor.x + bed.size.x):
			var cell := Vector2i(x, y)
			bed.cells.append(cell)
			_occupied[cell] = actor.id
	beds[actor.id] = bed
	changed.emit()
	return bed


func establish(actor: CreatureState) -> bool:
	if actor == null or not actor.position.is_finite():
		return false
	var bed := get_bed(actor.id)
	var definition := _registry.get_creature(actor.definition_id) if _registry != null else null
	if bed == null or definition == null or &"rest" not in definition.capabilities or definition.bed_size != bed.size or definition.rest_room_tag != bed.room_tag:
		return false
	if not _footprint_valid(bed.anchor, bed.size, bed.room_tag, actor.id) or actor.position.distance_to(bed.center(_grid)) > CLAIM_DISTANCE:
		return false
	if not bed.established:
		bed.established = true
		changed.emit()
	return true


func release(actor_id: int) -> void:
	var bed := get_bed(actor_id)
	if bed == null:
		return
	for cell in bed.cells:
		if _occupied.get(cell, -1) == actor_id:
			_occupied.erase(cell)
	beds.erase(actor_id)
	changed.emit()


func prune(actors: Array[CreatureState]) -> void:
	var live: Dictionary[int, CreatureState] = {}
	for actor in actors:
		live[actor.id] = actor
	for actor_id in beds.keys():
		var definition := _registry.get_creature(live[actor_id].definition_id) if live.has(actor_id) and _registry != null else null
		var bed := beds[actor_id]
		if definition == null or &"rest" not in definition.capabilities or bed.size != definition.bed_size or bed.room_tag != definition.rest_room_tag:
			release(actor_id)


func _footprint_valid(anchor: Vector2i, footprint: Vector2i, room_tag: StringName, owner_id: int) -> bool:
	if footprint.x <= 0 or footprint.y <= 0 or footprint.x > _grid.width or footprint.y > _grid.height or room_tag == &"" or _registry == null:
		return false
	var room := _rooms.get_room_at(anchor)
	if room == null:
		return false
	var definition := _registry.get_room(room.definition_id)
	if definition == null or room_tag not in definition.tags:
		return false
	for y in range(anchor.y, anchor.y + footprint.y):
		for x in range(anchor.x, anchor.x + footprint.x):
			var cell := Vector2i(x, y)
			if not _grid.is_inside(cell) or _grid.get_tile(cell) != DungeonGrid.Tile.FLOOR or _rooms.get_room_at(cell) != room:
				return false
			if _occupied.has(cell) and _occupied[cell] != owner_id:
				return false
	return true


func _invalidate() -> void:
	for actor_id in beds.keys():
		var bed := beds[actor_id]
		if not _footprint_valid(bed.anchor, bed.size, bed.room_tag, actor_id):
			release(actor_id)
