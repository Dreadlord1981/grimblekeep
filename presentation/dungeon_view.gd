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
var _bedrock_mesh: BoxMesh
var _bedrock_material: StandardMaterial3D
var _bedrock_band_material: StandardMaterial3D
var _bedrock_crown_material: StandardMaterial3D
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
var _portal_views: Dictionary[Vector2i, DungeonPortalView] = {}
var _unknown_material: StandardMaterial3D


func setup(context: GameContext) -> void:
	_context = context
	_block_mesh = DungeonGeometry.chamfered_block()
	_crystal_mesh = DungeonGeometry.octahedron()
	_bedrock_mesh = BoxMesh.new()
	_bedrock_mesh.size = Vector3.ONE
	_bedrock_material = DungeonGeometry.material(Color("242d39"), Color("242d39"), 0.16)
	_bedrock_band_material = DungeonGeometry.material(Color("45515b"), Color("45515b"), 0.16)
	_bedrock_crown_material = DungeonGeometry.material(Color("303d49"), Color("303d49"), 0.16)
	_unknown_material = DungeonGeometry.material(Color("050609"))
	_unknown_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for color in ["34313b", "403b43", "48414a", "37363d", "4c4148"]:
		# A faint remembered-rock base makes the revealed planning band legible.
		# It illuminates no neighboring cells; lamps still light floors and actors.
		_stone_materials.append(DungeonGeometry.material(Color(color), Color(color), 0.16))
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
	var food := DungeonFoodView.new()
	food.name = "PhysicalFood"
	add_child(food)
	food.setup(_context)
	_build_lighting()
	_build_terrain()
	_build_landmarks()
	_build_props()
	var infrastructure := DungeonInfrastructureView.new()
	infrastructure.name = "InfrastructureLights"
	add_child(infrastructure)
	infrastructure.setup(context)
	_refresh_gold()
	for actor in _context.actors:
		_add_actor(actor)
	_context.actor_added.connect(_add_actor)
	_context.keeper.actor_control_changed.connect(_on_actor_control_changed)
	_context.grid.tile_changed.connect(_on_tile_changed)
	_context.exploration.changed.connect(_on_exploration_changed)
	_context.infrastructure.changed.connect(_sync_portals)


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
		view.visible = _actor_visible(actor)
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
	view.visible = _actor_visible(actor)
	_actor_root.add_child(view)
	if view.has_method("setup_context"):
		view.call("setup_context", _context)
	_actor_views[actor.id] = view


func _on_actor_control_changed(actor: CreatureState) -> void:
	var view: Node3D = _actor_views.get(actor.id)
	if view != null:
		view.visible = _actor_visible(actor)
		view.position = actor.position


func _build_lighting() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("030407")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("647087")
	environment.ambient_light_energy = 0.055
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("050609")
	environment.fog_density = 0.003
	world_environment.environment = environment
	add_child(world_environment)


