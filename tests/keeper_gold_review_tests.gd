extends SceneTree
## Independent physical hand-gold, protected storage and worker race regressions.

const Workers = preload("res://content/features/worker_feature.gd")
const STEP := 1.0 / 30.0
const SOURCE := Vector2i(8, 4)
const BANK := Vector2i(2, 3)
const VAULT := Vector2i(5, 3)
const PILE := Vector2i(4, 4)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_loose_stored_and_overflow()
	_mixed_queue_and_blocking()
	_worker_competition_and_reload()
	_protected_storage_survives_rooms()
	for failure in _failures:
		push_error(failure)
	print("KEEPER GOLD REVIEW: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture() -> Dictionary:
	var grid := DungeonGrid.new(11, 9)
	for y in range(1, 7):
		for x in range(1, 8):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(1, 3), DungeonGrid.Tile.HEART)
	grid.set_tile(SOURCE, DungeonGrid.Tile.GOLD)
	grid.set_tile(Vector2i(9, 7), DungeonGrid.Tile.FLOOR)
	var worker := CreatureDefinition.new()
	worker.id = &"gold_review.worker"
	worker.capabilities = [&"haul"]
	worker.move_speed = 6.0
	var vault := RoomDefinition.new()
	vault.id = &"gold_review.vault"
	vault.gold_storage_per_tile = 100
	var module := ContentModule.new()
	module.id = &"gold_review"
	module.definitions = [worker, vault]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Gold-hand review registers an independent hauling/storage module")
	var context := GameContext.new(grid, registry)
	_check(context.economy.configure_protected_storage({BANK: 50}), "Fixture configures finite protected storage without a Treasury room")
	var feature := Workers.new()
	feature.setup(context)
	return {"context": context, "feature": feature, "conserved": true}


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.feature.tick(STEP)
		var context: GameContext = scene.context
		context.simulation_ticked.emit(STEP)
		if context.economy.accounted_gold(context.actors) != context.economy.initial_gold + context.economy.gem_gold_created:
			scene.conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 20.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _finish(scene: Dictionary, label: String) -> void:
	var context: GameContext = scene.context
	_check(scene.conserved and context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created, "%s conserves unmined, stored, loose, carried and keeper-held gold" % label)
	scene.feature.free()


func _loose_stored_and_overflow() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var economy := context.economy
	economy.deposit(BANK, economy.mine(SOURCE, 20))
	economy.drop_gold(PILE, economy.mine(SOURCE, 40))
	_check(context.keeper.pickup_gold(PILE) and context.keeper.held_gold == 40 and context.keeper.is_holding(), "Keeper physically acquires the loose pile as its hand contents")
	_check(economy.keeper_gold == 40 and economy.stored_gold == 20 and not economy.ground_gold.has(PILE), "Pickup transfers the exact pile to custody without making it spendable")
	_check(not context.keeper.pickup_gold(SOURCE) and context.keeper.held_count == 1, "Invalid gold source cannot append an empty hand item")
	var result := context.keeper.drop(BANK)
	_check(result.success and result.amount == 40 and context.keeper.held_gold == 0 and not context.keeper.is_holding(), "Gold drop empties the hand with an exact physical transfer")
	_check(economy.stored_by_cell.get(BANK, 0) == 50 and economy.ground_gold.get(BANK, 0) == 10, "Dropping into nearly full storage deposits what fits and leaves exact overflow loose")
	_check(economy.gold_at(BANK) == 10 and context.keeper.pickup_gold(BANK) and context.keeper.held_gold == 10 and economy.stored_gold == 50, "Visible overflow is picked up before the stock beneath it")
	_check(context.keeper.drop(PILE).success and economy.ground_gold.get(PILE, 0) == 10, "Dropping on ordinary floor creates a recoverable physical pile")
	_check(context.keeper.pickup_gold(BANK) and context.keeper.held_gold == 50 and economy.stored_gold == 0, "Stored gold can be lifted into the hand without remaining spendable")
	_check(not economy.spend(1), "Keeper-held currency cannot pay a construction expense")
	_check(context.keeper.drop(BANK).success and economy.stored_gold == 50 and not context.keeper.drop(BANK).success, "Returning stored gold and a stale second release cannot duplicate currency")
	_check(context.keeper.pickup_gold(BANK, 15) and economy.stored_gold == 35 and context.keeper.held_gold == 15, "Explicit partial keeper pickup preserves the unpicked storage balance")
	_check(context.keeper.drop(BANK).success and economy.stored_gold == 50, "Partial hand balance can be returned through the same keeper drop command")
	_finish(scene, "Loose, stored and overflowing hand gold")


