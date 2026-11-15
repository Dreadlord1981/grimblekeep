class_name BedState
extends RefCounted
## A resident's personal rectangular footprint; never stores a transient RoomState.

const SURFACE_HEIGHT := 0.48

var owner_id: int
var anchor: Vector2i
var size := Vector2i.ONE
var cells: Array[Vector2i] = []
var room_tag: StringName
## Pending space prevents over-recruitment; only local establishment makes a bed.
var established: bool = false


func center(grid: DungeonGrid) -> Vector3:
	return grid.cell_to_world(anchor) + Vector3(size.x - 1, 0, size.y - 1) * DungeonGrid.TILE_SIZE * 0.5


func lift_at(grid: DungeonGrid, position: Vector3) -> float:
	if not established:
		return 0.0
	var offset := position - center(grid)
	var x_fraction := absf(offset.x) / (float(size.x) * DungeonGrid.TILE_SIZE * 0.5)
	var z_fraction := absf(offset.z) / (float(size.y) * DungeonGrid.TILE_SIZE * 0.5)
	return SURFACE_HEIGHT * clampf((1.0 - maxf(x_fraction, z_fraction)) / 0.25, 0.0, 1.0)
