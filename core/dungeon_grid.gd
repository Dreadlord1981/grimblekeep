class_name DungeonGrid
extends RefCounted
## Authoritative terrain. World coordinates are tile centers, independent of views.

signal tile_changed(cell: Vector2i)

enum Tile { ROCK, FLOOR, GOLD, HEART, PORTAL, GEM }
const TILE_SIZE := 2.0

var width: int
var height: int
var navigation_revision: int = 0
var _tiles: PackedInt32Array


func _init(grid_width: int = 28, grid_height: int = 28) -> void:
	assert(grid_width > 0 and grid_height > 0, "Grid dimensions must be positive")
	width = grid_width
	height = grid_height
	_tiles.resize(width * height)
	_tiles.fill(Tile.ROCK)


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func get_tile(cell: Vector2i) -> int:
	if not is_inside(cell):
		return Tile.ROCK
	return _tiles[cell.y * width + cell.x]


func set_tile(cell: Vector2i, tile: int) -> bool:
	if not is_inside(cell) or tile < Tile.ROCK or tile > Tile.GEM:
		return false
	var index := cell.y * width + cell.x
	if _tiles[index] != tile:
		_tiles[index] = tile
		navigation_revision += 1
		tile_changed.emit(cell)
	return true


func is_walkable(cell: Vector2i) -> bool:
	return is_inside(cell) and get_tile(cell) in [Tile.FLOOR, Tile.PORTAL]


func can_excavate(cell: Vector2i) -> bool:
	return is_inside(cell) and get_tile(cell) in [Tile.ROCK, Tile.GOLD, Tile.GEM]


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * TILE_SIZE, 0.0, cell.y * TILE_SIZE)


func surface_height(cell: Vector2i) -> float:
	# Shared terrain elevation for geometry and picking; excludes decorative rubble.
	if can_excavate(cell):
		return 1.75 + float(posmod(cell.x * 17 + cell.y * 13, 7)) * 0.045 - 0.02
	return 0.01


func world_to_cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / TILE_SIZE + 0.5), floori(position.z / TILE_SIZE + 0.5))


func cells_of_type(tile: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if get_tile(cell) == tile:
				result.append(cell)
	return result
