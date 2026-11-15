extends SceneTree
## Actual-scene rendering and Viewport construction input with finite-gold fixtures.

var _capture_ok := true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(app)
	app.set_physics_process(false)
	var context: GameContext = app.context
	var keeper: KeeperController = app.controller
	# Rendering fixture: transfer finite seam gold, preserving the real ledger.
	# Headless worker tests separately prove ordinary delivery and distribution.
	var extracted := 0
	for cell in context.grid.cells_of_type(DungeonGrid.Tile.GOLD):
		if extracted >= 800:
			break
		extracted += context.economy.mine(cell, 200)
	var deposited := context.economy.deposit(Vector2i(16, 18), 100)
	deposited = context.economy.deposit(Vector2i(17, 18), 250) and deposited
	deposited = context.economy.deposit(Vector2i(16, 19), 450) and deposited
	keeper.focus = context.grid.cell_to_world(Vector2i(15, 16))
	keeper.distance = 29.0
	keeper.pitch = 0.85
	keeper.yaw = -0.45
	await _capture("rooms-overview")
	var pile := app.find_child("GoldStorage_16_18", true, false)
	var small := app.find_child("GoldStorage_17_18", true, false)
	var large := app.find_child("GoldStorage_16_19", true, false)
	var stages := pile != null and small != null and large != null
	if stages:
		stages = pile.get_meta("stage") == &"pile" and small.get_meta("stage") == &"small_chest" and large.get_meta("stage") == &"large_chest"
	keeper.focus = context.grid.cell_to_world(Vector2i(16, 18))
	keeper.distance = 13.0
	keeper.pitch = 0.85
	keeper.yaw = -0.60
	await _capture("treasury-gold-stages")
	# Synthetic Viewport events do not move the OS pointer. Keep this settled
	# camera and event-driven preview stable while capturing a held drag.
	keeper.set_process(false)
	keeper.set_build_room(&"foundation.treasury")
	await process_frame
	var target := Vector2i(18, 18)
	var at := keeper.camera.unproject_position(context.grid.cell_to_world(target))
	var mouse := InputEventMouseButton.new()
	mouse.position = at
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse, true)
	await _capture("treasury-build-preview")
	var preview := keeper.get_preview_changes()
	var preview_ok: bool = preview.get("valid", false) and preview.get("cost", 0) == 50 and target in preview.get("add", [])
	mouse = mouse.duplicate()
	mouse.pressed = false
	root.push_input(mouse, true)
	await _capture("treasury-built")
	var built: bool = context.rooms.tiles.get(target, &"") == &"foundation.treasury"
	var spent := context.economy.spent_gold == 50
	var conserved := context.economy.accounted_gold(context.actors) == context.economy.initial_gold
	keeper.exit_construction()
	keeper.set_sell_rooms()
	var removed_cell := Vector2i(17, 18)
	at = keeper.camera.unproject_position(context.grid.cell_to_world(removed_cell))
	mouse.position = at
	mouse.pressed = true
	root.push_input(mouse, true)
	var sale_preview := keeper.get_preview_changes()
	var refund_preview: bool = sale_preview.get("valid", false) and sale_preview.get("refund", 0) == 25
	await _capture("treasury-sell-preview")
	mouse = mouse.duplicate()
	mouse.pressed = false
	root.push_input(mouse, true)
	await _capture("treasury-removed-gold")
	var removed: bool = not context.rooms.tiles.has(removed_cell) and context.economy.ground_gold.get(removed_cell, 0) == 250
	var refunded := context.economy.refunded_gold == 25 and context.economy.stored_gold == 525
	# Spending must change existing props as well as the header's total.
	context.economy.spend(250)
	await _capture("treasury-stock-spent")
	var depleted := app.find_child("GoldStorage_16_18", true, false)
	var downgraded := app.find_child("GoldStorage_16_19", true, false)
	var stages_update: bool = depleted == null and downgraded != null and downgraded.get_meta("stage") == &"small_chest"
	conserved = conserved and context.economy.accounted_gold(context.actors) == context.economy.initial_gold
	print("ROOMS RENDER: deposited=%s stages=%s preview=%s built=%s spent=%s removed=%s refund_preview=%s refunded=%s stage_updates=%s conserved=%s captures=%s" % [deposited, stages, preview_ok, built, spent, removed, refund_preview, refunded, stages_update, conserved, _capture_ok])
	app.queue_free()
	await process_frame
	quit(0 if deposited and stages and preview_ok and built and spent and removed and refund_preview and refunded and stages_update and conserved and _capture_ok else 1)


func _capture(label: String) -> void:
	await create_timer(0.28).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := root.get_texture().get_image().save_png("res://artifacts/%s.png" % label)
	_capture_ok = _capture_ok and error == OK
	if error != OK:
		push_error("Room capture failed: %s" % error_string(error))
