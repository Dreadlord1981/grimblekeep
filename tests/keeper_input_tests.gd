extends SceneTree
## State-only creature picking and real Viewport keeper gesture regressions.

var _checks := 0
var _failures: Array[String] = []
var _context: GameContext
var _keeper: KeeperController
var _actor: CreatureState
var _panels: Array[Control] = []
var _entry: LineEdit


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	_fixture()
	await process_frame
	await process_frame
	_geometry()
	_immediate_pickup()
	await _focused_text_input()
	_held_drop_rules()
	_cancellation_and_modes()
	_terrain_drag_across_creature()
	_gold_custody()
	_mixed_queue()
	_stale_identity_and_removal()
	for failure in _failures:
		push_error(failure)
	print("KEEPER INPUT RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_keeper.queue_free()
	for panel in _panels:
		panel.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _fixture() -> void:
	var grid := DungeonGrid.new(13, 13)
	for y in range(1, 12):
		for x in range(1, 12):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(6, 6), DungeonGrid.Tile.HEART)
	grid.set_tile(Vector2i(10, 2), DungeonGrid.Tile.PORTAL)
	grid.set_tile(Vector2i(0, 0), DungeonGrid.Tile.GOLD)
	var creature := CreatureDefinition.new()
	creature.id = &"keeper_input.creature"
	creature.capabilities = [&"rest", &"haul"]
	creature.keeper_pick_size = Vector3(1.2, 1.6, 1.2)
	creature.keeper_sleep_pick_size = Vector3(1.6, 0.8, 2.0)
	var tall := CreatureDefinition.new()
	tall.id = &"keeper_input.tall"
	tall.keeper_pick_size = Vector3(1.2, 3.0, 1.2)
	var locked := CreatureDefinition.new()
	locked.id = &"keeper_input.locked"
	locked.keeper_pickup_allowed = false
	var vault := RoomDefinition.new()
	vault.id = &"keeper_input.vault"
	vault.gold_storage_per_tile = 100
	vault.gold_cost_per_tile = 10
	var lair := RoomDefinition.new()
	lair.id = &"keeper_input.lair"
	lair.tags = [&"lair"]
	var food := FoodDefinition.new()
	food.id = &"keeper_input.food"
	var producer := RoomDefinition.new()
	producer.id = &"keeper_input.producer"
	producer.food_type = food.id
	producer.food_capacity_per_tile = 1
	var module := ContentModule.new()
	module.id = &"keeper_input.module"
	module.definitions = [creature, tall, locked, vault, lair, food, producer]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Input fixture loads definition-driven pick bounds and pickup capability")
	_context = GameContext.new(grid, registry)
	_context.rooms.place_initial(vault.id, [Vector2i(2, 2)])
	_context.economy.deposit(Vector2i(2, 2), _context.economy.mine(Vector2i(0, 0), 100))
	_actor = _context.spawn_creature(creature.id, Vector2i(5, 6))
	_actor.carried_gold = _context.economy.mine(Vector2i(0, 0), 15)
	_context.rooms.place_initial(lair.id, [Vector2i(5, 6)])
	_context.beds.reserve(_actor, creature)
	_context.beds.establish(_actor)
	_context.rooms.place_initial(producer.id, [Vector2i(3, 9)])
	_context.food.produce(Vector2i(3, 9), food.id, 1)
	_keeper = KeeperController.new()
	root.add_child(_keeper)
	_keeper.setup(_context)
	_keeper.set_process(false)
	for rectangle in [Rect2(0, 0, 1280, 60), Rect2(0, 700, 1280, 100), Rect2(1080, 80, 200, 190)]:
		var panel := Panel.new()
		panel.position = rectangle.position
		panel.size = rectangle.size
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		root.add_child(panel)
		_panels.append(panel)
	_entry = LineEdit.new()
	_entry.position = Vector2(12, 12)
	_entry.size = Vector2(176, 32)
	_panels[2].add_child(_entry)
	_keeper.ui_hit_test = _is_ui
	_camera(_actor.position)


