extends SceneTree
## Consequential room transaction and physical storage scenarios.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_build_transactions()
	_test_groups_and_storage()
	_test_definition_validation()
	_test_mine_build_loop()
	_test_sale_refunds()
	print("ROOM RULES: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)


func _session() -> GameContext:
	var grid := DungeonGrid.new(8, 6)
	for y in range(1, 5):
		for x in range(1, 7):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(7, 2), DungeonGrid.Tile.GOLD)
	var registry := ContentRegistry.new()
	registry.register_module(load("res://content/modules/foundation.tres"))
	var context := GameContext.new(grid, registry)
	context.rooms.place_initial(&"foundation.treasury", [Vector2i(1, 1)])
	# Move actual finite supply, rather than minting test funds.
	context.economy.deposit(Vector2i(1, 1), context.economy.mine(Vector2i(7, 2), 200))
	return context


func _conserved(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created


func _test_build_transactions() -> void:
	var context := _session()
	var rooms := context.rooms
	var economy := context.economy
	var cells: Array[Vector2i] = [Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 1), Vector2i(0, 0)]
	var quote := rooms.quote_build(&"foundation.treasury", cells)
	_check(quote.valid and quote.cost == 100 and quote.add.size() == 2 and quote.blocked.size() == 1, "Mixed rectangle charges valid unique floor only and reports blocked cells")
	_check(economy.stored_gold == 200 and economy.spent_gold == 0 and rooms.tiles.size() == 1, "Preview cannot spend gold or place rooms")
	var result := rooms.build(&"foundation.treasury", cells)
	_check(result.success and result.cost == quote.cost and result.add == quote.add, "Build commits the quoted valid cells and exact cost")
	_check(economy.stored_gold == 100 and economy.spent_gold == 100 and _conserved(context), "Construction debits only stored gold and accounts for spending")
	_check(not rooms.build(&"foundation.treasury", cells).success and economy.spent_gold == 100, "Repeated placement cannot charge for existing tiles")
	var too_large: Array[Vector2i] = [Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)]
	var before := rooms.tiles.duplicate()
	_check(not rooms.build(&"foundation.treasury", too_large).success and rooms.tiles == before and economy.spent_gold == 100, "Unaffordable drag is atomic, without partial spending or construction")
	_check(not rooms.build(&"missing.room", [Vector2i(4, 1)]).success, "Unknown room types are rejected")
	_check(not rooms.build(&"foundation.lair", [Vector2i(4, 1)]).success, "Unreleased room definitions stay unavailable")
	context.grid.set_tile(Vector2i(4, 2), DungeonGrid.Tile.HEART)
	context.grid.set_tile(Vector2i(5, 2), DungeonGrid.Tile.PORTAL)
	_check(not rooms.quote_build(&"foundation.treasury", [Vector2i(4, 2), Vector2i(5, 2)]).valid, "Room placement protects Heart and portal")
	context.grid.set_tile(Vector2i(6, 2), DungeonGrid.Tile.ROCK)
	context.grid.set_tile(Vector2i(6, 2), DungeonGrid.Tile.FLOOR)
	_check(rooms.build(&"foundation.treasury", [Vector2i(6, 2)]).success, "Freshly excavated floor is immediately eligible for room placement")
	var stale: Array[Vector2i] = [Vector2i(4, 1)]
	_check(rooms.quote_build(&"foundation.treasury", stale).valid, "One affordable tile can be previewed")
	economy.spend(50)
	_check(not rooms.build(&"foundation.treasury", stale).success and not rooms.tiles.has(stale[0]), "Release rechecks affordability after another command spent the funds")
	_check(not economy.spend(-1) and economy.spend(0) and _conserved(context), "Invalid spend and zero spend preserve conservation")


func _test_groups_and_storage() -> void:
	var context := _session()
	var rooms := context.rooms
	var economy := context.economy
	_check(rooms.place_initial(&"foundation.treasury", [Vector2i(3, 1)]), "Scenario may establish a second separate room")
	_check(rooms.get_rooms().size() == 2, "Separated same-type tiles form distinct rooms")
	rooms.build(&"foundation.treasury", [Vector2i(2, 1)])
	var group := rooms.get_room_at(Vector2i(3, 1))
	_check(rooms.get_rooms().size() == 1 and group.cells.size() == 3 and group.capacity == 3 and group.gold_capacity == 1500, "Bridge merges room membership and data-driven capacities")
	rooms.place_initial(&"foundation.treasury", [Vector2i(4, 2)])
	_check(rooms.get_rooms().size() == 2, "Diagonal room contact does not merge components")
	rooms.remove([Vector2i(2, 1)])
	_check(rooms.get_rooms().size() == 3 and rooms.get_room_at(Vector2i(1, 1)).gold_capacity == 500, "Bridge removal splits rooms and recomputes capacity")
	_check(economy.treasury_capacity == 1500 and economy.storage_capacity(Vector2i(2, 1)) == 0, "Ledger storage mirrors remaining room tiles")
	var stored: int = economy.stored_by_cell.get(Vector2i(1, 1), 0)
	var spent := economy.spent_gold
	var removal := rooms.remove([Vector2i(1, 1), Vector2i(1, 1)])
	_check(removal.success and removal.refund == 25 and economy.spent_gold == spent and economy.refunded_gold == 50, "Selling unique room tiles returns half the cost once and preserves gross spending history")
	_check(economy.stored_by_cell.get(Vector2i(1, 1), 0) == 0 and economy.ground_gold.get(Vector2i(1, 1), 0) == stored and _conserved(context), "Filled storage removal spills exactly its physical stock onto the floor")
	_check(not economy.deposit(Vector2i(1, 1), 1), "Old room tile cannot accept new deliveries")
	var caps: Dictionary[Vector2i, int] = {Vector2i(3, 1): 60, Vector2i(4, 2): 40}
	economy.configure_treasury(caps)
	var recovered := economy.take_gold(Vector2i(1, 1), 75)
	_check(recovered == 75 and economy.deposit(Vector2i(3, 1), 35) and economy.deposit(Vector2i(4, 2), 40), "Recovered gold occupies separate physical storage cells alongside the sale refund")
	_check(economy.stored_gold == 100 and economy.available_storage(Vector2i(3, 1)) == 0 and not economy.deposit(Vector2i(3, 1), 1), "Each tile enforces its own capacity independently")
	caps[Vector2i(3, 1)] = 20
	economy.configure_treasury(caps)
	_check(economy.stored_by_cell[Vector2i(3, 1)] == 20 and economy.ground_gold.get(Vector2i(3, 1), 0) == 40 and _conserved(context), "Capacity reduction spills only the affected cell's overflow")
	context.grid.set_tile(Vector2i(4, 2), DungeonGrid.Tile.ROCK)
	_check(not rooms.tiles.has(Vector2i(4, 2)) and _conserved(context), "Terrain edits invalidate room tiles while preserving all gold")


