class_name ContentRegistry
extends RefCounted
## Register definitions atomically. Duplicate or malformed content fails at startup.

var _creatures: Dictionary[StringName, CreatureDefinition] = {}
var _rooms: Dictionary[StringName, RoomDefinition] = {}
var _foods: Dictionary[StringName, FoodDefinition] = {}
var _modules: Dictionary[StringName, ContentModule] = {}


func register_module(module: ContentModule) -> String:
	if module == null or module.id == &"":
		return "Module requires an ID"
	if _modules.has(module.id):
		return "Duplicate module ID: %s" % module.id
	var ids: Dictionary = {}
	for definition in module.definitions:
		if not (definition is CreatureDefinition or definition is RoomDefinition or definition is FoodDefinition):
			return "Module %s contains an unsupported definition" % module.id
		var error: String = definition.validation_error()
		if not error.is_empty():
			return "%s: %s" % [module.id, error]
		if ids.has(definition.id) or _creatures.has(definition.id) or _rooms.has(definition.id) or _foods.has(definition.id):
			return "Duplicate content ID: %s" % definition.id
		ids[definition.id] = definition
	# References may point to foods registered earlier or anywhere in this manifest.
	for definition in module.definitions:
		if definition is RoomDefinition and definition.food_type != &"":
			if not _foods.has(definition.food_type) and not (ids.get(definition.food_type) is FoodDefinition):
				return "Unknown food type: %s" % definition.food_type
	for feature_script in module.feature_scripts:
		if feature_script == null or not _is_feature_script(feature_script):
			return "Module %s contains a script that does not extend GameFeature" % module.id
	# Commit only after the entire manifest passes validation.
	_modules[module.id] = module
	for definition in module.definitions:
		if definition is CreatureDefinition:
			_creatures[definition.id] = definition
		elif definition is RoomDefinition:
			_rooms[definition.id] = definition
		else:
			_foods[definition.id] = definition
	return ""


func get_creature(id: StringName) -> CreatureDefinition:
	return _creatures.get(id)


func get_creatures() -> Array[CreatureDefinition]:
	var definitions: Array[CreatureDefinition] = []
	definitions.assign(_creatures.values())
	return definitions


func get_room(id: StringName) -> RoomDefinition:
	return _rooms.get(id)


func get_rooms() -> Array[RoomDefinition]:
	var definitions: Array[RoomDefinition] = []
	definitions.assign(_rooms.values())
	return definitions


func get_food(id: StringName) -> FoodDefinition:
	return _foods.get(id)


func get_foods() -> Array[FoodDefinition]:
	var definitions: Array[FoodDefinition] = []
	definitions.assign(_foods.values())
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
