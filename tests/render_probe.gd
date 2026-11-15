extends SceneTree
## GPU smoke test, reproducible captures and a small-map timing sample.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(app)
	for i in 60:
		await process_frame
	var started := Time.get_ticks_usec()
	var physics_seconds := 0.0
	for i in 180:
		await process_frame
		physics_seconds += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
	print("RENDER SAMPLE: viewport=%s | frames=180 | elapsed=%.3fs | mean_fps=%.1f | mean_physics_ms=%.3f | nodes=%d" % [root.size, elapsed, 180.0 / elapsed, physics_seconds / 180.0 * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := root.get_texture().get_image().save_png("res://artifacts/overview.png")
	app.controller.distance = 14.0
	app.controller.pitch = 0.55
	app.controller.yaw = -0.48
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var close_error := root.get_texture().get_image().save_png("res://artifacts/close.png")
	print("RENDER CAPTURES: overview=%s | close=%s" % [error_string(error), error_string(close_error)])
	app.queue_free()
	await process_frame
	quit(0 if error == OK and close_error == OK else 1)
