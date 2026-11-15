class_name DungeonHUD
extends CanvasLayer
## Desktop HUD observes authoritative economy and worker state; never assigns jobs.

const HandScript = preload("res://ui/keeper_hand.gd")
const INK := Color(0.82, 0.78, 0.67)
const MUTED := Color(0.50, 0.53, 0.51)
const ACCENT := Color(0.70, 0.54, 0.29)
const DefaultPortrait = preload("res://assets/ui/portrait_creature.svg")
const BedIcon = preload("res://assets/ui/bed.svg")
const WalkIcon = preload("res://assets/ui/action_walk.svg")
const DigIcon = preload("res://assets/ui/action_dig.svg")
const SleepIcon = preload("res://assets/ui/action_sleep.svg")
const GoldIcon = preload("res://assets/ui/action_gold.svg")
const IdleIcon = preload("res://assets/ui/action_idle.svg")

var context: GameContext
var active_tab: StringName = &"creatures"
var _hub: DungeonHub
var _rooms_tab_button: Button
var _creatures_tab_button: Button
var _debug_content: VBoxContainer
var _cursor_feedback: Label
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
var _resident_count: Label
var _worker_roster: VBoxContainer
var _worker_rows_root: VBoxContainer
var _resident_rows_root: VBoxContainer
var _resident_heading: Label
var _resident_hint: Label
var _worker_rows: Dictionary[int, Control] = {}
var _resident_rows: Dictionary[int, Control] = {}
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
	context.beds.changed.connect(_refresh_residents)
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
	if _cursor_feedback != null:
		_cursor_feedback.visible = controller.is_constructing() and context.hovered_cell != KeeperController.INVALID_CELL and not controller.is_pointer_over_ui(controller.pointer_position)
		var area := get_viewport().get_visible_rect().size
		var pointer := controller.pointer_position + Vector2(24, 22)
		_cursor_feedback.position = Vector2(clampf(pointer.x, 8, maxf(8, area.x - _cursor_feedback.size.x - 8)), clampf(pointer.y, 70, maxf(70, area.y - _cursor_feedback.size.y - 128)))
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
	_resident_count = _label("RESIDENTS   0", 16, INK)
	row.add_child(_resident_count)
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
	panel.offset_top = -120
	panel.offset_bottom = -16
	_root.add_child(panel)
	_hub = DungeonHub.new()
	panel.add_child(_hub)
	_hub.setup(context)
	_hub.room_chosen.connect(controller.set_build_room)
	_hub.sell_chosen.connect(controller.set_sell_rooms)
	_hub.done_chosen.connect(controller.exit_construction)
	_hub.tab_changed.connect(_on_tab_changed)
	_construction_buttons = _hub.room_buttons
	_sell_button = _hub.sell_button
	_return_button = _hub.done_button
	_rooms_tab_button = _hub.rooms_button
	_creatures_tab_button = _hub.creatures_button
	_cursor_feedback = _label("", 13, INK)
	_cursor_feedback.visible = false
	_cursor_feedback.add_theme_color_override("font_shadow_color", Color.BLACK)
	_cursor_feedback.add_theme_constant_override("shadow_offset_x", 1)
	_cursor_feedback.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_cursor_feedback)
	_refresh_construction()


func select_tab(tab: StringName) -> void:
	_hub.select_tab(tab)


func _on_tab_changed(tab: StringName) -> void:
	active_tab = tab
	if tab == &"creatures" and controller.is_constructing():
		controller.exit_construction()


