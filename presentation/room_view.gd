class_name DungeonRoomView
extends Node3D
## Replaceable paving and room dressing, derived from room data.

var _context: GameContext
var _dirty := false


func setup(context: GameContext) -> void:
	_context = context
	_context.rooms.changed.connect(_queue_refresh)
	_context.beds.changed.connect(_queue_refresh)
	_context.grid.tile_changed.connect(_on_terrain_changed)
	_context.excavation_marks_changed.connect(_on_terrain_changed)
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
			if definition.wall_style == &"pen_fencing":
				_build_pen_perimeter(room, definition)
	for bed in _context.beds.beds.values():
		if not bed.established:
			continue
		var view := DungeonBedView.new()
		view.build(bed, _context.grid)
		add_child(view)


func _on_terrain_changed(_cell: Vector2i) -> void:
	_queue_refresh()


func _build_room_tile(cell: Vector2i, definition: RoomDefinition) -> void:
	var tile := Node3D.new()
	tile.name = "RoomTile_%d_%d" % [cell.x, cell.y]
	tile.position = _context.grid.cell_to_world(cell)
	tile.set_meta("definition_id", definition.id)
	tile.set_meta("floor_style", definition.floor_style)
	add_child(tile)
	var paving := DungeonGeometry.material(definition.floor_color)
	var worn := DungeonGeometry.material(definition.floor_color.lightened(0.10))
	var trim := DungeonGeometry.material(definition.accent_color)
	DungeonGeometry.box(tile, Vector3(1.92, 0.055, 1.92), Vector3(0, 0.05, 0), paving)
	for x in [-1, 1]:
		for z in [-1, 1]:
			DungeonGeometry.box(tile, Vector3(0.84, 0.012, 0.84), Vector3(x * 0.46, 0.083, z * 0.46), worn)
	_build_floor_decoration(tile, definition, cell)
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _context.rooms.tiles.get(cell + direction, &"") == definition.id:
			continue
		var size := Vector3(0.07, 0.045, 1.90) if direction.x != 0 else Vector3(1.90, 0.045, 0.07)
		DungeonGeometry.box(tile, size, Vector3(direction.x * 0.93, 0.09, direction.y * 0.93), trim)
		var neighbor: Vector2i = cell + direction
		# Leave marked rock faces bare so their authoritative amber side glow
		# remains visible. Dressing returns immediately when the mark is removed.
		if _context.grid.is_inside(neighbor) and _context.grid.get_tile(neighbor) == DungeonGrid.Tile.ROCK and not _context.excavation_marks.has(neighbor):
			_build_wall(tile, definition, direction)
	if definition.view_scene != null:
		var custom := definition.view_scene.instantiate()
		if custom is Node3D:
			custom.position.y = 0.10
			tile.add_child(custom)
		else:
			custom.free()
			push_warning("Room view_scene must have a Node3D root: %s" % definition.id)


