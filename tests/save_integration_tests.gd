extends SceneTree
## Exercises actual app replacement and desktop commands against an isolated slot.

var _slot := "res://artifacts/save-integration/session-%d.json" % OS.get_process_id()
var _checks := 0
var _failures: Array[String] = []
var _app: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _run() -> void:
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_app.save_path = _slot
	root.add_child(_app)
	_app.set_physics_process(false)
	_app.controller.set_process(false)
	var original: GameContext = _app.context
	_check(original.rooms.build(&"foundation.lair", [Vector2i(12, 12)]).success, "Player builds a Lair before saving")
	_check(original.rooms.build(&"foundation.pig_pen", [Vector2i(16, 12), Vector2i(17, 12), Vector2i(18, 12), Vector2i(19, 12)]).success, "Player builds a producing pen before saving")
	for index in 1200:
		_app.call("_physics_process", 1.0 / 30.0)
	var grubbin: CreatureState
	for actor in original.actors:
		if actor.definition_id == &"foundation.grubbin":
			grubbin = actor
	_check(grubbin != null and original.beds.get_bed(grubbin.id) != null, "Normal attraction and local home claiming precede the snapshot")
	if grubbin == null:
		_finish()
		return
	var imp: CreatureState = original.actors[0]
	imp.carried_gold += original.economy.mine(Vector2i(20, 17), 23)
	original.keeper.inspect(imp.id)
	original.keeper.rename_selected("Muck æøå")
	_check(original.keeper.pickup(imp.id) and original.keeper.pickup_gold(Vector2i(13, 14), 31) and original.keeper.pickup(grubbin.id) and original.keeper.pickup_gold(Vector2i(14, 14), 47), "Actual creatures and distinct gold batches form a mixed held queue")
	original.mark_excavation([Vector2i(8, 12), Vector2i(8, 13)])
	_app.controller.focus = Vector3(26, 0, 28)
	_app.controller.distance = 25.0
	_app.controller.yaw = 0.7
	_app.controller.pitch = 1.0
	_app.controller.call("_update_camera")
	var before_gold := original.economy.accounted_gold(original.actors)
	var before_food := original.food.total_units
	var before_rooms := original.rooms.tiles.duplicate()
	var before_beds := original.beds.beds.size()
	var before_order: Array[int] = []
	for item in original.keeper.get_items():
		before_order.append(item.id)
	_key(KEY_F5)
	await _settle()
	_check(FileAccess.file_exists(_slot) and (_app.hud.get("_save_status") as Label).text == "Dungeon saved", "Viewport F5 writes the manual save and shows success")
	var disk := FileAccess.get_file_as_string(_slot)
	_check(not disk.is_empty(), "Save file contains a durable snapshot")
	original.keeper.drop(Vector2i(12, 15))
	original.rooms.remove([Vector2i(12, 12)])
	original.grid.set_tile(Vector2i(7, 11), DungeonGrid.Tile.FLOOR)
	original.clear_excavation_marks()
	_app.controller.distance = 40.0
	_key(KEY_F9)
	await _settle()
	var restored: GameContext = _app.context
	_check(restored != original, "F9 replaces the session after detached validation")
	_app.controller.set_process(false)
	_check(restored.actors.size() == original.actors.size() and restored.actors[0] != imp and restored.actors[0].id == imp.id, "Stable actor IDs restore to new session objects without duplicate population")
	_check(restored.actors[0].custom_name == "Muck æøå" and restored.actors[0].carried_gold == 23, "Unicode name and carried worker cargo survive load")
	_check(restored.rooms.tiles == before_rooms and restored.beds.beds.size() == before_beds, "Room tiles and owned bed space restore after unsaved sale")
	_check(restored.grid.get_tile(Vector2i(7, 11)) == DungeonGrid.Tile.ROCK and restored.grid.cells_of_type(DungeonGrid.Tile.HEART) == [Vector2i(14, 15)] and restored.grid.cells_of_type(DungeonGrid.Tile.PORTAL) == [Vector2i(14, 6)], "Terrain edits roll back with exactly one Heart and separate portal")
	_check(restored.excavation_marks.size() == 2 and restored.economy.protected_storage.size() == 8, "Excavation orders and protected starting storage persist")
	_check(restored.food.total_units == before_food and restored.economy.accounted_gold(restored.actors) == before_gold, "Loading conserves physical food and all gold balances")
	var after_order: Array[int] = []
	for item in restored.keeper.get_items():
		after_order.append(item.id)
	_check(after_order == before_order and restored.keeper.held_count == 4 and restored.keeper.total_held_gold == 78, "Complete mixed FIFO order and separate gold amounts restore")
	_check(restored.keeper.held_actor.id == imp.id and restored.keeper.get_items()[2].actor.id == grubbin.id and restored.keeper.get_items()[2].actor.is_held, "Every queued creature restores frozen, including one behind gold")
	_check(is_equal_approx(_app.controller.distance, 25.0) and is_equal_approx(_app.controller.yaw, 0.7) and _app.controller.focus == Vector3(26, 0, 28), "Saved perspective camera restores")
	_check((_app.hud.get("_save_status") as Label).text == "Dungeon loaded" and _app.hud.context == restored and _app.controller.context == restored, "Rebuilt views, controls and visible feedback bind only the restored session")
	for index in 60:
		_app.call("_physics_process", 1.0 / 30.0)
	_check(restored.keeper.held_actor.carried_gold == 23 and restored.keeper.total_held_gold == 78, "Queued cargo stays frozen across real post-load simulation")
	if "--render-save" in OS.get_cmdline_user_args():
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(820, 390)
		root.push_input(motion, true)
		await _settle()
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("res://artifacts/save-loaded-queue.png")
	# Invalid feature/camera data must leave the entire currently visible session.
	var corrupt: Dictionary = JSON.parse_string(disk)
	corrupt.features["foundation.residents"].arrival_in = -100.0
	_write(corrupt)
	_check(not _app.load_game().success and _app.context == restored and restored.keeper.held_count == 4, "Rejected extension state leaves live custody and dungeon untouched")
	corrupt = JSON.parse_string(disk)
	corrupt.presentation.distance = 999.0
	_write(corrupt)
	_check(not _app.load_game().success and _app.context == restored, "Invalid camera data cannot partially replace a live dungeon")
	var recovery_path := _slot + ".interrupted"
	var recovery_file := FileAccess.open(recovery_path + ".bak", FileAccess.WRITE)
	recovery_file.store_string(disk)
	recovery_file.close()
	_app.save_path = recovery_path
	var recovery: Dictionary = _app.load_game()
	_check(recovery.success and "recovery backup" in recovery.reason and _app.context.keeper.held_count == 4, "App restores a missing primary from its backup and clearly reports recovery")
	_app.save_path = _slot
	var handle := FileAccess.open(_slot, FileAccess.WRITE)
	handle.store_string(disk)
	handle.close()
	_check(_app.load_game().success and _app.context != restored, "A valid save remains loadable after rejecting bad candidates")
	var final: GameContext = _app.context
	_check(final.keeper.drop(Vector2i(12, 15)).success and final.keeper.held_gold == 31 and final.actors[0].carried_gold == 23, "First restored drop releases the original worker identity with cargo")
	_check(final.keeper.drop(Vector2i(12, 15)).success and final.keeper.held_actor.id == grubbin.id and final.keeper.total_held_gold == 47, "Second restored drop transfers only its own gold batch")
	_check(final.keeper.drop(Vector2i(12, 15)).success and final.keeper.held_gold == 47 and final.keeper.drop(Vector2i(12, 15)).success, "Remaining creature and gold drop in restored FIFO order")
	for index in 1800:
		_app.call("_physics_process", 1.0 / 30.0)
	_check(final.economy.accounted_gold(final.actors) == before_gold and final.food.accounted_units() == final.food.produced_units, "Fresh jobs and meals after load/drop conserve resources")
	_check(final.economy.keeper_gold == 0 and final.actors[0].carried_gold == 0 and not final.keeper.is_holding(), "Restored worker deposits its saved cargo and dropped gold is recoverable")
	# A second process-style app uses only disk, never old actor references.
	var next_app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	next_app.save_path = _slot
	root.add_child(next_app)
	next_app.set_physics_process(false)
	_check(next_app.load_game().success and next_app.context.keeper.held_count == 4 and next_app.context.economy.accounted_gold(next_app.context.actors) == before_gold, "Fresh application session restores the saved mixed queue without a new starting grant")
	next_app.free()
	_finish()


func _write(data: Dictionary) -> void:
	var handle := FileAccess.open(_slot, FileAccess.WRITE)
	handle.store_string(JSON.stringify(data))
	handle.close()


func _finish() -> void:
	_app.free()
	for failure in _failures:
		push_error(failure)
	print("SAVE INTEGRATION: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
