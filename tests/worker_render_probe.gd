extends SceneTree
## Advances the real simulation faster only inside this test harness, capturing work.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	app.starting_gold = 0
	root.add_child(app)
	app.set_physics_process(false)
	var context: GameContext = app.context
	context.mark_excavation([Vector2i(8, 12), Vector2i(8, 13), Vector2i(8, 11), Vector2i(7, 11)])
	app.controller.focus = context.grid.cell_to_world(Vector2i(10, 14))
	app.controller.distance = 23.0
	app.controller.pitch = 0.8
	app.controller.yaw = 0.7
	var captured_work := false
	var captured_cargo := false
	var diagonal_motion := false
	var conserved := true
	for tick in 7200:
		var previous_positions: Array[Vector3] = []
		for actor in context.actors:
			previous_positions.append(actor.position)
		app.call("_physics_process", 1.0 / 30.0)
		for index in context.actors.size():
			var offset := context.actors[index].position - previous_positions[index]
			diagonal_motion = diagonal_motion or (absf(offset.x) > 0.0001 and absf(offset.z) > 0.0001)
		conserved = conserved and context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created
		for actor in context.actors:
			if not captured_work and actor.action in [&"digging", &"mining"] and actor.work_progress > 0.35:
				await _capture("workers-working")
				captured_work = true
			if not captured_cargo and actor.action == &"hauling" and actor.carried_gold > 0:
				await _capture("workers-hauling")
				captured_cargo = true
		if tick % 30 == 0:
			await process_frame
		if context.economy.stored_gold >= 400 and context.grid.get_tile(Vector2i(7, 11)) == DungeonGrid.Tile.FLOOR:
			break
	app.controller.focus = context.grid.cell_to_world(Vector2i(15, 17))
	app.controller.distance = 25.0
	await _capture("workers-treasury")
	var finished := context.economy.stored_gold == 400 and context.excavation_marks.is_empty()
	print("WORKER RENDER: work=%s cargo=%s diagonal=%s stored=%d conserved=%s finished=%s" % [captured_work, captured_cargo, diagonal_motion, context.economy.stored_gold, conserved, finished])
	app.queue_free()
	await process_frame
	quit(0 if captured_work and captured_cargo and diagonal_motion and conserved and finished else 1)


func _capture(label: String) -> void:
	# Allow HUD polling and the view's dirty terrain batch to catch up to state.
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := root.get_texture().get_image().save_png("res://artifacts/%s.png" % label)
	if error != OK:
		push_error("Worker capture failed: %s" % error_string(error))
