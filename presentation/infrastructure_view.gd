class_name DungeonInfrastructureView
extends Node3D
## Render built lamps and room fixtures from session state, without placing them.

var _context: GameContext
var _dirty := false
var _snapshot := ""
var lamp_count := 0
var room_light_count := 0


func setup(context: GameContext) -> void:
	_context = context
	context.infrastructure.changed.connect(_queue_refresh)
	context.exploration.changed.connect(_queue_refresh)
	context.rooms.changed.connect(_queue_refresh)
	context.grid.tile_changed.connect(_on_terrain_changed)
	_refresh()


func _on_terrain_changed(_cell: Vector2i) -> void:
	_queue_refresh()


func _queue_refresh() -> void:
	if not _dirty:
		_dirty = true
		_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	var snapshot := str([_context.infrastructure.lamps, _context.infrastructure.lamp_walls, _context.rooms.tiles, _context.exploration.revealed, _context.grid.navigation_revision])
	if snapshot == _snapshot:
		return
	_snapshot = snapshot
	for child in get_children():
		child.free()
	lamp_count = 0
	room_light_count = 0
	var lit_cells: Array[Vector2i] = []
	for cell: Vector2i in _context.infrastructure.lamps:
		if not _context.exploration.is_revealed(cell) or not _context.grid.is_walkable(cell):
			continue
		var wall := _context.infrastructure.get_lamp_wall(cell)
		if not _context.infrastructure.is_lamp_wall_valid(cell, wall):
			continue
		_add_fixture(cell, wall, false)
		lit_cells.append(cell)
		lamp_count += 1
	# Room membership supplies fixture placement, not a separate resource source.
	# Large groups get spaced fixtures; merging never stacks coincident lights.
	for room in _context.rooms.get_rooms():
		var candidates := room.cells.duplicate()
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		for cell: Vector2i in candidates:
			if not _context.exploration.is_revealed(cell):
				continue
			var wall := _context.infrastructure.find_lamp_wall(cell)
			if not _context.infrastructure.is_lamp_wall_valid(cell, wall):
				continue
			var covered := false
			for other in lit_cells:
				if other.distance_squared_to(cell) < 10:
					var path := GridPathfinder.find_path(_context.grid, other, cell)
					if not path.is_empty() and GridPathfinder.path_cost(path) < 3.2:
						covered = true
						break
			if covered:
				continue
			_add_fixture(cell, wall, true)
			lit_cells.append(cell)
			room_light_count += 1


func _add_fixture(cell: Vector2i, wall: Vector2i, room_fixture: bool) -> void:
	var lamp := DungeonLampView.new()
	lamp.name = ("RoomLamp_%d_%d" if room_fixture else "BuiltLamp_%d_%d") % [cell.x, cell.y]
	var toward_wall := Vector3(wall.x - cell.x, 0, wall.y - cell.y)
	lamp.position = _context.grid.cell_to_world(cell) + toward_wall * (DungeonGrid.TILE_SIZE * 0.5 - 0.04)
	var outward := -toward_wall
	lamp.rotation.y = atan2(outward.x, outward.z)
	lamp.set_meta("cell", cell)
	lamp.set_meta("wall", wall)
	add_child(lamp)
	lamp.build(room_fixture)
