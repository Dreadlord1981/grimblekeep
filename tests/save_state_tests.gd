extends SceneTree
## Persistence boundary failures, monotonic identities and safe disk replacement.

const Layout = preload("res://content/scenarios/foundation_layout.gd")
var _checks := 0
var _failures: Array[String] = []
var _registry: ContentRegistry
var _path := "user://tests/state-%d/dungeon.json" % OS.get_process_id()


func _initialize() -> void:
	_registry = ContentRegistry.new()
	_check(_registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Definitions register")
	var context := GameContext.new(Layout.create(), _registry)
	Layout.setup_rooms(context, 3000)
	var imp := context.spawn_creature(&"foundation.imp", Vector2i(12, 16))
	var retired := context.spawn_creature(&"foundation.imp", Vector2i(12, 17))
	context.despawn_creature(retired.id)
	_check(context.rooms.build(&"foundation.lair", [Vector2i(11, 17), Vector2i(12, 17)]).success, "Fixture builds Lair")
	_check(context.rooms.build(&"foundation.pig_pen", [Vector2i(10, 19), Vector2i(11, 19), Vector2i(12, 19), Vector2i(13, 19)]).success, "Fixture builds Pig Pen")
	var resident := context.spawn_creature(&"foundation.grubbin", Vector2i(12, 17))
	resident.custom_name = "Snort 🐽"
	resident.energy = 0.42
	resident.satiety = 0.31
	var bed := context.beds.reserve(resident, _registry.get_creature(resident.definition_id))
	_check(bed != null and not bed.established, "Fixture has an invisible pending bed")
	var source: Vector2i = context.food.sources.keys()[0]
	context.food.sources[source].progress = 7.75
	context.food.produce(source, &"foundation.cave_pig", 1)
	var pig: FoodUnitState = context.food.units.values()[0]
	pig.age_seconds = 13.25
	pig.position += Vector3(0.15, 0, 0.2)
	imp.carried_gold = context.economy.mine(Vector2i(8, 12), 33)
	context.keeper.pickup(imp.id)
	context.keeper.pickup_gold(context.economy.stored_by_cell.keys()[0], 123)
	context.keeper.inspect(resident.id)
	context.mark_excavation([Vector2i(8, 12), Vector2i(8, 18)])
	var snapshot := DungeonSave.capture(context)
	var result := DungeonSave.restore(_json_copy(snapshot), _registry)
	_check(result.error.is_empty() and result.context != null, "Complex JSON round trip succeeds: %s" % result.error)
	if result.context != null:
		var restored: GameContext = result.context
		_check(restored.actors[1].custom_name == resident.custom_name, "Unicode creature names survive UTF-8 JSON")
		_check(restored.beds.get_bed(resident.id) != null and not restored.beds.get_bed(resident.id).established, "Pending bed remains exclusive and invisible")
		_check(not restored.beds.can_place(bed.anchor, bed.size, bed.room_tag), "Restored pending bed occupies its footprint")
		_check(restored.food.sources[source].progress == 7.75 and restored.food.units[pig.id].position.is_equal_approx(pig.position), "Producer partial interval and roaming food position survive")
		_check(restored.keeper.held_count == 2 and restored.keeper.held_actor.carried_gold == 33 and restored.keeper.inspected_actor.id == resident.id, "Held carrier, separate batch and inspection survive")
		var spawned := restored.spawn_creature(&"foundation.imp", Vector2i(12, 18))
		_check(spawned.id == context.next_actor_id() and spawned.id > retired.id, "Retired actor identities are never reused")
		_check(restored.economy.accounted_gold(restored.actors) == restored.economy.initial_gold + restored.economy.gem_gold_created, "Round trip preserves complete gold ledger")
	_corruption(snapshot)
	_disk(snapshot)
	for failure in _failures:
		push_error(failure)
	print("SAVE STATE: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _json_copy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _reject(data: Dictionary, label: String) -> void:
	var result := DungeonSave.restore(data, _registry)
	_check(result.context == null and not result.error.is_empty(), label)


func _corruption(original: Dictionary) -> void:
	for section in ["grid", "rooms", "marks", "gold", "actors", "pending_cargo", "next_actor_id", "beds", "hand", "food", "features"]:
		var data := original.duplicate(true)
		data.erase(section)
		_reject(data, "Missing %s is rejected" % section)
	var data := original.duplicate(true)
	data.version = 500
	_reject(data, "Unknown version rejects")
	data = original.duplicate(true)
	data.grid.width = true
	_reject(data, "Boolean does not pass numeric dimensions")
	data = original.duplicate(true)
	data.grid.width = 0.5
	_reject(data, "Fractional dimensions reject")
	data = original.duplicate(true)
	data.grid.tiles[0] = 99
	_reject(data, "Unknown terrain rejects")
	data = original.duplicate(true)
	data.gold.initial += 1
	_reject(data, "Unbalanced physical gold rejects")
	data = original.duplicate(true)
	data.hand.items[1].gold += 1
	_reject(data, "Queue/held-ledger mismatch rejects")
	data = original.duplicate(true)
	data.actors[0].position[0] = INF
	_reject(data, "Nonfinite creature position rejects")
	data = original.duplicate(true)
	data.actors[0].definition = "missing.species"
	_reject(data, "Unknown species rejects")
	data = original.duplicate(true)
	data.food.units[0].food = "missing.food"
	_reject(data, "Unknown physical food rejects")
	data = original.duplicate(true)
	data.beds.append(data.beds[0].duplicate(true))
	_reject(data, "Overlapping duplicate homes reject")
	data = original.duplicate(true)
	data.food.stock[0][3] += 1
	_reject(data, "Stock without matching physical food rejects")
	data = original.duplicate(true)
	data.food.sources[0].progress = -1
	_reject(data, "Negative producer progress rejects")
	data = original.duplicate(true)
	data.food.next_id = data.food.units[0].id
	_reject(data, "Food identity reuse rejects")
	data = original.duplicate(true)
	data.gold.initial = SaveReader.MAX_INTEGER
	data.gold.gem_created = 1
	_reject(data, "Gold supply exceeding exact JSON integer range rejects")
	data = original.duplicate(true)
	data.gold.ground.append([0, 0, SaveReader.MAX_INTEGER])
	_reject(data, "Oversized physical gold total rejects before integer overflow")
	data = original.duplicate(true)
	data.beds[0].size = [2, 1]
	_reject(data, "Changed bed profile rejects rather than silently resizing")
	data = original.duplicate(true)
	data.food.sources[0].capacity += 1
	_reject(data, "Changed food producer profile rejects rather than changing capacity")


func _disk(snapshot: Dictionary) -> void:
	_clean()
	_check(DungeonSaveStore.write_save(_path, snapshot, _registry).is_empty(), "Writes verified save to disk")
	var initial_bytes := FileAccess.get_file_as_bytes(_path)
	var bad := snapshot.duplicate(true)
	bad.gold.keeper += 1
	_check(not DungeonSaveStore.write_save(_path, bad, _registry).is_empty() and FileAccess.get_file_as_bytes(_path) == initial_bytes, "Invalid state cannot overwrite previous valid save")
	bad = snapshot.duplicate(true)
	bad.version = 500
	_check(not DungeonSaveStore.write_save(_path, bad).is_empty() and FileAccess.get_file_as_bytes(_path) == initial_bytes, "Unknown format cannot overwrite even without a registry")
	var second := snapshot.duplicate(true)
	second.actors[0].name = "New name"
	_check(DungeonSaveStore.write_save(_path, second, _registry).is_empty(), "A second valid save replaces the slot")
	_check(FileAccess.get_file_as_bytes(_path + ".bak") == initial_bytes, "Previous valid save remains as recoverable backup")
	var result := DungeonSaveStore.read_save(_path, _registry)
	_check(result.error.is_empty() and result.context.actors[0].custom_name == "New name", "Read returns the current complete save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	result = DungeonSaveStore.read_save(_path, _registry)
	_check(result.error.is_empty() and result.get("recovered_backup", false) and result.context.actors[0].custom_name == snapshot.actors[0].name, "Interrupted rename recovers the prior complete backup")
	var broken := FileAccess.open(_path, FileAccess.WRITE)
	broken.store_string("{broken json")
	broken.close()
	result = DungeonSaveStore.read_save(_path, _registry)
	_check(result.context == null and not result.error.is_empty(), "An explicitly corrupt primary reports an error")
	_check(FileAccess.get_file_as_bytes(_path + ".bak") == initial_bytes, "Reading corruption never modifies valid backup")
	_check(not DungeonSaveStore.write_save(_path, second, _registry).is_empty() and FileAccess.get_file_as_bytes(_path + ".bak") == initial_bytes, "Saving cannot rotate a corrupt primary over last-good backup")
	_clean()
	_check(not DungeonSaveStore.read_save(_path, _registry).error.is_empty(), "Missing save reports a useful error")
	_check(not DungeonSaveStore.write_save("", snapshot, _registry).is_empty(), "Empty save path rejects")
	var occupied := ProjectSettings.globalize_path(_path.get_base_dir().path_join("occupied"))
	DirAccess.make_dir_recursive_absolute(occupied)
	_check(not DungeonSaveStore.write_save(occupied, snapshot, _registry).is_empty() and DirAccess.dir_exists_absolute(occupied), "A destination directory fails safely without deleting it")
	DirAccess.remove_absolute(occupied)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path.get_base_dir()))


func _clean() -> void:
	for path in [_path, _path + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
