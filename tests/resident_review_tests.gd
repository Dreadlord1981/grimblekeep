extends SceneTree
## Independent small-map scenarios for space, interruption and mixed talents.

const Residents = preload("res://content/features/resident_feature.gd")
const Workers = preload("res://content/features/worker_feature.gd")
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_fragmented_space()
	_personal_ownership()
	_sleep_interruptions()
	_portal_reachability()
	_combined_talents()
	_local_establishment()
	_displaced_during_claim()
	_healthy_hybrid_home_first()
	for failure in _failures:
		push_error(failure)
	print("RESIDENT REVIEW RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(recruit_large: bool = false) -> GameContext:
	var grid := DungeonGrid.new(9, 9)
	for y in range(1, 8):
		for x in range(1, 8):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(1, 1), DungeonGrid.Tile.PORTAL)
	grid.set_tile(Vector2i(7, 7), DungeonGrid.Tile.GOLD)
	var small := CreatureDefinition.new()
	small.id = &"review.small"
	small.capabilities = [&"rest"]
	small.initial_energy = 0.1
	small.energy_drain_per_second = 0.03
	small.sleep_restore_per_second = 0.3
	small.move_speed = 5.0
	var large := CreatureDefinition.new()
	large.id = &"review.large"
	large.capabilities = [&"rest"]
	large.bed_size = Vector2i(2, 2)
	large.initial_energy = 0.1
	large.energy_drain_per_second = 0.03
	large.sleep_restore_per_second = 0.3
	large.move_speed = 5.0
	large.portal_population_limit = 1 if recruit_large else 0
	var hybrid := CreatureDefinition.new()
	hybrid.id = &"review.hybrid"
	hybrid.capabilities = [&"rest", &"haul", &"excavate"]
	hybrid.initial_energy = 0.1
	hybrid.energy_drain_per_second = 0.08
	hybrid.sleep_restore_per_second = 0.5
	hybrid.sleep_threshold = 0.2
	hybrid.wake_threshold = 0.8
	hybrid.move_speed = 8.0
	hybrid.work_rate = 3.0
	var room := RoomDefinition.new()
	room.id = &"review.rag_nest"
	room.tags = [&"lair"]
	var other := RoomDefinition.new()
	other.id = &"review.straw_nest"
	other.tags = [&"lair"]
	var vault := RoomDefinition.new()
	vault.id = &"review.gold_store"
	vault.gold_storage_per_tile = 500
	var module := ContentModule.new()
	module.id = &"review.resident_module"
	module.definitions = [small, large, hybrid, room, other, vault]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Independent resident definitions register")
	return GameContext.new(grid, registry)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _rectangle(first: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(first.y, first.y + size.y):
		for x in range(first.x, first.x + size.x):
			result.append(Vector2i(x, y))
	return result


func _fragmented_space() -> void:
	var context := _fixture()
	var fragmented: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(4, 3)]
	_check(context.rooms.place_initial(&"review.rag_nest", fragmented), "Five-tile U-shaped Lair exists")
	var definition := context.registry.get_creature(&"review.large")
	_check(context.beds.find_space(definition, Vector2i(1, 1)) == Vector2i(-1, -1), "Enough total area cannot substitute for a fitting contiguous 2x2 footprint")
	_check(context.beds.find_space(context.registry.get_creature(&"review.small"), Vector2i(1, 1)) != Vector2i(-1, -1), "Same fragmented room can fit a smaller species")
	context = _fixture()
	context.rooms.place_initial(&"review.rag_nest", [Vector2i(2, 2), Vector2i(2, 3)])
	context.rooms.place_initial(&"review.straw_nest", [Vector2i(3, 2), Vector2i(3, 3)])
	_check(not context.beds.can_place(Vector2i(2, 2), Vector2i(2, 2), &"lair"), "Same-tag adjacent room types cannot share one creature's footprint")
	_check(context.beds.find_space(context.registry.get_creature(&"review.large"), Vector2i(1, 1)) == Vector2i(-1, -1), "Arrival fitting query also rejects footprint spanning two room definitions")


