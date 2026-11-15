extends SceneTree

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_paths()
	_test_gold()
	print("PATH/ECONOMY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)


func _test_paths() -> void:
	var grid := DungeonGrid.new(5, 3)
	for x in 5:
		grid.set_tile(Vector2i(x, 1), DungeonGrid.Tile.FLOOR)
	var path := GridPathfinder.find_path(grid, Vector2i(0, 1), Vector2i(4, 1))
	_check(path.size() == 5 and path.front() == Vector2i(0, 1) and path.back() == Vector2i(4, 1), "Shortest cardinal path includes both endpoints")
	grid.set_tile(Vector2i(2, 1), DungeonGrid.Tile.HEART)
	_check(GridPathfinder.find_path(grid, Vector2i(0, 1), Vector2i(4, 1)).is_empty(), "Solid landmark blocks path")
	_check(GridPathfinder.find_path(grid, Vector2i(0, 1), Vector2i(0, 1)).size() == 1, "Same-cell path")
	_check(GridPathfinder.find_path(grid, Vector2i(-1, 1), Vector2i(0, 1)).is_empty(), "Invalid start has no path")
	for x in 5:
		grid.set_tile(Vector2i(x, 0), DungeonGrid.Tile.FLOOR)
	var detour := GridPathfinder.find_path(grid, Vector2i(0, 1), Vector2i(4, 1))
	_check(is_equal_approx(GridPathfinder.path_cost(detour), 2.0 + 2.0 * sqrt(2.0)), "Weighted diagonal detour takes the shortest safe route")


func _test_gold() -> void:
	var grid := DungeonGrid.new(4, 3)
	grid.set_tile(Vector2i(1, 1), DungeonGrid.Tile.GOLD)
	grid.set_tile(Vector2i(2, 1), DungeonGrid.Tile.GEM)
	grid.set_tile(Vector2i(1, 2), DungeonGrid.Tile.FLOOR)
	var economy := GoldEconomy.new(grid)
	var actor := CreatureState.new()
	var actors: Array[CreatureState] = [actor]
	_check(economy.initial_gold == 200 and economy.accounted_gold(actors) == 200, "Finite seam initializes physical gold supply")
	actor.carried_gold = economy.mine(Vector2i(1, 1), 60)
	_check(actor.carried_gold == 60 and economy.remaining_gold[Vector2i(1, 1)] == 140, "Mining transfers finite gold into cargo")
	_check(economy.accounted_gold(actors) == economy.initial_gold, "Cargo plus remaining seam conserves gold")
	_check(not economy.deposit(Vector2i(1, 2), actor.carried_gold), "Unregistered floor cannot bank gold")
	economy.treasury_cells.assign([Vector2i(1, 2)])
	_check(economy.deposit(Vector2i(1, 2), actor.carried_gold), "Treasury accepts delivered cargo")
	actor.carried_gold = 0
	_check(economy.stored_gold == 60 and economy.accounted_gold(actors) == 200, "Deposited amount is spendable, without creating gold")
	var mined := economy.mine(Vector2i(1, 1), 1000)
	economy.drop_gold(Vector2i(1, 2), mined)
	_check(mined == 140 and economy.mine(Vector2i(1, 1), 20) == 0, "Finite seam cannot yield beyond initial total")
	_check(economy.accounted_gold(actors) == 200, "Loose piles preserve finite supply")
	actor.carried_gold = economy.take_gold(Vector2i(1, 2), 60)
	_check(actor.carried_gold == 60 and economy.ground_gold[Vector2i(1, 2)] == 80, "Hauling respects requested pickup amount")
	_check(not economy.drop_gold(Vector2i(0, 0), 10), "Cannot drop cargo into solid rock")
	actor.carried_gold += economy.mine(Vector2i(2, 1), 20)
	_check(economy.gem_gold_created == 20 and grid.get_tile(Vector2i(2, 1)) == DungeonGrid.Tile.GEM, "Renewable gems report generated gold and retain terrain")
	_check(economy.accounted_gold(actors) == economy.initial_gold + economy.gem_gold_created, "Renewable generation is explicitly accounted")
	_check(economy.mine(Vector2i(1, 2), 20) == 0 and economy.mine(Vector2i(2, 1), -5) == 0, "Invalid mining never creates gold")
	_check(economy.take_gold(Vector2i(1, 2), -10) == 0 and not economy.deposit(Vector2i(1, 2), -1), "Negative transfers rejected")
	grid.set_tile(Vector2i(1, 1), DungeonGrid.Tile.FLOOR)
	_check(economy.accounted_gold(actors) == 220, "Seam removal after exhaustion preserves total")