func _refresh_construction() -> void:
	if _hub != null:
		_hub.show_tool(controller.build_room_id, controller.removing_rooms)
	for id in _construction_buttons:
		_construction_buttons[id].set_pressed_no_signal(controller.build_room_id == id)
	if _sell_button != null:
		_sell_button.set_pressed_no_signal(controller.removing_rooms)
	if _return_button != null:
		_return_button.visible = controller.is_constructing()
		_return_button.set_pressed_no_signal(false)
	if _controls_hint != null:
		if controller.build_room_id != &"":
			_controls_hint.text = "Click / drag  Place on empty excavated floor    ·    Green +  Build    ·    Red X  Blocked    ·    RMB / Esc  Cancel"
		elif controller.removing_rooms:
			_controls_hint.text = "Click / drag  Sell room tiles    ·    Red X  Sell    ·    RMB / Esc  Cancel"
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
	_debug_content = VBoxContainer.new()
	_debug_content.custom_minimum_size.x = 480
	_debug_content.add_theme_constant_override("separation", 6)
	_debug_panel.add_child(_debug_content)
	_debug = _label("DIAGNOSTICS", 14, INK)
	_debug_content.add_child(_debug)
	_marks = _label("", 13, INK)
	_marks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_content.add_child(_marks)
	_controls_hint = _label("", 12, MUTED)
	_controls_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_content.add_child(_controls_hint)
	var camera_help := _label("WASD / arrows: pan · RMB / Q E: orbit · MMB: pan\nWheel: zoom · Home: Heart · F3: close debug", 12, MUTED)
	_debug_content.add_child(camera_help)
	_action_feedback = _label("", 12, MUTED)
	_action_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_content.add_child(_action_feedback)
	_refresh_construction()


func _build_workers() -> void:
	# Detailed actor state belongs to F3 diagnostics, never an always-on sidebar.
	_worker_roster = VBoxContainer.new()
	_worker_roster.add_theme_constant_override("separation", 6)
	_debug_content.add_child(_worker_roster)
	_worker_roster.add_child(_label("ACTIVE WORKERS", 14, INK))
	var help := _label("Jobs are assigned automatically", 12, MUTED)
	help.tooltip_text = "Workers dig marked terrain and haul gold. Cancel an excavation mark to stop that digging job."
	help.mouse_filter = Control.MOUSE_FILTER_PASS
	_worker_roster.add_child(help)
	_worker_rows_root = VBoxContainer.new()
	_worker_rows_root.add_theme_constant_override("separation", 10)
	_worker_roster.add_child(_worker_rows_root)
	_worker_roster.add_child(HSeparator.new())
	_resident_heading = _label("RESIDENTS", 14, INK)
	_worker_roster.add_child(_resident_heading)
	_resident_hint = _label("Residents need a reachable bed-sized Lair", 12, MUTED)
	_resident_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resident_hint.custom_minimum_size.x = 242
	_worker_roster.add_child(_resident_hint)
	_resident_rows_root = VBoxContainer.new()
	_resident_rows_root.add_theme_constant_override("separation", 10)
	_worker_roster.add_child(_resident_rows_root)


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
			var row := _creature_card(definition, false)
			_worker_rows_root.add_child(row)
			_worker_rows[actor.id] = row
		_refresh_creature_card(_worker_rows[actor.id], actor, definition, false)
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
	_refresh_residents()
	if _hub != null:
		_hub.refresh()


func _refresh_residents() -> void:
	if context == null or _resident_rows_root == null:
		return
	var visible_residents: Dictionary[int, bool] = {}
	for actor in context.actors:
		var definition := context.registry.get_creature(actor.definition_id) if context.registry != null else null
		if definition == null or not (&"rest" in definition.capabilities):
			continue
		visible_residents[actor.id] = true
		if not _resident_rows.has(actor.id):
			var row := _creature_card(definition, true)
			_resident_rows_root.add_child(row)
			_resident_rows[actor.id] = row
		_refresh_creature_card(_resident_rows[actor.id], actor, definition, true)
	for actor_id in _resident_rows.keys():
		if not visible_residents.has(actor_id):
			_resident_rows[actor_id].queue_free()
			_resident_rows.erase(actor_id)
	_resident_count.text = "RESIDENTS   %d" % visible_residents.size()
	_resident_heading.text = "RESIDENTS   %d" % visible_residents.size()
	_resident_hint.visible = visible_residents.is_empty()


func _creature_card(definition: CreatureDefinition, resident: bool) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(242, 44)
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var portrait := _icon(definition.portrait if definition.portrait != null else DefaultPortrait, 40)
	portrait.name = "Portrait"
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.name = "Info"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)
	var name_label := _label("", 12, INK)
	name_label.name = "Name"
	name_label.clip_text = true
	info.add_child(name_label)
	var status := HBoxContainer.new()
	status.name = "Status"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_constant_override("separation", 5)
	info.add_child(status)
	var action := _icon(IdleIcon, 20)
	action.name = "Action"
	status.add_child(action)
	var meter := ProgressBar.new()
	meter.name = "Meter"
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.custom_minimum_size = Vector2(38, 7)
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.12, 0.13, 0.13)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.53, 0.63, 0.40) if resident else Color(0.66, 0.51, 0.29)
	meter.add_theme_stylebox_override("background", background)
	meter.add_theme_stylebox_override("fill", fill)
	status.add_child(meter)
	var value := _label("", 11, MUTED)
	value.name = "Value"
	status.add_child(value)
	if resident:
		var bed := _icon(BedIcon, 19)
		bed.name = "Bed"
		status.add_child(bed)
		var size_label := _label("", 11, MUTED)
		size_label.name = "BedSize"
		status.add_child(size_label)
	return row