func _geometry() -> void:
	for sleeping in [false, true]:
		_actor.action = &"sleeping" if sleeping else &"idle"
		_actor.heading = 1.9
		for yaw in [0.0, 0.8, 1.7, 3.8]:
			for distance in [15.0, 28.0]:
				_camera(_actor.position, yaw, 0.85, distance)
				_check(_keeper.get_target_actor(_screen_actor(_actor)) == _actor, "State-only %s creature picking works at yaw %.1f / distance %.0f" % ["sleeping" if sleeping else "awake", yaw, distance])
	_actor.action = &"idle"
	_camera(_actor.position, 0.0, 0.4, 16.0)
	var point := _screen_actor(_actor)
	_motion(point)
	_context.grid.set_tile(Vector2i(5, 7), DungeonGrid.Tile.BEDROCK)
	_check(_keeper.get_target_actor(point) == null and _keeper.get_target_cell(point) == Vector2i(5, 7), "Raised bedrock occludes a creature behind it")
	_check(_keeper.get_preview_changes().get("actor_id", -1) == -1, "Terrain edits refresh creature occlusion under a stationary pointer")
	_context.grid.set_tile(Vector2i(5, 7), DungeonGrid.Tile.FLOOR)
	var tall := _context.spawn_creature(&"keeper_input.tall", Vector2i(5, 7))
	_check(_keeper.get_target_actor(point) == tall, "Overlapping creature rays choose the nearer visible body")
	_context.despawn_creature(tall.id)
	_camera(_actor.position)
	point = _screen_actor(_actor)
	_motion(point)
	_check(_keeper.get_preview_changes().get("actor_id", -1) == _actor.id and _keeper.get_preview_changes().blocked.is_empty(), "Creature hover suppresses the ordinary blocked-floor excavation marker")
	var original := _actor.position
	_actor.position += Vector3(6, 0, 0)
	_context.simulation_ticked.emit(0.1)
	_check(_keeper.get_preview_changes().get("actor_id", -1) == -1, "Moving away refreshes creature hover without pointer motion")
	_actor.position = original
	_context.simulation_ticked.emit(0.1)
	_camera(_context.grid.cell_to_world(Vector2i(3, 9)))
	var food_point := _keeper.camera.unproject_position(_context.grid.cell_to_world(Vector2i(3, 9)) + Vector3.UP * 0.2)
	_check(_keeper.get_target_actor(food_point) == null, "Physical food units are never creature pickup targets")
	_camera(_actor.position)


func _immediate_pickup() -> void:
	var point := _screen_actor(_actor)
	_mouse(point, true)
	_check(_context.keeper.held_actor == _actor and _actor.is_held, "Left press immediately picks up the visible creature")
	_check(_context.keeper.inspected_actor == _actor, "Immediate pickup also selects the exact creature for inspection")
	_mouse(point, false)
	_check(_context.keeper.held_actor == _actor, "Left release never drops a picked-up creature")
	_motion(_screen_cell(Vector2i(4, 4)), MOUSE_BUTTON_MASK_LEFT)
	_mouse(_screen_cell(Vector2i(4, 4)), false)
	_check(_context.keeper.held_actor == _actor and _actor.carried_gold == 15, "Dragging and releasing retain custody and carried gold")
	_click_cell(Vector2i(4, 4))
	_check(_context.keeper.held_actor == _actor, "Additional left clicks while held do not drop or replace the creature")
	_check(_keeper.get_target_actor(point) == null, "Held creatures leave world ray targeting")
	_right_click_cell(Vector2i(4, 4))
	_check(_context.keeper.held_actor == null and _context.grid.world_to_cell(_actor.position) == Vector2i(4, 4), "Right click drops on valid floor")
	_check(_context.beds.get_bed(_actor.id) != null and _context.beds.get_bed(_actor.id).established, "Keeper relocation preserves the established personal bed")
	_camera(_actor.position)
	_context.keeper.clear_inspection()
	_motion(_screen_actor(_actor))
	_key(KEY_I)
	_check(_context.keeper.inspected_actor == _actor and _context.keeper.held_actor == null, "I inspects a hovered creature without pickup")


