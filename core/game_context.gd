class_name GameContext
extends RefCounted
## Explicit session dependencies and events shared by features and views.

signal actor_added(actor: CreatureState)
signal excavation_marks_changed(cell: Vector2i)
signal simulation_ticked(delta: float)

enum MarkOperation { REPLACE, ADD, REMOVE, TOGGLE }

var grid: DungeonGrid
var registry: ContentRegistry
var actors: Array[CreatureState] = []
var economy: GoldEconomy
var last_marked_cell := Vector2i(-1, -1)
var excavation_marks: Dictionary[Vector2i, bool] = {}
var hovered_cell := Vector2i(-1, -1)
var _next_actor_id: int = 1


func _init(dungeon_grid: DungeonGrid = null, content_registry: ContentRegistry = null) -> void:
	grid = dungeon_grid
	registry = content_registry
	economy = GoldEconomy.new(grid)
	if grid != null:
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
	actor.position = grid.cell_to_world(cell)
	actors.append(actor)
	actor_added.emit(actor)
	return actor


func mark_excavation(cells: Array[Vector2i], mode: int = MarkOperation.TOGGLE) -> void:
	if grid == null or mode < MarkOperation.REPLACE or mode > MarkOperation.TOGGLE:
		return
	if mode == MarkOperation.REPLACE:
		excavation_marks.clear()
	var visited: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		if not grid.can_excavate(cell) or visited.has(cell):
			continue
		visited[cell] = true
		if mode == MarkOperation.REMOVE or (mode == MarkOperation.TOGGLE and excavation_marks.has(cell)):
			excavation_marks.erase(cell)
		else:
			excavation_marks[cell] = true
	_emit_marks_changed()


func clear_excavation_marks() -> void:
	excavation_marks.clear()
	_emit_marks_changed()


func _on_terrain_changed(cell: Vector2i) -> void:
	if excavation_marks.has(cell) and not grid.can_excavate(cell):
		excavation_marks.erase(cell)
		_emit_marks_changed()


func _emit_marks_changed() -> void:
	last_marked_cell = Vector2i(-1, -1) if excavation_marks.is_empty() else excavation_marks.keys().back()
	excavation_marks_changed.emit(last_marked_cell)
