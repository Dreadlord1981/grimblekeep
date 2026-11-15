extends GameFeature
## Module lifecycle composes job discovery and individual worker execution.

var job_board: WorkerJobBoard
var behaviors: Dictionary[int, WorkerBehavior] = {}
var orphaned_cargo: Array[WorkerBehavior] = []
var _recovery_in := 0.0


func setup(game_context: GameContext) -> void:
	for behavior in behaviors.values():
		behavior.cancel()
	behaviors.clear()
	orphaned_cargo.clear()
	super.setup(game_context)
	job_board = WorkerJobBoard.new(context)
	# Pending cargo is authoritative session state, so unloading/reloading this
	# feature cannot strand gold waiting for a walkable recovery tile.
	for pending_actor in context.economy.pending_cargo.values():
		orphaned_cargo.append(WorkerBehavior.new(context, job_board, pending_actor))


func tick(delta: float) -> void:
	if context == null or job_board == null or not is_finite(delta) or delta <= 0.0:
		return
	var live_ids: Dictionary[int, bool] = {}
	for actor in context.actors:
		live_ids[actor.id] = true
	# Release removed workers before offering their jobs to remaining workers.
	for actor_id in behaviors.keys():
		if not live_ids.has(actor_id):
			var removed: WorkerBehavior = behaviors[actor_id]
			if not removed.recover_removed_actor():
				context.economy.retain_removed_actor(removed.actor)
				orphaned_cargo.append(removed)
			else:
				context.economy.release_removed_actor(actor_id)
			behaviors.erase(actor_id)
	for actor in context.actors:
		var definition := context.registry.get_creature(actor.definition_id)
		if definition == null or not (&"excavate" in definition.capabilities or &"haul" in definition.capabilities):
			if behaviors.has(actor.id):
				behaviors[actor.id].cancel()
				# Keep tracking cargo if a capability change coincides with every
				# floor becoming blocked; later actor removal must still recover it.
				if _recovery_in <= 0.0 and behaviors[actor.id].drop_cargo():
					behaviors.erase(actor.id)
			continue
		if actor.rest_requested:
			# Resident needs run first. Releasing a work reservation must not
			# overwrite the current rest action or destroy retained physical cargo.
			if behaviors.has(actor.id) and behaviors[actor.id].job != null:
				var action := actor.action
				var label := actor.job_label
				var target := actor.target_cell
				var progress := actor.work_progress
				behaviors[actor.id].cancel()
				actor.action = action
				actor.job_label = label
				actor.target_cell = target
				actor.work_progress = progress
			continue
		if not behaviors.has(actor.id):
			behaviors[actor.id] = WorkerBehavior.new(context, job_board, actor)
		behaviors[actor.id].tick(delta, definition)
	_recovery_in -= delta
	if _recovery_in <= 0.0:
		_recovery_in = WorkerBehavior.POLL_SECONDS
		for index in range(orphaned_cargo.size() - 1, -1, -1):
			var pending := orphaned_cargo[index]
			if pending.actor in context.actors or pending.drop_cargo():
				context.economy.release_removed_actor(pending.actor.id)
				orphaned_cargo.remove_at(index)


func _exit_tree() -> void:
	# Unloading behavior must not erase cargo that still belongs to a live actor.
	for behavior in behaviors.values():
		behavior.cancel()
