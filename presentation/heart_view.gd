class_name DungeonHeartView
extends Node3D
## Landmark view only: heartbeat never produces resources or mutates simulation.

var _organ: Node3D
var _light: OmniLight3D
var _elapsed := 0.0


func _ready() -> void:
	var stone := DungeonGeometry.material(Color("38363c"))
	var iron := DungeonGeometry.material(Color("292629"))
	var rust := DungeonGeometry.material(Color("68503c"))
	var flesh := DungeonGeometry.material(Color("922c49"))
	var dark_flesh := DungeonGeometry.material(Color("501e36"))
	var vein := DungeonGeometry.material(Color("bc5061"))
	var blood := DungeonGeometry.material(Color("351422"), Color("b52b50"), 0.2)
	var wax := DungeonGeometry.material(Color("c5ac7a"))
	var fire := DungeonGeometry.material(Color("ffce77"), Color("ff9e35"), 3.0)
	DungeonGeometry.cylinder(self, 2.0, 0.32, Vector3(0, 0.16, 0), stone, 1.9, 12)
	DungeonGeometry.cylinder(self, 1.55, 0.3, Vector3(0, 0.4, 0), iron, 1.8, 12)
	DungeonGeometry.cylinder(self, 1.43, 0.035, Vector3(0, 0.56, 0), blood, -1, 16)
	DungeonGeometry.torus(self, 1.5, 1.8, Vector3(0, 0.55, 0), rust)
	_organ = Node3D.new()
	_organ.position.y = 1.72
	add_child(_organ)
	var left := DungeonGeometry.sphere(_organ, Vector3(-0.37, 0.17, 0.0), Vector3(1.25, 1.37, 1.03), flesh)
	left.rotation.z = -0.25
	var right := DungeonGeometry.sphere(_organ, Vector3(0.35, 0.22, 0.03), Vector3(1.03, 1.23, 1.05), flesh)
	right.rotation.z = 0.2
	var tip := DungeonGeometry.sphere(_organ, Vector3(-0.04, -0.39, 0.04), Vector3(1.07, 1.17, 0.85), flesh)
	tip.rotation.z = -0.2
	DungeonGeometry.cylinder(_organ, 0.23, 0.73, Vector3(-0.33, 0.97, 0), dark_flesh, 0.25)
	DungeonGeometry.cylinder(_organ, 0.12, 0.47, Vector3(0.25, 0.88, -0.05), vein, 0.16)
	var artery := DungeonGeometry.cylinder(_organ, 0.15, 0.65, Vector3(0.48, 0.65, -0.12), dark_flesh, 0.2)
	artery.rotation.z = -0.8
	# Raised veins retain readable shape even at overview zoom.
	DungeonGeometry.rod(_organ, Vector3(-0.22, 0.72, 0.48), Vector3(0.16, 0.13, 0.57), 0.055, vein)
	DungeonGeometry.rod(_organ, Vector3(0.16, 0.13, 0.57), Vector3(-0.19, -0.52, 0.39), 0.045, dark_flesh)
	DungeonGeometry.rod(_organ, Vector3(0.08, 0.23, 0.57), Vector3(-0.53, 0.1, 0.43), 0.034, vein)
	for side in [-1.0, 1.0]:
		var post := Vector3(side * 2.05, 1.8, -0.65)
		DungeonGeometry.box(self, Vector3(0.35, 3.6, 0.35), post, iron)
		DungeonGeometry.box(self, Vector3(0.62, 0.2, 0.62), post + Vector3(0, 1.72, 0), rust)
		var top := post + Vector3(0, 1.4, 0)
		var bottom := Vector3(side * 0.6, 1.9, 0)
		for link_index in range(9):
			var at := top.lerp(bottom, float(link_index) / 8.0)
			var link := DungeonGeometry.torus(self, 0.07, 0.12, at, iron)
			link.rotation.x = PI * 0.5
			link.rotation.y = 0.65 if link_index % 2 == 0 else -0.65
	for index in range(5):
		var angle := float(index) * TAU / 5.0 + 0.2
		var at := Vector3(cos(angle) * 2.2, 0.0, sin(angle) * 2.2)
		DungeonGeometry.cylinder(self, 0.10, 0.38, at + Vector3(0, 0.19, 0), wax)
		DungeonGeometry.sphere(self, at + Vector3(0, 0.49, 0), Vector3(0.13, 0.23, 0.13), fire, 6)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 2.9, 0)
	_light.light_color = Color("f75b68")
	_light.light_energy = 1.8
	_light.omni_range = 8.0
	_light.shadow_enabled = true
	_light.shadow_bias = 0.035
	add_child(_light)


func _process(delta: float) -> void:
	_elapsed += delta
	# Two short contractions followed by a rest, rather than a uniform bob.
	var phase := fmod(_elapsed, 1.3)
	var beat := exp(-pow((phase - 0.16) * 13.0, 2.0)) + 0.55 * exp(-pow((phase - 0.39) * 14.0, 2.0))
	_organ.scale = Vector3(1.0 + beat * 0.07, 1.0 - beat * 0.045, 1.0 + beat * 0.06)
	_light.light_energy = 1.5 + beat * 0.65
