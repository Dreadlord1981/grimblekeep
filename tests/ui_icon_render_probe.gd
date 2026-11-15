extends SceneTree
## Captures the real Rooms hub at gameplay size for icon readability review.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(app)
	app.set_physics_process(false)
	for child in app.get_children():
		if child is DungeonHUD:
			child.select_tab(&"rooms")
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := root.get_texture().get_image().save_png("res://artifacts/hub-lair-bed-icon.png")
	print("HUB ICON CAPTURE: %s" % error_string(error))
	app.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
