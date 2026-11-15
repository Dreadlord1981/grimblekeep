extends SceneTree
## Actual room commands and saved wall fixtures keep Pig Pen interiors legible.

const THREE := Rect2i(18, 13, 3, 3)
const FIVE := Rect2i(18, 13, 5, 5)
var _app: Node3D
var _context: GameContext
var _view: DungeonView
var _checks := 0
var _failures: Array[String] = []
var _slot := "res://artifacts/room-corner-%d.json" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_app.save_path = _slot
	root.add_child(_app)
	_app.set_physics_process(false)
	_app.controller.set_process(false)
	_context = _app.context
	_find_view()
	# Authoring opens ordinary rock only; construction still uses player commands.
	_context.grid.set_tile(Vector2i(17, 14), DungeonGrid.Tile.FLOOR)
	_excavate(THREE)
	_check(_context.rooms.build(&"foundation.pig_pen", _cells(THREE)).success, "A real funded three-by-three Pig Pen builds on the excavated annex")
	_check(_corners_present(THREE), "Every wall-supported Pig Pen corner has an installed lamp despite normal spacing")
	_camera(Vector2i(19, 14), 20.0)
	var source: Vector2i = _context.food.sources.keys()[0]
	_context.food.produce(source, &"foundation.cave_pig", 2)
	for unit in _context.food.units.values():
		unit.age_seconds = 30.0
	var units := _context.food.units.values()
	units[0].position = _context.grid.cell_to_world(Vector2i(19, 14))
	units[1].position = _context.grid.cell_to_world(Vector2i(18, 15))
	var three_image := await _capture("room-corners-pigpen-3x3")
	_check(_visible_corner_models(THREE), "All four rendered sconces attach to the chosen walls and face the room interior")
	_check(_all_meshes_clear_floor(), "Corner lamps leave all floor-level space clear for pigs, beds and furniture")
	_check(_room_floor_brightness(three_image, THREE) > 0.075, "Three-by-three Pig Pen floor is readable under its local corner lights")
	# Extend the same room; old supporting walls disappear during excavation.
	_excavate(FIVE)
	_check(_context.rooms.build(&"foundation.pig_pen", _cells(FIVE)).success, "Extending the same Pig Pen builds the additional sixteen tiles")
	_check(_corners_present(FIVE), "Room expansion immediately fits lamps at the new outer corners")
	_camera(Vector2i(20, 15), 26.0)
	var five_image := await _capture("room-corners-pigpen-5x5")
	_check(_visible_corner_models(FIVE), "Expanded room corner fixtures remain attached and face inward")
	_check(_room_floor_brightness(five_image, FIVE) > 0.06, "Five-by-five room remains readable without global daylight")
	var before := _context.infrastructure.lamps.size()
	_context.rooms.changed.emit()
	_context.rooms.changed.emit()
	await process_frame
	_check(_context.infrastructure.lamps.size() == before and _lights().lamp_count == before, "Repeated room refreshes neither duplicate saved lamps nor rendered fixtures")
	# Sell a middle column, then rebuild it: components and current corners update.
	var split: Array[Vector2i] = []
	for y in range(FIVE.position.y, FIVE.end.y):
		split.append(Vector2i(20, y))
	_check(_context.rooms.remove(split).success and _context.rooms.get_rooms().size() == 2, "Selling a middle strip splits room membership without occupying the floor")
	_check(_context.rooms.build(&"foundation.pig_pen", split).success and _context.rooms.get_rooms().size() == 1 and _corners_present(FIVE), "Merging room components retains all valid outer corner lighting")
	var actor: CreatureState = _context.actors[0]
	var bank: Vector2i = _context.economy.stored_by_cell.keys()[0]
	_check(_context.keeper.pickup(actor.id) and _context.keeper.pickup_gold(bank, 23), "A mixed creature/gold queue can coexist with room-corner lighting")
	var lamps := _context.infrastructure.lamps.duplicate()
	var mounts := _context.infrastructure.lamp_walls.duplicate()
	var total_gold := _context.economy.accounted_gold(_context.actors)
	_check(_app.save_game().success and _app.load_game().success, "Actual app save/load restores the corner-lit room")
	_context = _app.context
	_app.controller.set_process(false)
	_find_view()
	_camera(Vector2i(20, 15), 26.0)
	var loaded := await _capture("room-corners-loaded")
	_check(_context.infrastructure.lamps == lamps and _context.infrastructure.lamp_walls == mounts and _corners_present(FIVE), "Saved corner positions and exact supporting faces restore without new duplicates")
	_check(_context.keeper.held_count == 2 and _context.keeper.held_actor.id == actor.id and _context.keeper.total_held_gold == 23 and _context.economy.accounted_gold(_context.actors) == total_gold, "Lighting and room edits preserve creature identity, hand order and every gold balance")
	_check(_room_floor_brightness(loaded, FIVE) > 0.06 and _all_meshes_clear_floor(), "Loaded room stays readable and every fixture remains above the floor")
	_finish()


