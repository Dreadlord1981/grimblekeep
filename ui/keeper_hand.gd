class_name KeeperHand
extends Control
## Original placeholder hand silhouette, drawn locally without texture dependencies.

var controller: KeeperController
var _phase := 0.0
var _held_preview: HeldCreaturePreview


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_held_preview = HeldCreaturePreview.new()
	_held_preview.context = controller.context
	_held_preview.z_index = -1
	add_child(_held_preview)


func _process(delta: float) -> void:
	_phase += delta
	var holding: bool = controller != null and controller.context.keeper.is_holding()
	visible = controller != null and DisplayServer.window_is_focused() and (holding or (not controller.is_pointer_over_ui(controller.pointer_position) and controller.context.hovered_cell != KeeperController.INVALID_CELL))
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if visible else Input.MOUSE_MODE_VISIBLE)
	position = (controller.pointer_position if controller != null else get_viewport().get_mouse_position()) + Vector2(0.0, sin(_phase * 2.5) * 1.1)
	var area := get_viewport().get_visible_rect().size
	var origin := position + Vector2(-45, -118)
	# At the top edge, keep the studio below and beside the hand instead of
	# clamping its name/model underneath the gripping silhouette.
	if position.y < 185:
		origin = position + Vector2(65, 50)
	origin.x = clampf(origin.x, 40, maxf(40, area.x - 184))
	origin.y = clampf(origin.y, 95, maxf(95, area.y - 152))
	_held_preview.position = origin - position
	queue_redraw()


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _draw() -> void:
	if controller != null and controller.context.keeper.is_holding():
		_draw_gripping()
		return
	var pointing := controller != null and controller.context.hovered_cell != KeeperController.INVALID_CELL
	var bend := 1.5 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0.0
	var tip := Vector2(1, 2 + bend) if pointing else Vector2(5, 10 + bend)
	var outline := PackedVector2Array([
		tip, Vector2(7, 1), Vector2(11, 6), Vector2(13, 18),
		Vector2(17, 14), Vector2(22, 15), Vector2(25, 20),
		Vector2(30, 19), Vector2(34, 23), Vector2(38, 25),
		Vector2(39, 36), Vector2(34, 44), Vector2(32, 54),
		Vector2(14, 53), Vector2(13, 44), Vector2(7, 39),
		Vector2(1, 28), Vector2(2, 24), Vector2(7, 25),
		Vector2(12, 30), Vector2(9, 18), Vector2(6, 9)
	])
	var shadow := outline.duplicate()
	for index in range(shadow.size()):
		shadow[index] += Vector2(3, 3)
	draw_colored_polygon(shadow, Color(0.03, 0.02, 0.02, 0.8))
	draw_colored_polygon(outline, Color(0.65, 0.57, 0.42))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, Color(0.17, 0.13, 0.10), 2.0, true)
	draw_line(Vector2(13, 19), Vector2(17, 32), Color(0.37, 0.29, 0.22), 1.4)
	draw_line(Vector2(23, 20), Vector2(25, 31), Color(0.37, 0.29, 0.22), 1.4)
	draw_line(Vector2(31, 25), Vector2(32, 33), Color(0.37, 0.29, 0.22), 1.4)
	draw_line(Vector2(14, 44), Vector2(34, 44), Color(0.30, 0.20, 0.17), 5.0)
	draw_line(tip + Vector2(2, 3), tip + Vector2(5, 8), Color(0.89, 0.81, 0.61), 2.2)


func _draw_gripping() -> void:
	var valid: bool = controller.get_drop_preview().get("valid", false)
	var accent := Color(0.60, 0.78, 0.48) if valid else Color(0.91, 0.35, 0.26)
	draw_circle(Vector2(22, 16), 29, Color(0.04, 0.035, 0.03, 0.85))
	draw_arc(Vector2(22, 16), 28, 0, TAU, 32, accent, 2.0, true)
	var palm := PackedVector2Array([Vector2(-5, 27), Vector2(0, 17), Vector2(7, 15), Vector2(13, 27), Vector2(18, 23), Vector2(25, 25), Vector2(29, 22), Vector2(37, 25), Vector2(43, 22), Vector2(48, 28), Vector2(44, 39), Vector2(34, 47), Vector2(33, 58), Vector2(12, 58), Vector2(10, 46), Vector2(0, 39)])
	draw_colored_polygon(palm, Color(0.65, 0.57, 0.42))
	var border := palm.duplicate()
	border.append(palm[0])
	draw_polyline(border, Color(0.17, 0.13, 0.10), 2.0, true)
	for finger in range(3):
		draw_line(Vector2(18 + finger * 10, 27), Vector2(19 + finger * 9, 35), Color(0.35, 0.28, 0.20), 1.5)
	draw_line(Vector2(13, 48), Vector2(34, 48), Color(0.30, 0.20, 0.17), 5.0)
