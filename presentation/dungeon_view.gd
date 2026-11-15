class_name DungeonView
extends Node3D
## Projects shared dungeon state into a replaceable procedural 3D presentation.
## Terrain is batched by material; simulation never depends on these meshes.

var _context: GameContext
var _terrain: Node3D
var _landmarks: Node3D
var _actor_root: Node3D
var _actor_views: Dictionary = {}
var _block_mesh: ArrayMesh
var _crystal_mesh: ArrayMesh
var _stone_materials: Array[StandardMaterial3D] = []
var _floor_materials: Array[StandardMaterial3D] = []
var _gold_material: StandardMaterial3D
var _gem_material: StandardMaterial3D
var _gold_root: Node3D
var _gold_snapshot: String = ""
var _gold_refresh: float = 0.0
var _terrain_dirty := false
var _landmark_dirty := false
var _heart_cell := Vector2i(-1, -1)
var _portal_cell := Vector2i(-1, -1)


func setup(context: GameContext) -> void:
	_context = context
	_block_mesh = DungeonGeometry.chamfered_block()
	_crystal_mesh = DungeonGeometry.octahedron()
	for color in ["34313b", "403b43", "48414a", "37363d", "4c4148"]:
		_stone_materials.append(DungeonGeometry.material(Color(color)))
	for color in ["62584f", "6b5d50", "5c5551", "756454", "655d57"]:
		_floor_materials.append(DungeonGeometry.material(Color(color)))
	_gold_material = DungeonGeometry.material(Color("d6a146"), Color("e1972c"), 0.2)
	_gold_material.metallic = 0.45
	_gold_material.roughness = 0.66
	_gem_material = DungeonGeometry.material(Color("62c4c0"), Color("298aa3"), 0.55)
	_gem_material.metallic = 0.25
	_gem_material.roughness = 0.4
	_terrain = Node3D.new()
	_terrain.name = "TerrainBatches"
	add_child(_terrain)
	_landmarks = Node3D.new()
	_landmarks.name = "Landmarks"
	add_child(_landmarks)
	_actor_root = Node3D.new()
	_actor_root.name = "Creatures"
	add_child(_actor_root)
	_gold_root = Node3D.new()
	_gold_root.name = "PhysicalGold"
	add_child(_gold_root)
	var rooms := DungeonRoomView.new()
	rooms.name = "Rooms"
	add_child(rooms)
	rooms.setup(_context)
	_build_lighting()
	_build_terrain()
	_build_landmarks()
	_build_props()
	_refresh_gold()
	for actor in _context.actors:
		_add_actor(actor)
	_context.actor_added.connect(_add_actor)
	_context.grid.tile_changed.connect(_on_tile_changed)


func _process(delta: float) -> void:
	if _context == null:
		return
	_gold_refresh -= delta
	if _gold_refresh <= 0.0:
		_gold_refresh = 0.2
		_refresh_gold()
	var living_ids: Dictionary = {}
	for actor in _context.actors:
		living_ids[actor.id] = true
		if not _actor_views.has(actor.id):
			_add_actor(actor)
		if not _actor_views.has(actor.id):
			continue
		var view: Node3D = _actor_views[actor.id]
		if view.has_method("sync"):
			view.call("sync", actor)
		else:
			view.position = actor.position
			view.rotation.y = actor.heading
	for actor_id in _actor_views.keys():
		if not living_ids.has(actor_id):
			_actor_views[actor_id].queue_free()
			_actor_views.erase(actor_id)


func _add_actor(actor: CreatureState) -> void:
	if _actor_views.has(actor.id):
		return
	var definition: CreatureDefinition = _context.registry.get_creature(actor.definition_id)
	if definition == null:
		push_warning("Cannot render unknown creature definition: %s" % actor.definition_id)
		return
	var view: Node3D
	if definition.view_scene != null:
		var candidate := definition.view_scene.instantiate()
		if candidate is Node3D:
			view = candidate
		else:
			candidate.free()
			push_warning("Creature view_scene must have a Node3D root; using placeholder.")
	if view == null:
		var placeholder := DungeonCreatureView.new()
		placeholder.build(definition.body_color)
		view = placeholder
	view.name = "Creature_%s" % actor.id
	view.scale = Vector3.ONE * definition.scale_factor
	view.position = actor.position
	_actor_root.add_child(view)
	_actor_views[actor.id] = view


