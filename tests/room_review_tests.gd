extends SceneTree
## Independent behavioral checks for extension boundaries and physical room stock.

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_rules()
	_storage_removal()
	_refund_edges()
	_connectivity()
	_validation()
	for failure in _failures:
		push_error(failure)
	print("ROOM REVIEW RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _fixture(den_cost: int = 20) -> GameContext:
	var grid := DungeonGrid.new(7, 7)
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(6, 6), DungeonGrid.Tile.GOLD)
	var registry := ContentRegistry.new()
	var storage := RoomDefinition.new()
	storage.id = &"review.vault"
	storage.display_name = "Unrelated vault"
	storage.gold_cost_per_tile = 10
	storage.gold_storage_per_tile = 100
	storage.capacity_per_tile = 2
	var den := RoomDefinition.new()
	den.id = &"review.den"
	den.gold_cost_per_tile = den_cost
	den.capacity_per_tile = 3
	var module := ContentModule.new()
	module.id = &"review.room_extension"
	module.definitions = [storage, den]
	_check(registry.register_module(module).is_empty(), "Independent room module registers")
	return GameContext.new(grid, registry)


func _fund(context: GameContext, cell: Vector2i, amount: int) -> void:
	_check(context.rooms.place_initial(&"review.vault", [cell]), "Scenario places custom storage definition")
	var mined := context.economy.mine(Vector2i(6, 6), amount)
	_check(mined == amount and context.economy.deposit(cell, mined), "Fixture gold comes from finite seam and physical deposit")


func _conserved(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created


func _rules() -> void:
	var context := _fixture()
	_fund(context, Vector2i(0, 0), 100)
	var target := Vector2i(1, 0)
	var quote := context.rooms.quote_build(&"review.den", [target])
	_check(quote.valid and quote.add == [target], "Empty open floor accepts room immediately")
	var excavated := Vector2i(2, 0)
	context.grid.set_tile(excavated, DungeonGrid.Tile.ROCK)
	_check(not context.rooms.quote_build(&"review.den", [excavated]).valid, "Solid stone cannot host room")
	context.grid.set_tile(excavated, DungeonGrid.Tile.FLOOR)
	_check(context.rooms.quote_build(&"review.den", [excavated]).valid, "Rock becoming floor is immediately buildable without a claim action")
	quote = context.rooms.quote_build(&"review.den", [target, target, Vector2i(-1, 0)])
	_check(quote.valid and quote.add == [target] and quote.cost == 20, "Duplicates and invalid area cells never inflate charge")
	_check(quote.blocked == [Vector2i(-1, 0)], "Quote preserves skipped invalid tile feedback")
	var result := context.rooms.build(&"review.den", [target, target, Vector2i(-1, 0)])
	_check(result.success and context.economy.stored_gold == 80 and context.economy.spent_gold == 20, "Custom non-storage room spends exact quoted amount")
	var room := context.rooms.get_room_at(target)
	_check(room != null and room.definition_id == &"review.den" and room.capacity == 3 and room.gold_capacity == 0, "New room derives capacity without Treasury ID special case")
	_check(context.economy.storage_capacity(target) == 0, "Non-storage room cannot receive gold")
	_check(not context.rooms.build(&"review.vault", [target]).success, "Room overlap cannot replace room or charge twice")
	_check(context.economy.stored_gold == 80, "Rejected overlap preserves spendable balance")
	var area: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)]
	var before := context.rooms.tiles.size()
	_check(not context.rooms.build(&"review.den", area).success, "Unaffordable area fails as a single transaction")
	_check(context.rooms.tiles.size() == before and context.economy.stored_gold == 80, "Failed area has no partial placement or partial debit")
	_check(not context.rooms.build(&"missing.room", area).success, "Unknown room content rejected")
	_check(context.rooms.quote_remove([target, target]).refund == 10, "Sell quote returns half construction cost once per unique tile")
	_check(context.rooms.remove([target]).success and context.economy.stored_gold == 90, "Selling room refunds half its cost into available storage")
	_check(context.economy.refunded_gold == 10, "Refund source is explicit in the conservation ledger")
	_check(_conserved(context), "Construction and sale conserve gold with spent and refunded stock accounted")
	context.grid.set_tile(target, DungeonGrid.Tile.PORTAL)
	_check(not context.rooms.build(&"review.den", [target]).success, "Portal cannot accept room")
	context.grid.set_tile(target, DungeonGrid.Tile.HEART)
	_check(not context.rooms.build(&"review.den", [target]).success, "Heart cannot accept room")


