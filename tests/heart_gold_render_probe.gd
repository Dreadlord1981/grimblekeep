extends SceneTree
## Actual fresh-game Heart storage and mouse-driven physical gold custody.

var _app: Node3D
var _context: GameContext
var _keeper: KeeperController
var _hud: DungeonHUD
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _run() -> void:
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(_app)
	_app.set_physics_process(false)
	_context = _app.context
	_keeper = _app.controller
	_keeper.set_process(false)
	for child in _app.get_children():
		if child is DungeonHUD:
			_hud = child
	_camera(Vector2i(14, 15), 23.0, 0.25, 1.0)
	await _capture("heart-storage-bootstrap")
	_check(_context.economy.stored_gold == 3000 and _context.economy.treasury_capacity == 4000, "Fresh game has finite 3000 stored in 4000 Heart capacity")
	_check(_context.economy.protected_storage.size() == 8 and _context.rooms.tiles.is_empty(), "Eight protected floors start without a Treasury room")
	var gold_root: Node3D
	for child in _app.get_children():
		if child is DungeonView:
			gold_root = child.get("_gold_root")
	var floor_count := 0
	var low_piles := 0
	for child in gold_root.get_children():
		if String(child.name).begins_with("HeartStorageFloor_"):
			floor_count += 1
		if child.get_meta("stage", &"") == &"heart_pile":
			low_piles += 1
	_check(floor_count == 8 and low_piles == 6, "All protected floors are dressed, with low piles only on six stocked cells")
	var source := Vector2i(13, 14)
	var empty := Vector2i(14, 16)
	var loose := Vector2i(12, 18)
	var initial := _context.economy.accounted_gold(_context.actors)
	_click(_screen(source), MOUSE_BUTTON_LEFT)
	await _capture("keeper-gold-held")
	_check(_context.keeper.held_gold == 500 and _context.economy.stored_gold == 2500, "LMB picks exact stored gold and LMB release keeps it out of spendable stock")
	var preview: HeldCreaturePreview
	for child in (_hud.get("_root") as Control).get_children():
		if child is KeeperHand:
			preview = child.get("_held_preview")
	var model: Node3D = preview.get("_view")
	_check(preview.visible and preview.bound_gold == 500 and model.name == "HeldGold" and "500" in preview.get("_identity").text, "Hand shows a real gold model and exact held amount")
	_context.keeper.inspect(_context.actors[0].id)
	await process_frame
	var inspector: CreatureInspector = _hud.get("_inspector")
	_check(preview.get("_view") == model and preview.bound_gold == 500 and not inspector.get("_pickup").disabled, "Inspecting a creature keeps front gold custody and allows appending the creature")
	_click(inspector.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	_check(_context.keeper.held_gold == 500, "Right-click on bottom-hub details cannot drop gold through UI")
	_click(_screen(Vector2i(9, 10)), MOUSE_BUTTON_RIGHT)
	await _capture("keeper-gold-invalid")
	_check(_context.keeper.held_gold == 500, "Solid terrain rejects the drop without losing custody")
	_click(_screen(empty), MOUSE_BUTTON_RIGHT)
	await _capture("heart-storage-deposited")
	_check(_context.keeper.held_gold == 0 and _context.economy.stored_by_cell.get(empty, 0) == 500 and _context.economy.stored_gold == 3000, "RMB fills actual free Heart storage without a Treasury")
	_click(_screen(empty), MOUSE_BUTTON_LEFT)
	_click(_screen(loose), MOUSE_BUTTON_RIGHT)
	await _capture("keeper-gold-loose")
	_check(_context.economy.ground_gold.get(loose, 0) == 500 and _context.keeper.held_gold == 0 and _context.economy.stored_gold == 2500, "RMB ordinary floor receives exactly the held loose gold")
	for tick in 2400:
		_app.call("_physics_process", 1.0 / 30.0)
		if _context.economy.stored_gold == 3000 and _context.economy.ground_gold.is_empty():
			break
		if tick % 60 == 0:
			await process_frame
	await _capture("heart-storage-worker-return")
	_check(_context.economy.stored_gold == 3000 and _context.economy.ground_gold.is_empty(), "Actual workers recover loose gold into protected Heart storage before any Treasury exists")
	_check(_context.economy.accounted_gold(_context.actors) == initial, "Custody, ground drop and worker recovery conserve all finite gold")
	_check(preview.get("_view") == null and preview.get("_viewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, "Empty gold hand clears its model and stops studio rendering")
	_check("Keeper 0" in (_hud.get("_stored_gold") as Label).tooltip_text, "Gold tooltip includes keeper custody")
	for failure in _failures:
		push_error(failure)
	print("HEART GOLD RENDER RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_app.queue_free()
	quit(0 if _failures.is_empty() else 1)


func _camera(cell: Vector2i, distance: float, yaw: float, pitch: float) -> void:
	_keeper.focus = _context.grid.cell_to_world(cell)
	_keeper.distance = distance
	_keeper.yaw = yaw
	_keeper.pitch = pitch
	_keeper.call("_update_camera")


func _screen(cell: Vector2i) -> Vector2:
	return _keeper.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.grid.surface_height(cell))


func _click(point: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _capture(label: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	_check(root.get_texture().get_image().save_png("res://artifacts/%s.png" % label) == OK, "Capture %s saves" % label)
