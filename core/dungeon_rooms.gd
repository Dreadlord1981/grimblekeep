class_name DungeonRooms
extends RefCounted
## Authoritative room commands, derived groups and definition-driven capacity.

signal changed

const CARDINALS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var tiles: Dictionary[Vector2i, StringName] = {}
var _grid: DungeonGrid
var _registry: ContentRegistry
var _economy: GoldEconomy
var _groups: Array[RoomState] = []
var _by_cell: Dictionary[Vector2i, RoomState] = {}


func _init(grid: DungeonGrid, registry: ContentRegistry, economy: GoldEconomy) -> void:
	_grid = grid
	_registry = registry
	_economy = economy
	_grid.tile_changed.connect(_on_tile_changed)


func quote_build(definition_id: StringName, cells: Array[Vector2i]) -> Dictionary:
	var quote := _empty_quote()
	var definition := _registry.get_room(definition_id) if _registry != null else null
	if definition == null or not definition.buildable:
		quote.reason = "Room type is unavailable"
		quote.blocked = _unique(cells)
		return quote
	for cell in _unique(cells):
		if _can_place(cell):
			quote.add.append(cell)
		else:
			quote.blocked.append(cell)
	quote.cost = quote.add.size() * definition.gold_cost_per_tile
	quote.valid = not quote.add.is_empty() and quote.cost <= _economy.stored_gold
	if quote.add.is_empty():
		quote.reason = "Build on empty excavated floor"
	elif quote.cost > _economy.stored_gold:
		quote.reason = "Need %d stored gold (%d available)" % [quote.cost, _economy.stored_gold]
	elif not quote.blocked.is_empty():
		quote.reason = "%d blocked tiles will be skipped" % quote.blocked.size()
	return quote


func quote_remove(cells: Array[Vector2i]) -> Dictionary:
	var quote := _empty_quote()
	for cell in _unique(cells):
		if tiles.has(cell):
			quote.remove.append(cell)
			var definition := _registry.get_room(tiles[cell])
			quote.refund += floori(definition.gold_cost_per_tile * definition.sell_refund_ratio)
		else:
			quote.blocked.append(cell)
	quote.valid = not quote.remove.is_empty()
	quote.reason = "Stored gold drops to the floor; refund uses remaining storage or drops beside it" if quote.valid else "Select existing room tiles to sell"
	return quote


func build(definition_id: StringName, cells: Array[Vector2i]) -> Dictionary:
	var result := quote_build(definition_id, cells)
	result.success = false
	if not result.valid or not _economy.spend(result.cost):
		return result
	for cell: Vector2i in result.add:
		tiles[cell] = definition_id
	_rebuild()
	result.success = true
	return result


func remove(cells: Array[Vector2i]) -> Dictionary:
	var result := quote_remove(cells)
	result.success = false
	if not result.valid:
		return result
	var refunds: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in result.remove:
		var definition := _registry.get_room(tiles[cell])
		refunds[cell] = floori(definition.gold_cost_per_tile * definition.sell_refund_ratio)
		tiles.erase(cell)
	_rebuild()
	for cell in refunds:
		_economy.refund(cell, refunds[cell])
	result.success = true
	return result


func place_initial(definition_id: StringName, cells: Array[Vector2i]) -> bool:
	# Scenario-only placement bypasses cost, never terrain/overlap rules.
	var definition := _registry.get_room(definition_id) if _registry != null else null
	if definition == null or cells.is_empty():
		return false
	var unique := _unique(cells)
	for cell in unique:
		if not _can_place(cell):
			return false
	for cell in unique:
		tiles[cell] = definition_id
	_rebuild()
	return true


func get_rooms() -> Array[RoomState]:
	return _groups.duplicate()


func get_room_at(cell: Vector2i) -> RoomState:
	return _by_cell.get(cell)


func _can_place(cell: Vector2i) -> bool:
	return _grid.is_inside(cell) and _grid.get_tile(cell) == DungeonGrid.Tile.FLOOR and not tiles.has(cell)


func _empty_quote() -> Dictionary:
	var adding: Array[Vector2i] = []
	var removing: Array[Vector2i] = []
	var blocked: Array[Vector2i] = []
	return {"add": adding, "remove": removing, "blocked": blocked, "cost": 0, "refund": 0, "valid": false, "reason": ""}


func _unique(cells: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		if not seen.has(cell):
			seen[cell] = true
			result.append(cell)
	return result


func _rebuild() -> void:
	_groups.clear()
	_by_cell.clear()
	var capacities: Dictionary[Vector2i, int] = {}
	var sorted := tiles.keys()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for seed: Vector2i in sorted:
		if _by_cell.has(seed):
			continue
		var definition := _registry.get_room(tiles[seed])
		var room := RoomState.new()
		room.definition_id = definition.id
		# IDs identify this snapshot, not permanent identities across merges/splits.
		room.id = StringName("%s:%d:%d" % [definition.id, seed.x, seed.y])
		var frontier: Array[Vector2i] = [seed]
		_by_cell[seed] = room
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			room.cells.append(cell)
			room.capacity += definition.capacity_per_tile
			room.gold_capacity += definition.gold_storage_per_tile
			if definition.gold_storage_per_tile > 0:
				capacities[cell] = definition.gold_storage_per_tile
			for offset: Vector2i in CARDINALS:
				var neighbor := cell + offset
				if tiles.get(neighbor, &"") == definition.id and not _by_cell.has(neighbor):
					_by_cell[neighbor] = room
					frontier.append(neighbor)
		_groups.append(room)
	_economy.configure_treasury(capacities)
	changed.emit()


func _on_tile_changed(cell: Vector2i) -> void:
	if tiles.has(cell) and _grid.get_tile(cell) != DungeonGrid.Tile.FLOOR:
		tiles.erase(cell)
		_rebuild()
