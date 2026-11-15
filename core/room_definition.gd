class_name RoomDefinition
extends Resource
## Stable room data; generic placement and connected capacity use these values.

@export var id: StringName
@export var display_name: String = "Room"
@export var gold_cost_per_tile: int = 0
@export_range(0.0, 1.0) var sell_refund_ratio: float = 0.5
@export var buildable: bool = true
@export var capacity_per_tile: int = 1
@export var gold_storage_per_tile: int = 0
@export_range(0.01, 1.0) var storage_small_chest_ratio: float = 0.35
@export_range(0.01, 1.0) var storage_large_chest_ratio: float = 0.75
@export var floor_color: Color = Color(0.28, 0.24, 0.22)
@export var tags: Array[StringName] = []
@export var floor_style: StringName = &"flagstone"
@export var wall_style: StringName
@export var wall_color := Color(0.24, 0.22, 0.25)
@export var accent_color := Color(0.55, 0.42, 0.23)
@export var wall_scene: PackedScene
@export var view_scene: PackedScene
@export var icon: Texture2D


func validation_error() -> String:
	if id == &"" or display_name.strip_edges().is_empty():
		return "Room requires an ID and display name"
	if gold_cost_per_tile < 0:
		return "Room cost cannot be negative"
	if not is_finite(sell_refund_ratio) or sell_refund_ratio < 0.0 or sell_refund_ratio > 1.0:
		return "Room sale refund must be a finite ratio from zero to one"
	if capacity_per_tile < 0 or gold_storage_per_tile < 0:
		return "Room capacity cannot be negative"
	if not is_finite(storage_small_chest_ratio) or not is_finite(storage_large_chest_ratio) or storage_small_chest_ratio <= 0.0 or storage_small_chest_ratio >= storage_large_chest_ratio or storage_large_chest_ratio > 1.0:
		return "Storage stages require finite ratios: 0 < small < large <= 1"
	return ""