func _focused_text_input() -> void:
	_entry.grab_focus()
	await process_frame
	_key(KEY_G, "g".unicode_at(0))
	_check(_entry.text == "g" and _context.keeper.held_actor == null, "Typing G in a focused name field never invokes pickup")
	_entry.release_focus()
	await process_frame


func _held_drop_rules() -> void:
	_key(KEY_G)
	_check(_context.keeper.held_actor == _actor, "G still lifts the inspected creature outside text input")
	_keeper.set_build_room(&"keeper_input.vault")
	_keeper.set_sell_rooms()
	_check(not _keeper.is_constructing(), "Build and Sell are refused while a creature is held")
	_key(KEY_ESCAPE)
	_check(_context.keeper.held_actor == _actor, "Escape never discards a held creature")
	_context.grid.set_tile(Vector2i(3, 3), DungeonGrid.Tile.ROCK)
	_motion(_screen_cell(Vector2i(3, 3)))
	_check(not _keeper.get_drop_preview().valid, "Rock has an invalid drop preview")
	_click_cell(Vector2i(3, 3))
	_check(_context.keeper.held_actor == _actor and not _context.excavation_marks.has(Vector2i(3, 3)), "Left clicks on rock retain custody without excavation")
	var yaw := _keeper.yaw
	_mouse(_screen_cell(Vector2i(3, 3)), true, MOUSE_BUTTON_RIGHT)
	_motion(_screen_cell(Vector2i(3, 3)), MOUSE_BUTTON_MASK_RIGHT, Vector2(10, 0))
	_check(_context.keeper.held_actor == _actor and is_equal_approx(yaw, _keeper.yaw), "Invalid right drop keeps the creature and suppresses camera orbit")
	_mouse(_screen_cell(Vector2i(3, 3)), false, MOUSE_BUTTON_RIGHT)
	var other := _context.spawn_creature(&"keeper_input.creature", Vector2i(7, 7))
	_context.rooms.place_initial(&"keeper_input.lair", [Vector2i(9, 9)])
	_context.beds.reserve(other, _context.registry.get_creature(other.definition_id))
	_motion(_screen_cell(Vector2i(7, 7)))
	_check(_keeper.get_drop_preview().valid, "Drop preview allows floor occupied by another creature")
	_motion(_screen_actor(other))
	_key(KEY_I)
	_check(_context.keeper.inspected_actor == other and _context.keeper.held_actor == _actor, "Inspection can select another individual without replacing the held creature")
	_click_actor(other)
	_check(_context.keeper.held_actor == _actor and other.is_held and _context.keeper.held_count == 2, "Left clicking another creature appends behind the existing front identity")
	_motion(_screen_cell(Vector2i(9, 9)))
	_check(_keeper.get_drop_preview().valid, "Drop preview allows another creature's bed floor")
	var isolated := Vector2i(11, 11)
	_context.grid.set_tile(Vector2i(10, 11), DungeonGrid.Tile.ROCK)
	_context.grid.set_tile(Vector2i(11, 10), DungeonGrid.Tile.ROCK)
	_camera(_context.grid.cell_to_world(isolated), 0.0, 1.2, 20)
	_motion(_screen_cell(isolated))
	_check(not _keeper.get_drop_preview().valid and "disconnected" in _keeper.get_drop_preview().reason, "Visible disconnected floor still rejects a drop")
	_right_click_cell(isolated)
	_check(_context.keeper.held_actor == _actor, "Right click cannot drop on disconnected floor")
	_camera(_context.grid.cell_to_world(Vector2i(5, 5)))
	_right_click(Vector2(80, 30))
	_check(_context.keeper.held_actor == _actor, "Right click over UI never drops a held creature")
	_mouse(_screen_cell(Vector2i(4, 5)), true)
	_mouse(Vector2(80, 30), false)
	_mouse(_screen_cell(Vector2i(4, 5)), false)
	_check(_context.keeper.held_actor == _actor, "UI crossing and stale left releases cannot drop")
	yaw = _keeper.yaw
	var occupied := _screen_cell(Vector2i(7, 7))
	_mouse(occupied, true, MOUSE_BUTTON_RIGHT)
	_check(_context.keeper.held_actor == other and _context.grid.world_to_cell(_actor.position) == Vector2i(7, 7), "Right press drops only the oldest creature and advances to the next")
	_motion(occupied, MOUSE_BUTTON_MASK_RIGHT, Vector2(12, 0))
	_check(is_equal_approx(yaw, _keeper.yaw), "Motion after a successful right drop cannot orbit before button release")
	_mouse(occupied, false, MOUSE_BUTTON_RIGHT)
	_right_click(occupied)
	_check(not _context.keeper.is_holding() and _context.grid.world_to_cell(other.position) == Vector2i(7, 7), "The next right click drops the second creature onto the shared floor")
	_mouse(occupied, true, MOUSE_BUTTON_RIGHT)
	_motion(occupied, MOUSE_BUTTON_MASK_RIGHT, Vector2(12, 0))
	_mouse(occupied, false, MOUSE_BUTTON_RIGHT)
	_check(not is_equal_approx(yaw, _keeper.yaw), "A fresh empty-hand right gesture restores camera orbit")
	_check(_context.actors.has(_actor) and _context.actors.has(other) and _context.grid.world_to_cell(other.position) == Vector2i(7, 7), "Shared-floor drop preserves both creature identities")
	other.position = _context.grid.cell_to_world(Vector2i(8, 8))
	_context.mark_excavation([Vector2i(3, 3)])
	_key(KEY_ESCAPE)
	_check(_context.keeper.inspected_actor == null and _context.excavation_marks.has(Vector2i(3, 3)), "Escape closes inspection before touching excavation marks")
	_key(KEY_ESCAPE)
	_check(_context.excavation_marks.is_empty(), "Default Escape still clears excavation when inspection is closed")


