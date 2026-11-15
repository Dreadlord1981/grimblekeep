extends SceneTree
## Real scene, actual Viewport room input and accelerated simulation only here.

var _capture_ok := true
var _app: Node3D
var _context: GameContext
var _keeper: KeeperController
var _hud: DungeonHUD


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_app.use_development_layout = true
	_app.starting_gold = 0
	_app.use_heart_storage = false
	root.add_child(_app)
	_app.set_physics_process(false)
	_context = _app.context
	_keeper = _app.controller
	for child in _app.get_children():
		if child is DungeonHUD:
			_hud = child
	_keeper.set_process(false)
	await _capture("hub-creatures-default")
	# Finite-gold rendering fixture; ordinary mining/hauling is separately tested.
	var extracted := 0
	for cell in _context.grid.cells_of_type(DungeonGrid.Tile.GOLD):
		if extracted >= 800:
			break
		extracted += _context.economy.mine(cell, 200)
	var funded := _context.economy.deposit(Vector2i(16, 18), 500)
	funded = _context.economy.deposit(Vector2i(17, 18), 300) and funded
	var built_lair := await _build_area(&"foundation.lair", Vector2i(9, 11), Vector2i(11, 13))
	var built_treasury := await _build_area(&"foundation.treasury", Vector2i(19, 14), Vector2i(19, 16))
	_keeper.exit_construction()
	_select_tab(&"rooms")
	_camera(Vector2i(13, 14), 27.0, -0.45, 1.05)
	await _capture("lair-and-treasury-overview")
	var lair_tile := _app.find_child("RoomTile_9_11", true, false)
	var treasury_tile := _app.find_child("RoomTile_19_14", true, false)
	var walls := lair_tile != null and treasury_tile != null
	if walls:
		walls = lair_tile.has_node("RoomWall_0_-1") and treasury_tile.has_node("RoomWall_1_0")
		walls = walls and lair_tile.get_meta("floor_style") == &"patched_rugs" and treasury_tile.get_meta("floor_style") == &"inlaid_tiles"
	var mineral_tile := _app.find_child("RoomTile_9_12", true, false)
	var minerals_clear := mineral_tile != null and not mineral_tile.has_node("RoomWall_-1_0")
	_camera(Vector2i(19, 15), 13.0, -0.75, 0.80)
	await _capture("treasury-wall-inlays")
	_camera(Vector2i(10, 12), 14.0, 0.4, 0.85)
	_select_tab(&"creatures")
	await _capture("lair-before-arrival")
	var prearrival_bare := _app.find_children("PersonalBed_*", "Node3D", true, false).is_empty()
	var resident: CreatureState
	var arrived := false
	var arrival_bare := false
	var approach_bare := false
	var claim_seen := false
	var claim_bare := false
	var local_established := false
	var bed_seen := false
	var walking := false
	var gait_changed := false
	var slept := false
	var woke := false
	var cycles := 0
	var previous_sleeping := false
	var sleep_energy := 0.0
	var recovered := false
	var bed_departure := false
	var conserved := true
	for tick in 18000:
		_app.call("_physics_process", 1.0 / 30.0)
		conserved = conserved and _context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold
		if resident == null:
			for actor in _context.actors:
				if actor.definition_id == &"foundation.grubbin":
					resident = actor
					arrived = _context.grid.get_tile(_context.grid.world_to_cell(actor.position)) == DungeonGrid.Tile.PORTAL
					var pending := _context.beds.get_bed(actor.id)
					arrival_bare = pending != null and not pending.established and _app.find_child("PersonalBed_%d" % actor.id, true, false) == null
					_camera(Vector2i(12, 10), 29.0, 0.4, 1.0)
					await _capture("lair-arrival-pending")
					break
		if resident != null:
			var bed := _context.beds.get_bed(resident.id)
			if bed != null and not bed.established and not approach_bare and resident.action == &"walking" and resident.position.distance_to(bed.center(_context.grid)) < 5.0:
				approach_bare = _app.find_child("PersonalBed_%d" % resident.id, true, false) == null
				_camera(Vector2i(10, 12), 15.0, 0.4, 0.85)
				await _capture("lair-approach-pending")
			if bed != null and resident.action == &"claiming_bed" and not claim_seen:
				claim_seen = true
				claim_bare = not bed.established and resident.position.distance_to(bed.center(_context.grid)) <= 0.08 and _app.find_child("PersonalBed_%d" % resident.id, true, false) == null
				_camera(_context.grid.world_to_cell(resident.position), 9.0, resident.heading, 0.65)
				await _capture("grubbin-claiming-bed")
			if bed != null and bed.established and not bed_seen:
				bed_seen = true
				local_established = resident.position.distance_to(bed.center(_context.grid)) <= 0.08
				_camera(Vector2i(10, 12), 16.0, 0.35, 0.85)
				await _capture("lair-personal-bed")
				local_established = local_established and _app.find_child("PersonalBed_%d" % resident.id, true, false) != null
			if resident.action == &"walking" and not walking and _context.grid.get_tile(_context.grid.world_to_cell(resident.position)) == DungeonGrid.Tile.FLOOR:
				walking = true
				gait_changed = await _capture_gait(resident)
			var is_sleeping := resident.action == &"sleeping"
			if is_sleeping and not previous_sleeping:
				cycles += 1
			if is_sleeping and not slept:
				slept = true
				sleep_energy = resident.energy
				_camera(Vector2i(10, 12), 12.0, 0.4, 0.85)
				await _capture("grubbin-sleeping")
			if slept and is_sleeping and resident.energy > sleep_energy + 0.2:
				recovered = true
			if slept and previous_sleeping and not is_sleeping:
				if not woke:
					_camera(_context.grid.world_to_cell(resident.position), 9.0, resident.heading, 0.65)
					await _capture("grubbin-awake")
					bed_departure = await _capture_bed_departure(resident)
				woke = true
			previous_sleeping = is_sleeping
			if cycles >= 2 and woke and recovered:
				break
		if tick % 30 == 0:
			await process_frame
	_camera(Vector2i(10, 12), 14.0, 0.4, 0.90)
	await _capture("lair-rest-cycle")
	# Room panels must not obscure the existing excavation glow on a rock face.
	_context.mark_excavation([Vector2i(9, 10)], GameContext.MarkOperation.ADD)
	_camera(Vector2i(9, 11), 11.0, 0.15, 0.45)
	await _capture("lair-marked-wall-glow")
	lair_tile = _app.find_child("RoomTile_9_11", true, false)
	var marked_wall_hidden := lair_tile != null and not lair_tile.has_node("RoomWall_0_-1")
	_context.mark_excavation([Vector2i(9, 10)], GameContext.MarkOperation.REMOVE)
	await _capture("lair-wall-restored")
	lair_tile = _app.find_child("RoomTile_9_11", true, false)
	var wall_restored := lair_tile != null and lair_tile.has_node("RoomWall_0_-1")
	# Decorations must disappear when their solid backing is excavated.
	_context.grid.set_tile(Vector2i(9, 10), DungeonGrid.Tile.FLOOR)
	await process_frame
	await process_frame
	lair_tile = _app.find_child("RoomTile_9_11", true, false)
	var wall_updated := lair_tile != null and not lair_tile.has_node("RoomWall_0_-1")
	var bed_removed := false
	var bed_lift_reset := false
	if resident != null:
		var bed := _context.beds.get_bed(resident.id)
		if bed != null:
			var old_anchor := bed.anchor
			_context.rooms.remove(bed.cells.duplicate())
			_app.call("_physics_process", 1.0 / 30.0)
			await process_frame
			var replacement := _context.beds.get_bed(resident.id)
			bed_removed = (replacement == null or replacement.anchor != old_anchor) and resident.action != &"sleeping"
	await _capture("lair-bed-removed")
	if resident != null:
		var view := _app.find_child("Creature_%d" % resident.id, true, false) as GrubbinView
		var body := view.get("_body") as Node3D if view != null else null
		bed_lift_reset = body != null and body.position.y < 0.08
	var debug := InputEventKey.new()
	debug.keycode = KEY_F3
	debug.pressed = true
	root.push_input(debug, true)
	await _capture("hub-f3-diagnostics")
	conserved = conserved and _context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold
	print("LAIR RENDER: funded=%s lair=%s treasury=%s styles=%s minerals=%s prearrival_bare=%s arrival=%s arrival_bare=%s approach_bare=%s claim=%s claim_bare=%s established_locally=%s bed=%s walking=%s gait=%s sleep=%s wake=%s recovery=%s departure=%s cycles=%d marked_wall_hidden=%s wall_restored=%s wall_update=%s bed_removed=%s lift_reset=%s conserved=%s captures=%s" % [funded, built_lair, built_treasury, walls, minerals_clear, prearrival_bare, arrived, arrival_bare, approach_bare, claim_seen, claim_bare, local_established, bed_seen, walking, gait_changed, slept, woke, recovered, bed_departure, cycles, marked_wall_hidden, wall_restored, wall_updated, bed_removed, bed_lift_reset, conserved, _capture_ok])
	var success := funded and built_lair and built_treasury and walls and minerals_clear and prearrival_bare and arrived and arrival_bare and approach_bare and claim_seen and claim_bare and local_established and bed_seen and walking and gait_changed and slept and woke and recovered and bed_departure and cycles >= 2 and marked_wall_hidden and wall_restored and wall_updated and bed_removed and bed_lift_reset and conserved and _capture_ok
	_app.queue_free()
	await process_frame
	quit(0 if success else 1)


