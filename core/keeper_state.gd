class_name KeeperState
extends RefCounted
## Authoritative creature inspection and custody. Input/views only send commands.

signal changed
signal actor_control_changed(actor: CreatureState)

const INVALID_CELL := Vector2i(-1, -1)
const MAX_NAME_LENGTH := 32
const CARDINALS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var _context_ref: WeakRef
var _inspected: CreatureState
var _items: Array[KeeperHandItem] = []
var _next_item_id := 1
var held_count: int:
	get:
		return _items.size()
var held_actor: CreatureState:
	get:
		var item := peek_item()
		return item.actor if item != null and item.kind == &"creature" and _is_live(item.actor) else null
var inspected_actor: CreatureState:
	get:
		return _inspected if _is_live(_inspected) and _context().is_actor_visible(_inspected) else null
var held_gold: int:
	get:
		var item := peek_item()
		return item.gold_amount if item != null and item.kind == &"gold" else 0
var total_held_gold: int:
	get:
		var context := _context()
		return context.economy.keeper_gold if context != null else 0


func _init(context: GameContext) -> void:
	_context_ref = weakref(context)
	context.actor_removed.connect(_on_actor_removed)
	context.simulation_ticked.connect(_on_simulation_ticked)


func inspect(actor_id: int) -> bool:
	var actor := _find_actor(actor_id)
	if actor == null or not _context().is_actor_visible(actor):
		return false
	if _inspected != actor:
		_inspected = actor
		changed.emit()
	return true


func clear_inspection() -> void:
	if _inspected != null:
		_inspected = null
		changed.emit()


func rename_selected(text: String) -> bool:
	var actor := inspected_actor
	var cleaned := text.strip_edges()
	if actor == null or cleaned.length() > MAX_NAME_LENGTH:
		return false
	for index in cleaned.length():
		if cleaned.unicode_at(index) < 32 or cleaned.unicode_at(index) == 127:
			return false
	if actor.custom_name != cleaned:
		actor.custom_name = cleaned
		changed.emit()
	return true


func pickup(actor_id: int) -> bool:
	prune()
	var context := _context()
	var actor := _find_actor(actor_id)
	if context == null or actor == null or actor.is_held or not actor.position.is_finite() or not context.is_actor_visible(actor):
		return false
	for item in _items:
		if item.kind == &"creature" and item.actor == actor:
			return false
	var definition := context.registry.get_creature(actor.definition_id)
	if definition == null or not definition.keeper_pickup_allowed:
		return false
	var item := _new_item(&"creature", context.grid.world_to_cell(actor.position))
	item.actor = actor
	_items.append(item)
	_inspected = actor
	actor.is_held = true
	context.food.release(actor.id)
	var bed := context.beds.get_bed(actor.id)
	if bed != null and not bed.established:
		context.beds.release(actor.id)
	actor_control_changed.emit(actor)
	_set_idle_state(actor, true)
	changed.emit()
	return true


func is_holding() -> bool:
	return not _items.is_empty()


func get_items() -> Array[KeeperHandItem]:
	return _items.duplicate()


func next_item_id() -> int:
	return _next_item_id


func restore_custody(items: Array[KeeperHandItem], next_id: int, inspected: CreatureState) -> void:
	# Called on a detached, validated session before features subscribe.
	_items = items.duplicate()
	_next_item_id = next_id
	_inspected = inspected


func peek_item() -> KeeperHandItem:
	return _items[0] if not _items.is_empty() else null


func _new_item(kind: StringName, origin: Vector2i) -> KeeperHandItem:
	var item := KeeperHandItem.new()
	item.id = _next_item_id
	_next_item_id += 1
	item.kind = kind
	item.origin = origin
	return item


func pickup_gold(cell: Vector2i, amount: int = -1) -> bool:
	prune()
	var context := _context()
	if context == null or not context.exploration.is_revealed(cell) or context.economy.gold_at(cell) <= 0:
		return false
	var taken := context.economy.pickup_for_keeper(cell, amount)
	if taken <= 0:
		return false
	var item := _new_item(&"gold", cell)
	item.gold_amount = taken
	_items.append(item)
	changed.emit()
	return true


