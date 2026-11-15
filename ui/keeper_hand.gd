class_name KeeperHand
extends Control
## Original placeholder hand silhouette, drawn locally without texture dependencies.

var controller: KeeperController
var _phase := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100


func _process(delta: float) -> void:
	_phase += delta
	visible = controller != null and not controller.is_pointer_over_ui() and DisplayServer.window_is_focused() and controller.context.hovered_cell != KeeperController.INVALID_CELL
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if visible else Input.MOUSE_MODE_VISIBLE)
	position = get_viewport().get_mouse_position() + Vector2(0.0, sin(_phase * 2.5) * 1.1)
	queue_redraw()


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _draw() -> void:
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
