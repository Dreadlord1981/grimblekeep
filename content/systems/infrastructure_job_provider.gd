class_name InfrastructureJobProvider
extends WorkerJobProvider
## Portal claiming uses local worker jobs; passage lights appear with excavation.

var _context: GameContext


func _init(context: GameContext) -> void:
	_context = context


func supports(definition: CreatureDefinition) -> bool:
	return &"claim_portal" in definition.capabilities


func find_job(board: WorkerJobBoard, actor: CreatureState, definition: CreatureDefinition, stage: Stage) -> WorkerJob:
	if not _context.infrastructure.enabled or actor.carried_gold > 0:
		return null
	var candidates: Array[Vector2i] = []
	var kind := &""
	if stage == Stage.BEFORE_EXCAVATION and &"claim_portal" in definition.capabilities:
		kind = &"claim_portal"
		for cell in _context.infrastructure.portal_progress:
			if _context.infrastructure.can_claim_portal(cell):
				candidates.append(cell)
	var best: WorkerJob
	var start := _context.grid.world_to_cell(actor.position)
	for cell in candidates:
		if not board.can_reserve_custom(cell, cell, actor.id):
			continue
		var path := GridPathfinder.find_path(_context.grid, start, cell)
		if path.is_empty() or (best != null and GridPathfinder.path_cost(path) >= GridPathfinder.path_cost(best.path)):
			continue
		best = WorkerJob.new(kind, cell, cell)
		best.path = path
		best.provider = self
	return best


func is_valid(job: WorkerJob, actor: CreatureState, definition: CreatureDefinition) -> bool:
	if not _context.infrastructure.enabled or actor.is_held or actor.needs_requested or actor.carried_gold > 0:
		return false
	if job.kind == &"claim_portal":
		return &"claim_portal" in definition.capabilities and _context.infrastructure.can_claim_portal(job.target_cell)
	return false


func work(job: WorkerJob, actor: CreatureState, definition: CreatureDefinition, delta: float) -> bool:
	if job.kind != &"claim_portal":
		return false
	actor.action = &"claiming_portal"
	actor.phase += delta * 5.0
	var complete := _context.infrastructure.work_portal(actor, job.target_cell, delta, definition.work_rate)
	actor.work_progress = progress(job)
	return complete


func label(job: WorkerJob) -> String:
	return "Claiming creature portal"


func progress(job: WorkerJob) -> float:
	return _context.infrastructure.portal_progress.get(job.target_cell, 0.0)
