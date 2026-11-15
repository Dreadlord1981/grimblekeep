extends Node3D
## Composition root: load content, create session, attach independent views/input.

const Layout = preload("res://content/scenarios/foundation_layout.gd")
@export var starting_gold: int = 3000
@export var use_heart_storage: bool = true
const DEFAULT_SAVE_PATH := "user://saves/dungeon.json"
var save_path: String = DEFAULT_SAVE_PATH
var context: GameContext
var controller: KeeperController
var hud: DungeonHUD
var _modules: Array[ContentModule] = []
var _features: Array[GameFeature] = []
var _capture_frame: int = -1
var _frame_count: int = 0


func _ready() -> void:
	var registry := ContentRegistry.new()
	for path in ProjectSettings.get_setting("grimblekeep/content_modules", []):
		var module := load(path) as ContentModule
		var error := registry.register_module(module)
		if not error.is_empty():
			push_error("Content startup failed: %s (%s)" % [error, path])
			get_tree().quit(1)
			return
		_modules.append(module)
	context = GameContext.new(Layout.create(), registry)
	Layout.setup_rooms(context, starting_gold, use_heart_storage)
	for cell in [Vector2i(12, 16), Vector2i(16, 14), Vector2i(7, 15)]:
		context.spawn_creature(&"foundation.imp", cell)
	_features = _create_features(context)
	_attach_session()
	if "--capture" in OS.get_cmdline_user_args():
		_capture_frame = 90
	print("GRIMBLEKEEP ready | modules=%d | actors=%d | milestone=4-save" % [registry.module_count(), context.actors.size()])


func _create_features(session: GameContext) -> Array[GameFeature]:
	var features: Array[GameFeature] = []
	for module in _modules:
		for feature_script in module.feature_scripts:
			var feature := feature_script.new() as GameFeature
			feature.setup(session)
			features.append(feature)
	return features


func _attach_session() -> void:
	for feature in _features:
		add_child(feature)
	var view := DungeonView.new()
	add_child(view)
	view.setup(context)
	controller = KeeperController.new()
	add_child(controller)
	controller.setup(context)
	hud = DungeonHUD.new()
	add_child(hud)
	hud.setup(context, controller)
	hud.set_save_path(save_path)
	hud.save_requested.connect(_request_save)
	hud.load_requested.connect(_request_load)


func _request_save() -> void:
	# Defer GUI commands so loading never frees a button in its pressed signal.
	save_game.call_deferred()


func _request_load() -> void:
	load_game.call_deferred()


func save_game() -> Dictionary:
	var feature_result := FeaturePersistence.capture(_features)
	if not feature_result.error.is_empty():
		return _save_feedback(feature_result.error, false)
	var data := DungeonSave.capture(context)
	data.features = feature_result.state
	data.presentation = SessionPresentation.capture(controller)
	# Validate extension state as well as the core snapshot before replacing disk.
	var restored := DungeonSave.restore(data, context.registry)
	if not restored.error.is_empty():
		return _save_feedback(restored.error, false)
	var candidate: GameContext = restored.context
	var error := SessionPresentation.validation_error(data.presentation, candidate.grid)
	var features: Array[GameFeature] = []
	if error.is_empty():
		features = _create_features(candidate)
		error = FeaturePersistence.restore(features, data.features)
	_free_features(features)
	if error.is_empty():
		error = DungeonSaveStore.write_save(save_path, data, context.registry)
	return _save_feedback("Dungeon saved" if error.is_empty() else "Save failed: %s" % error, error.is_empty())


func load_game() -> Dictionary:
	var result := DungeonSaveStore.read_save(save_path, context.registry)
	if not result.error.is_empty():
		return _save_feedback("Load failed: %s" % result.error, false)
	var candidate: GameContext = result.context
	var presentation: Dictionary = result.get("presentation", {})
	var error := SessionPresentation.validation_error(presentation, candidate.grid)
	if not error.is_empty():
		return _save_feedback("Load failed: %s" % error, false)
	var features := _create_features(candidate)
	error = FeaturePersistence.restore(features, result.get("features", {}))
	if not error.is_empty():
		_free_features(features)
		return _save_feedback("Load failed: %s" % error, false)
	# No mutation of the live dungeon occurs until every state owner has accepted.
	for child in get_children():
		remove_child(child)
		child.free()
	context = candidate
	_features = features
	_attach_session()
	SessionPresentation.apply(controller, presentation)
	return _save_feedback("Dungeon loaded from recovery backup" if result.get("recovered_backup", false) else "Dungeon loaded", true)


func _free_features(features: Array[GameFeature]) -> void:
	for feature in features:
		feature.free()


func _save_feedback(message: String, success: bool) -> Dictionary:
	if hud != null:
		hud.show_save_result(message, success)
	return {"success": success, "reason": message}


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
