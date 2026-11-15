class_name RoomState
extends RefCounted
## Derived four-connected component. Membership/capacity rebuild after edits.

var id: StringName
var definition_id: StringName
var cells: Array[Vector2i] = []
var capacity: int = 0
var gold_capacity: int = 0
