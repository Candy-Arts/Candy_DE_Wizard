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
const UpdateSteps = preload("Update_Steps.gd")

#^ How each file is sorted, for the review:
const ADDED := "added"							#/ New in the release
const UPDATED := "updated"						#/ Unchanged by the developer: replaced
const OVERWRITTEN := "overwritten"				#/ Changed by the developer: replaced (theirs in Previous)
const EXISTING := "existing"					#/ The developer's own file where the release adds one: replaced (theirs in Previous)
const DELETED := "deleted"						#/ Deleted by the developer: a choice
const TEMPLATE_CHANGED := "template_changed"	#/ A template the release changed: kept, the new version saved in New
const REMOVED := "removed"						#/ Dropped by the release: removed (kept in Previous)
const LEFT := "left"							#/ Dropped by the release, changed by the developer: left

#^ The choices. The first is the default:
const LEAVE_OUT := "leave"						#/ DELETED: stays deleted
const RESTORE := "restore"						#/ DELETED: the release's version is added back

#^ Files Godot keeps next to a file, moved with it:
const SIBLING_EXTENSIONS := ["uid", "import"]

#^ Set before plan():
var package = null						#/ Package.gd, opened and verified
var record: Dictionary = {}				#/ The install record
var new_answers: Dictionary = {}		#/ Answers to the questions the installed version didn't ask
var choices: Dictionary = {}			#/ Path -> choice, for the files needing one
var source_text := ""					#/ Where the release came from, for the record
var wizard_version := ""

#^ The plan (plan() fills it in):
var problem := ""						#/ Why the update can't be made at all
var files: Array = []					#/ [{path, status, choice}]: the files worth listing
var unchanged := 0						#/ Files already as the release has them
var step_results: Array = []			#/ [{step, result, reason, note}], in order
var to_do: Array = []					#/ [{title (BBCode), text}]: what's left to do by hand
var settings: Array = []				#/ [{icon, text (BBCode), warning}]: project settings changes
var folder := ""						#/ Where this update keeps its copies (res://...)

#^ What update() did:
var report_path := ""

#^ Plan internals:
var _moves := {}						#/ Path a file moves to -> where it is now
var _moved_away := {}					#/ Paths files move away from
var _record_files := {}					#/ The record's files, with the moves applied
var _final := {}						#/ Path -> the content it's written with
var _removals: PackedStringArray = []	#/ Files removed (into Previous)
var _new_copies := {}					#/ Path -> the release's version of a template, saved in New
var _new_record := {}					#/ The record's files after the update
var _wizard_made := {}					#/ Paths left as Candy Wizard writes them (not the developer's)
var _answers := {}						#/ Every answer: the record's, then the new ones
var _autoloads: Array = []				#/ The record's autoloads after the update
var _input_actions: PackedStringArray = []
var _settings := {}						#/ Setting key -> value (null removes it)


#==============================================================================
#  PLAN
#==============================================================================

#* Works out what the update does, without changing anything. Sets problem if it can't:
func plan() -> void:
	_reset()
	problem = _check()
	if problem != "":
		return
	var old_version := String(record.get("version", ""))
	var new_version: String = package.version()
	folder = _free_folder(new_version)
	var steps := UpdateSteps.between(package.manifest.get("updates", []), old_version, new_version)
	_record_files = Utils.safe_record_files(record.get("files", {}), Utils.PACKAGE_NAME + "/").duplicate(true)
	_answers = Dictionary(record.get("answers", {})).duplicate()
	_answers.merge(new_answers, true)
	_input_actions = PackedStringArray(record.get("input_actions", []))

	#? Moves first: the files are then compared where the release has them.
	var move_results := {}
	for index in steps.size():
		if steps[index]["action"] == "move":
			move_results[index] = _plan_move(steps[index])
	_plan_files()
	for index in steps.size():
		var step: Dictionary = steps[index]
		var outcome := {}
		match String(step["action"]):
			"move":
				outcome = move_results[index]
			"rename_input_action":
				outcome = _plan_input_rename(step)
			"manual":
				outcome = {"result": UpdateSteps.MANUAL}
				to_do.append({"title": UpdateSteps.describe(step, _code), "text": String(step["text"])})
			_:
				outcome = _plan_text_step(step)
		if outcome["result"] == UpdateSteps.FAILED:
			to_do.append({"title": UpdateSteps.describe(step, _code), "text": UpdateSteps.manual_text(step, String(outcome.get("reason", "")))})
		outcome["step"] = step
		step_results.append(outcome)
	_plan_new_answers()
	_drop_unchanged_writes()
	_plan_record_files()
	_plan_autoloads()
	_plan_input_actions()


