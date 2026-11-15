class_name CreatureDefinition
extends Resource
## Stable identity and presentation defaults; individual state lives in CreatureState.

@export var id: StringName
@export var display_name: String = "Creature"
@export var body_color: Color = Color(0.64, 0.22, 0.15)
@export_range(0.1, 4.0) var scale_factor: float = 1.0
@export_range(0.1, 10.0) var move_speed: float = 1.2
@export var view_scene: PackedScene
@export var portrait: Texture2D
@export var capabilities: Array[StringName] = []
@export var work_rate: float = 1.0
@export var carry_capacity: int = 60
@export var bed_size := Vector2i.ONE
@export var rest_room_tag: StringName = &"lair"
@export_range(0.0, 1.0) var initial_energy: float = 1.0
@export var energy_drain_per_second: float = 0.012
@export var sleep_restore_per_second: float = 0.08
@export_range(0.0, 1.0) var sleep_threshold: float = 0.3
@export_range(0.0, 1.0) var wake_threshold: float = 0.9
@export var portal_population_limit: int = 0
## Future food/wage systems consume these species requirements, not active yet.
@export var food_per_meal: int = 1
@export var wage_gold: int = 1


func validation_error() -> String:
	if id == &"" or display_name.strip_edges().is_empty():
		return "Creature requires an ID and display name"
	if not is_finite(scale_factor) or not is_finite(move_speed) or scale_factor <= 0 or move_speed <= 0:
		return "Creature scale and move speed must be finite and positive"
	if not is_finite(work_rate) or work_rate <= 0 or carry_capacity <= 0:
		return "Creature work rate and carry capacity must be positive"
	if bed_size.x <= 0 or bed_size.y <= 0 or rest_room_tag == &"":
		return "Creature requires a positive bed footprint and a rest-room tag"
	if not is_finite(initial_energy) or initial_energy < 0.0 or initial_energy > 1.0:
		return "Initial energy must be finite and between zero and one"
	if not is_finite(energy_drain_per_second) or energy_drain_per_second < 0.0 or not is_finite(sleep_restore_per_second) or sleep_restore_per_second <= 0.0:
		return "Energy drain must be finite/nonnegative and sleep recovery positive"
	if not is_finite(sleep_threshold) or not is_finite(wake_threshold) or sleep_threshold < 0.0 or sleep_threshold >= wake_threshold or wake_threshold > 1.0:
		return "Sleep thresholds require 0 <= sleep < wake <= 1"
	if portal_population_limit < 0 or food_per_meal <= 0 or wage_gold < 0:
		return "Arrival limit/wages must be nonnegative and food amount positive"
	return ""
