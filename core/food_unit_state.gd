class_name FoodUnitState
extends RefCounted
## A stable food identity; allocation controls capacity, position controls feeding.

var id: int
var cell: Vector2i
var food_id: StringName
var age_seconds: float = 0.0
var position := Vector3.ZERO
var heading: float = 0.0
