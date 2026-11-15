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
	add_bedrock_border(grid)
	# Small internal example in solid ground, leaving starting routes/resources intact.
	paint_bedrock(grid, [Vector2i(2, 9), Vector2i(3, 9), Vector2i(3, 10), Vector2i(3, 11)])
	return grid


static func paint_bedrock(grid: DungeonGrid, cells: Array[Vector2i]) -> bool:
	# Trusted level authoring, never a player construction/excavation command.
	if grid == null:
		return false
	for cell in cells:
		if not grid.is_inside(cell):
			return false
	for cell in cells:
		grid.set_tile(cell, DungeonGrid.Tile.BEDROCK)
	return true


static func add_bedrock_border(grid: DungeonGrid, thickness: int = 1) -> bool:
	if grid == null or thickness <= 0:
		return false
	for y in grid.height:
		for x in grid.width:
			if x < thickness or y < thickness or x >= grid.width - thickness or y >= grid.height - thickness:
				grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.BEDROCK)
	return true


static func _carve(grid: DungeonGrid, area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)


static func setup_rooms(context: GameContext, starting_gold: int = 0) -> void:
	# All open floor is immediately buildable; no separate claiming step.
	# Fresh playtests receive a finite bank; zero preserves mining-only fixtures.
	var treasury: Array[Vector2i] = [Vector2i(16, 18), Vector2i(17, 18), Vector2i(16, 19), Vector2i(17, 19)]
	if starting_gold > 2000:
		treasury.append_array([Vector2i(18, 18), Vector2i(18, 19)])
	var placed := context.rooms.place_initial(&"foundation.treasury", treasury)
	assert(placed, "Starting treasury must fit open floor")
	assert(starting_gold >= 0 and starting_gold <= context.economy.treasury_capacity, "Starting gold must fit the scenario Treasury")
	var remaining := starting_gold
	for cell in treasury:
		var amount := mini(remaining, context.economy.available_storage(cell))
		if amount > 0:
			var deposited := context.economy.deposit(cell, amount)
			assert(deposited, "Starting gold deposit must fit physical storage")
			context.economy.initial_gold += amount
			remaining -= amount
