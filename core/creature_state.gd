class_name CreatureState
extends RefCounted
## Runtime state has no mesh, animation, input or scene-tree references.

var id: int
var definition_id: StringName
var position: Vector3
var heading: float = 0.0
var phase: float = 0.0
var action: StringName = &"idle"
var job_label: String = "Idle"
var target_cell := Vector2i(-1, -1)
var work_progress: float = 0.0
var carried_gold: int = 0
var custom_name: String = ""
var is_held: bool = false
var energy: float = 1.0
## Needs run before work features; work yields while rest owns movement.
var rest_requested: bool = false
var satiety: float = 1.0
var food_requested: bool = false
var needs_requested: bool:
	get:
		return rest_requested or food_requested
