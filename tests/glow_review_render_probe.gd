extends SceneTree
## Independent blend diagnosis on actual dungeon terrain, using isolated materials.

const CELL := Vector2i(19, 14)
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
	keeper.focus = _app.context.grid.cell_to_world(CELL)
	keeper.distance = 18.0
	keeper.pitch = 0.9
	keeper.yaw = 0.2
	keeper.call("_update_camera")
	var pixel := keeper.camera.unproject_position(_app.context.grid.cell_to_world(CELL) + Vector3.UP * (_app.context.grid.surface_height(CELL) + 0.065))
	await _settle()
	var baseline := _sample(pixel)
	context.mark_excavation([CELL])
	var overlay: KeeperSelectionOverlay = keeper.get("_overlay")
	var shell := overlay.marked_frames[CELL].get_node("ExcavationGlow") as MeshInstance3D
	var old_code := "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;\nvoid fragment() { ALBEDO = vec3(1.0, 0.46, 0.07); ALPHA = 0.12; }"
	shell.material_override = _material(old_code)
	await _settle()
	var add_fill := _sample(pixel)
	shell.material_override = _material(old_code.replace("ALPHA = 0.12", "ALPHA = 0.0"))
	await _settle()
	var add_zero := _sample(pixel)
	shell.material_override = _material(old_code.replace("ALPHA = 0.12", "ALPHA = 0.5"))
	await _settle()
	var add_half := _sample(pixel)
	shell.material_override = _material(old_code.replace("blend_add", "blend_mix"))
	await _settle()
	var mix_fill := _sample(pixel)
	print("GLOW BLEND PIXELS baseline=%s add0=%s add.12=%s add.5=%s mix.12=%s" % [baseline, add_zero, add_fill, add_half, mix_fill])
	_check(add_zero.is_equal_approx(baseline), "Zero alpha contributes no additive color on the actual Compatibility renderer")
	_check(add_half.r > add_fill.r and add_fill.r > baseline.r, "Additive face strength increases with alpha")
	# Restore production material and inspect a repeatedly refreshed dense plan.
	shell.material_override = overlay.get("_glow_material")
	var cells: Array[Vector2i] = []
	for y in range(11, 15):
		for x in range(17, 21):
			cells.append(Vector2i(x, y))
	context.mark_excavation(cells, GameContext.MarkOperation.ADD)
	for index in 20:
		overlay.show_marks(cells)
	await _settle()
	_check(overlay.marked_frames.size() == cells.size() and overlay.get_child_count() < cells.size() + 5, "Repeated state refreshes do not accumulate duplicate marked shells")
	var production_fill := _sample(pixel)
	_check(production_fill.r < 0.45 and production_fill.g < 0.3 and production_fill.b < 0.15, "Actual dense-plan face center stays a dark amber tint rather than saturated orange")
	root.get_texture().get_image().save_png("res://artifacts/glow-independent-dense.png")
	for failure in _failures:
		push_error(failure)
	print("GLOW REVIEW RENDER: %d checks, %d failures" % [_checks, _failures.size()])
	_app.free()
	quit(0 if _failures.is_empty() else 1)


func _material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _sample(pixel: Vector2) -> Color:
	return root.get_texture().get_image().get_pixelv(Vector2i(pixel))


func _settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
