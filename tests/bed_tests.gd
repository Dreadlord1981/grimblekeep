extends SceneTree
## Definition contracts, footprint persistence and actor removal ledger safety.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_profiles()
	_test_personal_beds()
	_test_local_establishment()
	_test_cargo_despawn()
	print("BED CONTRACTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)


func _test_profiles() -> void:
	var creature := CreatureDefinition.new()
	creature.id = &"bed_tests.profile"
	_check(creature.validation_error().is_empty(), "Default creature profile remains registerable")
	creature.bed_size = Vector2i(0, 1)
	_check(not creature.validation_error().is_empty(), "Zero bed footprint rejected")
	creature.bed_size = Vector2i(2, 2)
	creature.initial_energy = NAN
	_check(not creature.validation_error().is_empty(), "Nonfinite initial energy rejected")
	creature.initial_energy = 0.5
	creature.sleep_restore_per_second = 0.0
	_check(not creature.validation_error().is_empty(), "Nonrecovering sleep profile rejected")
	creature.sleep_restore_per_second = 0.08
	creature.wake_threshold = creature.sleep_threshold
	_check(not creature.validation_error().is_empty(), "Rest hysteresis requires ordered thresholds")
	creature.wake_threshold = 0.9
	creature.portal_population_limit = -1
	_check(not creature.validation_error().is_empty(), "Negative recruitment limit rejected")
	creature.portal_population_limit = 0
	creature.food_per_meal = 0
	_check(not creature.validation_error().is_empty(), "Zero meal requirement rejected")
	creature.food_per_meal = 2
	creature.wage_gold = -1
	_check(not creature.validation_error().is_empty(), "Negative species wage rejected")
	creature.wage_gold = 5
	_check(creature.validation_error().is_empty(), "Larger bed/food/wage requirements need no species dispatch changes")


func _session() -> GameContext:
	var grid := DungeonGrid.new(8, 7)
	for y in range(1, 6):
		for x in range(1, 7):
			grid.set_tile(Vector2i(x, y), DungeonGrid.Tile.FLOOR)
	var registry := ContentRegistry.new()
	registry.register_module(load("res://content/modules/foundation.tres"))
	return GameContext.new(grid, registry)


func _test_personal_beds() -> void:
	var context := _session()
	var definition := CreatureDefinition.new()
	definition.id = &"bed_tests.large_resident"
	definition.bed_size = Vector2i(2, 2)
	definition.capabilities = [&"rest"]
	var module := ContentModule.new()
	module.id = &"bed_tests.residents"
	module.definitions = [definition]
	_check(context.registry.register_module(module).is_empty(), "Independent species with larger bed registers")
	var cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]
	context.rooms.place_initial(&"foundation.lair", cells)
	var actor := context.spawn_creature(definition.id, Vector2i(3, 3))
	_check(context.beds.reserve(actor, context.registry.get_creature(&"foundation.grubbin")) == null, "Reservation rejects a profile that does not belong to the actor")
	var bed := context.beds.reserve(actor, definition)
	_check(bed != null and bed.cells.size() == 4 and bed.owner_id == actor.id, "Personal large bed reserves all four cells for one resident")
	_check(bed.center(context.grid) == Vector3(3, 0, 3), "Even-sized bed center is derived from its actual footprint")
	_check(context.beds.reserve(actor, definition) == bed and context.beds.beds.size() == 1, "Repeated reservation preserves bed identity without duplication")
	var other := context.spawn_creature(&"foundation.grubbin", Vector2i(3, 3))
	_check(context.beds.reserve(other, context.registry.get_creature(other.definition_id)) == null, "A one-cell resident cannot overlap any part of a larger bed")
	context.rooms.place_initial(&"foundation.lair", [Vector2i(3, 2)])
	_check(context.beds.get_bed(actor.id) == bed, "Harmless room merge preserves personal bed identity")
	context.rooms.remove([Vector2i(1, 2)])
	_check(context.beds.get_bed(actor.id) == null, "Selling any cell releases the whole rectangular bed immediately")
	_check(context.beds.reserve(other, context.registry.get_creature(other.definition_id)) != null, "Released bed cells can be reused by a smaller species")
	_check(context.despawn_creature(other.id) and context.beds.get_bed(other.id) == null, "Despawn releases personal space immediately")
	_check(not context.despawn_creature(other.id), "Repeated actor removal is a no-op")
	_check(not context.beds.can_place(Vector2i(0, 0), Vector2i(2147483647, 2147483647), &"lair"), "Oversized footprints fail before scanning or arithmetic overflow")


func _test_cargo_despawn() -> void:
	var context := _session()
	context.grid.set_tile(Vector2i(6, 5), DungeonGrid.Tile.GOLD)
	var actor := context.spawn_creature(&"foundation.imp", Vector2i(2, 2))
	actor.carried_gold = context.economy.mine(Vector2i(6, 5), 60)
	var worker := preload("res://content/features/worker_feature.gd").new()
	worker.setup(context)
	worker.tick(1.0 / 30.0)
	# Cargo may have been dropped by the idle worker, so give it an actual finite
	# transfer again if needed before testing its removal from the live feature.
	if actor.carried_gold == 0:
		actor.carried_gold = context.economy.take_gold(Vector2i(2, 2), 60)
	_check(context.despawn_creature(actor.id) and context.economy.pending_gold() == 60, "Despawn retains cargo independently of feature lifetime")
	worker.tick(1.0 / 30.0)
	_check(context.economy.pending_cargo.is_empty() and context.economy.ground_gold.get(Vector2i(2, 2), 0) == 60, "Existing worker feature recovers retained cargo and clears the pending entry")
	_check(context.economy.accounted_gold(context.actors) == context.economy.initial_gold, "Actor removal conserves physical gold exactly once")
	worker.free()


func _test_local_establishment() -> void:
	var context := _session()
	context.rooms.place_initial(&"foundation.lair", [Vector2i(1, 1)])
	var actor := context.spawn_creature(&"foundation.grubbin", Vector2i(6, 5))
	var definition := context.registry.get_creature(actor.definition_id)
	var bed := context.beds.reserve(actor, definition)
	_check(bed != null and not bed.established, "Reserving capacity from far away does not establish a bed")
	_check(not context.beds.establish(actor) and not bed.established, "Authoritative claim command rejects remote establishment")
	var rival := context.spawn_creature(actor.definition_id, Vector2i(1, 1))
	_check(context.beds.reserve(rival, definition) == null and not context.beds.establish(rival), "Pending footprint excludes rivals without giving them local claim rights")
	actor.position = bed.center(context.grid) + Vector3(0.15, 0, 0)
	_check(not context.beds.establish(actor), "Being in the same tile is insufficient until the creature reaches its claim point")
	actor.position = bed.center(context.grid)
	var notifications: Array[int] = [0]
	context.beds.changed.connect(func() -> void: notifications[0] += 1)
	_check(context.beds.establish(actor) and bed.established and notifications[0] == 1, "Local owner establishes its bed and notifies views once")
	_check(context.beds.establish(actor) and notifications[0] == 1, "Repeated local establishment does not duplicate a bed or notification")
	context.rooms.remove([Vector2i(1, 1)])
	_check(not context.beds.establish(actor) and context.beds.get_bed(actor.id) == null, "A sold footprint cannot complete a stale local claim")
