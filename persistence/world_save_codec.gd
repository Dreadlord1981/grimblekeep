class_name WorldSaveCodec
extends RefCounted
## Terrain, room membership and physical gold. Room groups/capacities are derived.


static func capture(context: GameContext) -> Dictionary:
	var tiles: Array = []
	for y in context.grid.height:
		for x in context.grid.width:
			tiles.append(context.grid.get_tile(Vector2i(x, y)))
	var rooms: Array = []
	for at in context.rooms.tiles:
		rooms.append([at.x, at.y, String(context.rooms.tiles[at])])
	var marks: Array = []
	for at in context.excavation_marks:
		marks.append(SaveReader.encode_cell(at))
	var economy := context.economy
	return {
		"grid": {"width": context.grid.width, "height": context.grid.height, "tiles": tiles},
		"rooms": rooms, "marks": marks,
		"gold": {"remaining": SaveReader.encode_amounts(economy.remaining_gold), "ground": SaveReader.encode_amounts(economy.ground_gold), "stored": SaveReader.encode_amounts(economy.stored_by_cell), "protected": SaveReader.encode_amounts(economy.protected_storage), "initial": economy.initial_gold, "spent": economy.spent_gold, "refunded": economy.refunded_gold, "gem_created": economy.gem_gold_created, "keeper": economy.keeper_gold}
	}


static func restore_grid(data: Dictionary, reader: SaveReader) -> DungeonGrid:
	var raw := reader.object(data.get("grid"), "grid")
	var width := reader.integer(raw.get("width"), "grid width", 1, 512)
	var height := reader.integer(raw.get("height"), "grid height", 1, 512)
	var tiles := reader.array(raw.get("tiles"), "terrain")
	if tiles.size() != width * height:
		reader.fail("Terrain count does not match grid dimensions")
		return null
	var grid := DungeonGrid.new(width, height)
	for index in tiles.size():
		grid.set_tile(Vector2i(index % width, index / width), reader.integer(tiles[index], "terrain type", DungeonGrid.Tile.ROCK, DungeonGrid.Tile.BEDROCK))
	return grid


static func restore(context: GameContext, data: Dictionary, reader: SaveReader) -> void:
	var raw := reader.object(data.get("gold"), "gold")
	var economy := context.economy
	var protected := reader.cell_amounts(raw.get("protected"), context.grid, "protected storage", 1)
	if not economy.configure_protected_storage(protected):
		reader.fail("Protected storage must occupy floor")
	var used: Dictionary[Vector2i, bool] = {}
	for item in reader.array(data.get("rooms"), "rooms"):
		var row := reader.array(item, "room tile")
		if row.size() != 3:
			reader.fail("Room entry needs x, y and definition")
			continue
		var at := reader.cell([row[0], row[1]], context.grid, "room cell")
		var definition_id := StringName(reader.text(row[2], "room definition"))
		if used.has(at) or context.registry.get_room(definition_id) == null or not context.rooms.place_initial(definition_id, [at]):
			reader.fail("Invalid, duplicate or unknown room tile")
		used[at] = true
	for item in reader.array(data.get("marks"), "marks"):
		var at := reader.cell(item, context.grid, "excavation mark")
		# Eligibility depends on restored knowledge, checked by ExplorationSaveCodec.
		if context.excavation_marks.has(at):
			reader.fail("Invalid or duplicate excavation mark")
		context.excavation_marks[at] = true
	if not context.excavation_marks.is_empty():
		context.last_marked_cell = context.excavation_marks.keys().back()
	economy.remaining_gold = reader.cell_amounts(raw.get("remaining"), context.grid, "remaining seams")
	economy.ground_gold = reader.cell_amounts(raw.get("ground"), context.grid, "loose gold", 1)
	economy.stored_by_cell = reader.cell_amounts(raw.get("stored"), context.grid, "stored gold", 1)
	for at in economy.remaining_gold:
		if context.grid.get_tile(at) != DungeonGrid.Tile.GOLD or economy.remaining_gold[at] > GoldEconomy.GOLD_PER_SEAM:
			reader.fail("Remaining seam gold does not match terrain")
	for at in context.grid.cells_of_type(DungeonGrid.Tile.GOLD):
		if not economy.remaining_gold.has(at):
			reader.fail("Gold seam is missing its remaining balance")
	for at in economy.stored_by_cell:
		if economy.stored_by_cell[at] > economy.storage_capacity(at):
			reader.fail("Stored gold exceeds physical capacity")
	economy.initial_gold = reader.integer(raw.get("initial"), "initial gold")
	economy.spent_gold = reader.integer(raw.get("spent"), "spent gold")
	economy.refunded_gold = reader.integer(raw.get("refunded"), "refunded gold")
	economy.gem_gold_created = reader.integer(raw.get("gem_created"), "gem gold")
	economy.keeper_gold = reader.integer(raw.get("keeper"), "held gold")