func _cancellation_and_modes() -> void:
	_camera(_actor.position)
	var point := _screen_actor(_actor)
	_mouse(point, true)
	_motion(Vector2(80, 30), MOUSE_BUTTON_MASK_LEFT)
	_mouse(point, false)
	_check(_context.keeper.held_actor == _actor, "Crossing UI after immediate pickup preserves custody on left release")
	_keeper.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_mouse(point, false)
	_check(_context.keeper.held_actor == _actor, "Focus loss and a late left release preserve an already-held creature")
	_right_click_cell(Vector2i(4, 5))
	_camera(_actor.position)
	_context.keeper.clear_inspection()
	point = _screen_actor(_actor)
	_mouse(Vector2(80, 30), true)
	_mouse(point, false)
	_check(_context.keeper.held_actor == null and _context.keeper.inspected_actor == null, "UI press followed by world release cannot pick up a creature")
	var yaw := _keeper.yaw
	_mouse(point, true, MOUSE_BUTTON_RIGHT)
	_motion(point, MOUSE_BUTTON_MASK_RIGHT, Vector2(8, 0))
	_mouse(point, false, MOUSE_BUTTON_RIGHT)
	_check(_context.keeper.held_actor == null and not is_equal_approx(yaw, _keeper.yaw), "Empty-hand right drag remains camera orbit")
	_camera(_actor.position)
	_keeper.set_build_room(&"keeper_input.vault")
	_click_cell(_context.grid.world_to_cell(_actor.position))
	_check(_context.rooms.tiles.get(_context.grid.world_to_cell(_actor.position)) == &"keeper_input.vault" and _context.keeper.held_actor == null, "Explicit construction retains priority over creature pickup")
	_keeper.set_sell_rooms()
	_right_click(Vector2(80, 30))
	_check(not _keeper.is_constructing() and _context.rooms.tiles.has(_context.grid.world_to_cell(_actor.position)), "Right click over UI cancels Sell without removing its room")
	_keeper.set_sell_rooms()
	_click_cell(_context.grid.world_to_cell(_actor.position))
	_check(not _context.rooms.tiles.has(_context.grid.world_to_cell(_actor.position)) and _context.keeper.held_actor == null, "Explicit Sell remains a room action")
	_keeper.exit_construction()
	_mouse(_screen_cell(Vector2i(3, 3)), true)
	_keeper.set_build_room(&"keeper_input.vault")
	_mouse(_screen_cell(Vector2i(4, 3)), false)
	_check(not _context.rooms.tiles.has(Vector2i(4, 3)) and _context.keeper.held_actor == null, "Tool changes cancel old presses before a late release can build or pick up")
	_keeper.exit_construction()
	_camera(_context.grid.cell_to_world(Vector2i(3, 3)))
	_click_cell(Vector2i(3, 3))
	_check(_context.excavation_marks.has(Vector2i(3, 3)), "Default excavation still works after keeper gestures")
	var locked := _context.spawn_creature(&"keeper_input.locked", Vector2i(8, 5))
	_camera(locked.position)
	_click_actor(locked)
	_motion(_screen_actor(locked))
	_key(KEY_I)
	_key(KEY_G)
	_check(_context.keeper.inspected_actor == locked and _context.keeper.held_actor == null, "Pickup-disabled creatures remain inspectable through I")
	_context.despawn_creature(locked.id)


