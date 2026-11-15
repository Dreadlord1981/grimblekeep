class_name DungeonPortalView
extends Node3D
## Separate creature entrance landmark; no arrival logic lives in this view.

var _runes: Node3D
var _surface: MeshInstance3D
var _elapsed := 0.0
var _structure: Node3D
var _beacon: Node3D
var _light: OmniLight3D
var _rune_material: StandardMaterial3D
var _surface_material: StandardMaterial3D
var _claimed := true
var _discovered := true
var _label: Label3D


func setup_state(claimed: bool, discovered: bool) -> void:
	if _claimed == claimed and _discovered == discovered and _structure != null:
		return
	_claimed = claimed
	_discovered = discovered
	if _structure != null:
		_apply_state()


func _ready() -> void:
	_structure = Node3D.new()
	_structure.name = "DiscoveredStructure"
	add_child(_structure)
	var stone := DungeonGeometry.material(Color("3c364c"))
	var dark_stone := DungeonGeometry.material(Color("252333"))
	var rune := DungeonGeometry.material(Color("d3a4ff"), Color("b358ff"), 2.4)
	var surface := DungeonGeometry.material(Color("35145e"), Color("7b2bce"), 1.0)
	_rune_material = rune
	_surface_material = surface
	var iron := DungeonGeometry.material(Color("44384a"))
	DungeonGeometry.cylinder(_structure, 2.3, 0.22, Vector3(0, 0.11, 0), dark_stone, -1, 12)
	for index in range(13):
		var angle := float(index) / 12.0 * PI
		var at := Vector3(cos(angle) * 1.82, 1.55 + sin(angle) * 1.82, 0)
		var block := DungeonGeometry.box(_structure, Vector3(0.64, 0.7, 0.65), at, stone)
		block.rotation.z = angle - PI * 0.5
	for side in [-1.0, 1.0]:
		DungeonGeometry.box(_structure, Vector3(0.65, 1.55, 0.65), Vector3(side * 1.82, 0.78, 0), stone)
		DungeonGeometry.box(_structure, Vector3(0.85, 0.25, 0.9), Vector3(side * 1.82, 0.23, 0), iron)
	# Opaque emissive aperture avoids transparency sorting through dungeon walls.
	var disk := CylinderMesh.new()
	disk.top_radius = 1.48
	disk.bottom_radius = 1.48
	disk.height = 0.045
	disk.radial_segments = 32
	_surface = DungeonGeometry.mesh_instance(_structure, disk, surface, Vector3(0, 1.72, 0.03), Vector3(1, 1, 1.08))
	_surface.rotation.x = PI * 0.5
	_runes = Node3D.new()
	_runes.position = Vector3(0, 1.72, 0.10)
	_structure.add_child(_runes)
	for index in range(18):
		var angle := float(index) * TAU / 18.0
		var radius := 1.12 if index % 3 == 0 else 1.26
		var at := Vector3(cos(angle) * radius, sin(angle) * radius, 0)
		var mark := DungeonGeometry.box(_runes, Vector3(0.08, 0.24, 0.035), at, rune)
		mark.rotation.z = angle - PI * 0.5
	for index in range(3):
		var ring := DungeonGeometry.torus(_structure, 0.51 + index * 0.23, 0.55 + index * 0.23, Vector3(0, 1.72, 0.12), rune)
		ring.rotation.x = PI * 0.5
		# Offset rings suggest a moving magical tunnel rather than a flat sign.
		ring.scale.x = 1.0 - index * 0.08
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 2.1, 1.0)
	_light.light_color = Color("a452ff")
	_light.shadow_enabled = true
	add_child(_light)
	_beacon = Node3D.new()
	_beacon.name = "UnexploredBeacon"
	add_child(_beacon)
	var beacon_material := DungeonGeometry.material(Color("bc8bff"), Color("9d5ae7"), 2.0)
	var beacon_ring := DungeonGeometry.torus(_beacon, 0.78, 0.84, Vector3(0, 2.85, 0), beacon_material)
	beacon_ring.rotation.x = PI * 0.5
	var crystal := DungeonGeometry.mesh_instance(_beacon, DungeonGeometry.octahedron(), beacon_material, Vector3(0, 3.05, 0), Vector3(0.24, 0.55, 0.24))
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label = Label3D.new()
	_label.position = Vector3(0, 4.0, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
	_label.pixel_size = 0.010
	_label.modulate = Color(0.77, 0.62, 0.92)
	add_child(_label)
	_apply_state()


func _apply_state() -> void:
	_structure.visible = _discovered
	_beacon.visible = not _discovered
	_label.visible = _discovered
	_label.text = "CLAIMED PORTAL" if _claimed else "UNCLAIMED PORTAL"
	_rune_material.emission_energy_multiplier = 2.4 if _claimed else 0.65
	_surface_material.emission_energy_multiplier = 1.0 if _claimed else 0.22
	_light.light_energy = (3.2 if _claimed else 1.2) if _discovered else 0.45
	_light.omni_range = (10.0 if _claimed else 6.0) if _discovered else 3.0
	_light.position.y = 2.1 if _discovered else 3.0
	set_meta("claimed", _claimed)
	set_meta("discovered", _discovered)


func _process(delta: float) -> void:
	_elapsed += delta
	_runes.rotation.z += delta * (0.16 if _claimed else 0.035)
	_beacon.rotation.y += delta * 0.3
	_beacon.scale = Vector3.ONE * (1.0 + sin(_elapsed * 1.2) * 0.035)
	_surface.scale.x = 1.0 + sin(_elapsed * 1.7) * 0.025
