extends SceneTree
## Local infrastructure work shares ordinary workers' pathing and custody rules.

const Workers = preload("res://content/features/worker_feature.gd")
const Residents = preload("res://content/features/resident_feature.gd")
const STEP := 1.0 / 30.0
const PORTAL := Vector2i(12, 5)
const BANK := Vector2i(2, 4)
const GOLD := Vector2i(10, 3)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_claiming_gates_arrival()
	_excavation_fits_lamps_immediately()
	_priority_and_reservations()
	_lamps_do_not_delay_work()
	_capability_and_route_loss()
	_needs_preempt_specialist_work()
	_custom_provider_extension()
	for failure in _failures:
		push_error(failure)
	print("INFRASTRUCTURE WORKERS: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(capabilities: Array[StringName] = [&"excavate", &"haul", &"claim_portal"], count: int = 1) -> Dictionary:
	var grid := DungeonGrid.new(16, 12)
	for y in range(2, 10):
		for x in range(1, 10):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(2, 5), DungeonGrid.Tile.HEART)
	grid.set_tile(PORTAL, DungeonGrid.Tile.PORTAL)
	grid.set_tile(GOLD, DungeonGrid.Tile.GOLD)
	var worker := CreatureDefinition.new()
	worker.id = &"infrastructure.worker"
	worker.capabilities = capabilities
	worker.move_speed = 8.0
	worker.work_rate = 1.0
	var resident := CreatureDefinition.new()
	resident.id = &"infrastructure.resident"
	resident.capabilities = [&"rest"]
	resident.portal_population_limit = 1
	var lair := RoomDefinition.new()
	lair.id = &"infrastructure.lair"
	lair.tags = [&"lair"]
	var module := ContentModule.new()
	module.id = &"infrastructure.fixture"
	module.definitions = [worker, resident, lair]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Infrastructure fixture registers capability-based workers")
	var context := GameContext.new(grid, registry)
	context.economy.configure_protected_storage({BANK: 500})
	context.rooms.place_initial(lair.id, [Vector2i(4, 4)])
	context.exploration.enable()
	context.infrastructure.enable()
	for index in count:
		context.spawn_creature(worker.id, Vector2i(4 + index, 6))
	var workers := Workers.new()
	workers.setup(context)
	var residents := Residents.new()
	residents.setup(context)
	return {"context": context, "workers": workers, "residents": residents, "conserved": true}


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.residents.tick(STEP)
		scene.workers.tick(STEP)
		scene.context.simulation_ticked.emit(STEP)
		scene.conserved = scene.conserved and scene.context.economy.accounted_gold(scene.context.actors) == scene.context.economy.initial_gold + scene.context.economy.gem_gold_created


func _until(scene: Dictionary, predicate: Callable, seconds: float = 30.0) -> bool:
	for index in ceili(seconds / STEP):
		if predicate.call():
			return true
		_advance(scene, STEP)
	return predicate.call()


func _finish(scene: Dictionary) -> void:
	_check(scene.conserved, "Infrastructure work preserves all gold every simulation tick")
	scene.workers.free()
	scene.residents.free()


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _open_portal(context: GameContext) -> void:
	for x in range(10, 12):
		context.grid.set_tile(Vector2i(x, 5), DungeonGrid.Tile.FLOOR)


func _claiming_gates_arrival() -> void:
	var scene := _fixture([&"claim_portal"])
	var context: GameContext = scene.context
	_advance(scene, 3.0)
	_check(context.actors.size() == 1 and not context.infrastructure.is_portal_claimed(PORTAL) and context.infrastructure.portal_progress[PORTAL] == 0.0, "Unreachable unclaimed portal cannot claim remotely or recruit despite an available Lair")
	_open_portal(context)
	_check(_until(scene, func() -> bool: return context.actors[0].action == &"claiming_portal"), "A claim-capable worker walks through the opened route to the actual portal")
	_check(context.actors[0].position.distance_to(context.grid.cell_to_world(PORTAL)) < 0.1 and context.infrastructure.portal_progress[PORTAL] > 0.0 and context.actors.size() == 1, "Partial claim starts only after physical arrival and does not recruit early")
	var actor := context.actors[0]
	var progress: float = context.infrastructure.portal_progress[PORTAL]
	_check(context.keeper.pickup(actor.id), "Worker can be interrupted during a portal claim")
	_advance(scene, 2.0)
	_check(context.infrastructure.portal_progress[PORTAL] == progress and not context.infrastructure.is_portal_claimed(PORTAL) and scene.workers.job_board.active_job_count() == 0, "Held claimant pauses progress and releases shared reservations")
	_check(context.keeper.drop(Vector2i(11, 5)).success, "Claimant drops on valid connected floor")
	_check(_until(scene, func() -> bool: return context.infrastructure.is_portal_claimed(PORTAL)), "Released worker resumes a partial claim exactly once")
	_check(_until(scene, func() -> bool: return context.actors.size() == 2), "Claimed portal recruits one eligible resident")
	_advance(scene, 10.0)
	_check(context.actors.size() == 2 and context.infrastructure.portal_progress[PORTAL] == 1.0 and scene.workers.job_board.active_job_count() == 0, "Owned portal remains complete without duplicate arrivals or repeated claim jobs")
	_finish(scene)