func _gold_custody() -> void:
	var bank := Vector2i(2, 2)
	var floor_cell := Vector2i(7, 3)
	var receiving_bank := Vector2i(7, 4)
	_camera(_context.grid.cell_to_world(bank))
	var bank_before := _context.economy.stored_gold
	_mouse(_screen_cell(bank), true)
	_check(_context.keeper.held_gold == bank_before and bank_before > 0 and _context.economy.stored_gold == 0, "Left press lifts actual stored gold out of the clicked bank")
	_mouse(_screen_cell(bank), false)
	_check(_context.keeper.held_gold == bank_before and _context.keeper.held_actor == null, "Left release retains physical gold custody")
	_check(_context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold, "Gold in the keeper hand stays in the physical ledger")
	_keeper.set_build_room(&"keeper_input.vault")
	_check(not _keeper.is_constructing(), "Gold custody also blocks room construction")
	_keeper.set_sell_rooms()
	_check(not _keeper.is_constructing(), "Gold custody also blocks selling")
	_key(KEY_ESCAPE)
	_check(_context.keeper.held_gold == bank_before, "Escape never discards held gold")
	_click_actor(_actor)
	_check(_context.keeper.held_gold == bank_before and _actor.is_held and _context.keeper.held_count == 2 and not _keeper.pickup_selected(), "Creature pickup appends behind gold and duplicate held pickup is rejected")
	_motion(_screen_actor(_actor))
	_key(KEY_I)
	_check(_context.keeper.inspected_actor == _actor and _context.keeper.held_gold == bank_before, "Inspection while holding gold does not replace or debit that gold")
	_right_click(Vector2(100, 25))
	_check(_context.keeper.held_gold == bank_before and not _keeper.get_drop_preview().valid, "RMB over the interface retains gold with an invalid drop preview")
	_context.grid.set_tile(Vector2i(8, 3), DungeonGrid.Tile.ROCK)
	_camera(_context.grid.cell_to_world(Vector2i(8, 3)))
	_right_click_cell(Vector2i(8, 3))
	_check(_context.keeper.held_gold == bank_before, "Solid terrain cannot receive held gold")
	_camera(_context.grid.cell_to_world(floor_cell))
	_right_click_cell(floor_cell)
	_check(_context.keeper.held_actor == _actor and _context.economy.ground_gold.get(floor_cell, 0) == bank_before, "RMB drops the front gold pile and advances to the queued creature")
	_right_click_cell(Vector2i(4, 5))
	_context.economy.drop_gold(floor_cell, _context.economy.mine(Vector2i(0, 0), 50))
	var pile_before := _context.economy.gold_at(floor_cell)
	_motion(_screen_cell(floor_cell))
	_check(_keeper.get_preview_changes().blocked.is_empty(), "Loose-gold hover does not display the blocked excavation cross")
	_click_cell(floor_cell)
	_check(_context.keeper.held_gold == pile_before and _context.economy.ground_gold.get(floor_cell, 0) == 0, "Left click gathers the exact loose gold pile")
	_context.rooms.place_initial(&"keeper_input.vault", [receiving_bank])
	_right_click_cell(receiving_bank)
	_check(_context.economy.stored_by_cell.get(receiving_bank, 0) == mini(100, pile_before), "Gold drop fills only the target storage tile's available capacity")
	_check(_context.economy.ground_gold.get(receiving_bank, 0) == maxi(0, pile_before - 100) and not _context.keeper.is_holding(), "Gold exceeding local capacity remains loose at the same tile")
	_click_cell(receiving_bank)
	var overflow := maxi(0, pile_before - 100)
	_check(_context.keeper.held_gold == overflow and _context.economy.stored_by_cell.get(receiving_bank, 0) == 100 and _context.economy.ground_gold.get(receiving_bank, 0) == 0, "Visible overflow is picked up without also taking the stored gold beneath it")
	_right_click_cell(floor_cell)
	_camera(_context.grid.cell_to_world(Vector2i(0, 0)))
	_click_cell(Vector2i(0, 0))
	_check(not _context.keeper.is_holding() and _context.excavation_marks.has(Vector2i(0, 0)), "Solid gold seams retain excavation semantics instead of gold pickup")
	_actor.position = _context.grid.cell_to_world(floor_cell)
	_camera(_actor.position)
	_click_actor(_actor)
	_check(_context.keeper.held_actor == _actor and _context.keeper.held_gold == 0 and _context.economy.gold_at(floor_cell) == overflow, "Visible creatures have priority over loose gold beneath their bodies")
	_right_click_cell(Vector2i(4, 5))
	_check(_context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold, "Mixed creature/gold gestures conserve seam, stock, loose gold, cargo and custody")


