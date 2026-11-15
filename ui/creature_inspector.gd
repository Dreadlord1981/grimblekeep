class_name CreatureInspector
extends PanelContainer
## Individual details live inside the bottom hub, never in a floating sidebar.

const INK := Color(0.82, 0.78, 0.67)
const MUTED := Color(0.53, 0.55, 0.51)
const PortraitFallback = preload("res://assets/ui/portrait_creature.svg")
var _context: GameContext
var _keeper: KeeperController
var _portrait: TextureRect
var _name_edit: LineEdit
var _kind: Label
var _activity: Label
var _cargo: Label
var _bed: Label
var _energy: HBoxContainer
var _satiety: HBoxContainer
var _pickup: Button
var _hint: Label
var _editing_actor_id := -1
var _refresh_in := 0.0
var tab_visible := true


func setup(context: GameContext, keeper: KeeperController) -> void:
	_context = context
	_keeper = keeper
	name = "CreatureInspector"
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(650, 80)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.071, 0.073, 0.94)
	style.border_color = Color(0.28, 0.26, 0.21)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(48, 48)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait)
	var names := VBoxContainer.new()
	names.custom_minimum_size.x = 170
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 3)
	row.add_child(names)
	_kind = _label("", 11, MUTED)
	_kind.clip_text = true
	names.add_child(_kind)
	_name_edit = LineEdit.new()
	_name_edit.name = "CreatureName"
	_name_edit.max_length = 32
	_name_edit.tooltip_text = "Name this individual. Enter saves; leave blank for its species and number."
	_name_edit.text_submitted.connect(_name_submitted)
	_name_edit.focus_exited.connect(_name_focus_exited)
	names.add_child(_name_edit)
	_activity = _label("", 12, INK)
	_activity.clip_text = true
	names.add_child(_activity)
	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 205
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 3)
	row.add_child(details)
	_cargo = _label("", 12, INK)
	details.add_child(_cargo)
	_energy = _meter("Energy", Color(0.54, 0.65, 0.41))
	details.add_child(_energy)
	_satiety = _meter("Satiety", Color(0.70, 0.57, 0.32))
	details.add_child(_satiety)
	_bed = _label("", 11, MUTED)
	_bed.clip_text = true
	details.add_child(_bed)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 100
	actions.add_theme_constant_override("separation", 4)
	row.add_child(actions)
	_pickup = Button.new()
	_pickup.name = "PickUp"
	_pickup.text = "Pick up [G]"
	_pickup.focus_mode = Control.FOCUS_NONE
	_pickup.pressed.connect(_keeper.pickup_selected)
	actions.add_child(_pickup)
	_hint = _label("", 11, MUTED)
	_hint.clip_text = true
	actions.add_child(_hint)
	var close := Button.new()
	close.name = "Close"
	close.text = "×"
	close.tooltip_text = "Close individual details"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(_context.keeper.clear_inspection)
	row.add_child(close)
	_context.keeper.changed.connect(refresh)
	_context.beds.changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = 0.15
		refresh()


func refresh() -> void:
	var actor: CreatureState = _context.keeper.inspected_actor
	visible = actor != null and tab_visible
	if actor == null:
		_editing_actor_id = -1
		return
	var definition := _context.registry.get_creature(actor.definition_id)
	if definition == null:
		visible = false
		return
	var changed_actor := _editing_actor_id != actor.id
	_editing_actor_id = actor.id
	_portrait.texture = definition.portrait if definition.portrait != null else PortraitFallback
	_kind.text = "%s · #%d" % [definition.display_name, actor.id]
	if changed_actor or not _name_edit.has_focus():
		_name_edit.text = actor.custom_name
	_name_edit.placeholder_text = "%s #%d" % [definition.display_name, actor.id]
	_activity.text = "Held by the keeper" if actor.is_held else actor.job_label
	_activity.tooltip_text = String(actor.action).capitalize() + " · " + actor.job_label
	_cargo.visible = actor.carried_gold > 0 or &"haul" in definition.capabilities
	_cargo.text = "Gold carried  %d / %d" % [actor.carried_gold, definition.carry_capacity]
	_energy.visible = &"rest" in definition.capabilities
	_satiety.visible = &"eat" in definition.capabilities
	_update_meter(_energy, actor.energy)
	_update_meter(_satiety, actor.satiety)
	_bed.visible = &"rest" in definition.capabilities
	var bed := _context.beds.get_bed(actor.id)
	_bed.text = "Needs a %d×%d Lair bed" % [definition.bed_size.x, definition.bed_size.y]
	if bed != null:
		_bed.text = "%d×%d personal bed · %s" % [bed.size.x, bed.size.y, "Established" if bed.established else "Reserved"]
	_pickup.disabled = not definition.keeper_pickup_allowed or actor.is_held
	_pickup.text = "Held" if actor.is_held else "Pick up [G]"
	_hint.visible = true
	_hint.text = "Queued · RMB next" if actor.is_held else "Add to hand" if definition.keeper_pickup_allowed else "Cannot pick up"
	_hint.tooltip_text = "Right-click valid floor to drop the oldest item. Invalid drops keep the queue." if actor.is_held else "Append this creature to the hand queue." if definition.keeper_pickup_allowed else "This creature cannot be picked up."


func _name_submitted(text: String) -> void:
	_commit_name(text)
	_name_edit.release_focus()


func _name_focus_exited() -> void:
	_commit_name(_name_edit.text)


func _commit_name(text: String) -> void:
	var actor: CreatureState = _context.keeper.inspected_actor
	if actor != null and actor.id == _editing_actor_id:
		_context.keeper.rename_selected(text)


func _meter(title: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var label := _label(title, 11, MUTED)
	label.custom_minimum_size.x = 43
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.name = "Value"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(70, 7)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var amount := _label("", 11, INK)
	amount.name = "Amount"
	amount.custom_minimum_size.x = 30
	row.add_child(amount)
	return row


func _update_meter(row: HBoxContainer, amount: float) -> void:
	var value := roundi(clampf(amount, 0, 1) * 100.0)
	row.get_node("Value").value = value
	row.get_node("Amount").text = "%d%%" % value


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
