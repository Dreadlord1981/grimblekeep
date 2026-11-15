extends GameFeature
## Foundation ambient wandering. Later job/needs modules replace this feature.

const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var _targets: Dictionary[int, Vector3] = {}
var _random := RandomNumberGenerator.new()


func setup(game_context: GameContext) -> void:
	if context != null and context.keeper != null and context.keeper.actor_control_changed.is_connected(_on_control_changed):
		context.keeper.actor_control_changed.disconnect(_on_control_changed)
	super.setup(game_context)
	if context.keeper != null:
		context.keeper.actor_control_changed.connect(_on_control_changed)
	_targets.clear()
	_random.seed = 41821


func tick(delta: float) -> void:
	for actor in context.actors:
		if actor.is_held:
			_targets.erase(actor.id)
			continue
		var definition := context.registry.get_creature(actor.definition_id)
		if definition == null:
			continue
		if not _targets.has(actor.id):
			_choose_target(actor)
		var target: Vector3 = _targets.get(actor.id, actor.position)
		var direction := target - actor.position
		if direction.length() < 0.02:
			actor.position = target
			_targets.erase(actor.id)
			continue
		actor.heading = atan2(direction.x, direction.z)
		actor.position = actor.position.move_toward(target, definition.move_speed * delta)
		actor.phase += delta * 7.0


func _choose_target(actor: CreatureState) -> void:
	var cell := context.grid.world_to_cell(actor.position)
	var offset := _random.randi_range(0, 3)
	for i in 4:
		var next: Vector2i = cell + DIRECTIONS[(offset + i) % 4]
		if context.grid.is_walkable(next):
			_targets[actor.id] = context.grid.cell_to_world(next)
			return


func _on_control_changed(actor: CreatureState) -> void:
	_targets.erase(actor.id)
