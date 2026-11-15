extends SceneTree
## Headless input regression probe. Routes synthetic events through the Viewport.
## This verifies engine event routing, not physical mouse/OS automation.

var _checks := 0
var _failures := 0
var _controller: KeeperController
var _context: GameContext


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := DungeonGrid.new(7, 7)
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.ROCK)
	_context = GameContext.new(grid, null)
	_controller = KeeperController.new()
	root.add_child(_controller)
	_controller.setup(_context)
	_controller.set_process(false)
	_controller.camera.position = Vector3(6, 20, 10)
	_controller.camera.look_at(Vector3(6, 0, 6))
	var hud := DungeonHUD.new()
	root.add_child(hud)
	hud.setup(_context, _controller)
	await process_frame
	await process_frame
	_click(Vector2i(2, 2))
	_check(_context.excavation_marks.size() == 1, "Click selects one tile")
	_click(Vector2i(2, 2))
	_check(_context.excavation_marks.is_empty(), "Repeat click deselects tile")
	_drag(Vector2i(1, 1), Vector2i(3, 2))
	_check(_context.excavation_marks.size() == 6, "Drag toggles inclusive six-tile rectangle")
	_drag(Vector2i(1, 1), Vector2i(3, 2))
	_check(_context.excavation_marks.is_empty(), "Repeat drag deselects rectangle")
	_click(Vector2i(5, 5))
	_drag(Vector2i(1, 1), Vector2i(3, 2))
	_check(_context.excavation_marks.size() == 7 and _context.excavation_marks.has(Vector2i(5, 5)), "Drag preserves selection outside rectangle")
	_drag(Vector2i(1, 1), Vector2i(3, 2), true)
	_check(_context.excavation_marks.size() == 7, "Shift drag adds without toggling existing tiles")
	_drag(Vector2i(1, 1), Vector2i(3, 2), false, true)
	_check(_context.excavation_marks.size() == 1 and _context.excavation_marks.has(Vector2i(5, 5)), "Ctrl drag removes only rectangle")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	root.push_input(escape, true)
	_check(_context.excavation_marks.is_empty(), "Escape clears selection")
	var world := _screen(Vector2i(2, 2))
	var footer := Vector2(root.size.x * 0.5, root.size.y - 40)
	_mouse(footer, true)
	_mouse(world, false)
	_check(_context.excavation_marks.is_empty(), "UI press followed by world release never selects")
	_mouse(world, true)
	_mouse(footer, false)
	_check(_context.excavation_marks.is_empty(), "World press followed by UI release cancels drag")
	_check(_controller.get("_drag_start") == KeeperController.INVALID_CELL, "UI release clears pending drag")
	_mouse(world, false)
	_check(_context.excavation_marks.is_empty(), "Stale release cannot commit cancelled drag")
	_click(Vector2i(2, 2))
	_check(_context.excavation_marks.size() == 1, "World selection still works after UI crossing")
	_test_excavation_and_preview(grid)
	print("INPUT SELECTION: %d checks, %d failures" % [_checks, _failures])
	hud.queue_free()
	_controller.queue_free()
	quit(1 if _failures else 0)


