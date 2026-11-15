extends SceneTree
## Independent persistence checks: identities, FIFO custody and safe resumption.

const Workers = preload("res://content/features/worker_feature.gd")
const Residents = preload("res://content/features/resident_feature.gd")
const Producers = preload("res://content/features/food_feature.gd")
const STEP := 1.0 / 30.0
const SPECIES := &"save_review.hybrid"
const RAW := &"save_review.raw"
const PEN := &"save_review.pen"
const LAIR := &"save_review.lair"
const BANK := Vector2i(3, 2)
const PILE := Vector2i(4, 4)
const GOLD := Vector2i(14, 5)
const GEM := Vector2i(14, 6)
const FOOD_CELL := Vector2i(10, 4)
var _checks := 0
var _failures: Array[String] = []
var _codec: Script
var _store: Script


func _initialize() -> void:
	_codec = load("res://persistence/dungeon_save.gd")
	_store = load("res://persistence/dungeon_save_store.gd")
	_mixed_roundtrip_and_resume()
	_large_queue_and_monotonic_ids()
	_pending_cargo_and_stranded_food()
	_sleeping_continues_to_wake_threshold()
	_partial_meal_keeps_hunger_intent()
	_malformed_snapshots_are_rejected()
	_disk_replacement_and_failure()
	_pending_bed_and_consumed_identity()
	_unmet_hunger_intent_survives()
	_active_mining_and_cargo_resume()
	for failure in _failures:
		push_error(failure)
	print("SAVE REVIEW: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture() -> GameContext:
	var grid := DungeonGrid.new(17, 12)
	for y in range(1, 10):
		for x in range(1, 14):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	grid.set_tile(Vector2i(2, 2), DungeonGrid.Tile.HEART)
	grid.set_tile(Vector2i(2, 3), DungeonGrid.Tile.PORTAL)
	grid.set_tile(GOLD, DungeonGrid.Tile.GOLD)
	grid.set_tile(GEM, DungeonGrid.Tile.GEM)
	grid.set_tile(Vector2i(0, 5), DungeonGrid.Tile.BEDROCK)
	var species := CreatureDefinition.new()
	species.id = SPECIES
	species.capabilities = [&"haul", &"excavate", &"rest", &"eat"]
	species.move_speed = 7.0
	species.work_rate = 3.0
	species.bed_size = Vector2i(2, 1)
	species.energy_drain_per_second = 0.0
	species.hunger_drain_per_second = 0.0
	species.eating_seconds = 0.3
	var food := FoodDefinition.new()
	food.id = RAW
	food.nutrition_per_unit = 1.0
	food.growth_seconds = 30.0
	food.wanders = true
	var pen := RoomDefinition.new()
	pen.id = PEN
	pen.food_type = RAW
	pen.food_capacity_per_tile = 8
	pen.food_production_seconds = 12.0
	var lair := RoomDefinition.new()
	lair.id = LAIR
	lair.tags = [&"lair"]
	lair.gold_cost_per_tile = 50
	var module := ContentModule.new()
	module.id = &"save_review"
	module.definitions = [species, food, pen, lair]
	var registry := ContentRegistry.new()
	_check(registry.register_module(module).is_empty(), "Independent extension definitions register")
	var context := GameContext.new(grid, registry)
	context.economy.configure_protected_storage({BANK: 500, Vector2i(4, 2): 500})
	context.rooms.place_initial(PEN, [FOOD_CELL])
	context.rooms.place_initial(LAIR, [Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)])
	return context


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _json_copy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


func _roundtrip(context: GameContext) -> GameContext:
	var result: Dictionary = _codec.restore(_json_copy(_codec.capture(context)), context.registry)
	_check(result.error.is_empty() and result.context != null, "Valid snapshot survives real JSON encoding and detached restore: %s" % result.error)
	return result.context


func _conserved(context: GameContext) -> bool:
	return context.economy.accounted_gold(context.actors) == context.economy.initial_gold + context.economy.gem_gold_created and context.food.accounted_units() == context.food.produced_units


