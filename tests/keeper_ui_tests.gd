extends SceneTree
## Focused inspector editing and UI/world isolation through actual Viewport events.

var _checks := 0
var _failures: Array[String] = []
var _context: GameContext
var _keeper: KeeperController
var _hud: DungeonHUD
var _worker: CreatureState
var _resident: CreatureState
var _locked: CreatureState
var _worker_b: CreatureState


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	_fixture()
	await process_frame
	await process_frame
	var inspector: CreatureInspector = _hud.get("_inspector")
	_check(not inspector.visible, "Default HUD does not show an unselected creature panel")
	var hub: DungeonHub = _hud.get("_hub")
	_click(hub.creature_buttons[&"foundation.imp"].get_global_rect().get_center())
	await process_frame
	await process_frame
	_check(inspector.visible and inspector.is_visible_in_tree(), "Inspecting a live creature opens its focused panel")
	_check(_context.keeper.inspected_actor == _worker and _context.keeper.held_actor == null, "Species portrait inspects an individual without picking it up")
	_click(hub.creature_buttons[&"foundation.imp"].get_global_rect().get_center())
	_check(_context.keeper.inspected_actor == _worker_b, "Repeated species portrait click cycles distinct individual identities")
	_click(hub.creature_buttons[&"foundation.imp"].get_global_rect().get_center())
	_check(not inspector.get("_energy").visible and not inspector.get("_satiety").visible and inspector.get("_cargo").visible, "Worker inspector shows cargo and omits unsupported resident needs")
	var bounds := inspector.get_global_rect()
	_check(inspector.get_parent() == hub and bounds.position.y >= 640 and bounds.end.y <= 784 and bounds.end.x <= 1264, "All individual details fit inside the bottom hub at 1280x800")
	_context.grid.set_tile(Vector2i(3, 3), DungeonGrid.Tile.ROCK)
	_context.mark_excavation([Vector2i(3, 3)])
	var original_marks := _context.excavation_marks.duplicate()
	var name_edit: LineEdit = inspector.get("_name_edit")
	name_edit.grab_focus()
	name_edit.text = "Muck"
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter, true)
	await process_frame
	_check(_worker.custom_name == "Muck" and not name_edit.has_focus(), "Enter saves the selected creature's edited name through keeper state")
	_check(_context.excavation_marks == original_marks and _context.keeper.held_actor == null, "Name editing does not trigger excavation or pickup")
	var pickup: Button = inspector.get("_pickup")
	_click(pickup.get_global_rect().get_center())
	await process_frame
	_check(_context.keeper.held_actor == _worker and pickup.disabled, "Inspector Pick Up button lifts the selected creature once")
	_check(inspector.get("_activity").text == "Held by the keeper", "Inspector explains held activity")
	_right_click(inspector.get_global_rect().get_center())
	_check(_context.keeper.held_actor == _worker and _context.excavation_marks == original_marks, "Clicks within inspector never drop or mark the world underneath")
	var hand: KeeperHand
	for child in _hud.get("_root").get_children():
		if child is KeeperHand:
			hand = child
	var preview: HeldCreaturePreview = hand.get("_held_preview")
	var model: Node3D = preview.get("_view")
	_check(preview.bound_actor_id == _worker.id and model != null, "Held preview instantiates the actual held identity's model")
	_click(hub.creature_buttons[&"foundation.grubbin"].get_global_rect().get_center())
	_check(_context.keeper.inspected_actor == _resident and _context.keeper.held_actor == _worker and preview.bound_actor_id == _worker.id and preview.get("_view") == model, "Inspecting another species does not change or recreate the held model")
	var close := inspector.find_child("Close", true, false) as Button
	_click(close.get_global_rect().get_center())
	await process_frame
	_check(not inspector.visible and _context.keeper.inspected_actor == null and _context.keeper.held_actor == _worker, "Closing inspection keeps held creature safely in the hand")
	_motion(Vector2i(3, 3))
	_hud.call("_process", 0.2)
	var feedback: Label = _hud.get("_cursor_feedback")
	_check(feedback.visible and "floor" in feedback.text.to_lower(), "Held cursor explains an invalid solid-terrain drop")
	_click(_screen(Vector2i(3, 3)))
	_check(_context.keeper.held_actor == _worker, "Left click and release never drop a held creature")
	_right_click(_screen(Vector2i(3, 3)))
	_check(_context.keeper.held_actor == _worker, "Invalid right-click retains the held creature")
	_motion(Vector2i(7, 5))
	_hud.call("_process", 0.2)
	_check(feedback.visible and feedback.text == "Right-click: drop next", "Valid floor gets concise FIFO right-click drop feedback")
	_right_click(_screen(Vector2i(7, 5)))
	_check(_context.keeper.held_actor == null and not _worker.is_held and _context.grid.world_to_cell(_worker.position) == Vector2i(7, 5), "Right-click drops onto shared floor occupied by another creature and bed")
	_check(preview.bound_actor_id == -1 and preview.get("_view") == null and preview.get("_viewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, "Dropping clears the model and disables empty preview rendering")
	_context.keeper.inspect(_resident.id)
	await process_frame
	_check(inspector.get("_energy").visible and inspector.get("_satiety").visible, "Resident inspection shows its supported energy and satiety")
	_check("Established" in inspector.get("_bed").text, "Resident inspection distinguishes its established personal bed")
	_context.keeper.rename_selected("")
	_check(inspector.get("_name_edit").placeholder_text == "Grubbin #%d" % _resident.id, "Empty name retains a clear species-and-identity fallback")
	_context.despawn_creature(_resident.id)
	_check(not inspector.visible, "Removing an inspected creature closes stale details")
	_context.keeper.inspect(_locked.id)
	await process_frame
	_check(inspector.get("_pickup").disabled and inspector.get("_hint").visible, "Definition-level pickup restriction is visible in the inspector")
	_click((inspector.get("_pickup") as Button).get_global_rect().get_center())
	_check(_context.keeper.held_actor == null, "Disabled pickup control cannot lift a restricted creature")
	await _mixed_queue(preview, inspector)
	for failure in _failures:
		push_error(failure)
	print("KEEPER UI RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_hud.queue_free()
	_keeper.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _mixed_queue(preview: HeldCreaturePreview, inspector: CreatureInspector) -> void:
	var queue: KeeperQueue = _hud.get("_keeper_queue")
	_context.keeper.pickup(_worker.id)
	var front_id := preview.bound_item_id
	var front_model: Node3D = preview.get("_view")
	# Finite test piles are explicit ledger sources, not production/game income.
	_context.economy.drop_gold(Vector2i(9, 7), 75)
	_context.economy.drop_gold(Vector2i(9, 8), 125)
	_context.economy.initial_gold += 200
	var initial := _context.economy.accounted_gold(_context.actors)
	_context.keeper.pickup_gold(Vector2i(9, 7))
	_context.keeper.inspect(_worker_b.id)
	_check(not inspector.get("_pickup").disabled, "An unheld eligible creature can append even with mixed contents already held")
	_click((inspector.get("_pickup") as Button).get_global_rect().get_center())
	_context.keeper.pickup_gold(Vector2i(9, 8))
	await process_frame
	_check(_context.keeper.held_count == 4 and queue.visible, "Mixed creature/gold pickups appear as four ordered entries")
	_check(preview.bound_item_id == front_id and preview.get("_view") == front_model and preview.bound_actor_id == _worker.id, "Appending gold and another creature never recreates or replaces the front model")
	_check(queue.get("_canvas").get_child(0).tooltip_text.begins_with("1: #%d" % _worker.id) and "75 gold" in queue.get("_canvas").get_child(1).tooltip_text, "Queue cards show creature identity followed by the separate gold amount")
	_context.keeper.inspect(_worker.id)
	_click(queue.get("_canvas").get_child(2).get_global_rect().get_center())
	await process_frame
	_check(_context.keeper.inspected_actor == _worker_b and _context.keeper.held_count == 4 and preview.bound_item_id == front_id and preview.get("_view") == front_model, "Clicking a non-front queue creature safely inspects its exact identity without changing FIFO or preview")
	var footer: Control = _hud.get("_footer_panel")
	_check(footer.get_global_rect().position.y >= 550 and footer.get_global_rect().end.y <= 784 and inspector.get_global_rect().end.x <= 1264, "Queue and individual details fit together inside the bottom hub")
	_right_click(_screen(Vector2i(8, 5)))
	_check(preview.bound_actor_id == -1 and preview.bound_gold == 75 and _context.keeper.held_count == 3, "One right-click advances only the oldest creature to the first gold entry")
	_right_click(_screen(Vector2i(8, 5)))
	_check(preview.bound_actor_id == _worker_b.id and _context.keeper.held_count == 2, "Second drop advances exactly to the queued second creature")
	_right_click(_screen(Vector2i(8, 5)))
	_check(preview.bound_gold == 125 and _context.keeper.held_count == 1, "Fourth entry preserves its own amount rather than aggregate gold")
	_right_click(_screen(Vector2i(8, 5)))
	_check(not queue.visible and _context.economy.accounted_gold(_context.actors) == initial, "Draining FIFO hides the strip and conserves finite gold")
	for index in 80:
		var actor := _context.spawn_creature(&"foundation.imp", Vector2i(9, 6))
		_context.keeper.pickup(actor.id)
	await process_frame
	await process_frame
	_check(_context.keeper.held_count == 80 and queue.rendered_count <= KeeperQueue.MAX_VISIBLE, "Eighty entries have no gameplay cap and a bounded rendered-card count")
	var scroll: ScrollContainer = queue.get("_scroll")
	scroll.scroll_horizontal = 70 * KeeperQueue.SLOT_WIDTH
	await process_frame
	_check(queue.first_visible >= 69 and queue.rendered_count <= KeeperQueue.MAX_VISIBLE, "Horizontal scrolling virtualizes later queue entries")
	_check("Next:" in queue.get("_summary").text and queue.get("_canvas").get_child(0).tooltip_text.begins_with("71:"), "The next item stays identified while later numbered entries are visible")
	_right_click(scroll.get_global_rect().get_center())
	_check(_context.keeper.held_count == 80, "Right-click over the queue cannot leak a world drop")


func _fixture() -> void:
	var grid := DungeonGrid.new(12, 12)
	for y in range(1, 11):
		for x in range(1, 11):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(5, 5), DungeonGrid.Tile.HEART)
	var registry := ContentRegistry.new()
	registry.register_module(load("res://content/modules/foundation.tres"))
	var locked := CreatureDefinition.new()
	locked.id = &"keeper_ui.ward"
	locked.keeper_pickup_allowed = false
	var module := ContentModule.new()
	module.id = &"keeper_ui.extension"
	module.definitions = [locked]
	registry.register_module(module)
	_context = GameContext.new(grid, registry)
	_worker = _context.spawn_creature(&"foundation.imp", Vector2i(3, 5))
	_resident = _context.spawn_creature(&"foundation.grubbin", Vector2i(7, 5))
	_locked = _context.spawn_creature(locked.id, Vector2i(8, 8))
	_worker_b = _context.spawn_creature(&"foundation.imp", Vector2i(4, 5))
	_context.rooms.place_initial(&"foundation.lair", [Vector2i(7, 5)])
	_context.beds.reserve(_resident, registry.get_creature(_resident.definition_id))
	_context.beds.establish(_resident)
	_keeper = KeeperController.new()
	root.add_child(_keeper)
	_keeper.setup(_context)
	_keeper.set_process(false)
	_keeper.camera.position = Vector3(12, 25, 25)
	_keeper.camera.look_at(Vector3(11, 0, 11))
	_hud = DungeonHUD.new()
	root.add_child(_hud)
	_hud.setup(_context, _keeper)


func _screen(cell: Vector2i) -> Vector2:
	return _keeper.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.grid.surface_height(cell))


func _motion(cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _screen(cell)
	root.push_input(event, true)


func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _right_click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
