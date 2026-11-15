extends SceneTree
## Physical meals, appetite/diet extensions, interruptions and competing needs.

const ResidentFeature = preload("res://content/features/resident_feature.gd")
const FoodFeature = preload("res://content/features/food_feature.gd")
const WorkerFeature = preload("res://content/features/worker_feature.gd")
const STEP := 1.0 / 30.0
const SPECIES := &"feeding.eater"
const RAW := &"feeding.raw"
const COOKED := &"feeding.cooked"
const RAW_ROOM := &"feeding.pen"
const COOKED_ROOM := &"feeding.output"
const LAIR := &"feeding.lair"
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_local_meals_and_food_only_actor()
	_test_appetite_and_diet()
	_test_competing_eaters()
	_test_source_sale_and_blocking()
	_test_disappearing_meal_and_actor_cleanup()
	_test_food_navigation()
	_test_home_sleep_and_food_priorities()
	_test_missing_food_and_repeated_cycles()
	_test_hybrid_work_interrupt()
	_test_rest_only_compatibility()
	_test_reserved_pig_returns_before_eating()
	_test_displaced_pig_restarts_eating()
	for failure in _failures:
		push_error(failure)
	print("FEEDING RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(capabilities: Array[StringName] = [&"eat"], count: int = 1) -> Dictionary:
	var grid := DungeonGrid.new(11, 9)
	for y in range(1, 8):
		for x in range(1, 9):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	var eater := CreatureDefinition.new()
	eater.id = SPECIES
	eater.capabilities = capabilities
	eater.initial_satiety = 0.2
	eater.hunger_drain_per_second = 0.0
	eater.eating_seconds = 0.5
	eater.move_speed = 6.0
	var raw := FoodDefinition.new()
	raw.id = RAW
	raw.tags = [&"raw", &"meat"]
	raw.nutrition_per_unit = 0.6
	var cooked := FoodDefinition.new()
	cooked.id = COOKED
	cooked.tags = [&"cooked", &"meat"]
	cooked.nutrition_per_unit = 1.0
	var pen := RoomDefinition.new()
	pen.id = RAW_ROOM
	pen.food_type = RAW
	pen.food_capacity_per_tile = 20
	pen.food_production_seconds = 0.3
	var output := RoomDefinition.new()
	output.id = COOKED_ROOM
	output.food_type = COOKED
	output.food_capacity_per_tile = 20
	var lair := RoomDefinition.new()
	lair.id = LAIR
	lair.tags = [&"lair"]
	var module := ContentModule.new()
	module.id = &"feeding.tests"
	module.definitions = [eater, raw, cooked, pen, output, lair]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Two foods and producer/output extensions register through shared content contracts")
	var context := GameContext.new(grid, registry)
	for index in count:
		context.spawn_creature(SPECIES, Vector2i(2, 3 + index))
	var resident := ResidentFeature.new()
	resident.setup(context)
	var production := FoodFeature.new()
	production.setup(context)
	return {"context": context, "definition": eater, "feature": resident, "production": production, "automatic": false, "worker": null, "conserved": true, "gold_conserved": true}


func _seed(scene: Dictionary, cell: Vector2i, food_id: StringName = RAW, units: int = 4) -> void:
	var context: GameContext = scene.context
	_check(context.rooms.place_initial(RAW_ROOM if food_id == RAW else COOKED_ROOM, [cell]), "Fixture places a real food source/output tile")
	_check(context.food.produce(cell, food_id, units) == units, "Fixture produces accounted physical food through source capacity")


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		if scene.automatic:
			scene.production.tick(STEP)
		scene.feature.tick(STEP)
		if scene.worker != null:
			scene.worker.tick(STEP)
		var context: GameContext = scene.context
		if context.food.accounted_units() != context.food.produced_units:
			scene.conserved = false
		if context.economy.accounted_gold(context.actors) != context.economy.initial_gold + context.economy.gem_gold_created:
			scene.gold_conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 25.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _finish(scene: Dictionary, label: String) -> void:
	_check(scene.conserved and scene.context.food.accounted_units() == scene.context.food.produced_units, "%s conserves produced, physical and consumed food" % label)
	_check(scene.gold_conserved, "%s preserves unrelated physical gold" % label)
	scene.feature.free()
	scene.production.free()
	if scene.worker != null:
		scene.worker.free()


func _established_home(scene: Dictionary, cell: Vector2i) -> void:
	var context: GameContext = scene.context
	context.rooms.place_initial(LAIR, [cell])
	var actor := context.actors[0]
	var previous := actor.position
	var bed := context.beds.reserve(actor, scene.definition)
	actor.position = bed.center(context.grid)
	_check(context.beds.establish(actor), "Rest fixture establishes its home with the owner physically at its center")
	actor.position = previous


func _test_local_meals_and_food_only_actor() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_seed(scene, Vector2i(6, 3), RAW, 3)
	var actor := context.actors[0]
	var energy := actor.energy
	_advance(scene, STEP)
	_check(context.food.get_reservation(actor.id) != null and actor.food_requested, "Hungry food-only creature reserves a reachable meal without requiring rest capability")
	_advance(scene, 0.2)
	_check(context.food.consumed_units == 0 and context.food.get_stock(Vector2i(6, 3), RAW) == 3, "Walking to food never remotely debits the visible stock")
	_check(_until(scene, func() -> bool: return actor.action == &"eating"), "Creature physically reaches food before beginning local eating")
	_check(actor.position.distance_to(context.grid.cell_to_world(Vector2i(6, 3))) <= FoodEconomy.EAT_DISTANCE and context.food.consumed_units == 0, "Timed eating begins at the food cell while stock remains present")
	_check(_until(scene, func() -> bool: return context.food.consumed_units == 1), "Completed local eating consumes exactly one reserved unit")
	_check(is_equal_approx(actor.satiety, 0.8), "Raw-food nutrition restores satiety once per completed meal")
	_check(_until(scene, func() -> bool: return actor.satiety >= 0.9), "Creature eats another unit when one meal is insufficient to become sated")
	_advance(scene, 2.0)
	_check(context.food.consumed_units == 2 and not actor.food_requested and context.food.reservations.is_empty(), "Sated creature stops consuming and releases all meal state")
	_check(actor.energy == energy and context.beds.beds.is_empty(), "Food-only behavior does not drain energy or create a bed")
	_finish(scene, "Local physical meals")


func _test_appetite_and_diet() -> void:
	var large := _fixture()
	large.definition.food_per_meal = 2
	_seed(large, Vector2i(2, 3), RAW, 5)
	_check(_until(large, func() -> bool: return large.context.food.consumed_units == 1), "Larger-appetite species completes a normal local meal")
	_check(is_equal_approx(large.context.actors[0].satiety, 0.5), "Species appetite divides per-unit nutrition rather than duplicating food awards")
	_check(_until(large, func() -> bool: return large.context.actors[0].satiety >= 0.9), "Larger-appetite species takes the required additional physical units")
	_check(large.context.food.consumed_units == 3, "Larger appetite changes unit consumption through data")
	_finish(large, "Species appetite")
	var diet := _fixture()
	diet.definition.food_tags.assign([&"cooked"])
	_seed(diet, Vector2i(3, 3), RAW, 2)
	_seed(diet, Vector2i(7, 3), COOKED, 2)
	_advance(diet, STEP)
	var reservation: FoodReservation = diet.context.food.get_reservation(diet.context.actors[0].id)
	_check(reservation != null and reservation.food_id == COOKED, "Diet tags reject nearer incompatible raw food and reserve a compatible meal")
	_check(_until(diet, func() -> bool: return diet.context.food.consumed_units == 1), "Second food definition works through the shared eating behavior")
	_check(diet.context.actors[0].satiety == 1.0 and diet.context.food.get_stock(Vector2i(3, 3), RAW) == 2, "Different nutrition fills satiety without consuming rejected food")
	_finish(diet, "Diet and prepared-output extension")


func _test_competing_eaters() -> void:
	var scene := _fixture([&"eat"], 2)
	var context: GameContext = scene.context
	_seed(scene, Vector2i(5, 3), RAW, 4)
	_advance(scene, STEP)
	_check(context.food.reservations.size() == 1, "Competing eaters cannot reserve the same physical feeding position")
	_check(_until(scene, func() -> bool: return context.actors[0].satiety >= 0.9 and context.actors[1].satiety >= 0.9), "Waiting eater can reserve food after the first eater finishes")
	_check(context.food.consumed_units == 4 and context.food.reservations.is_empty(), "Competition consumes each physical unit exactly once")
	_finish(scene, "Meal competition")


func _test_source_sale_and_blocking() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var cell := Vector2i(6, 3)
	_seed(scene, cell, RAW, 3)
	_advance(scene, STEP)
	context.rooms.remove([cell])
	_check(context.food.get_reservation(context.actors[0].id) != null and context.food.get_stock(cell, RAW) == 3, "Selling a food room preserves physical loose food and its valid meal reservation")
	_check(_until(scene, func() -> bool: return context.food.consumed_units > 0), "Existing raw food remains edible after its producing room is sold")
	_finish(scene, "Sold producer food")
	var blocked := _fixture()
	_seed(blocked, cell, RAW, 3)
	_advance(blocked, STEP)
	blocked.context.grid.set_tile(cell, DungeonGrid.Tile.BEDROCK)
	_advance(blocked, 2.0)
	_check(blocked.context.food.reservations.is_empty() and blocked.context.food.consumed_units == 0 and not blocked.context.actors[0].food_requested, "Blocking a meal tile cancels feeding without a stale debit or need lock")
	_check(blocked.context.food.get_stock(cell, RAW) == 3, "Inaccessible food remains accounted in physical stock")
	blocked.context.grid.set_tile(cell, DungeonGrid.Tile.FLOOR)
	_check(_until(blocked, func() -> bool: return blocked.context.food.consumed_units > 0), "Reopening a food tile allows bounded retries to resume feeding")
	_finish(blocked, "Blocked meal tile")


func _test_disappearing_meal_and_actor_cleanup() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_seed(scene, Vector2i(2, 3), RAW, 1)
	_check(_until(scene, func() -> bool: return context.actors[0].action == &"eating"), "Disappearance fixture starts a real local eating action")
	_check(context.food.consume(context.actors[0]) > 0.0, "An external authoritative transfer removes the reserved physical unit")
	_advance(scene, 1.0)
	_check(context.food.consumed_units == 1 and context.actors[0].satiety == 0.2 and context.food.reservations.is_empty(), "Disappearing food cannot grant a second debit or nutrition award")
	_finish(scene, "Meal disappearance")
	var removed := _fixture()
	_seed(removed, Vector2i(6, 3), RAW, 2)
	_advance(removed, STEP)
	var actor: CreatureState = removed.context.actors[0]
	removed.context.despawn_creature(actor.id)
	_advance(removed, STEP)
	_check(removed.context.food.reservations.is_empty() and not removed.feature.behaviors.has(actor.id), "Actor removal releases meal ownership and need behavior")
	_finish(removed, "Removed eater")


func _test_food_navigation() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_seed(scene, Vector2i(7, 6), RAW, 2)
	_advance(scene, STEP)
	var behavior: ResidentBehavior = scene.feature.behaviors[context.actors[0].id]
	var feeding: ResidentFeeding = behavior.get("_feeding")
	var nav: ResidentNavigation = feeding.get("_navigation")
	var flank := Vector2i(-1, -1)
	for index in range(1, nav.path.size()):
		var offset := nav.path[index] - nav.path[index - 1]
		if offset.x != 0 and offset.y != 0:
			flank = nav.path[index - 1] + Vector2i(offset.x, 0)
			break
	_check(flank != Vector2i(-1, -1), "Food route fixture includes a diagonal edge")
	context.grid.set_tile(flank, DungeonGrid.Tile.BEDROCK)
	var before := context.actors[0].position
	_advance(scene, STEP)
	var valid := true
	for index in range(1, nav.path.size()):
		valid = valid and GridPathfinder.can_step(context.grid, nav.path[index - 1], nav.path[index])
	_check(valid and context.actors[0].position.distance_to(before) <= scene.definition.move_speed * STEP + 0.001, "Food travel replans strict diagonal edges without teleporting")
	_check(_until(scene, func() -> bool: return context.food.consumed_units > 0), "Eater follows the alternate safe route to food")
	_finish(scene, "Food route changes")


func _test_home_sleep_and_food_priorities() -> void:
	var scene := _fixture([&"rest", &"eat"])
	var context: GameContext = scene.context
	_seed(scene, Vector2i(2, 3), RAW, 5)
	context.rooms.place_initial(LAIR, [Vector2i(6, 3)])
	var actor := context.actors[0]
	actor.energy = 0.95
	_check(_until(scene, func() -> bool:
		var bed := context.beds.get_bed(actor.id)
		return bed != null and bed.established), "Hungry arrival still physically establishes its home first")
	_check(context.food.consumed_units == 0, "Homemaking does not remotely consume the nearby food it passes")
	_check(_until(scene, func() -> bool: return actor.satiety >= 0.9), "Resident feeds after completing its local home claim")
	actor.energy = 0.1
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Fed resident can begin its normal rest cycle")
	actor.satiety = 0.05
	_check(_until(scene, func() -> bool: return actor.action == &"eating"), "Critical hunger interrupts sleep only when reachable food can be reserved")
	_check(_until(scene, func() -> bool: return actor.satiety >= 0.9), "Interrupted sleeper finishes feeding rather than oscillating between needs")
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "After critical hunger recovers, resident returns to its unfinished rest need")
	_finish(scene, "Home, hunger and rest priority")