func quote_drop(cell: Vector2i) -> Dictionary:
	var quote := {"cell": cell, "valid": false, "reason": "The hand is empty"}
	var context := _context()
	if not is_holding() or context == null:
		return quote
	if not context.exploration.is_revealed(cell):
		quote.reason = "Explore that area before dropping here"
		return quote
	if not context.grid.is_inside(cell) or context.grid.get_tile(cell) != DungeonGrid.Tile.FLOOR:
		quote.reason = "Drop on excavated dungeon floor"
		return quote
	if not _is_accessible(cell):
		quote.reason = "That floor is disconnected from the dungeon"
		return quote
	# Creature/bed occupancy is not terrain ownership. Valid floor can be shared;
	# each dropped creature keeps its own identity, cargo and personal bed.
	quote.valid = true
	quote.reason = "Drop gold here" if held_gold > 0 else "Drop creature here"
	return quote


func drop(cell: Vector2i) -> Dictionary:
	prune()
	var result := quote_drop(cell)
	result.success = false
	if not result.valid:
		return result
	var item := peek_item()
	result.item_id = item.id
	result.kind = item.kind
	if item.kind == &"gold":
		result.amount = _context().economy.drop_from_keeper(cell, item.gold_amount)
		result.success = result.amount > 0
		if result.amount > 0:
			item.gold_amount -= result.amount
			if item.gold_amount == 0:
				_items.pop_front()
		changed.emit()
		return result
	var actor := item.actor
	actor.position = _context().grid.cell_to_world(cell)
	actor.is_held = false
	_items.pop_front()
	actor_control_changed.emit(actor)
	_set_idle_state(actor, false)
	result.success = true
	changed.emit()
	return result


func prune() -> void:
	var modified := false
	for index in range(_items.size() - 1, -1, -1):
		var item := _items[index]
		if item.kind != &"creature" or _is_live(item.actor):
			continue
		var context := _context()
		if context != null:
			# Raw array edits may bypass despawn; no active worker owns this cargo.
			context.economy.retain_removed_actor(item.actor)
			context.food.release(item.actor.id)
			context.beds.release(item.actor.id)
		item.actor.is_held = false
		_items.remove_at(index)
		modified = true
	if _inspected != null and not _is_live(_inspected):
		_inspected = null
		modified = true
	if modified:
		changed.emit()


func _set_idle_state(actor: CreatureState, held: bool) -> void:
	actor.rest_requested = false
	actor.food_requested = false
	actor.work_progress = 0.0
	actor.target_cell = INVALID_CELL
	actor.action = &"held" if held else &"idle"
	actor.job_label = "Held by the keeper" if held else "Finding a new task after being dropped"


func _is_accessible(cell: Vector2i) -> bool:
	var context := _context()
	var hearts := context.grid.cells_of_type(DungeonGrid.Tile.HEART)
	if hearts.is_empty():
		var item := peek_item()
		return item != null and not GridPathfinder.find_path(context.grid, item.origin, cell).is_empty()
	for heart in hearts:
		for offset: Vector2i in CARDINALS:
			if not GridPathfinder.find_path(context.grid, heart + offset, cell).is_empty():
				return true
	return false


func _context() -> GameContext:
	return _context_ref.get_ref() as GameContext if _context_ref != null else null


func _is_live(actor: CreatureState) -> bool:
	var context := _context()
	return actor != null and context != null and actor in context.actors


func _find_actor(actor_id: int) -> CreatureState:
	var context := _context()
	if context != null:
		for actor in context.actors:
			if actor.id == actor_id:
				return actor
	return null


func _on_actor_removed(_actor: CreatureState) -> void:
	prune()


func _on_simulation_ticked(_delta: float) -> void:
	prune()
