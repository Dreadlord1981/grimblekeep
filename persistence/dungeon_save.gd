class_name DungeonSave
extends RefCounted
## Versioned JSON session boundary. Restore constructs a detached candidate only.

const FORMAT := "grimblekeep.dungeon"
const VERSION := 1


static func capture(context: GameContext) -> Dictionary:
	var result := {"format": FORMAT, "version": VERSION, "features": {}, "presentation": {}}
	result.merge(WorldSaveCodec.capture(context))
	result.merge(CreatureSaveCodec.capture(context))
	result["food"] = FoodSaveCodec.capture(context)
	return result


static func restore(data: Dictionary, registry: ContentRegistry) -> Dictionary:
	var reader := SaveReader.new()
	if registry == null:
		return _failure("No content registry is available")
	if reader.text(data.get("format"), "save format") != FORMAT or reader.integer(data.get("version"), "save version", 1) != VERSION:
		return _failure("Unsupported save format or version")
	var features := reader.object(data.get("features"), "feature state")
	var presentation := reader.object(data.get("presentation", {}), "presentation state")
	var grid := WorldSaveCodec.restore_grid(data, reader)
	if grid == null or not reader.error.is_empty():
		return _failure(reader.error)
	var context := GameContext.new(grid, registry)
	WorldSaveCodec.restore(context, data, reader)
	if not reader.error.is_empty():
		return _failure(reader.error)
	CreatureSaveCodec.restore(context, data, reader)
	FoodSaveCodec.restore(context, data.get("food"), reader)
	var physical := _physical_gold(context, reader)
	var supplied := reader.add(context.economy.initial_gold, context.economy.gem_gold_created, "Gold supply")
	supplied = reader.add(supplied, context.economy.refunded_gold, "Gold supply")
	if physical != supplied:
		reader.fail("Gold ledger does not balance")
	if not reader.error.is_empty():
		return _failure(reader.error)
	return {"context": context, "error": "", "features": features.duplicate(true), "presentation": presentation.duplicate(true)}


static func _physical_gold(context: GameContext, reader: SaveReader) -> int:
	var economy := context.economy
	var total := reader.add(economy.spent_gold, economy.keeper_gold, "Gold ledger")
	for values in [economy.remaining_gold, economy.ground_gold, economy.stored_by_cell]:
		for amount: int in values.values():
			total = reader.add(total, amount, "Gold ledger")
	for actor in context.actors:
		total = reader.add(total, actor.carried_gold, "Carried gold")
	for actor in economy.pending_cargo.values():
		total = reader.add(total, actor.carried_gold, "Recoverable gold")
	return total


static func _failure(message: String) -> Dictionary:
	return {"context": null, "error": message, "features": {}, "presentation": {}}
