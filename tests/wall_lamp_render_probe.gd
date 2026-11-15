extends SceneTree
## Real compact dungeon: wall fixtures leave room floor free and follow excavation.

const STEP := 1.0 / 30.0
const SERVICE := Vector2i(12, 13)
const SUPPORT := Vector2i(12, 12)
const PORTAL := Vector2i(14, 6)
var _app: Node3D
var _context: GameContext
var _view: DungeonView
var _checks := 0
var _failures: Array[String] = []
var _slot := "res://artifacts/wall-lamp-render-%d.json" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


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
	_camera(Vector2i(14, 14), 22.0)
	await _capture("wall-lamps-start")
	var lights := _lights()
	_check(lights.lamp_count == 2 and _context.infrastructure.lamp_walls[SERVICE] == SUPPORT, "Authored starting lights have explicit supporting walls")
	_check(_mounts_correct(lights) and _meshes_above_floor(lights), "All sconces touch their wall face and leave floor-level geometry empty")
	_check(lights.get_node("BuiltLamp_12_13/WallPlate") != null and lights.get_node("BuiltLamp_12_13/Bracket") != null, "Lamp model uses a wall plate and short bracket instead of a floor post")
	_camera(SERVICE, 14.0)
	_app.controller.pitch = 0.80
	_app.controller.call("_update_camera")
	await _capture("wall-lamp-close")
	_camera(Vector2i(14, 14), 22.0)
	_build(&"foundation.lair", SERVICE)
	await _capture("wall-lamps-room")
	_check(_context.rooms.tiles.get(SERVICE) == &"foundation.lair" and _context.infrastructure.lamps.has(SERVICE), "A Lair can occupy the lamp access tile without removing its wall fixture")
	_check(_context.grid.is_walkable(SERVICE), "Wall fixture has no floor occupancy or navigation obstacle")
	# The existing support is dug by actual workers; replacement must be immediate.
	_click(SUPPORT)
	_check(_until(func() -> bool: return _context.grid.get_tile(SUPPORT) == DungeonGrid.Tile.FLOOR, 30.0), "Actual excavation removes a wall supporting a starting lamp")
	_check(not _context.infrastructure.lamps.has(SERVICE) and not _context.infrastructure.lamp_walls.has(SERVICE), "Removing the support removes its old lamp and mount state in the same excavation tick")
	var replacement := Vector2i(-1, -1)
	for service in _context.infrastructure.lamps:
		var path := GridPathfinder.find_path(_context.grid, SUPPORT, service)
		if not path.is_empty() and GridPathfinder.path_cost(path) < DungeonInfrastructure.LAMP_SPACING:
			replacement = service
			break
	_check(replacement != Vector2i(-1, -1) and _context.infrastructure.is_lamp_wall_valid(replacement, _context.infrastructure.get_lamp_wall(replacement)), "Newly excavated floor has a supported nearby replacement light before another simulation tick")
	await _capture("wall-lamp-excavation")
	_check(not _lights().has_node("BuiltLamp_12_13") and _mounts_correct(_lights()), "Rendered old sconce disappears and replacement mounts on remaining solid wall")
	_build(&"foundation.lair", replacement)
	_check(_context.rooms.tiles.get(replacement) == &"foundation.lair" and _context.infrastructure.lamps.has(replacement), "A room can also be built on the replacement light's access tile")
	for y in range(12, 6, -1):
		var cell := Vector2i(14, y)
		_click(cell)
		_check(_until(func() -> bool: return _context.grid.get_tile(cell) == DungeonGrid.Tile.FLOOR, 30.0), "Workers dig the route cell %s" % str(cell))
	_check(_until(func() -> bool: return _context.infrastructure.is_portal_claimed(PORTAL), 30.0), "Wall lighting does not interfere with portal claim work")
	_check(_until(func() -> bool: return _context.actors.size() == 4 and not _context.beds.beds.is_empty() and (_context.beds.beds.values()[0] as BedState).established, 60.0), "A real portal resident reaches and establishes its Lair on the lamp access floor")
	_check(_context.beds.beds.values()[0].anchor in [SERVICE, replacement] and _context.infrastructure.lamps.has(replacement), "A personal bed and wall fixture coexist in the Lair without stealing room capacity")
	_build(&"foundation.pig_pen", Vector2i(15, 13))
	_build(&"foundation.pig_pen", Vector2i(16, 13))
	# Interior floor with no adjacent solid wall must never receive a floor fallback.
	_build(&"foundation.treasury", Vector2i(14, 17))
	await _capture("wall-lamps-living-room")
	_check(not _lights().has_node("RoomLamp_14_17") and _context.rooms.tiles.has(Vector2i(14, 17)), "An unsupported interior room tile receives no free-standing light fallback")
	var installed := _context.infrastructure.lamps.duplicate()
	var supports := _context.infrastructure.lamp_walls.duplicate()
	_context.infrastructure.lamps.clear()
	_context.infrastructure.lamp_walls.clear()
	_context.infrastructure.changed.emit()
	await _capture("wall-lamps-room-fixtures")
	_check(_lights().room_light_count > 0 and _mounts_correct(_lights()) and _meshes_above_floor(_lights()), "Rooms without installed lighting derive supported wall sconces above floor space")
	_check(not _lights().has_node("RoomLamp_14_17"), "Derived room lighting still has no floor fallback in an unsupported interior tile")
	_context.infrastructure.lamps = installed
	_context.infrastructure.lamp_walls = supports
	_context.infrastructure.changed.emit()
	var actor: CreatureState = _context.actors[0]
	_check(_context.keeper.pickup(actor.id) and _context.keeper.pickup_gold(Vector2i(13, 14), 23), "Mixed hand contents remain available with wall lighting")
	var mounts := _context.infrastructure.lamp_walls.duplicate()
	var lamp_cells := _context.infrastructure.lamps.duplicate()
	var save_result: Dictionary = _app.save_game()
	_check(save_result.success, "Actual app saves explicit wall mounts: %s" % save_result.reason)
	_context.infrastructure.lamps.clear()
	_context.infrastructure.lamp_walls.clear()
	_check(_app.load_game().success, "Actual app restores the lit dungeon")
	_context = _app.context
	_app.controller.set_process(false)
	_find_view()
	_camera(Vector2i(14, 13), 23.0)
	var motion := InputEventMouseMotion.new()
	motion.position = _app.controller.camera.unproject_position(_context.grid.cell_to_world(Vector2i(16, 15)))
	root.push_input(motion, true)
	await _capture("wall-lamps-loaded")
	_check(_context.infrastructure.lamps == lamp_cells and _context.infrastructure.lamp_walls == mounts, "Exact fixture access cells and supporting wall faces survive loading")
	_check(_context.keeper.held_count == 2 and _context.keeper.total_held_gold == 23 and _context.keeper.held_actor.id == actor.id, "Saved wall mounts preserve ordered creature/gold custody")
	_check(_mounts_correct(_lights()) and _meshes_above_floor(_lights()), "Fresh loaded presentation retains wall attachment and floor clearance")
	_check(_context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold + _context.economy.gem_gold_created, "Wall-light placement/removal/loading create no gold or resource loss")
	_finish()


