class_name ExplorationSaveCodec
extends RefCounted
## Knowledge, installed fixtures and local work survive route/feature rebuilding.


static func capture(context: GameContext) -> Dictionary:
	var cells: Array = []
	for cell in context.exploration.revealed:
		cells.append(SaveReader.encode_cell(cell))
	var lamps: Array = []
	for cell in context.infrastructure.lamps:
		lamps.append(SaveReader.encode_cell(cell))
	var walls: Array = []
	for cell in context.infrastructure.lamp_walls:
		var wall := context.infrastructure.lamp_walls[cell]
		walls.append([cell.x, cell.y, wall.x, wall.y])
	return {"exploration": {"enabled": context.exploration.enabled, "radius": DungeonExploration.REVEAL_RADIUS, "revealed": cells},
		"infrastructure": {"enabled": context.infrastructure.enabled, "lamps": lamps, "lamp_walls": walls,
			"lamp_progress": _encode_progress(context.infrastructure.lamp_progress),
			"portals": _encode_progress(context.infrastructure.portal_progress)}}


static func restore(context: GameContext, data: Dictionary, reader: SaveReader) -> void:
	var knowledge := reader.object(data.get("exploration"), "exploration")
	context.exploration.enabled = reader.flag(knowledge.get("enabled"), "exploration enabled")
	context.exploration.revealed = _cells(knowledge.get("revealed"), context.grid, reader, "explored cells")
	var known_count := context.exploration.revealed.size()
	var saved_radius := reader.integer(knowledge.get("radius", 1), "exploration radius", 1, DungeonExploration.REVEAL_RADIUS)
	# Validate saved plans before gameplay subscribers can prune newly known cells.
	context.exploration.refresh(false, saved_radius)
	if context.exploration.revealed.size() != known_count:
		reader.fail("Exploration omits currently reachable terrain or its visible frontier")
	var structures := reader.object(data.get("infrastructure"), "infrastructure")
	var state := context.infrastructure
	state.enabled = reader.flag(structures.get("enabled"), "infrastructure enabled")
	state.lamps = _cells(structures.get("lamps"), context.grid, reader, "installed lamps")
	state.lamp_progress = _progress(structures.get("lamp_progress"), context.grid, reader, "lamp work")
	state.portal_progress = _progress(structures.get("portals"), context.grid, reader, "portal claims")
	var legacy_lamps := not structures.has("lamp_walls")
	if not legacy_lamps:
		for raw in reader.array(structures.get("lamp_walls"), "lamp supporting walls"):
			var row := reader.array(raw, "lamp wall entry")
			if row.size() != 4:
				reader.fail("Lamp wall needs access and support coordinates")
				continue
			var cell := reader.cell([row[0], row[1]], context.grid, "lamp access cell")
			var wall := reader.cell([row[2], row[3]], context.grid, "lamp supporting wall")
			if state.lamp_walls.has(cell) or not state.is_lamp_wall_valid(cell, wall):
				reader.fail("Lamp has duplicate or invalid supporting wall")
			state.lamp_walls[cell] = wall
	if state.enabled and not context.exploration.enabled:
		reader.fail("Infrastructure requires dungeon exploration")
	if not state.enabled and (not state.lamps.is_empty() or not state.lamp_progress.is_empty() or not state.portal_progress.is_empty() or not state.lamp_walls.is_empty()):
		reader.fail("Disabled infrastructure contains active fixtures")
	for cell in state.lamps:
		if context.grid.get_tile(cell) != DungeonGrid.Tile.FLOOR or not context.exploration.is_revealed(cell):
			reader.fail("Installed lamp must occupy explored floor")
	for cell in state.lamp_progress:
		if state.lamp_progress[cell] >= 1.0 or state.lamps.has(cell) or context.grid.get_tile(cell) != DungeonGrid.Tile.FLOOR or not context.exploration.is_revealed(cell):
			reader.fail("Pending lamp installation is invalid")
	if not legacy_lamps:
		for cell in state.lamps.keys() + state.lamp_progress.keys():
			if not state.lamp_walls.has(cell):
				reader.fail("Lamp is missing its supporting wall")
		for cell in state.lamp_walls:
			if not state.lamps.has(cell) and not state.lamp_progress.has(cell):
				reader.fail("Supporting wall has no lamp or pending work")
	for cell in state.portal_progress:
		if context.grid.get_tile(cell) != DungeonGrid.Tile.PORTAL or (state.portal_progress[cell] > 0.0 and not context.exploration.is_revealed(cell)):
			reader.fail("Portal claim does not match explored landmark terrain")
	if state.enabled:
		for cell in context.grid.cells_of_type(DungeonGrid.Tile.PORTAL):
			if not state.portal_progress.has(cell):
				reader.fail("A portal is missing its ownership state")
	for cell in context.excavation_marks:
		if not context.can_designate_excavation(cell):
			reader.fail("Excavation mark designates known non-diggable terrain")
	# Older version2 saves used a shorter frontier. Expand only after validating
	# their original knowledge/plans; normal reveal cleanup now applies to new range.
	if reader.error.is_empty() and saved_radius < DungeonExploration.REVEAL_RADIUS:
		context.exploration.refresh()
	if reader.error.is_empty() and legacy_lamps:
		_migrate_floor_lamps(context)
	elif reader.error.is_empty():
		state.ensure_room_corner_lamps()