func _mixed_queue() -> void:
	var entries: Array[Dictionary] = []
	var actors: Array[CreatureState] = []
	var pickup_cell := Vector2i(5, 4)
	var gold_cell := Vector2i(6, 4)
	for batch in 4:
		for index in 4:
			var definition_id: StringName = &"keeper_input.creature" if index % 2 == 0 else &"keeper_input.tall"
			var actor := _context.spawn_creature(definition_id, pickup_cell)
			actors.append(actor)
			_camera(actor.position)
			_click_actor(actor)
			entries.append({"kind": &"creature", "actor": actor})
		_context.economy.drop_gold(gold_cell, _context.economy.mine(Vector2i(0, 0), 1))
		_camera(_context.grid.cell_to_world(gold_cell))
		_click_cell(gold_cell)
		entries.append({"kind": &"gold", "amount": 1})
	_check(_context.keeper.held_count == 20 and _context.keeper.total_held_gold == 4, "Twenty mixed world pickups append without a count limit or same-type restriction")
	_check(actors.all(func(actor: CreatureState) -> bool: return actor.is_held), "Every queued creature stays held even while another type is at the front")
	var ids: Array[int] = []
	var ordering_correct := true
	for index in entries.size():
		var item: KeeperHandItem = _context.keeper.get_items()[index]
		ordering_correct = ordering_correct and item.kind == entries[index].kind and not item.id in ids
		if item.kind == &"creature":
			ordering_correct = ordering_correct and item.actor == entries[index].actor
		else:
			ordering_correct = ordering_correct and item.gold_amount == entries[index].amount
		ids.append(item.id)
	_check(ordering_correct, "Mixed queue preserves click order and unique entry identities")
	var front: KeeperHandItem = _context.keeper.peek_item()
	var spectator := _context.spawn_creature(&"keeper_input.tall", Vector2i(8, 5))
	_camera(spectator.position)
	_motion(_screen_actor(spectator))
	_key(KEY_I)
	_check(_context.keeper.inspected_actor == spectator and _context.keeper.peek_item().id == front.id, "Inspecting a different species never changes the next FIFO drop")
	_key(KEY_G)
	_check(spectator.is_held and _context.keeper.held_count == 21 and _context.keeper.peek_item().id == front.id, "G appends the inspected creature while preserving the front")
	entries.append({"kind": &"creature", "actor": spectator})
	_key(KEY_G)
	_check(_context.keeper.held_count == 21, "Repeated G cannot duplicate one held actor")
	_keeper.set_build_room(&"keeper_input.vault")
	_keeper.set_sell_rooms()
	_check(not _keeper.is_constructing(), "A mixed queue blocks Build and Sell commands")
	_keeper.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_mouse(_screen_actor(spectator), false)
	_right_click(Vector2(80, 30))
	_check(_context.keeper.held_count == 21 and _context.keeper.peek_item().id == front.id, "Focus changes, stale left release and UI right click preserve queue order")
	_camera(_context.grid.cell_to_world(Vector2i(8, 3)))
	_right_click_cell(Vector2i(8, 3))
	_check(_context.keeper.held_count == 21 and _context.keeper.peek_item().id == front.id, "Invalid terrain drop leaves the entire mixed queue untouched")
	var drop_cell := Vector2i(5, 5)
	_camera(_context.grid.cell_to_world(drop_cell))
	var fifo_correct := true
	var preview_correct := true
	for index in entries.size():
		var item: KeeperHandItem = _context.keeper.peek_item()
		var expected: Dictionary = entries[index]
		fifo_correct = fifo_correct and item.kind == expected.kind
		if expected.kind == &"creature":
			preview_correct = preview_correct and _context.keeper.held_actor == expected.actor and _context.keeper.held_gold == 0
		else:
			preview_correct = preview_correct and _context.keeper.held_actor == null and _context.keeper.held_gold == expected.amount
		_right_click_cell(drop_cell)
		fifo_correct = fifo_correct and _context.keeper.held_count == entries.size() - index - 1
		if expected.kind == &"creature":
			fifo_correct = fifo_correct and not expected.actor.is_held and _context.grid.world_to_cell(expected.actor.position) == drop_cell
	_check(fifo_correct and not _context.keeper.is_holding(), "Each right click drops exactly one FIFO entry, including many creatures sharing the same floor")
	_check(preview_correct, "Front actor/gold preview getters advance with FIFO order rather than newest pickup or inspection")
	_check(_context.economy.ground_gold.get(drop_cell, 0) == 4 and _context.keeper.total_held_gold == 0, "Separate queued gold entries drop their exact amounts without merging custody or losing money")
	_check(_context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold, "The many-item mixed loop preserves the complete physical gold ledger")
	for actor in actors:
		_context.despawn_creature(actor.id)
	_context.despawn_creature(spectator.id)


