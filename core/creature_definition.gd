class_name CreatureDefinition
extends Resource
## Stable identity and presentation defaults; individual state lives in CreatureState.

@export var id: StringName
@export var display_name: String = "Creature"
@export var body_color: Color = Color(0.64, 0.22, 0.15)
@export_range(0.1, 4.0) var scale_factor: float = 1.0
@export_range(0.1, 10.0) var move_speed: float = 1.2
@export var view_scene: PackedScene
@export var capabilities: Array[StringName] = []
@export var work_rate: float = 1.0
@export var carry_capacity: int = 60


func validation_error() -> String:
	if id == &"" or display_name.strip_edges().is_empty():
		return "Creature requires an ID and display name"
	if not is_finite(scale_factor) or not is_finite(move_speed) or scale_factor <= 0 or move_speed <= 0:
		return "Creature scale and move speed must be finite and positive"
	if not is_finite(work_rate) or work_rate <= 0 or carry_capacity <= 0:
		return "Creature work rate and carry capacity must be positive"
	return ""
