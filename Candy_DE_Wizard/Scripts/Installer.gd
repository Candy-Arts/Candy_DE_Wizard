#!###########################################################################################
#!																							#
#!       THIS SCRIPT MAY CONTAIN CODE THAT IS THE INTELLECTUAL PROPERTY OF CANDY ARTS       #
#!                             Copyright © 2025-2026 Candy Arts                             #
#!																							#
#!    Such code may only be used in compliance with the appropriate Candy Arts licenses.    #
#!                Any unauthorized use may constitute copyright infringement.               #
#!																							#
#!###########################################################################################


@tool
extends RefCounted


signal progress(fraction: float, message: String)

const Utils = preload("Wizard_Utils.gd")
const VoiceFiles = preload("Voice_Files.gd")

#^ Set before install():
var package = null							#/ Package.gd, opened and verified
var answers: Dictionary = {}				#/ Question id -> value
var source_text := ""						#/ Where the release came from, for the record
var wizard_version := ""
var notes_flow := Utils.NOTES_INSTALL		#/ The post notes kept: the upgrade's are an update's

#^ What install() did, for the wizard's last page:
var autoloads_added: PackedStringArray = []
var autoloads_replaced: PackedStringArray = []
var autoloads_adopted: PackedStringArray = []	#/ Already set as the release sets them: the install's from now on
var actions_added: PackedStringArray = []
var actions_kept: PackedStringArray = []	#/ Already in the project: left untouched

#^ The autoloads to set - [{name, value, previous}] (previous "" when new, or already set so):
var autoload_changes: Array = []

#^ Share of the progress bar each step takes:
const FILES_SHARE := 0.8
#^ Files written between two editor frames:
const FILES_PER_FRAME := 20


#* Installs Candy DE, returning an error message or "":
func install(tree: SceneTree) -> String:
	if Utils.candy_de_folder_exists():
		return "A Candy_DE folder already exists in this project. Nothing was installed."

	_plan_project_settings()
	var error := await _write_files(tree)
	if error != "":
		progress.emit(0.0, "Removing the partly installed files…")
		Utils.remove_folder(Utils.CANDY_DE_FOLDER)
		return error

	progress.emit(FILES_SHARE, "Letting Godot scan the new files…")
	await Utils.scan_filesystem(tree)

	progress.emit(0.9, "Setting up the project…")
	_apply_project_settings()
	var save_error := ProjectSettings.save()
	if save_error != OK:
		return "Candy DE's files were installed, but the project settings couldn't be saved (%s). Add the autoloads and input actions by hand, in Project Settings." % error_string(save_error)
	progress.emit(1.0, "Done.")
	return ""


#* Writes every file of the release, then the install record:
func _write_files(tree: SceneTree) -> String:
	var file_list: Dictionary = package.files()
	var paths := file_list.keys()
	paths.sort()
	var edits := _edits_by_file()
	var record_files := {}
	var count := 0
	for path in paths:
		var bytes: PackedByteArray = package.read(path)
		if edits.has(path):
			var text := bytes.get_string_from_utf8()
			for edit in edits[path]:
				var edited := Utils.set_variable(text, edit["variable"], edit["value"])
				if edited == "":
					return "Couldn't write your answer into %s: it has no '%s' setting." % [path, edit["variable"]]
				text = edited
			bytes = text.to_utf8_buffer()

		#Ł Folders holding files (the Folders tool makes the empty media folders):
		var target := "res://" + String(path)
		var dir_error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if dir_error != OK:
			return "Couldn't create the folder %s (%s)." % [target.get_base_dir(), error_string(dir_error)]
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return "Couldn't write %s (%s)." % [target, error_string(FileAccess.get_open_error())]
		file.store_buffer(bytes)
		var write_error := file.get_error()
		file.close()
		if write_error != OK:
			return "Couldn't write %s (%s)." % [target, error_string(write_error)]

		#? Hash of what was written, answers included: updates find the developer's edits by it.
		record_files[path] = {
			"category": String(file_list[path].get("category", "engine")),
			"sha256": Utils.content_hash(path, bytes),
		}
		count += 1
		if count % FILES_PER_FRAME == 0:
			progress.emit(FILES_SHARE * count / paths.size(), "Installing files… %d / %d" % [count, paths.size()])
			await tree.process_frame

	var record_error := _write_record(record_files)
	if record_error != "":
		return record_error
	var notes_error := Utils.save_post_notes(package.wizard_notes("post", notes_flow))
	if notes_error != "":
		return notes_error
	#? Record the voice layout, so the Folders tool can move the voice files when it changes.
	var layout := VoiceFiles.current_layout()
	if not layout.is_empty():
		return VoiceFiles.record_layout(layout)
	return ""


#* The wizard's answers, grouped by the file they go into:
func _edits_by_file() -> Dictionary:
	var edits := {}
	for question in package.manifest.get("questions", []):
		var id := String(question.get("id", ""))
		if not answers.has(id):
			continue
		var file := String(question.get("file", ""))
		if not edits.has(file):
			edits[file] = []
		edits[file].append({"variable": String(question.get("variable", "")), "value": answers[id]})
	return edits


func _write_record(record_files: Dictionary) -> String:
	var record := {
		"format": Utils.RECORD_FORMAT,
		"package": Utils.PACKAGE_NAME,
		"version": package.version(),
		"installed": Time.get_datetime_string_from_system(false, true),
		"wizard_version": wizard_version,
		"source": source_text,
		"answers": answers,
		"autoloads": autoload_changes,
		"input_actions": actions_added,
		"files": record_files,
	}
	DirAccess.make_dir_recursive_absolute(Utils.RECORD_PATH.get_base_dir())
	var file := FileAccess.open(Utils.RECORD_PATH, FileAccess.WRITE)
	if file == null:
		return "Couldn't write the install record %s (%s)." % [Utils.RECORD_PATH, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return ""


#* Plans the autoloads and input actions to add or replace, for the record:
func _plan_project_settings() -> void:
	for entry in package.manifest.get("autoloads", []):
		var autoload_name := String(entry.get("name", ""))
		#? "*" makes it a singleton, reachable by name from any script.
		var value := "*" + String(entry.get("path", ""))
		var key := "autoload/" + autoload_name
		var previous := ""
		if ProjectSettings.has_setting(key):
			previous = String(ProjectSettings.get_setting(key))
			if previous == value:
				#? Already there (Candy DE removed by hand?): recorded as the install's, so a removal takes it out.
				previous = ""
				autoloads_adopted.append(autoload_name)
			else:
				autoloads_replaced.append(autoload_name)
		else:
			autoloads_added.append(autoload_name)
		autoload_changes.append({"name": autoload_name, "value": value, "previous": previous})

	#? An action the project already has is never changed: its keys are the developer's.
	for action in package.manifest.get("input_actions", {}):
		if ProjectSettings.has_setting("input/" + String(action)):
			actions_kept.append(action)
		else:
			actions_added.append(action)


#* Sets autoloads directly, not with add_autoload_singleton():
#? add_autoload_singleton() compiles each script, and Candy DE's scripts print errors when compiled before the candy_de autoload exists.
func _apply_project_settings() -> void:
	for change in autoload_changes:
		ProjectSettings.set_setting("autoload/" + String(change["name"]), change["value"])

	var actions: Dictionary = package.manifest.get("input_actions", {})
	for action in actions_added:
		var events := []
		for event_data in actions[action].get("events", []):
			var event := Utils.event_from_data(event_data)
			if event != null:
				events.append(event)
		ProjectSettings.set_setting("input/" + String(action), {"deadzone": float(actions[action].get("deadzone", 0.5)), "events": events})