func _attach(context: GameContext) -> Dictionary:
	var workers := Workers.new()
	workers.setup(context)
	var residents := Residents.new()
	residents.setup(context)
	var producers := Producers.new()
	producers.setup(context)
	return {"context": context, "workers": workers, "residents": residents, "producers": producers, "roaming": FoodRoaming.new(), "conserved": true}


func _advance(scene: Dictionary, seconds: float, produce: bool = false) -> void:
	for index in ceili(seconds / STEP):
		if produce:
			scene.producers.tick(STEP)
		else:
			# Isolate finite-stock continuation while still running physical pig
			# movement/age, including the reserved pig's return to its service cell.
			scene.context.food.age_units(STEP)
			scene.roaming.tick(scene.context, STEP)
		scene.residents.tick(STEP)
		scene.workers.tick(STEP)
		scene.context.simulation_ticked.emit(STEP)
		scene.conserved = scene.conserved and _conserved(scene.context)


func _finish(scene: Dictionary) -> void:
	_check(scene.conserved and _conserved(scene.context), "Every resumed tick conserves physical food and gold")
	scene.residents.free()
	scene.workers.free()
	scene.producers.free()


func _actor(context: GameContext, id: int) -> CreatureState:
	for actor in context.actors:
		if actor.id == id:
			return actor
	return null


