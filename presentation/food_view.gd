class_name DungeonFoodView
extends Node3D
## Reconcile physical stock units without resetting them on reservation events.

var _context: GameContext
var _units: Dictionary[int, Node3D] = {}
var _dirty := false


func setup(context: GameContext) -> void:
	_context = context
	_context.food.changed.connect(_queue_refresh)
	_refresh()


func _queue_refresh() -> void:
	if not _dirty:
		_dirty = true
		_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	var wanted: Dictionary[int, bool] = {}
	for food in _context.food.units.values():
		var definition := _context.registry.get_food(food.food_id)
		if definition == null:
			continue
		wanted[food.id] = true
		if not _units.has(food.id):
			_units[food.id] = _make_unit(definition, food)
	for key in _units.keys():
		if not wanted.has(key):
			_units[key].queue_free()
			_units.erase(key)
	_sync_units()


func _make_unit(definition: FoodDefinition, food: FoodUnitState) -> Node3D:
	var unit := Node3D.new()
	unit.name = "FoodUnit_%d" % food.id
	unit.set_meta("food_id", definition.id)
	unit.set_meta("cell", food.cell)
	unit.set_meta("unit_id", food.id)
	add_child(unit)
	var view: Node3D
	if definition.view_scene != null:
		var candidate := definition.view_scene.instantiate()
		if candidate is Node3D:
			view = candidate
		else:
			candidate.free()
			push_warning("Food view_scene must have a Node3D root: %s" % definition.id)
	if view == null:
		view = Node3D.new()
		var chunk := DungeonGeometry.sphere(view, Vector3(0, 0.19, 0), Vector3(0.35, 0.30, 0.35), DungeonGeometry.material(definition.body_color), 6)
		chunk.position.x = -0.20 if food.id % 2 == 0 else 0.20
	unit.add_child(view)
	if view.has_method("configure_food"):
		view.call("configure_food", definition, food.id, food.cell)
	return unit


func _process(_delta: float) -> void:
	if _context != null:
		_sync_units()


func _sync_units() -> void:
	for id in _units:
		var food: FoodUnitState = _context.food.units.get(id)
		if food == null:
			continue
		var definition := _context.registry.get_food(food.food_id)
		var node := _units[id]
		var cell := _context.grid.world_to_cell(food.position)
		node.position = food.position + Vector3.UP * (0.12 if _context.rooms.tiles.has(cell) else 0.0)
		node.rotation.y = food.heading
		var maturity := clampf(food.age_seconds / definition.growth_seconds, 0.0, 1.0) if definition.growth_seconds > 0.0 else 1.0
		var size := lerpf(definition.newborn_scale, 1.0, maturity)
		node.scale = Vector3.ONE * size
		node.set_meta("maturity", maturity)
		var view := node.get_child(0)
		if view.has_method("sync_food"):
			view.call("sync_food", food)
