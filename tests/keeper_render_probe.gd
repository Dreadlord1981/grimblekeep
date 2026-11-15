extends SceneTree
## Real scene/Viewport evidence for inspection, held cargo and interrupted needs.

var _app: Node3D
var _context: GameContext
var _keeper: KeeperController
var _hud: DungeonHUD
var _checks := 0
var _failures: Array[String] = []
var _conserved := true


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _step() -> void:
	_app.call("_physics_process", 1.0 / 30.0)
	_conserved = _conserved and _context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold + _context.economy.gem_gold_created
	_conserved = _conserved and _context.food.accounted_units() == _context.food.produced_units


func _run() -> void:
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_app.use_development_layout = true
	_app.set("starting_gold", 0)
	_app.set("use_heart_storage", false)
	root.add_child(_app)
	_app.set_physics_process(false)
	_context = _app.context
	_keeper = _app.controller
	_keeper.set_process(false)
	for child in _app.get_children():
		if child is DungeonHUD:
			_hud = child
	_context.mark_excavation([Vector2i(8, 12), Vector2i(8, 13)])
	var worker: CreatureState
	for tick in 3600:
		_step()
		for actor in _context.actors:
			if actor.carried_gold > 0 and actor.action == &"hauling":
				worker = actor
				break
		if worker != null:
			break
	_check(worker != null, "Actual miners create physical carried gold before pickup")
	if worker == null:
		_finish()
		return
	_camera(_context.grid.world_to_cell(worker.position), 20.0, 0.3, 0.85)
	_click(_actor_screen(worker))
	await _capture("keeper-worker-inspection")
	var inspector: CreatureInspector = _hud.get("_inspector")
	_check(_context.keeper.inspected_actor == worker and inspector.visible and _context.keeper.held_actor == worker, "Left press immediately lifts the worker and shows bottom-hub details; release never drops")
	var name_edit: LineEdit = inspector.get("_name_edit")
	name_edit.grab_focus()
	name_edit.text = "Muck"
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter, true)
	_check(worker.custom_name == "Muck", "Inspector name editing changes the selected individual")
	var cargo := worker.carried_gold
	_camera(Vector2i(11, 15), 25.0, 0.3, 0.9)
	_motion(Vector2i(12, 18))
	await _capture("keeper-holding-valid")
	var view := _app.find_child("Creature_%d" % worker.id, true, false) as Node3D
	_check(_context.keeper.held_actor == worker and worker.is_held and view != null and not view.visible, "Held creature has one authoritative identity and no duplicate world model")
	_check(worker.carried_gold == cargo and _context.actors.size() == 3, "Pickup preserves cargo and population")
	var hand: KeeperHand
	for child in _hud.get("_root").get_children():
		if child is KeeperHand:
			hand = child
	var preview: HeldCreaturePreview = hand.get("_held_preview")
	_check(hand != null and hand.visible and preview.bound_actor_id == worker.id and preview.get("_view") is DungeonCreatureView, "Actual held worker model is rendered beside the gripping hand")
	_check(preview.get("_identity").text == "#%d  Muck" % worker.id and preview.get("_cargo").text == "%d gold carried" % cargo, "Held display identifies the exact named individual and its cargo")
	_motion(Vector2i(8, 11))
	await _capture("keeper-holding-invalid")
	_right_click(_screen(Vector2i(8, 11)))
	_check(_context.keeper.held_actor == worker and not _keeper.get_drop_preview().valid, "Invalid raised-terrain click keeps the worker held with an explanation")
	var held_position := worker.position
	for tick in 120:
		_step()
	_check(worker.position == held_position and worker.carried_gold == cargo, "Held worker remains suspended without dropping or mining extra cargo")
	var worker_b: CreatureState
	for tick in 1200:
		for actor in _context.actors:
			if actor != worker and actor.carried_gold != cargo:
				worker_b = actor
				break
		if worker_b != null:
			break
		_step()
	_check(worker_b != null, "A second actual worker has distinct carried cargo for identity verification")
	if worker_b == null:
		_finish()
		return
	var hub: DungeonHub = _hud.get("_hub")
	for index in _context.actors.size():
		_click(hub.creature_buttons[&"foundation.imp"].get_global_rect().get_center())
		if _context.keeper.inspected_actor == worker_b:
			break
	_rename("Grout")
	_camera(Vector2i(11, 15), 25.0, 0.3, 0.9)
	_motion(Vector2i(12, 18))
	await _capture("keeper-held-a-inspecting-b")
	_check(_context.keeper.inspected_actor == worker_b and preview.bound_actor_id == worker.id and "Muck" in preview.get("_identity").text, "Changing inspected identity leaves the held model and name bound to worker A")
	var shared := _context.grid.world_to_cell(worker_b.position)
	_camera(shared, 20.0, 0.3, 0.9)
	var balance_before := _context.economy.accounted_gold(_context.actors)
	_motion(shared)
	_right_click(_screen(shared))
	await _capture("keeper-worker-dropped")
	_check(_context.keeper.held_actor == null and not worker.is_held and view.visible and _context.grid.world_to_cell(worker.position) == shared and balance_before == _context.economy.accounted_gold(_context.actors), "Right-click drops on occupied floor without changing gold or identity")
	_click((inspector.get("_pickup") as Button).get_global_rect().get_center())
	_camera(Vector2i(11, 15), 25.0, 0.3, 0.9)
	_motion(Vector2i(12, 18))
	await _capture("keeper-held-worker-b")
	_check(preview.bound_actor_id == worker_b.id and "Grout" in preview.get("_identity").text and preview.get("_cargo").text == "%d gold carried" % worker_b.carried_gold, "Worker B replaces the studio with its own model, name and different cargo")
	_check(preview.get("_wrapper").get_child_count() == 1, "Switching held identities never leaves two preview models")
	_right_click(_screen(Vector2i(12, 18)))
	for tick in 7200:
		_step()
		if _context.economy.stored_gold == 400:
			break
		if tick % 30 == 0:
			await process_frame
	_check(_context.economy.stored_gold == 400, "Dropped carrying worker resumes hauling and the complete two-seam yield is stored")
	_context.keeper.clear_inspection()
	_check(await _build(&"foundation.lair", Vector2i(10, 11), Vector2i(11, 11)), "Viewport builds a Lair for resident interruption evidence")
	_check(await _build(&"foundation.pig_pen", Vector2i(18, 14), Vector2i(19, 14)), "Viewport builds the new two-tile minimum Pig Pen")
	_keeper.exit_construction()
	_hud.select_tab(&"creatures")
	var resident: CreatureState
	var interrupted_sleep := false
	var interrupted_meal := false
	for tick in 18000:
		_step()
		if resident == null:
			for actor in _context.actors:
				if actor.definition_id == &"foundation.grubbin":
					resident = actor
		if resident != null and resident.action == &"sleeping" and not interrupted_sleep:
			interrupted_sleep = true
			_camera(_context.grid.world_to_cell(resident.position), 14.0, 0.3, 0.9)
			_click(_actor_screen(resident))
			await _capture("keeper-resident-inspection")
			var bed := _context.beds.get_bed(resident.id)
			_rename("Grimble")
			var energy := resident.energy
			var satiety := resident.satiety
			for held_tick in 120:
				_step()
			_check(_context.keeper.held_actor == resident and resident.energy == energy and resident.satiety == satiety and _context.beds.get_bed(resident.id) == bed, "Lifting a sleeper freezes needs and preserves its established personal bed")
			_camera(Vector2i(12, 12), 18.0, 0.3, 0.9)
			_motion(Vector2i(12, 13))
			await _capture("keeper-grubbin-held")
			_check(preview.bound_actor_id == resident.id and preview.get("_view") is GrubbinView and "Grimble" in preview.get("_identity").text, "Cross-species pickup renders the actual named Grubbin model")
			_right_click(_screen(Vector2i(12, 13)))
		if resident != null and resident.action == &"eating" and not interrupted_meal:
			interrupted_meal = true
			_camera(_context.grid.world_to_cell(resident.position), 14.0, -0.5, 1.0)
			_click(_actor_screen(resident))
			var stock_before := _context.food.total_units
			_check(_context.keeper.held_actor == resident and _context.food.get_reservation(resident.id) == null and _context.food.total_units == stock_before, "Lifting an eater releases its meal claim without consuming food")
			_motion(Vector2i(17, 16))
			await _capture("keeper-eating-interrupted")
			_context.despawn_creature(resident.id)
			await _capture("keeper-held-removed")
			_check(_context.keeper.held_actor == null and _context.keeper.inspected_actor == null and not resident.is_held and preview.get("_view") == null, "Removing a held creature clears custody, hub details and preview model safely")
			break
		if tick % 30 == 0:
			await process_frame
	_check(interrupted_sleep and interrupted_meal, "Actual resident loop reached both sleeping and eating interruptions")
	_check(_conserved, "Gold and food remain conserved throughout keeper interruptions")
	_finish()


