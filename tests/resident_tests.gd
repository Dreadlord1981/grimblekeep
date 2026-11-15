extends SceneTree
## Capacity-gated portal arrivals and repeated autonomous rest, with interruptions.

const ResidentFeature = preload("res://content/features/resident_feature.gd")
const WorkerFeature = preload("res://content/features/worker_feature.gd")
const STEP := 1.0 / 30.0
const SPECIES := &"resident_test.creature"
const LAIR := &"resident_test.lair"
const PORTAL := Vector2i(1, 4)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_arrival_capacity_and_limit()
	_test_healthy_resident_claims_home_first()
	_test_claim_interruption_and_restart()
	_test_unreachable_arrival()
	_test_one_arrival_per_scan()
	_test_bed_capacity_respects_existing_residents()
	_test_repeated_sleep_and_exploration()
	_test_sell_sleeping_bed_and_rebuild()
	_test_diagonal_route_interruption()
	_test_unreachable_bed_release()
	_test_removed_actor_and_capability()
	_test_large_footprint_extension()
	_test_feature_reload_and_worker_isolation()
	_test_hybrid_worker_rest_priority()
	_test_hybrid_claims_home_before_work()
	for failure in _failures:
		push_error(failure)
	print("RESIDENT RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(footprint: Vector2i = Vector2i.ONE, limit: int = 0) -> Dictionary:
	var grid := DungeonGrid.new(12, 10)
	for y in range(1, 8):
		for x in range(1, 10):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(PORTAL, DungeonGrid.Tile.PORTAL)
	var definition := CreatureDefinition.new()
	definition.id = SPECIES
	definition.display_name = "Test resident"
	definition.capabilities = [&"rest"]
	definition.bed_size = footprint
	definition.move_speed = 4.0
	definition.initial_energy = 0.45
	definition.energy_drain_per_second = 0.2
	definition.sleep_restore_per_second = 0.8
	definition.portal_population_limit = limit
	var worker := CreatureDefinition.new()
	worker.id = &"resident_test.worker"
	worker.capabilities = [&"excavate", &"haul"]
	var room := RoomDefinition.new()
	room.id = LAIR
	room.display_name = "Test lair"
	room.gold_cost_per_tile = 50
	room.tags = [&"lair"]
	var module := ContentModule.new()
	module.id = &"resident_test"
	module.definitions = [definition, worker, room]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Resident/worker/Lair definitions register through content data")
	var context := GameContext.new(grid, registry)
	var feature := ResidentFeature.new()
	feature.setup(context)
	return {"context": context, "definition": definition, "feature": feature, "conserved": true}


func _room(scene: Dictionary, anchor: Vector2i, size: Vector2i = Vector2i.ONE) -> void:
	var cells: Array[Vector2i] = []
	for y in range(anchor.y, anchor.y + size.y):
		for x in range(anchor.x, anchor.x + size.x):
			cells.append(Vector2i(x, y))
	_check(scene.context.rooms.place_initial(LAIR, cells), "Fixture places a real Lair through room rules")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.feature.tick(STEP)
		var context: GameContext = scene.context
		var economy := context.economy
		if economy.accounted_gold(context.actors) != economy.initial_gold + economy.gem_gold_created:
			scene.conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 30.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _finish(scene: Dictionary, label: String) -> void:
	_check(scene.conserved, "%s never creates unaccounted economic resources" % label)
	scene.feature.free()


func _test_arrival_capacity_and_limit() -> void:
	var scene := _fixture(Vector2i.ONE, 1)
	var context: GameContext = scene.context
	_advance(scene, 5.0)
	_check(context.actors.is_empty(), "A portal alone cannot attract a homeless resident")
	_room(scene, Vector2i(6, 4))
	_check(_until(scene, func() -> bool: return context.actors.size() == 1), "Building a reachable fitting Lair admits a resident")
	var actor := context.actors[0]
	_check(actor.position == context.grid.cell_to_world(PORTAL), "Resident physically appears at the portal")
	_check(is_equal_approx(actor.energy, scene.definition.initial_energy), "Arrival starts with species-defined energy")
	_check(context.beds.get_bed(actor.id) != null and not context.beds.get_bed(actor.id).established, "Arrival reserves capacity without establishing a remote bed")
	_room(scene, Vector2i(7, 4), Vector2i(2, 2))
	_advance(scene, 20.0)
	_check(context.actors.size() == 1, "Extra room capacity does not bypass the species population limit")
	_finish(scene, "Portal eligibility")


func _test_unreachable_arrival() -> void:
	var scene := _fixture(Vector2i.ONE, 1)
	var context: GameContext = scene.context
	for y in range(1, 8):
		context.grid.set_tile(Vector2i(4, y), DungeonGrid.Tile.ROCK)
	_room(scene, Vector2i(6, 4))
	_advance(scene, 5.0)
	_check(context.actors.is_empty(), "An unreachable Lair cannot attract creatures through a wall")
	context.grid.set_tile(Vector2i(4, 4), DungeonGrid.Tile.FLOOR)
	_check(_until(scene, func() -> bool: return context.actors.size() == 1), "Opening a route makes existing room capacity eligible")
	_finish(scene, "Unreachable portal room")


func _test_one_arrival_per_scan() -> void:
	var scene := _fixture(Vector2i.ONE, 3)
	var context: GameContext = scene.context
	context.grid.set_tile(Vector2i(1, 2), DungeonGrid.Tile.PORTAL)
	_room(scene, Vector2i(6, 3), Vector2i(2, 2))
	_advance(scene, STEP)
	_check(context.actors.size() == 1, "Multiple portals still admit at most one resident per scan")
	_advance(scene, 0.5)
	_check(context.actors.size() == 1, "Arrival polling is bounded between scans")
	_check(_until(scene, func() -> bool: return context.actors.size() == 3, 10.0), "Later scans admit residents up to the configured cap")
	_check(context.beds.beds.size() == 3, "Every arrival has a separate reserved bed")
	var occupied: Dictionary[Vector2i, bool] = {}
	var nonoverlapping := true
	for bed: BedState in context.beds.beds.values():
		for cell in bed.cells:
			nonoverlapping = nonoverlapping and not occupied.has(cell)
			occupied[cell] = true
	_check(nonoverlapping, "Pending and established arrivals reserve distinct nonoverlapping footprints")
	_finish(scene, "Multiple portal scans")


func _test_bed_capacity_respects_existing_residents() -> void:
	var scene := _fixture(Vector2i.ONE, 2)
	var context: GameContext = scene.context
	_room(scene, Vector2i(6, 4))
	var resident := context.spawn_creature(SPECIES, Vector2i(5, 4))
	_advance(scene, 5.0)
	_check(context.actors.size() == 1 and context.beds.get_bed(resident.id) != null, "Existing residents reserve beds before portal eligibility is evaluated")
	_room(scene, Vector2i(7, 4))
	_check(_until(scene, func() -> bool: return context.actors.size() == 2), "Adding another bed footprint permits the next resident")
	var first := context.beds.get_bed(context.actors[0].id)
	var second := context.beds.get_bed(context.actors[1].id)
	_check(first != null and second != null and first.anchor != second.anchor, "Existing resident and new arrival cannot share a personal bed")
	_finish(scene, "Existing bed capacity")


func _test_repeated_sleep_and_exploration() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_room(scene, Vector2i(6, 4))
	var actor := context.spawn_creature(SPECIES, Vector2i(5, 4))
	var previous_sleep := false
	var sleeps := 0
	var moved := false
	var energy_fell := false
	var energy_rose := false
	var within_bounds := true
	var remained_walkable := true
	for index in 1200:
		var before := actor.position
		var energy := actor.energy
		_advance(scene, STEP)
		var sleeping := actor.action == &"sleeping"
		if sleeping and not previous_sleep:
			sleeps += 1
		previous_sleep = sleeping
		moved = moved or actor.position.distance_to(before) > 0.001
		energy_fell = energy_fell or actor.energy < energy
		energy_rose = energy_rose or actor.energy > energy
		within_bounds = within_bounds and actor.energy >= 0.0 and actor.energy <= 1.0
		remained_walkable = remained_walkable and context.grid.is_walkable(context.grid.world_to_cell(actor.position))
	_check(sleeps >= 3, "Resident completes repeated autonomous sleep cycles")
	_check(moved and energy_fell and energy_rose, "Resident explores, loses awake energy and restores energy by sleeping")
	_check(within_bounds and remained_walkable, "Repeated rest/exploration preserves energy bounds and valid terrain")
	_check(context.beds.get_bed(actor.id) != null, "A resident retains its personal bed between sleep cycles")
	_finish(scene, "Repeated rest loop")


func _test_sell_sleeping_bed_and_rebuild() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_room(scene, Vector2i(6, 4))
	var actor := context.spawn_creature(SPECIES, Vector2i(5, 4))
	actor.energy = 0.1
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Tired resident reaches its bed and begins sleeping")
	context.rooms.remove([Vector2i(6, 4)])
	_check(context.economy.refunded_gold == 25 and context.economy.ground_gold.get(Vector2i(6, 4), 0) == 25, "Selling the occupied bed's room tile records its exact physical refund")
	_advance(scene, 1.0)
	_check(context.beds.get_bed(actor.id) == null and actor.action != &"sleeping", "Selling an occupied Lair removes bed ownership and interrupts sleep")
	_room(scene, Vector2i(7, 4))
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Homeless resident discovers and sleeps in a rebuilt reachable Lair")
	_check(context.beds.get_bed(actor.id).anchor == Vector2i(7, 4), "Rebuilt Lair gets a fresh personal bed reference")
	_finish(scene, "Sold occupied bed")


func _test_diagonal_route_interruption() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_room(scene, Vector2i(6, 5))
	var actor := context.spawn_creature(SPECIES, Vector2i(2, 2))
	actor.energy = 0.1
	_advance(scene, STEP)
	var behavior: ResidentBehavior = scene.feature.behaviors[actor.id]
	var route: Array[Vector2i] = behavior.get("_path")
	var flank := Vector2i(-1, -1)
	for index in range(1, route.size()):
		var offset := route[index] - route[index - 1]
		if offset.x != 0 and offset.y != 0:
			flank = route[index - 1] + Vector2i(offset.x, 0)
			break
	_check(flank != Vector2i(-1, -1), "Fixture finds an actual diagonal resident route")
	context.grid.set_tile(flank, DungeonGrid.Tile.ROCK)
	var before := actor.position
	_advance(scene, STEP)
	_check(actor.position.distance_to(before) <= scene.definition.move_speed * STEP + 0.001, "Route invalidation never teleports a resident")
	var revised: Array[Vector2i] = behavior.get("_path")
	var edges_valid := true
	for index in range(1, revised.size()):
		edges_valid = edges_valid and GridPathfinder.can_step(context.grid, revised[index - 1], revised[index])
	_check(edges_valid, "Changed diagonal flanks force a corner-safe route before movement continues")
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Resident reaches the bed by an alternate route")
	_finish(scene, "Diagonal resident replan")


func _test_removed_actor_and_capability() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_room(scene, Vector2i(6, 4), Vector2i(2, 1))
	var actor := context.spawn_creature(SPECIES, Vector2i(5, 4))
	_advance(scene, STEP)
	_check(context.beds.get_bed(actor.id) != null, "Resident reserves a bed before removal")
	context.despawn_creature(actor.id)
	_advance(scene, STEP)
	_check(context.beds.get_bed(actor.id) == null and not scene.feature.behaviors.has(actor.id), "Despawn releases the removed actor's bed and behavior")
	actor = context.spawn_creature(SPECIES, Vector2i(5, 4))
	_advance(scene, STEP)
	scene.definition.capabilities.clear()
	_advance(scene, STEP)
	_check(context.beds.get_bed(actor.id) == null and not scene.feature.behaviors.has(actor.id), "Losing the rest capability releases beds and resident control")
	_finish(scene, "Resident removal")


func _test_unreachable_bed_release() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_room(scene, Vector2i(6, 4))
	var actor := context.spawn_creature(SPECIES, Vector2i(2, 4))
	actor.energy = 0.1
	_advance(scene, STEP)
	_check(context.beds.get_bed(actor.id) != null, "Tired resident owns a reachable bed before a route is sealed")
	for y in range(1, 8):
		context.grid.set_tile(Vector2i(4, y), DungeonGrid.Tile.ROCK)
	var before := actor.position
	_advance(scene, 2.0)
	_check(context.beds.get_bed(actor.id) == null and actor.rest_requested and actor.action == &"homeless", "Sealing the route releases the inaccessible personal bed and keeps rest demand")
	_check(actor.position.distance_to(before) < 0.001, "Homeless resident waits without crossing a sealed wall or teleporting")
	context.grid.set_tile(Vector2i(4, 4), DungeonGrid.Tile.FLOOR)
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Reopening the route lets the resident reacquire a bed and rest")
	_finish(scene, "Sealed bed route")


func _test_large_footprint_extension() -> void:
	var scene := _fixture(Vector2i(2, 2), 1)
	var context: GameContext = scene.context
	_room(scene, Vector2i(6, 3), Vector2i(3, 1))
	_advance(scene, 3.0)
	_check(context.actors.is_empty(), "Enough room tiles in the wrong shape cannot fit a larger species bed")
	_room(scene, Vector2i(6, 4), Vector2i(3, 1))
	_check(_until(scene, func() -> bool: return context.actors.size() == 1), "A new two-by-two species arrives when a fitting footprint exists")
	var actor := context.actors[0]
	actor.energy = 0.1
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Large-bed species uses the same autonomous rest implementation")
	var bed := context.beds.get_bed(actor.id)
	_check(bed.cells.size() == 4 and actor.position.distance_to(bed.center(context.grid)) < 0.01, "Large species sleeps at the center of its complete personal footprint")
	_finish(scene, "Species footprint extension")


func _test_feature_reload_and_worker_isolation() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_room(scene, Vector2i(6, 4))
	var actor := context.spawn_creature(SPECIES, Vector2i(5, 4))
	var worker := context.spawn_creature(&"resident_test.worker", Vector2i(3, 3))
	worker.action = &"mining"
	worker.job_label = "Worker controlled"
	var worker_start := worker.position
	var worker_energy := worker.energy
	_advance(scene, 2.0)
	var bed := context.beds.get_bed(actor.id)
	scene.feature.setup(context)
	_advance(scene, 3.0)
	_check(context.beds.get_bed(actor.id) == bed and scene.feature.behaviors.size() == 1, "Feature reload adopts the existing personal bed without duplicating ownership")
	_check(worker.position == worker_start and worker.energy == worker_energy and worker.action == &"mining" and worker.job_label == "Worker controlled", "Resident feature leaves worker movement, energy and jobs untouched")
	var count := context.actors.size()
	scene.feature.tick(NAN)
	scene.feature.tick(-1.0)
	_check(context.actors.size() == count and actor.energy >= 0.0, "Invalid timesteps do not spawn actors or corrupt resident needs")
	_finish(scene, "Feature lifecycle and worker isolation")


func _test_hybrid_worker_rest_priority() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var definition: CreatureDefinition = scene.definition
	definition.capabilities.assign([&"rest", &"excavate", &"haul"])
	definition.initial_energy = 0.95
	definition.energy_drain_per_second = 0.02
	definition.sleep_restore_per_second = 2.0
	definition.work_rate = 5.0
	_room(scene, Vector2i(6, 3))
	context.economy.configure_treasury({Vector2i(2, 3): 500})
	context.grid.set_tile(Vector2i(10, 4), DungeonGrid.Tile.GOLD)
	context.mark_excavation([Vector2i(10, 4)])
	var actor := context.spawn_creature(SPECIES, Vector2i(8, 4))
	var established_bed := context.beds.reserve(actor, definition)
	actor.position = established_bed.center(context.grid)
	_check(context.beds.establish(actor), "Worker-rest fixture establishes its existing bed with the owner physically present")
	actor.position = context.grid.cell_to_world(Vector2i(8, 4))
	var worker := WorkerFeature.new()
	worker.setup(context)
	var seen_cargo := false
	for index in 600:
		_tick_hybrid(scene, worker)
		if actor.carried_gold > 0:
			seen_cargo = true
			break
	_check(seen_cargo and not actor.rest_requested, "A rested multi-talent creature performs normal mining work")
	_check(worker.job_board.job_for(actor.id) != null, "Awake hybrid has a real reserved worker assignment")
	var cargo := actor.carried_gold
	actor.energy = 0.1
	var before := actor.position
	_tick_hybrid(scene, worker)
	_check(actor.rest_requested and worker.job_board.job_for(actor.id) == null and worker.job_board.active_job_count() == 0, "Rest demand interrupts the worker job and releases mining reservations")
	_check(actor.carried_gold == cargo, "Interrupting work for sleep preserves carried gold")
	_check(actor.position.distance_to(before) <= definition.move_speed * STEP + 0.001, "Resident and worker features cannot move the hybrid twice in one tick")
	var slept := false
	var woke := false
	var resumed := false
	for index in 1200:
		_tick_hybrid(scene, worker)
		slept = slept or actor.action == &"sleeping"
		woke = woke or (slept and not actor.rest_requested)
		if woke and context.economy.stored_gold > 0:
			resumed = true
			break
	_check(slept and woke and resumed, "Hybrid sleeps, wakes, and resumes physical gold delivery")
	_check(scene.conserved, "Hybrid rest interruption never loses or duplicates mined cargo")
	worker.free()
	_finish(scene, "Hybrid work and rest priority")


func _tick_hybrid(scene: Dictionary, worker: GameFeature) -> void:
	scene.feature.tick(STEP)
	worker.tick(STEP)
	var economy: GoldEconomy = scene.context.economy
	if economy.accounted_gold(scene.context.actors) != economy.initial_gold + economy.gem_gold_created:
		scene.conserved = false


func _test_healthy_resident_claims_home_first() -> void:
	var scene := _fixture(Vector2i(2, 2))
	var context: GameContext = scene.context
	scene.definition.initial_energy = 0.95
	scene.definition.energy_drain_per_second = 0.001
	_room(scene, Vector2i(6, 3), Vector2i(2, 2))
	var actor := context.spawn_creature(SPECIES, PORTAL)
	_advance(scene, STEP)
	var bed := context.beds.get_bed(actor.id)
	_check(bed != null and not bed.established and actor.rest_requested, "Healthy resident prioritizes making a home immediately after reserving space")
	_check(actor.position.distance_to(bed.center(context.grid)) > 0.08 and not context.beds.establish(actor), "Remote owner cannot establish a reserved bed")
	_check(_until(scene, func() -> bool: return actor.action == &"claiming_bed"), "Resident walks to its footprint before starting a local bed claim")
	_check(actor.position.distance_to(bed.center(context.grid)) <= 0.08 and not bed.established, "Two-by-two bed claim starts physically at its center while still pending")
	_advance(scene, 0.4)
	_check(not bed.established and actor.work_progress > 0.0 and actor.work_progress < 1.0, "Local claim takes visible work instead of instant creation")
	_check(_until(scene, func() -> bool: return bed.established), "A completed local claim establishes the personal bed")
	_check(actor.energy > scene.definition.sleep_threshold and not actor.rest_requested and actor.work_progress == 0.0, "Healthy resident finishes homemaking before returning to normal activity")
	_finish(scene, "Healthy local home claim")


func _test_claim_interruption_and_restart() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	scene.definition.initial_energy = 0.95
	scene.definition.energy_drain_per_second = 0.001
	_room(scene, Vector2i(6, 4))
	var actor := context.spawn_creature(SPECIES, Vector2i(6, 4))
	_advance(scene, 0.5)
	var bed := context.beds.get_bed(actor.id)
	_check(actor.action == &"claiming_bed" and actor.work_progress > 0.0 and not bed.established, "Local resident has an unfinished bed claim")
	actor.position = context.grid.cell_to_world(Vector2i(5, 4))
	_advance(scene, STEP)
	_check(actor.work_progress == 0.0 and not bed.established, "Moving away resets all local claim progress")
	_check(_until(scene, func() -> bool: return actor.action == &"claiming_bed"), "Resident must physically return before claiming again")
	_advance(scene, 0.4)
	_check(not bed.established, "Abandoned progress cannot shorten the next local claim")
	scene.feature.setup(context)
	_advance(scene, 0.4)
	_check(not bed.established and actor.work_progress < 0.5, "Reloading resident behavior retains pending capacity but restarts local claim work")
	context.rooms.remove([Vector2i(6, 4)])
	_advance(scene, 1.5)
	_check(context.beds.get_bed(actor.id) == null and not bed.established and actor.work_progress == 0.0, "Selling a footprint during claiming cannot create an orphan bed")
	_room(scene, Vector2i(7, 4))
	_check(_until(scene, func() -> bool:
		var replacement := context.beds.get_bed(actor.id)
		return replacement != null and replacement.established), "Resident makes a fresh local claim after a Lair is rebuilt")
	var replacement := context.beds.get_bed(actor.id)
	_check(replacement != bed and actor.position.distance_to(replacement.center(context.grid)) <= 0.08, "Replacement bed establishment uses the new footprint and the owner's real location")
	_finish(scene, "Interrupted local bed claim")


func _test_hybrid_claims_home_before_work() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var definition: CreatureDefinition = scene.definition
	definition.capabilities.assign([&"rest", &"excavate", &"haul"])
	definition.initial_energy = 0.95
	definition.energy_drain_per_second = 0.001
	definition.work_rate = 5.0
	_room(scene, Vector2i(6, 3))
	context.economy.configure_treasury({Vector2i(2, 3): 500})
	context.grid.set_tile(Vector2i(10, 4), DungeonGrid.Tile.GOLD)
	context.mark_excavation([Vector2i(10, 4)])
	var actor := context.spawn_creature(SPECIES, Vector2i(2, 4))
	var worker := WorkerFeature.new()
	worker.setup(context)
	_tick_hybrid(scene, worker)
	var bed := context.beds.get_bed(actor.id)
	var withheld_work := true
	var seen_claim := false
	for index in 600:
		if bed.established:
			break
		withheld_work = withheld_work and worker.job_board.job_for(actor.id) == null and actor.carried_gold == 0
		seen_claim = seen_claim or actor.action == &"claiming_bed"
		_tick_hybrid(scene, worker)
	_check(bed.established and seen_claim and withheld_work, "Healthy multi-talent creature travels and locally establishes its bed before any worker assignment")
	var worked := false
	for index in 600:
		_tick_hybrid(scene, worker)
		if actor.carried_gold > 0:
			worked = true
			break
	_check(worked and not actor.rest_requested, "Hybrid starts normal mining after its local home claim completes")
	worker.free()
	_finish(scene, "Hybrid homemaking priority")
