class_name ContentRegistry
extends RefCounted
## Register definitions atomically. Duplicate or malformed content fails at startup.

var _creatures: Dictionary[StringName, CreatureDefinition] = {}
var _rooms: Dictionary[StringName, RoomDefinition] = {}
var _modules: Dictionary[StringName, ContentModule] = {}


func register_module(module: ContentModule) -> String:
	if module == null or module.id == &"":
		return "Module requires an ID"
	if _modules.has(module.id):
		return "Duplicate module ID: %s" % module.id
	var ids: Dictionary = {}
	for definition in module.definitions:
		if not (definition is CreatureDefinition or definition is RoomDefinition):
			return "Module %s contains an unsupported definition" % module.id
		var error: String = definition.validation_error()
		if not error.is_empty():
			return "%s: %s" % [module.id, error]
		if ids.has(definition.id) or _creatures.has(definition.id) or _rooms.has(definition.id):
			return "Duplicate content ID: %s" % definition.id
		ids[definition.id] = true
	for feature_script in module.feature_scripts:
		if feature_script == null or not _is_feature_script(feature_script):
			return "Module %s contains a script that does not extend GameFeature" % module.id
	# Commit only after the entire manifest passes validation.
	_modules[module.id] = module
	for definition in module.definitions:
		if definition is CreatureDefinition:
			_creatures[definition.id] = definition
		else:
			_rooms[definition.id] = definition
	return ""


func get_creature(id: StringName) -> CreatureDefinition:
	return _creatures.get(id)


func get_room(id: StringName) -> RoomDefinition:
	return _rooms.get(id)


func get_rooms() -> Array[RoomDefinition]:
	var definitions: Array[RoomDefinition] = []
	definitions.assign(_rooms.values())
	return definitions


func module_count() -> int:
	return _modules.size()


func _is_feature_script(candidate: Script) -> bool:
	var current: Script = candidate
	while current != null:
		if current == preload("res://core/game_feature.gd"):
			return true
		current = current.get_base_script()
	return false
