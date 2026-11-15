class_name DungeonHUD
extends CanvasLayer
## Desktop HUD observes authoritative economy and worker state; never assigns jobs.

const HandScript = preload("res://ui/keeper_hand.gd")
const INK := Color(0.82, 0.78, 0.67)
const MUTED := Color(0.50, 0.53, 0.51)
const ACCENT := Color(0.70, 0.54, 0.29)

var context: GameContext
var controller: KeeperController
var _marks: Label
var _controls_hint: Label
var _construction_buttons: Dictionary[StringName, Button] = {}
var _sell_button: Button
var _return_button: Button
var _action_feedback: Label
var _feedback_remaining := 0.0
var _debug: Label
var _debug_panel: PanelContainer
var _root: Control
var _input_panels: Array[Control] = []
var _stored_gold: Label
var _gold_in_transit: Label
var _worker_count: Label
var _worker_roster: VBoxContainer
var _worker_rows: Dictionary[int, Label] = {}
var _refresh_in := 0.0


func setup(game_context: GameContext, keeper: KeeperController) -> void:
	context = game_context
	controller = keeper
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_header()
	_build_footer()
	_build_debug()
	_build_workers()
	controller.ui_hit_test = _is_ui_position
	var hand := HandScript.new() as KeeperHand
	hand.controller = controller
	_root.add_child(hand)
	context.excavation_marks_changed.connect(_refresh_marks)
	controller.preview_changed.connect(_refresh_preview)
	controller.construction_changed.connect(_refresh_construction)
	controller.room_action_finished.connect(_show_room_result)
	_refresh_marks(context.last_marked_cell)
	_refresh_economy_and_workers()


func _process(delta: float) -> void:
	if _feedback_remaining > 0.0:
		_feedback_remaining -= delta
		if _feedback_remaining <= 0.0:
			_action_feedback.text = "Build rooms on excavated floor"
			_action_feedback.add_theme_color_override("font_color", MUTED)
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = 0.15
		_refresh_economy_and_workers()
	if _debug_panel != null and _debug_panel.visible:
		_debug.text = "DIAGNOSTICS\nFPS  %d     ACTORS  %d\nTARGET  %s\nCAMERA  %.1f m\nCONTENT  modular definitions" % [Engine.get_frames_per_second(), context.actors.size(), str(context.hovered_cell), controller.distance]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_debug_panel.visible = not _debug_panel.visible
		get_viewport().set_input_as_handled()


func _build_header() -> void:
	var panel := _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 14
	panel.offset_bottom = 64
	_root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var title := _label("G R I M B L E K E E P", 20, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_stored_gold = _label("STORED GOLD   0", 16, Color(0.78, 0.64, 0.33))
	_stored_gold.tooltip_text = "Spendable gold deposited in the treasury. Gold carried by workers or lying on the ground is not spendable yet."
	_stored_gold.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_stored_gold)
	_gold_in_transit = _label("Carried 0  /  Ground 0", 13, MUTED)
	row.add_child(_gold_in_transit)
	row.add_child(_label("FOOD   0", 16, INK))
	_worker_count = _label("WORKERS   0", 16, INK)
	row.add_child(_worker_count)
	var home := Button.new()
	home.text = "Heart  [Home]"
	home.focus_mode = Control.FOCUS_NONE
	home.add_theme_color_override("font_color", INK)
	home.pressed.connect(controller.recenter)
	row.add_child(home)


func _build_footer() -> void:
	var panel := _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = -141
	panel.offset_bottom = -16
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	_build_construction_bar(column)
	_marks = _label("KEEPER HAND  /  Click or drag rock, gold or gems to mark excavation", 16, INK)
	_marks.add_theme_font_size_override("font_size", 14)
	_marks.clip_text = true
	column.add_child(_marks)
	_controls_hint = _label("", 12, INK)
	column.add_child(_controls_hint)
	column.add_child(_label("WASD / arrows  Pan    ·    RMB / Q E  Orbit    ·    MMB  Pan    ·    Wheel  Zoom    ·    Home  Heart    ·    F3  Diagnostics", 12, MUTED))
	_refresh_construction()


