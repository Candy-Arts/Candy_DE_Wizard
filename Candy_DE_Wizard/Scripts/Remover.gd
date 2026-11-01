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

#^ Files Godot generates (never the developer's work):
const GENERATED_EXTENSIONS := ["uid", "import"]

#^ Set before plan() or remove():
var record: Dictionary = {}					#/ The install record

#^ What remove() will do (plan() fills them in), then did:
var autoloads_removed: PackedStringArray = []
var autoloads_restored: Dictionary = {}		#/ Autoload name -> the value put back
var autoloads_kept: PackedStringArray = []	#/ Changed since the install: left as they are
var actions_removed: PackedStringArray = []
var actions_known := true					#/ false: the record doesn't list the actions it added
var trashed := false						#/ The folder went to the trash, rather than deleted

#^ Setting key -> its new value (null removes the setting):
var _settings := {}


#* Plans the project settings changes, without making them:
func plan() -> void:
	autoloads_removed.clear()
	autoloads_restored.clear()
	autoloads_kept.clear()
	actions_removed.clear()
	_settings.clear()

	var changes: Array = []
	if record.has("autoloads"):
		changes = record["autoloads"]
	else:
		changes = _autoloads_into_folder()
	for change in changes:
		var autoload_name := String(change.get("name", ""))
		var key := "autoload/" + autoload_name
		if not ProjectSettings.has_setting(key):
			continue
		if String(ProjectSettings.get_setting(key)) != String(change.get("value", "")):
			autoloads_kept.append(autoload_name)
			continue
		var previous := String(change.get("previous", ""))
		if previous == "":
			_settings[key] = null
			autoloads_removed.append(autoload_name)
		else:
			_settings[key] = previous
			autoloads_restored[autoload_name] = previous

	actions_known = record.has("input_actions")
	for action in record.get("input_actions", []):
		var key := "input/" + String(action)
		if ProjectSettings.has_setting(key):
			_settings[key] = null
			actions_removed.append(action)


#* Removes Candy DE. Returns an error message, or "":
func remove(tree: SceneTree) -> String:
	if Utils.is_dev_record(record):
		return "This is Candy DE's development project: Candy Wizard never removes Candy DE from it."
	plan()

	progress.emit(0.1, "Removing the Candy_DE folder…")
	await tree.process_frame
	var folder_error := _remove_folder()
	if folder_error != "":
		return folder_error

	progress.emit(0.5, "Letting Godot scan the project…")
	await Utils.scan_filesystem(tree)

	progress.emit(0.9, "Cleaning up the project settings…")
	for key in _settings:
		ProjectSettings.set_setting(key, _settings[key])
	var save_error := ProjectSettings.save()
	if save_error != OK:
		return "Candy DE's files were removed, but the project settings couldn't be saved (%s). Remove its autoloads and input actions by hand, in Project Settings." % error_string(save_error)
	progress.emit(1.0, "Done.")
	return ""


func _remove_folder() -> String:
	if OS.move_to_trash(ProjectSettings.globalize_path(Utils.CANDY_DE_FOLDER)) == OK:
		trashed = true
		return ""
	#? No trash on some systems or drives: delete instead.
	if Utils.remove_folder(Utils.CANDY_DE_FOLDER):
		return ""
	return "Some files in res://Candy_DE couldn't be removed (is one of them open in another program?). Delete what's left of the folder by hand. The project settings were left as they are."


#* For records that don't list autoloads - every autoload pointing into Candy_DE:
func _autoloads_into_folder() -> Array:
	var found := []
	for property in ProjectSettings.get_property_list():
		var key := String(property["name"])
		if not key.begins_with("autoload/"):
			continue
		var value := String(ProjectSettings.get_setting(key))
		if value.trim_prefix("*").begins_with(Utils.CANDY_DE_FOLDER + "/"):
			found.append({"name": key.trim_prefix("autoload/"), "value": value, "previous": ""})
	return found


#==============================================================================
#  BEFORE REMOVING
#==============================================================================

#* The developer's files in Candy_DE, removed with it - {"added" = not installed, "edited" = changed since}:
#? Paths as the record writes them ("Candy_DE/...").
static func developer_files(install_record: Dictionary) -> Dictionary:
	var installed: Dictionary = install_record.get("files", {})
	var present: PackedStringArray = []
	_list_files(Utils.CANDY_DE_FOLDER, Utils.PACKAGE_NAME, present)
	var added: PackedStringArray = []
	var edited: PackedStringArray = []
	#? Candy Wizard's own folder (the record, the voice layout, the updates' copies).
	var wizard_folder := Utils.RECORD_PATH.get_base_dir() + "/"
	for path in present:
		if path.get_extension() in GENERATED_EXTENSIONS or ("res://" + path).begins_with(wizard_folder):
			continue
		if not installed.has(path):
			added.append(path)
		elif Utils.content_hash(path, FileAccess.get_file_as_bytes("res://" + path)) != String(installed[path].get("sha256", "")):
			edited.append(path)
	return {"added": added, "edited": edited}


#* Open scenes and scripts from Candy_DE. Saving one afterwards would write it back:
static func open_files() -> PackedStringArray:
	var found: PackedStringArray = []
	var prefix := Utils.CANDY_DE_FOLDER + "/"
	for scene_path in EditorInterface.get_open_scenes():
		if scene_path.begins_with(prefix):
			found.append(scene_path)
	for script in EditorInterface.get_script_editor().get_open_scripts():
		if script.resource_path.begins_with(prefix):
			found.append(script.resource_path)
	return found


static func _list_files(folder: String, relative_folder: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_list_files(folder.path_join(entry), relative_folder + "/" + entry, found)
		else:
			found.append(relative_folder + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
