class_name FeaturePersistence
extends RefCounted
## Feature-local clocks/state extend saves without adding species switches.


static func capture(features: Array[GameFeature]) -> Dictionary:
	var state := {}
	for feature in features:
		var id := String(feature.persistence_id())
		var data := feature.capture_state()
		if id.is_empty():
			if not data.is_empty():
				return {"error": "A stateful feature needs a stable persistence ID"}
			continue
		if state.has(id):
			return {"error": "Duplicate feature persistence ID: %s" % id}
		state[id] = data
	return {"error": "", "state": state}


static func restore(features: Array[GameFeature], state: Dictionary) -> String:
	var expected := {}
	for feature in features:
		var id := String(feature.persistence_id())
		if id.is_empty():
			continue
		if expected.has(id):
			return "Duplicate feature persistence ID: %s" % id
		expected[id] = true
		if not state.has(id) or not state[id] is Dictionary:
			return "Missing feature state: %s" % id
		var error := feature.restore_state(state[id])
		if not error.is_empty():
			return "%s: %s" % [id, error]
	for id in state:
		if not expected.has(id):
			return "Save requires unavailable feature: %s" % id
	return ""
