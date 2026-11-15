class_name DungeonRoomView
extends Node3D
## Replaceable paving and room dressing, derived from room data.

var _context: GameContext
var _dirty := false


func setup(context: GameContext) -> void:
	_context = context
	_context.rooms.changed.connect(_queue_refresh)
	_refresh()


func _queue_refresh() -> void:
	if not _dirty:
		_dirty = true
		_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	for child in get_children():
		child.free()
	for cell in _context.rooms.tiles:
		var definition := _context.registry.get_room(_context.rooms.tiles[cell])
		if definition != null:
			_build_room_tile(cell, definition)
	for room in _context.rooms.get_rooms():
		var definition := _context.registry.get_room(room.definition_id)
		if definition != null and not room.cells.is_empty():
			_add_room_label(room, definition)


func _build_room_tile(cell: Vector2i, definition: RoomDefinition) -> void:
	var tile := Node3D.new()
	tile.name = "RoomTile_%d_%d" % [cell.x, cell.y]
	tile.position = _context.grid.cell_to_world(cell)
	tile.set_meta("definition_id", definition.id)
	add_child(tile)
	var paving := DungeonGeometry.material(definition.floor_color)
	var worn := DungeonGeometry.material(definition.floor_color.lightened(0.10))
	var trim := DungeonGeometry.material(definition.floor_color.lightened(0.28))
	DungeonGeometry.box(tile, Vector3(1.92, 0.055, 1.92), Vector3(0, 0.05, 0), paving)
	for x in [-1, 1]:
		for z in [-1, 1]:
			DungeonGeometry.box(tile, Vector3(0.84, 0.012, 0.84), Vector3(x * 0.46, 0.083, z * 0.46), worn)
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _context.rooms.tiles.get(cell + direction, &"") == definition.id:
			continue
		var size := Vector3(0.07, 0.045, 1.90) if direction.x != 0 else Vector3(1.90, 0.045, 0.07)
		DungeonGeometry.box(tile, size, Vector3(direction.x * 0.93, 0.09, direction.y * 0.93), trim)
	if definition.view_scene != null:
		var custom := definition.view_scene.instantiate()
		if custom is Node3D:
			custom.position.y = 0.10
			tile.add_child(custom)
		else:
			custom.free()
			push_warning("Room view_scene must have a Node3D root: %s" % definition.id)


func _add_room_label(room: RoomState, definition: RoomDefinition) -> void:
	var center := Vector3.ZERO
	for cell in room.cells:
		center += _context.grid.cell_to_world(cell)
	center /= float(room.cells.size())
	var label := Label3D.new()
	label.name = "RoomLabel_%s" % room.id
	label.text = definition.display_name.to_upper()
	label.font_size = 34
	label.pixel_size = 0.010
	label.modulate = Color(0.87, 0.80, 0.63)
	label.outline_size = 7
	label.position = center + Vector3(0, 1.25, -0.35)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