func _test_missing_food_and_repeated_cycles() -> void:
	var scene := _fixture([&"rest", &"eat"])
	var context: GameContext = scene.context
	_established_home(scene, Vector2i(3, 4))
	var actor := context.actors[0]
	actor.energy = 0.1
	actor.satiety = 0.0
	_check(_until(scene, func() -> bool: return actor.action == &"sleeping"), "Critical hunger without food does not prevent an exhausted resident from resting")
	_advance(scene, 2.0)
	_check(actor.action == &"sleeping" and actor.energy > 0.1 and not actor.food_requested, "Unavailable food does not repeatedly wake sleepers or leave a food movement lock")
	_seed(scene, Vector2i(6, 4), RAW, 2)
	scene.automatic = true
	scene.definition.energy_drain_per_second = 0.12
	scene.definition.sleep_restore_per_second = 0.8
	scene.definition.hunger_drain_per_second = 0.08
	var sleep_entries := 0
	var previous_sleep := false
	for index in 1800:
		_advance(scene, STEP)
		var sleeping := actor.action == &"sleeping"
		if sleeping and not previous_sleep:
			sleep_entries += 1
		previous_sleep = sleeping
	_check(context.food.consumed_units >= 4 and sleep_entries >= 2, "Actual production supports repeated eating and sleeping cycles after food is restored")
	_check(actor.satiety >= 0.0 and actor.satiety <= 1.0 and actor.energy >= 0.0 and actor.energy <= 1.0, "Repeated need recovery keeps both meters bounded")
	_finish(scene, "Missing food and repeated needs")