func _camera(cell: Vector2i, distance: float, yaw: float, pitch: float) -> void:
	_keeper.focus = _context.grid.cell_to_world(cell)
	_keeper.distance = distance
	_keeper.yaw = yaw
	_keeper.pitch = pitch
	_keeper.call("_update_camera")


func _select_tab(tab: StringName) -> void:
	if _hud != null and _hud.has_method("select_tab"):
		_hud.call("select_tab", tab)


func _capture_gait(actor: CreatureState) -> bool:
	var first_rotation := 0.0
	var captured := false
	for tick in range(240):
		_app.call("_physics_process", 1.0 / 30.0)
		await process_frame
		if actor.action != &"walking":
			continue
		var view := _app.find_child("Creature_%d" % actor.id, true, false) as GrubbinView
		if view == null:
			continue
		var leg := view.get("_left_leg") as Node3D
		if leg == null:
			continue
		if not captured or absf(leg.rotation.x - first_rotation) > 0.12:
			_camera(_context.grid.world_to_cell(actor.position), 9.0, actor.heading, 0.65)
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://artifacts")
			var path := "res://artifacts/grubbin-walking-a.png" if not captured else "res://artifacts/grubbin-walking-b.png"
			var result := root.get_texture().get_image().save_png(path)
			_capture_ok = _capture_ok and result == OK
			if captured:
				return true
			first_rotation = leg.rotation.x
			captured = true
	return false