func _reset() -> void:
	problem = ""
	files.clear()
	unchanged = 0
	step_results.clear()
	to_do.clear()
	settings.clear()
	_moves.clear()
	_moved_away.clear()
	_record_files.clear()
	_final.clear()
	_removals.clear()
	_new_copies.clear()
	_new_record.clear()
	_wizard_made.clear()
	_answers.clear()
	_autoloads.clear()
	_input_actions.clear()
	_settings.clear()


func _check() -> String:
	if record.is_empty():
		return "Candy DE wasn't installed by Candy Wizard in this project (it has no install record), so it can't be updated."
	if Utils.is_dev_record(record):
		return "This is Candy DE's development project: Candy Wizard never updates Candy DE in it."
	var installed := String(record.get("version", ""))
	if Utils.compare_versions(package.version(), installed) <= 0:
		return "Candy DE %s is installed, and this release is %s: only a newer release can update it." % [installed, package.version()]
	return UpdateSteps.check(package.manifest.get("updates", []))


#* A folder for this update's copies that doesn't exist yet:
func _free_folder(version: String) -> String:
	var base := Utils.UPDATES_FOLDER.path_join(version)
	var candidate := base
	var number := 2
	while DirAccess.dir_exists_absolute(candidate):
		candidate = "%s (%d)" % [base, number]
		number += 1
	return candidate


#==============================================================================
#  FILES
#==============================================================================

#* Where a file is on disk now, moves counted ("Candy_DE/..."), or "" if it isn't there:
func _disk_path(path: String) -> String:
	if _moves.has(path):
		return _moves[path]
	if _moved_away.has(path):
		return ""
	if FileAccess.file_exists("res://" + path):
		return path
	return ""


#* A file's content as the update leaves it so far:
#? Missing gives [] too: see _exists_after().
func _current_bytes(path: String) -> PackedByteArray:
	if _final.has(path):
		return _final[path]
	var disk_path := _disk_path(path)
	if disk_path == "":
		return PackedByteArray()
	return FileAccess.get_file_as_bytes("res://" + disk_path)


func _exists_after(path: String) -> bool:
	return _final.has(path) or (_disk_path(path) != "" and not path in _removals)


#* The release's version of a file, with the answers that go into it:
func _release_bytes(path: String) -> PackedByteArray:
	var bytes: PackedByteArray = package.read(path)
	var edits := []
	for question in package.manifest.get("questions", []):
		if String(question.get("file", "")) == path and _answers.has(String(question.get("id", ""))):
			edits.append(question)
	if edits.is_empty():
		return bytes
	var text := bytes.get_string_from_utf8()
	for question in edits:
		var edited := Utils.set_variable(text, String(question.get("variable", "")), _answers[String(question["id"])])
		if edited != "":
			text = edited
	return text.to_utf8_buffer()


func _choice(path: String, allowed: Array) -> String:
	var chosen := String(choices.get(path, ""))
	if chosen in allowed:
		return chosen
	return allowed[0]


#* Sorts every file of the release and of the record:
func _plan_files() -> void:
	var new_files: Dictionary = package.files()
	var paths := {}
	for path in new_files:
		paths[path] = true
	for path in _record_files:
		paths[path] = true
	var sorted := paths.keys()
	sorted.sort()
	for path in sorted:
		var disk_path := _disk_path(path)
		var disk_hash := ""
		if disk_path != "":
			disk_hash = Utils.content_hash(path, FileAccess.get_file_as_bytes("res://" + disk_path))
		var recorded := ""
		if _record_files.has(path):
			recorded = String(_record_files[path].get("sha256", ""))
		if new_files.has(path):
			_plan_release_file(path, String(new_files[path].get("category", "engine")), disk_path != "", disk_hash, recorded)
		else:
			_plan_gone_file(path, disk_path != "", disk_hash, recorded)