func _cells(area: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			result.append(Vector2i(x, y))
	return result


func _corners(area: Rect2i) -> Array[Vector2i]:
	return [area.position, Vector2i(area.end.x - 1, area.position.y), Vector2i(area.position.x, area.end.y - 1), area.end - Vector2i.ONE]


func _excavate(area: Rect2i) -> void:
	for cell in _cells(area):
		if _context.grid.get_tile(cell) == DungeonGrid.Tile.ROCK:
			_context.grid.set_tile(cell, DungeonGrid.Tile.FLOOR)


func _corners_present(area: Rect2i) -> bool:
	for cell in _corners(area):
		if not _context.infrastructure.lamps.has(cell) or not _context.infrastructure.is_lamp_wall_valid(cell, _context.infrastructure.get_lamp_wall(cell)):
			return false
	return true


func _visible_corner_models(area: Rect2i) -> bool:
	var center := _context.grid.cell_to_world(area.position + Vector2i(area.size.x / 2, area.size.y / 2))
	for cell in _corners(area):
		var lamp := _lights().get_node_or_null("BuiltLamp_%d_%d" % [cell.x, cell.y]) as DungeonLampView
		if lamp == null:
			return false
		var wall := _context.infrastructure.get_lamp_wall(cell)
		var toward := Vector3(wall.x - cell.x, 0, wall.y - cell.y)
		var expected := _context.grid.cell_to_world(cell) + toward * 0.96
		if not lamp.position.is_equal_approx(expected) or lamp.basis.z.dot(-toward) < 0.999 or lamp.basis.z.dot((center - lamp.position).normalized()) <= 0.1:
			return false
	return true


func _all_meshes_clear_floor() -> bool:
	for lamp in _lights().get_children():
		for mesh: MeshInstance3D in lamp.find_children("*", "MeshInstance3D", true, false):
			var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			if bounds.position.y < 0.85:
				return false
	return true


func _room_floor_brightness(picture: Image, area: Rect2i) -> float:
	var sum := 0.0
	var count := 0
	# Off-center samples avoid labels, pigs and the dark middle of each mud decal.
	for cell in _cells(area):
		var world := _context.grid.cell_to_world(cell) + Vector3(0.25, 0.03, 0.20)
		var point: Vector2 = _app.controller.camera.unproject_position(world)
		if point.x < 0 or point.y < 0 or point.x >= picture.get_width() or point.y >= picture.get_height():
			continue
		var color := picture.get_pixelv(Vector2i(point))
		sum += color.get_luminance()
		count += 1
	return sum / maxi(1, count)


func _lights() -> DungeonInfrastructureView:
	return _view.get_node("InfrastructureLights")


func _find_view() -> void:
	for child in _app.get_children():
		if child is DungeonView:
			_view = child


func _camera(cell: Vector2i, distance: float) -> void:
	_app.controller.focus = _context.grid.cell_to_world(cell)
	_app.controller.distance = distance
	_app.controller.pitch = 1.0
	_app.controller.yaw = 0.3
	_app.controller.call("_update_camera")


func _capture(label: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	_check(picture.save_png("res://artifacts/%s.png" % label) == OK, "Capture %s saves" % label)
	return picture


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("ROOM CORNER RENDER: %d checks, %d failures" % [_checks, _failures.size()])
	_app.free()
	quit(0 if _failures.is_empty() else 1)
