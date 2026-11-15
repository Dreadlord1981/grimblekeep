extends SceneTree
## Food HUD and Pig Pen construction through the actual desktop Viewport.

const PIG := &"food_ui.cave_pig"
const PEN := &"food_ui.pig_pen"
const PEN_CELL := Vector2i(5, 5)
var _checks := 0
var _failures: Array[String] = []
var _context: GameContext
var _keeper: KeeperController
var _hud: DungeonHUD
var _eater: CreatureState


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	_fixture()
	await process_frame
	await process_frame
	_check(_hud.active_tab == &"creatures" and not _hud.get("_debug_panel").visible, "Food keeps the clean Creatures hub and hidden diagnostics by default")
	_check(_hud.get("_food_count").text == "FOOD   0", "Food counter starts at actual zero stock")
	_check("Carried 20" in _hud.get("_stored_gold").tooltip_text and "Ground 20" in _hud.get("_stored_gold").tooltip_text, "Transit gold detail remains available in the compact gold tooltip")
	_check(not _hud.call("_is_ui_position", Vector2(1180, 150)), "Food does not restore a right-hand creature sidebar")
	_ui_click(_hud.get("_rooms_tab_button"))
	await process_frame
	var button: Button = _hud.get("_construction_buttons")[PEN]
	_check(button.is_visible_in_tree() and "Pig Pen" in button.tooltip_text and "75 gold" in button.tooltip_text, "Rooms tab discovers the data-defined Pig Pen with its price")
	_check("Minimum 3×1 or 1×3" in button.tooltip_text and "per 3 room tiles" in button.tooltip_text, "Pig Pen tooltip explains the straight minimum footprint and shared stocking density")
	_ui_click(button)
	_drag_cells(PEN_CELL, PEN_CELL + Vector2i(2, 0))
	_check(_context.rooms.tiles.get(PEN_CELL) == PEN and _context.rooms.tiles.get(PEN_CELL + Vector2i(2, 0)) == PEN and _context.economy.stored_gold == 135, "Pig Pen icon builds a straight three-tile room and charges exactly 225 gold")
	var hub: DungeonHub = _hud.get("_hub")
	_check(hub.room_badges[PEN].text == "1", "Three Pig Pen tiles form one connected room in its count overlay")
	_check(_context.food.produce(PEN_CELL, PIG, 2) == 1, "Three-tile Pig Pen has shared capacity for exactly one pig")
	_check(_hud.get("_food_count").text == "FOOD   1", "Food production immediately updates the actual header count")
	_check("Cave pig 1 / 1" in button.tooltip_text and not "Capacity 3" in button.tooltip_text, "Pig Pen tooltip shows pooled stock and capacity rather than generic tile count")
	_check(not "seconds" in button.tooltip_text and not "countdown" in button.tooltip_text, "Production timing is not exposed as a mobile-style countdown")
	var panels: Array = _hud.get("_input_panels")
	var bounds_ok := true
	for panel: Control in panels:
		if panel.is_visible_in_tree():
			bounds_ok = bounds_ok and panel.get_global_rect().end.x <= 1280 and panel.get_global_rect().end.y <= 800
	for child: Control in panels[0].get_child(0).get_children():
		bounds_ok = bounds_ok and child.get_global_rect().end.x <= 1264
	_check(bounds_ok, "Food count and three room-type icons fit inside the 1280x800 desktop HUD")
	_ui_click(_hud.get("_creatures_tab_button"))
	await process_frame
	_check(not _keeper.is_constructing(), "Returning to Creatures leaves the default keeper action active")
	var debug_row: Control = _hud.get("_resident_rows")[_eater.id]
	_check(not debug_row.is_visible_in_tree() and not _hud.get("_marks").is_visible_in_tree(), "Hunger details and verbose controls remain hidden in the default hub")
	_key(KEY_F3)
	await process_frame
	_check(debug_row.is_visible_in_tree() and debug_row.get_node("Info/FoodStatus/Satiety").value == 23, "F3 shows the resident's actual normalized satiety")
	_check(_hud.get("_debug_panel").get_global_rect().end.y <= 800, "Food diagnostics fit vertically inside the desktop viewport")
	_check(debug_row.get_node("Info/Status/Action").texture == preload("res://assets/ui/action_eat.svg") and debug_row.get_node("Info/Status/Meter").value == 60, "Eating has its own action icon and actual meal progress")
	var stock := _context.economy.stored_gold
	_mouse(debug_row.get_global_rect().get_center(), true)
	_mouse(debug_row.get_global_rect().get_center(), false)
	_check(_context.economy.stored_gold == stock and _context.excavation_marks.is_empty(), "Hunger diagnostics neither charge wages nor leak into world input")
	_key(KEY_F3)
	await process_frame
	_eater.position = _context.grid.cell_to_world(PEN_CELL)
	_check(_context.food.reserve_meal(_eater) != null and _context.food.consume(_eater) > 0.0, "Fixture consumes one locally reserved compatible meal")
	_check(_hud.get("_food_count").text == "FOOD   0" and "Cave pig 0 / 1" in button.tooltip_text, "Consumption immediately updates food count and source tooltip")
	_context.food.produce(PEN_CELL, PIG, 1)
	_context.rooms.remove([PEN_CELL, PEN_CELL + Vector2i(1, 0), PEN_CELL + Vector2i(2, 0)])
	_check(_hud.get("_food_count").text == "FOOD   1" and _context.food.total_at(PEN_CELL) == 1, "Selling a food room preserves its remaining physical food in the HUD")
	_check(hub.room_badges[PEN].text == "0", "Selling the last Pig Pen clears its connected-room overlay")
	_check(_context.food.total_units + _context.food.consumed_units == _context.food.produced_units, "UI operations preserve the physical food ledger")
	var food_only := _context.spawn_creature(&"food_ui.food_only", Vector2i(2, 3))
	food_only.action = &"eating"
	food_only.work_progress = 0.25
	_hud.call("_refresh_economy_and_workers")
	var food_only_card: Control = _hud.get("_resident_rows")[food_only.id]
	_check(food_only_card.has_node("Info/FoodStatus/Satiety") and not food_only_card.has_node("Info/Status/Bed"), "A food-only species gets hunger information without an invented bed requirement")
	_check(food_only_card.get_node("Info/Status/Meter").value == 25 and not food_only_card.is_visible_in_tree(), "Food-only meal progress remains accurate and confined to hidden diagnostics")
	for failure in _failures:
		push_error(failure)
	print("FOOD UI RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_hud.queue_free()
	_keeper.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _fixture() -> void:
	var grid := DungeonGrid.new(12, 10)
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(11, 9), DungeonGrid.Tile.GOLD)
	grid.set_tile(Vector2i(10, 9), DungeonGrid.Tile.GOLD)
	var pig := FoodDefinition.new()
	pig.id = PIG
	pig.display_name = "Cave pig"
	pig.tags = [&"raw_meat"]
	var pen := RoomDefinition.new()
	pen.id = PEN
	pen.display_name = "Pig Pen"
	pen.icon = preload("res://assets/ui/room_pig_pen.svg")
	pen.gold_cost_per_tile = 75
	pen.food_type = PIG
	pen.food_capacity_per_tile = 1
	pen.food_minimum_size = Vector2i(3, 1)
	pen.food_tiles_per_unit = 3
	pen.food_production_seconds = 12.0
	var vault := RoomDefinition.new()
	vault.id = &"food_ui.vault"
	vault.display_name = "Treasury"
	vault.gold_storage_per_tile = 1000
	var lair := RoomDefinition.new()
	lair.id = &"food_ui.lair"
	lair.display_name = "Lair"
	lair.tags = [&"lair"]
	var species := CreatureDefinition.new()
	species.id = &"food_ui.eater"
	species.display_name = "Grubbin food test"
	species.capabilities = [&"rest", &"eat"]
	species.food_tags = [&"raw_meat"]
	species.initial_satiety = 0.23
	var worker := CreatureDefinition.new()
	worker.id = &"food_ui.worker"
	worker.capabilities = [&"haul"]
	var food_only := CreatureDefinition.new()
	food_only.id = &"food_ui.food_only"
	food_only.capabilities = [&"eat"]
	food_only.food_tags = [&"raw_meat"]
	var module := ContentModule.new()
	module.id = &"food_ui.module"
	module.definitions = [pig, pen, vault, lair, species, worker, food_only]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Food UI extension definitions register atomically")
	_context = GameContext.new(grid, registry)
	for index in 3:
		_context.spawn_creature(worker.id, Vector2i(2 + index, 2))
	_eater = _context.spawn_creature(species.id, Vector2i(6, 4))
	_eater.action = &"eating"
	_eater.work_progress = 0.6
	_eater.job_label = "Eating a cave pig"
	_context.rooms.place_initial(vault.id, [Vector2i(1, 1)])
	_context.economy.mine(Vector2i(11, 9), 200)
	_context.economy.mine(Vector2i(10, 9), 200)
	_context.economy.deposit(Vector2i(1, 1), 360)
	_context.economy.drop_gold(Vector2i(1, 2), 20)
	_context.actors[0].carried_gold = 20
	_keeper = KeeperController.new()
	root.add_child(_keeper)
	_keeper.setup(_context)
	_keeper.set_process(false)
	_keeper.camera.position = Vector3(12, 28, 22)
	_keeper.camera.look_at(Vector3(12, 0, 10))
	_hud = DungeonHUD.new()
	root.add_child(_hud)
	_hud.setup(_context, _keeper)


func _click_cell(cell: Vector2i) -> void:
	var point := _keeper.camera.unproject_position(_context.grid.cell_to_world(cell))
	_mouse(point, true)
	_mouse(point, false)


func _drag_cells(first: Vector2i, last: Vector2i) -> void:
	_mouse(_keeper.camera.unproject_position(_context.grid.cell_to_world(first)), true)
	var motion := InputEventMouseMotion.new()
	motion.position = _keeper.camera.unproject_position(_context.grid.cell_to_world(last))
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_mouse(motion.position, false)


func _ui_click(button: Button) -> void:
	_mouse(button.get_global_rect().get_center(), true)
	_mouse(button.get_global_rect().get_center(), false)


func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)
