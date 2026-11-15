extends SceneTree
## Actual room input, visible growth, whole-pen movement and local food service.

var _app: Node3D
var _context: GameContext
var _keeper: KeeperController
var _hud: DungeonHUD
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _run() -> void:
	_app = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_app.set("starting_gold", 0)
	root.add_child(_app)
	_app.set_physics_process(false)
	_context = _app.context
	_keeper = _app.controller
	_keeper.set_process(false)
	for child in _app.get_children():
		if child is DungeonHUD:
			_hud = child
	# Finite-gold fixture only: food, maturity and satiety use normal simulation.
	var mined := 0
	for cell in _context.grid.cells_of_type(DungeonGrid.Tile.GOLD):
		if mined >= 800:
			break
		mined += _context.economy.mine(cell, 200)
	_check(_context.economy.deposit(Vector2i(16, 18), 500) and _context.economy.deposit(Vector2i(17, 18), 300), "Fixture funds are deposited finite seam gold")
	_check(await _build_area(&"foundation.pig_pen", Vector2i(17, 14), Vector2i(19, 14)), "Viewport builds a minimum three-by-one Pig Pen")
	_keeper.exit_construction()
	_camera(Vector2i(18, 14), 12.0, -0.6, 0.8)
	await _capture("pig-pen-minimum-3x1")
	_check(_context.food.total_capacity == 1 and _context.food.total_units == 0, "A minimum three-tile strip supports one pig and starts empty")
	_check(await _build_area(&"foundation.pig_pen", Vector2i(17, 15), Vector2i(19, 15)), "Viewport extends the same connected Pig Pen")
	_keeper.exit_construction()
	_camera(Vector2i(18, 14), 12.0, -0.6, 0.8)
	await _capture("pig-pen-empty")
	_check(_context.food.total_capacity == 2 and _context.food.total_units == 0, "Six connected tiles support two pigs, with no free initial stock")
	var boundaries := _app.find_children("PenBoundary_*", "Node3D", true, false)
	var perimeter_only := not boundaries.is_empty()
	var gates := 0
	for boundary in boundaries:
		var cell: Vector2i = boundary.get_meta("cell")
		var direction: Vector2i = boundary.get_meta("direction")
		perimeter_only = perimeter_only and _context.rooms.tiles.get(cell + direction, &"") != &"foundation.pig_pen"
		gates += 1 if boundary.get_meta("gate") else 0
	_check(perimeter_only and gates == 1, "Fences surround the connected perimeter with one clear gate and no internal dividers")
	var tracked_id := -1
	var visited: Dictionary[Vector2i, bool] = {}
	var newborn := false
	var growing := false
	var adult := false
	var speed_safe := true
	var inside := true
	var conserved := true
	var identity := 0
	for tick in 1800:
		var before: Dictionary[int, Vector3] = {}
		for unit in _context.food.units.values():
			before[unit.id] = unit.position
		_app.call("_physics_process", 1.0 / 30.0)
		conserved = conserved and _context.food.accounted_units() == _context.food.produced_units
		for unit in _context.food.units.values():
			if before.has(unit.id):
				speed_safe = speed_safe and before[unit.id].distance_to(unit.position) <= FoodRoaming.WALK_SPEED / 30.0 + 0.0001
			inside = inside and _context.rooms.tiles.get(_context.grid.world_to_cell(unit.position), &"") == &"foundation.pig_pen"
			if tracked_id < 0:
				tracked_id = unit.id
			if unit.id != tracked_id:
				continue
			visited[_context.grid.world_to_cell(unit.position)] = true
			if not newborn:
				await _capture("piglet-newborn")
				var node := _unit_node(unit.id)
				newborn = node != null and node.scale.x >= 0.35 and node.scale.x <= 0.42
				identity = node.get_instance_id() if node != null else 0
			if not growing and unit.age_seconds >= 14.0:
				await _capture("piglet-growing")
				var node := _unit_node(unit.id)
				growing = node != null and node.get_instance_id() == identity and node.scale.x > 0.6 and node.scale.x < 0.9
			if not adult and unit.age_seconds >= 30.0:
				await _capture("pig-grown-adult")
				var node := _unit_node(unit.id)
				adult = node != null and node.get_instance_id() == identity and is_equal_approx(node.scale.x, 1.0)
		if tick % 30 == 0:
			await process_frame
	_check(newborn and growing and adult, "The same stable food identity visibly grows from newborn through juvenile to adult over simulation time")
	_check(visited.size() >= 3 and speed_safe and inside, "Pigs cross multiple connected pen tiles at bounded world speed while remaining inside")
	_check(_context.food.total_units == 2 and _food_views().size() == 2, "Whole pen reaches its area-based capacity of two physical pigs")
	_camera(Vector2i(18, 14), 11.0, -0.6, 0.8)
	await _capture("pig-pen-full")
	await _capture("cave-pigs-roaming-a")
	var roaming_before := _context.food.units[tracked_id].position
	for tick in 90:
		_app.call("_physics_process", 1.0 / 30.0)
		if tick % 10 == 0:
			await process_frame
	await _capture("cave-pigs-roaming-b")
	_check(roaming_before.distance_to(_context.food.units[tracked_id].position) > 0.25, "Two rendered frames show actual pen-wide traversal")
	_context.food.changed.emit()
	await process_frame
	await process_frame
	_check(_unit_node(tracked_id).get_instance_id() == identity, "Reservation-only refresh does not rebuild or reset a pig")
	_check(await _build_area(&"foundation.lair", Vector2i(9, 11), Vector2i(11, 11)), "A Lair enables normal resident arrival after growth observation")
	_keeper.exit_construction()
	_hud.select_tab(&"creatures")
	var resident: CreatureState
	var meals := 0
	var trips := 0
	var was_feeding := false
	var slept := false
	var woke := false
	var was_sleeping := false
	var eating := false
	var returned := false
	var local_removal := true
	var quantity_views := true
	for tick in 18000:
		var old: Dictionary[int, Vector3] = {}
		for unit in _context.food.units.values():
			old[unit.id] = unit.position
		var previous_consumed := _context.food.consumed_units
		_app.call("_physics_process", 1.0 / 30.0)
		conserved = conserved and _context.food.accounted_units() == _context.food.produced_units
		conserved = conserved and _context.economy.accounted_gold(_context.actors) == _context.economy.initial_gold
		if resident == null:
			for actor in _context.actors:
				if actor.definition_id == &"foundation.grubbin":
					resident = actor
		if resident != null:
			var reservation := _context.food.get_reservation(resident.id)
			if reservation != null and not _context.food.meal_ready(reservation) and not returned:
				returned = true
				_camera(Vector2i(18, 14), 12.0, -0.6, 0.85)
				await _capture("pig-returning-to-feed")
			if resident.food_requested and not was_feeding:
				trips += 1
			was_feeding = resident.food_requested
			var sleeping := resident.action == &"sleeping"
			if sleeping and not slept:
				slept = true
				_camera(Vector2i(10, 11), 12.0, 0.3, 0.85)
				await _capture("food-loop-resting")
			woke = woke or (was_sleeping and not sleeping)
			was_sleeping = sleeping
			if resident.action == &"eating":
				local_removal = local_removal and reservation != null and _context.food.meal_ready(reservation)
				if not eating:
					eating = true
					_camera(Vector2i(18, 14), 10.0, -0.55, 1.0)
					await _capture("grubbin-eating")
		if _context.food.consumed_units > previous_consumed:
			meals += _context.food.consumed_units - previous_consumed
			for id in old:
				if not _context.food.units.has(id):
					# The pig could move at most one physics step before consumption.
					local_removal = local_removal and old[id].distance_to(_context.grid.cell_to_world(Vector2i(17, 14))) <= FoodEconomy.EAT_DISTANCE + FoodRoaming.WALK_SPEED / 30.0 + 0.001
			await process_frame
			await process_frame
			quantity_views = quantity_views and _food_views().size() == _context.food.total_units
		if meals >= 3 and trips >= 2 and slept and woke:
			break
	_check(meals >= 3 and trips >= 2 and eating and slept and woke, "Natural hunger causes repeated meals alongside rest cycles")
	_check(returned and local_removal, "Exact reserved pigs return before eating and never disappear remotely")
	_check(quantity_views and _context.actors.size() == 4, "Physical pig count follows the ledger without becoming resident actors")
	var retained_ids := _context.food.units.keys()
	var pen: Array[Vector2i] = []
	for y in range(14, 16):
		for x in range(17, 20):
			pen.append(Vector2i(x, y))
	_context.rooms.remove(pen)
	var retained := not retained_ids.is_empty()
	for id in retained_ids:
		retained = retained and _context.food.units.has(id)
	_camera(Vector2i(18, 14), 12.0, -0.55, 0.8)
	await _capture("pig-pen-sold-stock-retained")
	_check(retained and _context.food.sources.is_empty(), "Selling the producer retains existing pigs and removes its source")
	var produced_before_sale := _context.food.produced_units
	for tick in 450:
		_app.call("_physics_process", 1.0 / 30.0)
		if tick % 30 == 0:
			await process_frame
	_check(_context.food.produced_units == produced_before_sale, "Sold pen produces no births while retained pigs remain edible")
	conserved = conserved and _context.food.accounted_units() == _context.food.produced_units
	_check(conserved, "Food and gold ledgers remain conserved through growth, movement, feeding and sale")
	_hud.select_tab(&"rooms")
	_camera(Vector2i(14, 14), 30.0, -0.4, 1.0)
	await _capture("food-loop-overview")
	for failure in _failures:
		push_error(failure)
	print("FOOD RENDER RESULT: %d checks, %d failures | visited=%d meals=%d trips=%d produced=%d consumed=%d stock=%d" % [_checks, _failures.size(), visited.size(), meals, trips, _context.food.produced_units, _context.food.consumed_units, _context.food.total_units])
	_app.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _unit_node(id: int) -> Node3D:
	return _app.find_child("FoodUnit_%d" % id, true, false) as Node3D


