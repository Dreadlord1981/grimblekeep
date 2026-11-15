class_name DungeonCreatureView
extends Node3D
## Original procedural worker placeholder. State and movement belong to features.

var _body: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _cargo: Node3D
var _previous_position := Vector3.ZERO
var _has_previous_position := false
var _still_for := 1.0
var _animation_time := 0.0


func build(color: Color) -> void:
	var skin := DungeonGeometry.material(color)
	var shaded_skin := DungeonGeometry.material(color.darkened(0.24))
	var cloth := DungeonGeometry.material(Color("61513f"))
	var horn := DungeonGeometry.material(Color("ccbc91"))
	var eye := DungeonGeometry.material(Color("f8cc58"), Color("db8e26"), 0.25)
	var black := DungeonGeometry.material(Color("17121a"))
	var iron := DungeonGeometry.material(Color("767481"))
	var wood := DungeonGeometry.material(Color("55402f"))
	_body = Node3D.new()
	add_child(_body)
	DungeonGeometry.sphere(_body, Vector3(0, 0.81, 0), Vector3(0.6, 0.73, 0.45), skin)
	DungeonGeometry.sphere(_body, Vector3(0, 1.33, 0), Vector3(0.78, 0.65, 0.60), skin)
	DungeonGeometry.sphere(_body, Vector3(0, 1.17, 0.22), Vector3(0.48, 0.28, 0.29), shaded_skin)
	DungeonGeometry.sphere(_body, Vector3(0, 1.12, 0.35), Vector3(0.32, 0.12, 0.035), black, 8)
	DungeonGeometry.sphere(_body, Vector3(0, 1.3, 0.33), Vector3(0.14, 0.12, 0.15), shaded_skin, 8)
	for side in [-1.0, 1.0]:
		var ear := DungeonGeometry.cylinder(_body, 0.18, 0.47, Vector3(side * 0.45, 1.36, -0.02), skin, 0.01, 6)
		ear.rotation.z = side * -1.08
		var spike := DungeonGeometry.cylinder(_body, 0.12, 0.46, Vector3(side * 0.25, 1.73, -0.08), horn, 0.015, 6)
		spike.rotation.z = side * -0.3
		DungeonGeometry.sphere(_body, Vector3(side * 0.16, 1.41, 0.255), Vector3(0.23, 0.16, 0.12), eye, 8)
		DungeonGeometry.sphere(_body, Vector3(side * 0.14, 1.41, 0.31), Vector3(0.055, 0.11, 0.025), black, 6)
		var brow := DungeonGeometry.box(_body, Vector3(0.29, 0.07, 0.10), Vector3(side * 0.16, 1.5, 0.29), shaded_skin)
		brow.rotation.z = side * 0.17
		var tooth := DungeonGeometry.cylinder(_body, 0.035, 0.105, Vector3(side * 0.1, 1.12, 0.38), horn, 0.008, 5)
		tooth.rotation.z = PI
	DungeonGeometry.cylinder(_body, 0.32, 0.31, Vector3(0, 0.56, 0), cloth, 0.27, 8)
	_left_leg = _limb(_body, Vector3(-0.18, 0.48, 0), skin, Vector3(0.17, 0.42, 0.17))
	_right_leg = _limb(_body, Vector3(0.18, 0.48, 0), skin, Vector3(0.17, 0.42, 0.17))
	for leg in [_left_leg, _right_leg]:
		DungeonGeometry.sphere(leg, Vector3(0, -0.32, 0.08), Vector3(0.24, 0.17, 0.32), shaded_skin, 8)
	_left_arm = _limb(_body, Vector3(-0.38, 1.02, 0), skin, Vector3(0.17, 0.49, 0.18))
	_right_arm = _limb(_body, Vector3(0.38, 1.02, 0), skin, Vector3(0.17, 0.49, 0.18))
	DungeonGeometry.rod(_right_arm, Vector3(0.02, -0.32, -0.22), Vector3(0.02, -0.32, 0.65), 0.035, wood)
	var pick := DungeonGeometry.box(_right_arm, Vector3(0.49, 0.075, 0.11), Vector3(0.02, -0.32, 0.60), iron)
	pick.rotation.y = 0.14
	# A physical bag and visible coins explain hauling without floating rewards.
	_cargo = Node3D.new()
	_cargo.name = "CarriedGold"
	_cargo.position = Vector3(-0.29, 0.79, -0.30)
	_body.add_child(_cargo)
	var sack := DungeonGeometry.material(Color("745b36"))
	var gold := DungeonGeometry.material(Color("e9b54b"), Color("b77316"), 0.12)
	DungeonGeometry.sphere(_cargo, Vector3.ZERO, Vector3(0.48, 0.53, 0.38), sack, 8)
	DungeonGeometry.torus(_cargo, 0.10, 0.15, Vector3(0, 0.22, 0), cloth)
	for index in range(3):
		var coin := DungeonGeometry.cylinder(_cargo, 0.075, 0.035, Vector3(-0.07 + index * 0.065, 0.25 + float(index % 2) * 0.035, 0.025), gold, 0.075, 8)
		coin.rotation.z = -0.2 + float(index) * 0.2
	_cargo.visible = false
	# Crooked little tail, visible even when the worker faces away.
	DungeonGeometry.rod(_body, Vector3(0, 0.64, -0.18), Vector3(0.13, 0.66, -0.48), 0.06, skin)
	DungeonGeometry.rod(_body, Vector3(0.13, 0.66, -0.48), Vector3(0.25, 0.86, -0.53), 0.04, skin)


