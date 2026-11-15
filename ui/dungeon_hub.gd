class_name DungeonHub
extends HBoxContainer
## Bottom tabs show definition portraits/icons and authoritative population/room counts.

signal tab_changed(tab: StringName)
signal room_chosen(definition_id: StringName)
signal sell_chosen
signal done_chosen

const DefaultPortrait = preload("res://assets/ui/portrait_creature.svg")
const DefaultRoom = preload("res://assets/ui/room_lair.svg")
const CreaturesIcon = preload("res://assets/ui/category_creatures.svg")
const RoomsIcon = preload("res://assets/ui/category_rooms.svg")
const SellIcon = preload("res://assets/ui/sell.svg")
const DoneIcon = preload("res://assets/ui/done.svg")
var active_tab: StringName = &"creatures"
var rooms_button: Button
var creatures_button: Button
var room_buttons: Dictionary[StringName, Button] = {}
var creature_buttons: Dictionary[StringName, Button] = {}
var room_badges: Dictionary[StringName, Label] = {}
var creature_badges: Dictionary[StringName, Label] = {}
var sell_button: Button
var done_button: Button
var _rooms: HBoxContainer
var _creatures: HBoxContainer
var _context: GameContext


func setup(context: GameContext) -> void:
	_context = context
	add_theme_constant_override("separation", 12)
	creatures_button = _button(CreaturesIcon, 72, 48)
	creatures_button.tooltip_text = "Creatures"
	creatures_button.toggle_mode = true
	creatures_button.pressed.connect(select_tab.bind(&"creatures"))
	add_child(creatures_button)
	rooms_button = _button(RoomsIcon, 72, 48)
	rooms_button.tooltip_text = "Rooms"
	rooms_button.toggle_mode = true
	rooms_button.pressed.connect(select_tab.bind(&"rooms"))
	add_child(rooms_button)
	add_child(VSeparator.new())
	_creatures = HBoxContainer.new()
	_creatures.add_theme_constant_override("separation", 10)
	add_child(_creatures)
	_rooms = HBoxContainer.new()
	_rooms.add_theme_constant_override("separation", 10)
	add_child(_rooms)
	if context.registry != null:
		for definition in context.registry.get_creatures():
			var button := _button(definition.portrait if definition.portrait != null else DefaultPortrait)
			_creatures.add_child(button)
			button.pressed.connect(_inspect_next_species.bind(definition.id))
			creature_buttons[definition.id] = button
			creature_badges[definition.id] = _badge(button)
		for definition in context.registry.get_rooms():
			if not definition.buildable:
				continue
			var button := _button(definition.icon if definition.icon != null else DefaultRoom, 80, 52, definition.gold_cost_per_tile)
			button.toggle_mode = true
			button.pressed.connect(func() -> void: room_chosen.emit(definition.id))
			_rooms.add_child(button)
			room_buttons[definition.id] = button
			room_badges[definition.id] = _badge(button)
	sell_button = _button(SellIcon, 64, 44)
	sell_button.tooltip_text = "Sell room tiles · 50% refund\nStored gold on sold tiles drops to the floor. Right-click to cancel."
	sell_button.toggle_mode = true
	sell_button.pressed.connect(func() -> void: sell_chosen.emit())
	_rooms.add_child(sell_button)
	done_button = _button(DoneIcon, 64, 44)
	done_button.tooltip_text = "Done · Esc / Right-click\nReturn to the keeper hand."
	done_button.pressed.connect(func() -> void: done_chosen.emit())
	_rooms.add_child(done_button)
	context.rooms.changed.connect(refresh)
	context.beds.changed.connect(refresh)
	context.food.changed.connect(refresh)
	context.actor_added.connect(_on_actor_changed)
	context.actor_removed.connect(_on_actor_changed)
	context.exploration.changed.connect(refresh)
	select_tab(&"creatures")
	refresh()


func select_tab(tab: StringName) -> void:
	if tab not in [&"creatures", &"rooms"]:
		return
	active_tab = tab
	_creatures.visible = tab == &"creatures"
	_rooms.visible = tab == &"rooms"
	creatures_button.set_pressed_no_signal(tab == &"creatures")
	rooms_button.set_pressed_no_signal(tab == &"rooms")
	tab_changed.emit(tab)


func show_tool(definition_id: StringName, selling: bool) -> void:
	for id in room_buttons:
		room_buttons[id].set_pressed_no_signal(id == definition_id)
	sell_button.set_pressed_no_signal(selling)
	done_button.visible = definition_id != &"" or selling