func _build_lighting() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("100f18")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8e85a0")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("181420")
	environment.fog_density = 0.006
	world_environment.environment = environment
	add_child(world_environment)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -32, 0)
	moon.light_color = Color("b5aac7")
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 100.0
	add_child(moon)


func _build_terrain() -> void:
	for child in _terrain.get_children():
		child.free()
	var rock_transforms: Array = [[], [], [], [], []]
	var floor_transforms: Array = [[], [], [], [], []]
	var gold_transforms: Array[Transform3D] = []
	var gem_transforms: Array[Transform3D] = []
	var rubble_transforms: Array[Transform3D] = []
	var grid := _context.grid
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var tile := grid.get_tile(cell)
			var at := grid.cell_to_world(cell)
			var variation := posmod(x * 71 + y * 31, 5)
			if grid.can_excavate(cell):
				var height := grid.surface_height(cell) + 0.02
				rock_transforms[variation].append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.98, height, 1.98)), at + Vector3(0, height * 0.5 - 0.02, 0)))
				if _touches_floor(cell):
					var top_scale := Vector3(0.45 + variation * 0.07, 0.23, 0.4)
					rubble_transforms.append(Transform3D(Basis(Vector3.UP, float(variation) * 0.7).scaled(top_scale), at + Vector3(0.3, height + 0.08, -0.2)))
				if tile == DungeonGrid.Tile.GOLD:
					_crystals_at_cell(cell, gold_transforms, height)
				elif tile == DungeonGrid.Tile.GEM:
					_crystals_at_cell(cell, gem_transforms, height, 1.35)
			else:
				floor_transforms[variation].append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.96, 0.18, 1.96)), at + Vector3(0, grid.surface_height(cell) - 0.09, 0)))
				if tile == DungeonGrid.Tile.HEART:
					_heart_cell = cell
				elif tile == DungeonGrid.Tile.PORTAL:
					_portal_cell = cell
	for index in range(5):
		_add_batch("Rock_%s" % index, _block_mesh, _stone_materials[index], rock_transforms[index])
		_add_batch("Floor_%s" % index, _block_mesh, _floor_materials[index], floor_transforms[index])
	_add_batch("Rubble", _block_mesh, _stone_materials[2], rubble_transforms)
	_add_batch("GoldVeins", _crystal_mesh, _gold_material, gold_transforms)
	_add_batch("GemVeins", _crystal_mesh, _gem_material, gem_transforms)
	var slab_material := DungeonGeometry.material(Color("201e27"))
	DungeonGeometry.box(_terrain, Vector3(grid.width * 2.0, 0.8, grid.height * 2.0), Vector3((grid.width - 1), -0.59, (grid.height - 1)), slab_material)


func _touches_floor(cell: Vector2i) -> bool:
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Vector2i = cell + direction
		if _context.grid.is_inside(neighbor):
			if not _context.grid.can_excavate(neighbor):
				return true
	return false


func _crystals_at_cell(cell: Vector2i, transforms: Array[Transform3D], height: float, size_factor: float = 1.0) -> void:
	var center := _context.grid.cell_to_world(cell)
	var offsets := [Vector3(-0.63, height + 0.03, 0.25), Vector3(0.1, height + 0.14, -0.36), Vector3(0.58, height + 0.04, 0.2)]
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Vector2i = cell + direction
		if not _context.grid.is_inside(neighbor):
			continue
		if _context.grid.can_excavate(neighbor):
			continue
		for index in range(4):
			var tangent := Vector3(-direction.y, 0, direction.x)
			var offset := Vector3(direction.x, 0, direction.y) * 0.98 + tangent * (-0.6 + index * 0.4)
			offset.y = 0.48 + float(posmod(index + cell.x, 3)) * 0.34
			offsets.append(offset)
	for index in range(offsets.size()):
		var basis := Basis.from_euler(Vector3(0.2, float(index) * 1.5, 0.4)).scaled(Vector3(0.22, 0.34, 0.22) * size_factor)
		transforms.append(Transform3D(basis, center + offsets[index]))


