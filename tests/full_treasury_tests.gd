extends SceneTree
## Mineral work waits for reachable physical storage; stone excavation stays usable.

const WorkerFeature = preload("res://content/features/worker_feature.gd")
const ResidentFeature = preload("res://content/features/resident_feature.gd")
const STEP := 1.0 / 30.0
const TARGET := Vector2i(6, 3)
const TREASURY := Vector2i(1, 3)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_natural_full_storage(DungeonGrid.Tile.GOLD)
	_test_natural_full_storage(DungeonGrid.Tile.GEM)
	_test_interrupted_strike(DungeonGrid.Tile.GOLD)
	_test_interrupted_strike(DungeonGrid.Tile.GEM)
	_test_stone_keeps_working()
	_test_resume_after_spending()
	_test_resume_after_expansion()
	_test_unreachable_storage()
	_test_reserved_storage_is_not_full()
	_test_full_storage_preserves_local_rest()
	for failure in _failures:
		push_error(failure)
	print("FULL TREASURY RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(kind: int = DungeonGrid.Tile.GOLD, capacity: int = 60) -> Dictionary:
	var grid := DungeonGrid.new(10, 8)
	for y in range(1, 7):
		for x in range(1, 6):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(TARGET, kind)
	var definition := CreatureDefinition.new()
	definition.id = &"full_treasury.worker"
	definition.capabilities = [&"excavate", &"haul"]
	definition.move_speed = 8.0
	definition.work_rate = 4.0
	var module := ContentModule.new()
	module.id = &"full_treasury"
	var lair := RoomDefinition.new()
	lair.id = &"full_treasury.lair"
	lair.tags = [&"lair"]
	module.definitions = [definition, lair]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Storage gate fixture registers its worker definition")
	var context := GameContext.new(grid, registry)
	context.economy.configure_treasury({TREASURY: capacity})
	context.spawn_creature(definition.id, Vector2i(5, 3))
	context.mark_excavation([TARGET])
	var feature := WorkerFeature.new()
	feature.setup(context)
	return {"context": context, "definition": definition, "feature": feature, "conserved": true}


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.feature.tick(STEP)
		var context: GameContext = scene.context
		if context.economy.accounted_gold(context.actors) != context.economy.initial_gold + context.economy.gem_gold_created:
			scene.conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 25.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _finish(scene: Dictionary, label: String) -> void:
	_check(scene.conserved, "%s preserves unmined, carried, loose, stored and spent gold" % label)
	scene.feature.free()


func _extracted(scene: Dictionary) -> int:
	var economy: GoldEconomy = scene.context.economy
	return economy.initial_gold - economy.remaining_gold.get(TARGET, 0) + economy.gem_gold_created


func _fill_with_fixture_stock(scene: Dictionary, amount: int) -> void:
	# External initial stock is a fixture source, not a production game mechanic.
	scene.context.economy.initial_gold += amount
	_check(scene.context.economy.deposit(TREASURY, amount), "Fixture physically fills its Treasury tile")


func _test_natural_full_storage(kind: int) -> void:
	var scene := _fixture(kind)
	var context: GameContext = scene.context
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 60), "Miner fills a finite-capacity Treasury through normal hauling")
	_advance(scene, 1.0)
	var extracted := _extracted(scene)
	_advance(scene, 8.0)
	_check(extracted == 60 and _extracted(scene) == extracted, "Full Treasury stops further finite/gem extraction")
	_check(context.excavation_marks.has(TARGET) and context.grid.get_tile(TARGET) == kind, "Storage pause preserves the mineral terrain and its mining order")
	_check(scene.feature.job_board.active_job_count() == 0 and context.actors[0].carried_gold == 0, "Full-storage miners release reservations and stop collecting cargo")
	_check("Treasury space" in context.actors[0].job_label, "Paused miner explains that reachable Treasury space is needed")
	_finish(scene, "Natural finite/gem storage fill")


func _test_interrupted_strike(kind: int) -> void:
	var scene := _fixture(kind, 20)
	var context: GameContext = scene.context
	var actor := context.actors[0]
	_check(_until(scene, func() -> bool: return actor.action == &"mining" and actor.work_progress > 0.1), "Miner begins a real strike before another delivery fills storage")
	_fill_with_fixture_stock(scene, 20)
	var remaining: int = context.economy.remaining_gold.get(TARGET, 0)
	var generated := context.economy.gem_gold_created
	_advance(scene, 3.0)
	_check(context.economy.remaining_gold.get(TARGET, 0) == remaining and context.economy.gem_gold_created == generated, "A Treasury filled mid-strike cancels before any mineral award")
	_check(actor.work_progress == 0.0 and actor.carried_gold == 0 and scene.feature.job_board.active_job_count() == 0, "Interrupted strike clears work progress and reservations without producing cargo")
	_check(context.excavation_marks.has(TARGET), "Interrupted strike retains its designation for later resumption")
	_finish(scene, "In-progress mineral interruption")