func _limb(parent: Node3D, at: Vector3, surface: Material, size: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	DungeonGeometry.sphere(pivot, Vector3(0, -size.y * 0.36, 0), size, surface, 8)
	return pivot


func sync(actor: CreatureState) -> void:
	# Render frames can outnumber physics ticks; retain the gait briefly between
	# position updates instead of snapping to an idle pose every other frame.
	if _has_previous_position and actor.position.distance_squared_to(_previous_position) > 0.000001:
		_still_for = 0.0
	else:
		_still_for += get_process_delta_time()
	position = actor.position
	rotation.y = actor.heading
	_previous_position = actor.position
	_has_previous_position = true
	_animation_time += get_process_delta_time()
	var working := actor.action in [&"digging", &"mining"]
	var stride := sin(actor.phase) * clampf(1.0 - _still_for / 0.15, 0.0, 1.0)
	if working:
		stride = 0.0
	_body.position.y = absf(stride) * 0.055
	_body.rotation.z = stride * 0.04
	_body.rotation.x = 0.0
	_body.scale.y = 1.0 + sin(_animation_time * 2.0) * 0.008
	_left_leg.rotation.x = stride * 0.4
	_right_leg.rotation.x = -stride * 0.4
	_left_arm.rotation.x = -stride * 0.22
	_right_arm.rotation.x = stride * 0.18
	_left_arm.rotation.z = 0.0
	_right_arm.rotation.z = 0.0
	_cargo.visible = actor.carried_gold > 0
	_cargo.rotation.z = stride * 0.06
	if working:
		var swing := sin(_animation_time * 7.0)
		_right_arm.rotation.x = -0.5 + swing * 0.9
		_right_arm.rotation.z = -0.10
		_left_arm.rotation.x = -0.55 + swing * 0.35
		_body.rotation.x = 0.10 + swing * 0.055
		_body.position.y = -maxf(swing, 0.0) * 0.035
	elif actor.action == &"depositing":
		_body.rotation.x = 0.18
		_left_arm.rotation.x = -0.7
	elif actor.carried_gold > 0:
		# Shoulder braces under the sack while the other arm carries the pick.
		_left_arm.rotation.z = -0.55
		_left_arm.rotation.x = -0.8
