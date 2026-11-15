class_name FoodEconomy
extends RefCounted
## Physical stock and exclusive meal reservations; views never create food.

signal changed

const EAT_DISTANCE := 0.12
var stock: Dictionary[Vector2i, Dictionary] = {}
var sources: Dictionary[Vector2i, FoodSourceState] = {}
var units: Dictionary[int, FoodUnitState] = {}
var _next_unit_id: int = 1
var reservations: Dictionary[int, FoodReservation] = {}
var produced_units: int = 0
var consumed_units: int = 0
var produced_by_type: Dictionary[StringName, int] = {}
var consumed_by_type: Dictionary[StringName, int] = {}
var total_units: int:
	get:
		var total := 0
		for cell in stock:
			total += total_at(cell)
		return total
var total_capacity: int:
	get:
		var total := 0
		for source in sources.values():
			total += source.capacity
		return total
var _feeding_cells: Dictionary[Vector2i, int] = {}
var _grid: DungeonGrid
var _rooms: DungeonRooms
var _registry: ContentRegistry


func next_unit_id() -> int:
	return _next_unit_id


func restore_unit_sequence(next_id: int) -> void:
	_next_unit_id = next_id


func _init(grid: DungeonGrid, rooms: DungeonRooms, registry: ContentRegistry) -> void:
	_grid = grid
	_rooms = rooms
	_registry = registry
	_rooms.changed.connect(configure_sources)
	_grid.tile_changed.connect(_on_terrain_changed)
	configure_sources()


func get_stock(cell: Vector2i, food_id: StringName) -> int:
	var contents: Dictionary = stock.get(cell, {})
	return int(contents.get(food_id, 0))


func total_at(cell: Vector2i) -> int:
	var total := 0
	var contents: Dictionary = stock.get(cell, {})
	for amount: int in contents.values():
		total += amount
	return total


func accounted_units() -> int:
	return total_units + consumed_units


func configure_sources() -> void:
	var next: Dictionary[Vector2i, FoodSourceState] = {}
	if _registry != null:
		for group in _rooms.get_rooms():
			var definition := _registry.get_room(group.definition_id)
			if definition == null or definition.food_capacity_per_tile <= 0 or _registry.get_food(definition.food_type) == null:
				continue
			if definition.food_tiles_per_unit > 0:
				var capacity := floori(float(group.cells.size()) / definition.food_tiles_per_unit) if _fits_minimum(group.cells, definition.food_minimum_size) else 0
				_configure_source(next, group.cells[0], group.cells, definition, capacity)
			else:
				for cell in group.cells:
					_configure_source(next, cell, [cell], definition, definition.food_capacity_per_tile)
	sources = next
	# Removed pens stop producing. Existing stock remains physically at its cell,
	# even if another room is built there or a trusted terrain edit blocks it.
	_invalidate_reservations()
	changed.emit()


func _configure_source(next: Dictionary[Vector2i, FoodSourceState], anchor: Vector2i, cells: Array[Vector2i], definition: RoomDefinition, capacity: int) -> void:
	var source: FoodSourceState = sources.get(anchor)
	if source == null or source.food_id != definition.food_type:
		source = FoodSourceState.new()
		source.food_id = definition.food_type
	if not is_equal_approx(source.production_seconds, definition.food_production_seconds):
		source.progress = 0.0
	source.capacity = capacity
	source.cells = cells.duplicate()
	source.production_seconds = definition.food_production_seconds
	next[anchor] = source


func _fits_minimum(cells: Array[Vector2i], size: Vector2i) -> bool:
	if size.x * size.y > cells.size():
		return false
	var membership: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		membership[cell] = true
	for dimensions in [size, Vector2i(size.y, size.x)]:
		for anchor in cells:
			var fits := true
			for y in dimensions.y:
				for x in dimensions.x:
					if not membership.has(anchor + Vector2i(x, y)):
						fits = false
			if fits:
				return true
	return false


func source_free_capacity(cell: Vector2i) -> int:
	var source: FoodSourceState = sources.get(cell)
	if source == null:
		return 0
	var occupied := 0
	for member in source.cells:
		occupied += total_at(member)
	return maxi(0, source.capacity - occupied)