func _build_floor_decoration(tile: Node3D, definition: RoomDefinition, cell: Vector2i) -> void:
	var accent := DungeonGeometry.material(definition.accent_color)
	match definition.floor_style:
		&"inlaid_tiles":
			for side in [-1, 1]:
				DungeonGeometry.box(tile, Vector3(1.65, 0.013, 0.045), Vector3(0, 0.098, side * 0.72), accent)
				DungeonGeometry.box(tile, Vector3(0.045, 0.013, 1.65), Vector3(side * 0.72, 0.098, 0), accent)
			var diamond := DungeonGeometry.box(tile, Vector3(0.21, 0.014, 0.21), Vector3(0, 0.099, 0), accent)
			diamond.rotation.y = PI * 0.25
		&"patched_rugs":
			var faded := DungeonGeometry.material(definition.accent_color.lightened(0.18))
			var stitches := DungeonGeometry.material(Color("9b8a6b"))
			var rug := DungeonGeometry.box(tile, Vector3(1.64, 0.025, 1.64), Vector3(0, 0.105, 0), accent)
			rug.rotation.y = -0.025 if posmod(cell.x + cell.y, 2) == 0 else 0.025
			var patch := DungeonGeometry.box(tile, Vector3(0.48, 0.015, 0.39), Vector3(0.32, 0.127, -0.30), faded)
			patch.rotation.y = 0.16
			for stitch in range(4):
				DungeonGeometry.box(tile, Vector3(0.035, 0.014, 0.10), Vector3(0.12 + stitch * 0.13, 0.14, -0.10), stitches)
			for edge in [-1, 1]:
				for fringe in range(7):
					DungeonGeometry.box(tile, Vector3(0.10, 0.015, 0.10 + float(fringe % 3) * 0.025), Vector3(-0.68 + fringe * 0.22, 0.112, edge * 0.83), faded)
		&"muddy_straw":
			var mud := DungeonGeometry.material(definition.floor_color.darkened(0.20))
			var straw := DungeonGeometry.material(Color("ad9060"))
			var puddle := DungeonGeometry.material(Color("40372d"))
			DungeonGeometry.sphere(tile, Vector3(0, 0.102, 0), Vector3(1.88, 0.045, 1.86), mud, 8)
			DungeonGeometry.sphere(tile, Vector3(-0.33, 0.125, 0.30), Vector3(0.56, 0.015, 0.39), puddle, 8)
			for stalk in range(9):
				var x := -0.72 + float(posmod(stalk * 7 + cell.x * 3, 13)) * 0.12
				var z := -0.70 + float(posmod(stalk * 11 + cell.y * 5, 12)) * 0.12
				var blade := DungeonGeometry.box(tile, Vector3(0.28, 0.012, 0.025), Vector3(x, 0.137, z), straw)
				blade.rotation.y = float(stalk) * 1.9
			if posmod(cell.x + cell.y, 3) == 0:
				_build_trough(tile)


func _build_trough(tile: Node3D) -> void:
	var wood := DungeonGeometry.material(Color("70543b"))
	var dark := DungeonGeometry.material(Color("393329"))
	var center := Vector3(0, 0.20, -0.72)
	DungeonGeometry.box(tile, Vector3(0.70, 0.09, 0.29), center, dark)
	for side in [-1, 1]:
		DungeonGeometry.box(tile, Vector3(0.76, 0.18, 0.055), center + Vector3(0, 0.055, side * 0.16), wood)
		DungeonGeometry.box(tile, Vector3(0.055, 0.18, 0.32), center + Vector3(side * 0.36, 0.055, 0), wood)


func _build_pen_perimeter(room: RoomState, definition: RoomDefinition) -> void:
	var members: Dictionary[Vector2i, bool] = {}
	var cells := room.cells.duplicate()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell in cells:
		members[cell] = true
	var wood := DungeonGeometry.material(definition.accent_color)
	var gate_placed := false
	for cell in cells:
		for direction: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]:
			if members.has(cell + direction) or not _context.grid.is_walkable(cell + direction):
				continue
			_build_pen_section(cell, direction, wood, not gate_placed)
			gate_placed = true


func _build_pen_section(cell: Vector2i, direction: Vector2i, wood: Material, opening: bool) -> void:
	# Only actual room perimeter edges receive rails; one open-floor edge is a
	# central gate. Decoration has no collision and leaves navigation unchanged.
	var gate := Node3D.new()
	gate.name = "PenBoundary_%d_%d_%d_%d" % [cell.x, cell.y, direction.x, direction.y]
	gate.set_meta("cell", cell)
	gate.set_meta("direction", direction)
	gate.set_meta("gate", opening)
	gate.position = _context.grid.cell_to_world(cell) + Vector3(direction.x * 0.93, 0, direction.y * 0.93)
	gate.rotation.y = atan2(float(-direction.x), float(-direction.y))
	add_child(gate)
	if not opening:
		for post in [-0.90, 0.0, 0.90]:
			DungeonGeometry.box(gate, Vector3(0.075, 0.47, 0.075), Vector3(post, 0.32, 0), wood)
		for height in [0.24, 0.46]:
			DungeonGeometry.box(gate, Vector3(1.88, 0.055, 0.055), Vector3(0, height, 0), wood)
		return
	for side in [-1, 1]:
		for post in [0.48, 0.90]:
			DungeonGeometry.box(gate, Vector3(0.075, 0.47, 0.075), Vector3(side * post, 0.32, 0), wood)
		for height in [0.24, 0.46]:
			DungeonGeometry.box(gate, Vector3(0.49, 0.055, 0.055), Vector3(side * 0.70, height, 0), wood)