func _build_construction_bar(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	row.add_child(_label("ROOMS", 13, MUTED))
	if context.registry != null:
		for definition in context.registry.get_rooms():
			if not definition.buildable:
				continue
			var button := _tool_button("%s  ·  %d gold / tile" % [definition.display_name, definition.gold_cost_per_tile])
			button.tooltip_text = "Build on empty excavated floor. Drag to place several tiles."
			button.pressed.connect(controller.set_build_room.bind(definition.id))
			row.add_child(button)
			_construction_buttons[definition.id] = button
	_sell_button = _tool_button("Sell rooms")
	_sell_button.tooltip_text = "Select Sell, then click or drag existing room tiles. Treasury tiles refund 50% of their build cost. Stored gold on sold tiles falls onto the floor; the preview shows the exact refund."
	_sell_button.pressed.connect(controller.set_sell_rooms)
	row.add_child(_sell_button)
	_return_button = _tool_button("Done  [Esc]")
	_return_button.pressed.connect(controller.exit_construction)
	row.add_child(_return_button)
	_action_feedback = _label("Build rooms on excavated floor", 12, MUTED)
	_action_feedback.clip_text = true
	_action_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_action_feedback)


func _tool_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_pressed_color", Color(0.98, 0.79, 0.40))
	button.add_theme_font_size_override("font_size", 13)
	return button


func _refresh_construction() -> void:
	for id in _construction_buttons:
		_construction_buttons[id].set_pressed_no_signal(controller.build_room_id == id)
	if _sell_button != null:
		_sell_button.set_pressed_no_signal(controller.removing_rooms)
	if _return_button != null:
		_return_button.visible = controller.is_constructing()
		_return_button.set_pressed_no_signal(false)
	if _controls_hint != null:
		if controller.build_room_id != &"":
			_controls_hint.text = "Click / drag  Place on empty excavated floor    ·    Green +  Build    ·    Red X  Blocked    ·    Esc / Done  Return to excavation"
		elif controller.removing_rooms:
			_controls_hint.text = "Click / drag  Sell room tiles    ·    Red X  Sell    ·    Esc / Done  Return to excavation"
		else:
			_controls_hint.text = "Click / drag  Toggle excavation    ·    Green +  Mark    ·    Red X  Unmark    ·    Shift  Mark only    ·    Ctrl  Unmark only    ·    Esc  Clear"
	if _marks != null:
		_refresh_preview(controller.get_preview_changes())


func _show_room_result(result: Dictionary) -> void:
	_feedback_remaining = 4.0
	var success: bool = result.get("success", false)
	if success:
		var count: int = result.get("remove", []).size() if controller.removing_rooms else result.get("add", []).size()
		_action_feedback.text = "%d room tiles sold · %d gold refunded" % [count, result.get("refund", 0)] if controller.removing_rooms else "%d room tiles built · %d gold spent" % [count, result.get("cost", 0)]
	else:
		_action_feedback.text = result.get("reason", "Cannot change these tiles")
	_action_feedback.tooltip_text = _action_feedback.text
	_action_feedback.add_theme_color_override("font_color", INK if success else Color(0.97, 0.48, 0.36))


func _build_debug() -> void:
	_debug_panel = _panel()
	_debug_panel.position = Vector2(16, 78)
	_debug_panel.visible = false
	_root.add_child(_debug_panel)
	_debug = _label("DIAGNOSTICS", 14, INK)
	_debug_panel.add_child(_debug)


func _build_workers() -> void:
	var panel := _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -285
	panel.offset_right = -16
	panel.offset_top = 78
	_root.add_child(panel)
	_worker_roster = VBoxContainer.new()
	_worker_roster.add_theme_constant_override("separation", 10)
	panel.add_child(_worker_roster)
	_worker_roster.add_child(_label("ACTIVE WORKERS", 14, INK))
	var help := _label("Jobs are assigned automatically", 12, MUTED)
	help.tooltip_text = "Workers dig marked terrain and haul gold. Cancel an excavation mark to stop that digging job."
	help.mouse_filter = Control.MOUSE_FILTER_PASS
	_worker_roster.add_child(help)


