extends Node3D
## Composition root: load content, create session, attach independent views/input.

const Layout = preload("res://content/scenarios/foundation_layout.gd")
var context: GameContext
var controller: KeeperController
var _features: Array[GameFeature] = []
var _capture_frame: int = -1
var _frame_count: int = 0


func _ready() -> void:
	var registry := ContentRegistry.new()
	var modules: Array[ContentModule] = []
	for path in ProjectSettings.get_setting("grimblekeep/content_modules", []):
		var module := load(path) as ContentModule
		var error := registry.register_module(module)
		if not error.is_empty():
			push_error("Content startup failed: %s (%s)" % [error, path])
			get_tree().quit(1)
			return
		modules.append(module)
	context = GameContext.new(Layout.create(), registry)
	Layout.setup_rooms(context)
	for cell in [Vector2i(12, 16), Vector2i(16, 14), Vector2i(7, 15)]:
		context.spawn_creature(&"foundation.imp", cell)
	for module in modules:
		for feature_script in module.feature_scripts:
			var feature := feature_script.new() as GameFeature
			add_child(feature)
			feature.setup(context)
			_features.append(feature)
	var view := DungeonView.new()
	add_child(view)
	view.setup(context)
	controller = KeeperController.new()
	add_child(controller)
	controller.setup(context)
	var hud := DungeonHUD.new()
	add_child(hud)
	hud.setup(context, controller)
	if "--capture" in OS.get_cmdline_user_args():
		_capture_frame = 90
	print("GRIMBLEKEEP ready | modules=%d | actors=%d | milestone=2-construction" % [registry.module_count(), context.actors.size()])


func _physics_process(delta: float) -> void:
	if context == null:
		return
	for feature in _features:
		feature.tick(delta)
	context.simulation_ticked.emit(delta)


func _process(_delta: float) -> void:
	_frame_count += 1
	if _capture_frame == _frame_count:
		_capture_and_quit()


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := get_viewport().get_texture().get_image().save_png("res://artifacts/foundation.png")
	print("Capture result: %s" % error_string(error))
	get_tree().quit(0 if error == OK else 1)
