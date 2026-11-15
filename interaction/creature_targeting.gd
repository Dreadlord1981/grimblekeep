class_name KeeperCreatureTargeting
extends RefCounted
## Ray targeting reads terrain, actor pose and definition bounds, never view nodes.

const INVALID_CELL := Vector2i(-1, -1)


static func terrain_hit(grid: DungeonGrid, origin: Vector3, direction: Vector3) -> Dictionary:
	var result := {"cell": INVALID_CELL, "distance_squared": INF}
	if grid == null:
		return result
	var half := DungeonGrid.TILE_SIZE * 0.5
	for y in grid.height:
		for x in grid.width:
			var cell := Vector2i(x, y)
			var center := grid.cell_to_world(cell)
			var top := grid.surface_height(cell)
			var bounds := AABB(center + Vector3(-half, -0.1, -half), Vector3(DungeonGrid.TILE_SIZE, top + 0.1, DungeonGrid.TILE_SIZE))
			var intersection: Variant = bounds.intersects_ray(origin, direction)
			if intersection == null:
				continue
			var hit: Vector3 = intersection
			var distance := origin.distance_squared_to(hit)
			if distance < result.distance_squared:
				result.cell = cell
				result.distance_squared = distance
	return result


static func actor_at(context: GameContext, camera: Camera3D, screen: Vector2) -> CreatureState:
	if context == null or context.registry == null or camera == null:
		return null
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest: float = terrain_hit(context.grid, origin, direction).distance_squared
	var target: CreatureState
	for actor in context.actors:
		if actor.is_held or not actor.position.is_finite():
			continue
		var definition := context.registry.get_creature(actor.definition_id)
		if definition == null:
			continue
		var sleeping := actor.action == &"sleeping"
		var size: Vector3 = (definition.keeper_sleep_pick_size if sleeping else definition.keeper_pick_size) * definition.scale_factor
		var base := actor.position
		var bed := context.beds.get_bed(actor.id)
		if bed != null:
			base.y += bed.lift_at(context.grid, actor.position)
		# Current sleeping pose lies along world Z; awake actors follow heading.
		var transform := Transform3D(Basis(Vector3.UP, 0.0 if sleeping else actor.heading), base)
		var inverse := transform.affine_inverse()
		var bounds := AABB(Vector3(-size.x * 0.5, 0, -size.z * 0.5), size)
		var intersection: Variant = bounds.intersects_ray(inverse * origin, inverse.basis * direction)
		if intersection == null:
			continue
		var local_hit: Vector3 = intersection
		var distance := origin.distance_squared_to(transform * local_hit)
		if distance <= nearest + 0.0001:
			nearest = distance
			target = actor
	return target
