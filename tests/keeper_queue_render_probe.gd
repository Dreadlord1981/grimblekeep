extends SceneTree
## Actual Viewport FIFO controls; stress actors are a separate UI-only fixture.

var _app: Node3D
var _context: GameContext
var _keeper: KeeperController
var _hud: DungeonHUD
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _run() -> void:
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_app.use_development_layout = true
	root.add_child(_app)
	_app.set_physics_process(false)
	_context = _app.context
	_keeper = _app.controller
	_keeper.set_process(false)
	for child in _app.get_children():
		if child is DungeonHUD:
			_hud = child
	# The normal room/portal simulation supplies the cross-species queue member.
	_context.rooms.build(&"foundation.lair", [Vector2i(12, 12)])
	var resident: CreatureState
	for tick in 1200:
		_app.call("_physics_process", 1.0 / 30.0)
		for actor in _context.actors:
			if actor.definition_id == &"foundation.grubbin":
				resident = actor
		if resident != null:
			break
	_check(resident != null, "Normal Lair attraction supplies the Grubbin")
	if resident == null:
		_finish()
		return
	var a: CreatureState = _context.actors[0]
	var b: CreatureState = _context.actors[1]
	_name_actor(a, "Muck")
	_name_actor(b, "Grout")
	_name_actor(resident, "Grimble")
	_camera(_context.grid.world_to_cell(a.position))
	_click(_actor_screen(a), MOUSE_BUTTON_LEFT)
	await process_frame
	var preview: HeldCreaturePreview
	for child in (_hud.get("_root") as Control).get_children():
		if child is KeeperHand:
			preview = child.get("_held_preview")
	var first_model: Node3D = preview.get("_view")
	var first_id := preview.bound_item_id
	_camera(Vector2i(14, 15))
	_click(_screen(Vector2i(13, 14)), MOUSE_BUTTON_LEFT)
	_camera(_context.grid.world_to_cell(resident.position))
	_click(_actor_screen(resident), MOUSE_BUTTON_LEFT)
	_camera(Vector2i(14, 15))
	_click(_screen(Vector2i(15, 14)), MOUSE_BUTTON_LEFT)
	_camera(_context.grid.world_to_cell(b.position))
	_click(_actor_screen(b), MOUSE_BUTTON_LEFT)
	_camera(Vector2i(14, 15))
	var motion := InputEventMouseMotion.new()
	motion.position = _screen(Vector2i(12, 15))
	root.push_input(motion, true)
	await _capture("keeper-mixed-queue")
	var quote: Dictionary = _keeper.get_drop_preview()
	_check(quote.get("valid", false) and quote.get("cell") == Vector2i(12, 15) and (_hud.get("_cursor_feedback") as Label).text == "Right-click: drop next", "Rendered hand feedback and valid-floor target agree after camera changes")
	_check(_context.keeper.held_count == 5 and _context.keeper.total_held_gold == 950, "Three actual creatures and two separate gold pickups append without a type/count restriction")
	_check(preview.bound_item_id == first_id and preview.get("_view") == first_model and preview.bound_actor_id == a.id, "Appending four later entries preserves the oldest creature model exactly")
	var items := _context.keeper.get_items()
	_check(items.size() == 5 and items[0].actor == a and items[1].gold_amount == 450 and items[2].actor == resident and items[3].gold_amount == 500 and items[4].actor == b, "Authoritative mixed sequence matches numbered UI order after paying50 for the Lair")
	var initial := _context.economy.accounted_gold(_context.actors)
	_click(_screen(Vector2i(12, 15)), MOUSE_BUTTON_RIGHT)
	await _capture("keeper-queue-gold-next")
	_check(_context.keeper.held_count == 4 and preview.bound_gold == 450 and preview.bound_actor_id == -1 and _context.keeper.total_held_gold == 950, "First drop advances to450 gold even though950 gold remains in custody")
	var gold_model: Node3D = preview.get("_view")
	var gold_id := preview.bound_item_id
	_click(_screen(Vector2i(12, 15)), MOUSE_BUTTON_RIGHT)
	await _capture("keeper-queue-grubbin-next")
	_check(_context.keeper.held_count == 3 and preview.bound_actor_id == resident.id and preview.get("_view") is GrubbinView, "Second drop consumes only the oldest gold entry and shows the Grubbin next")
	_click(_screen(Vector2i(12, 15)), MOUSE_BUTTON_RIGHT)
	await _capture("keeper-queue-second-gold")
	_check(preview.bound_gold == 500 and preview.bound_item_id != gold_id and preview.get("_view") != gold_model, "Separate gold pickups retain distinct queue identity and exact amounts")
	_click(_screen(Vector2i(12, 15)), MOUSE_BUTTON_RIGHT)
	_check(preview.bound_actor_id == b.id and _context.keeper.held_count == 1, "Fourth drop advances to the second worker")
	_click(_screen(Vector2i(12, 15)), MOUSE_BUTTON_RIGHT)
	_check(not _context.keeper.is_holding() and _context.economy.ground_gold.get(Vector2i(12, 15), 0) == 950, "Fifth drop drains exactly five entries and leaves both gold pickups recoverable")
	_check(_context.economy.accounted_gold(_context.actors) == initial and not a.is_held and not b.is_held and not resident.is_held, "Full FIFO drain preserves identities and the gold ledger")
	# Presentation stress fixture: no gameplay population limit is implied.
	for index in 40:
		var actor := _context.spawn_creature(&"foundation.imp", Vector2i(12, 18))
		_name_actor(actor, "Queue imp %d" % (index + 1))
		_context.keeper.pickup(actor.id)
	await process_frame
	var queue: KeeperQueue = _hud.get("_keeper_queue")
	var scroll: ScrollContainer = queue.get("_scroll")
	scroll.scroll_horizontal = 32 * KeeperQueue.SLOT_WIDTH
	await _capture("keeper-queue-scrolled")
	_check(_context.keeper.held_count == 40 and queue.first_visible >= 31 and queue.rendered_count <= KeeperQueue.MAX_VISIBLE, "Forty-item stress queue scrolls to later entries with bounded rendered cards")
	var count := _context.keeper.held_count
	_click(scroll.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	_check(_context.keeper.held_count == count, "Right-click on scrolled queue never drops through UI")
	_finish()


func _name_actor(actor: CreatureState, text: String) -> void:
	_context.keeper.inspect(actor.id)
	_context.keeper.rename_selected(text)


func _camera(cell: Vector2i) -> void:
	_keeper.focus = _context.grid.cell_to_world(cell)
	_keeper.distance = 24.0
	_keeper.yaw = 0.25
	_keeper.pitch = 1.0
	_keeper.call("_update_camera")


func _actor_screen(actor: CreatureState) -> Vector2:
	return _keeper.camera.unproject_position(actor.position + Vector3.UP * 0.85)


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


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("KEEPER QUEUE RENDER RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	_app.queue_free()
	quit(0 if _failures.is_empty() else 1)
