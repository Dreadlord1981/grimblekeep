extends GameFeature
## Rest/exploration and capacity-gated arrivals are replaceable feature content.

const ARRIVAL_POLL_SECONDS := 2.0
var behaviors: Dictionary[int, ResidentBehavior] = {}
var _arrival_in := 0.0


func persistence_id() -> StringName:
	return &"foundation.residents"


func capture_state() -> Dictionary:
	return {"arrival_in": _arrival_in}


func restore_state(data: Dictionary) -> String:
	var remaining: Variant = data.get("arrival_in")
	if not (remaining is float or remaining is int) or not is_finite(float(remaining)) or float(remaining) < 0.0 or float(remaining) > ARRIVAL_POLL_SECONDS:
		return "Invalid resident arrival clock"
	_arrival_in = float(remaining)
	return ""


func setup(game_context: GameContext) -> void:
	if context != null and context.keeper.actor_control_changed.is_connected(_on_actor_control_changed):
		context.keeper.actor_control_changed.disconnect(_on_actor_control_changed)
	for behavior in behaviors.values():
		behavior.cancel()
	behaviors.clear()
	super.setup(game_context)
	context.keeper.actor_control_changed.connect(_on_actor_control_changed)
	_arrival_in = 0.0


func tick(delta: float) -> void:
	if context == null or context.beds == null or not is_finite(delta) or delta <= 0.0:
		return
	context.beds.prune(context.actors)
	context.food.prune(context.actors)
	var residents: Dictionary[int, bool] = {}
	for actor in context.actors:
		var definition := context.registry.get_creature(actor.definition_id)
		if definition == null or not (&"rest" in definition.capabilities or &"eat" in definition.capabilities):
			continue
		residents[actor.id] = true
		if actor.is_held:
			continue
		if not behaviors.has(actor.id):
			behaviors[actor.id] = ResidentBehavior.new(context, actor)
		behaviors[actor.id].tick(delta, definition)
	for actor_id in behaviors.keys():
		if not residents.has(actor_id):
			behaviors[actor_id].cancel()
			context.beds.release(actor_id)
			behaviors.erase(actor_id)
	_arrival_in -= delta
	if _arrival_in <= 0.0:
		_arrival_in = ARRIVAL_POLL_SECONDS
		_try_arrival()


func _try_arrival() -> void:
	for definition in context.registry.get_creatures():
		if definition.portal_population_limit <= 0 or &"rest" not in definition.capabilities:
			continue
		var population := 0
		for actor in context.actors:
			if actor.definition_id == definition.id:
				population += 1
		if population >= definition.portal_population_limit:
			continue
		for portal in context.grid.cells_of_type(DungeonGrid.Tile.PORTAL):
			if not context.infrastructure.is_portal_claimed(portal):
				continue
			if context.beds.find_space(definition, portal) == Vector2i(-1, -1):
				continue
			var actor := context.spawn_creature(definition.id, portal)
			if actor == null:
				continue
			if context.beds.reserve(actor, definition) == null:
				context.despawn_creature(actor.id)
				continue
			actor.action = &"idle"
			actor.job_label = "Arrived through the portal"
			return


func _exit_tree() -> void:
	for behavior in behaviors.values():
		behavior.cancel()


func _on_actor_control_changed(actor: CreatureState) -> void:
	if behaviors.has(actor.id):
		behaviors[actor.id].cancel()
		behaviors.erase(actor.id)
	context.food.release(actor.id)
	var bed := context.beds.get_bed(actor.id)
	if actor.is_held and bed != null and not bed.established:
		context.beds.release(actor.id)