func _build_terrain() -> void:
	for child in _terrain.get_children():
		child.free()
	var rock_transforms: Array = [[], [], [], [], []]
	var floor_transforms: Array = [[], [], [], [], []]
	var gold_transforms: Array[Transform3D] = []
	var gem_transforms: Array[Transform3D] = []
	var rubble_transforms: Array[Transform3D] = []
	var bedrock_transforms: Array[Transform3D] = []
	var bedrock_bands: Array[Transform3D] = []
	var bedrock_crowns: Array[Transform3D] = []
	var unexplored: Array[Transform3D] = []
	var grid := _context.grid
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var tile := grid.get_tile(cell)
			var at := grid.cell_to_world(cell)
			if tile == DungeonGrid.Tile.HEART:
				_heart_cell = cell
			elif tile == DungeonGrid.Tile.PORTAL:
				_portal_cell = cell
			if not _context.exploration.is_revealed(cell):
				# Every unknown cell has identical opaque geometry, regardless of
				# hidden terrain, resources, chambers or other contents underneath.
				unexplored.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.0, DungeonExploration.FOG_HEIGHT, 2.0)), at + Vector3(0, DungeonExploration.FOG_HEIGHT * 0.5, 0)))
				continue
			var variation := posmod(x * 71 + y * 31, 5)
			if grid.is_solid(cell):
				var height := grid.surface_height(cell) + 0.02
				if tile == DungeonGrid.Tile.BEDROCK:
					var body_height := height - 0.025
					bedrock_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.98, body_height, 1.98)), at + Vector3(0, body_height * 0.5 - 0.02, 0)))
					for band in [0.60, 1.25, 1.85]:
						bedrock_bands.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.995, 0.045, 1.995)), at + Vector3(0, band, 0)))
					bedrock_crowns.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.98, 0.025, 1.98)), at + Vector3(0, grid.surface_height(cell) - 0.0125, 0)))
					continue
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
	_add_batch("BedrockCore", _bedrock_mesh, _bedrock_material, bedrock_transforms)
	_add_batch("BedrockStrata", _bedrock_mesh, _bedrock_band_material, bedrock_bands)
	_add_batch("BedrockCrowns", _bedrock_mesh, _bedrock_crown_material, bedrock_crowns)
	_add_batch("UnexploredFog", _bedrock_mesh, _unknown_material, unexplored)
	var slab_material := DungeonGeometry.material(Color("201e27"))
	DungeonGeometry.box(_terrain, Vector3(grid.width * 2.0, 0.8, grid.height * 2.0), Vector3((grid.width - 1), -0.59, (grid.height - 1)), slab_material)


func _touches_floor(cell: Vector2i) -> bool:
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Vector2i = cell + direction
		if _context.grid.is_walkable(neighbor):
			return true
	return false


func _crystals_at_cell(cell: Vector2i, transforms: Array[Transform3D], height: float, size_factor: float = 1.0) -> void:
	var center := _context.grid.cell_to_world(cell)
	var offsets := [Vector3(-0.63, height + 0.03, 0.25), Vector3(0.1, height + 0.14, -0.36), Vector3(0.58, height + 0.04, 0.2)]
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Vector2i = cell + direction
		if not _context.grid.is_walkable(neighbor):
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
	if _context.exploration.enabled and label != "UnexploredFog":
		# Compatibility lights are selected per mesh. Spatial batches stop distant
		# fixtures from displacing the lights of a local patch of terrain.
		var chunks: Dictionary[Vector2i, Array] = {}
		for transform: Transform3D in transforms:
			var key := Vector2i(floori(transform.origin.x / 8.0), floori(transform.origin.z / 8.0))
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append(transform)
		for key in chunks:
			_add_spatial_batch("%s_%d_%d" % [label, key.x, key.y], mesh, surface, chunks[key])
		return
	_add_spatial_batch(label, mesh, surface, transforms)


func _add_spatial_batch(label: String, mesh: Mesh, surface: Material, transforms: Array) -> void:
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
	_portal_views.clear()
	for child in _landmarks.get_children():
		child.free()
	if _heart_cell.x >= 0:
		var heart := DungeonHeartView.new()
		heart.name = "DungeonHeart"
		heart.position = _context.grid.cell_to_world(_heart_cell)
		_landmarks.add_child(heart)
		heart.visible = _context.exploration.is_revealed(_heart_cell)
	for cell in _context.grid.cells_of_type(DungeonGrid.Tile.PORTAL):
		var portal := DungeonPortalView.new()
		portal.name = "CreaturePortal_%d_%d" % [cell.x, cell.y]
		portal.position = _context.grid.cell_to_world(cell)
		portal.setup_state(_context.infrastructure.is_portal_claimed(cell), _context.exploration.is_revealed(cell))
		_landmarks.add_child(portal)
		_portal_views[cell] = portal


