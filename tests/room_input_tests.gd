extends SceneTree
## Real Viewport routing for modular room tools; this is not OS mouse automation.

const TREASURY := &"input_test.treasury"
const NEST := &"input_test.nest"
const HIDDEN := &"input_test.hidden"
const STOCK_CELL := Vector2i(1, 1)
const EXCAVATED_CELL := Vector2i(5, 4)
var _checks := 0
var _failures := 0
var _context: GameContext
var _controller: KeeperController
var _hud: DungeonHUD


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_create_fixture()
	await process_frame
	await process_frame
	_check(_hud.active_tab == &"creatures", "Creatures overview is the default hub tab")
	_ui_click(_hud.get("_rooms_tab_button"))
	await process_frame
	_check(_hud.active_tab == &"rooms", "Viewport Rooms tab reveals construction choices")
	var buttons: Dictionary = _hud.get("_construction_buttons")
	_check(buttons.has(TREASURY) and buttons.has(NEST) and not buttons.has(HIDDEN), "Toolbar discovers buildable room definitions and hides unavailable types")
	_check("Gold 100 / 200" in buttons[TREASURY].tooltip_text, "Treasury tooltip reports real per-tile stock and gold capacity")
	_context.mark_excavation([Vector2i(8, 2)])
	_ui_click(buttons[TREASURY])
	_check(_controller.build_room_id == TREASURY, "Viewport toolbar click enters Treasury construction")
	_check(_context.excavation_marks.has(Vector2i(8, 2)), "Entering construction preserves excavation orders")
	_motion(Vector2i(3, 3))
	var quote := _controller.get_preview_changes()
	_check(quote.valid and quote.cost == 25 and quote.add == [Vector2i(3, 3)], "Excavated floor hover previews one tile and its exact cost")
	_mouse(_screen(Vector2i(3, 3)), true)
	_motion(Vector2i(4, 3), MOUSE_BUTTON_MASK_LEFT)
	quote = _controller.get_preview_changes()
	_check(quote.add.size() == 2 and quote.cost == 50, "Drag previews inclusive two-tile build cost")
	_mouse(_screen(Vector2i(4, 3)), false)
	_check(_context.rooms.tiles.get(Vector2i(3, 3)) == TREASURY and _context.rooms.tiles.get(Vector2i(4, 3)) == TREASURY, "Release builds the two previewed tiles")
	_check(_context.economy.stored_gold == 50 and _context.economy.spent_gold == 50, "Build spends exactly the previewed stored gold")
	_motion(Vector2i(3, 3))
	_check(not _controller.get_preview_changes().valid, "Occupied floor cannot be built twice")
	_click(Vector2i(3, 3))
	_check(_context.economy.stored_gold == 50 and _context.rooms.tiles.get(Vector2i(3, 3)) == TREASURY, "Repeated build click neither charges nor sells an existing room tile")
	_mouse(_screen(Vector2i(3, 3)), true)
	_motion(Vector2i(4, 3), MOUSE_BUTTON_MASK_LEFT)
	_mouse(_screen(Vector2i(4, 3)), false)
	_check(_context.rooms.tiles.get(Vector2i(3, 3)) == TREASURY and _context.rooms.tiles.get(Vector2i(4, 3)) == TREASURY and _context.economy.stored_gold == 50, "Build drag over existing room tiles never sells or toggles them")
	_test_insufficient_funds()
	_motion(EXCAVATED_CELL)
	_check(not _controller.get_preview_changes().valid, "Solid terrain is blocked in room preview")
	_context.grid.set_tile(EXCAVATED_CELL, DungeonGrid.Tile.FLOOR)
	_check(_controller.get_preview_changes().valid, "Excavating hovered terrain immediately refreshes placement without moving the pointer")
	_click(EXCAVATED_CELL)
	_check(_context.rooms.tiles.get(EXCAVATED_CELL) == TREASURY, "Newly excavated floor immediately accepts room construction")
	_test_ui_cancellation()
	_test_right_click_cancel()
	_key(KEY_ESCAPE)
	_check(not _controller.is_constructing(), "Escape exits construction")
	_check(_context.excavation_marks.has(Vector2i(8, 2)), "Escape from construction preserves excavation orders")
	_click(Vector2i(6, 3))
	_check(_context.excavation_marks.size() == 1, "Default keeper action still ignores open ground")
	_ui_click(_hud.get("_sell_button"))
	_check(_controller.removing_rooms, "Viewport Sell button enters explicit room selling")
	var before := _context.economy.stored_gold
	_mouse(_screen(Vector2i(3, 3)), true)
	_motion(Vector2i(4, 3), MOUSE_BUTTON_MASK_LEFT)
	quote = _controller.get_preview_changes()
	var quoted_refund: int = quote.refund
	_check(quote.valid and quote.remove.size() == 2 and quoted_refund == 24, "Sell previews exact room tiles and rounds the 50% refund down per tile")
	_mouse(_screen(Vector2i(4, 3)), false)
	_check(not _context.rooms.tiles.has(Vector2i(3, 3)) and not _context.rooms.tiles.has(Vector2i(4, 3)), "Release removes previewed room tiles")
	_check(_context.economy.stored_gold == before + quoted_refund, "Selling empty tiles returns exactly the quoted refund")
	var after_sell := _context.economy.stored_gold
	_test_tool_change_cancellation()
	_ui_click(buttons[NEST])
	_click(Vector2i(6, 3))
	_check(_context.rooms.tiles.get(Vector2i(6, 3)) == NEST, "A second module-defined room builds through the same toolbar and world controls")
	_check(_context.economy.stored_gold == after_sell - 50, "Extension room uses its own data-defined price")
	_test_single_sale()
	_ui_click(_hud.get("_return_button"))
	_check(not _controller.is_constructing(), "Done button returns to the default keeper action")
	_check(_context.excavation_marks.has(Vector2i(8, 2)), "Construction tools and UI never alter existing excavation marks")
	_check(_context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold, "Input construction transactions conserve mined and spent gold")
	print("ROOM INPUT: %d checks, %d failures" % [_checks, _failures])
	_hud.queue_free()
	_controller.queue_free()
	await process_frame
	quit(1 if _failures else 0)


