class_name GrubbinView
extends Node3D
## Original low-poly Grubbin: body shape and animation read creature state only.

var _body: Node3D
var _head: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _eyes: Array[MeshInstance3D] = []
var _eye_heights: Array[float] = []
var _time := 0.0
var _previous := Vector3.ZERO
var _has_previous := false
var _still_for := 1.0
var _context: GameContext


func _ready() -> void:
	_build()


func setup_context(context: GameContext) -> void:
	_context = context


func _build() -> void:
	if _body != null:
		return
	var skin := DungeonGeometry.material(Color("77794a"))
	var shade := DungeonGeometry.material(Color("555b38"))
	var belly := DungeonGeometry.material(Color("99945d"))
	var inner_ear := DungeonGeometry.material(Color("8e7053"))
	var cloth := DungeonGeometry.material(Color("564034"))
	var patch := DungeonGeometry.material(Color("887158"))
	var bone := DungeonGeometry.material(Color("c6ba8f"))
	var black := DungeonGeometry.material(Color("242020"))
	var eye := DungeonGeometry.material(Color("d9a64e"), Color("9d681b"), 0.1)
	_body = Node3D.new()
	_body.name = "GrubbinBody"
	add_child(_body)
	DungeonGeometry.sphere(_body, Vector3(0, 0.86, -0.06), Vector3(1.06, 0.93, 0.72), skin, 10)
	DungeonGeometry.sphere(_body, Vector3(0, 0.77, 0.22), Vector3(0.99, 0.83, 0.67), belly, 10)
	DungeonGeometry.sphere(_body, Vector3(0.05, 0.69, 0.55), Vector3(0.075, 0.045, 0.025), shade, 6)
	for side in [-1.0, 1.0]:
		DungeonGeometry.sphere(_body, Vector3(side * 0.47, 1.10, -0.04), Vector3(0.43, 0.43, 0.50), skin, 8)
	_head = Node3D.new()
	_head.position = Vector3(0, 1.36, 0.06)
	_body.add_child(_head)
	DungeonGeometry.sphere(_head, Vector3.ZERO, Vector3(1.10, 0.79, 0.78), skin, 10)
	DungeonGeometry.sphere(_head, Vector3(0, -0.19, 0.28), Vector3(0.82, 0.38, 0.43), belly, 8)
	DungeonGeometry.sphere(_head, Vector3(0, -0.02, 0.40), Vector3(0.27, 0.18, 0.20), inner_ear, 8)
	DungeonGeometry.box(_head, Vector3(0.62, 0.035, 0.07), Vector3(0, -0.20, 0.47), black)
	for side in [-1.0, 1.0]:
		_ear(_head, side, skin, inner_ear)
		var eyeball := DungeonGeometry.sphere(_head, Vector3(side * 0.235, 0.065, 0.354), Vector3(0.26, 0.12, 0.13), eye, 8)
		_eyes.append(eyeball)
		_eye_heights.append(eyeball.scale.y)
		var pupil := DungeonGeometry.sphere(_head, Vector3(side * 0.22, 0.065, 0.419), Vector3(0.065, 0.105, 0.025), black, 6)
		_eyes.append(pupil)
		_eye_heights.append(pupil.scale.y)
		var brow := DungeonGeometry.box(_head, Vector3(0.38, 0.12, 0.18), Vector3(side * 0.23, 0.17, 0.36), shade)
		brow.rotation.z = side * 0.12
		var tusk := DungeonGeometry.cylinder(_head, 0.065, 0.24 if side < 0 else 0.31, Vector3(side * 0.31, -0.12, 0.47), bone, 0.008, 6)
		tusk.rotation.z = side * -0.22
		DungeonGeometry.sphere(_head, Vector3(side * 0.42, -0.06, 0.28), Vector3(0.12, 0.10, 0.035), inner_ear, 6)
	DungeonGeometry.cylinder(_body, 0.48, 0.34, Vector3(0, 0.44, 0.03), cloth, 0.43, 10)
	DungeonGeometry.cylinder(_body, 0.47, 0.11, Vector3(0, 0.58, 0.03), black, 0.46, 10)
	DungeonGeometry.box(_body, Vector3(0.21, 0.15, 0.08), Vector3(0.10, 0.57, 0.48), patch)
	var wrap_patch := DungeonGeometry.box(_body, Vector3(0.25, 0.23, 0.025), Vector3(-0.19, 0.41, 0.48), patch)
	wrap_patch.rotation.z = 0.12
	for stitch in range(4):
		DungeonGeometry.box(_body, Vector3(0.035, 0.065, 0.035), Vector3(-0.31 + stitch * 0.075, 0.50, 0.50), bone)
	for strip in range(6):
		var angle := float(strip) * TAU / 6.0
		var hem := DungeonGeometry.box(_body, Vector3(0.16, 0.14 + float(strip % 2) * 0.08, 0.05), Vector3(sin(angle) * 0.43, 0.23, cos(angle) * 0.43 + 0.03), cloth)
		hem.rotation.y = angle
	_left_leg = _limb(Vector3(-0.28, 0.39, 0.04), Vector3(0.32, 0.37, 0.34), skin)
	_right_leg = _limb(Vector3(0.28, 0.39, 0.04), Vector3(0.32, 0.37, 0.34), skin)
	for leg in [_left_leg, _right_leg]:
		DungeonGeometry.sphere(leg, Vector3(0, -0.28, 0.13), Vector3(0.42, 0.23, 0.57), shade, 8)
		for toe in range(3):
			DungeonGeometry.box(leg, Vector3(0.085, 0.045, 0.09), Vector3(-0.12 + toe * 0.12, -0.28, 0.37), bone)
	_left_arm = _limb(Vector3(-0.58, 1.08, 0.02), Vector3(0.30, 0.62, 0.32), skin)
	_right_arm = _limb(Vector3(0.58, 1.08, 0.02), Vector3(0.30, 0.62, 0.32), skin)
	for arm in [_left_arm, _right_arm]:
		DungeonGeometry.sphere(arm, Vector3(0, -0.49, 0.03), Vector3(0.32, 0.29, 0.32), shade, 8)
	_body.scale = Vector3.ONE * 0.90