func age_units(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for unit in units.values():
		var definition := _registry.get_food(unit.food_id)
		if definition != null:
			unit.age_seconds = minf(definition.growth_seconds, unit.age_seconds + delta)


func produce(cell: Vector2i, food_id: StringName, amount: int) -> int:
	var source: FoodSourceState = sources.get(cell)
	if amount <= 0 or source == null or source.food_id != food_id or not _grid.is_walkable(cell):
		return 0
	var created := mini(amount, source_free_capacity(cell))
	if created <= 0:
		return 0
	var contents: Dictionary = stock.get(cell, {})
	contents[food_id] = get_stock(cell, food_id) + created
	stock[cell] = contents
	for index in created:
		var unit := FoodUnitState.new()
		unit.id = _next_unit_id
		_next_unit_id += 1
		unit.cell = cell
		unit.food_id = food_id
		unit.position = _grid.cell_to_world(cell)
		units[unit.id] = unit
	produced_units += created
	produced_by_type[food_id] = produced_by_type.get(food_id, 0) + created
	changed.emit()
	return created


func reserve_meal(actor: CreatureState) -> FoodReservation:
	var definition := _eater_definition(actor)
	if definition == null:
		if actor != null:
			release(actor.id)
		return null
	if not actor.position.is_finite():
		release(actor.id)
		return null
	var from := _grid.world_to_cell(actor.position)
	var existing := get_reservation(actor.id)
	if existing != null:
		if is_valid(existing) and _accepts(definition, existing.food_id) and not GridPathfinder.find_path(_grid, from, existing.cell).is_empty():
			return existing
		release(actor.id)
	var best: FoodReservation
	var best_cost := INF
	var cells := stock.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in cells:
		if _feeding_cells.has(cell) or not _grid.is_walkable(cell):
			continue
		var path := GridPathfinder.find_path(_grid, from, cell)
		if path.is_empty() or GridPathfinder.path_cost(path) >= best_cost:
			continue
		for food_id: StringName in stock[cell]:
			if get_stock(cell, food_id) <= 0 or not _accepts(definition, food_id):
				continue
			var unit_id := _find_unit(cell, food_id)
			if unit_id < 0:
				continue
			best = FoodReservation.new()
			best.actor_id = actor.id
			best.cell = cell
			best.food_id = food_id
			best.unit_id = unit_id
			best_cost = GridPathfinder.path_cost(path)
			break
	if best != null:
		reservations[actor.id] = best
		_feeding_cells[best.cell] = actor.id
		changed.emit()
	return best


func get_reservation(actor_id: int) -> FoodReservation:
	return reservations.get(actor_id)


func is_valid(reservation: FoodReservation) -> bool:
	if reservation == null or reservations.get(reservation.actor_id) != reservation or _feeding_cells.get(reservation.cell, -1) != reservation.actor_id or not _grid.is_walkable(reservation.cell):
		return false
	var unit: FoodUnitState = units.get(reservation.unit_id)
	return unit != null and unit.cell == reservation.cell and unit.food_id == reservation.food_id and get_stock(reservation.cell, reservation.food_id) > 0 and _unit_can_return(unit)


func meal_ready(reservation: FoodReservation) -> bool:
	return is_valid(reservation) and units[reservation.unit_id].position.distance_to(_grid.cell_to_world(reservation.cell)) <= EAT_DISTANCE


func _find_unit(cell: Vector2i, food_id: StringName) -> int:
	for unit in units.values():
		if unit.cell == cell and unit.food_id == food_id and _unit_can_return(unit):
			return unit.id
	return -1


func _unit_can_return(unit: FoodUnitState) -> bool:
	return unit.position.is_finite() and not GridPathfinder.find_path(_grid, _grid.world_to_cell(unit.position), unit.cell).is_empty()


func consume(actor: CreatureState) -> float:
	var definition := _eater_definition(actor)
	if definition == null or not actor.position.is_finite():
		return 0.0
	var reservation := get_reservation(actor.id)
	if not meal_ready(reservation) or not _accepts(definition, reservation.food_id) or actor.position.distance_to(_grid.cell_to_world(reservation.cell)) > EAT_DISTANCE:
		return 0.0
	var food := _registry.get_food(reservation.food_id)
	var contents: Dictionary = stock[reservation.cell]
	contents[reservation.food_id] -= 1
	if contents[reservation.food_id] == 0:
		contents.erase(reservation.food_id)
	if contents.is_empty():
		stock.erase(reservation.cell)
	units.erase(reservation.unit_id)
	consumed_units += 1
	consumed_by_type[reservation.food_id] = consumed_by_type.get(reservation.food_id, 0) + 1
	# Releasing also publishes the quantity change, only after the complete debit.
	release(actor.id)
	return food.nutrition_per_unit / float(definition.food_per_meal)


func release(actor_id: int) -> void:
	var reservation := get_reservation(actor_id)
	if reservation == null:
		return
	if _feeding_cells.get(reservation.cell, -1) == actor_id:
		_feeding_cells.erase(reservation.cell)
	reservations.erase(actor_id)
	changed.emit()


func prune(actors: Array[CreatureState]) -> void:
	var live: Dictionary[int, CreatureState] = {}
	for actor in actors:
		live[actor.id] = actor
	for actor_id in reservations.keys():
		var definition := _eater_definition(live.get(actor_id))
		if definition == null or not is_valid(reservations[actor_id]) or not _accepts(definition, reservations[actor_id].food_id):
			release(actor_id)


func _eater_definition(actor: CreatureState) -> CreatureDefinition:
	if actor == null or actor.is_held or actor.id <= 0 or _registry == null:
		return null
	var definition := _registry.get_creature(actor.definition_id)
	return definition if definition != null and &"eat" in definition.capabilities else null


func _accepts(creature: CreatureDefinition, food_id: StringName) -> bool:
	var food := _registry.get_food(food_id)
	if food == null:
		return false
	if creature.food_tags.is_empty():
		return true
	for tag in creature.food_tags:
		if tag in food.tags:
			return true
	return false


func _invalidate_reservations() -> void:
	for actor_id in reservations.keys():
		if not is_valid(reservations[actor_id]):
			release(actor_id)


func _on_terrain_changed(_cell: Vector2i) -> void:
	_invalidate_reservations()
