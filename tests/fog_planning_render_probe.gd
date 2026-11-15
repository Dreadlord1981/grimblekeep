extends SceneTree
## Multi-row room planning uses actual Viewport input on uniform fog geometry.

const STEP := 1.0 / 30.0
const FIRST := Vector2i(16, 12)
const LAST := Vector2i(19, 6)
var _app: Node3D
var _context: GameContext
var _keeper: KeeperController
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(_app)
	_app.set_physics_process(false)
	_context = _app.context
	_keeper = _app.controller
	_keeper.set_process(false)
	_keeper.focus = _context.grid.cell_to_world(Vector2i(17, 11))
	_keeper.distance = 31.0
	_keeper.pitch = 1.05
	_keeper.yaw = 0.15
	_keeper.call("_update_camera")
	# Different unknown contents must give identical planning eligibility/geometry.
	var hidden_floor := Vector2i(16, 6)
	var hidden_bedrock := Vector2i(17, 6)
	var hidden_gold := Vector2i(18, 6)
	var hidden_portal := Vector2i(19, 6)
	_context.grid.set_tile(hidden_floor, DungeonGrid.Tile.FLOOR)
	_context.grid.set_tile(hidden_bedrock, DungeonGrid.Tile.BEDROCK)
	_context.grid.set_tile(hidden_gold, DungeonGrid.Tile.GOLD)
	_context.grid.set_tile(hidden_portal, DungeonGrid.Tile.PORTAL)
	await process_frame
	await process_frame
	var known := _context.exploration.revealed.duplicate()
	_mouse(_screen(FIRST), true)
	_motion(LAST)
	_check(_keeper.get_preview_changes().add.size() == 28, "Four-by-seven drag previews all28 cells across multiple hidden rows")
	_mouse(_screen(LAST), false)
	_check(_context.excavation_marks.size() == 28 and _context.excavation_marks.has(hidden_floor) and _context.excavation_marks.has(hidden_bedrock) and _context.excavation_marks.has(hidden_portal), "Release queues the entire rectangle without testing concealed contents")
	_check(_context.exploration.revealed == known, "Planning does not reveal terrain or hidden resources")
	var overlay: KeeperSelectionOverlay = _keeper.get("_overlay")
	var uniform := true
	for cell in [hidden_floor, hidden_bedrock, hidden_gold, hidden_portal]:
		var frame: Node3D = overlay.marked_frames[cell]
		var shell := frame.get_node("ExcavationGlow") as MeshInstance3D
		uniform = uniform and is_equal_approx(frame.position.y, DungeonExploration.FOG_HEIGHT + 0.05) and is_equal_approx(shell.scale.y, DungeonExploration.FOG_HEIGHT + 0.12) and _keeper.get_target_cell(_screen(cell)) == cell
	_check(uniform, "Unknown floor, bedrock, gold and portal use identical fog-height picking and amber shells")
	await _capture("fog-planned-room")
	_mouse(_screen(FIRST), true)
	_motion(LAST)
	_check(_keeper.get_preview_changes().remove.size() == 28 and _keeper.get_preview_changes().add.is_empty(), "Repeating the full rectangle clearly previews28 red-X removals")
	await _capture("fog-plan-removal")
	_mouse(_screen(LAST), false)
	_check(_context.excavation_marks.is_empty(), "Repeated drag removes the full plan")
	_drag(FIRST, LAST, true)
	_drag(FIRST, LAST, true)
	_check(_context.excavation_marks.size() == 28, "Shift drag preserves previously planned hidden rows")
	_drag(Vector2i(18, 8), LAST, false, true)
	_check(_context.excavation_marks.size() == 22 and not _context.excavation_marks.has(hidden_portal), "Ctrl drag removes only its hidden subrectangle")
	_drag(FIRST, LAST, true)
	_check(_context.excavation_marks.size() == 28, "Shift restores missing cells without toggling the remaining plan")
	# GUI cancellation must still work with a far endpoint over the fog.
	var before := _context.excavation_marks.duplicate()
	_mouse(_screen(FIRST), true)
	_motion(LAST)
	_mouse(Vector2(600, 750), false)
	_mouse(_screen(LAST), false)
	_check(_context.excavation_marks == before and _keeper.get("_drag_start") == KeeperController.INVALID_CELL, "UI release cancels a fog drag; stale release cannot change plans")
	# A plan must persist without divulging hidden non-diggable terrain.
	var snapshot := DungeonSave.capture(_context)
	var restored := DungeonSave.restore(JSON.parse_string(JSON.stringify(snapshot)), _context.registry)
	_check(restored.error.is_empty() and restored.context.excavation_marks == before and restored.context.exploration.revealed == known, "Hidden rectangular plans survive the JSON save boundary unchanged")
	# All useful rock/gold in this rectangle can be reached from the chamber;
	# discovery removes the hidden floor/bedrock/portal marks automatically.
	var completed := false
	var invalid_seen := false
	var respected_frontier := true
	var checked_discovery := false
	for tick in 6000:
		_app.call("_physics_process", STEP)
		if not checked_discovery and _context.exploration.is_revealed(hidden_gold):
			checked_discovery = true
			var frame: Node3D = overlay.marked_frames.get(hidden_gold)
			var shell: MeshInstance3D = frame.get_node("ExcavationGlow") if frame != null else null
			_check(frame != null and is_equal_approx(frame.position.y, _context.grid.surface_height(hidden_gold) + 0.05) and is_equal_approx(shell.scale.y, _context.grid.surface_height(hidden_gold) + 0.12), "A still-planned gold tile changes from fog-height to real top/side glow immediately on discovery")
			_check(not _context.excavation_marks.has(hidden_floor) and not _context.excavation_marks.has(hidden_bedrock) and not _context.excavation_marks.has(hidden_portal), "Non-diggable plans clear as soon as they enter wall-view range, before an imp reaches them")
			await _capture("fog-plan-discovered")
		invalid_seen = invalid_seen or _context.exploration.is_revealed(hidden_bedrock)
		for actor in _context.actors:
			if actor.action in [&"digging", &"mining"]:
				respected_frontier = respected_frontier and _context.exploration.is_revealed(actor.target_cell)
		if invalid_seen and _context.excavation_marks.is_empty():
			completed = true
			break
	_check(completed and _context.grid.get_tile(hidden_bedrock) == DungeonGrid.Tile.BEDROCK and _context.grid.get_tile(hidden_floor) == DungeonGrid.Tile.FLOOR, "Workers progressively finish the plan while discovered bedrock/floor remain intact")
	_check(checked_discovery, "The queued far edge enters view range during progressive excavation")
	_check(not _context.excavation_marks.has(hidden_bedrock) and not _context.excavation_marks.has(hidden_floor) and not _context.excavation_marks.has(hidden_portal), "Discovery automatically clears plans on every non-diggable revealed tile")
	_check(respected_frontier and _context.exploration.revealed.size() > known.size(), "Work follows the revealed frontier instead of excavating unseen cells remotely")
	_check(_context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold + _context.economy.gem_gold_created, "Multi-row excavation and mining preserve the complete gold ledger")
	await _capture("fog-plan-excavated")
	_finish()


func _screen(cell: Vector2i) -> Vector2:
	return _keeper.camera.unproject_position(_context.grid.cell_to_world(cell) + Vector3.UP * _context.exploration.surface_height(cell))


func _mouse(at: Vector2, pressed: bool, shift := false, ctrl := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	root.push_input(event, true)


func _motion(cell: Vector2i, shift := false, ctrl := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _screen(cell)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	root.push_input(event, true)


func _drag(first: Vector2i, last: Vector2i, shift := false, ctrl := false) -> void:
	_mouse(_screen(first), true, shift, ctrl)
	_motion(last, shift, ctrl)
	_mouse(_screen(last), false, shift, ctrl)


func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://artifacts/%s.png" % label) == OK, "Capture %s saves" % label)


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("FOG PLANNING RENDER: %d checks, %d failures" % [_checks, _failures.size()])
	_app.free()
	quit(0 if _failures.is_empty() else 1)