func _test_definition_validation() -> void:
	var room := RoomDefinition.new()
	room.id = &"test.capacity"
	room.gold_storage_per_tile = -1
	_check(not room.validation_error().is_empty(), "Negative storage definitions are rejected")
	room.gold_storage_per_tile = 100
	room.capacity_per_tile = -1
	_check(not room.validation_error().is_empty(), "Negative functional capacity is rejected")
	room.capacity_per_tile = 2
	room.sell_refund_ratio = 1.1
	_check(not room.validation_error().is_empty(), "Sale refund cannot exceed construction price")
	room.sell_refund_ratio = NAN
	_check(not room.validation_error().is_empty(), "Nonfinite sale refunds are rejected")
	room.sell_refund_ratio = 0.5
	room.storage_small_chest_ratio = NAN
	_check(not room.validation_error().is_empty(), "Nonfinite stage thresholds are rejected")
	room.storage_small_chest_ratio = 0.8
	room.storage_large_chest_ratio = 0.5
	_check(not room.validation_error().is_empty(), "Unordered visual stage thresholds are rejected")


func _test_mine_build_loop() -> void:
	var layout := preload("res://content/scenarios/foundation_layout.gd")
	var registry := ContentRegistry.new()
	registry.register_module(load("res://content/modules/foundation.tres"))
	var context := GameContext.new(layout.create(), registry)
	layout.setup_rooms(context)
	for cell in [Vector2i(12, 16), Vector2i(16, 14), Vector2i(7, 15)]:
		context.spawn_creature(&"foundation.imp", cell)
	var feature := preload("res://content/features/worker_feature.gd").new()
	feature.setup(context)
	var target := Vector2i(8, 12)
	context.mark_excavation([target])
	var conserved := true
	var ready := false
	for tick in 6000:
		feature.tick(1.0 / 30.0)
		conserved = conserved and _conserved(context)
		ready = context.grid.get_tile(target) == DungeonGrid.Tile.FLOOR and context.economy.stored_gold == 200
		if ready:
			break
	_check(ready and conserved and context.excavation_marks.is_empty(), "Actual starting layout: workers mine and haul with conservation at every tick")
	var built := context.rooms.build(&"foundation.treasury", [target])
	_check(built.success and context.economy.spent_gold == 50 and context.economy.stored_gold == 150 and _conserved(context), "Earned mining stock buys a new Treasury immediately on excavated ground")
	var occupied := Vector2i(-1, -1)
	for cell in context.economy.stored_by_cell:
		occupied = cell
		break
	_check(occupied.x >= 0 and context.rooms.remove([occupied]).success, "An occupied starting Treasury tile can be removed")
	for tick in 3000:
		feature.tick(1.0 / 30.0)
		conserved = conserved and _conserved(context)
		if context.economy.stored_gold == 175:
			break
	_check(context.economy.stored_gold == 175 and context.economy.refunded_gold == 25 and conserved, "Workers recover sold-tile gold alongside its exactly-once half-price refund")
	feature.free()


func _test_sale_refunds() -> void:
	var context := _session()
	var cell := Vector2i(1, 1)
	var quote := context.rooms.quote_remove([cell, cell])
	_check(quote.refund == 25 and context.economy.refunded_gold == 0, "Sell preview shows 50% of each unique tile and cannot mint a refund")
	var result := context.rooms.remove([cell, cell])
	_check(result.success and context.economy.stored_gold == 0 and context.economy.ground_gold[cell] == 225, "Selling the last Treasury drops its entire stock plus refund onto the floor")
	_check(context.economy.refunded_gold == 25 and _conserved(context), "Starting-room salvage is explicitly accounted as a source")
	_check(not context.rooms.remove([cell]).success and context.economy.refunded_gold == 25, "Repeated selling cannot refund an already removed tile")
	var rebuilt := _session()
	var tile := Vector2i(2, 1)
	_check(rebuilt.rooms.build(&"foundation.treasury", [tile]).success, "Paid sale scenario builds through the real command")
	_check(rebuilt.rooms.remove([tile]).refund == 25 and rebuilt.economy.stored_gold == 175 and _conserved(rebuilt), "Build/sell cycle costs 25 net gold rather than creating profit")
