extends SceneTree

const Layout = preload("res://content/scenarios/foundation_layout.gd")
const Wander = preload("res://content/features/wander_feature.gd")
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_grid()
	_test_modules()
	_test_simulation()
	_test_selection()
	for failure in _failures:
		push_error(failure)
	print("TEST RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _test_grid() -> void:
	var grid := DungeonGrid.new(5, 4)
	_check(not grid.set_tile(Vector2i(-1, 0), DungeonGrid.Tile.FLOOR), "Reject out of bounds edits")
	_check(not grid.set_tile(Vector2i(0, 0), 99), "Reject unknown tile type")
	_check(not grid.is_walkable(Vector2i(5, 4)), "Outside grid never walkable")
	grid.set_tile(Vector2i(2, 2), DungeonGrid.Tile.FLOOR)
	_check(grid.is_walkable(Vector2i(2, 2)), "Floor walkable")
	_check(grid.world_to_cell(grid.cell_to_world(Vector2i(2, 3))) == Vector2i(2, 3), "Tile coordinate round trip")
	_check(grid.world_to_cell(Vector3(-1.1, 0, 0)).x == -1, "Negative world edge stays outside")
	_check(grid.cells_of_type(DungeonGrid.Tile.FLOOR).size() == 1, "Terrain query counts exact matches")
	var scenario := Layout.create()
	_check(scenario.cells_of_type(DungeonGrid.Tile.HEART).size() == 1, "Exactly one central Heart")
	_check(scenario.cells_of_type(DungeonGrid.Tile.PORTAL).size() == 1, "Exactly one separate portal")
	# Flood the floor and ensure all starting open areas connect.
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [Vector2i(12, 16)]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if visited.has(cell):
			continue
		visited[cell] = true
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if scenario.is_walkable(neighbor) and not visited.has(neighbor):
				queue.append(neighbor)
	var expected := scenario.cells_of_type(DungeonGrid.Tile.FLOOR).size() + 1
	_check(visited.size() == expected, "All starting walkable floor and portal connected")


func _test_modules() -> void:
	var registry := ContentRegistry.new()
	var base := load("res://content/modules/foundation.tres") as ContentModule
	_check(registry.register_module(base).is_empty(), "Built-in manifest loads")
	_check(not registry.register_module(base).is_empty(), "Duplicate module rejected")
	var creature := CreatureDefinition.new()
	creature.id = &"test.mossling"
	creature.display_name = "Test Mossling"
	var room := RoomDefinition.new()
	room.id = &"test.den"
	room.display_name = "Test Den"
	var module := ContentModule.new()
	module.id = &"test.extension"
	module.definitions = [creature, room]
	module.feature_scripts = [preload("res://tests/fixtures/probe_feature.gd")]
	_check(registry.register_module(module).is_empty(), "New creature, room and mechanic register without core edits")
	_check(registry.get_creature(creature.id) == creature and registry.get_room(room.id) == room, "New definitions resolve by stable ID")
	var context := GameContext.new(Layout.create(), registry)
	_check(context.spawn_creature(creature.id, Vector2i(12, 16)) != null, "Extension creature can spawn through existing API")
	_check(context.spawn_creature(&"unknown", Vector2i(12, 16)) == null, "Missing creature reference rejected")
	_check(context.spawn_creature(creature.id, Vector2i(0, 0)) == null, "Solid rock spawn rejected")
	var feature := module.feature_scripts[0].new() as GameFeature
	feature.setup(context)
	feature.tick(0.1)
	_check(feature.tick_count == 1 and feature.context == context, "Extension feature lifecycle receives context and ticks")
	feature.free()
	var invalid := ContentModule.new()
	invalid.id = &"test.invalid"
	var fresh := RoomDefinition.new()
	fresh.id = &"test.not_committed"
	invalid.definitions = [fresh, creature]
	_check(not registry.register_module(invalid).is_empty(), "Duplicate definition rejected")
	_check(registry.get_room(fresh.id) == null, "Failed registration rolls back whole module")
	invalid.definitions = []
	invalid.feature_scripts = [preload("res://content/scenarios/foundation_layout.gd")]
	_check(not registry.register_module(invalid).is_empty(), "Non-feature script rejected")
	var bad := CreatureDefinition.new()
	bad.id = &"test.bad"
	bad.move_speed = NAN
	_check(not bad.validation_error().is_empty(), "Nonfinite movement rejected")


func _test_simulation() -> void:
	var registry := ContentRegistry.new()
	registry.register_module(load("res://content/modules/foundation.tres"))
	var context := GameContext.new(Layout.create(), registry)
	var actor := context.spawn_creature(&"foundation.imp", Vector2i(12, 16))
	var start := actor.position
	var feature := Wander.new()
	feature.setup(context)
	var valid := true
	for i in 3600:
		feature.tick(1.0 / 60.0)
		valid = valid and context.grid.is_walkable(context.grid.world_to_cell(actor.position))
	_check(valid, "Wandering remains on open floor for 3600 ticks")
	_check(actor.position.distance_to(start) > 0.1, "Actor actually moves")
	_check(context.actors.size() == 1 and actor.id == 1, "Simulation preserves actor identity/count")
	feature.free()


func _test_selection() -> void:
	var context := GameContext.new(DungeonGrid.new(5, 5), ContentRegistry.new())
	context.mark_excavation([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)])
	_check(context.excavation_marks.size() == 3, "Default action marks multiple stone tiles for excavation")
	context.mark_excavation([Vector2i(1, 1), Vector2i(2, 1)], GameContext.MarkOperation.ADD)
	_check(context.excavation_marks.size() == 4, "Add mode unions excavation marks")
	context.mark_excavation([Vector2i(1, 0)], GameContext.MarkOperation.REMOVE)
	_check(context.excavation_marks.size() == 3 and not context.excavation_marks.has(Vector2i(1, 0)), "Remove mode unmarks one tile")
	context.mark_excavation([Vector2i(0, 0), Vector2i(0, 0)])
	_check(not context.excavation_marks.has(Vector2i(0, 0)), "Default toggle unmarks exactly once with repeated input cells")
	context.mark_excavation([Vector2i(-1, -1), Vector2i(5, 5)], GameContext.MarkOperation.ADD)
	_check(context.excavation_marks.size() == 2, "Marking ignores out of map cells")
	context.mark_excavation([Vector2i(4, 4)], GameContext.MarkOperation.REPLACE)
	_check(context.excavation_marks.size() == 1 and context.last_marked_cell == Vector2i(4, 4), "Explicit replacement resets marks and anchor")
	context.clear_excavation_marks()
	_check(context.excavation_marks.is_empty() and context.last_marked_cell == Vector2i(-1, -1), "Clear empties marks and anchor")
	context.grid.set_tile(Vector2i(1, 1), DungeonGrid.Tile.FLOOR)
	context.grid.set_tile(Vector2i(2, 1), DungeonGrid.Tile.GOLD)
	context.grid.set_tile(Vector2i(3, 1), DungeonGrid.Tile.HEART)
	context.grid.set_tile(Vector2i(4, 1), DungeonGrid.Tile.PORTAL)
	context.grid.set_tile(Vector2i(0, 2), DungeonGrid.Tile.GEM)
	context.mark_excavation([Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(0, 2)])
	_check(context.excavation_marks.size() == 3, "Only stone, gold and gems receive excavation marks")
	_check(not context.grid.can_excavate(Vector2i(1, 1)), "Excavation excludes open ground")
	_check(context.grid.can_excavate(Vector2i(0, 2)) and not context.grid.is_walkable(Vector2i(0, 2)), "Gem terrain is solid and excavatable")
	context.grid.set_tile(Vector2i(2, 1), DungeonGrid.Tile.FLOOR)
	_check(not context.excavation_marks.has(Vector2i(2, 1)), "Excavated terrain automatically loses its excavation mark")
	_check(not context.grid.can_excavate(Vector2i(-1, 0)), "Excavation excludes off-map targets")
	context.mark_excavation([Vector2i(0, 2)], 99)
	_check(context.excavation_marks.has(Vector2i(0, 2)), "Unknown mark operation cannot change marks")
