extends SceneTree
## Resident information and UI isolation at the actual desktop viewport size.

var _checks := 0
var _failures: Array[String] = []
var _context: GameContext
var _hud: DungeonHUD
var _keeper: KeeperController
var _resident: CreatureState


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Headless windows default to a 64px dummy surface. Explicitly set the
	# logical viewport so layout checks exercise the promised desktop size.
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	_create_fixture()
	await process_frame
	await process_frame
	_check(_hud.active_tab == &"creatures" and not _hud.get("_debug_panel").visible and not _hud.get("_marks").is_visible_in_tree(), "Default hub shows Creatures while verbose controls and actor details stay hidden in F3")
	var hub: DungeonHub = _hud.get("_hub")
	_check(hub.creature_badges[&"resident_ui.worker"].text == "3" and hub.creature_badges[&"resident_ui.grubbin"].text == "1" and hub.creature_buttons[&"resident_ui.worker"].is_visible_in_tree() and hub.creature_buttons[&"resident_ui.grubbin"].is_visible_in_tree(), "Populated species show their actual population overlays")
	_check(not hub.creature_buttons[&"resident_ui.empty"].is_visible_in_tree(), "A registered species that has never arrived has no visible portrait or zero-count card")
	var arrival := _context.spawn_creature(&"resident_ui.empty", Vector2i(4, 4))
	_check(hub.creature_buttons[&"resident_ui.empty"].is_visible_in_tree() and hub.creature_badges[&"resident_ui.empty"].text == "1", "First arrival immediately reveals its species portrait with the correct count")
	_context.keeper.pickup(arrival.id)
	_check(hub.creature_buttons[&"resident_ui.empty"].is_visible_in_tree() and hub.creature_badges[&"resident_ui.empty"].text == "1", "Picking up the only member keeps its species in the overview")
	_context.despawn_creature(arrival.id)
	_check(not hub.creature_buttons[&"resident_ui.empty"].is_visible_in_tree(), "Removing the last member immediately hides its species card")
	_check(hub.creature_buttons[&"resident_ui.grubbin"].custom_minimum_size == Vector2(80, 80), "Species overview uses a large portrait card")
	_check(_hud.get("_worker_rows").size() == 3 and _hud.get("_resident_rows").size() == 1, "Worker and resident rows remain separate")
	_check(_hud.get("_worker_count").text == "WORKERS   3" and _hud.get("_resident_count").text == "RESIDENTS   1", "Header counts workers and residents independently")
	var worker_card: Control = _hud.get("_worker_rows")[_context.actors[0].id]
	_check(worker_card.get_node("Info/Status/Action").texture == preload("res://assets/ui/action_dig.svg") and worker_card.get_node("Info/Status/Meter").value == 65, "Worker overview shows the real mining action and strike progress")
	var row: Control = _hud.get("_resident_rows")[_resident.id]
	_check("Grubbin test" in row.get_node("Info/Name").text and row.get_node("Info/Status/Action").texture == preload("res://assets/ui/action_sleep.svg"), "Resident overview identifies the creature and shows its sleeping action icon")
	_check(row.get_node("Info/Status/Meter").value == 42 and row.get_node("Info/Status/Value").text == "42%" and "Bed 2×2 established" in row.tooltip_text, "Resident overview shows normalized energy, footprint and established-bed tooltip")
	_check(row.get_node("Portrait").texture == preload("res://assets/ui/portrait_grubbin.svg"), "Resident portrait comes from its definition")
	_check(not _hud.call("_is_ui_position", Vector2(root.size.x - 100, 150)), "Former right-sidebar area no longer blocks world interaction")
	var panels: Array = _hud.get("_input_panels")
	var panel_bounds_ok := true
	for panel: Control in panels:
		if panel.visible:
			var bounds := panel.get_global_rect()
			panel_bounds_ok = panel_bounds_ok and bounds.position.x >= 0.0 and bounds.end.x <= root.size.x and bounds.position.y >= 0.0 and bounds.end.y <= root.size.y
	_check(panel_bounds_ok, "Visible HUD panels stay inside the 1280×800 viewport (actual=%s)" % root.size)
	var header: Control = panels[0]
	var header_children_fit := true
	for child: Control in header.get_child(0).get_children():
		header_children_fit = header_children_fit and child.get_global_rect().end.x <= root.size.x - 16
	_check(header_children_fit, "Resident count does not push the header controls outside the viewport")
	var buttons: Dictionary = _hud.get("_construction_buttons")
	_check(buttons.has(&"resident_ui.lair"), "Lair is available through the existing definition-driven room toolbar")
	_check(buttons[&"resident_ui.lair"].text.is_empty() and "Lair" in buttons[&"resident_ui.lair"].tooltip_text, "Build button is icon-led with its room name in the tooltip")
	_check(hub.room_badges[&"resident_ui.lair"].text == "1" and "4 tiles" in buttons[&"resident_ui.lair"].tooltip_text, "Room overlay counts one connected room rather than its four tiles")
	_check("Beds 1 established · 0 reserved" in buttons[&"resident_ui.lair"].tooltip_text and not "Capacity 4" in buttons[&"resident_ui.lair"].tooltip_text, "Lair tooltip reports actual beds rather than implying one bed per tile")
	_context.rooms.place_initial(&"resident_ui.lair", [Vector2i(8, 6)])
	_check(hub.room_badges[&"resident_ui.lair"].text == "2", "Disconnected room extension increases the room count overlay")
	_context.rooms.place_initial(&"resident_ui.lair", [Vector2i(7, 6)])
	_check(hub.room_badges[&"resident_ui.lair"].text == "1", "Merging room groups immediately updates their count overlay")
	_context.rooms.remove([Vector2i(7, 6)])
	_check(hub.room_badges[&"resident_ui.lair"].text == "2", "Splitting room groups immediately updates their count overlay")
	_context.mark_excavation([Vector2i(0, 0)])
	var before := _context.excavation_marks.duplicate()
	_ui_click(_hud.get("_rooms_tab_button"))
	await process_frame
	_check(_hud.active_tab == &"rooms" and buttons[&"resident_ui.lair"].is_visible_in_tree(), "Rooms tab reveals the room palette through real UI input")
	_ui_click(buttons[&"resident_ui.lair"])
	_check(_keeper.is_constructing(), "Room type icon activates construction")
	_ui_click(_hud.get("_creatures_tab_button"))
	await process_frame
	_check(_hud.active_tab == &"creatures" and not _keeper.is_constructing() and _context.excavation_marks == before, "Switching to Creatures cancels construction and preserves excavation marks")
	var portrait_button: Button = hub.creature_buttons[&"resident_ui.grubbin"]
	_ui_click(portrait_button)
	_check(_context.excavation_marks == before and not _hud.get("_debug_panel").visible, "Species portrait click neither leaks into excavation nor opens a sidebar")
	_key(KEY_F3)
	await process_frame
	_check(_hud.get("_debug_panel").visible and row.is_visible_in_tree(), "F3 opens the individual actions and needs debug view")
	_mouse(row.get_global_rect().get_center(), true)
	_mouse(row.get_global_rect().get_center(), false)
	_check(_context.excavation_marks == before and _keeper.get("_drag_start") == KeeperController.INVALID_CELL, "Resident panel clicks never leak into world excavation")
	_key(KEY_F3)
	await process_frame
	_check(not row.is_visible_in_tree() and not _hud.get("_marks").is_visible_in_tree(), "F3 closes details and control hints without leaving persistent text")
	_check(_context.economy.stored_gold == 0 and _context.economy.spent_gold == 0, "Resident HUD performs no food or wage deductions")
	_test_pending_bed_ui(row)
	_context.rooms.remove([Vector2i(5, 5)])
	_check("Needs 2×2 bed" in row.tooltip_text, "Selling a bed tile immediately updates the missing-bed display")
	_check(row.get_node("Info/Status/Bed").modulate.g < 0.5, "Missing personal bed has a visible warning tint in the overview")
	_resident.energy = 0.15
	_resident.action = &"homeless"
	_resident.job_label = "Needs a reachable Lair bed"
	_hud.call("_refresh_economy_and_workers")
	_check(row.get_node("Info/Status/Meter").value == 15 and "Homeless" in row.tooltip_text, "Resident overview tracks new energy and behavior state")
	_context.despawn_creature(_resident.id)
	_hud.call("_refresh_economy_and_workers")
	await process_frame
	_check(_hud.get("_resident_rows").is_empty() and _hud.get("_resident_count").text == "RESIDENTS   0", "Removing a resident clears its row and count without touching workers")
	_check(_hud.get("_worker_rows").size() == 3, "Resident removal preserves the three worker rows")
	_check(not hub.creature_buttons[&"resident_ui.grubbin"].is_visible_in_tree(), "Last resident departure hides the empty species portrait")
	for failure in _failures:
		push_error(failure)
	print("RESIDENT UI RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_hud.queue_free()
	_keeper.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _create_fixture() -> void:
	var grid := DungeonGrid.new(10, 10)
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(0, 0), DungeonGrid.Tile.ROCK)
	var worker := CreatureDefinition.new()
	worker.id = &"resident_ui.worker"
	worker.capabilities = [&"haul"]
	var species := CreatureDefinition.new()
	species.id = &"resident_ui.grubbin"
	species.display_name = "Grubbin test"
	species.capabilities = [&"rest"]
	species.bed_size = Vector2i(2, 2)
	species.initial_energy = 0.42
	species.portrait = preload("res://assets/ui/portrait_grubbin.svg")
	var lair := RoomDefinition.new()
	lair.id = &"resident_ui.lair"
	lair.display_name = "Lair"
	lair.tags = [&"lair"]
	var module := ContentModule.new()
	module.id = &"resident_ui.fixture"
	var empty := CreatureDefinition.new()
	empty.id = &"resident_ui.empty"
	module.definitions = [worker, species, lair, empty]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "HUD fixture registers independent species and room definitions")
	_context = GameContext.new(grid, registry)
	for x in 3:
		_context.spawn_creature(worker.id, Vector2i(1 + x, 1))
	_context.actors[0].action = &"mining"
	_context.actors[0].work_progress = 0.65
	_resident = _context.spawn_creature(species.id, Vector2i(7, 7))
	_context.rooms.place_initial(lair.id, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)])
	var bed := _context.beds.reserve(_resident, species)
	_check(bed != null, "HUD fixture reserves an actual 2×2 personal footprint")
	_resident.position = bed.center(grid)
	_check(_context.beds.establish(_resident), "HUD sleeping fixture physically reaches and establishes its home")
	_resident.action = &"sleeping"
	_resident.job_label = "Sleeping in personal bed"
	_keeper = KeeperController.new()
	root.add_child(_keeper)
	_keeper.setup(_context)
	_keeper.set_process(false)
	_hud = DungeonHUD.new()
	root.add_child(_hud)
	_hud.setup(_context, _keeper)