func _add_batch(label: String, mesh: Mesh, surface: Material, transforms: Array) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var view := MultiMeshInstance3D.new()
	view.name = label
	view.multimesh = multimesh
	view.material_override = surface
	_terrain.add_child(view)


func _build_landmarks() -> void:
	for child in _landmarks.get_children():
		child.free()
	if _heart_cell.x >= 0:
		var heart := DungeonHeartView.new()
		heart.name = "DungeonHeart"
		heart.position = _context.grid.cell_to_world(_heart_cell)
		_landmarks.add_child(heart)
	if _portal_cell.x >= 0:
		var portal := DungeonPortalView.new()
		portal.name = "CreaturePortal"
		portal.position = _context.grid.cell_to_world(_portal_cell)
		_landmarks.add_child(portal)


func _build_props() -> void:
	for cell in [Vector2i(10, 12), Vector2i(18, 12), Vector2i(10, 19), Vector2i(18, 19), Vector2i(12, 5), Vector2i(16, 5), Vector2i(6, 15)]:
		if _context.grid.is_inside(cell):
			_torch(_context.grid.cell_to_world(cell))
	# Chamber floor motif is decoration, not a separate resource or mechanic.
	if _heart_cell.x >= 0:
		var brass := DungeonGeometry.material(Color("a17c40"))
		var center := _context.grid.cell_to_world(_heart_cell)
		var motif := DungeonGeometry.torus(self, 3.15, 3.21, center + Vector3(0, 0.025, 0), brass)
		motif.scale.y = 0.18


func _torch(at: Vector3) -> void:
	var prop := Node3D.new()
	prop.position = at
	add_child(prop)
	var iron := DungeonGeometry.material(Color("2b272a"))
	var fire := DungeonGeometry.material(Color("ffc26c"), Color("ff8f30"), 3.0)
	DungeonGeometry.cylinder(prop, 0.27, 0.16, Vector3(0, 0.08, 0), iron, 0.21)
	DungeonGeometry.cylinder(prop, 0.07, 1.55, Vector3(0, 0.8, 0), iron)
	DungeonGeometry.cylinder(prop, 0.12, 0.22, Vector3(0, 1.6, 0), iron, 0.24)
	DungeonGeometry.sphere(prop, Vector3(0, 1.9, 0), Vector3(0.3, 0.65, 0.3), fire, 6)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.15, 0)
	light.light_color = Color("ffb36a")
	light.light_energy = 2.1
	light.omni_range = 8.0
	prop.add_child(light)


func _on_tile_changed(cell: Vector2i) -> void:
	_landmark_dirty = _landmark_dirty or cell == _heart_cell or cell == _portal_cell
	if not _terrain_dirty:
		_terrain_dirty = true
		_apply_terrain_changes.call_deferred()


func _apply_terrain_changes() -> void:
	# Batch simultaneous worker completions. Preserve the Heart's pulse and props.
	_terrain_dirty = false
	_heart_cell = Vector2i(-1, -1)
	_portal_cell = Vector2i(-1, -1)
	_build_terrain()
	if _landmark_dirty:
		_build_landmarks()
		_landmark_dirty = false


func _refresh_gold() -> void:
	var economy := _context.economy
	var snapshot := str([economy.ground_gold, economy.stored_by_cell, economy.treasury_cells])
	if snapshot == _gold_snapshot:
		return
	_gold_snapshot = snapshot
	for child in _gold_root.get_children():
		child.free()
	for cell in economy.treasury_cells:
		if not _context.grid.is_walkable(cell):
			continue
		var amount: int = economy.stored_by_cell.get(cell, 0)
		if amount > 0:
			_storage_prop(cell, amount)
	for cell in economy.ground_gold:
		_coin_pile(_context.grid.cell_to_world(cell), economy.ground_gold[cell])


