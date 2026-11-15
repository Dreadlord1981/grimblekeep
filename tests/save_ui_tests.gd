extends SceneTree
## Desktop save/load intents use real Viewport input and preserve world custody.

var _checks := 0
var _failures: Array[String] = []
var _context: GameContext
var _controller: KeeperController
var _hud: DungeonHUD
var _save_count := 0
var _load_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	_fixture()
	await process_frame
	await process_frame
	var panel: Control = _hud.get("_save_panel")
	var save_button: Button = _hud.get("_save_button")
	var load_button: Button = _hud.get("_load_button")
	var status: Label = _hud.get("_save_status")
	_check(panel.is_visible_in_tree() and save_button.visible and load_button.visible, "Save/load are available without opening diagnostics")
	_check(panel.get_global_rect().position.y >= 70 and panel.get_global_rect().end.x <= 1264 and panel.get_global_rect().end.y < 125, "Save controls fit below the header at 1280x800")
	_check(save_button.get_global_rect().end.x < load_button.get_global_rect().position.x and load_button.get_global_rect().end.x < status.get_global_rect().position.x, "Controls and feedback do not overlap")
	_check("F5" in save_button.text and "F9" in load_button.text, "Save/load buttons advertise desktop shortcuts")
	_check("dungeon.json" in save_button.tooltip_text and "Unsaved changes" in load_button.tooltip_text, "Tooltips explain the manual slot and replacement behavior")
	_click(save_button.get_global_rect().get_center())
	_click(load_button.get_global_rect().get_center())
	_check(_save_count == 1 and _load_count == 1, "Real button clicks emit exactly one corresponding intent")
	_check(_context.excavation_marks.size() == 1 and not _controller.is_constructing(), "Save/load clicks do not mark terrain or change construction mode")
	_key(KEY_F5)
	_key(KEY_F9)
	_check(_save_count == 2 and _load_count == 2, "F5 and F9 emit the corresponding save/load intent")
	_key(KEY_F5, true)
	_key(KEY_F9, true)
	_check(_save_count == 2 and _load_count == 2, "Key repeat does not repeatedly save or load")
	for modifier in ["ctrl_pressed", "alt_pressed", "meta_pressed", "shift_pressed"]:
		_key(KEY_F5, false, modifier)
		_key(KEY_F9, false, modifier)
	_check(_save_count == 2 and _load_count == 2, "Modified function keys do not trigger manual save/load")
	var edit := LineEdit.new()
	edit.position = Vector2(950, 120)
	_hud.get("_root").add_child(edit)
	edit.grab_focus()
	_key(KEY_F5)
	_key(KEY_F9)
	_check(_save_count == 2 and _load_count == 2, "Name text editing suppresses save/load shortcuts")
	edit.release_focus()
	var multiline := TextEdit.new()
	multiline.position = Vector2(950, 150)
	_hud.get("_root").add_child(multiline)
	multiline.grab_focus()
	_key(KEY_F5)
	_key(KEY_F9)
	_check(_save_count == 2 and _load_count == 2, "Multiline text editing also suppresses save/load shortcuts")
	multiline.release_focus()
	_key(KEY_F5)
	_key(KEY_F9)
	_check(_save_count == 3 and _load_count == 3, "Shortcuts work again after leaving text editing")
	_hud.set_save_path("user://test-slot/custom.json")
	_check("custom.json" in save_button.tooltip_text and "custom.json" in load_button.tooltip_text, "The app can supply a different save path without UI backend coupling")
	_hud.show_save_result("Dungeon saved", true)
	_check(status.text == "Dungeon saved" and status.is_visible_in_tree() and "custom.json" in status.tooltip_text, "Successful save feedback is immediately visible with the slot location")
	var success_color := status.get_theme_color("font_color")
	var long_error := "Could not load dungeon: this save uses unknown creature content and the current dungeon remains unchanged."
	_hud.show_save_result(long_error, false)
	_check(status.text == long_error and long_error in status.tooltip_text and status.get_theme_color("font_color") != success_color, "Failure feedback retains its complete message and distinct color")
	await process_frame
	_check(panel.get_global_rect().end.x <= 1264 and status.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Long errors remain bounded and available through their full tooltip")
	var actor := _context.actors[0]
	_context.keeper.pickup(actor.id)
	_context.economy.drop_gold(Vector2i(4, 4), 81)
	_context.economy.initial_gold += 81
	_context.keeper.pickup_gold(Vector2i(4, 4))
	var entries := _context.keeper.get_items()
	_click(save_button.get_global_rect().get_center())
	_right_click(load_button.get_global_rect().get_center())
	_right_click(status.get_global_rect().get_center())
	_check(_save_count == 4 and _load_count == 3, "Save remains clickable while holding; right-click never invokes Load")
	_check(_context.keeper.held_count == 2 and _context.keeper.peek_item() == entries[0] and actor.is_held and _context.economy.keeper_gold == 81, "UI interaction cannot release or reorder mixed hand contents")
	_check(_context.excavation_marks.size() == 1 and _controller.get("_drag_start") == KeeperController.INVALID_CELL, "Save controls never leave a terrain drag behind")
	_check(_controller.is_pointer_over_ui(status.get_global_rect().get_center()), "Feedback text participates in authoritative UI hit testing")
	_key(KEY_F3)
	await process_frame
	var debug: Control = _hud.get("_debug_panel")
	_check(debug.visible and debug.get_global_rect().position.y >= panel.get_global_rect().end.y, "Diagnostics remain accessible without obscuring save controls")
	for failure in _failures:
		push_error(failure)
	print("SAVE UI RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_hud.queue_free()
	_controller.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _fixture() -> void:
	var registry := ContentRegistry.new()
	registry.register_module(load("res://content/modules/foundation.tres"))
	var grid := DungeonGrid.new(12, 12)
	for y in range(1, 11):
		for x in range(1, 11):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(6, 6), DungeonGrid.Tile.HEART)
	_context = GameContext.new(grid, registry)
	_context.spawn_creature(&"foundation.imp", Vector2i(5, 5))
	_context.mark_excavation([Vector2i(0, 0)])
	_controller = KeeperController.new()
	root.add_child(_controller)
	_controller.setup(_context)
	_controller.set_process(false)
	_hud = DungeonHUD.new()
	root.add_child(_hud)
	_hud.setup(_context, _controller)
	_hud.save_requested.connect(func(): _save_count += 1)
	_hud.load_requested.connect(func(): _load_count += 1)


func _key(code: Key, repeated: bool = false, modifier: String = "") -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = repeated
	if not modifier.is_empty():
		event.set(modifier, true)
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	root.push_input(event, true)


func _click(point: Vector2) -> void:
	_mouse(point, MOUSE_BUTTON_LEFT)


func _right_click(point: Vector2) -> void:
	_mouse(point, MOUSE_BUTTON_RIGHT)


func _mouse(point: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
