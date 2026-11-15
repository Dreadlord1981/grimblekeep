class_name ResidentFeeding
extends RefCounted
## Appetite, exclusive meals and local timed consumption, independent of rest.

const RETRY_SECONDS := 0.5
var _context: GameContext
var _actor: CreatureState
var _navigation: ResidentNavigation
var _reservation: FoodReservation
var _hungry: bool:
	get:
		return _actor.hunger_intent
	set(value):
		_actor.hunger_intent = value
var _engaged := false
var _retry_in := 0.0
var _progress := 0.0
var active: bool:
	get:
		return _engaged
var unmet_food: bool:
	get:
		return _hungry and not _engaged


func _init(context: GameContext, actor: CreatureState) -> void:
	_context = context
	_actor = actor
	_navigation = ResidentNavigation.new(context.grid, actor)
	_reservation = context.food.get_reservation(actor.id)
	_engaged = _reservation != null
	_hungry = _hungry or _engaged or actor.food_requested


func update_need(delta: float, definition: CreatureDefinition) -> void:
	if _actor.is_held:
		return
	_retry_in -= delta
	if &"eat" not in definition.capabilities:
		cancel()
		_hungry = false
		return
	_actor.satiety = maxf(0.0, _actor.satiety - delta * definition.hunger_drain_per_second)
	if _actor.satiety <= definition.hunger_threshold:
		_hungry = true
	elif _actor.satiety >= definition.sated_threshold:
		_hungry = false


func is_critical(definition: CreatureDefinition) -> bool:
	return _hungry and _actor.satiety <= definition.hunger_threshold * 0.5


func try_begin() -> bool:
	if _actor.is_held:
		return false
	if _engaged:
		return true
	if not _hungry or _retry_in > 0.0:
		return false
	return _reserve_meal()


func tick(delta: float, definition: CreatureDefinition) -> void:
	if _actor.is_held:
		return
	if _reservation == null and not _reserve_meal():
		return
	if not _context.food.is_valid(_reservation):
		cancel()
		return
	_actor.food_requested = true
	var center := _context.grid.cell_to_world(_reservation.cell)
	_actor.target_cell = _reservation.cell
	if _actor.position.distance_to(center) > FoodEconomy.EAT_DISTANCE:
		_progress = 0.0
		_actor.work_progress = 0.0
		if _navigation.path.is_empty() and not _navigation.set_route(_reservation.cell, center):
			cancel()
			return
		_actor.job_label = "Going to a reserved meal"
		var travel := _navigation.follow(delta, definition.move_speed)
		if travel == ResidentNavigation.Travel.BLOCKED:
			cancel()
		elif travel == ResidentNavigation.Travel.ARRIVED:
			_navigation.clear()
		return
	if not _context.food.meal_ready(_reservation):
		# The eater owns the service position while the exact reserved animal
		# returns there. Waiting never consumes stock or preserves partial bites.
		_progress = 0.0
		_actor.work_progress = 0.0
		_actor.action = &"waiting_for_meal"
		_actor.job_label = "Waiting for the reserved meal"
		_navigation.clear()
		return
	_actor.action = &"eating"
	_actor.job_label = "Eating a reserved meal"
	_actor.phase += delta * 4.0
	_progress = minf(1.0, _progress + delta / definition.eating_seconds)
	_actor.work_progress = _progress
	if _progress < 1.0:
		return
	var gain := _context.food.consume(_actor)
	if gain <= 0.0:
		cancel()
		return
	_actor.satiety = minf(1.0, _actor.satiety + gain)
	_context.food.release(_actor.id)
	_reservation = null
	_progress = 0.0
	_navigation.clear()
	_actor.work_progress = 0.0
	_actor.action = &"idle"
	_actor.job_label = "Finished a meal"
	_hungry = _actor.satiety < definition.sated_threshold
	if not _hungry:
		_engaged = false
		_actor.food_requested = false


func cancel() -> void:
	_context.food.release(_actor.id)
	_reservation = null
	_engaged = false
	_retry_in = RETRY_SECONDS
	_progress = 0.0
	_navigation.clear()
	if _actor.food_requested:
		_actor.food_requested = false
		_actor.work_progress = 0.0
		_actor.target_cell = Vector2i(-1, -1)
		_actor.action = &"idle"
		_actor.job_label = "No reachable compatible food"


func _reserve_meal() -> bool:
	_retry_in = RETRY_SECONDS
	_reservation = _context.food.reserve_meal(_actor)
	if _reservation == null:
		cancel()
		return false
	_engaged = true
	_actor.food_requested = true
	_progress = 0.0
	_navigation.clear()
	return true
