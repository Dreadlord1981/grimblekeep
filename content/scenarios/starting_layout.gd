extends RefCounted
## Player start: only the Heart chamber is dug. Expansion belongs to the keeper.

const Development = preload("res://content/scenarios/foundation_layout.gd")
const HEART := Vector2i(14, 15)
const PORTAL := Vector2i(14, 6)
const WORKERS := [Vector2i(12, 16), Vector2i(16, 14), Vector2i(14, 17)]


static func create() -> DungeonGrid:
	var grid := DungeonGrid.new()
	for y in range(13, 18):
		for x in range(12, 17):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(HEART, DungeonGrid.Tile.HEART)
	# The beacon is visible, but its surrounding chamber and route must be dug.
	grid.set_tile(PORTAL, DungeonGrid.Tile.PORTAL)
	for cell in [Vector2i(11, 14), Vector2i(11, 15), Vector2i(17, 15), Vector2i(17, 16), Vector2i(13, 18), Vector2i(14, 18)]:
		grid.set_tile(cell, DungeonGrid.Tile.GOLD)
	for cell in [Vector2i(11, 18), Vector2i(11, 19)]:
		grid.set_tile(cell, DungeonGrid.Tile.GEM)
	Development.add_bedrock_border(grid)
	Development.paint_bedrock(grid, [Vector2i(2, 9), Vector2i(3, 9), Vector2i(3, 10), Vector2i(3, 11)])
	return grid


static func setup_rooms(context: GameContext, starting_gold: int = 3000) -> void:
	Development.setup_rooms(context, starting_gold, true)
	context.exploration.enable()
	context.infrastructure.enable([Vector2i(12, 13), Vector2i(16, 17)])
