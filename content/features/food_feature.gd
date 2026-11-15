extends GameFeature
## Definition-driven breeding/production, bounded by physical room-tile storage.

var _roaming := FoodRoaming.new()


func tick(delta: float) -> void:
	if context == null or context.food == null or not is_finite(delta) or delta <= 0.0:
		return
	context.food.age_units(delta)
	_roaming.tick(context, delta)
	for cell in context.food.sources:
		var source: FoodSourceState = context.food.sources[cell]
		if source.production_seconds <= 0.0:
			continue
		var free := context.food.source_free_capacity(cell)
		if free == 0:
			source.progress = 0.0
			continue
		source.progress += delta
		var due := floori(source.progress / source.production_seconds)
		if due <= 0:
			continue
		context.food.produce(cell, source.food_id, mini(due, free))
		source.progress = 0.0 if context.food.source_free_capacity(cell) == 0 else fmod(source.progress, source.production_seconds)
