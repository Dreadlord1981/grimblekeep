extends GameFeature
## Module lifecycle composes job discovery and individual worker execution.

var job_board: WorkerJobBoard
var behaviors: Dictionary[int, WorkerBehavior] = {}
var orphaned_cargo: Array[WorkerBehavior] = []
var _recovery_in := 0.0


func setup(game_context: GameContext) -> void:
	if context != null and context.keeper.actor_control_changed.is_connected(_on_actor_control_changed):
		context.keeper.actor_control_changed.disconnect(_on_actor_control_changed)
	for behavior in behaviors.values():
		behavior.cancel()
	behaviors.clear()
	orphaned_cargo.clear()
	super.setup(game_context)
	context.keeper.actor_control_changed.connect(_on_actor_control_changed)
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
		if actor.is_held:
			continue
		var definition := context.registry.get_creature(actor.definition_id)
		if not job_board.supports_worker(definition):
			if behaviors.has(actor.id):
				behaviors[actor.id].cancel()
				# Keep tracking cargo if a capability change coincides with every
				# floor becoming blocked; later actor removal must still recover it.
				if _recovery_in <= 0.0 and behaviors[actor.id].drop_cargo():
					behaviors.erase(actor.id)
			continue
		if actor.needs_requested:
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
		# Held actors have no active worker behavior. Despawning one can leave
		# cargo in the context ledger, including after this feature was reloaded.
		var tracked: Dictionary[int, bool] = {}
		for pending in orphaned_cargo:
			tracked[pending.actor.id] = true
		for pending_actor in context.economy.pending_cargo.values():
			if pending_actor not in context.actors and not tracked.has(pending_actor.id):
				orphaned_cargo.append(WorkerBehavior.new(context, job_board, pending_actor))
		for index in range(orphaned_cargo.size() - 1, -1, -1):
			var pending := orphaned_cargo[index]
			if pending.actor in context.actors or pending.drop_cargo():
				context.economy.release_removed_actor(pending.actor.id)
				orphaned_cargo.remove_at(index)


func _exit_tree() -> void:
	# Unloading behavior must not erase cargo that still belongs to a live actor.
	for behavior in behaviors.values():
		behavior.cancel()


func _on_actor_control_changed(actor: CreatureState) -> void:
	# Pickup and drop invalidate old routes synchronously. A dropped worker gets
	# a fresh behavior from its actual new position; carried gold stays on it.
	if behaviors.has(actor.id):
		behaviors[actor.id].suspend()
		behaviors.erase(actor.id)
	if job_board != null:
		job_board.release(actor.id)
