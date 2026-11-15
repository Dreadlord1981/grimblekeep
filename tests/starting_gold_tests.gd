extends SceneTree
## Actual startup bank, finite supply and full-Treasury mining behavior.

const Layout = preload("res://content/scenarios/foundation_layout.gd")
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_default_helper()
	var app := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	_check(app.starting_gold == 3000, "Actual game scene defaults to a 3000-gold bank")
	root.add_child(app)
	app.set_physics_process(false)
	await process_frame
	var context: GameContext = app.context
	var economy := context.economy
	var finite_supply := context.grid.cells_of_type(DungeonGrid.Tile.GOLD).size() * GoldEconomy.GOLD_PER_SEAM
	_check(economy.stored_gold == 3000 and economy.treasury_capacity == 3000, "Fresh game physically stores 3000 gold in matching Treasury capacity")
	_check(economy.treasury_cells.size() == 6 and economy.stored_by_cell.size() == 6, "The initial bank occupies six real Treasury tiles")
	var exact_tiles := true
	for cell in economy.treasury_cells:
		exact_tiles = exact_tiles and economy.stored_by_cell.get(cell, 0) == 500 and economy.available_storage(cell) == 0
	_check(exact_tiles, "Every starting Treasury tile contains exactly its 500-gold capacity")
	_check(economy.initial_gold == finite_supply + 3000 and economy.accounted_gold(context.actors) == economy.initial_gold, "Starting bank is recorded once alongside unchanged finite seam supply")
	var initial := economy.initial_gold
	for tick in 120:
		app.call("_physics_process", 1.0 / 30.0)
	for feature: GameFeature in app.get("_features"):
		feature.setup(context)
	for tick in 120:
		app.call("_physics_process", 1.0 / 30.0)
	_check(economy.stored_gold == 3000 and economy.initial_gold == initial and economy.gem_gold_created == 0, "Ordinary ticks and feature reloads cannot grant another startup bank")
	var seam := Vector2i(8, 12)
	context.mark_excavation([seam])
	for tick in 120:
		app.call("_physics_process", 1.0 / 30.0)
	_check(economy.remaining_gold.get(seam, 0) == 200 and economy.stored_gold == 3000, "Starting full Treasury pauses marked mineral mining")
	var result := context.rooms.build(&"foundation.lair", [Vector2i(12, 12)])
	_check(result.success and result.cost == 50 and economy.stored_gold == 2950 and economy.spent_gold == 50, "Starting bank can immediately pay the real room construction cost")
	_check(economy.treasury_capacity == 3000, "Spending alone frees storage without changing its capacity")
	var conserved := true
	var resumed := false
	for tick in 1500:
		app.call("_physics_process", 1.0 / 30.0)
		conserved = conserved and economy.accounted_gold(context.actors) == initial + economy.gem_gold_created
		resumed = resumed or economy.remaining_gold.get(seam, 0) < 200
		if economy.stored_gold == 3000:
			break
	_check(resumed and economy.stored_gold == 3000, "Spending automatically resumes physical mining and delivery until storage fills again")
	var remaining: int = economy.remaining_gold.get(seam, 0)
	for tick in 180:
		app.call("_physics_process", 1.0 / 30.0)
		conserved = conserved and economy.accounted_gold(context.actors) == initial + economy.gem_gold_created
	_check(economy.remaining_gold.get(seam, 0) == remaining and context.excavation_marks.has(seam), "Refilled storage pauses mining again while preserving the excavation order")
	_check(conserved and economy.initial_gold == initial, "Startup, spending, paused mining and resumed delivery conserve the original bank and finite seams")
	app.queue_free()
	await process_frame
	var zero := (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	zero.starting_gold = 0
	root.add_child(zero)
	zero.set_physics_process(false)
	_check(zero.context.economy.stored_gold == 0 and zero.context.economy.treasury_capacity == 2000, "Explicit zero-bank scenes preserve mining-only verification scenarios")
	_check(zero.context.economy.initial_gold == finite_supply, "Zero-bank game initialization introduces no unrecorded supply")
	zero.queue_free()
	await process_frame
	for failure in _failures:
		push_error(failure)
	print("STARTING GOLD RESULT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _default_helper() -> void:
	var registry := ContentRegistry.new()
	_check(registry.register_module(load("res://content/modules/foundation.tres")).is_empty(), "Starting-bank test loads real foundation definitions")
	var context := GameContext.new(Layout.create(), registry)
	var finite := context.economy.initial_gold
	Layout.setup_rooms(context)
	_check(context.economy.stored_gold == 0 and context.economy.treasury_capacity == 2000 and context.economy.treasury_cells.size() == 4, "Scenario helper defaults to four empty Treasury tiles for existing fixtures")
	_check(context.economy.initial_gold == finite and context.economy.accounted_gold(context.actors) == finite, "Default helper preserves the exact finite seam supply")


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)