func _personal_ownership() -> void:
	var context := _fixture()
	context.rooms.place_initial(&"review.rag_nest", _rectangle(Vector2i(2, 2), Vector2i(3, 2)))
	var large := context.spawn_creature(&"review.large", Vector2i(2, 2))
	var small_a := context.spawn_creature(&"review.small", Vector2i(3, 3))
	var small_b := context.spawn_creature(&"review.small", Vector2i(4, 3))
	var rejected := context.spawn_creature(&"review.small", Vector2i(5, 3))
	var large_bed := context.beds.reserve(large, context.registry.get_creature(large.definition_id))
	var bed_a := context.beds.reserve(small_a, context.registry.get_creature(small_a.definition_id))
	var bed_b := context.beds.reserve(small_b, context.registry.get_creature(small_b.definition_id))
	_check(large_bed != null and bed_a != null and bed_b != null, "A 2x2 resident and two 1x1 residents share a six-cell Lair")
	var covered: Dictionary[Vector2i, bool] = {}
	var overlaps := false
	for bed in context.beds.beds.values():
		for cell in bed.cells:
			overlaps = overlaps or covered.has(cell)
			covered[cell] = true
	_check(not overlaps and covered.size() == 6, "Independent footprint union proves no overlap or lost bed cells")
	_check(context.beds.reserve(rejected, context.registry.get_creature(rejected.definition_id)) == null, "A fourth resident cannot consume occupied capacity")
	context.rooms.place_initial(&"review.rag_nest", [Vector2i(6, 2)])
	context.rooms.place_initial(&"review.rag_nest", [Vector2i(5, 2)])
	_check(context.beds.get_bed(large.id) == large_bed and context.beds.get_bed(small_a.id) == bed_a, "Merging unrelated room extension preserves personal bed identities")
	context.rooms.remove([Vector2i(5, 2)])
	_check(context.beds.get_bed(large.id) == large_bed and context.beds.get_bed(small_b.id) == bed_b, "Splitting off unrelated room cells preserves valid personal reservations")
	context.despawn_creature(large.id)
	_check(context.beds.get_bed(large.id) == null, "Actor removal releases its personal footprint")
	_check(context.beds.reserve(rejected, context.registry.get_creature(rejected.definition_id)) != null, "Another resident can use newly released space")


func _sleep_until(feature: GameFeature, actor: CreatureState) -> bool:
	for tick in 300:
		feature.tick(0.1)
		if actor.action == &"sleeping":
			return true
	return false


func _sleep_interruptions() -> void:
	var context := _fixture()
	var cells := _rectangle(Vector2i(2, 2), Vector2i(2, 2))
	context.rooms.place_initial(&"review.rag_nest", cells)
	var actor := context.spawn_creature(&"review.large", Vector2i(2, 2))
	var feature := Residents.new()
	feature.setup(context)
	_check(_sleep_until(feature, actor), "Large resident reaches the center of its 2x2 bed and sleeps")
	var before := actor.energy
	context.rooms.remove([Vector2i(2, 2)])
	feature.tick(0.1)
	_check(actor.action != &"sleeping" and actor.energy <= before, "Selling one footprint cell immediately stops sleep restoration")
	_check(context.beds.get_bed(actor.id) == null, "A three-cell remnant cannot retain a 2x2 personal bed")
	context.rooms.place_initial(&"review.rag_nest", [Vector2i(2, 2)])
	_check(_sleep_until(feature, actor), "Rebuilding sold cell restores fitting bed and sensible sleep")
	before = actor.energy
	context.grid.set_tile(Vector2i(2, 2), DungeonGrid.Tile.ROCK)
	feature.tick(0.1)
	_check(actor.action != &"sleeping" and actor.energy <= before and context.beds.get_bed(actor.id) == null, "Terrain blocking a bed cell stops restoration and releases footprint")
	context.grid.set_tile(Vector2i(2, 2), DungeonGrid.Tile.FLOOR)
	context.rooms.place_initial(&"review.rag_nest", [Vector2i(2, 2)])
	_check(_sleep_until(feature, actor), "Unblocking and rebuilding recovers bed without recreating actor")
	_check(context.actors.size() == 1 and context.actors[0] == actor, "Interrupted rest preserves resident identity and population")
	feature.free()


