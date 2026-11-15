extends SceneTree
## Independent FIFO custody stress, removal and simulation conservation checks.

const Workers = preload("res://content/features/worker_feature.gd")
const Residents = preload("res://content/features/resident_feature.gd")
const STEP := 1.0 / 30.0
const SPECIES := &"queue_review.hybrid"
const FOOD := &"queue_review.food"
const PEN := &"queue_review.pen"
const BANK := Vector2i(2, 2)
const PILE := Vector2i(4, 4)
const GOLD := Vector2i(9, 4)
const GEM := Vector2i(9, 5)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_mixed_batches_and_overflow()
	_many_entries_reload_and_resume()
	_removed_entries_keep_the_order()
	_each_front_keeps_its_origin()
	for failure in _failures:
		push_error(failure)
	print("KEEPER QUEUE REVIEW: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture() -> Dictionary:
	var grid := DungeonGrid.new(12, 9)
	for y in range(1, 7):
		for x in range(1, 9):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(1, 3), DungeonGrid.Tile.HEART)
	grid.set_tile(Vector2i(10, 7), DungeonGrid.Tile.FLOOR)
	grid.set_tile(GOLD, DungeonGrid.Tile.GOLD)
	grid.set_tile(GEM, DungeonGrid.Tile.GEM)
	var species := CreatureDefinition.new()
	species.id = SPECIES
	species.capabilities = [&"haul", &"eat"]
	species.move_speed = 6.0
	species.initial_satiety = 0.2
	species.hunger_drain_per_second = 0.0
	species.eating_seconds = 0.3
	var pen := RoomDefinition.new()
	pen.id = PEN
	pen.food_type = FOOD
	pen.food_capacity_per_tile = 4
	var food := FoodDefinition.new()
	food.id = FOOD
	food.nutrition_per_unit = 1.0
	var module := ContentModule.new()
	module.id = &"queue_review"
	module.definitions = [species, pen, food]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Queue fixture registers independent worker/eater and food definitions")
	var context := GameContext.new(grid, registry)
	context.economy.configure_protected_storage({BANK: 2000})
	var workers := Workers.new()
	workers.setup(context)
	var residents := Residents.new()
	residents.setup(context)
	return {"context": context, "workers": workers, "residents": residents, "conserved": true}


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _conserved(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created and context.food.accounted_units() == context.food.produced_units


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.residents.tick(STEP)
		scene.workers.tick(STEP)
		scene.context.simulation_ticked.emit(STEP)
		scene.conserved = scene.conserved and _conserved(scene.context)


func _until(scene: Dictionary, condition: Callable, seconds: float = 30.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _finish(scene: Dictionary, label: String) -> void:
	_check(scene.conserved and _conserved(scene.context), "%s conserves food and every physical gold balance" % label)
	scene.residents.free()
	scene.workers.free()


func _ids(context: GameContext) -> Array[int]:
	var result: Array[int] = []
	for item in context.keeper.get_items():
		result.append(item.id)
	return result


func _mixed_batches_and_overflow() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var keeper := context.keeper
	var economy := context.economy
	economy.configure_protected_storage({BANK: 50})
	economy.deposit(BANK, economy.mine(GOLD, 50))
	economy.drop_gold(PILE, economy.mine(GOLD, 70))
	var first := context.spawn_creature(SPECIES, Vector2i(3, 3))
	var second := context.spawn_creature(SPECIES, Vector2i(4, 3))
	first.carried_gold = economy.mine(GOLD, 20)
	_check(keeper.pickup(first.id) and keeper.pickup_gold(BANK, 20) and keeper.pickup(second.id) and keeper.pickup_gold(PILE, 40) and keeper.pickup_gold(BANK), "Mixed pickups append creatures and separately sized same-source gold batches")
	_check(keeper.held_count == 5 and keeper.held_actor == first and keeper.held_gold == 0 and keeper.total_held_gold == 90 and economy.keeper_gold == 90, "Front getters differ from aggregate queued gold without losing balances")
	var order := _ids(context)
	_check(not keeper.pickup(first.id) and _ids(context) == order and economy.ground_gold.get(PILE, 0) == 30, "Duplicate creature pickup rejects without disturbing later items or unpicked partial gold")
	var invalid := true
	for cell in [Vector2i(-1, 0), Vector2i(0, 0), GOLD, Vector2i(10, 7), Vector2i(1, 3)]:
		invalid = invalid and not keeper.drop(cell).success and _ids(context) == order and economy.keeper_gold == 90
	_check(invalid and first.is_held and second.is_held, "Invalid mixed-queue drops preserve the complete order and all custody")
	_check(keeper.drop(Vector2i(3, 4)).success and not first.is_held and second.is_held and first.carried_gold == 20 and keeper.held_gold == 20, "Only oldest creature leaves custody and its cargo stays attached")
	_check(keeper.drop(BANK).success and economy.stored_gold == 20 and economy.keeper_gold == 70 and keeper.held_actor == second, "Dropping front gold debits that batch rather than all queued gold")
	_check(keeper.drop(Vector2i(3, 4)).success and not second.is_held and keeper.held_gold == 40, "FIFO returns the second creature before later gold")
	_check(keeper.drop(BANK).success and economy.stored_gold == 50 and economy.ground_gold.get(BANK, 0) == 10 and keeper.held_gold == 30 and economy.keeper_gold == 30, "One queued gold batch fills exact free capacity and spills exact overflow")
	_check(keeper.drop(Vector2i(3, 4)).success and economy.ground_gold.get(Vector2i(3, 4), 0) == 30 and keeper.held_count == 0 and not keeper.is_holding(), "Final gold batch drops to ordinary floor and empties queue once")
	_check(not keeper.drop(BANK).success and _conserved(context), "Repeated empty-queue drop cannot repeat an award")
	_finish(scene, "Mixed partial and overflowing FIFO transfers")


func _many_entries_reload_and_resume() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	# Four distinct delivery workplaces let a large roster drain concurrently.
	# Queue capacity should not be measured by one bank tile's serial throughput.
	context.economy.configure_protected_storage({BANK: 500, Vector2i(3, 2): 500, Vector2i(4, 2): 500, Vector2i(5, 2): 500})
	context.rooms.place_initial(PEN, [Vector2i(6, 4)])
	context.food.produce(Vector2i(6, 4), FOOD, 3)
	var actors: Array[CreatureState] = []
	var amounts: Array[int] = []
	var picked := true
	var total_gold := 0
	for index in 70:
		var actor := context.spawn_creature(SPECIES, Vector2i(3, 3))
		actor.carried_gold = context.economy.mine(GEM, 1)
		actors.append(actor)
		picked = context.keeper.pickup(actor.id) and picked
		var amount := index % 3 + 1
		amounts.append(amount)
		total_gold += amount
		context.economy.drop_gold(PILE, context.economy.mine(GEM, amount))
		picked = context.keeper.pickup_gold(PILE) and picked
	_check(picked and context.keeper.held_count == 140 and context.actors.size() == 70, "Queue accepts 140 mixed entries without a fixed small capacity or duplicate actors")
	var original_order := _ids(context)
	var unique: Dictionary[int, bool] = {}
	for item_id in original_order:
		unique[item_id] = true
	_check(unique.size() == 140 and context.keeper.total_held_gold == total_gold, "Every queued object has a distinct stable item identity and exact aggregate gold")
	scene.residents.setup(context)
	scene.workers.setup(context)
	_advance(scene, 2.0)
	var frozen := true
	for actor in actors:
		frozen = frozen and actor.is_held and actor.carried_gold == 1 and is_equal_approx(actor.satiety, 0.2) and actor.position == context.grid.cell_to_world(Vector2i(3, 3))
	_check(frozen and _ids(context) == original_order and context.food.consumed_units == 0 and context.food.reservations.is_empty() and scene.workers.job_board.active_job_count() == 0, "All queued hybrids stay frozen through feature reload without reserving meals or work")
	var fifo := true
	for index in 70:
		fifo = fifo and context.keeper.held_actor == actors[index] and context.keeper.peek_item().id == original_order[index * 2]
		fifo = context.keeper.drop(Vector2i(3, 4)).success and fifo
		fifo = fifo and not actors[index].is_held and context.keeper.held_gold == amounts[index] and context.keeper.peek_item().id == original_order[index * 2 + 1]
		fifo = context.keeper.drop(PILE).success and fifo
	_check(fifo and context.keeper.held_count == 0 and context.economy.keeper_gold == 0 and context.actors.size() == 70, "All 140 oldest-first drops preserve individual creature identity and gold-batch sizes")
	var resumed := _until(scene, func() -> bool: return context.economy.stored_gold == total_gold + 70 and context.food.consumed_units == 3)
	_check(resumed, "Dropped hungry hybrids resume meals and haul every attached and loose gold unit (stored %d/%d, meals %d/3)" % [context.economy.stored_gold, total_gold + 70, context.food.consumed_units])
	_check(context.food.total_units == 0 and context.food.produced_units == 3 and context.food.reservations.is_empty() and context.economy.ground_gold.is_empty(), "Resumed many-creature loop does not duplicate food, workers or physical gold")
	_finish(scene, "Large mixed queue and resumed simulation")


func _removed_entries_keep_the_order() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var actors: Array[CreatureState] = []
	for index in 5:
		var actor := context.spawn_creature(SPECIES, Vector2i(3, 3))
		actor.carried_gold = context.economy.mine(GOLD, 10)
		actors.append(actor)
		context.keeper.pickup(actor.id)
		if index == 0 or index == 2:
			context.economy.drop_gold(PILE, context.economy.mine(GOLD, 20))
			context.keeper.pickup_gold(PILE)
	var before := context.keeper.get_items()
	var retained: Array[int] = [before[1].id, before[2].id, before[4].id, before[5].id]
	context.despawn_creature(actors[0].id)
	context.despawn_creature(actors[2].id)
	context.actors.erase(actors[4])
	context.keeper.prune()
	context.keeper.prune()
	_check(_ids(context) == retained and context.keeper.held_count == 4 and context.keeper.held_gold == 20 and context.economy.keeper_gold == 40, "Head, middle and raw-array tail removals preserve surviving item order and gold")
	_check(not actors[0].is_held and not actors[2].is_held and not actors[4].is_held and actors[1].is_held and actors[3].is_held, "Removal releases only dead actors while surviving queued actors stay frozen")
	scene.workers.setup(context)
	scene.residents.setup(context)
	_advance(scene, 1.0)
	_check(context.economy.pending_cargo.is_empty() and context.economy.ground_gold.values().reduce(func(sum: int, amount: int) -> int: return sum + amount, 0) == 30 and context.economy.keeper_gold == 40, "Reload recovers all three removed cargo balances exactly once without releasing queued gold")
	var drained := true
	while context.keeper.is_holding():
		drained = context.keeper.drop(PILE).success and drained
	_check(drained and context.actors.size() == 2 and _until(scene, func() -> bool: return context.economy.stored_gold == 90), "Remaining queued workers drop and recover removed cargo plus all gold batches")
	_finish(scene, "Queue removal and orphaned cargo recovery")


func _each_front_keeps_its_origin() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	context.grid.set_tile(Vector2i(1, 3), DungeonGrid.Tile.ROCK)
	var first := context.spawn_creature(SPECIES, Vector2i(3, 3))
	var second := context.spawn_creature(SPECIES, Vector2i(10, 7))
	context.keeper.pickup(first.id)
	context.keeper.pickup(second.id)
	var order := _ids(context)
	_check(not context.keeper.drop(Vector2i(10, 7)).success and _ids(context) == order, "Without a Heart the front creature cannot borrow a later item's disconnected origin")
	_check(context.keeper.drop(Vector2i(3, 4)).success and context.keeper.held_actor == second and context.keeper.drop(Vector2i(10, 7)).success, "Each FIFO creature uses its own pickup origin for fallback drop reachability")
	context.economy.drop_gold(PILE, context.economy.mine(GOLD, 10))
	context.economy.drop_gold(Vector2i(10, 7), context.economy.mine(GOLD, 15))
	context.keeper.pickup_gold(PILE)
	context.keeper.pickup_gold(Vector2i(10, 7))
	_check(not context.keeper.drop(Vector2i(10, 7)).success and context.keeper.held_gold == 10 and context.keeper.total_held_gold == 25, "Front gold also retains its own connected component despite later isolated pickup")
	_check(context.keeper.drop(BANK).success and context.keeper.held_gold == 15 and context.keeper.drop(Vector2i(10, 7)).success and not context.keeper.is_holding(), "Gold FIFO drops retain independent origins and drain each batch only once")
	_finish(scene, "Per-entry fallback origins")
