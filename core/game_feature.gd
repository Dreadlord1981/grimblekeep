class_name GameFeature
extends Node
## Optional mechanics implement this lifecycle. No scene-tree or UI dependencies.

var context: GameContext


func setup(game_context: GameContext) -> void:
	context = game_context


func tick(_delta: float) -> void:
	pass


func persistence_id() -> StringName:
	# Stateless features need no save entry. Stateful extensions use a stable ID.
	return &""


func capture_state() -> Dictionary:
	return {}


func restore_state(data: Dictionary) -> String:
	return "Unsupported feature state" if not data.is_empty() else ""
