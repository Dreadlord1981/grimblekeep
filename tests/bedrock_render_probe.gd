extends SceneTree
## Actual scene evidence for raised indestructible borders and internal bedrock.

var _app: Node3D
var _context: GameContext
var _keeper: KeeperController
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _run() -> void:
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(_app)
	_app.set_physics_process(false)
	_context = _app.context
	_keeper = _app.controller
	_keeper.set_process(false)
	_camera(Vector2i(13, 13), 62.0, 0.35, 1.15)
	await _capture("bedrock-wide")
	var cells := _context.grid.cells_of_type(DungeonGrid.Tile.BEDROCK)
	var core := _app.find_child("BedrockCore", true, false) as MultiMeshInstance3D
	_check(core != null and core.multimesh.instance_count == cells.size(), "Every authoritative bedrock tile has one raised batched body")
	var crowns := _app.find_child("BedrockCrowns", true, false) as MultiMeshInstance3D
	var height_matches := crowns != null and crowns.multimesh.instance_count == cells.size()
	if height_matches:
		for index in crowns.multimesh.instance_count:
			var transform := crowns.multimesh.get_instance_transform(index)
			var cell := _context.grid.world_to_cell(transform.origin)
			var top := transform.origin.y + transform.basis.y.length() * 0.5
			height_matches = height_matches and is_equal_approx(top, _context.grid.surface_height(cell))
	_check(height_matches, "Rendered flat crowns match picking surface for every border/internal bedrock tile")
	_camera(Vector2i(3, 10), 16.0, 0.4, 0.85)
	await _capture("bedrock-internal")
	var bedrock := Vector2i(3, 10)
	var neighbor := Vector2i(4, 10)
	var at := _screen(bedrock)
	_check(_keeper.get_target_cell(at) == bedrock, "Perspective targeting hits raised bedrock rather than floor behind it")
	_mouse(at, true)
	_mouse(at, false)
	await _capture("bedrock-blocked-target")
	var quote := _keeper.get_preview_changes()
	_check(_context.excavation_marks.is_empty() and bedrock in quote.get("blocked", []), "Bedrock click gives blocked preview without an excavation mark")
	_mouse(at, true)
	var motion := InputEventMouseMotion.new()
	motion.position = _screen(neighbor)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_mouse(motion.position, false)
	await _capture("bedrock-mixed-selection")
	_check(not _context.excavation_marks.has(bedrock) and _context.excavation_marks.has(neighbor), "Mixed area selection marks adjacent ordinary rock while excluding bedrock")
	_check(_context.grid.get_tile(bedrock) == DungeonGrid.Tile.BEDROCK, "Selection leaves bedrock terrain unchanged")
	_context.clear_excavation_marks()
	# A trusted test-only observation aisle reveals the layered side treatment.
	# It does not replace any bedrock and exercises live terrain view rebuilding.
	for cell in [Vector2i(4, 9), Vector2i(4, 10), Vector2i(4, 11), Vector2i(4, 12), Vector2i(3, 12), Vector2i(2, 12)]:
		_context.grid.set_tile(cell, DungeonGrid.Tile.FLOOR)
	_camera(Vector2i(3, 11), 11.0, 0.7, 0.50)
	await _capture("bedrock-strata-close")
	_check(_context.grid.cells_of_type(DungeonGrid.Tile.BEDROCK).size() == cells.size(), "Nearby excavation preserves all border/internal bedrock")
	var strata := _app.find_child("BedrockStrata", true, false) as MultiMeshInstance3D
	_check(strata != null and strata.multimesh.instance_count == cells.size() * 3, "Live terrain rebuild retains three distinct strata bands per bedrock tile")
	# Surface-hit checks at the scenario border as well as the internal pattern.
	_camera(Vector2i(0, 14), 15.0, 0.6, 1.0)
	_check(_keeper.get_target_cell(_screen(Vector2i(0, 14))) == Vector2i(0, 14), "Raised map border is pickable at its own surface")
	await _capture("bedrock-border-close")
	for failure in _failures:
		push_error(failure)
	print("BEDROCK RENDER RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_app.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _screen(cell: Vector2i) -> Vector2:
	return _keeper.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.grid.surface_height(cell))


func _camera(cell: Vector2i, distance: float, yaw: float, pitch: float) -> void:
	_keeper.focus = _context.grid.cell_to_world(cell)
	_keeper.distance = distance
	_keeper.yaw = yaw
	_keeper.pitch = pitch
	_keeper.call("_update_camera")


func _mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _capture(label: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := root.get_texture().get_image().save_png("res://artifacts/%s.png" % label)
	_check(error == OK, "Capture %s saves successfully" % label)