func _build_props() -> void:
	# Chamber floor motif is decoration, not a separate resource or mechanic.
	if _heart_cell.x >= 0:
		var brass := DungeonGeometry.material(Color("a17c40"))
		var center := _context.grid.cell_to_world(_heart_cell)
		var motif := DungeonGeometry.torus(self, 3.15, 3.21, center + Vector3(0, 0.025, 0), brass)
		motif.scale.y = 0.18


func _actor_visible(actor: CreatureState) -> bool:
	return not actor.is_held and _context.exploration.is_revealed(_context.grid.world_to_cell(actor.position))


func _sync_portals() -> void:
	for cell in _portal_views:
		_portal_views[cell].setup_state(_context.infrastructure.is_portal_claimed(cell), _context.exploration.is_revealed(cell))


func _on_exploration_changed() -> void:
	_sync_portals()
	_on_tile_changed(Vector2i(-1, -1))
	_gold_snapshot = ""
	_refresh_gold()


func _on_tile_changed(cell: Vector2i) -> void:
	_landmark_dirty = _landmark_dirty or cell == _heart_cell or _portal_views.has(cell) or _context.grid.get_tile(cell) in [DungeonGrid.Tile.HEART, DungeonGrid.Tile.PORTAL]
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
	var snapshot := str([economy.ground_gold, economy.stored_by_cell, economy.treasury_cells, economy.protected_storage, _context.exploration.revealed])
	if snapshot == _gold_snapshot:
		return
	_gold_snapshot = snapshot
	for child in _gold_root.get_children():
		child.free()
	for cell in economy.treasury_cells:
		if not _context.grid.is_walkable(cell) or not _context.exploration.is_revealed(cell):
			continue
		if economy.protected_storage.has(cell):
			_heart_storage_floor(cell)
		var amount: int = economy.stored_by_cell.get(cell, 0)
		if amount > 0:
			_storage_prop(cell, amount)
	for cell in economy.ground_gold:
		if _context.exploration.is_revealed(cell):
			_coin_pile(_context.grid.cell_to_world(cell), economy.ground_gold[cell])


func _storage_prop(cell: Vector2i, amount: int) -> void:
	var root := Node3D.new()
	root.name = "GoldStorage_%d_%d" % [cell.x, cell.y]
	root.position = _context.grid.cell_to_world(cell) + Vector3.UP * 0.12
	root.set_meta("gold", amount)
	_gold_root.add_child(root)
	if _context.economy.protected_storage.has(cell):
		root.set_meta("stage", &"heart_pile")
		_coin_pile(root.position, amount, root)
		return
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


func _heart_storage_floor(cell: Vector2i) -> void:
	# Worn iron edging reserves this floor without hiding the chamber's stone
	# or surrounding the Heart with tall Treasury chests.
	var root := Node3D.new()
	root.name = "HeartStorageFloor_%d_%d" % [cell.x, cell.y]
	root.position = _context.grid.cell_to_world(cell)
	root.set_meta("capacity", _context.economy.storage_capacity(cell))
	_gold_root.add_child(root)
	var iron := DungeonGeometry.material(Color("393638"))
	var worn_brass := DungeonGeometry.material(Color("8a7143"))
	for side in [-1, 1]:
		DungeonGeometry.box(root, Vector3(1.86, 0.035, 0.065), Vector3(0, 0.035, side * 0.91), iron)
		DungeonGeometry.box(root, Vector3(0.065, 0.035, 1.86), Vector3(side * 0.91, 0.035, 0), iron)
		for corner in [-1, 1]:
			DungeonGeometry.cylinder(root, 0.055, 0.022, Vector3(side * 0.87, 0.06, corner * 0.87), worn_brass, -1, 6)
	DungeonGeometry.cylinder(root, 0.23, 0.014, Vector3(0, 0.015, 0), worn_brass, -1, 10)
	DungeonGeometry.box(root, Vector3(0.075, 0.01, 0.29), Vector3(0, 0.025, 0), iron)
	DungeonGeometry.box(root, Vector3(0.25, 0.01, 0.05), Vector3(0, 0.025, 0), iron)


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
