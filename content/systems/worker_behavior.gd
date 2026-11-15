class_name WorkerBehavior
extends RefCounted
## Executes one creature's assignment using shared state and economy operations.

const POLL_SECONDS := 0.25
const GOLD_PER_STRIKE := 20

var actor: CreatureState
var job: WorkerJob
var last_safe_cell: Vector2i
var _context: GameContext
var _board: WorkerJobBoard
var _path_index := 0
var _retry_in := 0.0


func _init(game_context: GameContext, board: WorkerJobBoard, creature: CreatureState) -> void:
	_context = game_context
	_board = board
	actor = creature
	last_safe_cell = _context.grid.world_to_cell(actor.position)


func tick(delta: float, definition: CreatureDefinition) -> void:
	var current_cell := _context.grid.world_to_cell(actor.position)
	if _context.grid.is_walkable(current_cell):
		last_safe_cell = current_cell
	if job != null and not _job_is_valid(definition):
		cancel()
	if job == null:
		_retry_in -= delta
		if _retry_in > 0.0:
			return
		_retry_in = POLL_SECONDS
		job = _board.assign(actor, definition)
		_path_index = 0
		if job == null:
			_handle_idle(definition)
			return
		actor.target_cell = job.target_cell
		actor.work_progress = 0.0
		actor.job_label = _job_label()
	if not _follow_path(delta, definition.move_speed):
		return
	if job == null:
		return
	if job.kind == &"excavate":
		_work(delta, definition)
	elif job.kind == &"haul":
		_pick_up_gold(definition)
	else:
		_deposit_gold()


func cancel() -> void:
	_board.release(actor.id)
	job = null
	_path_index = 0
	actor.action = &"idle"
	actor.job_label = "Awaiting work"
	actor.work_progress = 0.0
	actor.target_cell = Vector2i(-1, -1)


func recover_removed_actor() -> bool:
	# Called when this actor leaves the session. Retain it for a retry if every
	# tile is blocked rather than silently destroying its cargo.
	cancel()
	return drop_cargo()


func drop_cargo() -> bool:
	if actor.carried_gold <= 0:
		return true
	var cell := _nearest_safe_cell()
	if cell.x < 0:
		return false
	if not _context.economy.drop_gold(cell, actor.carried_gold):
		return false
	actor.carried_gold = 0
	return true


func _handle_idle(definition: CreatureDefinition) -> void:
	actor.action = &"idle"
	actor.job_label = "Awaiting reachable work"
	if actor.carried_gold <= 0:
		return
	var start := _context.grid.world_to_cell(actor.position)
	if &"haul" not in definition.capabilities or not _board.has_reachable_treasury(start):
		drop_cargo()
	else:
		actor.job_label = "Waiting for a treasury position"


func _job_is_valid(definition: CreatureDefinition) -> bool:
	if not _board.owns(actor.id, job) or not _context.grid.is_walkable(job.work_cell):
		return false
	if job.kind == &"excavate":
		return &"excavate" in definition.capabilities and _context.excavation_marks.has(job.target_cell) and _context.grid.get_tile(job.target_cell) == job.terrain_kind and _context.grid.can_excavate(job.target_cell)
	if job.kind == &"haul":
		return &"haul" in definition.capabilities and _context.economy.ground_gold.get(job.target_cell, 0) > 0 and _board.has_reachable_treasury(job.target_cell)
	return &"haul" in definition.capabilities and actor.carried_gold > 0 and _context.economy.available_storage(job.target_cell) > 0


