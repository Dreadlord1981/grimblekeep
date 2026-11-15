class_name FoodDefinition
extends Resource
## Stable meal data; raw ingredients and later prepared meals share this contract.

@export var id: StringName
@export var display_name: String = "Food"
@export var tags: Array[StringName] = []
@export var nutrition_per_unit: float = 0.65
@export var wanders: bool = false
@export var growth_seconds: float = 0.0
@export var newborn_scale: float = 0.4
@export var body_color := Color(0.63, 0.38, 0.34)
@export var view_scene: PackedScene


func validation_error() -> String:
	if id == &"" or display_name.strip_edges().is_empty():
		return "Food requires an ID and display name"
	if not is_finite(nutrition_per_unit) or nutrition_per_unit <= 0.0:
		return "Food nutrition must be finite and positive"
	if not is_finite(growth_seconds) or growth_seconds < 0.0 or not is_finite(newborn_scale) or newborn_scale <= 0.0 or newborn_scale > 1.0:
		return "Food growth requires a finite nonnegative duration and a scale from zero (exclusive) to one"
	return ""