func _create_fixture() -> void:
	var grid := DungeonGrid.new(10, 8)
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(0, 0), DungeonGrid.Tile.GOLD)
	grid.set_tile(Vector2i(8, 2), DungeonGrid.Tile.ROCK)
	grid.set_tile(Vector2i(8, 3), DungeonGrid.Tile.HEART)
	grid.set_tile(Vector2i(8, 4), DungeonGrid.Tile.PORTAL)
	grid.set_tile(EXCAVATED_CELL, DungeonGrid.Tile.ROCK)
	var treasury := RoomDefinition.new()
	treasury.id = TREASURY
	treasury.display_name = "Treasury"
	treasury.gold_cost_per_tile = 25
	treasury.gold_storage_per_tile = 200
	var nest := RoomDefinition.new()
	nest.id = NEST
	nest.display_name = "Test Nest"
	nest.gold_cost_per_tile = 50
	var hidden := RoomDefinition.new()
	hidden.id = HIDDEN
	hidden.buildable = false
	var module := ContentModule.new()
	module.id = &"input_test.rooms"
	module.definitions = [treasury, nest, hidden]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Room test extension manifest registers")
	_context = GameContext.new(grid, registry)
	_check(_context.rooms.place_initial(TREASURY, [STOCK_CELL]), "Scenario seeds a real capacity-bearing Treasury")
	_check(_context.economy.deposit(STOCK_CELL, _context.economy.mine(Vector2i(0, 0), 100)), "Fixture deposits mined gold in the starting Treasury")
	_controller = KeeperController.new()
	root.add_child(_controller)
	_controller.setup(_context)
	_controller.set_process(false)
	_controller.camera.position = Vector3(8, 26, 18)
	_controller.camera.look_at(Vector3(8, 0, 7))
	_hud = DungeonHUD.new()
	root.add_child(_hud)
	_hud.setup(_context, _controller)


func _test_insufficient_funds() -> void:
	_mouse(_screen(Vector2i(3, 5)), true)
	_motion(Vector2i(5, 5), MOUSE_BUTTON_MASK_LEFT)
	var quote := _controller.get_preview_changes()
	_check(not quote.valid and quote.cost == 75, "Unaffordable area keeps an exact quote and rejects construction")
	var overlay: Node3D = _controller.get("_overlay")
	_check(overlay.get("_add_frames").is_empty() and overlay.get("_blocked_frames").size() == 3, "Unaffordable candidate tiles show blocked crosses rather than green additions")
	_mouse(_screen(Vector2i(5, 5)), false)
	_check(not _context.rooms.tiles.has(Vector2i(3, 5)) and _context.economy.stored_gold == 50, "Unaffordable release builds nothing and spends nothing")
	_mouse(_screen(Vector2i(3, 5)), true)
	_motion(Vector2i(5, 5), MOUSE_BUTTON_MASK_LEFT)
	_context.economy.deposit(STOCK_CELL, _context.economy.mine(Vector2i(0, 0), 100))
	quote = _controller.get_preview_changes()
	_check(quote.valid and quote.cost == 75 and quote.add.size() == 3, "Gold arriving during a stationary drag immediately refreshes affordability")
	_mouse(_screen(Vector2i(5, 5)), false)
	_check(_context.rooms.tiles.has(Vector2i(3, 5)) and _context.rooms.tiles.has(Vector2i(5, 5)) and _context.economy.stored_gold == 75, "Release uses the current valid quote after new gold arrives")