func _refresh_creature_card(row: Control, actor: CreatureState, definition: CreatureDefinition, resident: bool) -> void:
	row.get_node("Info/Name").text = "%s #%d" % [definition.display_name, actor.id]
	row.get_node("Info/Status/Action").texture = _action_icon(actor.action)
	var meter: ProgressBar = row.get_node("Info/Status/Meter")
	var value: Label = row.get_node("Info/Status/Value")
	var action := String(actor.action).capitalize()
	row.tooltip_text = "%s #%d · %s\n%s" % [definition.display_name, actor.id, action, actor.job_label]
	if resident:
		var bed := context.beds.get_bed(actor.id)
		var size: Vector2i = definition.bed_size if bed == null else bed.size
		var energy := roundi(clampf(actor.energy, 0.0, 1.0) * 100.0)
		var forming_home := actor.action == &"claiming_bed" and bed != null and not bed.established
		meter.value = roundi(clampf(actor.work_progress, 0.0, 1.0) * 100.0) if forming_home else energy
		value.text = "%d%%" % roundi(meter.value)
		row.get_node("Info/Status/BedSize").text = "%d×%d" % [size.x, size.y]
		var bed_status := "Needs %d×%d bed" % [size.x, size.y]
		var bed_color := Color(0.95, 0.39, 0.29)
		if bed != null:
			bed_status = "Bed %d×%d established" % [size.x, size.y] if bed.established else "Bed %d×%d reserved · On the way" % [size.x, size.y]
			bed_color = Color(0.55, 0.72, 0.42) if bed.established else Color(0.92, 0.65, 0.25)
			if forming_home:
				bed_status = "Claiming reserved %d×%d bed · %d%%" % [size.x, size.y, roundi(meter.value)]
		row.get_node("Info/Status/Bed").modulate = bed_color
		row.tooltip_text += "\nEnergy %d%%\n%s" % [energy, bed_status]
	else:
		meter.value = clampf(actor.work_progress, 0.0, 1.0) * 100.0
		if actor.carried_gold > 0:
			meter.value = float(actor.carried_gold) / float(definition.carry_capacity) * 100.0
		value.text = str(actor.carried_gold) if actor.carried_gold > 0 else ""
		row.tooltip_text += "\nCarrying %d / %d gold" % [actor.carried_gold, definition.carry_capacity]


func _icon(texture: Texture2D, pixels: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE * pixels
	return icon


func _action_icon(action: StringName) -> Texture2D:
	match action:
		&"walking": return WalkIcon
		&"digging", &"mining": return DigIcon
		&"hauling", &"depositing": return GoldIcon
		&"sleeping": return SleepIcon
		&"claiming_bed": return BedIcon
		&"homeless": return BedIcon
	return IdleIcon


func _refresh_marks(_cell: Vector2i) -> void:
	_refresh_preview(controller.get_preview_changes())


func _refresh_preview(changes: Dictionary) -> void:
	if _cursor_feedback != null:
		if controller.is_constructing():
			var count: int = changes.get("remove", []).size() if controller.removing_rooms else changes.get("add", []).size()
			var amount: int = changes.get("refund", 0) if controller.removing_rooms else changes.get("cost", 0)
			var amount_text := "%d gold refund" % amount if controller.removing_rooms else "%d gold" % amount
			_cursor_feedback.text = "%d tiles · %s" % [count, amount_text]
			if not changes.get("valid", false):
				_cursor_feedback.text = changes.get("reason", "Cannot place here")
			elif not changes.get("blocked", []).is_empty():
				_cursor_feedback.text += " · %d blocked" % changes.get("blocked", []).size()
			_cursor_feedback.add_theme_color_override("font_color", INK if changes.get("valid", false) else Color(0.97, 0.48, 0.36))
		else:
			_cursor_feedback.visible = false
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
