extends SceneTree
## Independent hidden-command, local-work and persistent exploration checks.

const Workers = preload("res://content/features/worker_feature.gd")
const Residents = preload("res://content/features/resident_feature.gd")
const HEART := Vector2i(3, 7)
const PORTAL := Vector2i(10, 4)
const SEAM := Vector2i(5, 7)
const BANK := Vector2i(2, 7)
const SECRET := Vector2i(11, 3)
const STEP := 1.0 / 30.0
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_hidden_commands_and_dig_reveal()
	_local_claims_lamps_and_custody()
	_invalid_infrastructure_workers()
	_claimed_portal_controls_arrivals()
	_invalid_exploration_snapshots()
	_legacy_migration_and_disk_replacement()
	_fresh_compact_start()
	for failure in _failures:
		push_error(failure)
	print("EXPLORATION REVIEW: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _fixture(enabled: bool = true) -> GameContext:
	var grid := DungeonGrid.new(15, 12)
	for y in range(6, 9):
		for x in range(2, 5):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(HEART, DungeonGrid.Tile.HEART)
	grid.set_tile(PORTAL, DungeonGrid.Tile.PORTAL)
	grid.set_tile(SEAM, DungeonGrid.Tile.GOLD)
	grid.set_tile(SECRET, DungeonGrid.Tile.FLOOR)
	grid.set_tile(SECRET + Vector2i.DOWN, DungeonGrid.Tile.FLOOR)
	var registry := ContentRegistry.new()
	_check(registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Independent fixture registers actual modular creature and room profiles")
	var context := GameContext.new(grid, registry)
	context.economy.configure_protected_storage({BANK: 500})
	context.economy.deposit(BANK, 100)
	context.economy.initial_gold += 100
	if enabled:
		context.exploration.enable()
		context.infrastructure.enable()
	return context


func _connect_portal(context: GameContext) -> void:
	for x in range(5, PORTAL.x + 1):
		context.grid.set_tile(Vector2i(x, 6), DungeonGrid.Tile.FLOOR)
	context.grid.set_tile(PORTAL + Vector2i.DOWN, DungeonGrid.Tile.FLOOR)
	context.exploration.refresh()


func _copy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func _roundtrip(context: GameContext) -> GameContext:
	var result := DungeonSave.restore(_copy(DungeonSave.capture(context)), context.registry)
	_check(result.error.is_empty() and result.context != null, "Explored dungeon survives a real JSON round trip: %s" % result.error)
	return result.context


func _balanced(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created and context.food.accounted_units() == context.food.produced_units


func _hidden_commands_and_dig_reveal() -> void:
	var context := _fixture()
	_check(context.exploration.is_revealed(HEART) and context.exploration.is_revealed(SEAM) and not context.exploration.is_revealed(SECRET) and not context.exploration.is_revealed(PORTAL), "Initial reveal includes Heart chamber and adjacent rock but not secret floor or portal surroundings")
	_check(not context.exploration.is_reachable(PORTAL) and not context.infrastructure.can_claim_portal(PORTAL), "A beacon does not make a buried portal reachable or claimable")
	var hidden := context.spawn_creature(&"foundation.imp", SECRET)
	var imp := context.spawn_creature(&"foundation.imp", Vector2i(4, 7))
	context.economy.drop_gold(SECRET, context.economy.mine(SEAM, 17))
	var before := context.economy.accounted_gold(context.actors)
	_check(not context.keeper.inspect(hidden.id) and not context.keeper.pickup(hidden.id) and not hidden.is_held, "Blind inspection and pickup cannot reveal or lift an unseen creature")
	_check(not context.keeper.pickup_gold(SECRET) and context.economy.ground_gold.get(SECRET) == 17, "Unseen gold cannot be remotely picked up")
	context.mark_excavation([SEAM, Vector2i(12, 10)])
	_check(context.excavation_marks.has(SEAM) and context.excavation_marks.has(Vector2i(12, 10)), "Excavation planning may extend beyond the explored frontier without revealing terrain")
	_check(not context.rooms.build(&"foundation.lair", [SECRET]).success and context.economy.stored_gold == 100, "Build rejects a hidden open cell without spending")
	_check(context.rooms.place_initial(&"foundation.lair", [SECRET]), "Trusted scenario placement can seed an undiscovered room")
	_check(not context.rooms.remove([SECRET]).success and context.rooms.tiles.has(SECRET), "Sell cannot reveal or liquidate an undiscovered room")
	_check(context.keeper.pickup(imp.id) and not context.keeper.quote_drop(SECRET).valid and not context.keeper.drop(SECRET).success and imp.is_held, "Unknown floor cannot receive held creatures")
	_check(context.keeper.drop(Vector2i(4, 7)).success and _balanced(context) and context.economy.accounted_gold(context.actors) == before, "Rejected hidden commands preserve custody and resource accounting")
	context.grid.set_tile(Vector2i(5, 6), DungeonGrid.Tile.FLOOR)
	_check(context.exploration.is_revealed(Vector2i(6, 6)) and not context.exploration.is_revealed(SECRET), "Excavation reveals the next frontier without exposing unrelated distant terrain")
	var explored := context.exploration.revealed.duplicate()
	context.grid.set_tile(Vector2i(5, 6), DungeonGrid.Tile.ROCK)
	_check(context.exploration.revealed == explored, "Closing an explored passage does not erase discovered geography")
	var restored := _roundtrip(context)
	if restored != null:
		_check(restored.exploration.revealed == context.exploration.revealed and not restored.exploration.is_revealed(SECRET) and _balanced(restored), "Save/load preserves remembered frontier and unknown areas exactly")


func _local_claims_lamps_and_custody() -> void:
	var context := _fixture()
	_connect_portal(context)
	var a := context.spawn_creature(&"foundation.imp", Vector2i(4, 7))
	var b := context.spawn_creature(&"foundation.imp", Vector2i(4, 8))
	_check(context.infrastructure.can_claim_portal(PORTAL) and not context.infrastructure.work_portal(a, PORTAL, 0.25, 1.0), "Connected portal is available but remote work cannot advance it")
	_check(is_zero_approx(context.infrastructure.portal_progress.get(PORTAL, 0.0)), "Remote claim attempt preserves zero progress")
	a.position = context.grid.cell_to_world(PORTAL)
	context.infrastructure.work_portal(a, PORTAL, 0.25, 1.0)
	var progress: float = context.infrastructure.portal_progress.get(PORTAL, 0.0)
	_check(progress > 0.0 and progress < 1.0 and not context.infrastructure.is_portal_claimed(PORTAL), "A local worker makes partial claim progress before ownership changes")
	a.carried_gold = context.economy.mine(SEAM, 19)
	_check(context.keeper.pickup(a.id) and context.keeper.pickup_gold(BANK, 23) and context.keeper.pickup(b.id), "Mixed hand holds two workers, a carrier and a separate gold batch during infrastructure work")
	context.infrastructure.work_portal(a, PORTAL, 1.0, 1.0)
	_check(is_equal_approx(context.infrastructure.portal_progress.get(PORTAL, 0.0), progress), "Held worker cannot remotely finish its interrupted claim")
	context.spawn_creature(&"foundation.imp", Vector2i(4, 6))
	_check(not context.infrastructure.lamps.is_empty(), "Opening the portal route fits wall lamps immediately without worker installation")
	if context.infrastructure.lamps.is_empty():
		return
	var lamp_cell: Vector2i = context.infrastructure.lamps.keys().back()
	var wall: Vector2i = context.infrastructure.lamp_walls[lamp_cell]
	_check(context.infrastructure.is_lamp_wall_valid(lamp_cell, wall), "Each immediate lamp records a real revealed supporting wall")
	_check(context.infrastructure.lamp_progress.is_empty(), "Excavated passages do not retain a delayed lamp-installation task")
	var restored := _roundtrip(context)
	if restored == null:
		return
	_check(restored.infrastructure.portal_progress == context.infrastructure.portal_progress and restored.infrastructure.lamps == context.infrastructure.lamps and restored.infrastructure.lamp_walls == context.infrastructure.lamp_walls, "Partial portal claims and exact supported wall fixtures survive save/load")
	_check(restored.keeper.held_count == 3 and restored.keeper.held_actor.id == a.id and restored.keeper.held_actor.carried_gold == 19 and restored.keeper.total_held_gold == 23 and restored.keeper.get_items()[2].actor.id == b.id and restored.keeper.get_items()[2].actor.is_held, "Loaded mixed queue retains exact actor identity, cargo, FIFO order and gold")
	var workers := Workers.new()
	workers.setup(restored)
	var conserved := true
	for index in 10:
		workers.tick(STEP)
		restored.simulation_ticked.emit(STEP)
		conserved = conserved and _balanced(restored)
	_check(restored.keeper.held_actor.carried_gold == 19 and restored.keeper.total_held_gold == 23 and conserved, "Fresh worker jobs preserve all queued cargo and gold after loading")
	workers.free()
	# Portal claiming remains local work; lighting was already completed by excavation.
	var installer: CreatureState = restored.actors[2]
	installer.position = restored.grid.cell_to_world(PORTAL)
	for index in 40:
		restored.infrastructure.work_portal(installer, PORTAL, 0.25, 1.0)
	_check(restored.infrastructure.is_portal_claimed(PORTAL), "Resumed local claim reaches owned state")
	_check(restored.infrastructure.lamps.has(lamp_cell) and restored.infrastructure.lamp_walls[lamp_cell] == wall and _balanced(restored), "Completed wall lighting remains stable without local installation or economic side effects")
	var completed := _roundtrip(restored)
	if completed != null:
		_check(completed.infrastructure.is_portal_claimed(PORTAL) and completed.infrastructure.lamps.has(lamp_cell) and _balanced(completed), "Completed claim and lamp ownership persist through a second round trip")


func _invalid_infrastructure_workers() -> void:
	var context := _fixture()
	_connect_portal(context)
	var imp := context.spawn_creature(&"foundation.imp", PORTAL)
	var impostor := CreatureState.new()
	impostor.id = imp.id
	impostor.definition_id = imp.definition_id
	impostor.position = imp.position
	_check(not context.infrastructure.work_portal(impostor, PORTAL, 1.0, 1.0), "An unregistered state object cannot impersonate a local worker identity")
	for invalid in [0.0, -1.0, INF, NAN]:
		_check(not context.infrastructure.work_portal(imp, PORTAL, invalid, 1.0) and not context.infrastructure.work_portal(imp, PORTAL, 1.0, invalid), "Nonpositive or nonfinite work input cannot advance ownership: %s" % str(invalid))
	imp.rest_requested = true
	_check(not context.infrastructure.work_portal(imp, PORTAL, 1.0, 1.0), "A creature yielded to needs cannot also claim a portal")
	imp.rest_requested = false
	imp.carried_gold = context.economy.mine(SEAM, 11)
	_check(not context.infrastructure.work_portal(imp, PORTAL, 1.0, 1.0) and imp.carried_gold == 11, "A carrying worker retains cargo and cannot run an infrastructure task simultaneously")
	var grubbin := context.spawn_creature(&"foundation.grubbin", PORTAL)
	_check(not context.infrastructure.work_portal(grubbin, PORTAL, 1.0, 1.0), "Local residents without the claiming capability cannot claim portals")
	context.despawn_creature(grubbin.id)
	_check(is_zero_approx(context.infrastructure.portal_progress.get(PORTAL, 0.0)) and _balanced(context), "Every rejected work attempt preserves progress and resource balances")


func _claimed_portal_controls_arrivals() -> void:
	var context := _fixture()
	_connect_portal(context)
	context.rooms.place_initial(&"foundation.lair", [Vector2i(4, 7)])
	var imp := context.spawn_creature(&"foundation.imp", Vector2i(4, 7))
	var residents := Residents.new()
	residents.setup(context)
	for index in 120:
		residents.tick(STEP)
	_check(context.actors.size() == 1, "Available Lair and reachable portal cannot recruit before claiming")
	imp.position = context.grid.cell_to_world(PORTAL)
	for index in 40:
		context.infrastructure.work_portal(imp, PORTAL, 0.25, 1.0)
	for index in 120:
		residents.tick(STEP)
	var recruited := 0
	for actor in context.actors:
		if actor.definition_id == &"foundation.grubbin":
			recruited += 1
	_check(recruited == 1 and context.infrastructure.is_portal_claimed(PORTAL), "Claimed portal admits the bed-eligible resident exactly once")
	residents.free()


func _legacy_migration_and_disk_replacement() -> void:
	var legacy := _fixture(false)
	var actor := legacy.spawn_creature(&"foundation.imp", Vector2i(4, 7))
	actor.carried_gold = legacy.economy.mine(SEAM, 13)
	legacy.keeper.pickup(actor.id)
	legacy.keeper.pickup_gold(BANK, 29)
	var v1 := DungeonSave.capture(legacy)
	v1.version = 1
	v1.erase("exploration")
	v1.erase("infrastructure")
	var result := DungeonSave.restore(_copy(v1), legacy.registry)
	_check(result.error.is_empty() and result.context != null, "Version1 save migrates without discarding its session: %s" % result.error)
	if result.context == null:
		return
	var restored: GameContext = result.context
	_check(restored.infrastructure.is_portal_claimed(PORTAL) and restored.exploration.is_revealed(SECRET) and restored.keeper.held_count == 2 and restored.keeper.total_held_gold == 29 and restored.keeper.held_actor.carried_gold == 13 and _balanced(restored), "Legacy migration preserves known map, old active portal, mixed custody and gold")
	var path := "res://artifacts/exploration-review-v1-%d.json" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(JSON.stringify(v1, "", true, true))
	handle.close()
	var previous_bytes := FileAccess.get_file_as_bytes(path)
	var error := DungeonSaveStore.write_save(path, DungeonSave.capture(restored), restored.registry)
	_check(error.is_empty() and FileAccess.get_file_as_bytes(path + ".bak") == previous_bytes, "A valid existingv1 slot accepts a newv2 save and retains exact old backup: %s" % error)
	var loaded := DungeonSaveStore.read_save(path, restored.registry)
	_check(loaded.error.is_empty() and loaded.context.keeper.held_count == 2 and _balanced(loaded.context), "Replaced legacy slot remains loadable with complete custody")
	for file in [path, path + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))


func _reject(data: Dictionary, context: GameContext, label: String) -> void:
	var before := context.exploration.revealed.duplicate()
	var result := DungeonSave.restore(data, context.registry)
	_check(result.context == null and not result.error.is_empty() and context.exploration.revealed == before and _balanced(context), label)


func _invalid_exploration_snapshots() -> void:
	var context := _fixture()
	var snapshot := DungeonSave.capture(context)
	var data := snapshot.duplicate(true)
	data.erase("exploration")
	_reject(data, context, "Version2 cannot omit exploration state")
	data = snapshot.duplicate(true)
	data.erase("infrastructure")
	_reject(data, context, "Version2 cannot omit fixture and portal state")
	data = snapshot.duplicate(true)
	data.exploration.revealed.append(data.exploration.revealed[0].duplicate())
	_reject(data, context, "Duplicate discovery cells reject rather than hiding inconsistent state")
	data = snapshot.duplicate(true)
	data.exploration.revealed.append([-1, 0])
	_reject(data, context, "Out-of-bounds discovery rejects safely")
	data = snapshot.duplicate(true)
	data.exploration.revealed.clear()
	_reject(data, context, "A save cannot omit the currently reachable chamber and frontier")
	data = snapshot.duplicate(true)
	data.exploration.enabled = false
	_reject(data, context, "Active infrastructure cannot bypass exploration by disabling its dependency")
	data = snapshot.duplicate(true)
	data.infrastructure.enabled = false
	_reject(data, context, "Disabled infrastructure cannot retain active portal state")
	data = snapshot.duplicate(true)
	data.infrastructure.portals.clear()
	_reject(data, context, "An enabled portal cannot lose its explicit ownership state")
	data = snapshot.duplicate(true)
	data.infrastructure.portals[0][0] = PORTAL.x - 1
	_reject(data, context, "Ownership state cannot point at ordinary rock")
	data = snapshot.duplicate(true)
	data.infrastructure.portals[0][2] = 0.1
	_reject(data, context, "An undiscovered portal cannot contain remote claim progress")
	for invalid in [-0.1, 1.1, NAN, INF]:
		data = snapshot.duplicate(true)
		data.infrastructure.portals[0][2] = invalid
		_reject(data, context, "Invalid portal progress rejects: %s" % str(invalid))
	data = snapshot.duplicate(true)
	data.infrastructure.lamps = [[0, 0]]
	_reject(data, context, "Installed lamp cannot be embedded in solid rock")
	data = snapshot.duplicate(true)
	data.infrastructure.lamps = [[SECRET.x, SECRET.y]]
	_reject(data, context, "Installed lamp cannot expose an unknown floor cell")
	data = snapshot.duplicate(true)
	data.infrastructure.lamps = [[4, 6], [4, 6]]
	_reject(data, context, "Duplicate physical lamp cells reject")
	data = snapshot.duplicate(true)
	data.infrastructure.lamps = [[4, 6]]
	data.infrastructure.lamp_progress = [[4, 6, 0.5]]
	_reject(data, context, "Completed fixture cannot simultaneously remain pending installation")
	data = snapshot.duplicate(true)
	data.infrastructure.lamp_progress = [[4, 6, 1.0]]
	_reject(data, context, "Fully completed lamp work must be represented as an installed fixture")
	data = snapshot.duplicate(true)
	data.infrastructure.lamp_progress = [[BANK.x, BANK.y, 0.5]]
	data.infrastructure.lamp_walls = [[BANK.x, BANK.y, BANK.x, BANK.y]]
	_reject(data, context, "Pending lamp must reference an actual cardinal wall rather than its free access tile")
	data = snapshot.duplicate(true)
	data.marks.append([HEART.x, HEART.y])
	_reject(data, context, "Saved excavation designation cannot target a revealed non-diggable landmark")


func _fresh_compact_start() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(app)
	app.set_physics_process(false)
	var context: GameContext = app.context
	_check(context.actors.size() == 3 and context.economy.stored_gold == 3000 and context.economy.protected_storage.size() == 8 and context.rooms.tiles.is_empty(), "Fresh compact game starts with three imps, protected3000 gold and no prebuilt rooms")
	_check(context.grid.cells_of_type(DungeonGrid.Tile.FLOOR).size() <= 30 and context.grid.cells_of_type(DungeonGrid.Tile.HEART).size() == 1 and context.grid.cells_of_type(DungeonGrid.Tile.PORTAL).size() == 1, "Compact start has one small Heart chamber and a separate buried portal")
	var portals := context.grid.cells_of_type(DungeonGrid.Tile.PORTAL)
	_check(context.exploration.enabled and context.infrastructure.enabled and not context.infrastructure.is_portal_claimed(portals[0]) and not context.exploration.is_reachable(portals[0]), "Actual game enables exploration and requires digging plus portal claiming")
	var gold_nearby := false
	for at in context.grid.cells_of_type(DungeonGrid.Tile.GOLD):
		gold_nearby = gold_nearby or context.exploration.is_revealed(at)
	_check(gold_nearby and _balanced(context), "Initial frontier exposes useful mineable gold without pre-digging the dungeon")
	app.free()