func _rename(text: String) -> void:
	var inspector: CreatureInspector = _hud.get("_inspector")
	var edit: LineEdit = inspector.get("_name_edit")
	edit.grab_focus()
	edit.text = text
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
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


func _actor_screen(actor: CreatureState) -> Vector2:
	return _keeper.camera.unproject_position(actor.position + Vector3.UP * 0.85)


func _screen(cell: Vector2i) -> Vector2:
	return _keeper.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.grid.surface_height(cell))


func _motion(cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _screen(cell)
	root.push_input(event, true)


func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _camera(cell: Vector2i, distance: float, yaw: float, pitch: float) -> void:
	_keeper.focus = _context.grid.cell_to_world(cell)
	_keeper.distance = distance
	_keeper.yaw = yaw
	_keeper.pitch = pitch
	_keeper.call("_update_camera")


func _build(id: StringName, first: Vector2i, last: Vector2i) -> bool:
	_hud.select_tab(&"rooms")
	_camera(first, 20.0, -0.3, 1.05)
	_keeper.set_build_room(id)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = _screen(first)
	event.pressed = true
	root.push_input(event, true)
	var motion := InputEventMouseMotion.new()
	motion.position = _screen(last)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	event = event.duplicate()
	event.position = motion.position
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	return _context.rooms.tiles.get(first, &"") == id and _context.rooms.tiles.get(last, &"") == id


func _capture(label: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	_check(root.get_texture().get_image().save_png("res://artifacts/%s.png" % label) == OK, "Capture %s saves" % label)


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("KEEPER RENDER RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_app.queue_free()
	quit(0 if _failures.is_empty() else 1)