func _test_ui_cancellation() -> void:
	var before := _context.rooms.tiles.size()
	var stock := _context.economy.stored_gold
	var world := _screen(Vector2i(6, 3))
	var footer := Vector2(root.size.x * 0.5, root.size.y - 35)
	_mouse(world, true)
	_mouse(footer, false)
	_check(_controller.get("_drag_start") == KeeperController.INVALID_CELL, "World-to-UI release cancels a construction drag")
	_mouse(world, false)
	_check(_context.rooms.tiles.size() == before and _context.economy.stored_gold == stock, "Stale release after UI crossing cannot build or spend")
	_mouse(footer, true)
	_mouse(world, false)
	_check(_context.rooms.tiles.size() == before, "UI-to-world release never creates a construction command")


func _test_tool_change_cancellation() -> void:
	_controller.set_build_room(TREASURY)
	_mouse(_screen(Vector2i(6, 3)), true)
	_controller.set_sell_rooms()
	_mouse(_screen(Vector2i(3, 5)), false)
	_check(_context.rooms.tiles.has(Vector2i(3, 5)), "Switching tools cancels a pending drag before another tool can commit it")


func _test_right_click_cancel() -> void:
	var stock := _context.economy.stored_gold
	var tiles := _context.rooms.tiles.size()
	_mouse(_screen(Vector2i(6, 3)), true)
	_right_click(_hud.get("_sell_button").get_global_rect().get_center())
	_check(not _controller.is_constructing() and _controller.get("_drag_start") == KeeperController.INVALID_CELL, "Right-click over UI cancels an active build tool and its held drag")
	_mouse(_screen(Vector2i(6, 3)), false)
	_check(_context.rooms.tiles.size() == tiles and _context.economy.stored_gold == stock, "Left release after right-click cancellation cannot build or spend")
	_controller.set_sell_rooms()
	_mouse(_screen(Vector2i(3, 5)), true)
	_right_click(_screen(Vector2i(3, 5)))
	_mouse(_screen(Vector2i(3, 5)), false)
	_check(_context.rooms.tiles.has(Vector2i(3, 5)) and _context.economy.stored_gold == stock, "Right-click cancels a held Sell drag without deleting or refunding")
	var yaw := _controller.yaw
	var motion := InputEventMouseMotion.new()
	motion.position = _screen(Vector2i(6, 3))
	motion.relative = Vector2(12, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(motion, true)
	_check(not is_equal_approx(yaw, _controller.yaw), "Right-button camera orbit still works outside construction")
	_controller.yaw = yaw
	_controller.set_build_room(TREASURY)


func _right_click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	root.push_input(event, true)


func _test_single_sale() -> void:
	_ui_click(_hud.get("_sell_button"))
	_motion(Vector2i(6, 3))
	var quote := _controller.get_preview_changes()
	_check(quote.valid and quote.refund == 25 and quote.remove == [Vector2i(6, 3)], "A paid 50-gold room tile previews a 25-gold sale refund")
	var stock := _context.economy.stored_gold
	_click(Vector2i(6, 3))
	_check(not _context.rooms.tiles.has(Vector2i(6, 3)) and _context.economy.stored_gold == stock + 25, "Explicit Sell pays the quoted 25 gold exactly once")
	_click(Vector2i(6, 3))
	_check(not _controller.get_preview_changes().valid and _context.economy.stored_gold == stock + 25, "Selling the same floor again cannot pay another refund")


func _screen(cell: Vector2i) -> Vector2:
	return _controller.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.grid.surface_height(cell))


func _mouse(screen: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _motion(cell: Vector2i, buttons: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _screen(cell)
	event.button_mask = buttons
	root.push_input(event, true)


func _click(cell: Vector2i) -> void:
	_mouse(_screen(cell), true)
	_mouse(_screen(cell), false)


func _ui_click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	_mouse(point, true)
	_mouse(point, false)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