#* A file the new release has:
func _plan_release_file(path: String, category: String, exists: bool, disk_hash: String, recorded: String) -> void:
	var in_record := _record_files.has(path)
	var release_bytes := _release_bytes(path)
	var release_hash := Utils.content_hash(path, release_bytes)
	_new_record[path] = {"category": category, "sha256": release_hash}

	if not exists:
		if not in_record:
			files.append({"path": path, "status": ADDED})
			_final[path] = release_bytes
			_wizard_made[path] = true
		elif bool(_record_files[path].get("left_out", false)):
			#? Left out by an earlier update: still left out.
			_new_record[path]["left_out"] = true
		else:
			var choice := _choice(path, [LEAVE_OUT, RESTORE])
			files.append({"path": path, "status": DELETED, "choice": choice})
			if choice == RESTORE:
				_final[path] = release_bytes
				_wizard_made[path] = true
			else:
				_new_record[path]["left_out"] = true
		return

	if disk_hash == release_hash:
		unchanged += 1
		_wizard_made[path] = true
		return

	if category == "template":
		#? The record keeps the release's hash, so the next update sees whether it changed again.
		if not in_record or release_hash != recorded:
			files.append({"path": path, "status": TEMPLATE_CHANGED})
			_new_copies[path] = release_bytes
		else:
			unchanged += 1
		return

	#? Replaced even if only the developer changed it: their changes could break the release.
	var status := UPDATED
	if not in_record:
		status = EXISTING
	elif disk_hash != recorded:
		status = OVERWRITTEN
	files.append({"path": path, "status": status})
	_final[path] = release_bytes
	_wizard_made[path] = true


#* A file the install record has, but the new release doesn't:
func _plan_gone_file(path: String, exists: bool, disk_hash: String, recorded: String) -> void:
	if not exists:
		return
	var category := String(_record_files[path].get("category", "engine"))
	if category != "template" and disk_hash == recorded:
		files.append({"path": path, "status": REMOVED})
		_removals.append(path)
	else:
		#? Changed by the developer (or theirs): it stays, and isn't Candy DE's any more.
		files.append({"path": path, "status": LEFT})


#* A move step, planned before files are compared. A folder moves file by file:
func _plan_move(step: Dictionary) -> Dictionary:
	var from := String(step["from"]).trim_suffix("/")
	var to := String(step["to"]).trim_suffix("/")
	var pairs := []
	if _disk_path(from) != "":
		pairs.append([from, to])
	else:
		for path in _files_under(from):
			pairs.append([path, to + path.substr(from.length())])
	if pairs.is_empty():
		#? Already moved, or the project never had it.
		return {"result": UpdateSteps.ALREADY}
	var blocked: PackedStringArray = []
	for pair in pairs:
		if _disk_path(pair[1]) != "":
			blocked.append(pair[1])
			continue
		var actual := _disk_path(pair[0])
		_moves.erase(pair[0])
		_moved_away[pair[0]] = true
		_moved_away.erase(pair[1])
		_moves[pair[1]] = actual
		if _record_files.has(pair[0]):
			_record_files[pair[1]] = _record_files[pair[0]]
			_record_files.erase(pair[0])
	if not blocked.is_empty():
		return {"result": UpdateSteps.FAILED, "reason": "there's already a file at " + ", ".join(blocked)}
	return {"result": UpdateSteps.DONE}