func _lights() -> DungeonInfrastructureView:
	return _view.get_node("InfrastructureLights")


func _mounts_correct(lights: DungeonInfrastructureView) -> bool:
	for lamp: DungeonLampView in lights.get_children():
		var service: Vector2i = lamp.get_meta("cell")
		var wall: Vector2i = lamp.get_meta("wall")
		if not _context.infrastructure.is_lamp_wall_valid(service, wall):
			return false
		var toward := Vector3(wall.x - service.x, 0, wall.y - service.y)
		var expected := _context.grid.cell_to_world(service) + toward * 0.96
		if not lamp.position.is_equal_approx(expected) or lamp.basis.z.dot(-toward) < 0.999 or lamp.light.global_position.y > _context.grid.surface_height(wall):
			return false
	return true


func _meshes_above_floor(lights: DungeonInfrastructureView) -> bool:
	for lamp in lights.get_children():
		for mesh: MeshInstance3D in lamp.find_children("*", "MeshInstance3D", true, false):
			var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			if bounds.position.y < 0.85:
				return false
	return true


func _find_view() -> void:
	for child in _app.get_children():
		if child is DungeonView:
			_view = child


func _camera(cell: Vector2i, distance: float) -> void:
	_app.controller.focus = _context.grid.cell_to_world(cell)
	_app.controller.distance = distance
	_app.controller.pitch = 0.95
	_app.controller.yaw = 0.40
	_app.controller.call("_update_camera")


func _build(id: StringName, cell: Vector2i) -> void:
	_app.controller.set_build_room(id)
	_click(cell)
	_app.controller.exit_construction()


func _click(cell: Vector2i) -> void:
	var point: Vector2 = _app.controller.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.exploration.surface_height(cell))
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _until(condition: Callable, seconds: float) -> bool:
	for tick in ceili(seconds / STEP):
		if condition.call():
			return true
		_app.call("_physics_process", STEP)
	return condition.call()


func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	_check(root.get_texture().get_image().save_png("res://artifacts/%s.png" % label) == OK, "Capture %s saves" % label)


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("WALL LAMP RENDER: %d checks, %d failures" % [_checks, _failures.size()])
	_app.free()
	quit(0 if _failures.is_empty() else 1)
