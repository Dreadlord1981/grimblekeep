class_name DungeonSaveStore
extends RefCounted
## JSON files only. Adjacent verified temp + rollback backup protect the last save.

const MAX_BYTES := 64 * 1024 * 1024


static func write_save(path: String, data: Dictionary, registry: ContentRegistry = null) -> String:
	if path.is_empty():
		return "Save path is empty"
	if registry != null:
		var validation := DungeonSave.restore(data, registry)
		if not validation.error.is_empty():
			return "Cannot save invalid dungeon: %s" % validation.error
	var encoded := JSON.stringify(data, "\t", true, true)
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return "Save exceeds the supported file size"
	var json := JSON.new()
	if json.parse(encoded) != OK or not json.data is Dictionary:
		return "Save could not be encoded as JSON"
	if json.data.get("format") != DungeonSave.FORMAT or not DungeonSave.is_supported_version(json.data.get("version")):
		return "Unsupported save format or version"
	# Validate the exact JSON round trip before replacing any valid file.
	if registry != null:
		var validation := DungeonSave.restore(json.data, registry)
		if not validation.error.is_empty():
			return "Encoded save is invalid: %s" % validation.error
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return "Cannot create save directory: %s" % error_string(error)
	var suffix := ".%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var temporary := absolute + suffix + ".tmp"
	# A stable retained backup is discoverable after process interruption between
	# moving the previous slot aside and promoting the verified temporary file.
	var backup := absolute + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write save: %s" % error_string(FileAccess.get_open_error())
	file.store_string(encoded)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != encoded:
		DirAccess.remove_absolute(temporary)
		return "Save write verification failed"
	var previous := FileAccess.file_exists(absolute)
	if previous:
		# Never rotate a corrupt primary over an intact last-good backup. The
		# application supplies a registry; structural-only callers still preserve
		# the previous slot if its JSON/version envelope is malformed.
		var previous_data := JSON.new()
		var previous_text := FileAccess.get_file_as_string(absolute)
		var valid_previous := previous_data.parse(previous_text) == OK and previous_data.data is Dictionary
		if valid_previous:
			valid_previous = previous_data.data.get("format") == DungeonSave.FORMAT and DungeonSave.is_supported_version(previous_data.data.get("version"))
		if valid_previous and registry != null:
			valid_previous = DungeonSave.restore(previous_data.data, registry).error.is_empty()
		if not valid_previous:
			DirAccess.remove_absolute(temporary)
			return "Existing save is invalid; preserved it and its recovery backup"
		if FileAccess.file_exists(backup):
			error = DirAccess.remove_absolute(backup)
			if error != OK:
				DirAccess.remove_absolute(temporary)
				return "Cannot rotate save backup: %s" % error_string(error)
		error = DirAccess.rename_absolute(absolute, backup)
		if error != OK:
			DirAccess.remove_absolute(temporary)
			return "Cannot protect previous save: %s" % error_string(error)
	error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		var rollback := DirAccess.rename_absolute(backup, absolute) if previous else OK
		DirAccess.remove_absolute(temporary)
		return "Cannot install save: %s%s" % [error_string(error), "; prior save remains at " + backup if rollback != OK else ""]
	return ""


static func read_save(path: String, registry: ContentRegistry) -> Dictionary:
	# Missing primary + intact backup is the recoverable interrupted-rename case.
	# An explicitly corrupt primary still reports its validation error.
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"):
		var recovered := _read_file(path + ".bak", registry)
		recovered["recovered_backup"] = recovered.error.is_empty()
		return recovered
	return _read_file(path, registry)


static func _read_file(path: String, registry: ContentRegistry) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DungeonSave._failure("Cannot open saved dungeon: %s" % error_string(FileAccess.get_open_error()))
	if file.get_length() > MAX_BYTES:
		file.close()
		return DungeonSave._failure("Save exceeds the supported file size")
	var encoded := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error != OK and error != ERR_FILE_EOF:
		return DungeonSave._failure("Cannot read saved dungeon: %s" % error_string(error))
	var json := JSON.new()
	if json.parse(encoded) != OK:
		return DungeonSave._failure("Invalid save JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return DungeonSave._failure("Save root must be an object")
	return DungeonSave.restore(json.data, registry)
