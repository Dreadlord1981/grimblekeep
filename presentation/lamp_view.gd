class_name DungeonLampView
extends Node3D
## Replaceable local light fixture; construction/ownership belong to simulation.

var light: OmniLight3D


func build(room_fixture: bool = false) -> void:
	var iron := DungeonGeometry.material(Color("29272b"))
	var brass := DungeonGeometry.material(Color("796345"))
	var fire := DungeonGeometry.material(Color("ffcb80"), Color("ff9c43"), 2.2)
	# Local +Z points away from the supporting wall, into the open room.
	var plate := DungeonGeometry.box(self, Vector3(0.25, 0.48, 0.075), Vector3(0, 1.18, 0), iron)
	plate.name = "WallPlate"
	var bracket := DungeonGeometry.rod(self, Vector3(0, 1.02, 0.03), Vector3(0, 1.10, 0.28), 0.045, iron)
	bracket.name = "Bracket"
	DungeonGeometry.rod(self, Vector3(0, 1.10, 0.28), Vector3(0, 1.26, 0.28), 0.045, iron)
	DungeonGeometry.cylinder(self, 0.17, 0.11, Vector3(0, 1.28, 0.28), brass, 0.20)
	DungeonGeometry.cylinder(self, 0.12, 0.14, Vector3(0, 1.38, 0.28), iron, 0.17)
	var flame := DungeonGeometry.sphere(self, Vector3(0, 1.57, 0.28), Vector3(0.22, 0.34, 0.22), fire, 6)
	flame.name = "Flame"
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light = OmniLight3D.new()
	light.name = "LocalLight"
	light.position = Vector3(0, 1.65, 0.48)
	light.light_color = Color("ffb76b") if not room_fixture else Color("ffd29a")
	light.light_energy = 3.4 if not room_fixture else 2.8
	light.omni_range = 8.0 if not room_fixture else 7.0
	light.omni_attenuation = 1.0
	light.shadow_enabled = true
	light.shadow_bias = 0.035
	add_child(light)
