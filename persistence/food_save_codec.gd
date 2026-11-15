class_name FoodSaveCodec
extends RefCounted
## Food identities and ledgers outlive producer rooms and transient reservations.


static func capture(context: GameContext) -> Dictionary:
	var food := context.food
	var units: Array = []
	for unit in food.units.values():
		units.append({"id": unit.id, "cell": SaveReader.encode_cell(unit.cell), "food": String(unit.food_id), "age": unit.age_seconds, "position": SaveReader.encode_position(unit.position), "heading": unit.heading})
	var sources: Array = []
	for at in food.sources:
		var source := food.sources[at]
		sources.append({"cell": SaveReader.encode_cell(at), "food": String(source.food_id), "progress": source.progress, "capacity": source.capacity, "interval": source.production_seconds})
	var stock: Array = []
	for at in food.stock:
		for food_id in food.stock[at]:
			stock.append([at.x, at.y, String(food_id), food.stock[at][food_id]])
	return {"units": units, "sources": sources, "stock": stock, "next_id": food.next_unit_id(), "produced": food.produced_units, "consumed": food.consumed_units, "produced_by_type": _capture_totals(food.produced_by_type), "consumed_by_type": _capture_totals(food.consumed_by_type)}


static func _capture_totals(values: Dictionary) -> Dictionary:
	var result := {}
	for food_id in values:
		result[String(food_id)] = values[food_id]
	return result


static func restore(context: GameContext, raw: Variant, reader: SaveReader) -> void:
	var data := reader.object(raw, "food")
	var food := context.food
	var maximum := 0
	var unit_counts: Dictionary[StringName, int] = {}
	for raw_unit in reader.array(data.get("units"), "food units"):
		var saved := reader.object(raw_unit, "food unit")
		var unit := FoodUnitState.new()
		unit.id = reader.integer(saved.get("id"), "food identity", 1)
		unit.cell = reader.cell(saved.get("cell"), context.grid, "food allocation cell")
		unit.food_id = StringName(reader.text(saved.get("food"), "food definition"))
		var definition := context.registry.get_food(unit.food_id)
		if definition == null:
			reader.fail("Unknown food definition: %s" % unit.food_id)
		unit.age_seconds = reader.number(saved.get("age"), "food age", 0, definition.growth_seconds if definition != null else 0)
		unit.position = reader.position(saved.get("position"), context.grid, "food position")
		unit.heading = reader.number(saved.get("heading"), "food heading")
		if food.units.has(unit.id):
			reader.fail("Duplicate food identity")
		food.units[unit.id] = unit
		maximum = maxi(maximum, unit.id)
		var contents: Dictionary = food.stock.get(unit.cell, {})
		contents[unit.food_id] = int(contents.get(unit.food_id, 0)) + 1
		food.stock[unit.cell] = contents
		unit_counts[unit.food_id] = unit_counts.get(unit.food_id, 0) + 1
	var next_id := reader.integer(data.get("next_id"), "next food identity", 1)
	if next_id <= maximum:
		reader.fail("Next food identity would reuse an existing ID")
	food.restore_unit_sequence(next_id)
	_validate_stock(context, data.get("stock"), reader)
	food.produced_units = reader.integer(data.get("produced"), "food produced")
	food.consumed_units = reader.integer(data.get("consumed"), "food consumed")
	food.produced_by_type = _restore_totals(data.get("produced_by_type"), context, reader)
	food.consumed_by_type = _restore_totals(data.get("consumed_by_type"), context, reader)
	if reader.add(food.total_units, food.consumed_units, "Food ledger") != food.produced_units or _sum(food.produced_by_type, reader) != food.produced_units or _sum(food.consumed_by_type, reader) != food.consumed_units:
		reader.fail("Food ledger totals do not balance")
	for food_id in context.registry.get_foods():
		if reader.add(unit_counts.get(food_id.id, 0), food.consumed_by_type.get(food_id.id, 0), "Food ledger by type") != food.produced_by_type.get(food_id.id, 0):
			reader.fail("Food ledger by type does not balance")
	var source_cells: Dictionary[Vector2i, bool] = {}
	for raw_source in reader.array(data.get("sources"), "food sources"):
		var saved := reader.object(raw_source, "food source")
		var at := reader.cell(saved.get("cell"), context.grid, "food source cell")
		var food_id := StringName(reader.text(saved.get("food"), "producer food type"))
		var source: FoodSourceState = food.sources.get(at)
		if source_cells.has(at) or source == null or source.food_id != food_id:
			reader.fail("Food producer does not match restored room")
			continue
		source_cells[at] = true
		if reader.integer(saved.get("capacity"), "food source capacity") != source.capacity or reader.number(saved.get("interval"), "food production interval", 0) != source.production_seconds:
			reader.fail("Food producer profile does not match current room content")
		source.progress = reader.number(saved.get("progress"), "food production progress", 0, source.production_seconds)
		if source.production_seconds > 0 and source.progress >= source.production_seconds:
			reader.fail("Food production progress exceeds its interval")
	if source_cells.size() != food.sources.size():
		reader.fail("A food producer is missing from the save")


static func _validate_stock(context: GameContext, raw: Variant, reader: SaveReader) -> void:
	var stock: Dictionary[Vector2i, Dictionary] = {}
	for raw_row in reader.array(raw, "food stock"):
		var row := reader.array(raw_row, "food stock entry")
		if row.size() != 4:
			reader.fail("Food stock entry needs cell, type and amount")
			continue
		var at := reader.cell([row[0], row[1]], context.grid, "food stock cell")
		var food_id := StringName(reader.text(row[2], "stock food type"))
		var contents: Dictionary = stock.get(at, {})
		if context.registry.get_food(food_id) == null or contents.has(food_id):
			reader.fail("Unknown or duplicate food stock type")
		contents[food_id] = reader.integer(row[3], "food stock amount", 1)
		stock[at] = contents
	if stock != context.food.stock:
		reader.fail("Physical food identities do not match stock")


static func _restore_totals(raw: Variant, context: GameContext, reader: SaveReader) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var data := reader.object(raw, "food ledger by type")
	for key in data:
		var food_id := StringName(reader.text(key, "food ledger type"))
		if context.registry.get_food(food_id) == null:
			reader.fail("Unknown food ledger type")
		result[food_id] = reader.integer(data[key], "food ledger amount")
	return result


static func _sum(values: Dictionary, reader: SaveReader) -> int:
	var result := 0
	for amount: int in values.values():
		result = reader.add(result, amount, "Food totals")
	return result