func _stale_identity_and_removal() -> void:
	var temporary := _context.spawn_creature(&"keeper_input.creature", Vector2i(7, 5))
	_camera(temporary.position)
	var point := _screen_actor(temporary)
	_mouse(point, true)
	_check(_context.keeper.held_actor == temporary, "Immediate pickup binds the exact actor ID on press")
	_context.despawn_creature(temporary.id)
	var replacement := _context.spawn_creature(&"keeper_input.creature", Vector2i(7, 5))
	_mouse(point, false)
	_check(_context.keeper.inspected_actor == null and _context.keeper.held_actor == null, "Despawned press IDs cannot inspect or lift a replacement at the same position")
	_context.despawn_creature(replacement.id)
	_context.keeper.inspect(_actor.id)
	_keeper.pickup_selected()
	_keeper.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(_context.keeper.held_actor == _actor, "Focus loss keeps already-held custody intact")
	_actor.carried_gold += _context.economy.mine(Vector2i(0, 0), 2)
	_context.actors.erase(_actor)
	_context.simulation_ticked.emit(0.1)
	_check(_context.keeper.held_actor == null and _context.keeper.inspected_actor == null and not _actor.is_held, "Raw removal clears held and inspected references safely")
	_check(_context.economy.pending_gold() == 17 and _context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold, "Removed held cargo remains exactly accounted for as pending recovery")
	_check(_context.food.total_units == 1 and _context.food.consumed_units == 0, "Creature input never picks up or consumes physical food")


