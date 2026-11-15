extends SceneTree
## Independent unbreakable-terrain rules, worker interruptions and Viewport input.

const Layout = preload("res://content/scenarios/foundation_layout.gd")
const WorkerFeature = preload("res://content/features/worker_feature.gd")
const ResidentFeature = preload("res://content/features/resident_feature.gd")
const STEP := 1.0 / 30.0
const TARGET := Vector2i(6, 3)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_grid_contract()
	_test_marking_and_worker_cancellation()
	_test_mineral_replacement(DungeonGrid.Tile.GOLD)
	_test_mineral_replacement(DungeonGrid.Tile.GEM)
	_test_navigation()
	_test_rooms_and_beds()
	_test_portal_access()
	_test_starting_scenario()
	_test_scenario_helpers()
	await _test_raised_targeting_and_viewport_marks()
	for failure in _failures:
		push_error(failure)
	print("BEDROCK RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _fixture(kind: int = DungeonGrid.Tile.ROCK) -> Dictionary:
	var grid := DungeonGrid.new(9, 8)
	for y in range(1, 7):
		for x in range(1, 6):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(TARGET, kind)
	var worker := CreatureDefinition.new()
	worker.id = &"bedrock.worker"
	worker.capabilities = [&"excavate", &"haul"]
	worker.move_speed = 8.0
	var resident := CreatureDefinition.new()
	resident.id = &"bedrock.resident"
	resident.capabilities = [&"rest"]
	resident.portal_population_limit = 1
	var lair := RoomDefinition.new()
	lair.id = &"bedrock.lair"
	lair.tags = [&"lair"]
	var registry := ContentRegistry.new()
	var module := ContentModule.new()
	module.id = &"bedrock.tests"
	module.definitions = [worker, resident, lair]
	_check(registry.register_module(module).is_empty(), "Bedrock fixture content registers")
	var context := GameContext.new(grid, registry)
	context.economy.treasury_cells = [Vector2i(1, 3)]
	context.spawn_creature(worker.id, Vector2i(5, 3))
	var feature := WorkerFeature.new()
	feature.setup(context)
	return {"context": context, "feature": feature, "conserved": true}


func _advance(scene: Dictionary, seconds: float) -> void:
	for index in ceili(seconds / STEP):
		scene.feature.tick(STEP)
		var context: GameContext = scene.context
		if context.economy.accounted_gold(context.actors) != context.economy.initial_gold + context.economy.gem_gold_created:
			scene.conserved = false


func _until(scene: Dictionary, condition: Callable, seconds: float = 20.0) -> bool:
	for index in ceili(seconds / STEP):
		if condition.call():
			return true
		_advance(scene, STEP)
	return condition.call()


func _finish(scene: Dictionary, label: String) -> void:
	_check(scene.conserved, "%s conserves physical mineral supply" % label)
	scene.feature.free()


func _test_grid_contract() -> void:
	_check(DungeonGrid.Tile.ROCK == 0 and DungeonGrid.Tile.FLOOR == 1 and DungeonGrid.Tile.GOLD == 2 and DungeonGrid.Tile.HEART == 3 and DungeonGrid.Tile.PORTAL == 4 and DungeonGrid.Tile.GEM == 5 and DungeonGrid.Tile.BEDROCK == 6, "Bedrock appends a new terrain ID without changing existing IDs")
	var grid := DungeonGrid.new(3, 3)
	_check(grid.set_tile(Vector2i(1, 1), DungeonGrid.Tile.BEDROCK), "Grid accepts the new bedrock terrain")
	_check(not grid.set_tile(Vector2i(-1, 0), DungeonGrid.Tile.BEDROCK) and not grid.set_tile(Vector2i(3, 0), DungeonGrid.Tile.BEDROCK), "Bedrock edits respect grid bounds")
	_check(not grid.set_tile(Vector2i(1, 1), 7) and not grid.set_tile(Vector2i(1, 1), -1), "Terrain edits still reject unknown IDs")
	_check(grid.is_solid(Vector2i(1, 1)) and not grid.is_walkable(Vector2i(1, 1)) and not grid.can_excavate(Vector2i(1, 1)), "Bedrock is solid, unwalkable and ineligible for excavation")
	_check(not grid.is_solid(Vector2i(-1, 0)) and not grid.is_solid(Vector2i(3, 0)), "Outside coordinates are not rendered solid terrain")
	_check(is_equal_approx(grid.surface_height(Vector2i(1, 1)), 2.15), "Bedrock exposes the agreed raised surface height")
	for kind in [DungeonGrid.Tile.ROCK, DungeonGrid.Tile.GOLD, DungeonGrid.Tile.GEM]:
		grid.set_tile(Vector2i(0, 0), kind)
		_check(grid.is_solid(Vector2i(0, 0)) and grid.can_excavate(Vector2i(0, 0)), "Existing excavatable terrain remains solid")
	grid.set_tile(Vector2i(0, 0), DungeonGrid.Tile.FLOOR)
	_check(not grid.is_solid(Vector2i(0, 0)) and grid.is_walkable(Vector2i(0, 0)), "Floor remains open terrain")


func _test_marking_and_worker_cancellation() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	context.grid.set_tile(Vector2i(6, 4), DungeonGrid.Tile.BEDROCK)
	context.mark_excavation([TARGET, Vector2i(6, 4)])
	_check(context.excavation_marks.has(TARGET) and not context.excavation_marks.has(Vector2i(6, 4)), "Authoritative mixed marks reject bedrock while accepting ordinary stone")
	_check(_until(scene, func() -> bool: return context.actors[0].action == &"digging" and context.actors[0].work_progress > 0.1), "Worker begins a real stone job before a terrain replacement")
	context.grid.set_tile(TARGET, DungeonGrid.Tile.BEDROCK)
	_advance(scene, 3.0)
	_check(not context.excavation_marks.has(TARGET) and scene.feature.job_board.active_job_count() == 0, "Replacing active stone with bedrock clears marks and cancels stale jobs")
	_check(context.grid.get_tile(TARGET) == DungeonGrid.Tile.BEDROCK and context.actors[0].work_progress == 0.0, "Canceled excavation cannot dig or change the bedrock")
	context.mark_excavation([TARGET], GameContext.MarkOperation.ADD)
	_advance(scene, 2.0)
	_check(context.excavation_marks.is_empty() and scene.feature.job_board.active_job_count() == 0, "Repeated direct bedrock orders create no pending work")
	_finish(scene, "Stone-to-bedrock cancellation")


func _test_mineral_replacement(kind: int) -> void:
	var scene := _fixture(kind)
	var context: GameContext = scene.context
	context.mark_excavation([TARGET])
	_check(_until(scene, func() -> bool: return context.actors[0].action == &"mining" and context.actors[0].work_progress > 0.1), "Miner begins working before replacement with bedrock")
	context.grid.set_tile(TARGET, DungeonGrid.Tile.BEDROCK)
	_advance(scene, 5.0)
	_check(scene.feature.job_board.active_job_count() == 0 and context.actors[0].carried_gold == 0 and context.economy.stored_gold == 0, "Mineral replacement cancels jobs before any new cargo or stored payout")
	_check(context.economy.gem_gold_created == 0 and not context.excavation_marks.has(TARGET), "Bedrock replacement prevents stale gem production and designations")
	if kind == DungeonGrid.Tile.GOLD:
		_check(context.economy.ground_gold.get(TARGET, 0) == 200 and context.economy.remaining_gold.is_empty(), "Trusted gold-to-bedrock map edit preserves the old seam's remaining supply in the ledger")
		context.grid.set_tile(TARGET, DungeonGrid.Tile.FLOOR)
		_check(_until(scene, func() -> bool: return context.economy.stored_gold == 200), "Preserved seam supply is recoverable after a trusted map edit exposes floor")
	_finish(scene, "Mineral-to-bedrock cancellation")


func _test_navigation() -> void:
	var grid := DungeonGrid.new(7, 7)
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	var start := Vector2i(1, 3)
	var goal := Vector2i(5, 3)
	_check(is_equal_approx(GridPathfinder.path_cost(GridPathfinder.find_path(grid, start, goal)), 4.0), "Navigation fixture begins with a direct route")
	for y in range(1, 6):
		grid.set_tile(Vector2i(3, y), DungeonGrid.Tile.BEDROCK)
	var detour := GridPathfinder.find_path(grid, start, goal)
	var avoids_bedrock := not detour.is_empty()
	for cell in detour:
		avoids_bedrock = avoids_bedrock and grid.get_tile(cell) != DungeonGrid.Tile.BEDROCK
	_check(avoids_bedrock and GridPathfinder.path_cost(detour) > 4.0, "Revision-aware A* detours around a newly inserted bedrock barrier")
	var corner := DungeonGrid.new(4, 4)
	corner.set_tile(Vector2i(1, 1), DungeonGrid.Tile.FLOOR)
	corner.set_tile(Vector2i(2, 2), DungeonGrid.Tile.FLOOR)
	corner.set_tile(Vector2i(1, 2), DungeonGrid.Tile.FLOOR)
	corner.set_tile(Vector2i(2, 1), DungeonGrid.Tile.BEDROCK)
	_check(not GridPathfinder.can_step(corner, Vector2i(1, 1), Vector2i(2, 2)), "A single bedrock flank forbids diagonal corner cutting")
	_check(GridPathfinder.find_path(corner, Vector2i(1, 1), Vector2i(2, 2)).size() == 3, "Strict corner navigation uses the open cardinal detour")
	corner.set_tile(Vector2i(1, 2), DungeonGrid.Tile.BEDROCK)
	_check(GridPathfinder.find_path(corner, Vector2i(1, 1), Vector2i(2, 2)).is_empty(), "Bedrock flanks can completely seal a diagonal-only gap")
	_check(GridPathfinder.find_path(corner, Vector2i(1, 1), Vector2i(2, 1)).is_empty(), "Bedrock cannot be a path endpoint")


func _test_rooms_and_beds() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	context.grid.set_tile(TARGET, DungeonGrid.Tile.BEDROCK)
	var quote := context.rooms.quote_build(&"bedrock.lair", [TARGET])
	_check(not quote.valid and quote.add.is_empty() and quote.blocked == [TARGET], "Room placement rejects bedrock with an explicit blocked preview")
	_check(not context.rooms.build(&"bedrock.lair", [TARGET]).success, "Direct room commands cannot build on bedrock")
	var cell := Vector2i(4, 4)
	context.rooms.place_initial(&"bedrock.lair", [cell])
	var resident := context.spawn_creature(&"bedrock.resident", cell)
	var definition := context.registry.get_creature(resident.definition_id)
	var bed := context.beds.reserve(resident, definition)
	_check(bed != null, "Bed safety fixture reserves a real Lair footprint")
	context.grid.set_tile(cell, DungeonGrid.Tile.BEDROCK)
	_check(not context.rooms.tiles.has(cell) and context.beds.get_bed(resident.id) == null, "Replacing a room floor with bedrock removes its room and pending bed")
	_check(not context.beds.establish(resident) and not context.beds.can_place(cell, Vector2i.ONE, &"lair"), "A blocked footprint cannot establish a stale bed or admit another")
	_finish(scene, "Room and bed replacement")


func _test_portal_access() -> void:
	var scene := _fixture()
	var context: GameContext = scene.context
	context.actors.clear()
	context.grid.set_tile(Vector2i(1, 3), DungeonGrid.Tile.PORTAL)
	context.grid.set_tile(Vector2i(7, 3), DungeonGrid.Tile.FLOOR)
	context.rooms.place_initial(&"bedrock.lair", [Vector2i(7, 3)])
	for y in context.grid.height:
		context.grid.set_tile(Vector2i(6, y), DungeonGrid.Tile.BEDROCK)
	var resident := ResidentFeature.new()
	resident.setup(context)
	for index in 180:
		resident.tick(STEP)
	_check(context.actors.is_empty(), "A bedrock barrier prevents portal attraction to unreachable Lair space")
	context.grid.set_tile(Vector2i(6, 3), DungeonGrid.Tile.FLOOR)
	for index in 90:
		resident.tick(STEP)
	_check(context.actors.size() == 1, "An intentional opening in scenario bedrock restores the portal route")
	resident.free()
	_finish(scene, "Bedrock-protected portal access")


func _test_starting_scenario() -> void:
	var grid := Layout.create()
	var sealed := true
	for x in grid.width:
		sealed = sealed and grid.get_tile(Vector2i(x, 0)) == DungeonGrid.Tile.BEDROCK and grid.get_tile(Vector2i(x, grid.height - 1)) == DungeonGrid.Tile.BEDROCK
	for y in grid.height:
		sealed = sealed and grid.get_tile(Vector2i(0, y)) == DungeonGrid.Tile.BEDROCK and grid.get_tile(Vector2i(grid.width - 1, y)) == DungeonGrid.Tile.BEDROCK
	_check(sealed, "The entire starting map border is closed with bedrock")
	_check(grid.cells_of_type(DungeonGrid.Tile.HEART) == [Vector2i(14, 15)] and grid.cells_of_type(DungeonGrid.Tile.PORTAL) == [Vector2i(14, 6)], "Bedrock scenario keeps the original Heart and separate portal")
	var visited: Dictionary[Vector2i, bool] = {}
	var queue: Array[Vector2i] = [Vector2i(12, 16)]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if grid.is_walkable(next) and not visited.has(next):
				queue.append(next)
	_check(visited.size() == grid.cells_of_type(DungeonGrid.Tile.FLOOR).size() + 1, "Starting chamber, workers and portal remain connected")
	var minerals: Array[Vector2i] = grid.cells_of_type(DungeonGrid.Tile.GOLD)
	minerals.append_array(grid.cells_of_type(DungeonGrid.Tile.GEM))
	var accessible := minerals.size() == 8
	for mineral in minerals:
		var has_face := false
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			has_face = has_face or visited.has(mineral + offset)
		accessible = accessible and has_face
	_check(accessible, "All six starting gold seams and both gem seams retain a reachable mining face")
	var interior_pattern := false
	for cell in grid.cells_of_type(DungeonGrid.Tile.BEDROCK):
		interior_pattern = interior_pattern or (cell.x > 0 and cell.y > 0 and cell.x < grid.width - 1 and cell.y < grid.height - 1)
	_check(interior_pattern, "Starting scenario demonstrates bedrock as an internal pattern as well as a border")


func _test_raised_targeting_and_viewport_marks() -> void:
	var grid := DungeonGrid.new(7, 7)
	for y in grid.height:
		for x in grid.width:
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	var rock := Vector2i(2, 3)
	var bedrock := Vector2i(3, 3)
	var gold := Vector2i(4, 3)
	grid.set_tile(rock, DungeonGrid.Tile.ROCK)
	grid.set_tile(bedrock, DungeonGrid.Tile.BEDROCK)
	grid.set_tile(gold, DungeonGrid.Tile.GOLD)
	var context := GameContext.new(grid, ContentRegistry.new())
	var controller := KeeperController.new()
	root.add_child(controller)
	controller.setup(context)
	controller.set_process(false)
	controller.ui_hit_test = func(_point: Vector2) -> bool: return false
	await process_frame
	var center := grid.cell_to_world(bedrock)
	for yaw in [0.0, 1.0, 2.2, 4.3]:
		for distance in [12.0, 31.0, 65.0]:
			controller.camera.position = center + Vector3(sin(yaw) * 0.6, 0.8, cos(yaw) * 0.6) * distance
			controller.camera.look_at(center)
			var top := center + Vector3.UP * grid.surface_height(bedrock)
			_check(controller.get_target_cell(controller.camera.unproject_position(top)) == bedrock, "Raised bedrock surface round-trips through perspective nearest-hit targeting")
	controller.camera.position = Vector3(6, 24, 12)
	controller.camera.look_at(center)
	var screen := controller.camera.unproject_position(center + Vector3.UP * grid.surface_height(bedrock))
	_check(screen.distance_to(controller.camera.unproject_position(center)) > 10.0, "Targeting projection uses raised bedrock height rather than floor height")
	_mouse(screen, true)
	_mouse(screen, false)
	_check(context.excavation_marks.is_empty(), "Viewport click on bedrock creates no excavation mark")
	var first := controller.camera.unproject_position(grid.cell_to_world(rock) + Vector3.UP * grid.surface_height(rock))
	var last := controller.camera.unproject_position(grid.cell_to_world(gold) + Vector3.UP * grid.surface_height(gold))
	_mouse(first, true)
	var motion := InputEventMouseMotion.new()
	motion.position = last
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	var preview := controller.get_preview_changes()
	_check(preview.add.size() == 2 and not preview.add.has(bedrock), "Actual mixed drag preview skips the bedrock between mineral tiles")
	_mouse(last, false)
	_check(context.excavation_marks.size() == 2 and context.excavation_marks.has(rock) and context.excavation_marks.has(gold) and not context.excavation_marks.has(bedrock), "Viewport drag marks ordinary terrain while bedrock remains protected")
	controller.queue_free()
	await process_frame


func _test_scenario_helpers() -> void:
	var grid := DungeonGrid.new(9, 7)
	var revision := grid.navigation_revision
	_check(not Layout.paint_bedrock(grid, [Vector2i(2, 2), Vector2i(9, 3)]) and grid.navigation_revision == revision and grid.cells_of_type(DungeonGrid.Tile.BEDROCK).is_empty(), "Invalid pattern coordinates reject the whole authoring edit without partial mutation")
	var pattern: Array[Vector2i] = [Vector2i(2, 2), Vector2i(5, 3), Vector2i(5, 3), Vector2i(6, 4)]
	_check(Layout.paint_bedrock(grid, pattern) and grid.cells_of_type(DungeonGrid.Tile.BEDROCK).size() == 3 and grid.navigation_revision == revision + 3, "Arbitrary nonborder patterns accept disconnected cells and duplicate cells idempotently")
	_check(not Layout.paint_bedrock(null, pattern) and not Layout.add_bedrock_border(null) and not Layout.add_bedrock_border(grid, 0) and grid.navigation_revision == revision + 3, "Null grids and zero-width borders reject without altering terrain")
	var border := DungeonGrid.new(9, 7)
	_check(Layout.add_bedrock_border(border, 2), "Rectangular scenario accepts a two-tile bedrock border")
	var correct := true
	for y in border.height:
		for x in border.width:
			var expected := DungeonGrid.Tile.BEDROCK if x < 2 or x >= 7 or y < 2 or y >= 5 else DungeonGrid.Tile.ROCK
			correct = correct and border.get_tile(Vector2i(x, y)) == expected
	_check(correct, "Thick rectangular borders cover exactly their edge bands and preserve interior terrain")


func _mouse(screen: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
