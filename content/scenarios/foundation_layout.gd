extends RefCounted
## Replaceable starting scenario, not a rule embedded in core grid code.

static func create() -> DungeonGrid:
	var grid := DungeonGrid.new()
	_carve(grid, Rect2i(9, 11, 11, 10))
	_carve(grid, Rect2i(11, 3, 7, 6))
	_carve(grid, Rect2i(13, 8, 3, 4))
	_carve(grid, Rect2i(5, 14, 5, 4))
	grid.set_tile(Vector2i(14, 15), DungeonGrid.Tile.HEART)
	grid.set_tile(Vector2i(14, 6), DungeonGrid.Tile.PORTAL)
	for cell in [Vector2i(8, 12), Vector2i(8, 13), Vector2i(4, 15), Vector2i(4, 16), Vector2i(20, 17), Vector2i(20, 18)]:
		grid.set_tile(cell, DungeonGrid.Tile.GOLD)
	for cell in [Vector2i(8, 18), Vector2i(8, 19)]:
		grid.set_tile(cell, DungeonGrid.Tile.GEM)
	return grid


static func _carve(grid: DungeonGrid, area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)


static func setup_rooms(context: GameContext) -> void:
	# All open floor is immediately buildable; no separate claiming step.
	# The four-cell Treasury supplies the bootstrap mining/construction loop.
	var treasury: Array[Vector2i] = [Vector2i(16, 18), Vector2i(17, 18), Vector2i(16, 19), Vector2i(17, 19)]
	assert(context.rooms.place_initial(&"foundation.treasury", treasury), "Starting treasury must fit open floor")
