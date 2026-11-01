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

#^ Generated files, removed only with their file:
const GENERATED_EXTENSIONS := ["uid", "import"]
const BACKUPS_FOLDER := "user://candy_wizard/wizard_backups"

#^ Set before plan():
var package = null					#/ Package.gd with use_wizard_package(), opened and verified
var wizard_version := ""			#/ The running Candy Wizard's

#^ The plan, paths inside Candy Wizard's folder:
var problem := ""
var folder := ""					#/ Candy Wizard's folder (res://addons/Candy_DE_Wizard)
var changed: PackedStringArray = []
var added: PackedStringArray = []
var removed: PackedStringArray = []

#^ What update() did:
var backup_folder := ""


#* Plan the update, changing nothing. Sets problem on failure:
func plan() -> void:
	problem = ""
	changed.clear()
	added.clear()
	removed.clear()
	folder = Utils.wizard_folder()
	if FileAccess.file_exists(Utils.WIZARD_BUILDER_PATH):
		problem = "This is Candy Wizard's development project: Candy Wizard's folder is its source, so Candy Wizard never updates itself here."
		return
	if Utils.compare_versions(package.version(), wizard_version) <= 0:
		problem = "Candy Wizard %s is installed, and this release is %s: only a newer release can update it." % [wizard_version, package.version()]
		return

	var release_files := {}
	for path in package.files():
		release_files[String(path).trim_prefix(package.root)] = String(path)
	for relative in release_files:
		var target := folder.path_join(relative)
		if not FileAccess.file_exists(target):
			added.append(relative)
		elif Utils.content_hash(relative, FileAccess.get_file_as_bytes(target)) != String(package.files()[release_files[relative]].get("sha256", "")):
			changed.append(relative)
	for relative in _files_in(folder):
		if relative.get_extension() in GENERATED_EXTENSIONS:
			continue
		if not release_files.has(relative):
			removed.append(relative)
	changed.sort()
	added.sort()
	removed.sort()


#* Update the files. Returns an error, or "". The editor must restart after:
func update(tree: SceneTree) -> String:
	plan()
	if problem != "":
		return problem
	progress.emit(0.05, "Keeping a copy of Candy Wizard %s…" % wizard_version)
	await tree.process_frame
	var error := _back_up()
	if error != "":
		return error

	var journal := []
	error = await _apply(tree, journal)
	if error != "":
		progress.emit(0.5, "Putting Candy Wizard back…")
		var failures := _roll_back(journal)
		if failures.is_empty():
			return error + " Nothing was changed: Candy Wizard was put back as it was."
		return "%s Some of Candy Wizard's files couldn't be put back (%s): copy them from %s." % [error, ", ".join(failures), ProjectSettings.globalize_path(backup_folder)]
	progress.emit(1.0, "Done.")
	return ""


#* Back up the whole folder:
func _back_up() -> String:
	var base := BACKUPS_FOLDER.path_join(wizard_version)
	backup_folder = base
	var number := 2
	while DirAccess.dir_exists_absolute(backup_folder):
		backup_folder = "%s (%d)" % [base, number]
		number += 1
	for relative in _files_in(folder):
		var error := _copy(folder.path_join(relative), backup_folder.path_join(relative))
		if error != "":
			return "Couldn't keep a copy of Candy Wizard, so nothing was changed: " + error
	return ""


func _apply(tree: SceneTree, journal: Array) -> String:
	var total := maxi(changed.size() + added.size() + removed.size(), 1)
	var count := 0
	for relative in changed + added:
		var target := folder.path_join(relative)
		journal.append({"type": "written", "path": relative, "existed": relative in changed})
		var error := _write(target, package.read(package.root + relative))
		if error != "":
			return error
		count += 1
		if count % 10 == 0:
			progress.emit(0.1 + 0.85 * count / total, "Updating Candy Wizard… %d / %d" % [count, total])
			await tree.process_frame
	for relative in removed:
		for path in [relative, relative + ".uid", relative + ".import"]:
			var target := folder.path_join(path)
			if FileAccess.file_exists(target):
				journal.append({"type": "removed", "path": path})
				if DirAccess.remove_absolute(target) != OK:
					return "Couldn't remove %s." % target
	_remove_empty_folders()
	return ""


#* Undo the journal from the backup, last first. Returns files not put back:
func _roll_back(journal: Array) -> PackedStringArray:
	var failures: PackedStringArray = []
	for index in range(journal.size() - 1, -1, -1):
		var entry: Dictionary = journal[index]
		var target := folder.path_join(entry["path"])
		var backup := backup_folder.path_join(entry["path"])
		if entry["type"] == "written" and not entry["existed"]:
			if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) != OK:
				failures.append(entry["path"])
		elif FileAccess.get_file_as_bytes(target) != FileAccess.get_file_as_bytes(backup) or not FileAccess.file_exists(target):
			if _copy(backup, target) != "":
				failures.append(entry["path"])
	_remove_empty_folders()
	return failures


#* Files under a folder, relative:
static func _files_in(base: String) -> PackedStringArray:
	var found: PackedStringArray = []
	_list(base, "", found)
	return found


static func _list(base: String, relative: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(base.path_join(relative))
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := entry
		if relative != "":
			path = relative + "/" + entry
		if dir.current_is_dir():
			_list(base, path, found)
		else:
			found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


#* Remove empty folders inside Candy Wizard's:
func _remove_empty_folders() -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub_folder in dir.get_directories():
		_remove_empty_under(folder.path_join(sub_folder))


static func _remove_empty_under(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.include_hidden = true
	var empty := dir.get_files().is_empty()
	for sub_folder in dir.get_directories():
		if not _remove_empty_under(path.path_join(sub_folder)):
			empty = false
	return empty and DirAccess.remove_absolute(path) == OK


func _write(path: String, bytes: PackedByteArray) -> String:
	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK:
		return "Couldn't create the folder %s (%s)." % [path.get_base_dir(), error_string(dir_error)]
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
	var dir_error := DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	if dir_error != OK:
		return "Couldn't create the folder %s (%s)." % [to.get_base_dir(), error_string(dir_error)]
	var error := DirAccess.copy_absolute(from, to)
	if error != OK:
		return "Couldn't copy %s to %s (%s)." % [from, to, error_string(error)]
	return ""
