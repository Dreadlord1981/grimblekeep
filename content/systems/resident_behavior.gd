class_name ResidentBehavior
extends RefCounted
## Home, hunger and rest priorities; available workers retain their own jobs.

enum Travel { ARRIVED, MOVING, BLOCKED }
const BED_RETRY_SECONDS := 0.5
const EXPLORE_PAUSE_SECONDS := 1.25
const BED_CLAIM_SECONDS := 1.0
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

var actor: CreatureState
var _context: GameContext
var _bed: BedState
var _needs_rest := false
var _sleeping := false
var _bed_retry_in := 0.0
var _explore_in := 0.0
var _explore_index := 0
var _navigation: ResidentNavigation
var _feeding: ResidentFeeding
var _path: Array[Vector2i]:
	get:
		return _navigation.path
var _traveling_to_bed := false
var _claim_progress := 0.0


func _init(game_context: GameContext, creature: CreatureState) -> void:
	_context = game_context
	actor = creature
	_explore_index = actor.id * 17
	_navigation = ResidentNavigation.new(game_context.grid, actor)
	_feeding = ResidentFeeding.new(game_context, actor)


func tick(delta: float, definition: CreatureDefinition) -> void:
	if actor.is_held:
		return
	_bed_retry_in -= delta
	_explore_in -= delta
	_feeding.update_need(delta, definition)
	var rests := &"rest" in definition.capabilities
	var owned_bed := _context.beds.get_bed(actor.id)
	if owned_bed != _bed:
		_bed = owned_bed
		_sleeping = false
		_claim_progress = 0.0
		_clear_route(not _feeding.active and (not _has_worker_work(definition) or actor.rest_requested))
	if rests and _bed == null and _bed_retry_in <= 0.0:
		_bed_retry_in = BED_RETRY_SECONDS
		_bed = _context.beds.reserve(actor, definition)
	if _sleeping and _bed != null and not (_feeding.is_critical(definition) and _feeding.try_begin()):
		actor.rest_requested = true
		actor.energy = minf(1.0, actor.energy + delta * definition.sleep_restore_per_second)
		actor.phase += delta
		actor.action = &"sleeping"
		actor.job_label = "Sleeping in personal bed"
		if actor.energy < definition.wake_threshold:
			return
		_sleeping = false
		_needs_rest = false
		actor.rest_requested = false
		_explore_in = EXPLORE_PAUSE_SECONDS
		_clear_route()
		_idle("Rested and comfortable")
		return
	if _sleeping:
		# Critical hunger can wake a sleeper only after a reachable meal is held.
		_sleeping = false
		_clear_route()
	if rests:
		actor.energy = maxf(0.0, actor.energy - delta * definition.energy_drain_per_second)
	if rests and actor.energy <= definition.sleep_threshold:
		_needs_rest = true
	if not rests:
		_needs_rest = false
	var making_home: bool = _bed != null and not _bed.established
	actor.rest_requested = _needs_rest or making_home
	if making_home:
		if _feeding.active:
			_feeding.cancel()
			_clear_route()
		_make_home(delta, definition)
	elif _feeding.active:
		_feeding.tick(delta, definition)
	elif _feeding.is_critical(definition) and _feeding.try_begin():
		_clear_route()
		_feeding.tick(delta, definition)
	elif _needs_rest:
		_seek_rest(delta, definition)
	elif _feeding.try_begin():
		_clear_route()
		_feeding.tick(delta, definition)
	elif _has_worker_work(definition):
		# Awake workers keep their current jobs. Every work consumer must yield to
		# needs_requested before moving this actor or executing its assignment.
		_clear_route(false)
	else:
		_explore(delta, definition)


func cancel() -> void:
	var definition := _context.registry.get_creature(actor.definition_id)
	var controlled_actor: bool = actor.rest_requested or actor.food_requested or not _has_worker_work(definition)
	_feeding.cancel()
	actor.rest_requested = false
	_sleeping = false
	_claim_progress = 0.0
	_clear_route(controlled_actor)
	if controlled_actor:
		_idle("Awaiting resident behavior")


func _has_worker_work(definition: CreatureDefinition) -> bool:
	return definition != null and (&"excavate" in definition.capabilities or &"haul" in definition.capabilities)