func _excavation_fits_lamps_immediately() -> void:
	var scene := _fixture([&"excavate", &"haul"])
	var context: GameContext = scene.context
	var actor := context.actors[0]
	actor.carried_gold = context.economy.mine(GOLD, 19)
	context.economy.drop_gold(Vector2i(3, 6), context.economy.mine(GOLD, 23))
	_check(context.keeper.pickup(actor.id) and context.keeper.pickup_gold(Vector2i(3, 6)), "Mixed creature and gold custody precedes excavation lighting")
	var before := context.economy.accounted_gold(context.actors)
	_check(context.infrastructure.lamps.is_empty(), "Fixture has no pre-existing authored lamps")
	context.grid.set_tile(Vector2i(10, 6), DungeonGrid.Tile.FLOOR)
	_check(not context.infrastructure.lamps.is_empty(), "Opening floor fits wall lamps synchronously before another worker tick")
	var supported := true
	for service in context.infrastructure.lamps:
		supported = supported and context.infrastructure.is_lamp_wall_valid(service, context.infrastructure.lamp_walls.get(service, Vector2i(-1, -1)))
	_check(supported and context.infrastructure.lamp_progress.is_empty(), "Immediate fixtures all have actual wall support and no waiting lamp job")
	_check(actor.is_held and actor.carried_gold == 19 and context.keeper.held_count == 2 and context.keeper.total_held_gold == 23 and context.economy.accounted_gold(context.actors) == before, "Instant excavation lighting preserves held identities, cargo and separate gold batches")
	_finish(scene)


func _priority_and_reservations() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var actor := context.actors[0]
	context.mark_excavation([GOLD])
	var job: WorkerJob = scene.workers.job_board.assign(actor, context.registry.get_creature(actor.definition_id))
	_check(job != null and job.kind == &"excavate", "Explicit reachable mining orders take priority over automatic lamps")
	scene.workers.job_board.release(actor.id)
	actor.carried_gold = context.economy.mine(GOLD, 23)
	_open_portal(context)
	job = scene.workers.job_board.assign(actor, context.registry.get_creature(actor.definition_id))
	_check(job != null and job.kind == &"deposit", "Carried gold is delivered before claiming or installation")
	scene.workers.job_board.release(actor.id)
	_check(_until(scene, func() -> bool: return actor.carried_gold == 0 and context.economy.stored_gold >= 23), "Worker safely deposits retained physical cargo before infrastructure work")
	context.clear_excavation_marks()
	scene.workers.job_board.release(actor.id)
	# Board-only reservations demonstrate exclusivity independently of movement.
	var second := context.spawn_creature(actor.definition_id, Vector2i(6, 6))
	job = scene.workers.job_board.assign(actor, context.registry.get_creature(actor.definition_id))
	var other: WorkerJob = scene.workers.job_board.assign(second, context.registry.get_creature(second.definition_id))
	_check(job != null and (other == null or other.work_cell != job.work_cell) and scene.workers.job_board.owns(actor.id, job), "Custom work shares global exclusive workplaces with all worker jobs")
	context.keeper.pickup(actor.id)
	_check(scene.workers.job_board.job_for(actor.id) == null and not scene.workers.job_board.work_reservations.values().has(actor.id), "Pickup synchronously releases a custom reservation")
	_finish(scene)