#* The files under a folder, as they are once the planned moves are made:
func _files_under(folder_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	_list_files("res://" + folder_path, folder_path, found)
	var result: PackedStringArray = []
	for path in found:
		if path.get_extension() in SIBLING_EXTENSIONS or _moved_away.has(path):
			continue
		result.append(path)
	for path in _moves:
		if String(path).begins_with(folder_path + "/"):
			result.append(path)
	return result


static func _list_files(folder_path: String, relative_folder: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(folder_path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_list_files(folder_path.path_join(entry), relative_folder + "/" + entry, found)
		else:
			found.append(relative_folder + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()


func _plan_text_step(step: Dictionary) -> Dictionary:
	var path := String(step["file"])
	if not _exists_after(path):
		return {"result": UpdateSteps.FAILED, "reason": "%s isn't in the project" % path}
	var outcome := UpdateSteps.apply_text(step, _current_bytes(path).get_string_from_utf8())
	if outcome["result"] == UpdateSteps.DONE:
		_final[path] = String(outcome["text"]).to_utf8_buffer()
	return outcome


#* Writes the new questions' answers into files the update doesn't replace:
func _plan_new_answers() -> void:
	for question in package.manifest.get("questions", []):
		var id := String(question.get("id", ""))
		if not new_answers.has(id):
			continue
		var path := String(question.get("file", ""))
		var variable := String(question.get("variable", ""))
		var text := _current_bytes(path).get_string_from_utf8()
		var edited := ""
		if _exists_after(path):
			edited = Utils.set_variable(text, variable, new_answers[id])
		if edited == "":
			to_do.append({"title": "Your answer to \"%s\"" % String(question.get("title", id)).replace("[", "[lb]"), "text": "Set %s to %s in %s: the update couldn't find its line." % [variable, UpdateSteps.value_text(new_answers[id]), path]})
		elif edited != text:
			_final[path] = edited.to_utf8_buffer()


#* Drops planned writes that wouldn't change a file:
func _drop_unchanged_writes() -> void:
	for path in _final.keys():
		var disk_path := _disk_path(path)
		if disk_path != "" and FileAccess.get_file_as_bytes("res://" + disk_path) == _final[path]:
			_final.erase(path)


#* The record's hashes:
#? As Candy Wizard leaves a file it made (so the next update knows it's untouched), or the release's for the developer's files (so it knows they differ).
func _plan_record_files() -> void:
	for path in _new_record:
		if _wizard_made.has(path) and _exists_after(path):
			_new_record[path]["sha256"] = Utils.content_hash(path, _current_bytes(path))


#==============================================================================
#  PROJECT SETTINGS
#==============================================================================

#* A setting's value once the planned changes are made, or null if it doesn't exist:
func _setting_after(key: String) -> Variant:
	if _settings.has(key):
		return _settings[key]
	if ProjectSettings.has_setting(key):
		return ProjectSettings.get_setting(key)
	return null


#* An autoload's value once the planned changes are made, or "" if the project doesn't have it:
func _autoload_after(key: String) -> String:
	var value = _setting_after(key)
	if value == null:
		return ""
	return str(value)


func _plan_input_rename(step: Dictionary) -> Dictionary:
	var from_key := "input/" + String(step["from"])
	var to_key := "input/" + String(step["to"])
	var has_from := _setting_after(from_key) != null
	var has_to := _setting_after(to_key) != null
	if not has_from:
		return {"result": UpdateSteps.ALREADY}
	if has_to:
		return {"result": UpdateSteps.FAILED, "reason": "the project has both"}
	_settings[to_key] = _setting_after(from_key)
	_settings[from_key] = null
	var index := _input_actions.find(String(step["from"]))
	if index != -1:
		_input_actions[index] = String(step["to"])
	return {"result": UpdateSteps.DONE}


#* Plans the release's autoloads. One the developer changed since is left as they set it:
func _plan_autoloads() -> void:
	var recorded := {}
	for entry in record.get("autoloads", []):
		recorded[String(entry.get("name", ""))] = entry
	var wanted := {}
	for entry in package.manifest.get("autoloads", []):
		wanted[String(entry.get("name", ""))] = "*" + String(entry.get("path", ""))
	if not record.has("autoloads"):
		#? A record that doesn't list them: the ones pointing into Candy_DE are its own.
		for autoload_name in wanted:
			var current := _autoload_after("autoload/" + autoload_name)
			if current.trim_prefix("*").begins_with(Utils.CANDY_DE_FOLDER + "/"):
				recorded[autoload_name] = {"name": autoload_name, "value": current, "previous": ""}

	for autoload_name in wanted:
		var key: String = "autoload/" + autoload_name
		var value: String = wanted[autoload_name]
		var current := _autoload_after(key)
		if recorded.has(autoload_name):
			var entry: Dictionary = recorded[autoload_name].duplicate()
			if current == value:
				#? Set already (by the developer, when the record has another value).
				entry["value"] = value
				_autoloads.append(entry)
			elif current == String(entry.get("value", "")):
				_settings[key] = value
				entry["value"] = value
				_autoloads.append(entry)
				_add_setting("Script", "Autoload %s now points to %s" % [_code(autoload_name), _code(value.trim_prefix("*"))], false)
			else:
				var yours := "removed it"
				if current != "":
					yours = "set it to " + current.trim_prefix("*")
				_add_setting("StatusWarning", "Autoload %s  left as you set it" % _code(autoload_name), true)
				to_do.append({"title": "Autoload %s" % _code(autoload_name), "text": "You %s. Candy DE %s expects %s, in Project Settings → Globals → Autoload." % [yours, package.version(), value.trim_prefix("*")]})
		elif current != value:
			_settings[key] = value
			_autoloads.append({"name": autoload_name, "value": value, "previous": current})
			if current == "":
				_add_setting("Script", "Autoload %s added" % _code(autoload_name), false)
			else:
				_add_setting("StatusWarning", "Autoload %s  replaces the project's own, %s" % [_code(autoload_name), _code(current.trim_prefix("*"))], true)
		else:
			#? Set as the release sets it, but not by the install: recorded, so a removal takes it out.
			_autoloads.append({"name": autoload_name, "value": value, "previous": ""})
			_add_setting("StatusWarning", "Autoload %s  is already in the project: it's recorded as Candy DE's, and removed with it" % _code(autoload_name), true)

	for autoload_name in recorded:
		if wanted.has(autoload_name):
			continue
		var entry: Dictionary = recorded[autoload_name]
		var key: String = "autoload/" + autoload_name
		#? One the developer removed or changed since is left as they have it.
		var current := _autoload_after(key)
		if current == "" or current != String(entry.get("value", "")):
			continue
		var previous := String(entry.get("previous", ""))
		if previous == "":
			_settings[key] = null
			_add_setting("Script", "Autoload %s removed: Candy DE doesn't use it any more" % _code(autoload_name), false)
		else:
			_settings[key] = previous
			_add_setting("Script", "Autoload %s set back to %s" % [_code(autoload_name), _code(previous.trim_prefix("*"))], false)


#* Adds the release's input actions the project lacks. Existing ones are never changed:
func _plan_input_actions() -> void:
	var actions: Dictionary = package.manifest.get("input_actions", {})
	for action in actions:
		var key := "input/" + String(action)
		if _setting_after(key) != null:
			continue
		var events := []
		for event_data in actions[action].get("events", []):
			var event := Utils.event_from_data(event_data)
			if event != null:
				events.append(event)
		_settings[key] = {"deadzone": float(actions[action].get("deadzone", 0.5)), "events": events}
		_input_actions.append(String(action))
		_add_setting("InputEventKey", "Input action %s added" % _code(action), false)


func _add_setting(icon_name: String, bbcode: String, warning: bool) -> void:
	settings.append({"icon": icon_name, "text": bbcode, "warning": warning})


static func _code(text: String) -> String:
	return "[code]%s[/code]" % text.replace("[", "[lb]")


#==============================================================================
#  UPDATE
#==============================================================================

#* Open scenes and scripts the update would change. Saving one afterwards would undo the update:
func open_files() -> PackedStringArray:
	var touched := {}
	for path in _final:
		touched["res://" + path] = true
	for path in _removals:
		touched["res://" + path] = true
	for path in _moves:
		touched["res://" + path] = true
		touched["res://" + String(_moves[path])] = true
	var found: PackedStringArray = []
	for scene_path in EditorInterface.get_open_scenes():
		if touched.has(scene_path):
			found.append(scene_path)
	for script in EditorInterface.get_script_editor().get_open_scripts():
		if touched.has(script.resource_path):
			found.append(script.resource_path)
	return found


#* The developer's files the update overwrites with the release's ([{path, status}], in path order):
#? Candy DE's files they changed, and their own files where the release adds one.
func overwritten_files() -> Array:
	var found := []
	for entry in files:
		if entry["status"] == OVERWRITTEN or entry["status"] == EXISTING:
			found.append(entry)
	return found


#* How many files the update writes, removes and moves:
func change_count() -> int:
	return _final.size() + _removals.size() + _moves.size()


#* Updates Candy DE. Returns an error message, or "":
func update(tree: SceneTree) -> String:
	plan()
	if problem != "":
		return problem

	var journal := []
	var error := await _apply_files(tree, journal)
	if error != "":
		progress.emit(0.5, "Putting the files back…")
		var failures := _roll_back(journal)
		if failures.is_empty():
			return error + " Nothing was changed: every file was put back as it was."
		return "%s Some files couldn't be put back (%s): take them from %s, or from your backup." % [error, ", ".join(failures), folder.path_join("Previous")]

	#? A failure here doesn't undo the update.
	var notes_error := Utils.save_post_notes(package.wizard_notes("post", Utils.NOTES_UPDATE))
	if notes_error != "":
		push_warning(notes_error)

	progress.emit(0.8, "Letting Godot scan the files…")
	await Utils.scan_filesystem(tree)

	progress.emit(0.9, "Updating the project settings…")
	for key in _settings:
		ProjectSettings.set_setting(key, _settings[key])
	var save_error := ProjectSettings.save()
	var record_error := _write_record()
	_write_report()
	if record_error != "":
		return record_error
	if save_error != OK:
		return "Candy DE's files were updated, but the project settings couldn't be saved (%s). Make the changes listed below by hand, in Project Settings." % error_string(save_error)
	progress.emit(1.0, "Done.")
	return ""


func _previous_path(path: String) -> String:
	return folder.path_join("Previous").path_join(path.trim_prefix(Utils.PACKAGE_NAME + "/"))


func _new_path(path: String) -> String:
	return folder.path_join("New").path_join(path.trim_prefix(Utils.PACKAGE_NAME + "/"))


#* Makes every file change, noting each in journal so it can be undone:
func _apply_files(tree: SceneTree, journal: Array) -> String:
	var error := _make_folder(folder)
	if error != "":
		return error
	#? Godot must not load the copies (their classes would clash with the project's).
	var ignore := Utils.UPDATES_FOLDER.path_join(".gdignore")
	if not FileAccess.file_exists(ignore):
		var ignore_file := FileAccess.open(ignore, FileAccess.WRITE)
		if ignore_file == null:
			return "Couldn't write %s (%s)." % [ignore, error_string(FileAccess.get_open_error())]
		ignore_file.close()

	var total := maxi(change_count() + _new_copies.size(), 1)
	var count := 0
	for to in _moves:
		error = _move("res://" + String(_moves[to]), "res://" + String(to))
		if error != "":
			return error
		journal.append({"type": "moved", "from": _moves[to], "to": to})
		count += 1

	var paths := _final.keys()
	paths.sort()
	for path in paths:
		var target: String = "res://" + path
		var existed := FileAccess.file_exists(target)
		if existed:
			error = _copy(target, _previous_path(path))
			if error != "":
				return error
		journal.append({"type": "written", "path": path, "existed": existed})
		error = _write(target, _final[path])
		if error != "":
			return error
		count += 1
		if count % 20 == 0:
			progress.emit(0.75 * count / total, "Updating files… %d / %d" % [count, total])
			await tree.process_frame

	for path in _removals:
		error = _move("res://" + path, _previous_path(path))
		if error != "":
			return error
		journal.append({"type": "removed", "path": path})
		count += 1

	for path in _new_copies:
		error = _write(_new_path(path), _new_copies[path])
		if error != "":
			return error

	#? Remove folders a move or removal emptied.
	for to in _moves:
		_remove_empty_folders(("res://" + String(_moves[to])).get_base_dir())
	for path in _removals:
		_remove_empty_folders(("res://" + path).get_base_dir())
	return ""


#* Undoes the journal's changes, last first. Returns the files that couldn't be put back:
func _roll_back(journal: Array) -> PackedStringArray:
	var failures: PackedStringArray = []
	for index in range(journal.size() - 1, -1, -1):
		var entry: Dictionary = journal[index]
		match entry["type"]:
			"written":
				var target: String = "res://" + entry["path"]
				if entry["existed"]:
					#? A write that failed may have left the file as it was.
					var previous := _previous_path(entry["path"])
					if FileAccess.get_file_as_bytes(target) != FileAccess.get_file_as_bytes(previous) and _copy(previous, target) != "":
						failures.append(entry["path"])
				elif FileAccess.file_exists(target):
					if DirAccess.remove_absolute(target) != OK:
						failures.append(entry["path"])
					_remove_empty_folders(target.get_base_dir())
			"removed":
				if _move(_previous_path(entry["path"]), "res://" + entry["path"]) != "":
					failures.append(entry["path"])
			"moved":
				if _move("res://" + String(entry["to"]), "res://" + String(entry["from"])) != "":
					failures.append(entry["from"])
				_remove_empty_folders(("res://" + String(entry["to"])).get_base_dir())
	return failures


#* Removes a folder the update emptied, and its emptied parents, up to Candy_DE:
func _remove_empty_folders(folder_path: String) -> void:
	while folder_path.begins_with(Utils.CANDY_DE_FOLDER + "/"):
		var dir := DirAccess.open(folder_path)
		if dir == null:
			return
		dir.include_hidden = true
		if not dir.get_files().is_empty() or not dir.get_directories().is_empty():
			return
		if DirAccess.remove_absolute(folder_path) != OK:
			return
		folder_path = folder_path.get_base_dir()


func _make_folder(path: String) -> String:
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error != OK:
		return "Couldn't create the folder %s (%s)." % [path, error_string(error)]
	return ""


func _write(path: String, bytes: PackedByteArray) -> String:
	var error := _make_folder(path.get_base_dir())
	if error != "":
		return error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Couldn't write %s (%s)." % [path, error_string(FileAccess.get_open_error())]
	file.store_buffer(bytes)
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Couldn't write %s (%s)." % [path, error_string(write_error)]
	return ""


func _copy(from: String, to: String) -> String:
	var error := _make_folder(to.get_base_dir())
	if error != "":
		return error
	var copy_error := DirAccess.copy_absolute(from, to)
	if copy_error != OK:
		return "Couldn't copy %s to %s (%s)." % [from, to, error_string(copy_error)]
	return ""


#* Moves a file, and its .uid and .import with it:
func _move(from: String, to: String) -> String:
	var error := _make_folder(to.get_base_dir())
	if error != "":
		return error
	var move_error := DirAccess.rename_absolute(from, to)
	if move_error != OK:
		return "Couldn't move %s to %s (%s)." % [from, to, error_string(move_error)]
	for extension in SIBLING_EXTENSIONS:
		if FileAccess.file_exists(from + "." + extension):
			DirAccess.rename_absolute(from + "." + extension, to + "." + extension)
	return ""


#* Writes the updated install record (the install's date kept, this update added to "updates"):
func _write_record() -> String:
	var updated := record.duplicate(true)
	var now := Time.get_datetime_string_from_system(false, true)
	updated["version"] = package.version()
	updated["wizard_version"] = wizard_version
	updated["answers"] = _answers
	updated["autoloads"] = _autoloads
	updated["input_actions"] = _input_actions
	updated["files"] = _new_record
	var history: Array = updated.get("updates", [])
	history.append({"from": String(record.get("version", "")), "to": package.version(), "date": now, "source": source_text})
	updated["updates"] = history
	var file := FileAccess.open(Utils.RECORD_PATH, FileAccess.WRITE)
	if file == null:
		return "Candy DE was updated, but its install record couldn't be written (%s). The next update may take your changed files for untouched ones: back them up first." % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(updated, "\t"))
	file.close()
	return ""


#* A plain text summary in the update's folder, to come back to after the wizard closes:
func _write_report() -> void:
	var lines: PackedStringArray = []
	lines.append("Candy DE %s → %s, updated %s from the %s." % [record.get("version", ""), package.version(), Time.get_datetime_string_from_system(false, true), source_text])
	lines.append("")
	if not to_do.is_empty():
		lines.append("TO DO BY HAND")
		for item in to_do:
			lines.append("- " + _plain(String(item["title"])))
			for text_line in String(item["text"]).split("\n"):
				lines.append("    " + text_line)
		lines.append("")
	var labels := {
		ADDED: "Added", UPDATED: "Updated", OVERWRITTEN: "Changed by you: replaced by the release's version (yours is in Previous)",
		EXISTING: "Your own file where the release adds one: replaced by the release's (yours is in Previous)", DELETED: "Deleted by you",
		TEMPLATE_CHANGED: "Your file, changed by the release: yours kept, the new version is in New",
		REMOVED: "No longer in Candy DE: removed (it's in Previous)", LEFT: "No longer in Candy DE, changed by you: left",
	}
	for status in labels:
		var listed: PackedStringArray = []
		for entry in files:
			if entry["status"] == status:
				var line := "- " + String(entry["path"])
				if entry.has("choice"):
					line += "  (%s)" % _choice_text(entry["choice"])
				listed.append(line)
		if not listed.is_empty():
			lines.append("%s (%d)" % [labels[status].to_upper(), listed.size()])
			lines.append_array(listed)
			lines.append("")
	lines.append("Previous: every file as it was before the update, for each file it changed, replaced or removed.")
	lines.append("New: the release's versions of your files it changed, which the update didn't install.")
	report_path = folder.path_join("Update_Report.txt")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()


#* BBCode from _code() and escaping, as plain text:
static func _plain(bbcode: String) -> String:
	return bbcode.replace("[code]", "").replace("[/code]", "").replace("[lb]", "[")


#* A choice in plain words:
static func _choice_text(choice: String) -> String:
	match choice:
		RESTORE:
			return "restored"
		LEAVE_OUT:
			return "left out"
	return choice