func _mixed_roundtrip_and_resume() -> void:
	var original := _fixture()
	var first := original.spawn_creature(SPECIES, Vector2i(3, 4))
	var second := original.spawn_creature(SPECIES, Vector2i(4, 5))
	first.custom_name = "Pickles the Unpaid"
	first.carried_gold = original.economy.mine(GOLD, 27)
	first.energy = 0.43
	first.satiety = 0.21
	second.custom_name = "Snout №2"
	second.energy = 0.71
	second.satiety = 0.18
	var bed := original.beds.reserve(first, original.registry.get_creature(SPECIES))
	first.position = bed.center(original.grid)
	original.beds.establish(first)
	original.beds.reserve(second, original.registry.get_creature(SPECIES))
	original.economy.deposit(BANK, original.economy.mine(GOLD, 50))
	original.economy.drop_gold(PILE, original.economy.mine(GOLD, 71))
	original.food.produce(FOOD_CELL, RAW, 2)
	var unit: FoodUnitState = original.food.units.values()[0]
	unit.age_seconds = 17.25
	unit.position += Vector3(0.2, 0.0, 0.1)
	unit.heading = 0.7
	original.food.sources[FOOD_CELL].progress = 7.5
	_check(original.keeper.pickup(first.id) and original.keeper.pickup_gold(PILE, 31) and original.keeper.pickup(second.id) and original.keeper.pickup_gold(BANK, 19), "Prepare mixed creatures and separate gold batches")
	original.keeper.inspect(first.id)
	original.mark_excavation([GOLD, GEM, Vector2i(14, 4)])
	var before_items := original.keeper.get_items()
	var restored := _roundtrip(original)
	if restored == null:
		return
	_check(restored != original and restored.grid != original.grid and restored.actors[0] != first, "Load constructs independent session and actor objects")
	_check(restored.grid.cells_of_type(DungeonGrid.Tile.HEART) == original.grid.cells_of_type(DungeonGrid.Tile.HEART) and restored.grid.cells_of_type(DungeonGrid.Tile.PORTAL) == original.grid.cells_of_type(DungeonGrid.Tile.PORTAL) and restored.grid.get_tile(Vector2i(0, 5)) == DungeonGrid.Tile.BEDROCK, "Heart, portal and indestructible terrain survive without duplication")
	_check(restored.excavation_marks == original.excavation_marks and restored.rooms.tiles == original.rooms.tiles and restored.economy.protected_storage == original.economy.protected_storage, "Orders, room membership and protected capacities survive")
	_check(restored.economy.stored_by_cell == original.economy.stored_by_cell and restored.economy.ground_gold == original.economy.ground_gold and restored.economy.remaining_gold == original.economy.remaining_gold and _conserved(restored), "Stored, loose, unmined, carried and held gold remain conserved")
	var held := _actor(restored, first.id)
	_check(held.custom_name == first.custom_name and held.carried_gold == 27 and is_equal_approx(held.energy, 0.43) and is_equal_approx(held.satiety, 0.21) and held.position == first.position, "Held creature retains exact name, cargo, position and needs")
	_check(restored.beds.get_bed(first.id) != null and restored.beds.get_bed(first.id).established and restored.beds.get_bed(first.id).size == Vector2i(2, 1) and restored.beds.get_bed(second.id) == null, "Held owner keeps established sized bed; pickup-released pending bed stays absent")
	_check(restored.keeper.inspected_actor == held and restored.keeper.held_count == 4 and restored.keeper.total_held_gold == 50, "Inspection and whole mixed queue restore separately")
	var same := true
	var after_items := restored.keeper.get_items()
	for index in before_items.size():
		var a := before_items[index]
		var b := after_items[index]
		same = same and a.id == b.id and a.kind == b.kind and a.origin == b.origin and a.gold_amount == b.gold_amount
		if a.actor != null:
			same = same and b.actor != a.actor and b.actor.id == a.actor.id and b.actor.is_held
	_check(same, "FIFO item IDs, kinds, origins, exact batches and actor references restore")
	var pig: FoodUnitState = restored.food.units[unit.id]
	_check(pig != unit and pig.cell == unit.cell and pig.position.is_equal_approx(unit.position) and is_equal_approx(pig.age_seconds, 17.25) and is_equal_approx(pig.heading, 0.7) and is_equal_approx(restored.food.sources[FOOD_CELL].progress, 7.5), "Physical pig identity, allocation, roaming pose, age and producer progress restore")
	var scene := _attach(restored)
	_advance(scene, 2.0)
	_check(held.is_held and held.position == first.position and is_equal_approx(held.energy, 0.43) and is_equal_approx(held.satiety, 0.21) and scene.workers.job_board.active_job_count() == 0 and restored.food.reservations.is_empty(), "All held actors remain frozen with no work or meal reservations after loading")
	_check(not restored.keeper.drop(Vector2i(0, 0)).success and restored.keeper.held_count == 4, "Invalid post-load drop leaves restored queue untouched")
	_check(restored.keeper.drop(PILE).success and restored.keeper.held_gold == 31 and restored.keeper.drop(BANK).success and restored.keeper.held_actor.id == second.id and restored.keeper.drop(PILE).success and restored.keeper.held_gold == 19 and restored.keeper.drop(BANK).success, "Post-load drops consume exactly one oldest item of correct kind and amount")
	# Do not keep generating gold; drain the designated finite seam and loose cargo.
	restored.mark_excavation([GEM], GameContext.MarkOperation.REMOVE)
	_advance(scene, 50.0)
	_check(restored.keeper.held_count == 0 and restored.economy.keeper_gold == 0 and restored.economy.remaining_gold.get(GOLD, 0) == 0 and restored.economy.ground_gold.is_empty(), "Restored workers resume finite excavation and hauling without stranding cargo")
	_check(restored.food.consumed_units == 2 and restored.food.total_units == 0 and restored.actors.size() == 2, "Restored creatures resume meals once and neither food nor population duplicates")
	_check(original.keeper.held_count == 4 and original.economy.keeper_gold == 50 and first.is_held and original.food.consumed_units == 0, "Advancing restored session never mutates source snapshot session")
	_finish(scene)


func _large_queue_and_monotonic_ids() -> void:
	var original := _fixture()
	var largest_actor := 0
	for index in 24:
		var actor := original.spawn_creature(SPECIES, Vector2i(3, 3))
		largest_actor = actor.id
		original.keeper.pickup(actor.id)
		original.economy.drop_gold(PILE, original.economy.mine(GEM, index + 1))
		original.keeper.pickup_gold(PILE)
	var deleted := original.spawn_creature(SPECIES, Vector2i(3, 3))
	largest_actor = deleted.id
	original.despawn_creature(deleted.id)
	var last_entry: int = original.keeper.get_items().back().id
	var restored := _roundtrip(original)
	if restored == null:
		return
	_check(restored.keeper.held_count == 48 and restored.keeper.total_held_gold == 300 and restored.actors.size() == 24 and _conserved(restored), "Save/load restores a queue beyond visible UI capacity without truncation")
	var actor := restored.spawn_creature(SPECIES, Vector2i(3, 3))
	_check(actor.id > largest_actor and restored.keeper.pickup(actor.id) and restored.keeper.get_items().back().id > last_entry, "Monotonic actor and custody counters survive removed identities")
	var replay := _roundtrip(restored)
	_check(replay != null and replay.keeper.held_count == 49 and replay.actors.size() == 25 and _conserved(replay), "Repeated save/load leaves held actors and ledger idempotent")


