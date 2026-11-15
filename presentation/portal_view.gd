class_name DungeonPortalView
extends Node3D
## Separate creature entrance landmark; no arrival logic lives in this view.

var _runes: Node3D
var _surface: MeshInstance3D
var _elapsed := 0.0


func _ready() -> void:
	var stone := DungeonGeometry.material(Color("3c364c"))
	var dark_stone := DungeonGeometry.material(Color("252333"))
	var rune := DungeonGeometry.material(Color("d3a4ff"), Color("b358ff"), 2.4)
	var surface := DungeonGeometry.material(Color("35145e"), Color("7b2bce"), 1.0)
	var iron := DungeonGeometry.material(Color("44384a"))
	DungeonGeometry.cylinder(self, 2.3, 0.22, Vector3(0, 0.11, 0), dark_stone, -1, 12)
	for index in range(13):
		var angle := float(index) / 12.0 * PI
		var at := Vector3(cos(angle) * 1.82, 1.55 + sin(angle) * 1.82, 0)
		var block := DungeonGeometry.box(self, Vector3(0.64, 0.7, 0.65), at, stone)
		block.rotation.z = angle - PI * 0.5
	for side in [-1.0, 1.0]:
		DungeonGeometry.box(self, Vector3(0.65, 1.55, 0.65), Vector3(side * 1.82, 0.78, 0), stone)
		DungeonGeometry.box(self, Vector3(0.85, 0.25, 0.9), Vector3(side * 1.82, 0.23, 0), iron)
	# Opaque emissive aperture avoids transparency sorting through dungeon walls.
	var disk := CylinderMesh.new()
	disk.top_radius = 1.48
	disk.bottom_radius = 1.48
	disk.height = 0.045
	disk.radial_segments = 32
	_surface = DungeonGeometry.mesh_instance(self, disk, surface, Vector3(0, 1.72, 0.03), Vector3(1, 1, 1.08))
	_surface.rotation.x = PI * 0.5
	_runes = Node3D.new()
	_runes.position = Vector3(0, 1.72, 0.10)
	add_child(_runes)
	for index in range(18):
		var angle := float(index) * TAU / 18.0
		var radius := 1.12 if index % 3 == 0 else 1.26
		var at := Vector3(cos(angle) * radius, sin(angle) * radius, 0)
		var mark := DungeonGeometry.box(_runes, Vector3(0.08, 0.24, 0.035), at, rune)
		mark.rotation.z = angle - PI * 0.5
	for index in range(3):
		var ring := DungeonGeometry.torus(self, 0.51 + index * 0.23, 0.55 + index * 0.23, Vector3(0, 1.72, 0.12), rune)
		ring.rotation.x = PI * 0.5
		# Offset rings suggest a moving magical tunnel rather than a flat sign.
		ring.scale.x = 1.0 - index * 0.08
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.1, 1.0)
	light.light_color = Color("a452ff")
	light.light_energy = 3.2
	light.omni_range = 10.0
	add_child(light)


func _process(delta: float) -> void:
	_elapsed += delta
	_runes.rotation.z += delta * 0.16
	_surface.scale.x = 1.0 + sin(_elapsed * 1.7) * 0.025
