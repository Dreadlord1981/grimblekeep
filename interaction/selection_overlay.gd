class_name KeeperSelectionOverlay
extends Node3D
## Tile feedback only. Reconcile marker nodes when cells change, never every frame.

var grid: DungeonGrid
var marked_frames: Dictionary[Vector2i, Node3D] = {}
var _add_frames: Dictionary[Vector2i, Node3D] = {}
var _remove_frames: Dictionary[Vector2i, Node3D] = {}
var _neutral_frames: Dictionary[Vector2i, Node3D] = {}
var _blocked_frames: Dictionary[Vector2i, Node3D] = {}
var _glow_material: ShaderMaterial
const GlowShader = preload("res://interaction/excavation_glow.gdshader")


func show_marks(cells: Array[Vector2i]) -> void:
	_sync_frames(marked_frames, cells, Color(0.96, 0.60, 0.20), 0.055, 0, true)


func show_preview(adding: Array[Vector2i], removing: Array[Vector2i], neutral: Array[Vector2i]) -> void:
	_sync_frames(_blocked_frames, [], Color(0.97, 0.29, 0.23), 0.05, 2)
	_sync_frames(_add_frames, adding, Color(0.45, 0.87, 0.55), 0.04, 1)
	_sync_frames(_remove_frames, removing, Color(0.97, 0.29, 0.23), 0.05, 2)
	_sync_frames(_neutral_frames, neutral, Color(0.53, 0.55, 0.54), 0.025)


func show_construction_preview(adding: Array[Vector2i], removing: Array[Vector2i], blocked: Array[Vector2i]) -> void:
	_sync_frames(_add_frames, adding, Color(0.45, 0.87, 0.55), 0.04, 1)
	_sync_frames(_remove_frames, removing, Color(0.97, 0.29, 0.23), 0.05, 2)
	_sync_frames(_neutral_frames, [], Color(0.53, 0.55, 0.54), 0.025)
	_sync_frames(_blocked_frames, blocked, Color(0.97, 0.29, 0.23), 0.055, 2)


func _make_frame(color: Color, thickness: float, marker: int = 0, glow_height: float = -1.0) -> Node3D:
	var frame := Node3D.new()
	add_child(frame)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in range(4):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.92, thickness, thickness)
		var edge := MeshInstance3D.new()
		edge.mesh = mesh
		edge.material_override = material
		if side < 2:
			edge.position.z = -0.96 if side == 0 else 0.96
		else:
			edge.rotation.y = PI * 0.5
			edge.position.x = -0.96 if side == 2 else 0.96
		frame.add_child(edge)
	if marker != 0:
		for axis in range(2):
			var symbol_mesh := BoxMesh.new()
			symbol_mesh.size = Vector3(0.90, 0.045, 0.13)
			var symbol := MeshInstance3D.new()
			symbol.mesh = symbol_mesh
			symbol.material_override = material
			symbol.position.y = 0.025
			symbol.rotation.y = float(axis) * PI * 0.5 + (PI * 0.25 if marker == 2 else 0.0)
			frame.add_child(symbol)
	if glow_height >= 0.0:
		if _glow_material == null:
			_glow_material = ShaderMaterial.new()
			_glow_material.shader = GlowShader
		var shell := MeshInstance3D.new()
		shell.name = "ExcavationGlow"
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		shell.mesh = box
		shell.scale = Vector3(2.01, glow_height + 0.12, 2.01)
		shell.position.y = -glow_height * 0.5 - 0.04
		shell.material_override = _glow_material
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(shell)
	return frame


func _sync_frames(frames: Dictionary[Vector2i, Node3D], cells: Array[Vector2i], color: Color, thickness: float, marker: int = 0, glowing: bool = false) -> void:
	var wanted: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		wanted[cell] = true
	for cell in frames.keys():
		if not wanted.has(cell):
			frames[cell].queue_free()
			frames.erase(cell)
	for cell in cells:
		if not frames.has(cell):
			frames[cell] = _make_frame(color, thickness, marker, grid.surface_height(cell) if glowing else -1.0)
		var position_in_world := grid.cell_to_world(cell)
		# Preview sits above persistent outlines, avoiding overlapping green/red edges.
		position_in_world.y = grid.surface_height(cell) + (0.05 if marker == 0 else 0.10)
		frames[cell].position = position_in_world