func _pending_cargo_and_stranded_food() -> void:
	var original := _fixture()
	var removed := original.spawn_creature(SPECIES, Vector2i(3, 3))
	removed.carried_gold = original.economy.mine(GOLD, 37)
	removed.position = original.grid.cell_to_world(Vector2i(0, 0))
	original.despawn_creature(removed.id)
	original.food.produce(FOOD_CELL, RAW, 2)
	original.rooms.remove([FOOD_CELL])
	original.grid.set_tile(FOOD_CELL, DungeonGrid.Tile.ROCK)
	var restored := _roundtrip(original)
	if restored == null:
		return
	_check(restored.economy.pending_gold() == 37 and restored.actors.is_empty() and restored.food.total_units == 2 and restored.food.units.size() == 2 and _conserved(restored), "Removed carrying actor and food on sold blocked terrain are retained")
	var scene := _attach(restored)
	_advance(scene, 1.0)
	_check(restored.economy.pending_gold() == 0 and restored.economy.ground_gold.values().reduce(func(total: int, amount: int) -> int: return total + amount, 0) == 37, "Reloaded worker recovery drops orphaned gold exactly once on reachable floor")
	_check(restored.food.total_units == 2 and restored.food.consumed_units == 0 and restored.food.sources.is_empty(), "Stranded food is accounted without being deleted or freely regenerated")
	_finish(scene)


func _sleeping_continues_to_wake_threshold() -> void:
	var original := _fixture()
	var actor := original.spawn_creature(SPECIES, Vector2i(5, 6))
	actor.satiety = 1.0
	actor.energy = 0.2
	var bed := original.beds.reserve(actor, original.registry.get_creature(SPECIES))
	actor.position = bed.center(original.grid)
	original.beds.establish(actor)
	var before := _attach(original)
	_advance(before, 1.0)
	actor.energy = 0.6
	_check(actor.action == &"sleeping" and actor.rest_requested, "Fixture saves a real sleeping creature between sleep and wake thresholds")
	var restored := _roundtrip(original)
	if restored == null:
		_finish(before)
		return
	var loaded := _actor(restored, actor.id)
	var after := _attach(restored)
	_advance(after, 0.5)
	_check(loaded.action == &"sleeping" and loaded.rest_requested and loaded.energy > 0.6, "Loaded sleeper resumes recovery instead of waking prematurely within hysteresis band")
	_advance(after, 5.0)
	_check(loaded.energy >= restored.registry.get_creature(SPECIES).wake_threshold and not loaded.rest_requested, "Restored sleeper wakes normally at species-defined threshold")
	_finish(after)
	_finish(before)


func _partial_meal_keeps_hunger_intent() -> void:
	var original := _fixture()
	original.registry.get_creature(SPECIES).capabilities = [&"eat"]
	original.registry.get_food(RAW).nutrition_per_unit = 0.4
	var actor := original.spawn_creature(SPECIES, FOOD_CELL)
	actor.satiety = 0.2
	original.food.produce(FOOD_CELL, RAW, 3)
	var before := _attach(original)
	for index in 90:
		_advance(before, STEP)
		if original.food.consumed_units == 1:
			break
	_check(original.food.consumed_units == 1 and actor.satiety > 0.3 and actor.satiety < 0.9 and actor.food_requested, "Fixture saves after one insufficient meal within hunger hysteresis band")
	var restored := _roundtrip(original)
	if restored == null:
		_finish(before)
		return
	var after := _attach(restored)
	_advance(after, 2.0)
	var loaded := _actor(restored, actor.id)
	_check(restored.food.consumed_units == 2 and loaded.satiety >= 0.9 and not loaded.food_requested, "Loaded creature finishes appetite target rather than abandoning a partial meal")
	_check(restored.food.total_units == 1 and restored.food.produced_units == 3, "Partial-meal reload consumes only the remaining necessary unit")
	_finish(after)
	_finish(before)


