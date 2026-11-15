class_name KeeperCreatureInput
extends RefCounted
## Immediate left pickup and explicit right drop, independent of terrain drags.

signal action_finished(result: Dictionary)

var is_acting := false
var _keeper: KeeperController
var _context: GameContext
var _left_captured := false
var _right_drop_active := false


func _init(controller: KeeperController, context: GameContext) -> void:
	_keeper = controller
	_context = context


func has_pending() -> bool:
	return _left_captured


func cancel() -> void:
	_left_captured = false
	# Keep suppressing a right-drop button's motion until release, even after
	# custody becomes empty. This prevents accidental post-drop camera orbit.


func begin(screen: Vector2) -> bool:
	cancel()
	var actor: CreatureState = _keeper.get_target_actor(screen)
	if actor != null:
		_left_captured = true
		lift(actor.id)
		return true
	var cell := _keeper.get_target_cell(screen)
	if _context.grid.is_inside(cell) and _context.grid.get_tile(cell) == DungeonGrid.Tile.FLOOR and _context.economy.gold_at(cell) > 0:
		_left_captured = true
		is_acting = true
		var success := _context.keeper.pickup_gold(cell)
		is_acting = false
		action_finished.emit({"success": success, "reason": "Gold picked up" if success else "That gold cannot be picked up"})
		return true
	if _context.keeper.is_holding():
		_left_captured = true
		return true
	return false


func observe(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _context.keeper.is_holding():
			cancel()
			_right_drop_active = true
			if not _keeper.is_pointer_over_ui(event.position):
				is_acting = true
				var result := _context.keeper.drop(_keeper.get_target_cell(event.position))
				is_acting = false
				action_finished.emit(result)
			return true
		if not event.pressed and _right_drop_active:
			_right_drop_active = false
			return true
		if event.pressed:
			_right_drop_active = false
			cancel()
	if event is InputEventMouseMotion and _right_drop_active:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			return true
		_right_drop_active = false
	if _left_captured and event is InputEventMouse and _keeper.is_pointer_over_ui(event.position):
		cancel()
		return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	return false


func finish(_screen: Vector2) -> bool:
	var captured := _left_captured or _context.keeper.is_holding()
	cancel()
	return captured


func lift(actor_id: int) -> bool:
	is_acting = true
	var success := _context.keeper.pickup(actor_id)
	is_acting = false
	action_finished.emit({"success": success, "reason": "Creature picked up" if success else "That creature cannot be picked up"})
	return success


func inspect_actor(actor_id: int) -> bool:
	is_acting = true
	var success := _context.keeper.inspect(actor_id)
	is_acting = false
	action_finished.emit({"success": success, "reason": "Creature inspected" if success else "That creature is no longer available"})
	return success
