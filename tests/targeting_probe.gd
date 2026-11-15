extends SceneTree
## Standalone regression check: rendered surface centers round-trip through the camera.
## Run with Godot --headless --path . --script tests/targeting_probe.gd.

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := DungeonGrid.new(7, 7)
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(3, 3), DungeonGrid.Tile.ROCK)
	grid.set_tile(Vector2i(4, 3), DungeonGrid.Tile.GOLD)
	grid.set_tile(Vector2i(3, 4), DungeonGrid.Tile.GEM)
	var context := GameContext.new(grid, null)
	var controller := KeeperController.new()
	root.add_child(controller)
	controller.setup(context)
	controller.set_process(false)
	var target := grid.cell_to_world(Vector2i(3, 3))
	for yaw in [0.0, 1.0, 2.2, 4.3]:
		for distance in [12.0, 31.0, 65.0]:
			controller.camera.position = target + Vector3(sin(yaw) * 0.6, 0.8, cos(yaw) * 0.6) * distance
			controller.camera.look_at(target)
			for cell in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(1, 1)]:
				var surface := grid.cell_to_world(cell) + Vector3.UP * grid.surface_height(cell)
				var screen := controller.camera.unproject_position(surface)
				var result := controller.get_target_cell(screen)
				_checks += 1
				if result != cell:
					_failures += 1
					push_error("Surface targeting: %s became %s (yaw %.1f, distance %.1f)" % [cell, result, yaw, distance])
	_checks += 1
	controller.camera.position = Vector3(-20, 20, -20)
	controller.camera.look_at(Vector3(-30, 0, -30))
	if controller.get_target_cell(root.size * 0.5) != KeeperController.INVALID_CELL:
		_failures += 1
		push_error("Ray outside the dungeon selected a tile")
	controller.queue_free()
	print("TARGETING: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