func _storage_removal() -> void:
	var context := _fixture()
	var first := Vector2i(0, 0)
	var second := Vector2i(1, 0)
	_fund(context, first, 100)
	_check(context.rooms.place_initial(&"review.vault", [second]), "Second storage tile derives own limit")
	_check(context.economy.storage_capacity(first) == 100 and context.economy.available_storage(first) == 0, "First tile is individually full")
	_check(context.economy.available_storage(second) == 100, "Empty neighbor retains independent capacity")
	_check(not context.economy.deposit(first, 1), "Room total free space cannot overfill specific tile")
	var mined := context.economy.mine(Vector2i(6, 6), 70)
	_check(context.economy.deposit(second, mined), "Gold stores physically on second tile")
	_check(context.economy.stored_by_cell.get(first) == 100 and context.economy.stored_by_cell.get(second) == 70, "Stored amounts remain on actual receiving tiles")
	_check(context.economy.treasury_capacity == 200 and context.economy.stored_gold == 170, "Treasury totals sum actual tiles")
	_check(context.economy.spend(120), "Spend can debit more than one physical tile")
	_check(context.economy.stored_by_cell.get(first, 0) == 0 and context.economy.stored_by_cell.get(second) == 50, "Deterministic spend updates physical stock on affected tiles")
	_check(_conserved(context), "Multi-tile spending preserves full gold ledger")
	_check(context.rooms.remove([second]).success, "Filled tile can be removed")
	_check(context.economy.stored_gold == 5 and context.economy.ground_gold.get(second) == 50, "Selling filled tile spills its stock while refund uses surviving capacity")
	_check(context.economy.treasury_capacity == 100 and context.economy.storage_capacity(second) == 0, "Removal reduces capacity and rejects stale deposits")
	_check(not context.economy.deposit(second, 10), "Removed treasury destination refuses late worker deposit")
	_check(_conserved(context), "Storage removal does not lose or duplicate gold")
	_check(context.economy.take_gold(second, 50) == 50, "Spilled gold is recoverable physical ground stock")
	_check(context.economy.deposit(first, 50), "Recovered stock can be delivered to surviving storage tile")
	_check(_conserved(context), "Spill/recovery round trip conserves gold")


