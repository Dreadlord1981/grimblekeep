extends SceneTree
## Real-scene evidence of four distinct cardinal miners sharing one gold seam.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(app)
	app.set_physics_process(false)
	var context: GameContext = app.context
	var target := Vector2i(14, 12)
	context.grid.set_tile(target, DungeonGrid.Tile.GOLD)
	var starts: Array[Vector2i] = [Vector2i(12, 12), Vector2i(16, 12), Vector2i(14, 10)]
	for index in context.actors.size():
		context.actors[index].position = context.grid.cell_to_world(starts[index])
	context.spawn_creature(&"foundation.imp", Vector2i(14, 14))
	context.mark_excavation([target])
	app.controller.focus = context.grid.cell_to_world(target)
	app.controller.yaw = -0.6
	app.controller.pitch = 1.0
	app.controller.distance = 16.0
	var all_mining := false
	var conserved := true
	for tick in 1200:
		app.call("_physics_process", 1.0 / 30.0)
		conserved = conserved and context.economy.accounted_gold(context.actors) == context.economy.initial_gold
		var count := 0
		for actor in context.actors:
			if actor.action == &"mining" and actor.target_cell == target:
				count += 1
		if count == 4:
			all_mining = true
			await create_timer(0.22).timeout
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://artifacts")
			var error := root.get_texture().get_image().save_png("res://artifacts/four-sided-mining.png")
			if error != OK:
				push_error("Four-miner capture failed")
				all_mining = false
			break
		if tick % 30 == 0:
			await process_frame
	print("MULTI-SIDE RENDER: four_miners=%s conserved=%s" % [all_mining, conserved])
	app.queue_free()
	await process_frame
	quit(0 if all_mining and conserved else 1)
