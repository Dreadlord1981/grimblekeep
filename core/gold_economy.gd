class_name GoldEconomy
extends RefCounted
## Physical gold ledger: remaining seams, loose piles and deposited treasury stock.

signal changed

const GOLD_PER_SEAM := 200
var remaining_gold: Dictionary[Vector2i, int] = {}
var ground_gold: Dictionary[Vector2i, int] = {}
var treasury_cells: Array[Vector2i] = []
var stored_by_cell: Dictionary[Vector2i, int] = {}
var spent_gold: int = 0
var refunded_gold: int = 0
var stored_gold: int:
	get:
		var total := 0
		for amount: int in stored_by_cell.values():
			total += amount
		return total
var treasury_capacity: int:
	get:
		if not _room_storage:
			return -1
		var total := 0
		for cell in treasury_cells:
			total += storage_capacity(cell)
		return total
var gem_gold_created: int = 0
var initial_gold: int = 0
var pending_cargo: Dictionary[int, CreatureState] = {}
var _grid: DungeonGrid
var _room_storage := false
var _storage_limits: Dictionary[Vector2i, int] = {}


func _init(grid: DungeonGrid = null) -> void:
	_grid = grid
	if grid == null:
		return
	for cell in grid.cells_of_type(DungeonGrid.Tile.GOLD):
		remaining_gold[cell] = GOLD_PER_SEAM
		initial_gold += GOLD_PER_SEAM
	grid.tile_changed.connect(_on_tile_changed)


func mine(cell: Vector2i, amount: int) -> int:
	if amount <= 0 or _grid == null or not _grid.is_inside(cell):
		return 0
	var extracted := 0
	if _grid.get_tile(cell) == DungeonGrid.Tile.GOLD:
		extracted = mini(amount, remaining_gold.get(cell, 0))
		remaining_gold[cell] = remaining_gold.get(cell, 0) - extracted
	elif _grid.get_tile(cell) == DungeonGrid.Tile.GEM:
		extracted = amount
		gem_gold_created += extracted
	if extracted > 0:
		changed.emit()
	return extracted


func drop_gold(cell: Vector2i, amount: int) -> bool:
	if amount <= 0 or _grid == null or not _grid.is_walkable(cell):
		return false
	ground_gold[cell] = ground_gold.get(cell, 0) + amount
	changed.emit()
	return true


func take_gold(cell: Vector2i, amount: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, ground_gold.get(cell, 0))
	if taken > 0:
		ground_gold[cell] -= taken
		if ground_gold[cell] == 0:
			ground_gold.erase(cell)
		changed.emit()
	return taken


func is_treasury(cell: Vector2i) -> bool:
	return _grid != null and _grid.is_walkable(cell) and cell in treasury_cells


func storage_capacity(cell: Vector2i) -> int:
	if not is_treasury(cell):
		return 0
	return _storage_limits.get(cell, 0) if _room_storage else 2147483647


func available_storage(cell: Vector2i) -> int:
	return maxi(0, storage_capacity(cell) - stored_by_cell.get(cell, 0))


func configure_treasury(capacities: Dictionary[Vector2i, int]) -> void:
	# Room state supplies physical cell capacities. Removed/overflow stock stays
	# where it was as recoverable loose gold, never silently moved or destroyed.
	_room_storage = true
	_storage_limits.clear()
	treasury_cells.clear()
	for cell in capacities:
		if capacities[cell] > 0 and _grid.get_tile(cell) == DungeonGrid.Tile.FLOOR:
			_storage_limits[cell] = capacities[cell]
			treasury_cells.append(cell)
	for cell in stored_by_cell.keys():
		var overflow := maxi(0, stored_by_cell[cell] - storage_capacity(cell))
		if overflow > 0:
			stored_by_cell[cell] -= overflow
			ground_gold[cell] = ground_gold.get(cell, 0) + overflow
		if stored_by_cell[cell] == 0:
			stored_by_cell.erase(cell)
	changed.emit()


func deposit(cell: Vector2i, amount: int) -> bool:
	if amount <= 0 or amount > available_storage(cell):
		return false
	stored_by_cell[cell] = stored_by_cell.get(cell, 0) + amount
	changed.emit()
	return true


func spend(amount: int) -> bool:
	if amount < 0 or amount > stored_gold:
		return false
	if amount == 0:
		return true
	var remaining := amount
	# Fixed row-major debits make transactions reproducible across group edits.
	var cells := stored_by_cell.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in cells:
		var taken := mini(remaining, stored_by_cell[cell])
		stored_by_cell[cell] -= taken
		remaining -= taken
		if stored_by_cell[cell] == 0:
			stored_by_cell.erase(cell)
		if remaining == 0:
			break
	spent_gold += amount
	changed.emit()
	return true


func refund(cell: Vector2i, amount: int) -> void:
	if amount <= 0 or _grid == null or not _grid.is_inside(cell):
		return
	# Salvage is an explicit source, including the scenario's starting rooms.
	# Credit real remaining storage; if none fits, leave physical loose gold.
	refunded_gold += amount
	var remaining := amount
	for treasury_cell in treasury_cells:
		var credited := mini(remaining, available_storage(treasury_cell))
		if credited > 0:
			stored_by_cell[treasury_cell] = stored_by_cell.get(treasury_cell, 0) + credited
			remaining -= credited
		if remaining == 0:
			break
	if remaining > 0:
		ground_gold[cell] = ground_gold.get(cell, 0) + remaining
	changed.emit()


func accounted_gold(actors: Array[CreatureState]) -> int:
	# physical + construction spent = finite supply + gem output + sale refunds
	var total := stored_gold + spent_gold - refunded_gold
	for amount in remaining_gold.values():
		total += amount
	for amount in ground_gold.values():
		total += amount
	for actor in actors:
		total += actor.carried_gold
	for actor in pending_cargo.values():
		if actor not in actors:
			total += actor.carried_gold
	return total


func retain_removed_actor(actor: CreatureState) -> void:
	if actor.carried_gold > 0:
		pending_cargo[actor.id] = actor
		changed.emit()


func release_removed_actor(actor_id: int) -> void:
	pending_cargo.erase(actor_id)
	changed.emit()


func pending_gold() -> int:
	var total := 0
	for actor in pending_cargo.values():
		total += actor.carried_gold
	return total


func _on_tile_changed(cell: Vector2i) -> void:
	if _grid.get_tile(cell) == DungeonGrid.Tile.GOLD and not remaining_gold.has(cell):
		remaining_gold[cell] = GOLD_PER_SEAM
		initial_gold += GOLD_PER_SEAM
	elif _grid.get_tile(cell) != DungeonGrid.Tile.GOLD and remaining_gold.has(cell):
		var remaining: int = remaining_gold[cell]
		remaining_gold.erase(cell)
		# If another system removes a seam, preserve its gold as a loose floor pile.
		if remaining > 0:
			ground_gold[cell] = ground_gold.get(cell, 0) + remaining
	changed.emit()
