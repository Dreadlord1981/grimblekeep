extends SceneTree
## Independent animal identities, shared pen capacity, bounded roaming and fences.

const Production = preload("res://content/features/food_feature.gd")
const PIG := &"pig_life.food"
const PEN := &"pig_life.pen"
const EATER := &"pig_life.eater"
const CARDINALS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const STEP := 0.1
const MAX_STEP := 0.121
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_capacity_shapes()
	_age_and_identity()
	_isolated_and_concave_roaming()
	_topology_continuity()
	_exact_service_pig()
	_shrinking_capacity()
	_mixed_food_components()
	_newborn_nutrition()
	await _perimeter_fences()
	for failure in _failures:
		push_error(failure)
	print("PIG LIFE RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(automatic: bool = false) -> GameContext:
	var grid := DungeonGrid.new(18, 12)
	for y in range(1, 11):
		for x in range(1, 17):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	var pig := FoodDefinition.new()
	pig.id = PIG
	pig.tags = [&"meat"]
	pig.wanders = true
	pig.growth_seconds = 2.0
	pig.newborn_scale = 0.3
	var pen := RoomDefinition.new()
	pen.id = PEN
	pen.food_type = PIG
	pen.food_capacity_per_tile = 1
	pen.food_minimum_size = Vector2i(3, 1)
	pen.food_tiles_per_unit = 3
	pen.food_production_seconds = 0.5 if automatic else 0.0
	pen.floor_style = &"muddy_straw"
	pen.wall_style = &"pen_fencing"
	var eater := CreatureDefinition.new()
	eater.id = EATER
	eater.capabilities = [&"eat"]
	eater.food_tags = [&"meat"]
	var other := FoodDefinition.new()
	other.id = &"pig_life.other_food"
	other.wanders = true
	other.growth_seconds = 2.0
	var other_pen := RoomDefinition.new()
	other_pen.id = &"pig_life.other_pen"
	other_pen.food_type = other.id
	other_pen.food_capacity_per_tile = 1
	other_pen.food_minimum_size = Vector2i(3, 1)
	other_pen.food_tiles_per_unit = 3
	var module := ContentModule.new()
	module.id = &"pig_life.module"
	module.definitions = [pig, pen, eater, other, other_pen]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Pig life uses independent data definitions")
	return GameContext.new(grid, registry)


func _rectangle(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			result.append(Vector2i(x, y))
	return result


func _source(context: GameContext, member: Vector2i) -> Vector2i:
	for cell in context.food.sources:
		if member in context.food.sources[cell].cells:
			return cell
	return Vector2i(-1, -1)


func _feature(context: GameContext) -> GameFeature:
	var feature := Production.new()
	feature.setup(context)
	return feature


func _conserved(context: GameContext) -> bool:
	if context.food.units.size() != context.food.total_units or context.food.accounted_units() != context.food.produced_units:
		return false
	for cell in context.food.stock:
		for food_id: StringName in context.food.stock[cell]:
			var identities := 0
			for unit in context.food.units.values():
				if unit.cell == cell and unit.food_id == food_id:
					identities += 1
			if identities != context.food.get_stock(cell, food_id):
				return false
	return true


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _capacity_shapes() -> void:
	var shapes: Array = [
		_rectangle(Vector2i(3, 3), Vector2i.ONE),
		_rectangle(Vector2i(3, 3), Vector2i(2, 1)),
		[Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4)],
		_rectangle(Vector2i(3, 3), Vector2i(3, 1)),
		_rectangle(Vector2i(3, 3), Vector2i(1, 3)),
		_rectangle(Vector2i(3, 3), Vector2i(3, 2)),
		_rectangle(Vector2i(3, 3), Vector2i(3, 3))]
	var expected := [0, 0, 0, 1, 1, 2, 3]
	for index in shapes.size():
		var context := _fixture()
		var cells: Array[Vector2i] = []
		cells.assign(shapes[index])
		context.rooms.place_initial(PEN, cells)
		var anchor := _source(context, cells[0])
		_check(context.food.total_capacity == expected[index], "Pen shape %d has capacity %d with a straight minimum and one pig per three tiles" % [index, expected[index]])
		_check(context.food.produce(anchor, PIG, 99) == expected[index], "Shared source %d clamps births to its whole-room capacity" % index)
		_check(_conserved(context), "Shape %d keeps identity and quantity ledgers consistent" % index)
	var separate := _fixture()
	separate.rooms.place_initial(PEN, [Vector2i(3, 3)])
	separate.rooms.place_initial(PEN, [Vector2i(8, 3), Vector2i(9, 3)])
	_check(separate.food.total_capacity == 0, "Disconnected undersized pens cannot pool their three tiles into a birth")


func _age_and_identity() -> void:
	var context := _fixture()
	context.rooms.place_initial(PEN, _rectangle(Vector2i(3, 3), Vector2i(6, 1)))
	var anchor := _source(context, Vector2i(3, 3))
	context.food.produce(anchor, PIG, 1)
	var first: FoodUnitState = context.food.units.values()[0]
	var first_id := first.id
	var feature := _feature(context)
	feature.tick(0.6)
	context.food.produce(anchor, PIG, 1)
	var second: FoodUnitState
	for unit in context.food.units.values():
		if unit.id != first_id:
			second = unit
	_check(context.food.units[first_id] == first and is_equal_approx(first.age_seconds, 0.6) and second != null and is_zero_approx(second.age_seconds), "A newborn has its own ID and zero age without resetting its older sibling")
	var before := first.position
	feature.free()
	feature = _feature(context)
	feature.tick(STEP)
	_check(context.food.units[first_id] == first and is_equal_approx(first.age_seconds, 0.7) and first.position.distance_to(before) <= MAX_STEP, "Feature reload preserves identity, maturity and continuous position")
	for tick in 30:
		feature.tick(STEP)
	_check(is_equal_approx(first.age_seconds, 2.0) and is_equal_approx(second.age_seconds, 2.0), "Independent pigs mature to the configured age ceiling")
	var units := context.food.total_units
	feature.tick(NAN)
	feature.tick(-1.0)
	_check(context.food.total_units == units and _conserved(context), "Invalid ticks cannot create pigs or corrupt stable identities")
	feature.free()


func _isolated_and_concave_roaming() -> void:
	var context := _fixture()
	var first_cells := _rectangle(Vector2i(3, 3), Vector2i(3, 1))
	var second_cells := _rectangle(Vector2i(9, 3), Vector2i(3, 1))
	context.rooms.place_initial(PEN, first_cells)
	context.rooms.place_initial(PEN, second_cells)
	var first_anchor := _source(context, first_cells[0])
	var second_anchor := _source(context, second_cells[0])
	context.food.produce(first_anchor, PIG, 1)
	context.food.produce(second_anchor, PIG, 1)
	var feature := _feature(context)
	var bounded := true
	var smooth := true
	var crossed := false
	for tick in 600:
		var old: Dictionary[int, Vector3] = {}
		for unit in context.food.units.values():
			old[unit.id] = unit.position
		feature.tick(STEP)
		for unit in context.food.units.values():
			var current := context.grid.world_to_cell(unit.position)
			var membership := first_cells if unit.cell == first_anchor else second_cells
			bounded = bounded and current in membership
			smooth = smooth and unit.position.distance_to(old[unit.id]) <= MAX_STEP
			crossed = crossed or current != unit.cell
	_check(bounded and smooth, "Separate pens remain isolated with speed-bounded authoritative movement")
	_check(crossed, "Pigs visit other connected pen tiles instead of remaining in their allocation tile")
	_check(_conserved(context), "Roaming never changes food quantity")
	feature.free()
	context = _fixture()
	var concave: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)]
	context.rooms.place_initial(PEN, concave)
	context.food.produce(_source(context, concave[0]), PIG, 2)
	feature = _feature(context)
	var corners_safe := true
	for tick in 700:
		var previous: Dictionary[int, Vector2i] = {}
		for unit in context.food.units.values():
			previous[unit.id] = context.grid.world_to_cell(unit.position)
		feature.tick(STEP)
		for unit in context.food.units.values():
			var cell := context.grid.world_to_cell(unit.position)
			var prior: Vector2i = previous[unit.id]
			var difference := cell - prior
			corners_safe = corners_safe and cell in concave
			if difference.x != 0 and difference.y != 0:
				corners_safe = corners_safe and prior + Vector2i(difference.x, 0) in concave and prior + Vector2i(0, difference.y) in concave
	_check(corners_safe, "Concave pen routes never leave the room or cut across missing corner cells")
	feature.free()


