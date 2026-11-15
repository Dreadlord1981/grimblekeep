class_name SessionPresentation
extends RefCounted
## Optional saved camera; transient tools and mouse gestures always start fresh.


static func capture(controller: KeeperController) -> Dictionary:
	return {"focus": [controller.focus.x, controller.focus.y, controller.focus.z],
		"yaw": controller.yaw, "pitch": controller.pitch, "distance": controller.distance}


static func validation_error(data: Dictionary, grid: DungeonGrid) -> String:
	if data.is_empty():
		return ""
	var focus: Variant = data.get("focus")
	if not focus is Array or focus.size() != 3:
		return "Invalid saved camera focus"
	for value in focus:
		if not _number(value):
			return "Invalid saved camera focus"
	if absf(float(focus[0])) > grid.width * DungeonGrid.TILE_SIZE or absf(float(focus[2])) > grid.height * DungeonGrid.TILE_SIZE or not is_zero_approx(float(focus[1])):
		return "Saved camera focus is outside the dungeon"
	for key in ["yaw", "pitch", "distance"]:
		if not _number(data.get(key)):
			return "Invalid saved camera %s" % key
	if float(data.pitch) < 0.30 or float(data.pitch) > 1.30 or float(data.distance) < KeeperController.MIN_DISTANCE or float(data.distance) > KeeperController.MAX_DISTANCE:
		return "Saved camera is outside supported limits"
	return ""


static func apply(controller: KeeperController, data: Dictionary) -> void:
	if data.is_empty():
		return
	controller.focus = Vector3(data.focus[0], data.focus[1], data.focus[2])
	controller.yaw = float(data.yaw)
	controller.pitch = float(data.pitch)
	controller.distance = float(data.distance)
	controller.call("_update_camera")


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
