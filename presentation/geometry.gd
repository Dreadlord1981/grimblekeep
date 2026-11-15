class_name DungeonGeometry
extends RefCounted
## Small mesh/material helpers shared by the replaceable procedural views.

static func material(color: Color, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.94
	if energy > 0.0:
		result.emission_enabled = true
		result.emission = emission
		result.emission_energy_multiplier = energy
	return result


static func mesh_instance(parent: Node3D, mesh: Mesh, surface: Material, at: Vector3, size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = surface
	result.position = at
	result.scale = size
	parent.add_child(result)
	return result


static func box(parent: Node3D, size: Vector3, at: Vector3, surface: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_instance(parent, mesh, surface, at)


static func sphere(parent: Node3D, at: Vector3, size: Vector3, surface: Material, segments: int = 10) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = 5
	return mesh_instance(parent, mesh, surface, at, size)


static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, surface: Material, top_radius: float = -1.0, segments: int = 10) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	return mesh_instance(parent, mesh, surface, at)


static func rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, surface: Material) -> MeshInstance3D:
	var result := cylinder(parent, radius, from.distance_to(to), (from + to) * 0.5, surface, radius, 6)
	var direction := (to - from).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		result.quaternion = Quaternion(Vector3.UP, direction)
	return result


static func octahedron() -> ArrayMesh:
	var vertices: Array[Vector3] = [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK, Vector3.DOWN]
	var faces: Array[Vector3i] = [Vector3i(0, 2, 1), Vector3i(0, 3, 2), Vector3i(0, 4, 3), Vector3i(0, 1, 4), Vector3i(5, 1, 2), Vector3i(5, 2, 3), Vector3i(5, 3, 4), Vector3i(5, 4, 1)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for face in faces:
		for index in [face.x, face.y, face.z]:
			tool.add_vertex(vertices[index])
	tool.generate_normals()
	return tool.commit()


static func chamfered_block() -> ArrayMesh:
	# Unit block with clipped corners and an inset top; instanced for stonework.
	var rim: Array[Vector2] = [Vector2(-0.38, -0.5), Vector2(0.38, -0.5), Vector2(0.5, -0.38), Vector2(0.5, 0.38), Vector2(0.38, 0.5), Vector2(-0.38, 0.5), Vector2(-0.5, 0.38), Vector2(-0.5, -0.38)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for index in range(8):
		var next := (index + 1) % 8
		var a := Vector3(rim[index].x, -0.5, rim[index].y)
		var b := Vector3(rim[next].x, -0.5, rim[next].y)
		var c := Vector3(rim[index].x, 0.38, rim[index].y)
		var d := Vector3(rim[next].x, 0.38, rim[next].y)
		var e := Vector3(rim[index].x * 0.87, 0.5, rim[index].y * 0.87)
		var f := Vector3(rim[next].x * 0.87, 0.5, rim[next].y * 0.87)
		# Godot uses clockwise front faces. Reversing the mathematical
		# outward winding keeps both culling and generated normals correct.
		var triangles := [a, c, b, b, c, d, c, e, d, d, e, f, Vector3(0, 0.5, 0), f, e]
		for triangle in range(0, triangles.size(), 3):
			tool.add_vertex(triangles[triangle])
			tool.add_vertex(triangles[triangle + 2])
			tool.add_vertex(triangles[triangle + 1])
	tool.generate_normals()
	return tool.commit()


static func torus(parent: Node3D, inner_radius: float, outer_radius: float, at: Vector3, surface: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 16
	mesh.ring_segments = 6
	return mesh_instance(parent, mesh, surface, at)
