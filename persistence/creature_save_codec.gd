class_name CreatureSaveCodec
extends RefCounted
## Persistent actor identities, homes and ordered custody; active jobs replan.


static func capture(context: GameContext) -> Dictionary:
	var actors: Array = []
	for actor in context.actors:
		actors.append(_capture_actor(actor))
	var pending: Array = []
	for actor in context.economy.pending_cargo.values():
		if actor not in context.actors:
			pending.append(_capture_actor(actor))
	var beds: Array = []
	for bed in context.beds.beds.values():
		beds.append({"owner": bed.owner_id, "anchor": SaveReader.encode_cell(bed.anchor), "size": SaveReader.encode_cell(bed.size), "room_tag": String(bed.room_tag), "established": bed.established})
	var queue: Array = []
	for item in context.keeper.get_items():
		queue.append({"id": item.id, "kind": String(item.kind), "origin": SaveReader.encode_cell(item.origin), "actor": item.actor.id if item.actor != null else 0, "gold": item.gold_amount})
	return {"actors": actors, "pending_cargo": pending, "next_actor_id": context.next_actor_id(), "beds": beds, "hand": {"items": queue, "next_id": context.keeper.next_item_id(), "inspected": context.keeper.inspected_actor.id if context.keeper.inspected_actor != null else 0}}


static func _capture_actor(actor: CreatureState) -> Dictionary:
	return {"id": actor.id, "definition": String(actor.definition_id), "position": SaveReader.encode_position(actor.position), "heading": actor.heading, "phase": actor.phase, "name": actor.custom_name, "gold": actor.carried_gold, "energy": actor.energy, "satiety": actor.satiety, "held": actor.is_held, "rest_requested": actor.rest_requested, "food_requested": actor.food_requested, "hunger_intent": actor.hunger_intent, "sleeping": actor.action == &"sleeping"}


static func restore(context: GameContext, data: Dictionary, reader: SaveReader) -> void:
	var by_id: Dictionary[int, CreatureState] = {}
	var maximum := 0
	for raw in reader.array(data.get("actors"), "creatures"):
		var actor := _restore_actor(raw, context, reader)
		if by_id.has(actor.id):
			reader.fail("Duplicate creature identity")
		by_id[actor.id] = actor
		maximum = maxi(maximum, actor.id)
		context.actors.append(actor)
	for raw in reader.array(data.get("pending_cargo"), "pending cargo"):
		var actor := _restore_actor(raw, context, reader)
		if by_id.has(actor.id) or actor.carried_gold <= 0 or actor.is_held:
			reader.fail("Invalid or duplicate pending cargo identity")
		by_id[actor.id] = actor
		maximum = maxi(maximum, actor.id)
		context.economy.pending_cargo[actor.id] = actor
	var next_actor := reader.integer(data.get("next_actor_id"), "next creature identity", 1)
	if next_actor <= maximum:
		reader.fail("Next creature identity would reuse an existing ID")
	context.restore_actor_sequence(next_actor)
	_restore_beds(context, data, by_id, reader)
	_restore_hand(context, data, by_id, reader)
	for actor in context.actors:
		if actor.action == &"sleeping":
			var bed := context.beds.get_bed(actor.id)
			if actor.is_held or not actor.rest_requested or bed == null or not bed.established or actor.position.distance_to(bed.center(context.grid)) > DungeonBeds.CLAIM_DISTANCE:
				reader.fail("Sleeping creature has no matching established bed")


static func _restore_actor(raw: Variant, context: GameContext, reader: SaveReader) -> CreatureState:
	var data := reader.object(raw, "creature")
	var actor := CreatureState.new()
	actor.id = reader.integer(data.get("id"), "creature identity", 1)
	actor.definition_id = StringName(reader.text(data.get("definition"), "creature definition"))
	var definition := context.registry.get_creature(actor.definition_id)
	if definition == null:
		reader.fail("Unknown creature definition: %s" % actor.definition_id)
	actor.position = reader.position(data.get("position"), context.grid, "creature position")
	actor.heading = reader.number(data.get("heading"), "creature heading")
	actor.phase = reader.number(data.get("phase"), "creature animation phase")
	actor.custom_name = reader.text(data.get("name"), "creature name", KeeperState.MAX_NAME_LENGTH)
	if actor.custom_name != actor.custom_name.strip_edges():
		reader.fail("Creature name has surrounding whitespace")
	for index in actor.custom_name.length():
		if actor.custom_name.unicode_at(index) < 32 or actor.custom_name.unicode_at(index) == 127:
			reader.fail("Creature name contains a control character")
	actor.carried_gold = reader.integer(data.get("gold"), "carried gold")
	actor.energy = reader.number(data.get("energy"), "creature energy", 0, 1)
	actor.satiety = reader.number(data.get("satiety"), "creature satiety", 0, 1)
	actor.is_held = reader.flag(data.get("held"), "creature held")
	actor.rest_requested = reader.flag(data.get("rest_requested"), "rest intent")
	actor.food_requested = reader.flag(data.get("food_requested"), "food intent")
	actor.hunger_intent = reader.flag(data.get("hunger_intent"), "persistent hunger intent")
	var sleeping := reader.flag(data.get("sleeping"), "creature sleeping")
	actor.action = &"held" if actor.is_held else (&"sleeping" if sleeping else &"idle")
	actor.job_label = "Held by the keeper" if actor.is_held else ("Sleeping" if sleeping else "Finding a task after loading")
	if actor.is_held and (sleeping or actor.rest_requested or actor.food_requested or (definition != null and not definition.keeper_pickup_allowed)):
		reader.fail("Held creature has inconsistent control state")
	return actor