func _test_stone_keeps_working() -> void:
	var scene := _fixture(DungeonGrid.Tile.GOLD, 20)
	var context: GameContext = scene.context
	_fill_with_fixture_stock(scene, 20)
	context.grid.set_tile(Vector2i(6, 4), DungeonGrid.Tile.GEM)
	context.mark_excavation([Vector2i(6, 4), Vector2i(6, 2), Vector2i(7, 2)], GameContext.MarkOperation.ADD)
	_check(_until(scene, func() -> bool: return context.grid.get_tile(Vector2i(7, 2)) == DungeonGrid.Tile.FLOOR), "Stone excavation and buried stone chains continue with a full Treasury")
	_check(context.economy.remaining_gold.get(TARGET, 0) == 200 and context.economy.gem_gold_created == 0, "Stone work does not accidentally extract blocked gold or gems")
	_check(context.excavation_marks.has(TARGET) and context.excavation_marks.has(Vector2i(6, 4)), "Blocked mineral orders remain marked while stone jobs complete")
	_finish(scene, "Stone excavation during storage pause")


func _test_resume_after_spending() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 60), "Spending scenario starts with naturally full storage")
	var remaining: int = context.economy.remaining_gold[TARGET]
	_check(context.economy.spend(20), "Spending stored gold frees physical storage capacity")
	_check(_until(scene, func() -> bool: return context.economy.remaining_gold.get(TARGET, 0) < remaining, 3.0), "Retained mining order resumes after spending without a new mark")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 60), "Resumed cargo refills the available space")
	_advance(scene, 1.0)
	var extracted := _extracted(scene)
	_advance(scene, 5.0)
	_check(_extracted(scene) == extracted and context.economy.spent_gold == 20, "Mining pauses again once newly freed capacity is filled")
	_finish(scene, "Resume after spending")


func _test_resume_after_expansion() -> void:
	var scene := _fixture(DungeonGrid.Tile.GEM)
	var context: GameContext = scene.context
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 60), "Expansion scenario starts with a full Treasury")
	var created := context.economy.gem_gold_created
	context.economy.configure_treasury({TREASURY: 60, Vector2i(3, 5): 60})
	_check(_until(scene, func() -> bool: return context.economy.gem_gold_created > created, 3.0), "Adding reachable Treasury capacity resumes an existing gem order")
	_check(_until(scene, func() -> bool: return context.economy.stored_gold == 120), "New Treasury tile receives resumed physical deliveries")
	_advance(scene, 1.0)
	created = context.economy.gem_gold_created
	_advance(scene, 5.0)
	_check(context.economy.gem_gold_created == created, "Expanded Treasury filling pauses renewable gem production again")
	_finish(scene, "Resume after Treasury expansion")


func _test_unreachable_storage() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	for y in range(1, 7):
		context.grid.set_tile(Vector2i(3, y), DungeonGrid.Tile.ROCK)
	_advance(scene, 3.0)
	_check(context.economy.remaining_gold[TARGET] == 200 and scene.feature.job_board.active_job_count() == 0, "Empty but unreachable storage cannot authorize new mineral work")
	context.grid.set_tile(Vector2i(3, 3), DungeonGrid.Tile.FLOOR)
	_check(_until(scene, func() -> bool: return context.economy.remaining_gold[TARGET] < 200, 3.0), "Opening the Treasury route resumes retained mining orders")
	_finish(scene, "Unreachable Treasury")


func _test_reserved_storage_is_not_full() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var carrier := context.spawn_creature(scene.definition.id, Vector2i(2, 3))
	carrier.carried_gold = 20
	context.economy.initial_gold += 20
	var board: WorkerJobBoard = scene.feature.job_board
	var delivery := board.assign(carrier, scene.definition)
	var mining := board.assign(context.actors[0], scene.definition)
	_check(delivery != null and delivery.kind == &"deposit" and mining != null and mining.kind == &"excavate", "Reserved delivery positions do not make available Treasury capacity appear full")
	board.release(carrier.id)
	board.release(context.actors[0].id)
	_finish(scene, "Storage position reservation")


func _test_full_storage_preserves_local_rest() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var definition: CreatureDefinition = scene.definition
	definition.capabilities.assign([&"rest", &"excavate", &"haul"])
	definition.energy_drain_per_second = 0.01
	definition.sleep_restore_per_second = 1.0
	context.rooms.place_initial(&"full_treasury.lair", [Vector2i(3, 5)])
	context.economy.configure_treasury({TREASURY: 60})
	_fill_with_fixture_stock(scene, 60)
	var actor := context.actors[0]
	actor.energy = 0.95
	var resident := ResidentFeature.new()
	resident.setup(context)
	var established := false
	var claimed_locally := false
	for index in 600:
		resident.tick(STEP)
		_advance(scene, STEP)
		claimed_locally = claimed_locally or actor.action == &"claiming_bed"
		var bed := context.beds.get_bed(actor.id)
		if bed != null and bed.established:
			established = true
			break
	_check(established and claimed_locally and context.economy.remaining_gold[TARGET] == 200, "Full storage leaves a hybrid free to walk home and establish its bed locally")
	actor.energy = 0.1
	var slept := false
	var woke := false
	for index in 600:
		resident.tick(STEP)
		_advance(scene, STEP)
		slept = slept or actor.action == &"sleeping"
		if slept and not actor.rest_requested:
			woke = true
			break
	_check(slept and woke and context.economy.remaining_gold[TARGET] == 200, "Tired hybrid sleeps and wakes without bypassing the full-storage mineral gate")
	_check(scene.feature.job_board.active_job_count() == 0 and actor.carried_gold == 0, "Rest priority and full Treasury waiting leave no mining jobs or cargo")
	resident.free()
	_finish(scene, "Full-storage hybrid rest")
