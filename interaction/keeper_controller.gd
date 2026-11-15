class_name KeeperController
extends Node3D
## Converts desktop input into camera movement and excavation marking.

signal preview_changed(changes: Dictionary)

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
var _overlay: Node3D
var _preview_changes: Dictionary = {"add": [], "remove": [], "blocked": []}
var _drag_start := INVALID_CELL
var _drag_end := INVALID_CELL
var _drag_mode: int = GameContext.MarkOperation.TOGGLE
var _hover_mode: int = GameContext.MarkOperation.TOGGLE


func setup(game_context: GameContext) -> void:
	context = game_context
	_overlay = OverlayScript.new()
	_overlay.grid = context.grid
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
	if event is InputEventMouse or event is InputEventKey:
		var previous_mode := _hover_mode
		_hover_mode = _modifier_mode(event)
		if _drag_start != INVALID_CELL:
			_drag_mode = _hover_mode
		if event is InputEventMouse:
			_update_pointer_preview(event.position)
		if previous_mode != _hover_mode:
			_refresh_preview()
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
			_cancel_drag()
			context.clear_excavation_marks()
			get_viewport().set_input_as_handled()
	var pointer: Vector2 = event.position if event is InputEventMouse else get_viewport().get_mouse_position()
	if is_pointer_over_ui(pointer):
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event)
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
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest_distance := INF
	var target := INVALID_CELL
	# Terrain bounds come from the grid contract, not physics nodes or view paths.
	# A nearest hit respects raised rock instead of selecting the floor behind it.
	var half_tile := DungeonGrid.TILE_SIZE * 0.5
	for y in context.grid.height:
		for x in context.grid.width:
			var cell := Vector2i(x, y)
			var center := context.grid.cell_to_world(cell)
			var top := context.grid.surface_height(cell)
			var bounds := AABB(center + Vector3(-half_tile, -0.1, -half_tile), Vector3(DungeonGrid.TILE_SIZE, top + 0.1, DungeonGrid.TILE_SIZE))
			var intersection: Variant = bounds.intersects_ray(origin, direction)
			if intersection == null:
				continue
			var hit: Vector3 = intersection
			var distance_to_hit := origin.distance_squared_to(hit)
			if distance_to_hit < nearest_distance:
				nearest_distance = distance_to_hit
				target = cell
	return target


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
			if context.grid.can_excavate(cell):
				result.append(cell)
	return result


func get_preview_changes() -> Dictionary:
	return _preview_changes.duplicate(true)


func _update_pointer_preview(screen: Vector2) -> void:
	var cell := INVALID_CELL if is_pointer_over_ui(screen) else get_target_cell(screen)
	if cell == context.hovered_cell and (_drag_start == INVALID_CELL or _drag_end == cell):
		return
	context.hovered_cell = cell
	_drag_end = cell
	_refresh_preview()


func _refresh_preview() -> void:
	if context == null:
		return
	var candidates: Array[Vector2i] = []
	var blocked: Array[Vector2i] = []
	if _drag_start != INVALID_CELL:
		candidates = rectangle_cells(_drag_start, _drag_end)
	elif context.grid.is_inside(context.hovered_cell):
		if context.grid.can_excavate(context.hovered_cell):
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


func _modifier_mode(event: InputEventWithModifiers) -> int:
	if event.ctrl_pressed:
		return GameContext.MarkOperation.REMOVE
	if event.shift_pressed:
		return GameContext.MarkOperation.ADD
	return GameContext.MarkOperation.TOGGLE


func _on_terrain_changed(_cell: Vector2i) -> void:
	# A worker may change the hovered block without moving the pointer.
	_refresh_preview()


func _begin_drag(event: InputEventMouseButton) -> void:
	_drag_start = get_target_cell(event.position)
	_drag_end = _drag_start
	_drag_mode = _modifier_mode(event)
	_refresh_preview()


func _finish_drag(screen: Vector2) -> void:
	var last := get_target_cell(screen)
	var cells := rectangle_cells(_drag_start, last)
	if not cells.is_empty():
		context.mark_excavation(cells, _drag_mode)
	_cancel_drag()


func _cancel_drag() -> void:
	_drag_start = INVALID_CELL
	_drag_end = INVALID_CELL
	_refresh_preview()


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
