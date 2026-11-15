class_name CavePigView
extends Node3D
## Physical food has cosmetic rooting motion, never resident AI or navigation.

var _skin: StandardMaterial3D
var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _time := 0.0
var _seed := 0.0
var _previous_position := Vector3.ZERO
var _has_previous := false
var _still_for := 1.0


func _ready() -> void:
	_build()


func configure_food(definition: FoodDefinition, unit_index: int, cell: Vector2i) -> void:
	_seed = float(posmod(cell.x * 17 + cell.y * 29 + unit_index * 41, 101)) * 0.23
	_time = _seed
	if _skin != null:
		_skin.albedo_color = definition.body_color
	set_meta("unit_index", unit_index)
	set_meta("food_id", definition.id)
	_process(0.0)


func sync_food(food: FoodUnitState) -> void:
	if _has_previous and food.position.distance_squared_to(_previous_position) > 0.000001:
		_still_for = 0.0
	else:
		_still_for += get_process_delta_time()
	_previous_position = food.position
	_has_previous = true


func _build() -> void:
	_skin = DungeonGeometry.material(Color("a67b70"))
	var mud := DungeonGeometry.material(Color("615044"))
	var hoof := DungeonGeometry.material(Color("342d2c"))
	var inner_ear := DungeonGeometry.material(Color("a97269"))
	var ivory := DungeonGeometry.material(Color("d6c7a1"))
	var eye := DungeonGeometry.material(Color("211c1b"))
	_body = Node3D.new()
	_body.name = "PigBody"
	add_child(_body)
	DungeonGeometry.sphere(_body, Vector3(0, 0.36, -0.04), Vector3(0.47, 0.43, 0.73), _skin, 8)
	DungeonGeometry.sphere(_body, Vector3(-0.13, 0.44, -0.14), Vector3(0.22, 0.22, 0.29), mud, 6)
	_head = Node3D.new()
	_head.name = "RootingHead"
	_head.position = Vector3(0, 0.35, 0.29)
	_body.add_child(_head)
	DungeonGeometry.sphere(_head, Vector3.ZERO, Vector3(0.39, 0.36, 0.36), _skin, 8)
	var snout := DungeonGeometry.cylinder(_head, 0.13, 0.15, Vector3(0, -0.07, 0.20), inner_ear, -1.0, 8)
	snout.rotation.x = PI * 0.5
	for side in [-1, 1]:
		DungeonGeometry.sphere(_head, Vector3(side * 0.047, -0.05, 0.275), Vector3(0.039, 0.035, 0.018), hoof, 6)
		DungeonGeometry.sphere(_head, Vector3(side * 0.145, 0.065, 0.115), Vector3(0.055, 0.050, 0.035), eye, 6)
		var ear := DungeonGeometry.cylinder(_head, 0.095, 0.23, Vector3(side * 0.14, 0.20, -0.015), _skin, 0.009, 5)
		ear.rotation.z = side * -0.65
		var tusk := DungeonGeometry.cylinder(_head, 0.025, 0.10, Vector3(side * 0.13, -0.09, 0.17), ivory, 0.003, 5)
		tusk.rotation.z = side * -0.35
	for side in [-1, 1]:
		for end in [-1, 1]:
			var leg := Node3D.new()
			leg.position = Vector3(side * 0.15, 0.20, end * 0.22 - 0.02)
			_body.add_child(leg)
			DungeonGeometry.cylinder(leg, 0.055, 0.17, Vector3(0, -0.065, 0), _skin, -1.0, 6)
			DungeonGeometry.box(leg, Vector3(0.10, 0.055, 0.12), Vector3(0, -0.15, 0.025), hoof)
			_legs.append(leg)
	for tuft in range(4):
		DungeonGeometry.cylinder(_body, 0.038, 0.085, Vector3(0, 0.59, -0.24 + tuft * 0.11), mud, 0.003, 5)
	DungeonGeometry.rod(_body, Vector3(0, 0.39, -0.38), Vector3(0.07, 0.49, -0.45), 0.023, _skin)
	DungeonGeometry.rod(_body, Vector3(0.07, 0.49, -0.45), Vector3(0.10, 0.45, -0.43), 0.019, _skin)


func _process(delta: float) -> void:
	if _body == null:
		return
	_time += delta
	# Authoritative unit positions drive traversal; only body motion is cosmetic.
	var moving := _still_for < 0.15
	var rooting := not moving and sin(_time * 1.3 + _seed) > -0.15
	_head.rotation.x = 0.24 + sin(_time * 4.5) * 0.10 if rooting else -0.08
	_body.position.y = sin(_time * 2.5) * 0.007
	for index in _legs.size():
		_legs[index].rotation.x = sin(_time * (8.0 if moving else 3.0) + float(index % 2) * PI) * (0.22 if moving else 0.06)
	set_meta("rooting", rooting)