func _reject(data: Dictionary, context: GameContext, label: String) -> void:
	var result: Dictionary = _codec.restore(data, context.registry)
	_check(result.context == null and not result.error.is_empty(), "Malformed snapshot rejects with an error: %s" % label)


func _malformed_snapshots_are_rejected() -> void:
	var original := _fixture()
	var actor := original.spawn_creature(SPECIES, Vector2i(3, 3))
	var bed := original.beds.reserve(actor, original.registry.get_creature(SPECIES))
	actor.position = bed.center(original.grid)
	original.beds.establish(actor)
	original.keeper.pickup(actor.id)
	original.economy.drop_gold(PILE, original.economy.mine(GOLD, 41))
	original.keeper.pickup_gold(PILE)
	original.food.produce(FOOD_CELL, RAW, 1)
	var snapshot: Dictionary = _codec.capture(original)
	var unchanged := JSON.stringify(snapshot)
	var bad := _json_copy(snapshot)
	bad.version = 999
	_reject(bad, original, "future save version")
	bad = _json_copy(snapshot)
	bad.grid.width = 17.5
	_reject(bad, original, "fractional grid dimensions")
	bad = _json_copy(snapshot)
	bad.grid.tiles.pop_back()
	_reject(bad, original, "truncated terrain array")
	bad = _json_copy(snapshot)
	bad.rooms.append(bad.rooms[0].duplicate())
	_reject(bad, original, "duplicate room tile")
	bad = _json_copy(snapshot)
	bad.rooms[0][2] = "missing.room"
	_reject(bad, original, "missing room definition")
	bad = _json_copy(snapshot)
	bad.gold.remaining[0][2] = -1
	_reject(bad, original, "negative seam quantity")
	bad = _json_copy(snapshot)
	bad.gold.spent += 1
	_reject(bad, original, "unbalanced gold ledger")
	bad = _json_copy(snapshot)
	bad.gold.keeper += 1
	_reject(bad, original, "held gold differs from queued batches")
	bad = _json_copy(snapshot)
	bad.actors.append(bad.actors[0].duplicate(true))
	_reject(bad, original, "duplicate creature identity")
	bad = _json_copy(snapshot)
	bad.actors[0].definition = "missing.creature"
	_reject(bad, original, "missing creature definition")
	bad = _json_copy(snapshot)
	bad.actors[0].energy = NAN
	_reject(bad, original, "nonfinite creature need")
	bad = _json_copy(snapshot)
	bad.actors[0].position = [3, null, 4]
	_reject(bad, original, "nonnumeric creature position")
	bad = _json_copy(snapshot)
	bad.actors[0].name = "Bad\nName"
	_reject(bad, original, "control character in name")
	bad = _json_copy(snapshot)
	bad.hand.items.pop_front()
	_reject(bad, original, "held actor missing from custody")
	bad = _json_copy(snapshot)
	bad.hand.items[0].kind = "food"
	_reject(bad, original, "unsupported custody type")
	bad = _json_copy(snapshot)
	bad.hand.items[1].id = bad.hand.items[0].id
	_reject(bad, original, "duplicate queue identity")
	bad = _json_copy(snapshot)
	bad.hand.next_id = 1
	_reject(bad, original, "reused next custody identity")
	bad = _json_copy(snapshot)
	bad.hand.inspected = 9876
	_reject(bad, original, "missing inspected creature")
	bad = _json_copy(snapshot)
	bad.food.units.append(bad.food.units[0].duplicate(true))
	_reject(bad, original, "duplicate physical food identity")
	bad = _json_copy(snapshot)
	bad.food.produced += 1
	_reject(bad, original, "unbalanced food production")
	bad = _json_copy(snapshot)
	bad.food.next_id = 1
	_reject(bad, original, "reused next physical food identity")
	bad = _json_copy(snapshot)
	bad.beds.append(bad.beds[0].duplicate(true))
	_reject(bad, original, "overlapping duplicate personal bed")
	_check(JSON.stringify(_codec.capture(original)) == unchanged and original.keeper.held_count == 2 and actor.is_held and _conserved(original), "Every failed detached restore leaves the original dungeon, queue and ledgers untouched")