func _topology_continuity() -> void:
	var context := _fixture()
	var cells := _rectangle(Vector2i(3, 3), Vector2i(6, 1))
	context.rooms.place_initial(PEN, cells)
	context.food.produce(_source(context, cells[0]), PIG, 1)
	var unit: FoodUnitState = context.food.units.values()[0]
	var feature := _feature(context)
	for tick in 150:
		feature.tick(STEP)
	var smooth := true
	var kept := unit.id
	for changed_cell in [Vector2i(5, 3), Vector2i(3, 3)]:
		var before := unit.position
		context.rooms.remove([changed_cell])
		smooth = smooth and unit.position == before
		for tick in 15:
			before = unit.position
			feature.tick(STEP)
			smooth = smooth and unit.position.distance_to(before) <= MAX_STEP
		context.rooms.place_initial(PEN, [changed_cell])
	_check(smooth and context.food.units.get(kept) == unit, "Splitting, selling and rebuilding preserve the same pig without teleporting it")
	var blocked := context.grid.world_to_cell(unit.position)
	var before_block := unit.position
	context.grid.set_tile(blocked, DungeonGrid.Tile.BEDROCK)
	feature.tick(STEP)
	_check(unit.position.distance_to(before_block) <= MAX_STEP and _conserved(context), "Blocking a pig's position preserves it and permits only speed-bounded escape")
	context.grid.set_tile(blocked, DungeonGrid.Tile.FLOOR)
	if not context.rooms.tiles.has(blocked):
		context.rooms.place_initial(PEN, [blocked])
	feature.tick(STEP)
	_check(context.food.units.get(kept) == unit and _conserved(context), "Reopening blocked terrain recovers without replacing the food identity")
	feature.free()