func _build_wall(tile: Node3D, definition: RoomDefinition, direction: Vector2i) -> void:
	if definition.wall_style == &"" and definition.wall_scene == null:
		return
	var wall := Node3D.new()
	wall.name = "RoomWall_%d_%d" % [direction.x, direction.y]
	wall.set_meta("wall_style", definition.wall_style)
	wall.set_meta("direction", direction)
	wall.position = Vector3(direction.x * 0.99, 0, direction.y * 0.99)
	wall.rotation.y = atan2(float(-direction.x), float(-direction.y))
	tile.add_child(wall)
	if definition.wall_scene != null:
		var custom := definition.wall_scene.instantiate()
		if custom is Node3D:
			wall.add_child(custom)
		else:
			custom.free()
			push_warning("Room wall_scene must have a Node3D root: %s" % definition.id)
		return
	var stone := DungeonGeometry.material(definition.wall_color)
	var accent := DungeonGeometry.material(definition.accent_color)
	var iron := DungeonGeometry.material(Color("302d31"))
	var bone := DungeonGeometry.material(Color("b7a882"))
	match definition.wall_style:
		&"pen_fencing":
			for post in [-1, 0, 1]:
				DungeonGeometry.box(wall, Vector3(0.12, 1.22, 0.12), Vector3(post * 0.78, 0.73, 0.10), accent)
			for height in [0.43, 0.88, 1.32]:
				DungeonGeometry.box(wall, Vector3(1.78, 0.12, 0.10), Vector3(0, height, 0.12), accent)
			for post in [-1, 1]:
				for height in [0.43, 0.88, 1.32]:
					DungeonGeometry.sphere(wall, Vector3(post * 0.78, height, 0.18), Vector3.ONE * 0.065, iron, 6)
		&"brass_panels":
			DungeonGeometry.box(wall, Vector3(1.82, 1.35, 0.06), Vector3(0, 0.82, 0.035), stone)
			for edge in [-1, 1]:
				DungeonGeometry.box(wall, Vector3(1.76, 0.075, 0.08), Vector3(0, 0.82 + edge * 0.57, 0.09), accent)
				DungeonGeometry.box(wall, Vector3(0.075, 1.18, 0.08), Vector3(edge * 0.80, 0.82, 0.09), accent)
				for row in [-1, 1]:
					DungeonGeometry.sphere(wall, Vector3(edge * 0.77, 0.82 + row * 0.52, 0.15), Vector3.ONE * 0.10, iron, 6)
			var seal := DungeonGeometry.cylinder(wall, 0.27, 0.045, Vector3(0, 0.85, 0.12), accent, -1.0, 8)
			seal.rotation.x = PI * 0.5
			DungeonGeometry.box(wall, Vector3(0.055, 0.35, 0.035), Vector3(0, 0.85, 0.16), iron)
		&"patched_hangings":
			DungeonGeometry.box(wall, Vector3(1.85, 0.10, 0.13), Vector3(0, 1.52, 0.11), iron)
			DungeonGeometry.box(wall, Vector3(1.24, 1.00, 0.035), Vector3(0, 0.98, 0.12), accent)
			for fringe in range(6):
				var length := 0.14 + float(fringe % 3) * 0.06
				DungeonGeometry.box(wall, Vector3(0.19, length, 0.035), Vector3(-0.52 + fringe * 0.21, 0.48 - length * 0.5, 0.12), accent)
			var patch := DungeonGeometry.box(wall, Vector3(0.32, 0.30, 0.02), Vector3(-0.32, 0.68, 0.15), stone)
			patch.rotation.z = 0.13
			DungeonGeometry.sphere(wall, Vector3(0, 1.10, 0.17), Vector3(0.40, 0.40, 0.08), bone, 8)
			DungeonGeometry.box(wall, Vector3(0.24, 0.13, 0.05), Vector3(0, 0.89, 0.18), bone)
			for side in [-1, 1]:
				DungeonGeometry.sphere(wall, Vector3(side * 0.08, 1.10, 0.21), Vector3(0.10, 0.12, 0.025), iron, 6)
			for tally in range(4):
				DungeonGeometry.box(wall, Vector3(0.025, 0.19, 0.03), Vector3(0.68 + tally * 0.065, 0.67, 0.09), bone)


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