func _test_hybrid_work_interrupt() -> void:
	var scene := _fixture([&"eat", &"excavate", &"haul"])
	var context: GameContext = scene.context
	_seed(scene, Vector2i(3, 5), RAW, 4)
	context.economy.configure_treasury({Vector2i(1, 3): 500})
	context.grid.set_tile(Vector2i(9, 3), DungeonGrid.Tile.GOLD)
	context.mark_excavation([Vector2i(9, 3)])
	var actor := context.actors[0]
	actor.position = context.grid.cell_to_world(Vector2i(8, 3))
	actor.satiety = 0.95
	scene.definition.work_rate = 4.0
	scene.worker = WorkerFeature.new()
	scene.worker.setup(context)
	_check(_until(scene, func() -> bool: return actor.carried_gold > 0), "Healthy hungry-capable worker performs normal mining")
	var cargo := actor.carried_gold
	actor.satiety = 0.1
	var before := actor.position
	_advance(scene, STEP)
	_check(actor.food_requested and scene.worker.job_board.job_for(actor.id) == null and actor.carried_gold == cargo, "Hunger interrupts worker reservations while preserving carried gold")
	_check(actor.position.distance_to(before) <= scene.definition.move_speed * STEP + 0.001, "Food and work features cannot move the same actor twice per tick")
	_check(_until(scene, func() -> bool: return actor.satiety >= 0.9 and context.economy.stored_gold > 0), "Sated worker resumes delivery of its retained physical cargo")
	_finish(scene, "Hybrid food and work arbitration")


