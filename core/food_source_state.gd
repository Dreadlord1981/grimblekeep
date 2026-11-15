class_name FoodSourceState
extends RefCounted
## A tile or pooled room output profile. Progress survives harmless room edits.

var food_id: StringName
var capacity: int = 0
var production_seconds: float = 0.0
var progress: float = 0.0
var cells: Array[Vector2i] = []
