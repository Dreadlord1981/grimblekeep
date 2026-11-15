class_name BedState
extends RefCounted
## A resident's personal rectangular footprint; never stores a transient RoomState.

var owner_id: int
var anchor: Vector2i
var size := Vector2i.ONE
var cells: Array[Vector2i] = []
var room_tag: StringName
## Pending space prevents over-recruitment; only local establishment makes a bed.
var established: bool = false


func center(grid: DungeonGrid) -> Vector3:
	return grid.cell_to_world(anchor) + Vector3(size.x - 1, 0, size.y - 1) * DungeonGrid.TILE_SIZE * 0.5