func _make_home(delta: float, definition: CreatureDefinition) -> void:
	var center := _bed.center(_context.grid)
	if actor.position.distance_to(center) > DungeonBeds.CLAIM_DISTANCE:
		if _claim_progress > 0.0:
			_claim_progress = 0.0
			_clear_route()
		if not _traveling_to_bed:
			if not _set_route(_context.grid.world_to_cell(center), center):
				_lose_bed()
				return
			_traveling_to_bed = true
		actor.target_cell = _bed.anchor
		actor.job_label = "Going to claim personal Lair space"
		var travel := _follow_route(delta, definition.move_speed)
		if travel == Travel.BLOCKED:
			_lose_bed()
		elif travel == Travel.ARRIVED:
			_clear_route()
		return
	actor.action = &"claiming_bed"
	actor.job_label = "Claiming personal Lair space"
	actor.target_cell = _bed.anchor
	actor.phase += delta * 4.0
	_claim_progress = minf(1.0, _claim_progress + delta / BED_CLAIM_SECONDS)
	actor.work_progress = _claim_progress
	if _claim_progress < 1.0:
		return
	if not _context.beds.establish(actor):
		_lose_bed()
		return
	_claim_progress = 0.0
	_clear_route()
	actor.rest_requested = _needs_rest
	_idle("Personal bed established")


func _seek_rest(delta: float, definition: CreatureDefinition) -> void:
	if _bed == null:
		_clear_route()
		actor.action = &"homeless"
		actor.job_label = "Needs a reachable personal bed"
		return
	if not _traveling_to_bed:
		var center := _bed.center(_context.grid)
		if not _set_route(_context.grid.world_to_cell(center), center):
			_lose_bed()
			return
		_traveling_to_bed = true
	actor.job_label = "Going to personal bed"
	actor.target_cell = _bed.anchor
	var travel := _follow_route(delta, definition.move_speed)
	if travel == Travel.BLOCKED:
		_lose_bed()
	elif travel == Travel.ARRIVED:
		_sleeping = true
		actor.action = &"sleeping"
		actor.job_label = "Sleeping in personal bed"
		_clear_route()


func _lose_bed() -> void:
	_context.beds.release(actor.id)
	_bed = null
	_sleeping = false
	_claim_progress = 0.0
	_bed_retry_in = BED_RETRY_SECONDS
	_clear_route()
	actor.action = &"homeless"
	actor.job_label = "Cannot reach a bed; seeking another"


func _explore(delta: float, definition: CreatureDefinition) -> void:
	if not _path.is_empty():
		var travel := _follow_route(delta, definition.move_speed)
		actor.job_label = "Exploring the dungeon"
		if travel != Travel.MOVING:
			_clear_route()
			_explore_in = EXPLORE_PAUSE_SECONDS
			_idle(_ambient_description(definition))
		return
	_idle(_ambient_description(definition))
	if _explore_in > 0.0:
		return
	_explore_in = EXPLORE_PAUSE_SECONDS
	var current := _context.grid.world_to_cell(actor.position)
	for index in NEIGHBORS.size():
		var candidate: Vector2i = current + NEIGHBORS[(_explore_index + index) % NEIGHBORS.size()]
		if _context.grid.get_tile(candidate) != DungeonGrid.Tile.FLOOR or not _context.grid.is_inside(candidate):
			continue
		if _set_route(candidate, _context.grid.cell_to_world(candidate)):
			_explore_index += index + 1
			actor.target_cell = candidate
			actor.job_label = "Exploring the dungeon"
			_follow_route(delta, definition.move_speed)
			return
	_explore_index += 1


func _set_route(goal_cell: Vector2i, goal_world: Vector3) -> bool:
	return _navigation.set_route(goal_cell, goal_world)


func _follow_route(delta: float, speed: float) -> int:
	return _navigation.follow(delta, speed)


func _clear_route(clear_actor: bool = true) -> void:
	_navigation.clear()
	_traveling_to_bed = false
	if clear_actor:
		actor.target_cell = Vector2i(-1, -1)
		actor.work_progress = 0.0


func _idle(description: String) -> void:
	actor.action = &"idle"
	actor.job_label = description


func _ambient_description(definition: CreatureDefinition) -> String:
	if &"rest" in definition.capabilities and _bed == null:
		return "Looking for a personal bed"
	return "Waiting for reachable food" if _feeding.unmet_food else "Enjoying the dungeon"