func _mixed_queue_and_blocking() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var economy := context.economy
	economy.deposit(BANK, economy.mine(SOURCE, 40))
	var actor := context.spawn_creature(&"gold_review.worker", Vector2i(4, 3))
	context.keeper.pickup(actor.id)
	_check(context.keeper.pickup_gold(BANK) and context.keeper.held_gold == 0 and context.keeper.held_actor == actor and context.keeper.total_held_gold == 40 and context.keeper.held_count == 2, "Gold appends behind a held creature while front getters retain FIFO identity")
	context.keeper.drop(Vector2i(4, 3))
	_check(context.keeper.pickup(actor.id) and actor.is_held and context.keeper.held_gold == 40 and context.keeper.held_actor == null and context.keeper.held_count == 2, "Creature appends behind front gold without replacing that batch")
	context.grid.set_tile(BANK, DungeonGrid.Tile.BEDROCK)
	var rejected := true
	for cell in [BANK, Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 3), SOURCE, Vector2i(9, 7)]:
		var quote := context.keeper.quote_drop(cell)
		var result := context.keeper.drop(cell)
		rejected = rejected and not quote.valid and not result.success and context.keeper.held_gold == 40
	_check(rejected and economy.accounted_gold(context.actors) == economy.initial_gold, "Source removal and invalid terrain/connectivity cannot lose keeper-held currency")
	context.grid.set_tile(BANK, DungeonGrid.Tile.FLOOR)
	_check(economy.storage_capacity(BANK) == 50 and context.keeper.drop(BANK).success and economy.stored_gold == 40 and context.keeper.held_actor == actor, "Restoring protected floor accepts only front gold and exposes the queued creature")
	context.keeper.drop(Vector2i(4, 3))
	_finish(scene, "Mixed hand queue and blocked sources")


func _worker_competition_and_reload() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var economy := context.economy
	context.rooms.place_initial(&"gold_review.vault", [VAULT])
	var worker := context.spawn_creature(&"gold_review.worker", Vector2i(4, 3))
	economy.drop_gold(PILE, economy.mine(SOURCE, 60))
	context.keeper.pickup_gold(PILE)
	scene.feature.setup(context)
	_advance(scene, 3.0)
	_check(context.keeper.held_gold == 60 and worker.carried_gold == 0 and scene.feature.job_board.active_job_count() == 0, "Workers and feature reload cannot collect gold already in the keeper's hand")
	_check(context.keeper.drop(VAULT).success and economy.stored_by_cell.get(VAULT, 0) == 60, "Keeper deposits into a player storage room beside protected capacity")
	economy.drop_gold(PILE, economy.mine(SOURCE, 50))
	var reserved := _until(scene, func() -> bool: return scene.feature.job_board.job_for(worker.id) != null, 1.0)
	_check(reserved and worker.carried_gold == 0, "Worker reserves an actual loose-pile haul before the keeper competes")
	_check(context.keeper.pickup_gold(PILE), "Keeper can take the still-physical pile before its reserved worker arrives")
	_advance(scene, 2.0)
	_check(worker.carried_gold == 0 and context.keeper.held_gold == 50 and scene.feature.job_board.active_job_count() == 0, "Reserved haul cancels after keeper pickup without duplicated cargo")
	context.keeper.drop(Vector2i(3, 4))
	_check(_until(scene, func() -> bool: return economy.stored_gold == 110), "Dropped loose hand gold is rediscovered and physically hauled by workers")
	_check(worker.carried_gold == 0 and economy.ground_gold.is_empty() and economy.keeper_gold == 0, "Competing transfers end with each currency unit stored once")
	_finish(scene, "Worker competition and reload")


func _protected_storage_survives_rooms() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	var economy := context.economy
	economy.deposit(BANK, economy.mine(SOURCE, 40))
	var before := economy.protected_storage.duplicate()
	_check(not economy.configure_protected_storage({BANK: 100, Vector2i(-1, 0): 50}) and economy.protected_storage == before and economy.stored_gold == 40, "Invalid protected-storage configuration is rejected atomically")
	_check(not context.rooms.build(&"gold_review.vault", [BANK]).success and not context.rooms.remove([BANK]).success, "Protected bank is neither buildable room floor nor saleable room stock")
	context.rooms.place_initial(&"gold_review.vault", [VAULT])
	economy.deposit(VAULT, economy.mine(SOURCE, 30))
	_check(economy.treasury_capacity == 150 and economy.protected_storage == before, "Room-based storage expands rather than replacing protected capacity")
	_check(context.rooms.remove([VAULT]).success and economy.treasury_capacity == 50 and economy.stored_by_cell.get(BANK, 0) == 40 and economy.ground_gold.get(VAULT, 0) == 30, "Selling Treasury spills only its own stock and preserves protected bank and capacity")
	context.rooms.place_initial(&"gold_review.vault", [VAULT])
	_check(economy.treasury_capacity == 150 and economy.protected_storage == before and economy.stored_by_cell.get(BANK, 0) == 40, "Room rebuilds cannot overwrite or duplicate protected storage")
	_finish(scene, "Protected capacity across room edits")