static func _restore_beds(context: GameContext, data: Dictionary, by_id: Dictionary[int, CreatureState], reader: SaveReader) -> void:
	for raw in reader.array(data.get("beds"), "beds"):
		var saved := reader.object(raw, "bed")
		var owner := reader.integer(saved.get("owner"), "bed owner", 1)
		var actor: CreatureState = by_id.get(owner)
		var definition := context.registry.get_creature(actor.definition_id) if actor != null and actor in context.actors else null
		var bed := BedState.new()
		bed.owner_id = owner
		bed.anchor = reader.cell(saved.get("anchor"), context.grid, "bed anchor")
		bed.established = reader.flag(saved.get("established"), "bed established")
		if definition == null or &"rest" not in definition.capabilities:
			reader.fail("Bed owner is missing or cannot rest")
			continue
		bed.size = definition.bed_size
		bed.room_tag = definition.rest_room_tag
		var footprint := reader.array(saved.get("size"), "saved bed footprint")
		if footprint.size() != 2:
			reader.fail("Saved bed footprint needs two dimensions")
		elif reader.integer(footprint[0], "bed width", 1, context.grid.width) != bed.size.x or reader.integer(footprint[1], "bed height", 1, context.grid.height) != bed.size.y:
			reader.fail("Saved bed profile does not match current creature content")
		if reader.text(saved.get("room_tag"), "saved bed room tag") != String(bed.room_tag):
			reader.fail("Saved bed profile does not match current creature content")
		if (actor.is_held and not bed.established) or not context.beds.restore_bed(bed):
			reader.fail("Bed is invalid, overlapping or duplicated")


static func _restore_hand(context: GameContext, data: Dictionary, by_id: Dictionary[int, CreatureState], reader: SaveReader) -> void:
	var hand := reader.object(data.get("hand"), "hand")
	var items: Array[KeeperHandItem] = []
	var ids: Dictionary[int, bool] = {}
	var held: Dictionary[int, bool] = {}
	var maximum := 0
	var gold := 0
	for raw in reader.array(hand.get("items"), "hand queue"):
		var saved := reader.object(raw, "hand item")
		var item := KeeperHandItem.new()
		item.id = reader.integer(saved.get("id"), "hand identity", 1)
		item.kind = StringName(reader.text(saved.get("kind"), "hand kind"))
		item.origin = reader.cell(saved.get("origin"), context.grid, "pickup origin")
		item.gold_amount = reader.integer(saved.get("gold"), "hand gold")
		var actor_id := reader.integer(saved.get("actor"), "held creature identity")
		if ids.has(item.id):
			reader.fail("Duplicate hand identity")
		ids[item.id] = true
		maximum = maxi(maximum, item.id)
		if item.kind == &"creature":
			item.actor = by_id.get(actor_id)
			if item.actor == null or item.actor not in context.actors or not item.actor.is_held or held.has(actor_id) or item.gold_amount != 0:
				reader.fail("Missing, duplicated or inconsistent held creature")
			held[actor_id] = true
		elif item.kind == &"gold":
			if item.gold_amount <= 0 or actor_id != 0:
				reader.fail("Invalid held gold batch")
			gold = reader.add(gold, item.gold_amount, "Held gold")
		else:
			reader.fail("Unknown hand item kind")
		items.append(item)
	for actor in context.actors:
		if actor.is_held != held.has(actor.id):
			reader.fail("Held creature is missing from its hand queue")
	if gold != context.economy.keeper_gold:
		reader.fail("Held gold batches do not match the gold ledger")
	var next_id := reader.integer(hand.get("next_id"), "next hand identity", 1)
	if next_id <= maximum:
		reader.fail("Next hand identity would reuse an existing ID")
	var inspected_id := reader.integer(hand.get("inspected"), "inspected creature identity")
	var inspected: CreatureState = by_id.get(inspected_id)
	if inspected_id != 0 and (inspected == null or inspected not in context.actors):
		reader.fail("Inspected creature is missing")
	context.keeper.restore_custody(items, next_id, inspected)