func _test_excavation_and_preview(grid: DungeonGrid) -> void:
	_context.clear_excavation_marks()
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(2, 2), DungeonGrid.Tile.ROCK)
	grid.set_tile(Vector2i(3, 2), DungeonGrid.Tile.GOLD)
	grid.set_tile(Vector2i(4, 2), DungeonGrid.Tile.HEART)
	grid.set_tile(Vector2i(5, 2), DungeonGrid.Tile.PORTAL)

	_click(Vector2i(1, 1))
	_check(_context.excavation_marks.is_empty(), "Dig click cannot mark open ground")
	_click(Vector2i(4, 2))
	_click(Vector2i(5, 2))
	_check(_context.excavation_marks.is_empty(), "Dig click cannot mark Heart or portal")
	_mouse(_screen(Vector2i(1, 1)), true)
	_motion(Vector2i(3, 2))
	var changes := _controller.get_preview_changes()
	_check(changes.add.size() == 2 and changes.remove.is_empty(), "Mixed-terrain drag preview includes only rock and gold")
	_mouse(_screen(Vector2i(3, 2)), false)
	_check(_context.excavation_marks.size() == 2, "Dig rectangle skips open ground")
	_motion(Vector2i(2, 2))
	changes = _controller.get_preview_changes()
	_check(changes.remove == [Vector2i(2, 2)] and changes.add.is_empty(), "Hover over marked rock previews removal")
	_click(Vector2i(2, 2))
	_check(not _context.excavation_marks.has(Vector2i(2, 2)), "Repeated Dig click unmarks rock")
	_mouse(_screen(Vector2i(2, 2)), true)
	_motion(Vector2i(3, 2))
	changes = _controller.get_preview_changes()
	_check(changes.add == [Vector2i(2, 2)] and changes.remove == [Vector2i(3, 2)], "Mixed rectangle previews one addition and one removal")
	_mouse(_screen(Vector2i(3, 2)), false)
	_check(_context.excavation_marks.has(Vector2i(2, 2)) and not _context.excavation_marks.has(Vector2i(3, 2)), "Committed delta matches mixed preview")
	_mouse(_screen(Vector2i(2, 2)), true, true)
	changes = _controller.get_preview_changes()
	_check(changes.add.is_empty() and changes.remove.is_empty(), "Add-only over marked tile previews no change")
	_mouse(_screen(Vector2i(2, 2)), false, true)
	_check(_context.excavation_marks.has(Vector2i(2, 2)), "Add-only release preserves marked tile")
	_mouse(_screen(Vector2i(3, 2)), true, false, true)
	changes = _controller.get_preview_changes()
	_check(changes.add.is_empty() and changes.remove.is_empty(), "Remove-only over unmarked tile previews no change")
	_mouse(_screen(Vector2i(3, 2)), false, false, true)
	_check(not _context.excavation_marks.has(Vector2i(3, 2)), "Remove-only release preserves unmarked tile")
	_motion(Vector2i(2, 2))
	_key(KEY_SHIFT, true, false)
	changes = _controller.get_preview_changes()
	_check(changes.remove.is_empty(), "Stationary Shift press updates hover preview")
	_key(KEY_SHIFT, false, false, false)
	var before := _context.excavation_marks.duplicate()
	_key(KEY_H)
	_key(KEY_B)
	_check(_context.excavation_marks == before, "Old mode shortcuts never clear excavation marks")
	grid.set_tile(Vector2i(3, 2), DungeonGrid.Tile.GEM)
	_click(Vector2i(3, 2))
	_check(_context.excavation_marks.has(Vector2i(3, 2)), "Default keeper hand marks gem terrain without a mode switch")
	var gem_count := _context.excavation_marks.size()
	_click(Vector2i(1, 1))
	_check(_context.excavation_marks.size() == gem_count, "Ground click never creates a general selection")
	grid.set_tile(Vector2i(2, 3), DungeonGrid.Tile.ROCK)
	_motion(Vector2i(2, 3))
	_check(_controller.get_preview_changes().add == [Vector2i(2, 3)], "Unmarked hovered rock previews marking")
	grid.set_tile(Vector2i(2, 3), DungeonGrid.Tile.FLOOR)
	_check(_controller.get_preview_changes().add.is_empty(), "Terrain change invalidates stationary excavation preview immediately")


func _motion(cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _screen(cell)
	root.push_input(event, true)


func _key(code: Key, shift: bool = false, ctrl: bool = false, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	root.push_input(event, true)


func _screen(cell: Vector2i) -> Vector2:
	return _controller.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.grid.surface_height(cell))


func _mouse(screen: Vector2, pressed: bool, shift: bool = false, ctrl: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	root.push_input(event, true)


func _click(cell: Vector2i) -> void:
	_mouse(_screen(cell), true)
	_mouse(_screen(cell), false)


func _drag(first: Vector2i, last: Vector2i, shift: bool = false, ctrl: bool = false) -> void:
	_mouse(_screen(first), true, shift, ctrl)
	var motion := InputEventMouseMotion.new()
	motion.position = _screen(last)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_mouse(_screen(last), false, shift, ctrl)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
