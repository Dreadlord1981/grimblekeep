extends SceneTree
## Loads the actual composition root and sends input through Godot's viewport.

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _run() -> void:
	var scene := load("res://scenes/dungeon.tscn") as PackedScene
	var app := scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var keeper: KeeperController = app.controller
	var context: GameContext = app.context
	_check(context != null and context.actors.size() == 3, "Composition root starts 3 actors")
	_check(keeper.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Perspective projection active")
	_check(keeper.camera.is_current(), "Keeper camera active")
	var initial_distance := keeper.distance
	# Dispatch a mouse wheel input through the viewport (no OS/UI automation).
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(640, 350)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.push_input(wheel, true)
	await process_frame
	_check(keeper.distance < initial_distance, "Viewport wheel zooms camera")
	var click := InputEventMouseButton.new()
	click.position = keeper.camera.unproject_position(context.grid.cell_to_world(Vector2i(8, 12)) + Vector3.UP * context.grid.surface_height(Vector2i(8, 12)))
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame
	_check(context.last_marked_cell != KeeperController.INVALID_CELL, "World click marks rock for excavation")
	var selected := context.last_marked_cell
	# Header panel must consume a click before world input sees it.
	click.position = Vector2(80, 30)
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame
	_check(context.last_marked_cell == selected, "Header click leaves world selection unchanged")
	click.position = Vector2(100, root.size.y - 35)
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame
	_check(context.last_marked_cell == selected, "Footer click leaves world selection unchanged")
	keeper.yaw = 1.5
	keeper.pitch = 0.4
	keeper.distance = 18.0
	var home := InputEventKey.new()
	home.keycode = KEY_HOME
	home.pressed = true
	root.push_input(home, true)
	await process_frame
	_check(is_equal_approx(keeper.distance, 31.0) and is_equal_approx(keeper.pitch, 0.9), "Home restores overview")
	_check(keeper.focus == context.grid.cell_to_world(Vector2i(14, 15)), "Home centers on Heart")
	var starts: Array[Vector3] = []
	for actor in context.actors:
		starts.append(actor.position)
	for i in 90:
		await physics_frame
	var moved := false
	for index in context.actors.size():
		moved = moved or context.actors[index].position.distance_to(starts[index]) > 0.1
	_check(moved, "Actual scene workers respond to the marked excavation tile")
	for failure in _failures:
		push_error(failure)
	print("INTEGRATION RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	app.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
