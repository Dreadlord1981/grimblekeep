class_name HeldCreaturePreview
extends Control
## A separate transparent studio renders the held identity's actual view scene.
## There is one authoritative actor; this node owns presentation objects only.

var context: GameContext
var bound_actor_id := -1
var bound_gold := 0
var bound_item_id := -1
var _viewport: SubViewport
var _stage: Node3D
var _wrapper: Node3D
var _camera: Camera3D
var _view: Node3D
var _texture: TextureRect
var _identity: Label
var _cargo: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(144, 144)
	size = custom_minimum_size
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(192, 192)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	_wrapper = Node3D.new()
	_wrapper.rotation.y = -0.35
	_stage.add_child(_wrapper)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.2
	_camera.near = 0.05
	_camera.far = 30.0
	_stage.add_child(_camera)
	_camera.make_current()
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0, 0, 0, 0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.75, 0.77, 0.82)
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	_stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color(1.0, 0.88, 0.73)
	key.light_energy = 1.4
	_stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2, 2, 3)
	fill.light_energy = 0.6
	fill.omni_range = 8.0
	_stage.add_child(fill)
	_texture = TextureRect.new()
	_texture.texture = _viewport.get_texture()
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_texture)
	_identity = _label(12)
	_identity.position = Vector2(-38, -24)
	_identity.size = Vector2(220, 18)
	add_child(_identity)
	_cargo = _label(11)
	_cargo.position = Vector2(-38, -9)
	_cargo.size = Vector2(220, 18)
	add_child(_cargo)
	visible = false
	if context != null:
		context.keeper.changed.connect(_refresh_held)
		_refresh_held()


func _process(_delta: float) -> void:
	_refresh_held()


func _refresh_held() -> void:
	if context == null:
		return
	var actor: CreatureState = context.keeper.held_actor
	var id := actor.id if actor != null else -1
	var gold: int = context.keeper.held_gold
	var front = context.keeper.peek_item()
	var item_id: int = front.id if front != null else -1
	if item_id != bound_item_id:
		_clear_model()
		bound_item_id = item_id
		bound_actor_id = id
		bound_gold = gold
		if actor != null:
			_create_model(actor)
		elif gold > 0:
			_create_gold()
	bound_gold = gold
	visible = (actor != null or gold > 0) and _view != null
	if gold > 0 and _view != null:
		_identity.text = "Gold · %d" % gold
		_cargo.text = "Next of %d held" % context.keeper.held_count
		return
	if actor == null or _view == null:
		return
	_sync(actor)
	var definition := context.registry.get_creature(actor.definition_id)
	var label := actor.custom_name if not actor.custom_name.is_empty() else definition.display_name
	_identity.text = "#%d  %s" % [actor.id, label]
	_cargo.text = "%d gold carried" % actor.carried_gold if &"haul" in definition.capabilities or actor.carried_gold > 0 else definition.display_name


func _create_model(actor: CreatureState) -> void:
	var definition := context.registry.get_creature(actor.definition_id)
	if definition == null:
		return
	if definition.view_scene != null:
		var candidate := definition.view_scene.instantiate()
		if candidate is Node3D:
			_view = candidate
		else:
			candidate.free()
	if _view == null:
		var worker := DungeonCreatureView.new()
		worker.build(definition.body_color)
		_view = worker
	_view.name = "HeldModel_%d" % actor.id
	_view.scale = Vector3.ONE * definition.scale_factor
	_wrapper.add_child(_view)
	if _view.has_method("setup_context"):
		_view.call("setup_context", context)
	_view.set_process(false)
	_sync(actor)
	_fit_camera()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _create_gold() -> void:
	_view = Node3D.new()
	_view.name = "HeldGold"
	_wrapper.add_child(_view)
	var sack := DungeonGeometry.material(Color("796143"))
	var tie := DungeonGeometry.material(Color("41362c"))
	var coins := DungeonGeometry.material(Color("d5a549"), Color("a76d22"), 0.15)
	DungeonGeometry.sphere(_view, Vector3(0, 0.51, 0), Vector3(0.74, 0.90, 0.65), sack, 8)
	DungeonGeometry.torus(_view, 0.16, 0.23, Vector3(0, 0.88, 0), tie)
	for index in range(8):
		var offset := Vector3(float(index % 3 - 1) * 0.13, 0.90 + float(index / 3) * 0.04, float(index % 2) * 0.12 - 0.06)
		var coin := DungeonGeometry.cylinder(_view, 0.12, 0.045, offset, coins, -1, 8)
		coin.rotation.z = float(index % 3 - 1) * 0.22
	_fit_camera()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _sync(actor: CreatureState) -> void:
	if _view.has_method("sync"):
		_view.call("sync", actor)
	# sync reads the real actor, including its cargo, but world coordinates never
	# move the studio or write back to actor state.
	_view.position = Vector3.ZERO
	_view.rotation = Vector3.ZERO


func _fit_camera() -> void:
	var bounds := AABB()
	var found := false
	for item in _view.find_children("*", "MeshInstance3D", true, false):
		var mesh := item as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	var center := bounds.get_center() if found else Vector3(0, 0.8, 0)
	_camera.size = maxf(1.2, maxf(bounds.size.y, bounds.size.x) * 1.28) if found else 2.2
	_camera.position = center + Vector3(0, 0.20, 5)
	_camera.look_at(center)


func _clear_model() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _view != null:
		_wrapper.remove_child(_view)
		_view.free()
		_view = null
	visible = false
	_identity.text = ""
	_cargo.text = ""


func _label(size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.89, 0.84, 0.69))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label