func _storage_prop(cell: Vector2i, amount: int) -> void:
	var root := Node3D.new()
	root.name = "GoldStorage_%d_%d" % [cell.x, cell.y]
	root.position = _context.grid.cell_to_world(cell) + Vector3.UP * 0.12
	root.set_meta("gold", amount)
	_gold_root.add_child(root)
	var definition := _context.registry.get_room(_context.rooms.tiles.get(cell, &""))
	var small_ratio := definition.storage_small_chest_ratio if definition != null else 0.35
	var large_ratio := definition.storage_large_chest_ratio if definition != null else 0.75
	var capacity := _context.economy.storage_capacity(cell)
	var fullness := float(amount) / float(capacity) if capacity > 0 else 0.0
	if fullness < small_ratio:
		root.set_meta("stage", &"pile")
		_coin_pile(root.position, amount, root)
	else:
		var large := fullness >= large_ratio
		root.set_meta("stage", &"large_chest" if large else &"small_chest")
		_build_chest(root, large)


func _build_chest(root: Node3D, large: bool) -> void:
	# Chunky worn boards and iron bands keep the two silhouettes readable in play.
	var wood := DungeonGeometry.material(Color("69452e"))
	var dark_wood := DungeonGeometry.material(Color("422d24"))
	var iron := DungeonGeometry.material(Color("302b30"))
	var brass := DungeonGeometry.material(Color("b58a47"))
	var size := 1.0 if large else 0.68
	root.scale = Vector3.ONE * size
	DungeonGeometry.box(root, Vector3(1.32, 0.48, 0.92), Vector3(0, 0.29, 0), wood)
	var lid := DungeonGeometry.cylinder(root, 0.46, 1.31, Vector3(0, 0.52, 0), dark_wood, -1.0, 8)
	lid.rotation.z = PI * 0.5
	lid.scale.z = 0.72
	for side in [-1, 1]:
		DungeonGeometry.box(root, Vector3(0.13, 0.55, 0.96), Vector3(side * 0.43, 0.30, 0), iron)
		var band := DungeonGeometry.cylinder(root, 0.48, 0.135, Vector3(side * 0.43, 0.52, 0), iron, -1.0, 8)
		band.rotation.z = PI * 0.5
		band.scale.z = 0.72
		for bolt_z in [-1, 1]:
			DungeonGeometry.sphere(root, Vector3(side * 0.43, 0.27, bolt_z * 0.49), Vector3.ONE * 0.10, brass, 6)
	for board in range(3):
		DungeonGeometry.box(root, Vector3(1.30, 0.018, 0.012), Vector3(0, 0.15 + board * 0.12, 0.47), dark_wood)
	DungeonGeometry.box(root, Vector3(0.20, 0.24, 0.06), Vector3(0, 0.43, 0.49), brass)
	DungeonGeometry.box(root, Vector3(0.045, 0.09, 0.02), Vector3(0, 0.44, 0.53), iron)
	# A few bright coins identify this as a gold store, rather than generic luggage.
	for coin in range(5 if large else 3):
		DungeonGeometry.cylinder(root, 0.13, 0.065, Vector3(-0.43 + coin * 0.20, 0.055, 0.64), _gold_material, -1.0, 8)


func _coin_pile(at: Vector3, amount: int, parent: Node3D = null) -> void:
	var destination := _gold_root if parent == null else parent
	var origin := at if parent == null else Vector3.ZERO
	for index in range(mini(15, maxi(1, ceili(amount / 15.0)))):
		var offset := Vector3(float(index % 3 - 1) * 0.21, 0.05 + floorf(index / 3.0) * 0.075, float(index % 2) * 0.18)
		DungeonGeometry.cylinder(destination, 0.15, 0.07, origin + offset, _gold_material, -1, 8)