func _disk_replacement_and_failure() -> void:
	var original := _fixture()
	var actor := original.spawn_creature(SPECIES, Vector2i(3, 3))
	original.keeper.pickup(actor.id)
	var path := "user://tests/save-review-%d.json" % OS.get_process_id()
	var malformed_path := path + ".malformed"
	var snapshot: Dictionary = _codec.capture(original)
	_check(_store.write_save(path, snapshot, original.registry).is_empty(), "Validated save writes a real JSON file")
	var first := FileAccess.get_file_as_string(path)
	var bad := _json_copy(snapshot)
	bad.version = 99
	_check(not _store.write_save(path, bad, original.registry).is_empty() and FileAccess.get_file_as_string(path) == first, "Invalid replacement cannot overwrite a previously valid save")
	_check(not _store.write_save(path + "/blocked.json", snapshot, original.registry).is_empty() and FileAccess.get_file_as_string(path) == first, "Unwritable parent path reports failure and preserves existing save")
	actor.custom_name = "Saved Again"
	_check(_store.write_save(path, _codec.capture(original), original.registry).is_empty(), "A second valid snapshot safely replaces the first slot")
	var loaded: Dictionary = _store.read_save(path, original.registry)
	_check(loaded.error.is_empty() and loaded.context != null and loaded.context.keeper.held_actor.custom_name == "Saved Again", "Disk load restores exact latest held identity from the replaced slot")
	var backup := FileAccess.get_file_as_string(path + ".bak")
	_check(backup == first, "The discoverable recovery backup retains the previous valid snapshot")
	var interrupted_primary := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var recovered: Dictionary = _store.read_save(path, original.registry)
	_check(recovered.error.is_empty() and recovered.get("recovered_backup", false) and recovered.context.keeper.held_actor.custom_name.is_empty(), "Missing-primary interrupted rename recovers the intact previous slot with explicit recovery metadata")
	var primary := FileAccess.open(path, FileAccess.WRITE)
	primary.store_string("corrupt primary")
	primary.close()
	_check(not _store.write_save(path, _codec.capture(original), original.registry).is_empty() and FileAccess.get_file_as_string(path + ".bak") == backup and FileAccess.get_file_as_string(path) == "corrupt primary", "Saving over a corrupt primary preserves its last-good backup and reports a clear failure")
	_check(_store.read_save(path, original.registry).context == null, "Explicitly corrupt primary reports corruption instead of silently loading an older dungeon")
	primary = FileAccess.open(path, FileAccess.WRITE)
	primary.store_string(interrupted_primary)
	primary.close()
	var file := FileAccess.open(malformed_path, FileAccess.WRITE)
	file.store_string("{\"version\":1,")
	file.close()
	var result: Dictionary = _store.read_save(malformed_path, original.registry)
	_check(result.context == null and not result.error.is_empty(), "Truncated JSON file fails without producing a partial dungeon")
	file = FileAccess.open(malformed_path, FileAccess.WRITE)
	file.store_string("[]")
	file.close()
	result = _store.read_save(malformed_path, original.registry)
	_check(result.context == null and not result.error.is_empty(), "Array-root JSON fails clearly")
	_check(_store.read_save(path + ".missing", original.registry).context == null, "Missing file fails without a live replacement")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))


