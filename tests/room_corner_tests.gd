extends SceneTree
## Independent room-corner lighting, real wall support and persistent fixtures.

const PEN := &"foundation.pig_pen"
const BANK := Vector2i(2, 6)
const GEM := Vector2i(16, 13)
const INVALID := Vector2i(-1, -1)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_corners_override_corridor_spacing()
	_single_and_irregular_rooms()
	_room_edits_and_support_changes()
	_no_invented_walls_or_hidden_lights()
	_save_restore_and_old_corner_catchup()
	for failure in _failures:
		push_error(failure)
	print("ROOM CORNERS: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _rectangle(first: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(first.y, first.y + size.y):
		for x in range(first.x, first.x + size.x):
			cells.append(Vector2i(x, y))
	return cells


func _fixture(size: Vector2i = Vector2i(3, 3), room_origin: Vector2i = Vector2i(6, 6)) -> GameContext:
	var grid := DungeonGrid.new(20, 17)
	for cell in _rectangle(Vector2i(2, 6), Vector2i(3, 3)) + _rectangle(room_origin, size):
		grid.set_tile(cell, DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(3, 7), DungeonGrid.Tile.HEART)
	for x in range(4, room_origin.x + 1):
		grid.set_tile(Vector2i(x, 7), DungeonGrid.Tile.FLOOR)
	grid.set_tile(GEM, DungeonGrid.Tile.GEM)
	var registry := ContentRegistry.new()
	_check(registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Corner fixture loads real room/creature definitions")
	var context := GameContext.new(grid, registry)
	context.economy.configure_protected_storage({BANK: 4000})
	context.economy.deposit(BANK, 3000)
	context.economy.initial_gold += 3000
	context.exploration.enable()
	context.infrastructure.enable([room_origin])
	return context


func _supported(context: GameContext) -> bool:
	for cell in context.infrastructure.lamps:
		if not context.infrastructure.lamp_walls.has(cell) or not context.infrastructure.is_lamp_wall_valid(cell, context.infrastructure.lamp_walls[cell]):
			return false
	return true


func _balanced(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created


func _copy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func _corners_override_corridor_spacing() -> void:
	var context := _fixture()
	var state := context.infrastructure
	_check(state.lamps.has(Vector2i(6, 6)) and not state.can_install_lamp(Vector2i(8, 6)), "Nearby existing lamp would suppress the adjacent corner under ordinary corridor spacing")
	var before := context.economy.stored_gold
	_check(context.rooms.build(PEN, _rectangle(Vector2i(6, 6), Vector2i(3, 3))).success, "Player builds an actual three-by-three Pig Pen")
	for cell in [Vector2i(6, 6), Vector2i(8, 6), Vector2i(6, 8), Vector2i(8, 8)]:
		_check(state.lamps.has(cell) and state.is_lamp_wall_valid(cell, state.lamp_walls.get(cell, INVALID)), "Room corner immediately gets a supported wall lamp despite corridor spacing: %s" % str(cell))
	_check(not state.lamps.has(Vector2i(7, 7)) and context.grid.is_walkable(Vector2i(7, 7)), "Room center remains free of invented floor lights and movement blockers")
	_check(context.economy.stored_gold == before - 9 * 75 and _balanced(context), "Corner lamps add no extra resource charges or gold source")
	var lamps := state.lamps.duplicate()
	var walls := state.lamp_walls.duplicate()
	for index in 5:
		state.ensure_room_corner_lamps()
	_check(state.lamps == lamps and state.lamp_walls == walls, "Repeated room-light reconciliation is idempotent")
	_check(_supported(context), "Every corner lamp still refers to an actual adjacent wall")


func _single_and_irregular_rooms() -> void:
	var context := _fixture()
	context.rooms.build(&"foundation.lair", [Vector2i(6, 6)])
	var state := context.infrastructure
	_check(state.lamps.has(Vector2i(6, 6)) and state.lamp_walls.keys().count(Vector2i(6, 6)) == 1, "Single-tile room does not produce four coincident lamps")
	var resident := context.spawn_creature(&"foundation.grubbin", Vector2i(6, 6))
	var bed := context.beds.reserve(resident, context.registry.get_creature(resident.definition_id))
	_check(bed != null and context.beds.establish(resident) and state.lamps.has(Vector2i(6, 6)), "Corner fixture leaves the complete floor tile usable for a locally claimed bed")
	var shaped := _fixture()
	shaped.rooms.build(PEN, [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(6, 7), Vector2i(6, 8)])
	_check(shaped.infrastructure.lamps.has(Vector2i(8, 6)) and shaped.infrastructure.lamps.has(Vector2i(6, 8)), "L-shaped room lights both supported outer endpoints")
	_check(not shaped.infrastructure.lamps.has(Vector2i(7, 7)) and _supported(shaped), "Irregular room adds no unsupported lamp in its empty concave interior")


func _room_edits_and_support_changes() -> void:
	var context := _fixture(Vector2i(5, 3))
	var initial := _rectangle(Vector2i(6, 6), Vector2i(3, 3))
	context.rooms.build(PEN, initial)
	context.rooms.build(PEN, _rectangle(Vector2i(9, 6), Vector2i(2, 3)))
	_check(context.rooms.get_rooms().size() == 1 and context.infrastructure.lamps.has(Vector2i(10, 6)) and context.infrastructure.lamps.has(Vector2i(10, 8)), "Room expansion merges its group and lights new supported far corners")
	context.rooms.remove(_rectangle(Vector2i(8, 6), Vector2i(1, 3)))
	_check(context.rooms.get_rooms().size() == 2 and _supported(context), "Selling a bridge splits the room without invalid or duplicate fixtures")
	var survivor := Vector2i(6, 6)
	var support: Vector2i = context.infrastructure.lamp_walls[survivor]
	context.grid.set_tile(support, DungeonGrid.Tile.FLOOR)
	_check(not context.infrastructure.lamp_walls.values().has(support) and _supported(context), "Digging a supporting wall removes its old attachment and rebuilds only against remaining walls")
	context.rooms.remove(context.rooms.tiles.keys())
	_check(context.rooms.tiles.is_empty() and _supported(context) and _balanced(context), "Selling rooms preserves real fixtures and the construction/refund ledger")


func _no_invented_walls_or_hidden_lights() -> void:
	var context := _fixture(Vector2i(7, 7))
	var interior := Vector2i(8, 8)
	context.rooms.build(&"foundation.lair", [interior])
	_check(context.infrastructure.find_lamp_wall(interior) == INVALID and not context.infrastructure.lamps.has(interior), "A room isolated from solid walls does not invent a floor post or invisible support")
	var hidden := Vector2i(18, 0)
	context.grid.set_tile(hidden, DungeonGrid.Tile.FLOOR)
	context.rooms.place_initial(&"foundation.lair", [hidden])
	context.infrastructure.ensure_room_corner_lamps()
	_check(not context.exploration.is_revealed(hidden) and not context.infrastructure.lamps.has(hidden), "Unexplored disconnected room cannot reveal itself by adding corner light")


func _save_restore_and_old_corner_catchup() -> void:
	var context := _fixture()
	context.rooms.build(PEN, _rectangle(Vector2i(6, 6), Vector2i(3, 3)))
	var worker := context.spawn_creature(&"foundation.imp", Vector2i(4, 6))
	worker.carried_gold = context.economy.mine(GEM, 13)
	context.keeper.pickup(worker.id)
	context.keeper.pickup_gold(BANK, 23)
	var snapshot := DungeonSave.capture(context)
	var restored := DungeonSave.restore(_copy(snapshot), context.registry)
	_check(restored.error.is_empty() and restored.context != null, "Corner-lit dungeon restores through JSON: %s" % restored.error)
	if restored.context == null:
		return
	var loaded: GameContext = restored.context
	_check(loaded.infrastructure.lamps == context.infrastructure.lamps and loaded.infrastructure.lamp_walls == context.infrastructure.lamp_walls and _supported(loaded), "Modern save preserves exact corner fixtures and supporting wall faces")
	_check(loaded.keeper.held_count == 2 and loaded.keeper.held_actor.id == worker.id and loaded.keeper.held_actor.carried_gold == 13 and loaded.keeper.total_held_gold == 23 and _balanced(loaded), "Corner lighting save/load preserves mixed held identities and every gold balance")
	var previous := _copy(snapshot)
	previous.infrastructure.lamps = [[6, 6]]
	previous.infrastructure.lamp_walls = [[6, 6, 6, 5]]
	var upgraded := DungeonSave.restore(previous, context.registry)
	_check(upgraded.error.is_empty() and upgraded.context != null, "Previous valid mounted-lamp save remains loadable: %s" % upgraded.error)
	if upgraded.context != null:
		var filled: GameContext = upgraded.context
		_check([Vector2i(6, 6), Vector2i(8, 6), Vector2i(6, 8), Vector2i(8, 8)].all(func(cell: Vector2i) -> bool: return filled.infrastructure.lamps.has(cell)), "Existing rooms with older sparse mounts receive missing corner lamps on loading")
		_check(filled.keeper.held_count == 2 and filled.keeper.total_held_gold == 23 and _balanced(filled), "Corner catch-up changes fixtures only, preserving custody and economy")