func _exact_service_pig() -> void:
	var context := _fixture()
	context.rooms.place_initial(PEN, _rectangle(Vector2i(3, 3), Vector2i(6, 1)))
	var anchor := _source(context, Vector2i(3, 3))
	context.food.produce(anchor, PIG, 2)
	var feature := _feature(context)
	var unit: FoodUnitState = context.food.units.values()[0]
	for tick in 250:
		feature.tick(STEP)
		if context.grid.world_to_cell(unit.position) != anchor:
			break
	var actor := context.spawn_creature(EATER, anchor)
	var reservation := context.food.reserve_meal(actor)
	_check(reservation != null and context.food.units.has(reservation.unit_id), "Meal reservation names a specific stable pig identity")
	var selected: FoodUnitState = context.food.units[reservation.unit_id]
	var selected_id := selected.id
	var others: Array[int] = []
	for id in context.food.units:
		if id != selected_id:
			others.append(id)
	if not context.food.meal_ready(reservation):
		_check(context.food.consume(actor) == 0.0, "A nearby eater cannot consume its reserved pig from elsewhere in the pen")
	for tick in 600:
		if context.food.meal_ready(reservation):
			break
		feature.tick(STEP)
	_check(context.food.meal_ready(reservation) and selected.position.distance_to(actor.position) <= FoodEconomy.EAT_DISTANCE, "The reserved pig physically gathers at the eater's service cell")
	var gain := context.food.consume(actor)
	_check(gain > 0.0 and not context.food.units.has(selected_id) and context.food.consume(actor) == 0.0, "Consumption removes exactly the reserved identity once")
	var survivors := true
	for id in others:
		survivors = survivors and context.food.units.has(id)
	_check(survivors and _conserved(context), "Other pigs retain their IDs after a neighboring meal")
	feature.free()


