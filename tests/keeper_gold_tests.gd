extends SceneTree
## Finite Heart bootstrap storage and atomic keeper gold transfers.

const Layout = preload("res://content/scenarios/foundation_layout.gd")
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_transactions()
	_protection_and_edits()
	for failure in _failures:
		push_error(failure)
	print("KEEPER GOLD RULES: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _fixture() -> GameContext:
	var registry := ContentRegistry.new()
	_check(registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Gold hand fixture uses actual content")
	var context := GameContext.new(Layout.create(), registry)
	Layout.setup_rooms(context, 3000)
	return context


func _conserved(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created


func _transactions() -> void:
	var context := _fixture()
	var economy := context.economy
	var keeper := context.keeper
	var source: Vector2i = economy.stored_by_cell.keys()[0]
	var actor := context.spawn_creature(&"foundation.imp", Vector2i(12, 16))
	_check(context.rooms.get_rooms().is_empty() and economy.stored_gold == 3000 and economy.treasury_capacity == 4000, "Fresh dungeon has a finite Heart bank before any Treasury exists")
	_check(keeper.pickup_gold(source) and keeper.held_gold == 500 and economy.stored_gold == 2500 and keeper.is_holding(), "Picking up stock moves exactly 500 gold from storage into hand custody")
	_check(_conserved(context) and not economy.spend(2501), "Held gold remains accounted but cannot be spent as stored currency")
	_check(not keeper.pickup_gold(source) and keeper.held_count == 1, "An exhausted source cannot append an empty gold entry")
	_check(not keeper.drop(Vector2i(0, 0)).success and keeper.held_gold == 500, "Invalid solid terrain never discards held gold")
	var full: Vector2i = economy.stored_by_cell.keys()[0]
	_check(keeper.drop(full).success and keeper.held_gold == 0 and economy.ground_gold.get(full, 0) == 500 and economy.stored_by_cell[full] == 500, "Dropping onto full storage leaves all overflow as a recoverable loose pile")
	_check(keeper.pickup_gold(full) and keeper.held_gold == 500 and economy.stored_by_cell[full] == 500 and not economy.ground_gold.has(full), "Visible loose gold is picked before the stored stock underneath it")
	_check(keeper.drop(source).success and economy.stored_gold == 3000 and not economy.ground_gold.has(source) and _conserved(context), "Dropping back into available Heart storage restores spendable gold without duplication")
	_check(not keeper.drop(source).success and _conserved(context), "A repeated drop of an empty hand cannot award gold")
	keeper.pickup_gold(source)
	economy.spend(100)
	var partial := Vector2i(-1, -1)
	for cell in economy.stored_by_cell:
		if economy.stored_by_cell[cell] == 400:
			partial = cell
	_check(partial.x >= 0 and keeper.drop(partial).success and economy.stored_by_cell.get(partial, 0) == 500 and economy.ground_gold.get(partial, 0) == 400, "Partially full storage accepts its exact free capacity and spills the rest")
	keeper.pickup_gold(partial)
	keeper.drop(source)
	_check(economy.stored_gold == 2900 and economy.spent_gold == 100 and _conserved(context), "Recovered overflow and construction spending preserve the finite bank")
	var next_batch := economy.gold_at(source)
	_check(keeper.pickup(actor.id) and keeper.pickup_gold(source) and keeper.held_actor == actor and keeper.held_count == 2, "Creatures and gold may share the queue without replacing its front")
	keeper.drop(Vector2i(11, 16))
	_check(keeper.held_actor == null and keeper.held_gold == next_batch and not actor.is_held, "Dropping the first creature reveals the queued gold batch")
	_check(keeper.drop(source).success and not keeper.is_holding() and _conserved(context), "Dropping the queued batch restores its original stored balance")
	var loose_cell := Vector2i(10, 17)
	var mined := economy.mine(Vector2i(8, 12), 200)
	economy.drop_gold(loose_cell, mined)
	_check(keeper.pickup_gold(loose_cell) and keeper.held_gold == 200 and not economy.ground_gold.has(loose_cell), "Loose mined gold can be lifted through the same keeper command")
	var target := Vector2i(11, 17)
	_check(keeper.drop(target).success and economy.ground_gold.get(target, 0) == 200 and _conserved(context), "Dropping on ordinary valid floor leaves the exact physical pile")
	economy.take_gold(target, 200)
	actor.carried_gold = 200
	_check(not keeper.pickup_gold(target) and keeper.held_gold == 0 and _conserved(context), "A worker winning the pile first cannot cause a stale keeper pickup reward")


func _protection_and_edits() -> void:
	var context := _fixture()
	var economy := context.economy
	var protected: Array[Vector2i] = []
	protected.assign(economy.protected_storage.keys())
	_check(protected.size() == 8 and not context.rooms.build(&"foundation.treasury", protected).success, "Protected Heart floor cannot be built over")
	var refunds := economy.refunded_gold
	_check(not context.rooms.remove(protected).success and economy.refunded_gold == refunds and economy.stored_gold == 3000, "Heart storage cannot be sold or create construction refunds")
	_check(context.rooms.build(&"foundation.treasury", [Vector2i(16, 18)]).success and economy.treasury_capacity == 4500, "A later Treasury adds capacity alongside protected storage")
	_check(context.rooms.remove([Vector2i(16, 18)]).success and economy.treasury_capacity == 4000 and economy.protected_storage.size() == 8 and _conserved(context), "Selling the Treasury leaves Heart storage intact and accounts for its refund")
	var cell: Vector2i = economy.stored_by_cell.keys()[0]
	var amount := economy.stored_by_cell[cell]
	context.grid.set_tile(cell, DungeonGrid.Tile.BEDROCK)
	_check(economy.storage_capacity(cell) == 0 and not economy.stored_by_cell.has(cell) and economy.ground_gold.get(cell, 0) == amount and _conserved(context), "Trusted terrain blockage preserves local Heart stock as retained loose gold")
	context.grid.set_tile(cell, DungeonGrid.Tile.FLOOR)
	_check(economy.storage_capacity(cell) == 500 and context.keeper.pickup_gold(cell), "Reopened protected floor restores its capacity and retained gold can be picked up")
	context.keeper.drop(cell)
	_check(economy.stored_by_cell.get(cell, 0) == amount and _conserved(context), "Re-depositing restored stock neither loses nor duplicates gold")
	var before := economy.protected_storage.duplicate()
	_check(not economy.configure_protected_storage({Vector2i(0, 0): 500}) and economy.protected_storage == before, "Invalid protected-storage configuration rejects atomically")
