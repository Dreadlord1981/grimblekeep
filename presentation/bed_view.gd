class_name DungeonBedView
extends Node3D
## A personal cot exists only for an authoritative reserved BedState.


func build(bed: BedState, grid: DungeonGrid) -> void:
	name = "PersonalBed_%d" % bed.owner_id
	position = bed.center(grid)
	set_meta("owner_id", bed.owner_id)
	set_meta("anchor", bed.anchor)
	set_meta("footprint", bed.size)
	var wood := DungeonGeometry.material(Color("4c352b"))
	var wood_light := DungeonGeometry.material(Color("72513a"))
	var mattress := DungeonGeometry.material(Color("8f816b"))
	var cloth := DungeonGeometry.material(Color("70473b"))
	var patch := DungeonGeometry.material(Color("a58e6b"))
	var iron := DungeonGeometry.material(Color("302b2d"))
	var bone := DungeonGeometry.material(Color("b8ad88"))
	var width := float(bed.size.x) * 1.68
	var length := float(bed.size.y) * 1.68
	DungeonGeometry.box(self, Vector3(width, 0.12, length), Vector3(0, 0.22, 0), wood)
	for side in [-1, 1]:
		for end in [-1, 1]:
			DungeonGeometry.box(self, Vector3(0.13, 0.37, 0.13), Vector3(side * width * 0.43, 0.19, end * length * 0.43), wood_light)
		DungeonGeometry.box(self, Vector3(width + 0.05, 0.27, 0.12), Vector3(0, 0.44, side * length * 0.46), wood_light)
		DungeonGeometry.box(self, Vector3(0.07, 0.15, 0.14), Vector3(width * 0.34, 0.43, side * length * 0.46), iron)
	DungeonGeometry.sphere(self, Vector3(0, 0.35, 0), Vector3(width * 0.94, 0.23, length * 0.91), mattress, 8)
	DungeonGeometry.sphere(self, Vector3(0, 0.43, -length * 0.30), Vector3(width * 0.65, 0.19, length * 0.26), patch, 8)
	DungeonGeometry.box(self, Vector3(width * 0.92, 0.045, length * 0.56), Vector3(0, 0.47, length * 0.13), cloth)
	var sewn_patch := DungeonGeometry.box(self, Vector3(width * 0.25, 0.015, length * 0.22), Vector3(-width * 0.21, 0.50, length * 0.12), patch)
	sewn_patch.rotation.y = 0.13
	for stitch in range(4):
		DungeonGeometry.box(self, Vector3(0.035, 0.025, 0.08), Vector3(-width * 0.33 + stitch * 0.12, 0.52, length * 0.22), wood)
	for fringe in range(7):
		DungeonGeometry.box(self, Vector3(width * 0.10, 0.10 + float(fringe % 3) * 0.035, 0.035), Vector3(-width * 0.39 + fringe * width * 0.13, 0.39, length * 0.43), cloth)
	# A discarded boot and a tiny skull make each reserved nest feel inhabited.
	var boot_at := Vector3(width * 0.36, 0.16, length * 0.34)
	DungeonGeometry.sphere(self, boot_at, Vector3(0.25, 0.20, 0.34), wood, 6)
	DungeonGeometry.cylinder(self, 0.09, 0.15, boot_at + Vector3(0, 0.13, -0.08), iron, 0.11, 6)
	var skull_at := Vector3(width * 0.35, 0.64, -length * 0.43)
	DungeonGeometry.sphere(self, skull_at, Vector3(0.21, 0.21, 0.16), bone, 6)
	for side in [-1, 1]:
		DungeonGeometry.sphere(self, skull_at + Vector3(side * 0.043, 0.015, 0.07), Vector3(0.045, 0.055, 0.025), iron, 6)
