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


const Utils = preload("Wizard_Utils.gd")
const DocsZip = preload("Docs_Zip.gd")

const BACKUPS_FOLDER := "user://candy_wizard/docs_backups"

#^ Set before fetch():
var docs_set: Dictionary = {}		#/ An entry of Utils.DOCS_SETS
var tree: Dictionary = {}			#/ Docs_Source.fetch_tree()'s answer for the set's repository

#^ The checked zip (fetch()), paths inside Databases:
var zip_hash := ""					#/ The zip's git hash on GitHub
var contents := {}					#/ path -> bytes

#^ The plan, paths inside Databases:
var problem := ""
var upstream := {}					#/ Every file of the zip: path -> git hash
var to_download: PackedStringArray = []
var to_remove: PackedStringArray = []
var changed_here: PackedStringArray = []
var left_out: PackedStringArray = []	#/ Files of a type never downloaded

#^ What apply() did:
var backup_folder := ""


#* Whether the zip on GitHub is the one last downloaded, and every file it brought is still here as it was:
func is_current() -> bool:
	var entry = Utils.read_database_record().get("docs", {}).get(docs_set["id"], {})
	var on_github := String(tree.get("files", {}).get(Utils.docs_zip_path(docs_set), ""))
	if not entry is Dictionary or on_github == "" or String(entry.get("zip_hash", "")) != on_github:
		return false
	var recorded := recorded_files()
	for relative in recorded:
		var target := Utils.DOCS_DATABASES_FOLDER.path_join(relative)
		if not FileAccess.file_exists(target) or not _has_hash(relative, FileAccess.get_file_as_bytes(target), String(recorded[relative])):
			return false
	return not recorded.is_empty()


#* Download the set's zip and check it, then plan(). Sets problem on failure:
#? source: a Docs_Source.gd in the tree.
func fetch(source: Node) -> void:
	problem = ""
	contents = {}
	if not DirAccess.dir_exists_absolute(Utils.DATABASE_FOLDER):
		problem = "Install Candy Database first: the documentation goes in its folder."
		return
	var zip_path := Utils.docs_zip_path(docs_set)
	if not tree.get("files", {}).has(zip_path):
		problem = "The %s documentation isn't on GitHub yet (%s, %s)." % [docs_set["title"], docs_set["repository"], zip_path]
		return
	zip_hash = String(tree["files"][zip_path])
	var downloaded: Dictionary = await source.download_files(docs_set["repository"], tree["commit"], {zip_path: zip_hash})
	if downloaded.has("error"):
		problem = downloaded["error"] + " Nothing was changed."
		return
	var title := "%s documentation" % docs_set["title"]
	var unpacked := DocsZip.read(downloaded["files"][zip_path], String(docs_set["folder"]).get_file(), title)
	if unpacked.has("error"):
		problem = unpacked["error"] + " Nothing was changed."
		return
	contents = unpacked["files"]
	left_out = unpacked["left_out"]
	plan()


#* Plan the download from the checked zip, changing nothing:
func plan() -> void:
	upstream.clear()
	to_download.clear()
	to_remove.clear()
	changed_here.clear()
	for relative in contents:
		upstream[relative] = Utils.git_blob_hash(relative, contents[relative], false)

	var recorded := recorded_files()
	for relative in upstream:
		var target := Utils.DOCS_DATABASES_FOLDER.path_join(relative)
		if not FileAccess.file_exists(target):
			to_download.append(relative)
			continue
		var bytes := FileAccess.get_file_as_bytes(target)
		if _has_hash(relative, bytes, upstream[relative]):
			continue
		to_download.append(relative)
		if not _has_hash(relative, bytes, String(recorded.get(relative, ""))):
			changed_here.append(relative)
	for relative in recorded:
		if upstream.has(relative):
			continue
		var target := Utils.DOCS_DATABASES_FOLDER.path_join(relative)
		if not FileAccess.file_exists(target):
			continue
		to_remove.append(relative)
		if not _has_hash(relative, FileAccess.get_file_as_bytes(target), String(recorded[relative])):
			changed_here.append(relative)
	to_download.sort()
	to_remove.sort()
	changed_here.sort()


#* Whether a file matches a git hash, as is or with normalized line endings:
static func _has_hash(relative: String, bytes: PackedByteArray, git_hash: String) -> bool:
	return Utils.git_blob_hash(relative, bytes, false) == git_hash or Utils.git_blob_hash(relative, bytes) == git_hash	#/ Git may change line endings on checkout


#* Files of the last download - path inside Databases -> git hash:
func recorded_files() -> Dictionary:
	var entry = Utils.read_database_record().get("docs", {}).get(docs_set["id"], {})
	if entry is Dictionary:
		return Utils.safe_record_files(entry.get("files"))
	return {}


#* Write the zip's files, remove dropped ones and record the set. Returns an error, or "":
func apply() -> String:
	if contents.is_empty():
		return "Download the documentation first."
	plan()
	var error := _back_up()
	if error != "":
		return error
	for relative in to_download:
		error = Utils.write_file(Utils.DOCS_DATABASES_FOLDER.path_join(relative), contents[relative])
		if error != "":
			return error + " The documentation is only partly updated: download it again."
	for relative in to_remove:
		if not Utils.remove_with_generated(Utils.DOCS_DATABASES_FOLDER.path_join(relative)):
			return "Couldn't remove %s. The documentation is only partly updated: download it again." % Utils.DOCS_DATABASES_FOLDER.path_join(relative)
	Utils.remove_emptied_folders(Utils.DOCS_DATABASES_FOLDER, to_remove)

	var record := Utils.read_database_record()
	var docs = record.get("docs", {})
	if not docs is Dictionary:
		docs = {}
	docs[docs_set["id"]] = {
		"repository": docs_set["repository"],
		"folder": docs_set["folder"],
		"commit": tree["commit"],
		"zip_hash": zip_hash,
		"date": Time.get_datetime_string_from_system(false, true),
		"files": upstream,
	}
	record["docs"] = docs
	error = Utils.write_database_record(record)
	if error != "":
		return "The documentation was downloaded, but the record couldn't be written, so its next update won't remove the files it drops. " + error
	return ""


#* Back up changed_here:
func _back_up() -> String:
	backup_folder = ""
	if changed_here.is_empty():
		return ""
	var base := BACKUPS_FOLDER.path_join("%s %s" % [docs_set["id"], Time.get_datetime_string_from_system(false, true).replace(":", "-")])
	backup_folder = base
	var number := 2
	while DirAccess.dir_exists_absolute(backup_folder):
		backup_folder = "%s (%d)" % [base, number]
		number += 1
	for relative in changed_here:
		var error := Utils.copy_file(Utils.DOCS_DATABASES_FOLDER.path_join(relative), backup_folder.path_join(relative))
		if error != "":
			return "Couldn't keep a copy of the files changed here, so nothing was changed: " + error
	return ""