func _refund_edges() -> void:
	var context := _fixture()
	var last := Vector2i(0, 0)
	_fund(context, last, 100)
	var quote := context.rooms.quote_remove([last, last, Vector2i(-1, 0)])
	_check(quote.refund == 5 and quote.remove == [last], "Initial Treasury sale quotes 50 percent once and skips invalid cells")
	_check(context.rooms.remove([last, last]).success, "Last filled Treasury tile can be sold")
	_check(context.economy.stored_gold == 0 and context.economy.ground_gold.get(last, 0) == 105, "Without remaining storage, both removed stock and refund stay on sold floor")
	_check(context.economy.refunded_gold == 5 and _conserved(context), "Last-tile refund is explicitly accounted without losing stored gold")
	_check(not context.rooms.remove([last]).success and context.economy.refunded_gold == 5, "Repeated sale cannot issue refund twice")
	context = _fixture()
	_fund(context, last, 100)
	var remaining := Vector2i(1, 0)
	_check(context.rooms.place_initial(&"review.vault", [remaining]), "Partial refund fixture adds surviving storage")
	_check(context.economy.deposit(remaining, context.economy.mine(Vector2i(6, 6), 98)), "Surviving storage has only two free gold slots")
	_check(context.rooms.remove([last]).success, "Selling stock-bearing tile with nearly full remaining storage succeeds")
	_check(context.economy.stored_by_cell.get(remaining) == 100 and context.economy.ground_gold.get(last) == 103, "Refund fills only available two slots and leaves exact remainder beside original spilled stock")
	_check(_conserved(context), "Split stored/loose refund conserves its explicit source")
	context = _fixture()
	_fund(context, Vector2i(0, 0), 100)
	var target := Vector2i(1, 0)
	for cycle in range(3):
		_check(context.rooms.build(&"review.den", [target]).success, "Build/sell cycle %d builds" % cycle)
		var before := context.economy.stored_gold
		_check(not context.rooms.build(&"review.den", [target]).success and context.economy.stored_gold == before, "Repeated build cannot sell or refund existing room")
		_check(context.rooms.remove([target, target]).success, "Build/sell cycle %d sells once" % cycle)
	_check(context.economy.stored_gold == 70 and context.economy.spent_gold == 60 and context.economy.refunded_gold == 30, "Three build/sell cycles each cost a net half-price and cannot create profit")
	_check(_conserved(context), "Repeated build/sell cycles preserve explicit gold ledger")
	context = _fixture(21)
	_fund(context, Vector2i(0, 0), 100)
	var odd_cells: Array[Vector2i] = [target, Vector2i(2, 0)]
	_check(context.rooms.build(&"review.den", odd_cells).success, "Odd-price room area builds")
	_check(context.rooms.quote_remove(odd_cells).refund == 20, "Odd-price area refund rounds down per tile before summing")
	_check(context.rooms.remove(odd_cells).success and context.economy.stored_gold == 78, "Rounded area sale credits exact quoted refund")
	_check(_conserved(context), "Odd-price sale preserves conservation")


func _connectivity() -> void:
	var context := _fixture()
	var line: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
	_check(context.rooms.place_initial(&"review.den", [line[0], line[2]]), "Two disconnected same-type room islands start separately")
	_check(context.rooms.get_rooms().size() == 2, "Disconnected same-type cells are two rooms")
	_check(context.rooms.place_initial(&"review.den", [line[1]]), "Bridge tile accepted")
	_check(context.rooms.get_rooms().size() == 1 and context.rooms.get_room_at(line[0]).capacity == 9, "Cardinal bridge merges groups and sums capacity")
	_check(context.rooms.remove([line[1]]).success and context.rooms.get_rooms().size() == 2, "Removing bridge splits connected room")
	_check(context.rooms.get_room_at(line[0]).capacity == 3 and context.rooms.get_room_at(line[2]).capacity == 3, "Split groups each have correct remaining capacity")
	var diagonal := Vector2i(2, 3)
	_check(context.rooms.place_initial(&"review.den", [diagonal]), "Diagonal island placement accepted")
	_check(context.rooms.get_rooms().size() == 3, "Diagonal adjacency does not merge room groups")
	context.grid.set_tile(line[0], DungeonGrid.Tile.ROCK)
	_check(context.rooms.get_room_at(line[0]) == null and not context.rooms.tiles.has(line[0]), "Terrain invalidation removes stale room and capacity")


func _validation() -> void:
	var definition := RoomDefinition.new()
	definition.id = &"review.invalid"
	definition.storage_small_chest_ratio = 0.8
	definition.storage_large_chest_ratio = 0.7
	_check(not definition.validation_error().is_empty(), "Visual stages reject reversed thresholds")
	definition.storage_small_chest_ratio = NAN
	_check(not definition.validation_error().is_empty(), "Visual stages reject nonfinite thresholds")
	definition.storage_small_chest_ratio = 0.3
	definition.storage_large_chest_ratio = 1.0
	_check(definition.validation_error().is_empty(), "Content can configure large chest at full tile capacity")
	definition.gold_storage_per_tile = -1
	_check(not definition.validation_error().is_empty(), "Storage definitions reject negative cell capacity")
	definition.gold_storage_per_tile = 0
	_check(is_equal_approx(definition.sell_refund_ratio, 0.5), "Default room sale refund is fifty percent")
	definition.sell_refund_ratio = NAN
	_check(not definition.validation_error().is_empty(), "Refund definitions reject nonfinite ratios")
	definition.sell_refund_ratio = 1.1
	_check(not definition.validation_error().is_empty(), "Refund definitions reject ratios above full cost")