func _limb(at: Vector3, size: Vector3, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	_body.add_child(pivot)
	DungeonGeometry.sphere(pivot, Vector3(0, -size.y * 0.36, 0), size, material, 8)
	return pivot


func _ear(parent: Node3D, side: float, skin: Material, inner: Material) -> void:
	var ear := Node3D.new()
	ear.position = Vector3(side * 0.43, 0.05, -0.02)
	parent.add_child(ear)
	# Flattened low-poly pointed ears stay broad in overview, unlike round horns.
	var outer := DungeonGeometry.sphere(ear, Vector3(side * 0.28, 0, 0), Vector3(0.83, 0.40, 0.20), skin, 6)
	outer.rotation.z = side * 0.24
	var inset := DungeonGeometry.sphere(ear, Vector3(side * 0.29, -0.015, 0.075), Vector3(0.64, 0.27, 0.055), inner, 6)
	inset.rotation.z = side * 0.24


func sync(actor: CreatureState) -> void:
	if _body == null:
		_build()
	var delta := get_process_delta_time()
	_time += delta
	if _has_previous and actor.position.distance_squared_to(_previous) > 0.000001:
		_still_for = 0.0
	else:
		_still_for += delta
	_previous = actor.position
	_has_previous = true
	position = actor.position
	rotation.y = actor.heading
	var sleeping := actor.action == &"sleeping"
	var claiming := actor.action == &"claiming_bed"
	set_meta("pose", &"sleeping" if sleeping else (&"claiming_bed" if claiming else (&"walking" if _still_for < 0.15 else &"idle")))
	var stride := sin(actor.phase) * clampf(1.0 - _still_for / 0.15, 0.0, 1.0)
	_body.position = Vector3(0, _bed_lift(actor) + absf(stride) * 0.035, 0)
	_body.rotation = Vector3(0.035, 0, stride * 0.055)
	_body.scale = Vector3(0.90, 0.90 + sin(_time * 1.7) * 0.007, 0.90)
	_head.rotation.z = sin(_time * 0.8) * 0.025
	_left_leg.rotation.x = stride * 0.32
	_right_leg.rotation.x = -stride * 0.32
	_left_arm.rotation = Vector3(-stride * 0.18, 0, -0.05)
	_right_arm.rotation = Vector3(stride * 0.18, 0, 0.05)
	for index in _eyes.size():
		_eyes[index].scale.y = _eye_heights[index] * (0.10 if sleeping else 1.0)
	if sleeping:
		rotation.y = 0.0
		_body.position = Vector3(0, 0.47 + sin(_time * 1.4) * 0.012, 0.54)
		_body.rotation = Vector3(-PI * 0.5, 0, 0.08)
		_left_arm.rotation.x = -0.9
		_right_arm.rotation.x = -0.9
		_left_leg.rotation.x = -0.35
		_right_leg.rotation.x = -0.25
	elif claiming:
		_body.position.y = -0.015
		_body.rotation.x = 0.32
		_left_leg.rotation.x = 0.65
		_right_leg.rotation.x = 0.65
		_right_arm.rotation.x = -0.40 + sin(_time * 8.0) * 0.16
		_left_arm.rotation.x = -0.25


func _bed_lift(actor: CreatureState) -> float:
	if _context == null or _context.beds == null:
		return 0.0
	var bed := _context.beds.get_bed(actor.id)
	if bed == null or not bed.established:
		return 0.0
	var offset := actor.position - bed.center(_context.grid)
	var x_fraction := absf(offset.x) / (float(bed.size.x) * DungeonGrid.TILE_SIZE * 0.5)
	var z_fraction := absf(offset.z) / (float(bed.size.y) * DungeonGrid.TILE_SIZE * 0.5)
	# Feet rest on the mattress until its edge, then lower by actual distance.
	# Selling the reservation removes the lift immediately, even when stationary.
	return 0.48 * clampf((1.0 - maxf(x_fraction, z_fraction)) / 0.25, 0.0, 1.0)
