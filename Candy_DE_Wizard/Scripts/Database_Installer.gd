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

const BACKUPS_FOLDER := "user://candy_wizard/database_backups"

#^ Set before plan():
var package = null					#/ Package.gd with use_database_package(), opened and verified

#^ The plan, paths inside Candy Database's folder:
var problem := ""
var installed_version := ""			#/ "" when Candy Database isn't installed yet
var changed: PackedStringArray = []
var added: PackedStringArray = []
var removed: PackedStringArray = []
var unrecorded := false				#/ Installed without a record: files the release dropped stay

#^ What install() did:
var backup_folder := ""


#* Plan the install or update, changing nothing. Sets problem on failure:
func plan() -> void:
	problem = ""
	changed.clear()
	added.clear()
	removed.clear()
	unrecorded = false
	if FileAccess.file_exists(Utils.DATABASE_BUILDER_PATH):
		problem = "This is Candy Database's development project: its folder is Candy Database's source, so Candy Wizard never installs or updates it here."
		return
	installed_version = Utils.installed_database_version()
	if installed_version != "" and Utils.compare_versions(package.version(), installed_version) <= 0:
		problem = "Candy Database %s is installed, and this release is %s: only a newer release can update it." % [installed_version, package.version()]
		return

	var release_files := _release_files()
	for relative in release_files:
		var target := Utils.DATABASE_FOLDER.path_join(relative)
		if not FileAccess.file_exists(target):
			added.append(relative)
		elif Utils.content_hash(relative, FileAccess.get_file_as_bytes(target)) != String(package.files()[release_files[relative]].get("sha256", "")):
			changed.append(relative)
	var recorded := Utils.safe_record_files(Utils.read_database_record().get("files", {}))
	unrecorded = installed_version != "" and recorded.is_empty()
	for relative in recorded:
		if not release_files.has(relative) and FileAccess.file_exists(Utils.DATABASE_FOLDER.path_join(relative)):
			removed.append(relative)
	changed.sort()
	added.sort()
	removed.sort()


#* Install or update, then enable. Returns an error, or "":
func install(tree: SceneTree) -> String:
	plan()
	if problem != "":
		return problem
	var plugin_name := Utils.DATABASE_FOLDER.get_file()
	var was_enabled := installed_version != "" and EditorInterface.is_plugin_enabled(plugin_name)
	progress.emit(0.05, "Keeping a copy of the files that change…")
	await tree.process_frame
	var error := _back_up()
	if error != "":
		return error
	if was_enabled:
		EditorInterface.set_plugin_enabled(plugin_name, false)
		await tree.process_frame

	var journal := []
	error = await _apply(tree, journal)
	if error != "":
		progress.emit(0.5, "Putting Candy Database back…")
		var failures := _roll_back(journal)
		await Utils.scan_filesystem(tree)
		if was_enabled:
			EditorInterface.set_plugin_enabled(plugin_name, true)
		if failures.is_empty():
			return error + " Nothing was changed: Candy Database was put back as it was."
		return "%s Some of Candy Database's files couldn't be put back (%s): copy them from %s." % [error, ", ".join(failures), ProjectSettings.globalize_path(backup_folder)]

	error = _write_record()
	progress.emit(0.95, "Loading Candy Database…")
	await Utils.scan_filesystem(tree)
	if was_enabled or installed_version == "":
		EditorInterface.set_plugin_enabled(plugin_name, true)
	progress.emit(1.0, "Done.")
	if error != "":
		return "Candy Database was installed, but its record couldn't be written, so its next update won't remove the files it drops. " + error
	return ""


#* Release files - path inside Candy Database's folder -> path in the zip:
func _release_files() -> Dictionary:
	var found := {}
	for path in package.files():
		found[String(path).trim_prefix(package.root)] = String(path)
	return found


#* Back up changed and removed files, with their .uid and .import:
func _back_up() -> String:
	#? Named after a plain installed version:
	var base := BACKUPS_FOLDER.path_join("unknown_version")
	if installed_version == "":
		base = BACKUPS_FOLDER.path_join("before_install")
	elif Utils.is_plain_version(installed_version):
		base = BACKUPS_FOLDER.path_join(installed_version)
	backup_folder = base
	var number := 2
	while DirAccess.dir_exists_absolute(backup_folder):
		backup_folder = "%s (%d)" % [base, number]
		number += 1
	for relative in changed + removed:
		for path in [relative, relative + ".uid", relative + ".import"]:
			var source := Utils.DATABASE_FOLDER.path_join(path)
			if not FileAccess.file_exists(source):
				continue
			var error := Utils.copy_file(source, backup_folder.path_join(path))
			if error != "":
				return "Couldn't keep a copy of Candy Database's files, so nothing was changed: " + error
	return ""


func _apply(tree: SceneTree, journal: Array) -> String:
	var release_files := _release_files()
	var total := maxi(changed.size() + added.size() + removed.size(), 1)
	var count := 0
	for relative in changed + added:
		journal.append({"type": "written", "path": relative, "existed": relative in changed})
		var error := Utils.write_file(Utils.DATABASE_FOLDER.path_join(relative), package.read(release_files[relative]))
		if error != "":
			return error
		count += 1
		if count % 10 == 0:
			progress.emit(0.1 + 0.8 * count / total, "Writing Candy Database… %d / %d" % [count, total])
			await tree.process_frame
	for relative in removed:
		for path in [relative, relative + ".uid", relative + ".import"]:
			var target := Utils.DATABASE_FOLDER.path_join(path)
			if FileAccess.file_exists(target):
				journal.append({"type": "removed", "path": path})
				if DirAccess.remove_absolute(target) != OK:
					return "Couldn't remove %s." % target
	Utils.remove_emptied_folders(Utils.DATABASE_FOLDER, removed)
	return ""


#* Undo the journal from the backup, last first. Returns files not put back:
func _roll_back(journal: Array) -> PackedStringArray:
	var failures: PackedStringArray = []
	var created: PackedStringArray = []
	for index in range(journal.size() - 1, -1, -1):
		var entry: Dictionary = journal[index]
		var target := Utils.DATABASE_FOLDER.path_join(entry["path"])
		if entry["type"] == "written" and not entry["existed"]:
			created.append(entry["path"])
			if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) != OK:
				failures.append(entry["path"])
		elif Utils.copy_file(backup_folder.path_join(entry["path"]), target) != "":
			failures.append(entry["path"])
	Utils.remove_emptied_folders(Utils.DATABASE_FOLDER, created)
	if installed_version == "":
		#? New install: remove its folder if empty:
		Utils.remove_if_empty(Utils.DATABASE_FOLDER)
	return failures


#* Write the record (version, files), keeping the docs' entries:
func _write_record() -> String:
	var record := Utils.read_database_record()
	var now := Time.get_datetime_string_from_system(false, true)
	if installed_version == "" or not record.has("installed"):
		record["installed"] = now
	else:
		record["updated"] = now
	record["version"] = package.version()
	record["source"] = "GitHub release"
	var files := {}
	var release_files := _release_files()
	for relative in release_files:
		files[relative] = String(package.files()[release_files[relative]].get("sha256", ""))
	record["files"] = files
	return Utils.write_database_record(record)
