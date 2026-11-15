class_name SaveReader
extends RefCounted
## Typed JSON boundary. Every failure is accumulated before the session is used.

const MAX_INTEGER := 9007199254740991
var error := ""


func fail(message: String) -> void:
	if error.is_empty():
		error = message


func add(total: int, amount: int, label: String) -> int:
	# Reject before addition: malformed large ledgers cannot wrap signed integers
	# or exceed the exact integer range representable by the JSON number format.
	if amount < 0 or total < 0 or amount > MAX_INTEGER - total:
		fail("%s exceeds the supported exact integer range" % label)
		return total
	return total + amount


func object(value: Variant, label: String) -> Dictionary:
	if not value is Dictionary:
		fail("%s must be an object" % label)
		return {}
	return value


func array(value: Variant, label: String) -> Array:
	if not value is Array:
		fail("%s must be an array" % label)
		return []
	return value


func integer(value: Variant, label: String, minimum: int = 0, maximum: int = MAX_INTEGER) -> int:
	if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) < minimum or float(value) > maximum:
		fail("%s must be an integer between %d and %d" % [label, minimum, maximum])
		return minimum
	return int(value)


func number(value: Variant, label: String, minimum: float = -1.0e12, maximum: float = 1.0e12) -> float:
	if not (value is int or value is float) or not is_finite(float(value)) or float(value) < minimum or float(value) > maximum:
		fail("%s must be a finite number in range" % label)
		return minimum
	return float(value)


func text(value: Variant, label: String, maximum: int = 256) -> String:
	if not value is String or value.length() > maximum:
		fail("%s must be a bounded string" % label)
		return ""
	return value


func flag(value: Variant, label: String) -> bool:
	if not value is bool:
		fail("%s must be a boolean" % label)
		return false
	return value


func cell(value: Variant, grid: DungeonGrid, label: String) -> Vector2i:
	var values := array(value, label)
	if values.size() != 2:
		fail("%s must have two coordinates" % label)
		return Vector2i.ZERO
	return Vector2i(integer(values[0], label, 0, grid.width - 1), integer(values[1], label, 0, grid.height - 1))


func position(value: Variant, grid: DungeonGrid, label: String) -> Vector3:
	var values := array(value, label)
	if values.size() != 3:
		fail("%s must have three coordinates" % label)
		return Vector3.ZERO
	return Vector3(number(values[0], label, -1.0, grid.width * DungeonGrid.TILE_SIZE - 1.0), number(values[1], label, -10.0, 10.0), number(values[2], label, -1.0, grid.height * DungeonGrid.TILE_SIZE - 1.0))


func cell_amounts(value: Variant, grid: DungeonGrid, label: String, minimum: int = 0) -> Dictionary[Vector2i, int]:
	var result: Dictionary[Vector2i, int] = {}
	for raw in array(value, label):
		var row := array(raw, label)
		if row.size() != 3:
			fail("%s entry needs x, y, amount" % label)
			continue
		var at := cell([row[0], row[1]], grid, label)
		if result.has(at):
			fail("%s contains a duplicate cell" % label)
		result[at] = integer(row[2], label, minimum)
	return result


static func encode_cell(cell_value: Vector2i) -> Array:
	return [cell_value.x, cell_value.y]


static func encode_position(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func encode_amounts(values: Dictionary) -> Array:
	var rows: Array = []
	var cells := values.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for at: Vector2i in cells:
		rows.append([at.x, at.y, values[at]])
	return rows