func _test_pending_bed_ui(row: Control) -> void:
	_context.beds.release(_resident.id)
	_resident.position = _context.grid.cell_to_world(Vector2i(7, 7))
	var definition := _context.registry.get_creature(_resident.definition_id)
	var pending := _context.beds.reserve(_resident, definition)
	_hud.call("_refresh_economy_and_workers")
	_check(pending != null and not pending.established and "reserved" in row.tooltip_text and not "established" in row.tooltip_text, "A remote reservation is shown as pending rather than an established home")
	var tint: Color = row.get_node("Info/Status/Bed").modulate
	_check(tint.r > tint.g and tint.g > 0.5, "Pending home has an amber bed icon")
	_resident.action = &"claiming_bed"
	_resident.position = pending.center(_context.grid)
	_resident.work_progress = 0.45
	_hud.call("_refresh_economy_and_workers")
	_check(row.get_node("Info/Status/Action").texture == preload("res://assets/ui/bed.svg") and row.get_node("Info/Status/Meter").value == 45 and "Claiming reserved" in row.tooltip_text, "Local bed formation shows a bed action icon and actual claim progress")
	_resident.position = pending.center(_context.grid)
	_check(_context.beds.establish(_resident), "Reaching the reserved center allows local home establishment")
	_resident.action = &"sleeping"
	_resident.work_progress = 0.0
	_hud.call("_refresh_economy_and_workers")
	tint = row.get_node("Info/Status/Bed").modulate
	_check("established" in row.tooltip_text and tint.g > tint.r, "Established home turns its bed icon green")


func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _ui_click(button: Button) -> void:
	_mouse(button.get_global_rect().get_center(), true)
	_mouse(button.get_global_rect().get_center(), false)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
