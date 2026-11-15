extends SceneTree
## Mixed FIFO custody and per-entry identity, independent of input/presentation.

const Layout = preload("res://content/scenarios/foundation_layout.gd")
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_mixed_fifo()
	_removal_order()
	for failure in _failures:
		push_error(failure)
	print("KEEPER QUEUE RULES: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _fixture() -> GameContext:
	var registry := ContentRegistry.new()
	_check(registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Queue tests load real creature and gold definitions")
	var context := GameContext.new(Layout.create(), registry)
	Layout.setup_rooms(context, 3000)
	return context


func _accounted(context: GameContext) -> bool:
	var gold := 0
	var actors: Dictionary[int, bool] = {}
	for item in context.keeper.get_items():
		if item.kind == &"gold":
			gold += item.gold_amount
		elif item.kind == &"creature":
			if item.actor == null or not item.actor.is_held or actors.has(item.actor.id):
				return false
			actors[item.actor.id] = true
	return gold == context.economy.keeper_gold and context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created


func _ids(context: GameContext) -> Array[int]:
	var ids: Array[int] = []
	for item in context.keeper.get_items():
		ids.append(item.id)
	return ids


func _mixed_fifo() -> void:
	var context := _fixture()
	var keeper := context.keeper
	var a := context.spawn_creature(&"foundation.imp", Vector2i(12, 16))
	var b := context.spawn_creature(&"foundation.grubbin", Vector2i(12, 17))
	var c := context.spawn_creature(&"foundation.imp", Vector2i(11, 16))
	a.custom_name = "First"
	b.custom_name = "Third"
	c.custom_name = "Fifth"
	var cells := context.economy.stored_by_cell.keys()
	var first_cell: Vector2i = cells[0]
	var second_cell: Vector2i = cells[1]
	_check(keeper.pickup(a.id) and keeper.pickup_gold(first_cell) and keeper.pickup(b.id) and keeper.pickup_gold(second_cell, 250) and keeper.pickup(c.id), "A mixed creature/gold/creature/gold/creature sequence appends successfully")
	var items := keeper.get_items()
	_check(items.size() == 5 and keeper.held_count == 5 and items[0].actor == a and items[1].gold_amount == 500 and items[2].actor == b and items[3].gold_amount == 250 and items[4].actor == c, "Queue order preserves each actor identity and distinct gold amount")
	var unique: Dictionary[int, bool] = {}
	for item in items:
		unique[item.id] = true
	_check(unique.size() == 5 and _accounted(context), "Mixed entries have unique stable custody IDs with matching gold accounting")
	items.clear()
	_check(keeper.held_count == 5, "Mutating the returned array cannot erase authoritative queue membership")
	_check(not keeper.pickup(a.id) and keeper.held_count == 5, "Already-held actors cannot be queued twice")
	keeper.inspect(c.id)
	_check(keeper.held_actor == a and keeper.held_gold == 0 and keeper.total_held_gold == 750 and keeper.inspected_actor == c, "Front preview and aggregate gold are independent of the latest inspection")
	var before := _ids(context)
	_check(not keeper.drop(Vector2i(0, 0)).success and _ids(context) == before and _accounted(context), "An invalid drop preserves the entire mixed queue and its quantities")
	var floor := Vector2i(12, 18)
	var result := keeper.drop(floor)
	_check(result.success and result.item_id == before[0] and not a.is_held and b.is_held and c.is_held and keeper.held_gold == 500, "The first drop releases only the oldest creature and reveals the first gold batch")
	result = keeper.drop(first_cell)
	_check(result.success and result.amount == 500 and keeper.total_held_gold == 250 and keeper.held_actor == b, "Dropping one gold entry debits only its amount, leaving later gold held")
	_check(keeper.drop(floor).success and not b.is_held and keeper.held_gold == 250, "A different creature species drops in the original FIFO order")
	_check(keeper.drop(first_cell).success and context.economy.ground_gold.get(first_cell, 0) == 250 and keeper.held_actor == c, "A later gold batch overflows full storage without consuming the following actor")
	_check(keeper.drop(floor).success and not keeper.is_holding() and keeper.held_count == 0 and context.actors.size() == 3 and _accounted(context), "The final actor drops without losing any creatures, carried gold or stored/loose gold")
	_check(not keeper.drop(floor).success and _accounted(context), "Repeated drops after the queue empties cannot create another item")


func _removal_order() -> void:
	var context := _fixture()
	var keeper := context.keeper
	var a := context.spawn_creature(&"foundation.imp", Vector2i(12, 16))
	var b := context.spawn_creature(&"foundation.imp", Vector2i(12, 17))
	var c := context.spawn_creature(&"foundation.imp", Vector2i(11, 16))
	a.carried_gold = context.economy.mine(Vector2i(8, 12), 20)
	b.carried_gold = context.economy.mine(Vector2i(8, 12), 30)
	var cell: Vector2i = context.economy.stored_by_cell.keys()[0]
	keeper.pickup(a.id)
	keeper.pickup_gold(cell, 100)
	keeper.pickup(b.id)
	keeper.pickup_gold(cell, 150)
	keeper.pickup(c.id)
	var before := _ids(context)
	context.despawn_creature(b.id)
	_check(_ids(context) == [before[0], before[1], before[3], before[4]] and keeper.held_actor == a and _accounted(context), "Removing a queued middle creature retains both gold entries and survivor order")
	context.actors.erase(a)
	context.simulation_ticked.emit(0.1)
	_check(_ids(context) == [before[1], before[3], before[4]] and keeper.held_gold == 100 and not a.is_held and c.is_held and _accounted(context), "Raw removal of the front carrier recovers its cargo and advances to the correct gold batch")
	keeper.prune()
	_check(context.economy.pending_gold() == 50 and keeper.total_held_gold == 250 and _accounted(context), "Repeated pruning preserves removed cargo and queued gold exactly once")
	_check(keeper.drop(cell).success and keeper.held_gold == 150 and keeper.held_actor == null, "Consecutive same-type entries remain separate FIFO batches")
	_check(keeper.drop(cell).success and keeper.held_actor == c and _accounted(context), "Draining the second gold entry reveals the surviving last actor")
	context.despawn_creature(c.id)
	_check(not keeper.is_holding() and keeper.held_count == 0 and keeper.total_held_gold == 0 and _accounted(context), "Removing the last queued actor clears custody without disturbing recovery balances")