func _portal_reachability() -> void:
	var context := _fixture(true)
	context.rooms.place_initial(&"review.rag_nest", _rectangle(Vector2i(2, 2), Vector2i(2, 2)))
	context.grid.set_tile(Vector2i(2, 1), DungeonGrid.Tile.ROCK)
	context.grid.set_tile(Vector2i(1, 2), DungeonGrid.Tile.ROCK)
	var feature := Residents.new()
	feature.setup(context)
	for tick in 40:
		feature.tick(0.1)
	_check(context.actors.is_empty(), "An isolated portal cannot recruit despite a free fitting Lair")
	context.grid.set_tile(Vector2i(2, 1), DungeonGrid.Tile.FLOOR)
	for tick in 25:
		feature.tick(0.1)
	_check(context.actors.size() == 1 and context.actors[0].definition_id == &"review.large", "Opening a real route enables data-defined species recruitment")
	for tick in 150:
		feature.tick(0.1)
	_check(context.actors.size() == 1 and context.beds.beds.size() == 1, "Species arrival limit prevents duplicate recruits and footprint reservations")
	feature.free()


func _combined_talents() -> void:
	var context := _fixture()
	context.rooms.place_initial(&"review.rag_nest", [Vector2i(2, 2)])
	context.rooms.place_initial(&"review.gold_store", [Vector2i(4, 2)])
	var actor := context.spawn_creature(&"review.hybrid", Vector2i(3, 3))
	actor.carried_gold = context.economy.mine(Vector2i(7, 7), 60)
	context.mark_excavation([Vector2i(7, 7)])
	var residents := Residents.new()
	var workers := Workers.new()
	residents.setup(context)
	workers.setup(context)
	var slept := false
	var mined := false
	var awake_again := false
	var rest_jobs_released := true
	var conserved := true
	for tick in 2400:
		residents.tick(0.1)
		workers.tick(0.1)
		slept = slept or actor.action == &"sleeping"
		mined = mined or actor.action == &"mining"
		awake_again = awake_again or (slept and not actor.rest_requested)
		if actor.rest_requested:
			rest_jobs_released = rest_jobs_released and workers.job_board.job_for(actor.id) == null
		conserved = conserved and context.economy.accounted_gold(context.actors) == context.economy.initial_gold
		if context.economy.stored_gold == 200 and slept and mined:
			break
	_check(slept and awake_again and mined, "One definition can rest, wake and perform excavation without species switches")
	_check(rest_jobs_released, "Needs priority releases every worker reservation while rest controls the actor")
	_check(context.economy.stored_gold == 200 and actor.carried_gold == 0, "Cargo retained through sleep and subsequent mining all reaches real Treasury")
	_check(conserved, "Mixed work/rest execution conserves finite gold on every timestep")
	workers.free()
	residents.free()


func _local_establishment() -> void:
	var context := _fixture()
	context.rooms.place_initial(&"review.rag_nest", _rectangle(Vector2i(2, 2), Vector2i(2, 2)))
	var actor := context.spawn_creature(&"review.large", Vector2i(6, 6))
	var definition := context.registry.get_creature(actor.definition_id)
	var bed := context.beds.reserve(actor, definition)
	_check(bed != null and not bed.established, "Remote allocation reserves capacity without establishing a bed")
	_check(not context.beds.establish(actor) and not bed.established, "A remote owner cannot establish a bed through the core API")
	actor.position = context.grid.cell_to_world(bed.anchor)
	_check(not context.beds.establish(actor), "Standing at a 2x2 footprint corner is insufficient to establish its center")
	var events: Array[int] = [0]
	context.beds.changed.connect(func() -> void: events[0] += 1)
	actor.position = bed.center(context.grid) + Vector3(0.081, 0, 0)
	_check(not context.beds.establish(actor) and events[0] == 0, "Just outside the center tolerance cannot form a bed or emit establishment")
	actor.position = bed.center(context.grid)
	_check(context.beds.establish(actor) and bed.established and events[0] == 1, "Physical arrival establishes one personal bed and publishes one change")
	_check(context.beds.establish(actor) and events[0] == 1, "Repeated establishment is idempotent and cannot duplicate the bed event")


