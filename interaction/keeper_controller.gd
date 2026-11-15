class_name KeeperController
extends Node3D
## Converts desktop input into camera movement and excavation marking.

signal preview_changed(changes: Dictionary)
signal construction_changed
signal room_action_finished(result: Dictionary)
signal keeper_action_finished(result: Dictionary)
signal drop_preview_changed(quote: Dictionary)

const INVALID_CELL := Vector2i(-1, -1)
const MIN_DISTANCE := 12.0
const MAX_DISTANCE := 65.0
const OverlayScript = preload("res://interaction/selection_overlay.gd")

var camera: Camera3D
var context: GameContext
var focus := Vector3(28.0, 0.0, 30.0)
var yaw := 0.30
var pitch := 0.90
var distance := 31.0
var ui_hit_test: Callable
var pointer_position := Vector2.ZERO
var build_room_id: StringName = &""
var removing_rooms := false
var _overlay: Node3D
var _creature_input: KeeperCreatureInput
var _hovered_actor_id := -1
var _drop_preview: Dictionary = {}
var _preview_changes: Dictionary = {"add": [], "remove": [], "blocked": []}
var _drag_start := INVALID_CELL
var _drag_end := INVALID_CELL
var _drag_mode: int = GameContext.MarkOperation.TOGGLE
var _hover_mode: int = GameContext.MarkOperation.TOGGLE


func setup(game_context: GameContext) -> void:
	if game_context == null or game_context.grid == null:
		return
	context = game_context
	_creature_input = KeeperCreatureInput.new(self, context)
	_creature_input.action_finished.connect(_on_keeper_action_finished)
	_overlay = OverlayScript.new()
	_overlay.grid = context.grid
	_overlay.exploration = context.exploration
	add_child(_overlay)
	camera = Camera3D.new()
	camera.name = "KeeperCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 53.0
	camera.near = 0.15
	camera.far = 180.0
	add_child(camera)
	camera.make_current()
	recenter()
	context.excavation_marks_changed.connect(_show_marks)
	context.grid.tile_changed.connect(_on_terrain_changed)
	context.rooms.changed.connect(_refresh_preview)
	context.economy.changed.connect(_refresh_preview)
	context.exploration.changed.connect(_on_exploration_changed)
	context.keeper.changed.connect(_on_keeper_changed)
	context.simulation_ticked.connect(_on_simulation_ticked)
	_show_marks(context.last_marked_cell)


func _process(delta: float) -> void:
	if context == null:
		return
	if DisplayServer.window_is_focused() and get_viewport().gui_get_focus_owner() == null:
		_process_keyboard(delta)
	_update_camera()
	_update_pointer_preview(get_viewport().get_mouse_position())


func _input(event: InputEvent) -> void:
	# GUI controls may consume release events. Cancel here before GUI handling so
	# dragging from the world onto a panel cannot leave a stale pending operation.
	if context == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and is_constructing():
		exit_construction()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse or event is InputEventKey:
		var previous_mode := _hover_mode
		_hover_mode = _modifier_mode(event)
		if _drag_start != INVALID_CELL:
			_drag_mode = _hover_mode
		if event is InputEventMouse:
			_update_pointer_preview(event.position)
		if previous_mode != _hover_mode:
			_refresh_preview()
	if _creature_input.observe(event):
		get_viewport().set_input_as_handled()
		return
	if _drag_start == INVALID_CELL:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if is_pointer_over_ui(event.position) or get_target_cell(event.position) == INVALID_CELL:
			_cancel_drag()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if context != null:
			context.hovered_cell = INVALID_CELL
		_cancel_drag()