func _capture_bed_departure(actor: CreatureState) -> bool:
	var bed := _context.beds.get_bed(actor.id)
	if bed == null or not bed.established:
		return false
	for tick in range(240):
		_app.call("_physics_process", 1.0 / 30.0)
		await process_frame
		if actor.action != &"walking" or actor.position.distance_to(bed.center(_context.grid)) < 0.10:
			continue
		var view := _app.find_child("Creature_%d" % actor.id, true, false) as GrubbinView
		var body := view.get("_body") as Node3D if view != null else null
		_camera(bed.anchor, 9.0, actor.heading, 0.65)
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png("res://artifacts/grubbin-leaving-bed.png")
		_capture_ok = _capture_ok and result == OK
		return body != null and body.position.y >= 0.40 and body.position.y <= 0.55
	return false


func _build_area(definition_id: StringName, first: Vector2i, last: Vector2i) -> bool:
	_select_tab(&"rooms")
	_camera(Vector2i((first.x + last.x) / 2, (first.y + last.y) / 2), 20.0, -0.3, 1.05)
	_keeper.set_build_room(definition_id)
	var start := _keeper.camera.unproject_position(_context.grid.cell_to_world(first))
	var finish := _keeper.camera.unproject_position(_context.grid.cell_to_world(last))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = start
	event.pressed = true
	root.push_input(event, true)
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	var preview := _keeper.get_preview_changes()
	var expected := (absi(last.x - first.x) + 1) * (absi(last.y - first.y) + 1)
	var quoted: bool = preview.get("valid", false) and preview.get("add", []).size() == expected
	if definition_id == &"foundation.lair":
		await _capture("hub-build-cursor-quote")
	event = event.duplicate()
	event.position = finish
	event.pressed = false
	root.push_input(event, true)
	return quoted and _context.rooms.tiles.get(first, &"") == definition_id and _context.rooms.tiles.get(last, &"") == definition_id


func _capture(label: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var result := root.get_texture().get_image().save_png("res://artifacts/%s.png" % label)
	_capture_ok = _capture_ok and result == OK
	if result != OK:
		push_error("Lair capture failed: %s" % error_string(result))
