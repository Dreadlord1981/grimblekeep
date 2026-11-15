extends SceneTree
## Editor import does not compile every unattached script. Check them explicitly.

var _failures: int = 0
var _count: int = 0


func _initialize() -> void:
	_scan("res://")
	print("SCRIPT VALIDATION: %d scripts, %d failures" % [_count, _failures])
	quit(0 if _failures == 0 else 1)


func _scan(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		_failures += 1
		return
	for file in directory.get_files():
		if file.ends_with(".gd"):
			_count += 1
			var script := load(path.path_join(file)) as Script
			if script == null or not script.can_instantiate():
				push_error("Script failed validation: %s" % path.path_join(file))
				_failures += 1
	for child in directory.get_directories():
		if not child.begins_with(".") and child not in ["artifacts", "builds"]:
			_scan(path.path_join(child))