func _test_rest_only_compatibility() -> void:
	var scene := _fixture([&"rest"])
	_seed(scene, Vector2i(2, 3), RAW, 4)
	var actor: CreatureState = scene.context.actors[0]
	actor.satiety = 0.1
	scene.definition.hunger_drain_per_second = 1.0
	_advance(scene, 5.0)
	_check(actor.satiety == 0.1 and scene.context.food.consumed_units == 0 and not actor.food_requested, "Existing rest-only profiles never acquire hunger or consume food implicitly")
	_finish(scene, "Rest-only compatibility")


func _test_reserved_pig_returns_before_eating() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	context.registry.get_food(RAW).wanders = true
	var service := Vector2i(6, 3)
	var pen := context.registry.get_room(RAW_ROOM)
	pen.food_tiles_per_unit = 3
	pen.food_minimum_size = Vector2i(3, 1)
	_check(context.rooms.place_initial(RAW_ROOM, [service, Vector2i(7, 3), Vector2i(8, 3)]), "Returning-pig fixture builds a fitting three-tile pooled pen")
	_check(context.food.produce(service, RAW, 1) == 1, "Three-tile pen produces one accounted roaming pig")
	var actor := context.actors[0]
	actor.position = context.grid.cell_to_world(service)
	scene.definition.eating_seconds = 1.5
	_advance(scene, STEP)
	var reservation := context.food.get_reservation(actor.id)
	var unit: FoodUnitState = context.food.units[reservation.unit_id]
	unit.position = context.grid.cell_to_world(Vector2i(7, 3))
	_advance(scene, 0.5)
	_check(actor.action == &"waiting_for_meal" and actor.food_requested and actor.work_progress == 0.0, "Eater waits at its reserved service cell while the exact pig is elsewhere in the pen")
	_check(context.food.get_reservation(actor.id) == reservation and context.food.consume(actor) == 0.0, "Roaming pig keeps its exclusive reservation and cannot be consumed remotely")
	_check(context.food.consumed_units == 0 and actor.satiety == 0.2, "Waiting for the pig grants neither early nutrition nor food debit")
	var service_position := actor.position
	scene.automatic = true
	_check(_until(scene, func() -> bool: return actor.action == &"eating"), "Authoritative food movement returns the reserved pig before eating begins")
	_check(context.food.meal_ready(reservation) and actor.position == service_position and context.food.consumed_units == 0, "Only the pig moves to the service position; food remains physical at the start of eating")
	_advance(scene, 0.4)
	_check(context.food.consumed_units == 0 and actor.work_progress > 0.0 and actor.work_progress < 1.0, "The full configured eating duration starts after the pig arrives")
	_check(_until(scene, func() -> bool: return context.food.consumed_units == 1), "Arrived pig is consumed once after local timed eating completes")
	_check(not context.food.units.has(reservation.unit_id) and is_equal_approx(actor.satiety, 0.8), "Consumption removes the exact reserved unit and grants its nutrition once")
	_finish(scene, "Roaming pig meal return")