func _follow_path(delta: float, speed: float) -> bool:
	# A route may change underneath a walking worker. Validate every remaining
	# edge (including diagonal flank tiles) before moving and replan once.
	for index in range(_path_index, job.path.size()):
		var previous := job.path[maxi(0, index - 1)]
		if not GridPathfinder.can_step(_context.grid, previous, job.path[index]):
			var start := _context.grid.world_to_cell(actor.position)
			job.path = GridPathfinder.find_path(_context.grid, start, job.work_cell)
			_path_index = 0
			if job.path.is_empty():
				cancel()
				return false
			break
	var budget := speed * delta
	var moved := false
	while _path_index < job.path.size():
		var destination := _context.grid.cell_to_world(job.path[_path_index])
		var distance := actor.position.distance_to(destination)
		if distance < 0.002:
			actor.position = destination
			last_safe_cell = job.path[_path_index]
			_path_index += 1
			continue
		if budget <= 0.0:
			break
		var direction := destination - actor.position
		actor.heading = atan2(direction.x, direction.z)
		var traveled := minf(distance, budget)
		actor.position = actor.position.move_toward(destination, traveled)
		actor.phase += traveled * 4.0
		budget -= traveled
		moved = true
	if moved:
		actor.action = &"hauling" if actor.carried_gold > 0 else &"walking"
		return false
	return _path_index >= job.path.size()


func _work(delta: float, definition: CreatureDefinition) -> void:
	var is_stone := job.terrain_kind == DungeonGrid.Tile.ROCK
	actor.action = &"digging" if is_stone else &"mining"
	var direction := _context.grid.cell_to_world(job.target_cell) - actor.position
	actor.heading = atan2(direction.x, direction.z)
	actor.phase += delta * 7.0
	var duration := 2.5 if is_stone else (3.0 if job.terrain_kind == DungeonGrid.Tile.GEM else 1.4)
	actor.work_progress = minf(1.0, actor.work_progress + delta * definition.work_rate / duration)
	if actor.work_progress < 1.0:
		return
	if is_stone:
		_context.grid.set_tile(job.target_cell, DungeonGrid.Tile.FLOOR)
		cancel()
		return
	var mined := _context.economy.mine(job.target_cell, GOLD_PER_STRIKE)
	var carried := mini(mined, maxi(0, definition.carry_capacity - actor.carried_gold))
	actor.carried_gold += carried
	if mined > carried:
		_context.economy.drop_gold(job.work_cell, mined - carried)
	actor.work_progress = 0.0
	if job.terrain_kind == DungeonGrid.Tile.GOLD and _context.economy.remaining_gold.get(job.target_cell, 0) <= 0:
		_context.grid.set_tile(job.target_cell, DungeonGrid.Tile.FLOOR)
		cancel()
	elif actor.carried_gold >= definition.carry_capacity:
		cancel()


func _pick_up_gold(definition: CreatureDefinition) -> void:
	var capacity := maxi(0, definition.carry_capacity - actor.carried_gold)
	actor.carried_gold += _context.economy.take_gold(job.target_cell, capacity)
	cancel()


func _deposit_gold() -> void:
	actor.action = &"depositing"
	var amount := mini(actor.carried_gold, _context.economy.available_storage(job.target_cell))
	if _context.economy.deposit(job.target_cell, amount):
		actor.carried_gold -= amount
	cancel()


func _nearest_safe_cell() -> Vector2i:
	var current := _context.grid.world_to_cell(actor.position)
	if _context.grid.is_walkable(current):
		return current
	if _context.grid.is_walkable(last_safe_cell):
		return last_safe_cell
	var best := Vector2i(-1, -1)
	var best_distance := 2147483647
	for y in _context.grid.height:
		for x in _context.grid.width:
			var cell := Vector2i(x, y)
			var distance := absi(x - current.x) + absi(y - current.y)
			if _context.grid.is_walkable(cell) and distance < best_distance:
				best = cell
				best_distance = distance
	return best


func _job_label() -> String:
	if job.kind == &"deposit":
		return "Delivering gold to treasury"
	if job.kind == &"haul":
		return "Collecting dropped gold"
	if job.terrain_kind == DungeonGrid.Tile.GOLD:
		return "Mining gold seam"
	if job.terrain_kind == DungeonGrid.Tile.GEM:
		return "Mining gem seam"
	return "Excavating stone"
