extends SceneTree
## Test-only mechanic proves optional state persists without core dispatch changes.

class ClockFeature extends GameFeature:
	var count := 0
	func persistence_id() -> StringName:
		return &"test.clock"
	func capture_state() -> Dictionary:
		return {"count": count}
	func restore_state(data: Dictionary) -> String:
		var value: Variant = data.get("count")
		if not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0.0:
			return "Invalid test clock"
		count = int(value)
		return ""

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var a := ClockFeature.new()
	a.count = 42
	var original: Array[GameFeature] = [a]
	var captured := FeaturePersistence.capture(original)
	_check(captured.error.is_empty() and captured.state["test.clock"].count == 42, "Extension captures its state through a stable ID")
	var b := ClockFeature.new()
	var restored: Array[GameFeature] = [b]
	_check(FeaturePersistence.restore(restored, JSON.parse_string(JSON.stringify(captured.state))).is_empty() and b.count == 42, "Test-only mechanic restores JSON state without core species switches")
	_check(not FeaturePersistence.restore(restored, {}).is_empty(), "Missing required feature payload fails explicitly")
	_check(not FeaturePersistence.restore(restored, {"test.clock": {"count": -1}}).is_empty() and b.count == 42, "Invalid extension state is rejected before committing its own state")
	_check(not FeaturePersistence.restore(restored, {"test.clock": {"count": 4}, "missing.module": {}}).is_empty(), "Unavailable stateful extension fails instead of silently losing state")
	var duplicate: Array[GameFeature] = [a, b]
	_check(not FeaturePersistence.capture(duplicate).error.is_empty() and not FeaturePersistence.restore(duplicate, captured.state).is_empty(), "Duplicate stable feature keys cannot overwrite each other")
	var stateless := GameFeature.new()
	var no_state: Array[GameFeature] = [stateless]
	_check(FeaturePersistence.capture(no_state).state.is_empty() and FeaturePersistence.restore(no_state, {}).is_empty(), "Stateless mechanics require no speculative serialized internals")
	var resident: GameFeature = preload("res://content/features/resident_feature.gd").new()
	_check(resident.restore_state({"arrival_in": 1.4}).is_empty() and is_equal_approx(resident.capture_state().arrival_in, 1.4), "Resident arrival poll progress persists")
	for invalid in [-0.1, 3.0, "soon", null, INF, NAN]:
		_check(not resident.restore_state({"arrival_in": invalid}).is_empty(), "Malformed arrival clock is rejected: %s" % str(invalid))
	a.free()
	b.free()
	stateless.free()
	resident.free()
	for failure in _failures:
		push_error(failure)
	print("FEATURE SAVE: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)
