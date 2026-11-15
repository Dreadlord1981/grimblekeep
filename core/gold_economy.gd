class_name GoldEconomy
extends RefCounted
## Physical gold ledger: remaining seams, loose piles and deposited treasury stock.

signal changed

const GOLD_PER_SEAM := 200
var remaining_gold: Dictionary[Vector2i, int] = {}
var ground_gold: Dictionary[Vector2i, int] = {}
var treasury_cells: Array[Vector2i] = []
var stored_gold: int = 0
var gem_gold_created: int = 0
var initial_gold: int = 0
var pending_cargo: Dictionary[int, CreatureState] = {}
var _grid: DungeonGrid


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


func deposit(cell: Vector2i, amount: int) -> bool:
	if amount <= 0 or not is_treasury(cell):
		return false
	stored_gold += amount
	changed.emit()
	return true


func accounted_gold(actors: Array[CreatureState]) -> int:
	var total := stored_gold
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
