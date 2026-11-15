class_name GameContext
extends RefCounted
## Explicit session dependencies and events shared by features and views.

signal actor_added(actor: CreatureState)
signal actor_removed(actor: CreatureState)
signal excavation_marks_changed(cell: Vector2i)
signal simulation_ticked(delta: float)

enum MarkOperation { REPLACE, ADD, REMOVE, TOGGLE }

var grid: DungeonGrid
var registry: ContentRegistry
var actors: Array[CreatureState] = []
var economy: GoldEconomy
var rooms: DungeonRooms
var beds: DungeonBeds
var food: FoodEconomy
var keeper: KeeperState
var exploration: DungeonExploration
var infrastructure: DungeonInfrastructure
var last_marked_cell := Vector2i(-1, -1)
var excavation_marks: Dictionary[Vector2i, bool] = {}
var hovered_cell := Vector2i(-1, -1)
var _next_actor_id: int = 1


func next_actor_id() -> int:
	return _next_actor_id


func restore_actor_sequence(next_id: int) -> void:
	# Detached save reconstruction only; validated by the persistence boundary.
	_next_actor_id = next_id


func _init(dungeon_grid: DungeonGrid = null, content_registry: ContentRegistry = null) -> void:
	grid = dungeon_grid
	registry = content_registry
	economy = GoldEconomy.new(grid)
	if grid != null:
		exploration = DungeonExploration.new(grid)
		rooms = DungeonRooms.new(grid, registry, economy, exploration)
		beds = DungeonBeds.new(grid, rooms, registry)
		food = FoodEconomy.new(grid, rooms, registry)
		keeper = KeeperState.new(self)
		infrastructure = DungeonInfrastructure.new(self)
		exploration.changed.connect(_prune_revealed_marks)
		grid.tile_changed.connect(_on_terrain_changed)


func spawn_creature(definition_id: StringName, cell: Vector2i) -> CreatureState:
	if registry == null or grid == null or registry.get_creature(definition_id) == null:
		return null
	if not grid.is_walkable(cell):
		return null
	var actor := CreatureState.new()
	actor.id = _next_actor_id
	_next_actor_id += 1
	actor.definition_id = definition_id
	actor.energy = registry.get_creature(definition_id).initial_energy
	actor.satiety = registry.get_creature(definition_id).initial_satiety
	actor.position = grid.cell_to_world(cell)
	actors.append(actor)
	actor_added.emit(actor)
	return actor


func despawn_creature(actor_id: int) -> bool:
	for actor in actors:
		if actor.id == actor_id:
			# Preserve physical cargo even when no worker feature is currently loaded.
			economy.retain_removed_actor(actor)
			actors.erase(actor)
			beds.release(actor_id)
			food.release(actor_id)
			actor_removed.emit(actor)
			return true
	return false


func mark_excavation(cells: Array[Vector2i], mode: int = MarkOperation.TOGGLE) -> void:
	if grid == null or mode < MarkOperation.REPLACE or mode > MarkOperation.TOGGLE:
		return
	if mode == MarkOperation.REPLACE:
		excavation_marks.clear()
	var visited: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		if not can_designate_excavation(cell) or visited.has(cell):
			continue
		visited[cell] = true
		if mode == MarkOperation.REMOVE or (mode == MarkOperation.TOGGLE and excavation_marks.has(cell)):
			excavation_marks.erase(cell)
		else:
			excavation_marks[cell] = true
	_emit_marks_changed()


func can_designate_excavation(cell: Vector2i) -> bool:
	# Unknown marks are plans, independent of the concealed terrain underneath.
	return grid != null and grid.is_inside(cell) and (not exploration.is_revealed(cell) or grid.can_excavate(cell))


func can_execute_excavation(cell: Vector2i) -> bool:
	return grid != null and exploration.is_revealed(cell) and grid.can_excavate(cell)


func is_actor_visible(actor: CreatureState) -> bool:
	return actor != null and actor in actors and (actor.is_held or exploration.is_revealed(grid.world_to_cell(actor.position)))


func clear_excavation_marks() -> void:
	excavation_marks.clear()
	_emit_marks_changed()


func _on_terrain_changed(cell: Vector2i) -> void:
	if excavation_marks.has(cell) and exploration.is_revealed(cell) and not grid.can_excavate(cell):
		excavation_marks.erase(cell)
		_emit_marks_changed()


func _prune_revealed_marks() -> void:
	var dirty := false
	for cell in excavation_marks.keys():
		if exploration.is_revealed(cell) and not grid.can_excavate(cell):
			excavation_marks.erase(cell)
			dirty = true
	if dirty:
		_emit_marks_changed()


func _emit_marks_changed() -> void:
	last_marked_cell = Vector2i(-1, -1) if excavation_marks.is_empty() else excavation_marks.keys().back()
	excavation_marks_changed.emit(last_marked_cell)
