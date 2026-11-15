extends SceneTree
## Actual protected Heart bank and mining before any Treasury room exists.

const Layout = preload("res://content/scenarios/foundation_layout.gd")
const SEAM := Vector2i(17, 15)
const STEP := 1.0 / 30.0
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_helpers()
	await _fresh_start()
	await _full_storage()
	for failure in _failures:
		push_error(failure)
	print("STARTING GOLD RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _helpers() -> void:
	var registry := ContentRegistry.new()
	_check(registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Startup test loads real foundation definitions")
	var context := GameContext.new(Layout.create(), registry)
	var finite := context.economy.initial_gold
	Layout.setup_rooms(context)
	_check(context.rooms.tiles.is_empty() and context.economy.protected_storage.size() == 8 and context.economy.treasury_capacity == 4000 and context.economy.stored_gold == 0, "Default helper provides eight empty protected Heart cells, with no Treasury")
	_check(context.economy.initial_gold == finite and context.economy.accounted_gold(context.actors) == finite, "Zero-bank helper introduces no gold")
	var legacy := GameContext.new(Layout.create(), registry)
	Layout.setup_rooms(legacy, 0, false)
	_check(legacy.economy.protected_storage.is_empty() and legacy.rooms.tiles.size() == 4 and legacy.economy.treasury_capacity == 2000, "Explicit legacy helper retains four empty Treasury tiles")


func _fresh_start() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_check(app.starting_gold == 3000 and app.use_heart_storage, "Actual game defaults to a 3000-gold Heart bank")
	root.add_child(app)
	app.set_physics_process(false)
	await process_frame
	var context: GameContext = app.context
	var economy := context.economy
	var finite := context.grid.cells_of_type(DungeonGrid.Tile.GOLD).size() * 200
	_check(economy.stored_gold == 3000 and economy.treasury_capacity == 4000 and economy.protected_storage.size() == 8, "Fresh game has 3000 stored gold and eight protected cells totaling 4000 capacity")
	_check(context.rooms.tiles.is_empty() and context.rooms.get_rooms().is_empty(), "Fresh game has no prebuilt Treasury or other room")
	var valid := true
	var total := 0
	for cell in economy.protected_storage:
		var offset: Vector2i = cell - Vector2i(14, 15)
		var amount: int = economy.stored_by_cell.get(cell, 0)
		valid = valid and cell != Vector2i(14, 15) and absi(offset.x) <= 1 and absi(offset.y) <= 1 and context.grid.get_tile(cell) == DungeonGrid.Tile.FLOOR and economy.storage_capacity(cell) == 500 and amount >= 0 and amount <= 500
		total += amount
	_check(valid and total == 3000, "Physical starting stock fits the eight 500-capacity floor cells around the Heart")
	var initial := economy.initial_gold
	_check(initial == finite + 3000 and economy.accounted_gold(context.actors) == initial, "Startup bank is recorded once beside finite seam supply")
	for tick in 120:
		app.call("_physics_process", STEP)
	for feature: GameFeature in app.get("_features"):
		feature.setup(context)
	for tick in 120:
		app.call("_physics_process", STEP)
	_check(economy.stored_gold == 3000 and economy.initial_gold == initial and economy.gem_gold_created == 0, "Ticks and feature reloads cannot duplicate the startup bank")
	context.mark_excavation([SEAM])
	var conserved := true
	for tick in 3600:
		app.call("_physics_process", STEP)
		conserved = conserved and economy.accounted_gold(context.actors) == initial + economy.gem_gold_created
		if economy.stored_gold == 3200:
			break
	_check(economy.stored_gold == 3200 and context.grid.get_tile(SEAM) == DungeonGrid.Tile.FLOOR, "Workers mine and deliver a complete seam into Heart storage before a Treasury exists")
	_check(context.rooms.tiles.is_empty() and conserved, "Bootstrap hauling requires no room and conserves the finite bank")
	app.queue_free()
	await process_frame
	var zero := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	zero.starting_gold = 0
	zero.use_heart_storage = false
	root.add_child(zero)
	zero.set_physics_process(false)
	_check(zero.context.economy.stored_gold == 0 and zero.context.economy.treasury_capacity == 2000 and zero.context.economy.protected_storage.is_empty(), "Explicit zero-bank legacy scene remains available for mining fixtures")
	_check(zero.context.economy.initial_gold == finite, "Legacy zero-bank initialization preserves finite supply")
	zero.queue_free()
	await process_frame


func _full_storage() -> void:
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(app)
	app.set_physics_process(false)
	await process_frame
	var context: GameContext = app.context
	var economy := context.economy
	var initial := economy.initial_gold
	var supplied := 0
	for cell in context.grid.cells_of_type(DungeonGrid.Tile.GOLD):
		if cell != SEAM:
			supplied += economy.mine(cell, 200)
	var remaining := supplied
	for cell in economy.treasury_cells:
		var amount := mini(remaining, economy.available_storage(cell))
		if amount > 0:
			economy.deposit(cell, amount)
			remaining -= amount
	_check(supplied == 1000 and remaining == 0 and economy.stored_gold == 4000 and economy.remaining_gold[SEAM] == 200, "Five finite seams fill Heart storage while one untouched seam is reserved")
	context.mark_excavation([SEAM])
	for tick in 240:
		app.call("_physics_process", STEP)
	_check(economy.remaining_gold[SEAM] == 200 and context.excavation_marks.has(SEAM), "Full 4000-capacity Heart storage pauses marked mineral mining")
	var protected_cells: Array[Vector2i] = []
	protected_cells.assign(economy.protected_storage.keys())
	_check(not context.rooms.build(&"foundation.treasury", protected_cells).success and not context.rooms.remove(protected_cells).success, "Protected Heart cells reject room construction and selling")
	_check(economy.stored_gold == 4000 and economy.protected_storage.size() == 8 and context.rooms.tiles.is_empty(), "Rejected protected-area commands leave bank and capacity unchanged")
	_check(economy.spend(50), "Stored Heart gold can be spent to free capacity")
	var resumed := false
	var conserved := true
	for tick in 2400:
		app.call("_physics_process", STEP)
		conserved = conserved and economy.accounted_gold(context.actors) == initial + economy.gem_gold_created
		resumed = resumed or economy.remaining_gold.get(SEAM, 0) < 200
		if economy.stored_gold == 4000:
			break
	_check(resumed and economy.stored_gold == 4000 and economy.treasury_capacity == 4000, "Spending resumes mining and delivery into protected storage")
	for tick in 120:
		app.call("_physics_process", STEP)
	var paused: int = economy.remaining_gold.get(SEAM, 0)
	for tick in 120:
		app.call("_physics_process", STEP)
	_check(economy.remaining_gold.get(SEAM, 0) == paused and context.excavation_marks.has(SEAM), "Refilled Heart storage pauses the retained mining order again")
	var built := context.rooms.build(&"foundation.treasury", [Vector2i(12, 17)])
	_check(built.success and built.cost == 50 and economy.treasury_capacity == 4500 and economy.protected_storage.size() == 8, "Player-built Treasury adds capacity alongside protected Heart storage")
	for tick in 2400:
		app.call("_physics_process", STEP)
		conserved = conserved and economy.accounted_gold(context.actors) == initial + economy.gem_gold_created
		if context.grid.get_tile(SEAM) == DungeonGrid.Tile.FLOOR and context.actors.all(func(actor: CreatureState) -> bool: return actor.carried_gold == 0) and economy.ground_gold.is_empty():
			break
	_check(context.grid.get_tile(SEAM) == DungeonGrid.Tile.FLOOR and context.actors.all(func(actor: CreatureState) -> bool: return actor.carried_gold == 0) and economy.ground_gold.is_empty(), "Added Treasury capacity lets workers finish the reserved seam and store all outstanding gold")
	var sold := context.rooms.remove([Vector2i(12, 17)])
	_check(sold.success and economy.treasury_capacity == 4000 and economy.protected_storage.size() == 8, "Selling the added Treasury preserves all eight protected Heart cells")
	_check(conserved and economy.accounted_gold(context.actors) == initial + economy.gem_gold_created and economy.initial_gold == initial, "Startup, full-storage pauses, spending, expansion and sale conserve supply")
	app.queue_free()
	await process_frame
