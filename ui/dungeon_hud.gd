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
	_refresh_marks(context.last_marked_cell)
	_refresh_economy_and_workers()


func _process(delta: float) -> void:
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
	panel.offset_top = -99
	panel.offset_bottom = -16
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	_marks = _label("KEEPER HAND  /  Click or drag rock, gold or gems to mark excavation", 16, INK)
	column.add_child(_marks)
	column.add_child(_label("Click / drag  Toggle excavation marks    ·    Green +  Mark    ·    Red X  Unmark    ·    Shift  Mark only    ·    Ctrl  Unmark only    ·    Esc  Clear", 13, INK))
	column.add_child(_label("WASD / arrows  Pan    ·    RMB / Q E  Orbit    ·    MMB  Pan    ·    Wheel  Zoom    ·    Home  Heart    ·    F3  Diagnostics    |    WORKERS 02", 12, MUTED))


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
	help.tooltip_text = "Workers take reachable excavation and hauling jobs. Cancel an excavation mark to stop that digging job."
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
		_stored_gold.text = "STORED GOLD   %d" % context.economy.stored_gold
	_gold_in_transit.text = "Carried %d  /  Ground %d" % [carried, ground]
	_worker_count.text = "WORKERS   %d" % visible_workers.size()


func _refresh_marks(_cell: Vector2i) -> void:
	_refresh_preview(controller.get_preview_changes())


func _refresh_preview(changes: Dictionary) -> void:
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
