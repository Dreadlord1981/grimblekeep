extends SceneTree
## Actual compact scene, Viewport digging, worker lamps/claim, hidden contents/save.

const PORTAL := Vector2i(14, 6)
const STEP := 1.0 / 30.0
var _app: Node3D
var _context: GameContext
var _view: DungeonView
var _checks := 0
var _failures: Array[String] = []
var _slot := "res://artifacts/exploration-render-%d.json" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_app.save_path = _slot
	root.add_child(_app)
	_app.set_physics_process(false)
	_context = _app.context
	_app.controller.set_process(false)
	_find_view()
	await _capture("exploration-dark-start")
	_check(_context.grid.cells_of_type(DungeonGrid.Tile.FLOOR).size() == 24 and _context.rooms.tiles.is_empty(), "Compact start has only24 Heart-chamber floor cells and no ready-made rooms")
	_check(_context.actors.size() == 3 and _context.economy.stored_gold == 3000 and _context.economy.protected_storage.size() == 8, "Compact start preserves three imps and finite protected starting gold")
	_check(_context.exploration.enabled and not _context.exploration.is_revealed(PORTAL), "Unconnected portal is unknown to normal exploration")
	_check(not _context.infrastructure.is_portal_claimed(PORTAL), "Starting portal has no keeper ownership")
	var portal: DungeonPortalView = _view.get("_portal_views")[PORTAL]
	_check(portal.get_node("UnexploredBeacon").visible and not portal.get_node("DiscoveredStructure").visible, "Distant magical beacon is visible without disclosing the portal chamber")
	_check(_view.find_children("*", "DirectionalLight3D", true, false).is_empty(), "No global daylight illuminates the dungeon")
	var ambient := 1.0
	for child in _view.get_children():
		if child is WorldEnvironment:
			ambient = child.environment.ambient_light_energy
	_check(ambient < 0.1, "Only a faint ambient baseline remains for silhouettes")
	var lights: DungeonInfrastructureView = _view.get_node("InfrastructureLights")
	_check(lights.lamp_count == 2 and _context.infrastructure.lamps.size() == 2, "Exactly the two authored starting lamps are rendered before imp work")
	_check(_view.get_node("TerrainBatches").has_node("UnexploredFog"), "Unknown terrain uses opaque fog instead of rendering hidden resources")
	# Hidden actors, food and room art must not leak above opaque terrain/labels.
	var hidden := Vector2i(22, 20)
	_context.grid.set_tile(hidden, DungeonGrid.Tile.FLOOR)
	_context.grid.set_tile(hidden + Vector2i.RIGHT, DungeonGrid.Tile.FLOOR)
	_context.rooms.place_initial(&"foundation.pig_pen", [hidden, hidden + Vector2i.RIGHT])
	var source: Vector2i = _context.food.sources.keys()[0]
	_context.food.produce(source, &"foundation.cave_pig", 1)
	var secret := _context.spawn_creature(&"foundation.grubbin", hidden)
	await process_frame
	await process_frame
	_check(not (_view.get("_actor_views")[secret.id] as Node3D).visible, "A tall creature in an unknown disconnected area is hidden explicitly")
	var room_view: DungeonRoomView = _view.get_node("Rooms")
	_check(not room_view.has_node("RoomTile_22_20"), "Hidden room floors and labels never disclose an unexplored chamber")
	var food_view: DungeonFoodView = _view.get_node("PhysicalFood")
	_check(not (food_view.get("_units").values()[0] as Node3D).visible, "Hidden physical food never leaks above fog")
	_context.despawn_creature(secret.id)
	_context.rooms.remove([hidden, hidden + Vector2i.RIGHT])
	_context.grid.set_tile(hidden, DungeonGrid.Tile.ROCK)
	# Unseen rock accepts a plan without exposing its contents or executing remotely.
	var initial_revealed := _context.exploration.revealed.size()
	_click_cell(Vector2i(14, 7))
	_check(_context.excavation_marks.has(Vector2i(14, 7)) and not _context.exploration.is_revealed(Vector2i(14, 7)), "Viewport queues an unseen excavation plan without revealing the target")
	_context.clear_excavation_marks()
	var dug := true
	for y in range(12, 6, -1):
		var cell := Vector2i(14, y)
		_click_cell(cell)
		dug = dug and _context.excavation_marks.has(cell)
		dug = _until(func() -> bool: return _context.grid.get_tile(cell) == DungeonGrid.Tile.FLOOR, 30.0) and dug
		await process_frame
		if y == 10:
			await _capture("exploration-frontier-dig")
	_check(dug and _context.exploration.revealed.size() > initial_revealed, "Actual Viewport marks and imp excavation reveal a route through six frontier blocks")
	_check(_until(func() -> bool: return _context.infrastructure.is_portal_claimed(PORTAL), 30.0), "An imp reaches and physically claims the newly connected portal")
	_check(_until(func() -> bool: return _context.infrastructure.lamps.size() >= 4, 30.0), "Idle imps install additional local lamps in the expanded passage")
	await _capture("exploration-claimed-lamps")
	portal = _view.get("_portal_views")[PORTAL]
	_check(portal.get_meta("claimed", false) and portal.get_meta("discovered", false) and not portal.get_node("UnexploredBeacon").visible, "Claimed portal renders its awakened real structure instead of the hidden beacon")
	lights = _view.get_node("InfrastructureLights")
	_check(lights.lamp_count == _context.infrastructure.lamps.size(), "Rendered lamps exactly follow physical completed installations")
	_check(_context.rooms.build(&"foundation.lair", [Vector2i(12, 17)]).success and _context.rooms.build(&"foundation.pig_pen", [Vector2i(15, 13), Vector2i(16, 13)]).success, "Keeper can build basic living rooms on known floor after opening the route")
	_check(_until(func() -> bool: return _context.actors.size() == 4, 15.0), "Claimed portal recruits a Grubbin when actual Lair space is available")
	_check(_until(func() -> bool: return _context.beds.beds.size() == 1 and (_context.beds.beds.values()[0] as BedState).established, 30.0), "Arriving resident walks home and establishes its bed locally")
	_check(_until(func() -> bool: return _context.food.produced_units >= 2, 20.0), "Player's visible two-tile pen produces a physical pig")
	_app.controller.distance = 25.0
	_app.controller.focus = _context.grid.cell_to_world(Vector2i(14, 13))
	_app.controller.call("_update_camera")
	await _capture("exploration-lit-rooms")
	room_view = _view.get_node("Rooms")
	_check(room_view.has_node("RoomTile_12_17") and room_view.has_node("RoomTile_15_13"), "Actual built room floors remain recognizable under local light")
	var actor: CreatureState = _context.actors[0]
	_context.keeper.pickup(actor.id)
	_context.keeper.pickup_gold(Vector2i(13, 14), 23)
	var known := _context.exploration.revealed.duplicate()
	var lamps := _context.infrastructure.lamps.duplicate()
	var save_result: Dictionary = _app.save_game()
	_check(save_result.success, "Expanded claimed dungeon with mixed held contents saves: %s" % save_result.reason)
	_context.infrastructure.portal_progress[PORTAL] = 0.0
	_context.infrastructure.lamps.clear()
	_context.exploration.revealed.clear()
	_check(_app.load_game().success, "Expanded state restores through actual app session replacement")
	_context = _app.context
	_app.controller.set_process(false)
	_find_view()
	var motion := InputEventMouseMotion.new()
	motion.position = _app.controller.camera.unproject_position(_context.grid.cell_to_world(Vector2i(16, 15)))
	root.push_input(motion, true)
	await _capture("exploration-loaded")
	_check(_context.exploration.revealed == known and _context.infrastructure.lamps == lamps and _context.infrastructure.is_portal_claimed(PORTAL), "Explored knowledge, exact lamp sites and claimed portal survive load")
	_check(_context.keeper.held_count == 2 and _context.keeper.held_actor.id == actor.id and _context.keeper.total_held_gold == 23, "Infrastructure save/load preserves ordered creature/gold custody")
	_check((_view.get_node("InfrastructureLights") as DungeonInfrastructureView).lamp_count == lamps.size() and (_view.get("_portal_views")[PORTAL] as DungeonPortalView).get_meta("claimed", false), "Freshly rebuilt presentation reflects restored lights and ownership")
	_check(_context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold + _context.economy.gem_gold_created, "Construction/exploration/claim creates no gold and preserves every ledger balance")
	_finish()


func _find_view() -> void:
	for child in _app.get_children():
		if child is DungeonView:
			_view = child


func _click_cell(cell: Vector2i) -> void:
	var point: Vector2 = _app.controller.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.exploration.surface_height(cell))
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _until(condition: Callable, seconds: float) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_app.call("_physics_process", STEP)
	return condition.call()


func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	_check(root.get_texture().get_image().save_png("res://artifacts/%s.png" % label) == OK, "Capture %s saves" % label)


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("EXPLORATION RENDER: %d checks, %d failures" % [_checks, _failures.size()])
	_app.free()
	quit(0 if _failures.is_empty() else 1)
