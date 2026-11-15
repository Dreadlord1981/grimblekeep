extends SceneTree
## Independent wall fixtures, immediate excavation lighting and save compatibility.

const Workers = preload("res://content/features/worker_feature.gd")
const EDGE := Vector2i(5, 3)
const BANK := Vector2i(4, 5)
const INTERIOR := Vector2i(7, 6)
const GEM := Vector2i(16, 12)
const INVALID := Vector2i(-1, -1)
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_fixture_geometry_and_room_space()
	_distinct_wall_faces()
	_immediate_excavation_and_support_loss()
	_custody_and_exact_saved_support()
	_legacy_floor_lamps_convert()
	_invalid_mounts_reject()
	for failure in _failures:
		push_error(failure)
	print("WALL LAMPS: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _fixture() -> GameContext:
	var grid := DungeonGrid.new(18, 15)
	for y in range(3, 10):
		for x in range(3, 11):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(4, 6), DungeonGrid.Tile.HEART)
	grid.set_tile(GEM, DungeonGrid.Tile.GEM)
	var registry := ContentRegistry.new()
	_check(registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Wall tests register actual game definitions")
	var context := GameContext.new(grid, registry)
	context.economy.configure_protected_storage({BANK: 1000})
	context.economy.deposit(BANK, 1000)
	context.economy.initial_gold += 1000
	context.exploration.enable()
	context.infrastructure.enable([EDGE])
	return context


func _balanced(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created


func _all_supported(context: GameContext) -> bool:
	var state := context.infrastructure
	for cell in state.lamps:
		if not state.lamp_walls.has(cell) or not state.is_lamp_wall_valid(cell, state.lamp_walls[cell]):
			return false
	for cell in state.lamp_progress:
		if not state.lamp_walls.has(cell) or not state.is_lamp_wall_valid(cell, state.lamp_walls[cell]):
			return false
	return true


func _json_copy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func _roundtrip(context: GameContext) -> GameContext:
	var result := DungeonSave.restore(_json_copy(DungeonSave.capture(context)), context.registry)
	_check(result.error.is_empty() and result.context != null, "Wall-lit dungeon restores a JSON snapshot: %s" % result.error)
	return result.context


func _fixture_geometry_and_room_space() -> void:
	var context := _fixture()
	var state := context.infrastructure
	_check(state.lamps.has(EDGE) and state.lamp_walls.get(EDGE, INVALID) == EDGE + Vector2i.UP, "Starting fixture stores its actual supporting wall rather than a floor post")
	_check(state.find_lamp_wall(INTERIOR) == INVALID and not state.can_install_lamp(INTERIOR), "Open room interior cannot host an unsupported floor lamp")
	_check(state.is_lamp_wall_valid(EDGE, EDGE + Vector2i.UP) and not state.is_lamp_wall_valid(EDGE, EDGE + Vector2i(1, -1)), "Wall supports must share the exact cardinal floor face")
	_check(not state.is_lamp_wall_valid(EDGE, EDGE + Vector2i.DOWN), "An adjacent floor tile cannot support a wall sconce")
	context.grid.set_tile(EDGE + Vector2i.UP, DungeonGrid.Tile.BEDROCK)
	_check(state.lamps.has(EDGE) and _all_supported(context), "Indestructible rock remains valid wall support")
	var built := context.rooms.build(&"foundation.lair", [EDGE])
	_check(built.success and state.lamps.has(EDGE), "A room can be built on the lamp service tile without removing the wall fixture")
	var resident := context.spawn_creature(&"foundation.grubbin", EDGE)
	var bed := context.beds.reserve(resident, context.registry.get_creature(resident.definition_id))
	_check(bed != null and bed.anchor == EDGE and context.beds.establish(resident), "The entire floor cell remains available for a locally claimed creature bed")
	_check(state.lamps.has(EDGE) and _all_supported(context), "Bed establishment does not displace or invalidate the wall fixture")
	var restored := _roundtrip(context)
	if restored != null:
		_check(restored.beds.get_bed(resident.id) != null and restored.beds.get_bed(resident.id).established and restored.infrastructure.lamp_walls == state.lamp_walls, "Saved room, bed and exact lamp wall coexist after loading")
	context.rooms.remove([EDGE])
	_check(state.lamps.has(EDGE) and _balanced(context), "Selling the room leaves the supporting wall and lamp intact without changing gold accounting")


func _immediate_excavation_and_support_loss() -> void:
	var context := _fixture()
	var state := context.infrastructure
	var before := state.lamps.size()
	for x in range(11, 16):
		context.grid.set_tile(Vector2i(x, 6), DungeonGrid.Tile.FLOOR)
		_check(_all_supported(context), "Every excavation event leaves only valid wall-supported fixtures (x=%d)" % x)
	_check(state.lamps.size() > before and context.actors.is_empty(), "Excavation adds lamps synchronously with no worker-idle time or feature ticks")
	_check(state.lamps.keys().any(func(cell: Vector2i) -> bool: return cell.x >= 11), "Newly dug corridor receives wall fixtures along its own length")
	var snapshot := state.lamps.duplicate()
	state.ensure_wall_lamps()
	_check(state.lamps == snapshot, "Repeated lighting reconciliation cannot stack duplicate wall fixtures")
	var old_wall: Vector2i = state.lamp_walls[EDGE]
	context.grid.set_tile(old_wall, DungeonGrid.Tile.FLOOR)
	_check(not state.lamp_walls.values().has(old_wall) and _all_supported(context), "Excavating a supporting wall removes its old mount immediately")
	_check(not state.lamps.is_empty() and state.lamps.keys().any(func(cell: Vector2i) -> bool: return cell.distance_to(EDGE) <= 3.0), "Remaining nearby walls receive replacement lighting without a timed installer")
	var hidden := Vector2i(17, 13)
	context.grid.set_tile(hidden, DungeonGrid.Tile.FLOOR)
	_check(not context.exploration.is_reachable(hidden) and not state.lamps.has(hidden), "Disconnected unexplored authored floor does not acquire a visible lamp")
	_check(_balanced(context), "Digging and support replacement neither charge nor create gold")
	var restored := _roundtrip(context)
	if restored != null:
		_check(restored.infrastructure.lamps == state.lamps and restored.infrastructure.lamp_walls == state.lamp_walls and _all_supported(restored), "Actual excavation lamp sites and supporting faces survive save/load exactly")


func _distinct_wall_faces() -> void:
	var context := _fixture()
	var state := context.infrastructure
	var wall := Vector2i(8, 6)
	var left := wall + Vector2i.LEFT
	var right := wall + Vector2i.RIGHT
	context.grid.set_tile(wall, DungeonGrid.Tile.ROCK)
	_check(state.find_lamp_wall(left) == wall and state.find_lamp_wall(right) == wall, "Opposite sides of one solid wall resolve to distinct supported faces")
	state.enable([left])
	_check(state.can_install_lamp(right), "Path-distance spacing allows opposite passages separated by the supporting wall")
	state.enable([right])
	_check(state.lamp_walls[left] == wall and state.lamp_walls[right] == wall and _all_supported(context), "Two wall faces can carry fixtures without occupying either floor cell")
	var restored := _roundtrip(context)
	if restored != null:
		_check(restored.infrastructure.lamp_walls[left] == wall and restored.infrastructure.lamp_walls[right] == wall, "Save/load preserves exact opposite-facing lamp supports")


func _custody_and_exact_saved_support() -> void:
	var context := _fixture()
	var worker := context.spawn_creature(&"foundation.imp", EDGE)
	worker.carried_gold = context.economy.mine(GEM, 23)
	worker.custom_name = "Sconce inspector"
	_check(context.keeper.pickup(worker.id) and context.keeper.pickup_gold(BANK, 31), "Creature cargo and a separate gold batch enter the mixed hand queue")
	var original_order: Array[int] = []
	for item in context.keeper.get_items():
		original_order.append(item.id)
	var restored := _roundtrip(context)
	if restored == null:
		return
	var new_order: Array[int] = []
	for item in restored.keeper.get_items():
		new_order.append(item.id)
	_check(original_order == new_order and restored.keeper.held_actor.id == worker.id and restored.keeper.held_actor.carried_gold == 23 and restored.keeper.total_held_gold == 31, "Wall state restoration preserves all ordered custody and worker cargo")
	_check(restored.infrastructure.lamp_walls == context.infrastructure.lamp_walls and _balanced(restored), "Wall-face metadata cannot duplicate or lose economic resources")
	var held := restored.keeper.held_actor
	var held_position := held.position
	var workers := Workers.new()
	workers.setup(restored)
	for index in 60:
		workers.tick(1.0 / 30.0)
	_check(held.position == held_position and held.carried_gold == 23 and held.is_held, "Adding immediate wall lighting does not resume held creature work")
	_check(restored.keeper.drop(EDGE).success and restored.keeper.held_gold == 31 and restored.keeper.drop(BANK).success, "Restored queue still releases its creature and gold in FIFO order")
	for index in 1800:
		workers.tick(1.0 / 30.0)
		if held.carried_gold == 0:
			break
	_check(held.carried_gold == 0 and _balanced(restored), "Released worker delivers its saved cargo normally beside wall fixtures")
	workers.free()


func _legacy_floor_lamps_convert() -> void:
	var context := _fixture()
	var worker := context.spawn_creature(&"foundation.imp", EDGE)
	context.keeper.pickup(worker.id)
	context.keeper.pickup_gold(BANK, 17)
	var legacy := DungeonSave.capture(context)
	legacy.infrastructure.erase("lamp_walls")
	legacy.infrastructure.lamps = [[INTERIOR.x, INTERIOR.y]]
	legacy.infrastructure.lamp_progress = [[10, 9, 0.4]]
	var result := DungeonSave.restore(_json_copy(legacy), context.registry)
	_check(result.error.is_empty() and result.context != null, "An older floor-lamp save converts rather than becoming unloadable: %s" % result.error)
	if result.context == null:
		return
	var restored: GameContext = result.context
	_check(restored.infrastructure.lamp_progress.is_empty() and restored.infrastructure.lamps.size() >= 1 and _all_supported(restored), "Legacy completed and timed floor fixtures become real supported wall lamps without waiting")
	_check(not restored.infrastructure.lamps.has(INTERIOR), "Legacy unsupported interior floor post cannot remain in the room center")
	_check(restored.keeper.held_count == 2 and restored.keeper.held_actor.id == worker.id and restored.keeper.total_held_gold == 17 and _balanced(restored), "Converting old fixtures preserves the complete dungeon economy and hand queue")
	var again := _roundtrip(restored)
	if again != null:
		_check(again.infrastructure.lamps == restored.infrastructure.lamps and again.infrastructure.lamp_walls == restored.infrastructure.lamp_walls, "Converted wall fixtures remain stable on subsequent saves")
	var unlit_legacy := DungeonSave.capture(context)
	unlit_legacy.infrastructure.erase("lamp_walls")
	unlit_legacy.infrastructure.lamps.clear()
	unlit_legacy.infrastructure.lamp_progress.clear()
	var relit := DungeonSave.restore(_json_copy(unlit_legacy), context.registry)
	_check(relit.error.is_empty() and relit.context != null
		and not relit.context.infrastructure.lamps.is_empty() and _all_supported(relit.context)
		and relit.context.infrastructure.lamps.keys().all(func(cell: Vector2i) -> bool: return relit.context.exploration.is_reachable(cell))
		and relit.context.keeper.held_count == 2 and relit.context.keeper.held_actor.id == worker.id
		and relit.context.keeper.held_gold == 0 and relit.context.keeper.total_held_gold == 17
		and _balanced(relit.context),
		"An old excavated but entirely unlit dungeon gains immediate supported reachable wall lighting while preserving FIFO custody and gold")


func _invalid_mounts_reject() -> void:
	var context := _fixture()
	var snapshot := DungeonSave.capture(context)
	var variants: Array[Dictionary] = []
	var data := snapshot.duplicate(true)
	data.infrastructure.lamp_walls = []
	variants.append({"data": data, "label": "Explicit mount payload cannot omit an installed lamp's wall"})
	data = snapshot.duplicate(true)
	data.infrastructure.lamp_walls.append(data.infrastructure.lamp_walls[0].duplicate())
	variants.append({"data": data, "label": "Duplicate lamp support identities reject"})
	data = snapshot.duplicate(true)
	data.infrastructure.lamp_walls[0][2] = EDGE.x + 1
	variants.append({"data": data, "label": "Diagonal supporting walls reject"})
	data = snapshot.duplicate(true)
	data.infrastructure.lamp_walls[0][3] = EDGE.y + 1
	variants.append({"data": data, "label": "An open floor tile cannot be restored as supporting wall"})
	data = snapshot.duplicate(true)
	data.infrastructure.lamp_walls[0][2] = -1
	variants.append({"data": data, "label": "Out-of-bounds wall metadata rejects"})
	data = snapshot.duplicate(true)
	data.infrastructure.lamp_walls.append([INTERIOR.x, INTERIOR.y, INTERIOR.x, INTERIOR.y - 1])
	variants.append({"data": data, "label": "Orphan support metadata cannot introduce an untracked lamp"})
	data = snapshot.duplicate(true)
	data.infrastructure.lamp_walls[0] = [EDGE.x, EDGE.y, "wall", 2]
	variants.append({"data": data, "label": "Wrong-type wall coordinates reject without runtime failure"})
	for item in variants:
		var result := DungeonSave.restore(_json_copy(item.data), context.registry)
		_check(result.context == null and not result.error.is_empty(), item.label)
	_check(context.infrastructure.lamps.has(EDGE) and context.infrastructure.lamp_walls[EDGE] == EDGE + Vector2i.UP and _balanced(context), "Rejected candidates never mutate the live wall-lit dungeon")
