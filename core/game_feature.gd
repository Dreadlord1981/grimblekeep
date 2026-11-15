class_name GameFeature
extends Node
## Optional mechanics implement this lifecycle. No scene-tree or UI dependencies.

var context: GameContext


func setup(game_context: GameContext) -> void:
	context = game_context


func tick(_delta: float) -> void:
	pass
