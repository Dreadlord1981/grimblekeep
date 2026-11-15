extends SceneTree
## Pixel-level regression for saturated opaque excavation overlays in Compatibility.

var _app: Node3D
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(_app)
	_app.set_physics_process(false)
	var context: GameContext = _app.context
	var keeper: KeeperController = _app.controller
	keeper.set_process(false)
	keeper.focus = context.grid.cell_to_world(Vector2i(18, 15))
	keeper.distance = 25.0
	keeper.pitch = 1.0
	keeper.yaw = 0.30
	keeper.call("_update_camera")
	var cells: Array[Vector2i] = []
	for y in range(13, 17):
		for x in range(18, 22):
			cells.append(Vector2i(x, y))
	var baseline := await _capture("glow-unmarked")
	context.mark_excavation(cells)
	var marked := await _capture("glow-marked")
	_check(context.excavation_marks.size() == 16, "Dense four-row area stays marked")
	var samples: Array = []
	for cell in cells:
		var point: Vector2 = keeper.camera.unproject_position(context.grid.cell_to_world(cell) + Vector3.UP * (context.grid.surface_height(cell) + 0.06))
		var original := baseline.get_pixelv(Vector2i(point))
		var selected := marked.get_pixelv(Vector2i(point))
		samples.append([cell.x, cell.y, original.r, selected.r, selected.g, selected.b])
		_check(selected.r > original.r + 0.015 and selected.r < original.r + 0.07, "Marked top keeps its original shading with a faint amber tint (%s: %.3f -> %.3f)" % [str(cell), original.r, selected.r])
	for phase in 3:
		for frame in 30:
			await process_frame
		var pulse := await _capture("glow-pulse-%d" % phase)
		var bounded := true
		for cell in cells:
			var point: Vector2 = keeper.camera.unproject_position(context.grid.cell_to_world(cell) + Vector3.UP * (context.grid.surface_height(cell) + 0.06))
			bounded = bounded and pulse.get_pixelv(Vector2i(point)).r < baseline.get_pixelv(Vector2i(point)).r + 0.07
		_check(bounded, "Dense marked faces remain faint across glow pulse %d" % phase)
	for failure in _failures:
		push_error(failure)
	print("EXCAVATION GLOW RENDER: %d checks, %d failures" % [_checks, _failures.size()])
	_app.free()
	quit(0 if _failures.is_empty() else 1)


func _capture(label: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	picture.save_png("res://artifacts/%s.png" % label)
	return picture


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)