func refresh() -> void:
	if _context == null or _context.registry == null:
		return
	for id in creature_buttons:
		var count := 0
		for actor in _context.actors:
			if actor.definition_id == id and _context.is_actor_visible(actor):
				count += 1
		creature_badges[id].text = str(count)
		creature_buttons[id].visible = count > 0
		var definition := _context.registry.get_creature(id)
		creature_buttons[id].tooltip_text = "%s\nPopulation %d\nClick to inspect; click again to cycle individuals." % [definition.display_name, count]
	for id in room_buttons:
		var count := 0
		var tiles := 0
		var capacity := 0
		var gold_capacity := 0
		var gold := 0
		var food := 0
		var food_capacity := 0
		for room in _context.rooms.get_rooms():
			var known_cells: Array[Vector2i] = []
			for cell in room.cells:
				if _context.exploration.is_revealed(cell):
					known_cells.append(cell)
			if room.definition_id == id and not known_cells.is_empty():
				var profile := _context.registry.get_room(id)
				count += 1
				tiles += known_cells.size()
				capacity += known_cells.size() * profile.capacity_per_tile
				gold_capacity += known_cells.size() * profile.gold_storage_per_tile
				for cell in known_cells:
					gold += _context.economy.stored_by_cell.get(cell, 0)
					food += _context.food.total_at(cell)
					if _context.food.sources.has(cell):
						food_capacity += _context.food.sources[cell].capacity
		room_badges[id].text = str(count)
		var definition := _context.registry.get_room(id)
		var details := "Gold %d / %d" % [gold, gold_capacity] if definition.gold_storage_per_tile > 0 else ""
		if definition.food_type != &"":
			var food_type := _context.registry.get_food(definition.food_type)
			var food_name: String = food_type.display_name if food_type != null else "Food"
			details += ("\n" if not details.is_empty() else "") + "%s %d / %d" % [food_name, food, food_capacity]
			var minimum: Vector2i = definition.food_minimum_size
			if minimum != Vector2i.ONE:
				details += "\nMinimum %d×%d" % [minimum.x, minimum.y]
				if minimum.x != minimum.y:
					details += " or %d×%d" % [minimum.y, minimum.x]
			if definition.food_tiles_per_unit > 0:
				details += "\n1 %s per %d room tiles" % [food_name, definition.food_tiles_per_unit]
		var supports_beds := false
		for species in _context.registry.get_creatures():
			if &"rest" in species.capabilities and species.rest_room_tag in definition.tags:
				supports_beds = true
				break
		if supports_beds:
			var established := 0
			var reserved := 0
			for bed in _context.beds.beds.values():
				if not _context.exploration.is_revealed(bed.anchor):
					continue
				if _context.rooms.tiles.get(bed.anchor, &"") != id:
					continue
				if bed.established:
					established += 1
				else:
					reserved += 1
			details += ("\n" if not details.is_empty() else "") + "Beds %d established · %d reserved" % [established, reserved]
		elif details.is_empty():
			details = "Capacity %d" % capacity
		room_buttons[id].tooltip_text = "%s\n%d connected rooms · %d tiles\n%s\nBuild %d gold per tile. Right-click to cancel." % [definition.display_name, count, tiles, details, definition.gold_cost_per_tile]


func _on_actor_changed(_actor: CreatureState) -> void:
	refresh()


func _inspect_next_species(definition_id: StringName) -> void:
	var members: Array[CreatureState] = []
	for actor in _context.actors:
		if actor.definition_id == definition_id and _context.is_actor_visible(actor):
			members.append(actor)
	if members.is_empty():
		return
	members.sort_custom(func(a: CreatureState, b: CreatureState) -> bool: return a.id < b.id)
	var selected: CreatureState = _context.keeper.inspected_actor
	var index := members.find(selected)
	_context.keeper.inspect(members[(index + 1) % members.size()].id)


func _button(texture: Texture2D, width: float = 80, icon_size: float = 56, cost: int = -1) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(width, 80)
	button.focus_mode = Control.FOCUS_NONE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 4
	column.offset_bottom = -4
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	button.add_child(column)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE * icon_size
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(icon)
	if cost >= 0:
		var price := Label.new()
		price.name = "Price"
		price.text = str(cost)
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.add_theme_color_override("font_color", Color(0.85, 0.69, 0.38))
		price.add_theme_font_size_override("font_size", 13)
		column.add_child(price)
	return button


func _badge(button: Button) -> Label:
	var label := Label.new()
	label.name = "Count"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.offset_left = -27
	label.offset_right = -5
	label.offset_top = 3
	label.offset_bottom = 24
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.97, 0.89, 0.68))
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.065, 0.065, 0.92)
	background.set_content_margin_all(2)
	label.add_theme_stylebox_override("normal", background)
	button.add_child(label)
	return label
