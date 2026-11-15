class_name WorkerJob
extends RefCounted
## Assignment data. Discovery/reservation and execution deliberately live elsewhere.

var kind: StringName
var target_cell: Vector2i
var work_cell: Vector2i
var terrain_kind: int = -1
var path: Array[Vector2i] = []


func _init(job_kind: StringName = &"", target: Vector2i = Vector2i.ZERO, workplace: Vector2i = Vector2i.ZERO) -> void:
	kind = job_kind
	target_cell = target
	work_cell = workplace
