class_name DungeonExploration
extends RefCounted
## Persistent knowledge is independent of local light. Digging exposes connected space.

signal changed

const FOG_HEIGHT := 2.2
const WALL_REVEAL_ROWS := 4
# Include the exposed wall itself, then four rows beyond it into surrounding rock.
const REVEAL_RADIUS := WALL_REVEAL_ROWS + 1

const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
var enabled := false
var revealed: Dictionary[Vector2i, bool] = {}
var _connected: Dictionary[Vector2i, bool] = {}
var _grid: DungeonGrid


func _init(grid: DungeonGrid) -> void:
	_grid = grid
	_grid.tile_changed.connect(_on_tile_changed)


func enable() -> void:
	enabled = true
	refresh()


func is_revealed(cell: Vector2i) -> bool:
	return _grid.is_inside(cell) and (not enabled or revealed.has(cell))


func surface_height(cell: Vector2i) -> float:
	return _grid.surface_height(cell) if is_revealed(cell) else FOG_HEIGHT


func is_reachable(cell: Vector2i) -> bool:
	return _grid.is_walkable(cell) and (not enabled or _connected.has(cell))


func connected_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_connected.keys())
	return cells


func refresh(notify: bool = true, radius: int = REVEAL_RADIUS) -> void:
	if not enabled:
		return
	var next: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for heart in _grid.cells_of_type(DungeonGrid.Tile.HEART):
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = heart + offset
			if _grid.is_walkable(cell) and not next.has(cell):
				next[cell] = true
				frontier.append(cell)
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for offset in NEIGHBORS:
			var neighbor: Vector2i = cell + offset
			if not next.has(neighbor) and GridPathfinder.can_step(_grid, cell, neighbor):
				next[neighbor] = true
				frontier.append(neighbor)
	var dirty := next != _connected
	_connected = next
	for cell in _connected:
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var known := cell + Vector2i(x, y)
				if _grid.is_inside(known) and not revealed.has(known):
					revealed[known] = true
					dirty = true
	for heart in _grid.cells_of_type(DungeonGrid.Tile.HEART):
		if not revealed.has(heart):
			revealed[heart] = true
			dirty = true
	if dirty and notify:
		changed.emit()


func _on_tile_changed(_cell: Vector2i) -> void:
	refresh()