func _terrain_drag_across_creature() -> void:
	_context.clear_excavation_marks()
	_actor.position = _context.grid.cell_to_world(Vector2i(4, 5))
	_camera(_context.grid.cell_to_world(Vector2i(4, 4)))
	_mouse(_screen_cell(Vector2i(3, 3)), true)
	_motion(_screen_actor(_actor), MOUSE_BUTTON_MASK_LEFT)
	_check(_keeper.get_preview_changes().add.has(Vector2i(3, 3)), "An existing terrain rectangle keeps its excavation preview while crossing a creature")
	_mouse(_screen_actor(_actor), false)
	_check(_context.excavation_marks.has(Vector2i(3, 3)) and not _actor.is_held, "Terrain drag crossing a creature commits the terrain operation without pickup")


func _camera(focus: Vector3, yaw: float = 0.3, pitch: float = 0.85, distance: float = 22.0) -> void:
	_keeper.focus = focus
	_keeper.yaw = yaw
	_keeper.pitch = pitch
	_keeper.distance = distance
	_keeper.call("_update_camera")


func _screen_actor(actor: CreatureState) -> Vector2:
	var definition := _context.registry.get_creature(actor.definition_id)
	var size: Vector3 = definition.keeper_sleep_pick_size if actor.action == &"sleeping" else definition.keeper_pick_size
	var height := size.y * definition.scale_factor * 0.5
	var bed := _context.beds.get_bed(actor.id)
	if bed != null:
		height += bed.lift_at(_context.grid, actor.position)
	return _keeper.camera.unproject_position(actor.position + Vector3.UP * height)


func _screen_cell(cell: Vector2i) -> Vector2:
	return _keeper.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.grid.surface_height(cell))


func _is_ui(point: Vector2) -> bool:
	for panel in _panels:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(point):
			return true
	return false


func _mouse(point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)


func _motion(point: Vector2, mask: int = 0, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = mask
	event.relative = relative
	root.push_input(event, true)


func _click_cell(cell: Vector2i) -> void:
	_mouse(_screen_cell(cell), true)
	_mouse(_screen_cell(cell), false)


func _right_click_cell(cell: Vector2i) -> void:
	_right_click(_screen_cell(cell))


func _right_click(point: Vector2) -> void:
	_mouse(point, true, MOUSE_BUTTON_RIGHT)
	_mouse(point, false, MOUSE_BUTTON_RIGHT)


func _click_actor(actor: CreatureState) -> void:
	_mouse(_screen_actor(actor), true)
	_mouse(_screen_actor(actor), false)


func _key(code: Key, unicode: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.pressed = true
	root.push_input(event, true)


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)