func _test_displaced_pig_restarts_eating() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var service := Vector2i(2, 3)
	_seed(scene, service, RAW, 1)
	context.rooms.place_initial(RAW_ROOM, [Vector2i(3, 3)])
	scene.definition.eating_seconds = 1.5
	var actor := context.actors[0]
	_advance(scene, 0.5)
	var reservation := context.food.get_reservation(actor.id)
	var unit: FoodUnitState = context.food.units[reservation.unit_id]
	_check(actor.action == &"eating" and actor.work_progress > 0.0, "Pig displacement fixture begins a partially completed eating action")
	unit.position = context.grid.cell_to_world(Vector2i(3, 3))
	_advance(scene, 1.5)
	_check(actor.action == &"waiting_for_meal" and actor.work_progress == 0.0 and context.food.consumed_units == 0, "Pig displacement resets eating progress without canceling its reservation or consuming it")
	_check(context.food.get_reservation(actor.id) == reservation and actor.satiety == 0.2, "Displaced meal remains exclusively reserved and supplies no premature nutrition")
	unit.position = context.grid.cell_to_world(service)
	_advance(scene, 0.5)
	_check(context.food.consumed_units == 0 and actor.work_progress > 0.0 and actor.work_progress < 0.5, "Returned pig requires a fresh full eating action rather than saved partial progress")
	_check(_until(scene, func() -> bool: return context.food.consumed_units == 1), "Restarted local eating eventually consumes the returned unit once")
	_finish(scene, "Pig displacement during eating")