func _shrinking_capacity() -> void:
	var context := _fixture(true)
	context.rooms.place_initial(PEN, _rectangle(Vector2i(3, 3), Vector2i(6, 1)))
	var anchor := _source(context, Vector2i(3, 3))
	context.food.produce(anchor, PIG, 2)
	context.rooms.remove([Vector2i(8, 3)])
	var feature := _feature(context)
	feature.tick(30.0)
	_check(context.food.total_capacity == 1 and context.food.total_units == 2 and context.food.produced_units == 2, "Shrinking a pen retains excess pigs and pauses new births")
	_check(_conserved(context), "Over-capacity stock remains fully accounted for")
	feature.free()


func _mixed_food_components() -> void:
	var context := _fixture()
	var cells := _rectangle(Vector2i(3, 3), Vector2i(6, 1))
	context.rooms.place_initial(PEN, cells)
	var anchor := _source(context, cells[0])
	context.food.produce(anchor, PIG, 1)
	var old: FoodUnitState = context.food.units.values()[0]
	var feature := _feature(context)
	feature.tick(STEP)
	context.rooms.remove(cells)
	context.rooms.place_initial(&"pig_life.other_pen", cells)
	context.food.produce(_source(context, cells[0]), &"pig_life.other_food", 1)
	var retained_stayed_loose := true
	var new_food_moved := false
	for tick in 700:
		feature.tick(STEP)
		retained_stayed_loose = retained_stayed_loose and old.position.distance_to(context.grid.cell_to_world(anchor)) < 0.002
		for unit in context.food.units.values():
			if unit.food_id == &"pig_life.other_food":
				new_food_moved = new_food_moved or context.grid.world_to_cell(unit.position) != anchor
	_check(retained_stayed_loose and new_food_moved, "Shared-cell component caches keep old retained food loose while only the new matching food roams its room")
	_check(context.food.units.has(old.id) and _conserved(context), "Producer-type replacement retains old identity and both food quantities")
	feature.free()


func _newborn_nutrition() -> void:
	var context := _fixture()
	context.rooms.place_initial(PEN, _rectangle(Vector2i(3, 3), Vector2i(3, 1)))
	var anchor := _source(context, Vector2i(3, 3))
	context.food.produce(anchor, PIG, 1)
	var newborn: FoodUnitState = context.food.units.values()[0]
	var actor := context.spawn_creature(EATER, anchor)
	context.food.reserve_meal(actor)
	_check(is_zero_approx(newborn.age_seconds) and is_equal_approx(context.food.consume(actor), 0.65), "Visual growth does not silently introduce maturity-based edibility or different nutrition")
	_check(_conserved(context), "Eating a newborn still consumes one exact physical unit")


func _perimeter_fences() -> void:
	var context := _fixture()
	var first := _rectangle(Vector2i(3, 3), Vector2i(3, 1))
	var second := _rectangle(Vector2i(9, 3), Vector2i(3, 1))
	context.rooms.place_initial(PEN, first)
	context.rooms.place_initial(PEN, second)
	var view := DungeonRoomView.new()
	root.add_child(view)
	view.setup(context)
	await process_frame
	_assert_perimeter(view, context, 2, "Separate pens")
	context.rooms.place_initial(PEN, [Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3)])
	await process_frame
	_assert_perimeter(view, context, 1, "Merged pen")
	context.rooms.remove([Vector2i(7, 3)])
	await process_frame
	_assert_perimeter(view, context, 2, "Split pens")
	view.queue_free()
	await process_frame


func _assert_perimeter(view: Node3D, context: GameContext, gates: int, label: String) -> void:
	var expected := 0
	for cell in context.rooms.tiles:
		for offset: Vector2i in CARDINALS:
			if not context.rooms.tiles.has(cell + offset):
				expected += 1
	var boundaries := view.find_children("PenBoundary_*", "Node3D", true, false)
	var internal := false
	var actual_gates := 0
	for boundary in boundaries:
		var cell: Vector2i = boundary.get_meta("cell")
		var offset: Vector2i = boundary.get_meta("direction")
		internal = internal or context.rooms.tiles.has(cell + offset)
		actual_gates += 1 if boundary.get_meta("gate", false) else 0
	_check(boundaries.size() == expected and not internal, "%s have exactly their outer perimeter and no internal tile fences" % label)
	_check(actual_gates == gates, "%s have one accessible gate per connected enclosure" % label)