static func _migrate_floor_lamps(context: GameContext) -> void:
	var state := context.infrastructure
	var previous := state.lamps.keys() + state.lamp_progress.keys()
	state.lamps.clear()
	state.lamp_progress.clear()
	# Older floor fixtures move to the nearest known wall face. Unfinished old
	# installation becomes immediate too; no creature/economic state is changed.
	for origin: Vector2i in previous:
		var chosen := DungeonInfrastructure.INVALID_CELL
		var best := INF
		for y in context.grid.height:
			for x in context.grid.width:
				var cell := Vector2i(x, y)
				if state.lamps.has(cell) or state.find_lamp_wall(cell) == DungeonInfrastructure.INVALID_CELL:
					continue
				var distance := origin.distance_squared_to(cell)
				if distance < best:
					chosen = cell
					best = distance
		if chosen != DungeonInfrastructure.INVALID_CELL:
			state.lamps[chosen] = true
			state.lamp_walls[chosen] = state.find_lamp_wall(chosen)
	# Catch up older excavated passages that were still waiting for idle installers.
	state.ensure_wall_lamps()


static func migrate_v1(data: Dictionary) -> Dictionary:
	# Existing dungeons were fully visible and their portals already operational.
	# Preserve that knowledge and ownership; only new games use the smaller start.
	var migrated := data.duplicate(true)
	var raw: Variant = migrated.get("grid")
	if not raw is Dictionary:
		return migrated
	var width: Variant = raw.get("width")
	var height: Variant = raw.get("height")
	var tiles: Variant = raw.get("tiles")
	if not (width is int or width is float) or not (height is int or height is float) or not tiles is Array or float(width) != floorf(float(width)) or float(height) != floorf(float(height)) or width < 1 or height < 1 or width > 512 or height > 512 or tiles.size() != int(width) * int(height):
		return migrated
	var revealed: Array = []
	var portals: Array = []
	var lamps: Array = []
	for index in tiles.size():
		var cell := [index % int(width), index / int(width)]
		revealed.append(cell)
		if tiles[index] == DungeonGrid.Tile.PORTAL:
			portals.append([cell[0], cell[1], 1.0])
	for candidate in [[10, 12], [18, 12], [10, 19], [18, 19], [12, 5], [16, 5], [6, 15]]:
		if candidate[0] < int(width) and candidate[1] < int(height) and tiles[candidate[1] * int(width) + candidate[0]] == DungeonGrid.Tile.FLOOR:
			lamps.append(candidate)
	migrated["exploration"] = {"enabled": true, "revealed": revealed}
	migrated["infrastructure"] = {"enabled": true, "lamps": lamps, "lamp_progress": [], "portals": portals}
	return migrated


static func _encode_progress(values: Dictionary[Vector2i, float]) -> Array:
	var rows: Array = []
	for cell in values:
		rows.append([cell.x, cell.y, values[cell]])
	return rows


static func _cells(raw: Variant, grid: DungeonGrid, reader: SaveReader, label: String) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	for value in reader.array(raw, label):
		var cell := reader.cell(value, grid, label)
		if result.has(cell):
			reader.fail("%s contains duplicate cells" % label)
		result[cell] = true
	return result


static func _progress(raw: Variant, grid: DungeonGrid, reader: SaveReader, label: String) -> Dictionary[Vector2i, float]:
	var result: Dictionary[Vector2i, float] = {}
	for value in reader.array(raw, label):
		var row := reader.array(value, label)
		if row.size() != 3:
			reader.fail("%s entry needs x, y and progress" % label)
			continue
		var cell := reader.cell([row[0], row[1]], grid, label)
		if result.has(cell):
			reader.fail("%s contains duplicate cells" % label)
		result[cell] = reader.number(row[2], label, 0.0, 1.0)
	return result