func _unhandled_input(event: InputEvent) -> void:
	if context == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_HOME:
			recenter()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if is_constructing():
				exit_construction()
			elif context.keeper.is_holding():
				_cancel_drag()
			elif context.keeper.inspected_actor != null:
				_cancel_drag()
				context.keeper.clear_inspection()
			else:
				_cancel_drag()
				context.clear_excavation_marks()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			pickup_selected()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			inspect_hovered()
			get_viewport().set_input_as_handled()
	var pointer: Vector2 = event.position if event is InputEventMouse else get_viewport().get_mouse_position()
	if is_pointer_over_ui(pointer):
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not is_constructing() and _creature_input.begin(event.position):
					get_viewport().set_input_as_handled()
					return
				_begin_drag(event)
			elif _creature_input.finish(event.position):
				get_viewport().set_input_as_handled()
				return
			elif _drag_start != INVALID_CELL:
				_finish_drag(event.position)
			else:
				return
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * 0.90, MIN_DISTANCE, MAX_DISTANCE)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance / 0.90, MIN_DISTANCE, MAX_DISTANCE)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.006
			pitch = clampf(pitch + event.relative.y * 0.004, 0.30, 1.30)
			get_viewport().set_input_as_handled()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var right := Vector3(cos(yaw), 0.0, -sin(yaw))
			var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
			focus += (-right * event.relative.x + forward * event.relative.y) * distance * 0.0017
			_clamp_focus()
			get_viewport().set_input_as_handled()


func recenter() -> void:
	var heart_cells := context.grid.cells_of_type(DungeonGrid.Tile.HEART)
	var center_cell := Vector2i(context.grid.width / 2, context.grid.height / 2)
	focus = context.grid.cell_to_world(heart_cells[0] if not heart_cells.is_empty() else center_cell)
	yaw = 0.30
	pitch = 0.90
	distance = 31.0
	_update_camera()


func get_target_cell(screen: Vector2) -> Vector2i:
	if camera == null or context == null:
		return INVALID_CELL
	return KeeperCreatureTargeting.terrain_hit(context.grid, camera.project_ray_origin(screen), camera.project_ray_normal(screen), context.exploration).cell


func get_target_actor(screen: Vector2) -> CreatureState:
	if context == null or camera == null or is_pointer_over_ui(screen):
		return null
	return KeeperCreatureTargeting.actor_at(context, camera, screen)


func pickup_selected() -> bool:
	if context == null:
		return false
	var actor := context.keeper.inspected_actor
	if actor == null or actor.is_held:
		return false
	_cancel_drag()
	return _creature_input.lift(actor.id)


func inspect_hovered() -> bool:
	var actor: CreatureState = get_target_actor(pointer_position)
	if actor == null:
		return false
	_cancel_drag()
	return _creature_input.inspect_actor(actor.id)


func get_drop_preview() -> Dictionary:
	if context == null:
		return {"valid": false, "reason": "No dungeon is active", "cell": INVALID_CELL}
	var over_ui := is_pointer_over_ui(pointer_position)
	var cell := INVALID_CELL if over_ui else get_target_cell(pointer_position)
	var quote := context.keeper.quote_drop(cell)
	if over_ui and context.keeper.is_holding():
		quote.reason = "Move off the interface to drop"
	return quote



func is_pointer_over_ui(screen: Vector2 = Vector2.INF) -> bool:
	var point := get_viewport().get_mouse_position() if screen == Vector2.INF else screen
	if ui_hit_test.is_valid():
		return ui_hit_test.call(point)
	return get_viewport().gui_get_hovered_control() != null


