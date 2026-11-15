extends SceneTree
## Independent planned excavation: unknown marks persist until discovery validates them.

const Workers = preload("res://content/features/worker_feature.gd")
const HEART := Vector2i(2, 9)
const BANK := Vector2i(1, 9)
const FLOOR := Vector2i(10, 7)
const BEDROCK := Vector2i(11, 7)
const PORTAL := Vector2i(12, 7)
const GOLD := Vector2i(10, 6)
const GEM := Vector2i(11, 6)
const STEP := 1.0 / 30.0
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_unknown_plans_and_toggle()
	_hidden_changes_wait_for_discovery()
	_save_restore_and_validation()
	_progressive_room_execution()
	_wall_visibility_range()
	_legacy_visibility_expansion()
	for failure in _failures:
		push_error(failure)
	print("FOG PLANNING: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _fixture() -> GameContext:
	var grid := DungeonGrid.new(18, 17)
	for y in range(8, 11):
		for x in range(1, 4):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(HEART, DungeonGrid.Tile.HEART)
	grid.set_tile(FLOOR, DungeonGrid.Tile.FLOOR)
	grid.set_tile(BEDROCK, DungeonGrid.Tile.BEDROCK)
	grid.set_tile(PORTAL, DungeonGrid.Tile.PORTAL)
	grid.set_tile(GOLD, DungeonGrid.Tile.GOLD)
	grid.set_tile(GEM, DungeonGrid.Tile.GEM)
	var registry := ContentRegistry.new()
	_check(registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Planning fixture loads actual room/worker/mineral definitions")
	var context := GameContext.new(grid, registry)
	context.economy.configure_protected_storage({BANK: 2000})
	context.exploration.enable()
	context.infrastructure.enable()
	return context


func _rectangle() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(6, 10):
		for x in range(9, 13):
			result.append(Vector2i(x, y))
	return result


func _balanced(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created and context.food.accounted_units() == context.food.produced_units


func _copy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func _restore(context: GameContext) -> GameContext:
	var result := DungeonSave.restore(_copy(DungeonSave.capture(context)), context.registry)
	_check(result.error.is_empty() and result.context != null, "Unknown plans survive a complete JSON save/load: %s" % result.error)
	return result.context


func _unknown_plans_and_toggle() -> void:
	var context := _fixture()
	var cells := _rectangle()
	_check(cells.all(func(cell: Vector2i) -> bool: return not context.exploration.is_revealed(cell)), "All four planned rows initially lie outside discovery")
	context.mark_excavation(cells)
	_check(context.excavation_marks.size() == 16 and cells.all(func(cell: Vector2i) -> bool: return context.excavation_marks.has(cell)), "A complete four-by-four plan includes all hidden cells regardless of terrain")
	_check(context.excavation_marks.has(FLOOR) and context.excavation_marks.has(BEDROCK) and context.excavation_marks.has(PORTAL), "Unknown floor, bedrock and portal plans remain marked instead of exposing contents")
	_check(cells.all(func(cell: Vector2i) -> bool: return not context.can_execute_excavation(cell)), "No hidden planned cell is immediately executable")
	var known := context.exploration.revealed.duplicate()
	context.mark_excavation([FLOOR, BEDROCK], GameContext.MarkOperation.REMOVE)
	_check(context.excavation_marks.size() == 14 and not context.excavation_marks.has(FLOOR) and not context.excavation_marks.has(BEDROCK), "Explicit removal works for unknown planned cells")
	context.mark_excavation([FLOOR, BEDROCK], GameContext.MarkOperation.ADD)
	context.mark_excavation([FLOOR, FLOOR])
	_check(context.excavation_marks.size() == 15 and not context.excavation_marks.has(FLOOR), "Repeated cells toggle only once within one plan command")
	context.mark_excavation([FLOOR], GameContext.MarkOperation.ADD)
	_check(context.excavation_marks.size() == 16 and context.exploration.revealed == known, "Re-adding unknown plan cells neither discovers nor changes their terrain")
	context.mark_excavation([HEART, BANK, Vector2i(-1, 1), Vector2i(18, 3)], GameContext.MarkOperation.ADD)
	_check(context.excavation_marks.size() == 16, "Known non-diggable cells and out-of-map cells remain ineligible")
	context.mark_excavation([BEDROCK], GameContext.MarkOperation.REPLACE)
	_check(context.excavation_marks.size() == 1 and context.excavation_marks.has(BEDROCK), "Replace mode supports an unknown plan without inspecting hidden terrain")
	context.clear_excavation_marks()
	_check(context.excavation_marks.is_empty(), "Explicit clearing still removes pending plans")


func _hidden_changes_wait_for_discovery() -> void:
	var context := _fixture()
	var variable := Vector2i(16, 15)
	context.mark_excavation([FLOOR, BEDROCK, PORTAL, variable])
	var initial := context.excavation_marks.duplicate()
	for tile in [DungeonGrid.Tile.FLOOR, DungeonGrid.Tile.BEDROCK, DungeonGrid.Tile.ROCK, DungeonGrid.Tile.PORTAL]:
		context.grid.set_tile(variable, tile)
		_check(context.excavation_marks == initial and not context.exploration.is_revealed(variable), "Changing hidden terrain preserves its mark until discovery (terrain%d)" % tile)
	# Open a safe route that exposes the three non-diggable planned cells.
	for x in range(4, 13):
		context.grid.set_tile(Vector2i(x, 8), DungeonGrid.Tile.FLOOR)
	_check(context.exploration.is_revealed(FLOOR) and context.exploration.is_revealed(BEDROCK) and context.exploration.is_revealed(PORTAL), "Approaching the planned region reveals the actual floor, bedrock and landmark")
	_check(not context.excavation_marks.has(FLOOR) and not context.excavation_marks.has(BEDROCK) and not context.excavation_marks.has(PORTAL), "Only after discovery are non-diggable marks automatically removed")
	_check(context.excavation_marks.has(variable) and not context.exploration.is_revealed(variable), "An unrelated distant non-diggable plan remains until its own discovery")
	var diggable := Vector2i(12, 9)
	context.mark_excavation([diggable])
	_check(context.can_execute_excavation(diggable) and context.excavation_marks.has(diggable), "Revealed diggable terrain retains its executable mark")
	context.grid.set_tile(diggable, DungeonGrid.Tile.FLOOR)
	_check(not context.excavation_marks.has(diggable) and context.excavation_marks.has(variable), "Excavation removes the completed mark without cancelling unrelated unknown plans")


func _save_restore_and_validation() -> void:
	var context := _fixture()
	context.mark_excavation(_rectangle())
	var restored := _restore(context)
	if restored == null:
		return
	_check(restored.excavation_marks == context.excavation_marks and restored.exploration.revealed == context.exploration.revealed and _balanced(restored), "Save/load preserves all unknown plans and the exact discovery boundary")
	_check(restored.excavation_marks.has(FLOOR) and restored.excavation_marks.has(BEDROCK) and restored.excavation_marks.has(PORTAL), "Loading does not prematurely clear hidden non-diggable plans")
	var repeated := _restore(restored)
	_check(repeated != null and repeated.excavation_marks == context.excavation_marks, "Repeated round trips keep hidden planning idempotent")
	var malformed := DungeonSave.capture(context)
	malformed.marks.append([HEART.x, HEART.y])
	var rejected := DungeonSave.restore(_copy(malformed), context.registry)
	_check(rejected.context == null and not rejected.error.is_empty(), "A malformed saved known-floor/landmark mark rejects rather than being silently pruned")
	malformed = DungeonSave.capture(context)
	malformed.marks.append([BANK.x, BANK.y])
	rejected = DungeonSave.restore(_copy(malformed), context.registry)
	_check(rejected.context == null and not rejected.error.is_empty(), "A saved mark on known open floor is invalid even when unknown marks are permitted")
	var workers := Workers.new()
	workers.setup(restored)
	for index in 120:
		workers.tick(STEP)
		restored.simulation_ticked.emit(STEP)
	_check(restored.excavation_marks == context.excavation_marks and restored.economy.gem_gold_created == 0 and restored.economy.remaining_gold[GOLD] == 200 and _balanced(restored), "Remote hidden plans do not excavate or produce mineral gold while inaccessible")
	workers.free()


func _progressive_room_execution() -> void:
	var context := _fixture()
	context.mark_excavation(_rectangle())
	context.mark_excavation([Vector2i(4, 9), Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(8, 9)], GameContext.MarkOperation.ADD)
	context.spawn_creature(&"foundation.imp", Vector2i(3, 9))
	context.spawn_creature(&"foundation.imp", Vector2i(3, 10))
	var restored := _restore(context)
	if restored == null:
		return
	var workers := Workers.new()
	workers.setup(restored)
	var valid_every_tick := true
	var unexposed_preserved := true
	var hidden_supply_preserved := true
	var completed := false
	for index in 18000:
		workers.tick(STEP)
		restored.simulation_ticked.emit(STEP)
		valid_every_tick = valid_every_tick and _balanced(restored)
		for cell in [FLOOR, BEDROCK, PORTAL]:
			if not restored.exploration.is_revealed(cell):
				unexposed_preserved = unexposed_preserved and restored.excavation_marks.has(cell)
			else:
				valid_every_tick = valid_every_tick and not restored.excavation_marks.has(cell)
		if not restored.exploration.is_revealed(GOLD):
			hidden_supply_preserved = hidden_supply_preserved and restored.economy.remaining_gold[GOLD] == 200
		if not restored.exploration.is_revealed(GEM):
			hidden_supply_preserved = hidden_supply_preserved and restored.economy.gem_gold_created == 0
		# Gem is infinite, so explicitly cancel only after it has become usable.
		if restored.economy.gem_gold_created > 0:
			restored.mark_excavation([GEM], GameContext.MarkOperation.REMOVE)
		if restored.excavation_marks.is_empty() and restored.actors.all(func(actor: CreatureState) -> bool: return actor.carried_gold == 0) and restored.economy.ground_gold.is_empty():
			completed = true
			break
	_check(unexposed_preserved, "Unknown floor/bedrock/portal plans survive every simulation tick until in range")
	_check(hidden_supply_preserved, "Workers never award hidden seam/gem gold before discovery")
	_check(completed and restored.grid.get_tile(BEDROCK) == DungeonGrid.Tile.BEDROCK and restored.grid.get_tile(PORTAL) == DungeonGrid.Tile.PORTAL, "Workers dig the connected four-row room plan while preserving discovered non-diggable obstacles")
	_check(restored.economy.stored_gold >= 200 and restored.economy.remaining_gold.get(GOLD, 0) == 0 and restored.economy.gem_gold_created > 0 and valid_every_tick, "Discovered finite/gem mining and hauling complete with conservation on every tick")
	_check(restored.exploration.is_revealed(PORTAL) and restored.exploration.is_revealed(GOLD), "Executing the original multi-row plan progressively explores its hidden contents")
	var saved := _restore(restored)
	_check(saved != null and saved.excavation_marks.is_empty() and _balanced(saved), "Completed planned excavation saves without stale non-diggable marks or resource loss")
	workers.free()


func _wall_visibility_range() -> void:
	var registry := ContentRegistry.new()
	registry.register_module(load("res://content/modules/foundation.tres"))
	var start: Script = load("res://content/scenarios/starting_layout.gd")
	var context := GameContext.new(start.create(), registry)
	start.setup_rooms(context)
	for pair in [[Vector2i(14, 8), Vector2i(14, 7)], [Vector2i(14, 22), Vector2i(14, 23)], [Vector2i(7, 15), Vector2i(6, 15)], [Vector2i(21, 15), Vector2i(22, 15)]]:
		_check(context.exploration.is_revealed(pair[0]) and not context.exploration.is_revealed(pair[1]), "Exposed chamber wall plus four additional rows is revealed, but the next row stays hidden (%s)" % str(pair[0]))
	_check(not context.exploration.is_revealed(Vector2i(14, 6)), "The remote portal remains a beacon beyond the initial wall visibility range")


func _legacy_visibility_expansion() -> void:
	var context := _fixture()
	context.grid.set_tile(Vector2i(6, 9), DungeonGrid.Tile.FLOOR)
	context.grid.set_tile(Vector2i(6, 8), DungeonGrid.Tile.BEDROCK)
	var imp := context.spawn_creature(&"foundation.imp", Vector2i(3, 9))
	imp.carried_gold = context.economy.mine(GOLD, 20)
	context.economy.deposit(BANK, context.economy.mine(GOLD, 30))
	context.keeper.pickup(imp.id)
	context.keeper.pickup_gold(BANK)
	var legacy := DungeonSave.capture(context)
	legacy.exploration.erase("radius")
	var old_knowledge: Array = []
	for y in range(7, 12):
		for x in range(0, 5):
			old_knowledge.append([x, y])
	legacy.exploration.revealed = old_knowledge
	legacy.marks = [[6, 9], [6, 8], [5, 9], [16, 15]]
	var result := DungeonSave.restore(_copy(legacy), context.registry)
	_check(result.error.is_empty() and result.context != null, "A version2 save without a visibility-radius field migrates its legitimate old frontier: %s" % result.error)
	if result.context == null:
		return
	var restored: GameContext = result.context
	_check(restored.grid.get_tile(Vector2i(6, 9)) == DungeonGrid.Tile.FLOOR and restored.exploration.is_revealed(Vector2i(6, 9)) and restored.exploration.is_revealed(Vector2i(6, 8)), "Older terrain is preserved while new visibility expands from the original chamber")
	_check(not restored.excavation_marks.has(Vector2i(6, 9)) and not restored.excavation_marks.has(Vector2i(6, 8)) and restored.excavation_marks.has(Vector2i(5, 9)) and restored.excavation_marks.has(Vector2i(16, 15)), "Migration prunes newly revealed non-diggable plans but preserves diggable and still-unknown plans")
	_check(restored.keeper.held_count == 2 and restored.keeper.held_actor.id == imp.id and restored.keeper.held_actor.carried_gold == 20 and restored.keeper.held_gold == 0 and restored.keeper.total_held_gold == 30 and _balanced(restored), "Visibility migration retains creature identities, cargo, mixed hand order and all gold")
	var again := _restore(restored)
	_check(again != null and again.excavation_marks == restored.excavation_marks and again.exploration.revealed == restored.exploration.revealed and _balanced(again), "New-radius saves remain stable after migration and another full JSON round trip")
	var invalid := legacy.duplicate(true)
	invalid.marks.append([BANK.x, BANK.y])
	var rejected := DungeonSave.restore(_copy(invalid), context.registry)
	_check(rejected.context == null and not rejected.error.is_empty(), "Legacy-radius migration still rejects an originally known floor designation")
