class_name KeeperQueue
extends HBoxContainer
## Virtualized FIFO strip. Scrolling changes presentation, never drop order.

const SLOT_WIDTH := 174
const MAX_VISIBLE := 10
const DefaultPortrait = preload("res://assets/ui/portrait_creature.svg")
const GoldIcon = preload("res://assets/ui/action_gold.svg")
var context: GameContext
var rendered_count := 0
var first_visible := 0
var _summary: Label
var _scroll: ScrollContainer
var _canvas: Control
var _items: Array = []
var _last_start := -1
var _last_width := -1.0


func setup(game_context: GameContext) -> void:
	context = game_context
	name = "KeeperQueue"
	custom_minimum_size.y = 64
	add_theme_constant_override("separation", 12)
	_summary = Label.new()
	_summary.custom_minimum_size.x = 145
	_summary.clip_text = true
	_summary.mouse_filter = Control.MOUSE_FILTER_STOP
	_summary.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_scroll.scroll_horizontal = 0
	)
	_summary.add_theme_font_size_override("font_size", 12)
	_summary.add_theme_color_override("font_color", Color(0.82, 0.74, 0.52))
	add_child(_summary)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.y = 64
	add_child(_scroll)
	_canvas = Control.new()
	_canvas.custom_minimum_size.y = 48
	_scroll.add_child(_canvas)
	_scroll.get_h_scroll_bar().value_changed.connect(_on_scroll)
	context.keeper.changed.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	if visible and _last_width != _scroll.size.x:
		_render_window()


func refresh() -> void:
	_items = context.keeper.get_items()
	visible = not _items.is_empty()
	_summary.text = "HAND  %d\nRight-click: next" % _items.size()
	if not _items.is_empty():
		var front = _items[0]
		_summary.text = "HAND  %d\nNext: %d gold" % [_items.size(), front.gold_amount]
		if front.actor != null:
			var actor: CreatureState = front.actor
			var definition := context.registry.get_creature(actor.definition_id)
			_summary.text = "HAND  %d\nNext: #%d %s" % [_items.size(), actor.id, actor.custom_name if not actor.custom_name.is_empty() else definition.display_name]
	_summary.tooltip_text = _summary.text + "\nRight-click: drop oldest. Scroll to see later entries.\nClick here to return to the front; creature cards inspect without reordering."
	_canvas.custom_minimum_size.x = _items.size() * SLOT_WIDTH
	_render_window(true)


func _on_scroll(_value: float) -> void:
	_render_window()


func _render_window(force: bool = false) -> void:
	var start := maxi(0, mini(floori(float(_scroll.scroll_horizontal) / SLOT_WIDTH), maxi(0, _items.size() - 1)))
	if not force and start == _last_start and _last_width == _scroll.size.x:
		return
	_last_start = start
	_last_width = _scroll.size.x
	first_visible = start
	for child in _canvas.get_children():
		# Inspection may refresh this strip from a card's own pressed signal.
		# Detach immediately, then let the emitting GUI object finish its event.
		_canvas.remove_child(child)
		child.queue_free()
	var count := mini(MAX_VISIBLE, ceili(_scroll.size.x / SLOT_WIDTH) + 2)
	for index in range(start, mini(_items.size(), start + count)):
		_card(index)
	rendered_count = _canvas.get_child_count()


func _card(index: int) -> void:
	var item = _items[index]
	var actor: CreatureState = item.actor
	var card := Button.new()
	card.position = Vector2(index * SLOT_WIDTH, 0)
	card.size = Vector2(SLOT_WIDTH - 7, 48)
	card.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.115, 0.09) if index == 0 else Color(0.07, 0.075, 0.075)
	style.border_color = Color(0.68, 0.51, 0.27) if index == 0 else Color(0.23, 0.23, 0.21)
	style.set_border_width_all(2 if index == 0 else 1)
	card.add_theme_stylebox_override("normal", style)
	_canvas.add_child(card)
	var icon := TextureRect.new()
	icon.position = Vector2(8, 8)
	icon.size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	var label := Label.new()
	label.position = Vector2(46, 5)
	label.size = Vector2(116, 38)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 11)
	card.add_child(label)
	var title := "%d · NEXT" % (index + 1) if index == 0 else str(index + 1)
	if actor != null:
		var definition := context.registry.get_creature(actor.definition_id)
		var actor_name := actor.custom_name if not actor.custom_name.is_empty() else definition.display_name
		icon.texture = definition.portrait if definition.portrait != null else DefaultPortrait
		label.text = "%s\n#%d %s" % [title, actor.id, actor_name]
		card.tooltip_text = "%d: #%d %s\nCarrying %d gold · Click to inspect" % [index + 1, actor.id, actor_name, actor.carried_gold]
		card.pressed.connect(func() -> void: context.keeper.inspect(actor.id))
	else:
		icon.texture = GoldIcon
		label.text = "%s\n%d gold" % [title, item.gold_amount]
		card.tooltip_text = "%d: %d gold" % [index + 1, item.gold_amount]
