extends SceneTree
## Visual evidence for a mixed add/remove excavation preview in the real scene.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var controller: KeeperController = app.controller
	controller.focus = app.context.grid.cell_to_world(Vector2i(20, 17))
	controller.yaw = 0.15
	controller.pitch = 0.95
	controller.distance = 20.0
	controller.call("_update_camera")
	controller.set_process(false)
	var marked: Array[Vector2i] = [Vector2i(20, 17), Vector2i(21, 17)]
	app.context.mark_excavation(marked, GameContext.MarkOperation.ADD)
	var first := Vector2i(20, 16)
	var last := Vector2i(22, 18)
	var press := InputEventMouseButton.new()
	press.position = _screen(app, first)
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = _screen(app, last)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	controller.set_process_input(false)
	controller.set_process_unhandled_input(false)
	var changes := controller.get_preview_changes()
	var valid: bool = changes.add.size() == 7 and changes.remove.size() == 2
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := root.get_texture().get_image().save_png("res://artifacts/selection-preview.png")
	print("SELECTION RENDER: add=%d remove=%d capture=%s" % [changes.add.size(), changes.remove.size(), error_string(error)])
	if not valid:
		push_error("Expected seven new marks and two removals in visual preview fixture")
	# Clear the live drag but retain marks; inspect glow where a wall faces open floor.
	controller.call("_cancel_drag")
	app.context.hovered_cell = KeeperController.INVALID_CELL
	controller.call("_refresh_preview")
	var glow_cells: Array[Vector2i] = [Vector2i(8, 17), Vector2i(8, 18), Vector2i(8, 19)]
	app.context.mark_excavation(glow_cells, GameContext.MarkOperation.REPLACE)
	controller.focus = app.context.grid.cell_to_world(Vector2i(8, 18))
	controller.yaw = 1.1
	controller.pitch = 0.95
	controller.distance = 14.0
	controller.call("_update_camera")
	await process_frame
	await RenderingServer.frame_post_draw
	var top_error := root.get_texture().get_image().save_png("res://artifacts/excavation-glow-top.png")
	controller.pitch = 0.38
	controller.distance = 11.5
	controller.call("_update_camera")
	await process_frame
	await RenderingServer.frame_post_draw
	var side_error := root.get_texture().get_image().save_png("res://artifacts/excavation-glow-side.png")
	print("EXCAVATION GLOW: top=%s sides=%s" % [error_string(top_error), error_string(side_error)])
	app.queue_free()
	await process_frame
	quit(0 if valid and error == OK and top_error == OK and side_error == OK else 1)


func _screen(app: Node, cell: Vector2i) -> Vector2:
	return app.controller.camera.unproject_position(app.context.grid.cell_to_world(cell) + Vector3.UP * app.context.grid.surface_height(cell))
