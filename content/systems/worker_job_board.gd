class_name WorkerJobBoard
extends RefCounted
## Finds reachable work and owns reservations. It never walks or awards gold.

const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

# Each target owns actor_id -> work_cell slots. Mining nodes can share four
# cardinal faces; stone and loose gold remain exclusive assignments.
var target_reservations: Dictionary[Vector2i, Dictionary] = {}
var work_reservations: Dictionary[Vector2i, int] = {}
var _jobs: Dictionary[int, WorkerJob] = {}
var _context: GameContext


func _init(game_context: GameContext) -> void:
	_context = game_context


func active_job_count() -> int:
	return _jobs.size()


func job_for(actor_id: int) -> WorkerJob:
	return _jobs.get(actor_id)


func assign(actor: CreatureState, definition: CreatureDefinition) -> WorkerJob:
	if actor.is_held:
		release(actor.id)
		return null
	if _jobs.has(actor.id):
		return _jobs[actor.id]
	var start := _context.grid.world_to_cell(actor.position)
	if not _context.grid.is_walkable(start):
		return null
	var job: WorkerJob
	if actor.carried_gold > 0:
		if &"haul" in definition.capabilities:
			job = _find_deposit(start, actor.id)
	elif &"haul" in definition.capabilities:
		job = _find_haul(start, actor.id)
	if job == null and actor.carried_gold == 0 and &"excavate" in definition.capabilities:
		job = _find_excavation(start, actor.id)
	if job != null:
		_reserve(actor.id, job)
	return job


func release(actor_id: int) -> void:
	var job := job_for(actor_id)
	if job == null:
		return
	if target_reservations.has(job.target_cell):
		var slots: Dictionary = target_reservations[job.target_cell]
		if slots.get(actor_id) == job.work_cell:
			slots.erase(actor_id)
			if slots.is_empty():
				target_reservations.erase(job.target_cell)
	if work_reservations.get(job.work_cell, -1) == actor_id:
		work_reservations.erase(job.work_cell)
	_jobs.erase(actor_id)


func owns(actor_id: int, job: WorkerJob) -> bool:
	if job == null or job_for(actor_id) != job or work_reservations.get(job.work_cell, -1) != actor_id:
		return false
	if job.kind == &"deposit":
		return true
	var slots: Dictionary = target_reservations.get(job.target_cell, {})
	return slots.get(actor_id) == job.work_cell


func has_reachable_treasury(start: Vector2i) -> bool:
	for cell in _context.economy.treasury_cells:
		if _context.economy.available_storage(cell) > 0 and not GridPathfinder.find_path(_context.grid, start, cell).is_empty():
			return true
	return false


func _find_deposit(start: Vector2i, actor_id: int) -> WorkerJob:
	var best: WorkerJob
	var best_fill := INF
	var finite_storage := _context.economy.treasury_capacity >= 0
	for cell in _context.economy.treasury_cells:
		if _context.economy.available_storage(cell) <= 0 or not _work_available(cell, actor_id):
			continue
		var path := GridPathfinder.find_path(_context.grid, start, cell)
		var capacity := _context.economy.storage_capacity(cell)
		var fill := float(_context.economy.stored_by_cell.get(cell, 0)) / float(capacity) if finite_storage and capacity > 0 else 0.0
		if path.is_empty() or fill > best_fill:
			continue
		if best != null and is_equal_approx(fill, best_fill) and GridPathfinder.path_cost(path) >= GridPathfinder.path_cost(best.path):
			continue
		best = WorkerJob.new(&"deposit", cell, cell)
		best.path = path
		best_fill = fill
	return best


func _find_haul(start: Vector2i, actor_id: int) -> WorkerJob:
	var best: WorkerJob
	for cell in _context.economy.ground_gold:
		if _context.economy.ground_gold[cell] <= 0 or target_reservations.has(cell) or not _work_available(cell, actor_id):
			continue
		var path := GridPathfinder.find_path(_context.grid, start, cell)
		if path.is_empty() or (best != null and GridPathfinder.path_cost(path) >= GridPathfinder.path_cost(best.path)):
			continue
		# Do not create a pick-up/drop loop when storage cannot be reached.
		if not has_reachable_treasury(cell):
			continue
		best = WorkerJob.new(&"haul", cell, cell)
		best.path = path
	return best


func _find_excavation(start: Vector2i, actor_id: int) -> WorkerJob:
	var best: WorkerJob
	for target in _context.excavation_marks:
		if not _context.grid.can_excavate(target) or not _target_available(target, actor_id):
			continue
		for direction in DIRECTIONS:
			var workplace: Vector2i = target + direction
			if not _context.grid.is_walkable(workplace) or not _work_available(workplace, actor_id):
				continue
			# Mineral orders remain marked while storage is full or disconnected.
			# Ordinary stone excavation does not consume Treasury capacity.
			if _context.grid.get_tile(target) in [DungeonGrid.Tile.GOLD, DungeonGrid.Tile.GEM] and not has_reachable_treasury(workplace):
				continue
			var path := GridPathfinder.find_path(_context.grid, start, workplace)
			if path.is_empty() or (best != null and GridPathfinder.path_cost(path) >= GridPathfinder.path_cost(best.path)):
				continue
			best = WorkerJob.new(&"excavate", target, workplace)
			best.terrain_kind = _context.grid.get_tile(target)
			best.path = path
	return best


func _work_available(cell: Vector2i, actor_id: int) -> bool:
	return not work_reservations.has(cell) or work_reservations[cell] == actor_id


func _target_available(cell: Vector2i, actor_id: int) -> bool:
	var slots: Dictionary = target_reservations.get(cell, {})
	if slots.has(actor_id):
		return true
	var capacity := 4 if _context.grid.get_tile(cell) in [DungeonGrid.Tile.GOLD, DungeonGrid.Tile.GEM] else 1
	return slots.size() < capacity


func _reserve(actor_id: int, job: WorkerJob) -> void:
	_jobs[actor_id] = job
	work_reservations[job.work_cell] = actor_id
	if job.kind != &"deposit":
		var slots: Dictionary = target_reservations.get(job.target_cell, {})
		slots[actor_id] = job.work_cell
		target_reservations[job.target_cell] = slots