func _food_views() -> Array[Node]:
	return _app.find_children("FoodUnit_*", "Node3D", true, false)


func _camera(cell: Vector2i, distance: float, yaw: float, pitch: float) -> void:
	_keeper.focus = _context.grid.cell_to_world(cell)
	_keeper.distance = distance
	_keeper.yaw = yaw
	_keeper.pitch = pitch
	_keeper.call("_update_camera")


func _build_area(id: StringName, first: Vector2i, last: Vector2i) -> bool:
	_hud.select_tab(&"rooms")
	_camera(Vector2i((first.x + last.x) / 2, (first.y + last.y) / 2), 20.0, -0.3, 1.05)
	_keeper.set_build_room(id)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = _keeper.camera.unproject_position(_context.grid.cell_to_world(first))
	event.pressed = true
	root.push_input(event, true)
	var motion := InputEventMouseMotion.new()
	motion.position = _keeper.camera.unproject_position(_context.grid.cell_to_world(last))
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	var valid: bool = _keeper.get_preview_changes().get("valid", false)
	event = event.duplicate()
	event.position = motion.position
	event.pressed = false
	root.push_input(event, true)
	return valid and _context.rooms.tiles.get(first, &"") == id and _context.rooms.tiles.get(last, &"") == id


func _capture(label: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	_check(root.get_texture().get_image().save_png("res://artifacts/%s.png" % label) == OK, "Capture %s saves" % label)