func _displaced_during_claim() -> void:
	var context := _fixture()
	context.rooms.place_initial(&"review.rag_nest", _rectangle(Vector2i(2, 2), Vector2i(2, 2)))
	var actor := context.spawn_creature(&"review.large", Vector2i(2, 2))
	var bed := context.beds.reserve(actor, context.registry.get_creature(actor.definition_id))
	actor.position = bed.center(context.grid)
	var residents := Residents.new()
	residents.setup(context)
	residents.tick(0.4)
	_check(actor.action == &"claiming_bed" and actor.work_progress > 0.0 and not bed.established, "Local bed formation has an observable unfinished work phase")
	actor.position += Vector3(0.4, 0, 0)
	residents.tick(0.1)
	_check(not bed.established and is_zero_approx(actor.work_progress), "Moving away during the claim resets progress without forming a remote bed")
	actor.position = bed.center(context.grid)
	residents.tick(0.7)
	_check(not bed.established, "Returning cannot reuse partial work from an interrupted claim")
	residents.tick(0.31)
	_check(bed.established and context.beds.get_bed(actor.id) == bed, "A complete new local claim establishes the original reserved footprint")
	residents.free()


func _healthy_hybrid_home_first() -> void:
	var context := _fixture()
	var definition := context.registry.get_creature(&"review.hybrid")
	definition.initial_energy = 0.95
	definition.energy_drain_per_second = 0.0
	definition.bed_size = Vector2i(2, 2)
	context.rooms.place_initial(&"review.rag_nest", _rectangle(Vector2i(2, 2), Vector2i(2, 2)))
	context.rooms.place_initial(&"review.gold_store", [Vector2i(4, 2)])
	var actor := context.spawn_creature(definition.id, Vector2i(6, 6))
	actor.carried_gold = context.economy.mine(Vector2i(7, 7), 60)
	context.mark_excavation([Vector2i(7, 7)])
	var residents := Residents.new()
	var workers := Workers.new()
	residents.setup(context)
	workers.setup(context)
	var home_first := true
	var speed_valid := true
	var conserved := true
	var established := false
	var claim_locations: Array[Vector3] = []
	var bed_store: WeakRef = weakref(context.beds)
	context.beds.changed.connect(func() -> void:
		var current: BedState = bed_store.get_ref().get_bed(actor.id)
		if current != null and current.established:
			claim_locations.append(actor.position))
	for tick in 400:
		var before := actor.position
		residents.tick(0.1)
		workers.tick(0.1)
		var bed := context.beds.get_bed(actor.id)
		established = bed != null and bed.established
		if not established:
			home_first = home_first and actor.rest_requested and workers.job_board.job_for(actor.id) == null and actor.carried_gold == 60
		speed_valid = speed_valid and actor.position.distance_to(before) <= definition.move_speed * 0.1 + 0.001
		conserved = conserved and context.economy.accounted_gold(context.actors) == context.economy.initial_gold
		if established and context.economy.stored_gold >= 60:
			break
	_check(home_first, "A healthy multi-talent resident makes its home before accepting work or dropping its cargo")
	_check(established and claim_locations.size() == 1 and claim_locations[0].distance_to(context.beds.get_bed(actor.id).center(context.grid)) <= DungeonBeds.CLAIM_DISTANCE, "The hybrid establishes its home only at its physical center, once")
	_check(speed_valid, "Home-making and work never move the same resident twice in one timestep")
	_check(context.economy.stored_gold >= 60 and conserved, "Worker resumes physical delivery after home formation with conserved cargo")
	workers.free()
	residents.free()
