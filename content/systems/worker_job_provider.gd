class_name WorkerJobProvider
extends RefCounted
## Optional work plugs into the shared board, route follower and reservations.

enum Stage { BEFORE_EXCAVATION, IDLE }


func supports(_definition: CreatureDefinition) -> bool:
	return false


func find_job(_board: WorkerJobBoard, _actor: CreatureState, _definition: CreatureDefinition, _stage: Stage) -> WorkerJob:
	return null


func is_valid(_job: WorkerJob, _actor: CreatureState, _definition: CreatureDefinition) -> bool:
	return false


func work(_job: WorkerJob, _actor: CreatureState, _definition: CreatureDefinition, _delta: float) -> bool:
	return false


func label(_job: WorkerJob) -> String:
	return "Working"


func progress(_job: WorkerJob) -> float:
	return 0.0


func yields_to_orders(_job: WorkerJob) -> bool:
	return false