func _refresh_economy_and_workers() -> void:
	if context == null or _stored_gold == null:
		return
	var carried := 0
	var ground := 0
	var visible_workers: Dictionary[int, bool] = {}
	for actor in context.actors:
		carried += actor.carried_gold
		var definition: CreatureDefinition = context.registry.get_creature(actor.definition_id) if context.registry != null else null
		if definition == null or not (&"excavate" in definition.capabilities or &"haul" in definition.capabilities):
			continue
		visible_workers[actor.id] = true
		if not _worker_rows.has(actor.id):
			var row := _label("", 13, INK)
			row.custom_minimum_size.x = 242
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_worker_roster.add_child(row)
			_worker_rows[actor.id] = row
		var label: Label = _worker_rows[actor.id]
		var job: String = actor.job_label if not actor.job_label.is_empty() else "Awaiting reachable work"
		label.text = "%s #%d  /  %s\n%s" % [definition.display_name, actor.id, String(actor.action).to_upper(), job]
		if actor.carried_gold > 0:
			label.text += "  ·  Carrying %d gold" % actor.carried_gold
	for actor_id in _worker_rows.keys():
		if not visible_workers.has(actor_id):
			_worker_rows[actor_id].queue_free()
			_worker_rows.erase(actor_id)
	if context.economy != null:
		for amount in context.economy.ground_gold.values():
			ground += amount
		var capacity: int = context.economy.treasury_capacity
		_stored_gold.text = "GOLD   %d / %d" % [context.economy.stored_gold, capacity] if capacity >= 0 else "STORED GOLD   %d" % context.economy.stored_gold
	_gold_in_transit.text = "Carried %d  /  Ground %d" % [carried, ground]
	_worker_count.text = "WORKERS   %d" % visible_workers.size()


func _refresh_marks(_cell: Vector2i) -> void:
	_refresh_preview(controller.get_preview_changes())


func _refresh_preview(changes: Dictionary) -> void:
	if controller.is_constructing():
		var valid: bool = changes.get("valid", false)
		var reason: String = changes.get("reason", "")
		var blocked: int = changes.get("blocked", []).size()
		if controller.removing_rooms:
			_marks.text = "SELL ROOMS   |   %d tiles   |   Refund %d gold   |   %s" % [changes.get("remove", []).size(), changes.get("refund", 0), reason]
		else:
			var definition := context.registry.get_room(controller.build_room_id)
			_marks.text = "BUILD %s   |   %d tiles   |   Cost %d gold   |   %s" % [definition.display_name.to_upper(), changes.get("add", []).size(), changes.get("cost", 0), reason]
		if blocked > 0:
			_marks.text += "   |   %d blocked" % blocked
		_marks.add_theme_color_override("font_color", INK if valid else Color(0.97, 0.48, 0.36))
		return
	_marks.add_theme_color_override("font_color", INK)
	var count := context.excavation_marks.size()
	var adding: Array = changes.get("add", [])
	var removing: Array = changes.get("remove", [])
	var eligible_hint := "Rock / gold / gems only"
	if not changes.get("blocked", []).is_empty():
		eligible_hint = "Ground is ignored; mark rock / gold / gems"
	_marks.text = "EXCAVATION MARKS   |   %d MARKED   |   +%d mark / -%d unmark   |   %s" % [count, adding.size(), removing.size(), eligible_hint]


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.062, 0.065, 0.94)
	style.border_color = Color(0.27, 0.25, 0.21)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	_input_panels.append(panel)
	return panel


func _is_ui_position(point: Vector2) -> bool:
	for panel in _input_panels:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(point):
			return true
	return false


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label