func rectangle_cells(first: Vector2i, last: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not context.grid.is_inside(first) or not context.grid.is_inside(last):
		return result
	for y in range(mini(first.y, last.y), maxi(first.y, last.y) + 1):
		for x in range(mini(first.x, last.x), maxi(first.x, last.x) + 1):
			var cell := Vector2i(x, y)
			if context.can_designate_excavation(cell):
				result.append(cell)
	return result


func get_preview_changes() -> Dictionary:
	return _preview_changes.duplicate(true)


func is_constructing() -> bool:
	return build_room_id != &"" or removing_rooms


func set_build_room(definition_id: StringName) -> void:
	if _reject_construction_while_held():
		return
	if context.registry == null:
		return
	var definition := context.registry.get_room(definition_id)
	if definition == null or not definition.buildable:
		return
	build_room_id = definition_id
	removing_rooms = false
	_cancel_drag()
	construction_changed.emit()


func set_sell_rooms() -> void:
	if _reject_construction_while_held():
		return
	build_room_id = &""
	removing_rooms = true
	_cancel_drag()
	construction_changed.emit()


func set_remove_rooms() -> void:
	# Compatibility for existing verification probes; the player chooses Sell.
	set_sell_rooms()


func exit_construction() -> void:
	build_room_id = &""
	removing_rooms = false
	_cancel_drag()
	construction_changed.emit()


func _construction_cells(first: Vector2i, last: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not context.grid.is_inside(first) or not context.grid.is_inside(last):
		return cells
	for y in range(mini(first.y, last.y), maxi(first.y, last.y) + 1):
		for x in range(mini(first.x, last.x), maxi(first.x, last.x) + 1):
			cells.append(Vector2i(x, y))
	return cells


func _update_pointer_preview(screen: Vector2) -> void:
	pointer_position = screen
	var cell := INVALID_CELL if is_pointer_over_ui(screen) else get_target_cell(screen)
	var actor: CreatureState = get_target_actor(screen) if not is_constructing() and not context.keeper.is_holding() else null
	var actor_id := actor.id if actor != null else -1
	if cell == context.hovered_cell and actor_id == _hovered_actor_id and (_drag_start == INVALID_CELL or _drag_end == cell) and not context.keeper.is_holding():
		return
	context.hovered_cell = cell
	_hovered_actor_id = actor_id
	_drag_end = cell
	_refresh_preview()


func _refresh_preview() -> void:
	if context == null or _overlay == null:
		return
	if context.keeper.is_holding():
		_refresh_drop_preview()
		return
	var gold_hover := context.exploration.is_revealed(context.hovered_cell) and context.grid.get_tile(context.hovered_cell) == DungeonGrid.Tile.FLOOR and context.economy.gold_at(context.hovered_cell) > 0
	if not is_constructing() and ((_drag_start == INVALID_CELL and (_hovered_actor_id != -1 or gold_hover)) or (_creature_input != null and _creature_input.has_pending())):
		var empty: Array[Vector2i] = []
		_overlay.show_preview(empty, empty, empty)
		_preview_changes = {"add": [], "remove": [], "blocked": [], "actor_id": _hovered_actor_id}
		preview_changed.emit(get_preview_changes())
		return
	if is_constructing():
		_refresh_construction_preview()
		return
	var candidates: Array[Vector2i] = []
	var blocked: Array[Vector2i] = []
	if _drag_start != INVALID_CELL:
		candidates = rectangle_cells(_drag_start, _drag_end)
	elif context.grid.is_inside(context.hovered_cell):
		if context.can_designate_excavation(context.hovered_cell):
			candidates.append(context.hovered_cell)
		else:
			blocked.append(context.hovered_cell)
	var adding: Array[Vector2i] = []
	var removing: Array[Vector2i] = []
	var neutral: Array[Vector2i] = []
	neutral.append_array(blocked)
	var mode := _drag_mode if _drag_start != INVALID_CELL else _hover_mode
	for cell in candidates:
		var selected := context.excavation_marks.has(cell)
		if mode == GameContext.MarkOperation.REMOVE:
			if selected:
				removing.append(cell)
			else:
				neutral.append(cell)
		elif mode == GameContext.MarkOperation.ADD:
			if not selected:
				adding.append(cell)
			else:
				neutral.append(cell)
		elif selected:
			removing.append(cell)
		else:
			adding.append(cell)
	var changes := {"add": adding, "remove": removing, "blocked": blocked}
	_overlay.show_preview(adding, removing, neutral)
	if changes != _preview_changes:
		_preview_changes = changes
		preview_changed.emit(get_preview_changes())


func _refresh_construction_preview() -> void:
	var cells: Array[Vector2i] = []
	if _drag_start != INVALID_CELL:
		cells = _construction_cells(_drag_start, _drag_end)
	elif context.grid.is_inside(context.hovered_cell):
		cells.append(context.hovered_cell)
	var quote: Dictionary = context.rooms.quote_remove(cells) if removing_rooms else context.rooms.quote_build(build_room_id, cells)
	var adding: Array[Vector2i] = []
	var removing: Array[Vector2i] = []
	var blocked: Array[Vector2i] = []
	adding.assign(quote.get("add", []))
	removing.assign(quote.get("remove", []))
	blocked.assign(quote.get("blocked", []))
	if not quote.get("valid", false):
		blocked.append_array(adding)
		blocked.append_array(removing)
		adding.clear()
		removing.clear()
	_overlay.show_construction_preview(adding, removing, blocked)
	if quote != _preview_changes:
		_preview_changes = quote.duplicate(true)
		preview_changed.emit(get_preview_changes())


func _modifier_mode(event: InputEventWithModifiers) -> int:
	if event.ctrl_pressed:
		return GameContext.MarkOperation.REMOVE
	if event.shift_pressed:
		return GameContext.MarkOperation.ADD
	return GameContext.MarkOperation.TOGGLE


func _on_terrain_changed(_cell: Vector2i) -> void:
	# A worker may change the hovered block without moving the pointer.
	_update_pointer_preview(pointer_position)
	_refresh_preview()


func _on_exploration_changed() -> void:
	# A queued plan can become known rock without its membership changing.
	# Reconcile both its top/side shell and the stationary-pointer preview.
	_show_marks(context.last_marked_cell)
	_update_pointer_preview(pointer_position)


func _begin_drag(event: InputEventMouseButton) -> void:
	_drag_start = get_target_cell(event.position)
	_drag_end = _drag_start
	_drag_mode = _modifier_mode(event)
	_refresh_preview()


func _finish_drag(screen: Vector2) -> void:
	var last := get_target_cell(screen)
	if is_constructing():
		var result: Dictionary
		var room_cells := _construction_cells(_drag_start, last)
		if removing_rooms:
			result = context.rooms.remove(room_cells)
		else:
			result = context.rooms.build(build_room_id, room_cells)
		room_action_finished.emit(result)
		_cancel_drag()
		return
	var cells := rectangle_cells(_drag_start, last)
	if not cells.is_empty():
		context.mark_excavation(cells, _drag_mode)
	_cancel_drag()


func _cancel_drag() -> void:
	if _creature_input != null:
		_creature_input.cancel()
	_drag_start = INVALID_CELL
	_drag_end = INVALID_CELL
	_refresh_preview()


func _refresh_drop_preview() -> void:
	var quote := get_drop_preview()
	var valid: Array[Vector2i] = []
	var invalid: Array[Vector2i] = []
	var removing: Array[Vector2i] = []
	if context.grid.is_inside(quote.cell):
		if quote.valid:
			valid.append(quote.cell)
		else:
			invalid.append(quote.cell)
	_overlay.show_construction_preview(valid, removing, invalid)
	_preview_changes = {"add": [], "remove": [], "blocked": []}
	if quote != _drop_preview:
		_drop_preview = quote.duplicate(true)
		drop_preview_changed.emit(quote.duplicate(true))


func _reject_construction_while_held() -> bool:
	if context == null or not context.keeper.is_holding():
		return false
	construction_changed.emit()
	keeper_action_finished.emit({"success": false, "reason": "Empty your hand before building or selling"})
	return true


func _on_keeper_changed() -> void:
	_drag_start = INVALID_CELL
	_drag_end = INVALID_CELL
	if _creature_input != null and not _creature_input.is_acting:
		_creature_input.cancel()
	if context.keeper.is_holding() and is_constructing():
		build_room_id = &""
		removing_rooms = false
		construction_changed.emit()
	_update_pointer_preview(pointer_position)
	_refresh_preview()


func _on_keeper_action_finished(result: Dictionary) -> void:
	keeper_action_finished.emit(result)
	_refresh_preview()


func _on_simulation_ticked(_delta: float) -> void:
	# Creature motion and occupancy may change under a stationary pointer.
	_update_pointer_preview(pointer_position)


func _process_keyboard(delta: float) -> void:
	var horizontal := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var vertical := float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var backward := Vector3(sin(yaw), 0.0, cos(yaw))
	var move := (right * horizontal + backward * vertical).limit_length(1.0)
	focus += move * delta * distance * 0.55
	var orbit := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	yaw += orbit * delta * 1.25
	_clamp_focus()


func _clamp_focus() -> void:
	focus.x = clampf(focus.x, 0.0, (context.grid.width - 1) * DungeonGrid.TILE_SIZE)
	focus.z = clampf(focus.z, 0.0, (context.grid.height - 1) * DungeonGrid.TILE_SIZE)


func _update_camera() -> void:
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(focus)


func _show_marks(_cell: Vector2i) -> void:
	var cells: Array[Vector2i] = []
	for cell in context.excavation_marks:
		cells.append(cell)
	_overlay.show_marks(cells)
	_refresh_preview()