func _pending_bed_and_consumed_identity() -> void:
	var original := _fixture()
	var actor := original.spawn_creature(SPECIES, Vector2i(3, 3))
	actor.satiety = 1.0
	var bed := original.beds.reserve(actor, original.registry.get_creature(SPECIES))
	var anchor := bed.anchor
	var eater := original.spawn_creature(SPECIES, FOOD_CELL)
	original.food.produce(FOOD_CELL, RAW, 1)
	var consumed_id: int = original.food.units.keys()[0]
	original.food.reserve_meal(eater)
	_check(original.food.consume(eater) > 0 and original.food.total_units == 0, "Fixture removes a real stable food identity through consumption")
	original.despawn_creature(eater.id)
	var restored := _roundtrip(original)
	if restored == null:
		return
	var loaded := _actor(restored, actor.id)
	var loaded_bed := restored.beds.get_bed(actor.id)
	_check(loaded_bed != null and not loaded_bed.established and loaded_bed.anchor == anchor and loaded_bed.size == Vector2i(2, 1), "Pending sized footprint survives as an invisible reservation")
	var other := restored.spawn_creature(SPECIES, Vector2i(3, 3))
	var second_bed := restored.beds.reserve(other, restored.registry.get_creature(SPECIES))
	_check(second_bed != null and not second_bed.cells.any(func(cell: Vector2i) -> bool: return cell in loaded_bed.cells), "Restored pending occupancy prevents a second creature from stealing reserved space")
	restored.despawn_creature(other.id)
	restored.food.produce(FOOD_CELL, RAW, 1)
	_check(restored.food.units.size() == 1 and restored.food.units.keys()[0] > consumed_id and restored.food.consumed_units == 1, "New births never reuse a consumed pre-save food identity")
	var scene := _attach(restored)
	_advance(scene, 0.1)
	_check(not loaded_bed.established and loaded.position.distance_to(loaded_bed.center(restored.grid)) > DungeonBeds.CLAIM_DISTANCE, "Loading pending home does not remotely create its bed")
	_advance(scene, 7.0)
	_check(loaded_bed.established, "Restored creature walks to its original footprint and establishes locally")
	_finish(scene)


func _unmet_hunger_intent_survives() -> void:
	var original := _fixture()
	original.registry.get_creature(SPECIES).capabilities = [&"eat"]
	original.registry.get_food(RAW).nutrition_per_unit = 0.4
	var actor := original.spawn_creature(SPECIES, FOOD_CELL)
	actor.satiety = 0.2
	original.food.produce(FOOD_CELL, RAW, 1)
	var before := _attach(original)
	_advance(before, 2.0)
	_check(original.food.consumed_units == 1 and is_equal_approx(actor.satiety, 0.6) and not actor.food_requested, "Hungry fixture has eaten insufficient food and yielded movement while no further meal exists")
	var restored := _roundtrip(original)
	if restored == null:
		_finish(before)
		return
	var after := _attach(restored)
	original.food.produce(FOOD_CELL, RAW, 1)
	restored.food.produce(FOOD_CELL, RAW, 1)
	_advance(before, 2.0)
	_advance(after, 2.0)
	_check(original.food.consumed_units == 2 and restored.food.consumed_units == 2 and is_equal_approx(_actor(restored, actor.id).satiety, actor.satiety), "Unmet hunger intent persists through save while no food exists and resumes when food becomes available")
	_finish(after)
	_finish(before)


func _active_mining_and_cargo_resume() -> void:
	var original := _fixture()
	original.registry.get_creature(SPECIES).capabilities = [&"excavate", &"haul"]
	var actor := original.spawn_creature(SPECIES, Vector2i(13, 5))
	original.mark_excavation([GOLD])
	var before := _attach(original)
	_advance(before, 0.2)
	_check(actor.action == &"mining" and actor.work_progress > 0.0 and actor.work_progress < 1.0 and actor.carried_gold == 0, "Fixture saves during a real unfinished mining strike")
	var restored := _roundtrip(original)
	if restored == null:
		_finish(before)
		return
	var middle := _attach(restored)
	var loaded := _actor(restored, actor.id)
	for index in 120:
		_advance(middle, STEP)
		if loaded.carried_gold > 0:
			break
	_check(loaded.carried_gold == 20 and restored.economy.remaining_gold[GOLD] == 180 and _conserved(restored), "Resumed strike awards one extraction against one shared seam debit")
	var with_cargo := _roundtrip(restored)
	if with_cargo == null:
		_finish(middle)
		_finish(before)
		return
	var after := _attach(with_cargo)
	_advance(after, 65.0)
	_check(with_cargo.economy.stored_gold == 200 and with_cargo.economy.ground_gold.is_empty() and with_cargo.grid.get_tile(GOLD) == DungeonGrid.Tile.FLOOR and _actor(with_cargo, actor.id).carried_gold == 0, "Loading mid-mining then with cargo drains the finite seam into storage exactly once")
	_finish(after)
	_finish(middle)
	_finish(before)