func _capability_and_route_loss() -> void:
	var scene := _fixture([&"claim_portal"])
	var context: GameContext = scene.context
	_open_portal(context)
	var actor := context.actors[0]
	_advance(scene, STEP)
	_check(scene.workers.job_board.job_for(actor.id) != null, "Optional claimant capability creates a job without excavation or hauling")
	context.grid.set_tile(Vector2i(10, 5), DungeonGrid.Tile.ROCK)
	_advance(scene, 1.0)
	_check(scene.workers.job_board.job_for(actor.id) == null and context.infrastructure.portal_progress[PORTAL] == 0.0, "Blocked route invalidates claim work without remote progress")
	_open_portal(context)
	_advance(scene, STEP)
	context.registry.get_creature(actor.definition_id).capabilities = []
	_advance(scene, 1.0)
	_check(scene.workers.job_board.active_job_count() == 0 and context.infrastructure.portal_progress[PORTAL] == 0.0, "Capability removal releases custom work and cannot award a claim")
	_finish(scene)


func _lamps_do_not_delay_work() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var actor := context.actors[0]
	context.grid.set_tile(Vector2i(10, 6), DungeonGrid.Tile.FLOOR)
	_check(not context.infrastructure.lamps.is_empty() and context.infrastructure.lamp_progress.is_empty(), "Excavated expansion is lit without a separate installation queue")
	context.mark_excavation([GOLD])
	_check(_until(scene, func() -> bool: return scene.workers.job_board.job_for(actor.id) != null and scene.workers.job_board.job_for(actor.id).kind == &"excavate", 0.5), "Mining starts without waiting for lamp construction")
	_check(_until(scene, func() -> bool: return actor.carried_gold > 0, 10.0), "Actual excavation and mining continue after immediate fixture placement")
	_check(actor.action != &"installing_lamp" and context.infrastructure.lamp_progress.is_empty(), "Worker movement remains owned by its mining job rather than a lamp routine")
	_finish(scene)


class ProbeProvider extends WorkerJobProvider:
	var complete := false
	func supports(definition: CreatureDefinition) -> bool:
		return &"probe" in definition.capabilities
	func find_job(board: WorkerJobBoard, actor: CreatureState, _definition: CreatureDefinition, stage: Stage) -> WorkerJob:
		if complete or stage != Stage.IDLE:
			return null
		var cell := Vector2i(4, 6)
		if not board.can_reserve_custom(cell, cell, actor.id):
			return null
		var job := WorkerJob.new(&"test.optional", cell, cell)
		job.path = [cell]
		job.provider = self
		return job
	func is_valid(_job: WorkerJob, _actor: CreatureState, definition: CreatureDefinition) -> bool:
		return not complete and supports(definition)
	func work(_job: WorkerJob, _actor: CreatureState, _definition: CreatureDefinition, _delta: float) -> bool:
		complete = true
		return true


func _custom_provider_extension() -> void:
	var scene := _fixture([&"probe"])
	var probe := ProbeProvider.new()
	scene.workers.job_board.providers.append(probe)
	_check(_until(scene, func() -> bool: return probe.complete, 1.0), "Test-only provider extends worker behavior through capability and shared routing without core dispatch edits")
	_check(scene.workers.job_board.active_job_count() == 0, "Completed extension releases its shared reservation")
	_finish(scene)


func _needs_preempt_specialist_work() -> void:
	var scene := _fixture([&"work", &"claim_portal", &"rest"])
	var context: GameContext = scene.context
	_open_portal(context)
	var actor := context.actors[0]
	_check(_until(scene, func() -> bool: return actor.action == &"claiming_portal"), "A rest-capable specialist establishes its home before claiming without competing movement")
	var partial: float = context.infrastructure.portal_progress[PORTAL]
	actor.energy = 0.05
	_advance(scene, STEP)
	_check(actor.rest_requested and scene.workers.job_board.job_for(actor.id) == null and context.infrastructure.portal_progress[PORTAL] == partial, "Resident rest need synchronously preempts optional work while preserving claim progress")
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Specialist returns to its established bed and sleeps")
	_check(_until(scene, func() -> bool: return context.infrastructure.is_portal_claimed(PORTAL), 60.0), "Rested specialist returns to finish the claim")
	_finish(scene)
