class_name RoomDefinition
extends Resource
## Room data contract. Construction and capacity behavior arrive in Milestone 2.

@export var id: StringName
@export var display_name: String = "Room"
@export var gold_cost_per_tile: int = 0
@export var floor_color: Color = Color(0.28, 0.24, 0.22)
@export var view_scene: PackedScene


func validation_error() -> String:
	if id == &"" or display_name.strip_edges().is_empty():
		return "Room requires an ID and display name"
	if gold_cost_per_tile < 0:
		return "Room cost cannot be negative"
	return ""
