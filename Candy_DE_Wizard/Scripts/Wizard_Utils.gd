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


#^ Where Candy DE is installed:
const CANDY_DE_FOLDER := "res://Candy_DE"

#^ What Candy Wizard installed (in Candy_DE, so it survives Candy Wizard being replaced):
#? Candy Wizard's files go in Candy_DE/.Install: the dot hides it from Godot (never imported, scanned or exported).
const RECORD_PATH := "res://Candy_DE/.Install/Install_Record.json"
const RECORD_FORMAT := 1

#^ The voice files' recorded layout (voice_folder + voice_path), for moving them (Voice_Files.gd):
const VOICE_LAYOUT_PATH := "res://Candy_DE/.Install/Voice_Layout.json"

#^ A release's BBCode notes: "pre", shown before the wizards change anything, "post" once done,
#^ each general (both installs and updates) or for one flow ("_install" / "_update"):
#! Must match NOTES in Release_Tools/Build_Release.gd.
const NOTES_FILES := {
	"pre": "wizard_pre_notes.txt",
	"pre_install": "wizard_pre_notes_i.txt",
	"pre_update": "wizard_pre_notes_u.txt",
	"post_install": "wizard_post_notes_i.txt",
	"post_update": "wizard_post_notes_u.txt",
	"post": "wizard_post_notes.txt",
}
#^ The flows a wizard can be in, for its notes (an upgrade from 1.1.3 is an update):
const NOTES_INSTALL := "install"
const NOTES_UPDATE := "update"
#^ The installed release's post notes, kept for the Setup tool's "Notes" button:
const POST_NOTES_PATH := "res://Candy_DE/.Install/Post_Notes.txt"

#^ Whether the post notes are still to be shown (per project, EditorSettings' project metadata):
const METADATA_SECTION := "candy_wizard"
const METADATA_POST_NOTES_PENDING := "post_notes_pending"
#^ Tools marked in the dock's drop-down until opened once (per project), by name:
const METADATA_UNOPENED_TOOLS := "unopened_tools"
#^ The tools to open after an install, and after a 1.1.3 upgrade:
const TOOLS_TO_OPEN_AFTER_INSTALL := ["Docs", "Folders", "Symbols"]
const TOOLS_TO_OPEN_AFTER_UPGRADE := ["Docs", "Folders", "Symbols", "Dialogue Converter"]

#^ Each update's replaced/removed files ("Previous") and the release's uninstalled versions ("New"), per version:
#? Its .gdignore keeps copied scripts from clashing with the project's classes.
const UPDATES_FOLDER := "res://Candy_DE/.Install/Updates"

#^ Source of the --dev-record record (Candy DE's development project, never removed):
#! Must match _write_dev_record() in Release_Tools/Build_Release.gd.
const DEV_RECORD_SOURCE := "development project"

#^ Release packages:
const PACKAGE_NAME := "Candy_DE"
const MANIFEST_NAME := "candy_de_manifest.json"
const MANIFEST_FORMAT := 1			#/ The newest manifest format this Candy Wizard can read

#^ GitHub repository of Candy DE's releases ("owner/repository"). Empty: zip only:
const GITHUB_REPOSITORY := "Candy-Arts/Candy-Dialogue-Engine"
#^ The repository's ID, what GitHub is asked by (never the name), here and below. 0 = off:
#? An ID is never reused, so a new repository under the same name is never read; it follows renames.
#? Found in the repository page's "octolytics-dimension-repository_id" meta tag.
const GITHUB_REPOSITORY_ID := 1187655828

#^ Candy Wizard's own releases (Wizard_Tools/Build_Wizard.gd in its development project):
const WIZARD_PACKAGE_NAME := "Candy_DE_Wizard"
const WIZARD_MANIFEST_NAME := "candy_wizard_manifest.json"
#^ GitHub repository of Candy Wizard's releases. Empty: zip only, and no update checks:
const WIZARD_GITHUB_REPOSITORY := "Candy-Arts/Candy_DE_Wizard"
const WIZARD_GITHUB_REPOSITORY_ID := 1441479940
#^ Only in Candy Wizard's development project, where it must never update itself:
const WIZARD_BUILDER_PATH := "res://Wizard_Tools/Build_Wizard.gd"
#^ Gives Candy Wizard's folder, wherever it is:
const _WIZARD_ANCHOR := preload("../Icons/Candy_Icon.svg")

#^ Candy Database, the documentation browser. Installed in DATABASE_FOLDER only:
const DATABASE_PACKAGE_NAME := "Candy_Database"
const DATABASE_MANIFEST_NAME := "candy_database_manifest.json"
const DATABASE_GITHUB_REPOSITORY := "Candy-Arts/Candy-Database"
const DATABASE_GITHUB_REPOSITORY_ID := 1440638590
const DATABASE_FOLDER := "res://addons/Candy_Database"
#^ Record of Candy Database and its documentation (in its folder, which its updates leave alone):
const DATABASE_RECORD_PATH := "res://addons/Candy_Database/Install_Record.json"
#^ Only in Candy Database's development project, where Candy Wizard must never install it:
const DATABASE_BUILDER_PATH := "res://Database_Tools/Build_Database.gd"

#^ Candy Arts' repository - the news and the documentation:
const CANDY_ARTS_GITHUB_REPOSITORY := "Candy-Arts/Candy-Arts"
const CANDY_ARTS_GITHUB_REPOSITORY_ID := 1177938775

#^ Documentation for Candy Database's Databases folder, a signed zip of a GitHub branch each (docs_zip_path()):
#? A database's folder lands in Databases under the same name.
const DOCS_DATABASES_FOLDER := "res://addons/Candy_Database/Databases"
#^ Candy Arts' repository folder holding every database, a zip each (<folder>.zip):
const DOCS_REPOSITORY_FOLDER := "DOCUMENTATION"
#^ A documentation zip's manifest at its root, signed like a release's (Release_Signature.gd), and its format:
#! Shared with Candy Web Database's Web_Docs_Zip.gd and Candy DC's Core/docs_zip.gd: change them together.
const DOCS_MANIFEST_NAME := "candy_docs_manifest.json"
const DOCS_PACKAGE_NAME := "candy_docs"
const DOCS_MANIFEST_FORMAT := 1
#^ The documentation of Candy DE and its tools, always offered ("title": the row's; messages add " documentation"):
#? The other databases of DOCS_REPOSITORY_FOLDER are offered too, apart (docs_sets()).
const DOCS_SETS := [
	{"id": "candy_de", "title": "Candy Dialogue Engine", "repository": CANDY_ARTS_GITHUB_REPOSITORY, "repository_id": CANDY_ARTS_GITHUB_REPOSITORY_ID, "branch": "main", "folder": DOCS_REPOSITORY_FOLDER + "/Candy_Dialogue_Engine"},
	{"id": "candy_dc", "title": "Candy Dialogue Creator", "repository": CANDY_ARTS_GITHUB_REPOSITORY, "repository_id": CANDY_ARTS_GITHUB_REPOSITORY_ID, "branch": "main", "folder": DOCS_REPOSITORY_FOLDER + "/Candy_Dialogue_Creator"},
	{"id": "candy_db", "title": "Candy Database", "repository": CANDY_ARTS_GITHUB_REPOSITORY, "repository_id": CANDY_ARTS_GITHUB_REPOSITORY_ID, "branch": "main", "folder": DOCS_REPOSITORY_FOLDER + "/Candy_Database"},
]
#^ Prefixes the set id of a database outside DOCS_SETS:
const OTHER_DOCS_ID_PREFIX := "other_"
#^ The only file types downloaded as documentation (never scripts, scenes or resources):
const DOCS_EXTENSIONS := ["txt", "json", "md", "png", "jpg", "jpeg", "webp", "svg", "bmp", "ttf", "otf", "woff", "woff2", "gitkeep"]
#^ The News tool's sources (News.gd) - one BBCode file of a branch each, shown in this order.
#? "id" prefixes its items' identifiers, so two files can use the same one. repository_id 0 = that source off.
const NEWS_SOURCES := [
	{"id": "candy_de", "title": "Candy DE news", "repository": CANDY_ARTS_GITHUB_REPOSITORY, "repository_id": CANDY_ARTS_GITHUB_REPOSITORY_ID, "branch": "main", "path": "NEWS/Candy Dialogue Engine/News.txt"},
	{"id": "candy_arts", "title": "Candy Arts news", "repository": CANDY_ARTS_GITHUB_REPOSITORY, "repository_id": CANDY_ARTS_GITHUB_REPOSITORY_ID, "branch": "main", "path": "NEWS/Candy Arts/News.txt"},
]

#^ Downloads and other temporary files:
const TEMP_FOLDER := "user://candy_wizard"

#^ Editor settings (kept per machine, not per project):
const SETTING_BACKUP_FOLDER := "candy_wizard/backup_folder"
#^ The dock's last look for a newer release, {"time", "version"}: Candy DE's, Candy Wizard's:
const SETTING_UPDATE_CHECK := "candy_wizard/update_check"
const SETTING_WIZARD_UPDATE_CHECK := "candy_wizard/wizard_update_check"
#^ The Docs tool's last looks - Candy Database's latest release, and the documentation's folders:
#? {"time", "version"} and {"time", "trees": {<set id>: <folder's tree hash, "" when missing>}}.
const SETTING_DATABASE_UPDATE_CHECK := "candy_wizard/database_update_check"
const SETTING_DOCS_CHECK := "candy_wizard/docs_check"
#^ The news (News.gd) - {"auto", "time", "etag", "text"}:
const SETTING_NEWS := "candy_wizard/news"

#^ Files hashed with normalized line endings:
#! Must match TEXT_EXTENSIONS in Release_Tools/Build_Release.gd.
const TEXT_EXTENSIONS := ["gd", "tscn", "tres", "json", "cfg", "gdshader", "md", "txt", "csv", "gitkeep", "gdignore"]


#==============================================================================
#  HASHING
#==============================================================================

#* A file's content with "\r\n" line endings turned into "\n", if it is a text file:
static func normalized(path: String, bytes: PackedByteArray) -> PackedByteArray:
	if not path.get_extension().to_lower() in TEXT_EXTENSIONS:
		return bytes
	return bytes.get_string_from_utf8().replace("\r\n", "\n").to_utf8_buffer()	#/ Git on Windows can change line endings on checkout


#* SHA-256 of a file's normalized content, as the manifest writes it:
static func content_hash(path: String, bytes: PackedByteArray) -> String:
	var data := normalized(path, bytes)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if data.size() > 0:
		context.update(data)
	return context.finish().hex_encode()


#^ Scenes and text resources, compared by resource_hash():
const RESOURCE_EXTENSIONS := ["tscn", "tres"]
#^ What Godot rewrites in them on its own: UIDs (new ones per project), load_steps, format,
#^ node unique IDs (Godot 4.6):
const RESOURCE_NOISE := [r' uid="uid://[a-z0-9]+"', r' load_steps=\d+', r' format=\d+', r' unique_id=\d+']
#^ Where resource_hash() puts the folders it's given:
const RESOURCE_FOLDER := "res://Candy_DE/"

#* SHA-256 of a scene or text resource without what Godot rewrites on its own (RESOURCE_NOISE),
#* every path in one of folders (each ending in "/") read as in RESOURCE_FOLDER.
#? A 1.1.3 install's scenes the developer never edited still differ from 1.1.3's: Godot gives
#? them the project's UIDs, and points them at the folder they were moved to.
static func resource_hash(bytes: PackedByteArray, folders: PackedStringArray) -> String:
	var text := bytes.get_string_from_utf8().replace("\r\n", "\n")
	for folder in folders:
		text = text.replace(folder, RESOURCE_FOLDER)
	for pattern in RESOURCE_NOISE:
		text = RegEx.create_from_string(pattern).sub(text, "", true)
	return content_hash("resource.txt", text.to_utf8_buffer())


#* A content's git blob hash (SHA-1), as GitHub lists files:
#? normalize: text normalized like content_hash(); false checks a download is exactly GitHub's.
static func git_blob_hash(path: String, bytes: PackedByteArray, normalize: bool = true) -> String:
	var data := bytes
	if normalize:
		data = normalized(path, bytes)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA1)
	var header := ("blob %d" % data.size()).to_utf8_buffer()
	header.append(0)
	context.update(header)
	if data.size() > 0:
		context.update(data)
	return context.finish().hex_encode()


#==============================================================================
#  VERSIONS
#==============================================================================

#* Compares two "major.minor.patch" versions (-1 = a is older, 0 = equal, 1 = newer):
static func compare_versions(a: String, b: String) -> int:
	#? Leading "v" ignored; missing parts count as 0 ("4.6" == "4.6.0").
	var parts_a := a.strip_edges().trim_prefix("v").split("-")[0].split(".")
	var parts_b := b.strip_edges().trim_prefix("v").split("-")[0].split(".")
	for index in max(parts_a.size(), parts_b.size()):
		var number_a := 0
		var number_b := 0
		if index < parts_a.size():
			number_a = parts_a[index].to_int()
		if index < parts_b.size():
			number_b = parts_b[index].to_int()
		if number_a < number_b:
			return -1
		if number_a > number_b:
			return 1
	return 0


#^ A version alone - digits and dots ("1.2.0"):
static var _plain_version_regex := RegEx.create_from_string(r"^\d+(\.\d+)*\z")

#* Whether a version is written with digits and dots only ("1.2.0"), as releases give it:
static func is_plain_version(version: String) -> bool:
	return _plain_version_regex.search(version) != null	#/ Versions name folders and zips: anything else ("../..") is never used


#* The last look for a newer release (SETTING_UPDATE_CHECK or SETTING_WIZARD_UPDATE_CHECK):
#* {"time", "version"}, or {} when there was none:
static func last_update_check(setting: String) -> Dictionary:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(setting):
		return {}
	var value = settings.get_setting(setting)
	if value is Dictionary:
		return value
	return {}


#* Keeps Release_Source.fetch_latest_release()'s answer in setting. Returns false (nothing kept) when GitHub couldn't be reached:
#? Its version when installable, "" when GitHub has none.
static func remember_latest_release(setting: String, latest: Dictionary) -> bool:
	var version := ""
	if latest.has("asset_url") and not latest.has("error"):
		version = String(latest["version"])
	elif not latest.has("version"):
		return false
	EditorInterface.get_editor_settings().set_setting(setting, {"time": Time.get_unix_time_from_system(), "version": version})
	return true


#* Candy Wizard's newer version on GitHub (as last looked), or "" (none, or not looking):
static func newer_wizard_version(wizard_version: String) -> String:
	if WIZARD_GITHUB_REPOSITORY == "" or FileAccess.file_exists(WIZARD_BUILDER_PATH):
		return ""
	var latest := String(last_update_check(SETTING_WIZARD_UPDATE_CHECK).get("version", ""))
	if latest == "" or compare_versions(latest, wizard_version) <= 0:
		return ""
	return latest


#* The running Godot editor's version, as "major.minor.patch":
static func godot_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [info["major"], info["minor"], info["patch"]]


#==============================================================================
#  INSTALL RECORD
#==============================================================================

#* The install record, or {} when Candy DE wasn't installed by Candy Wizard:
static func read_record() -> Dictionary:
	if not FileAccess.file_exists(RECORD_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	if parsed is Dictionary:
		return parsed
	return {}


#* Whether the record is the development project's, where Candy DE is made, not installed:
static func is_dev_record(record: Dictionary) -> bool:
	return String(record.get("source", "")) == DEV_RECORD_SOURCE


#* Candy Database's record, or {} when there's none:
#? "version", "installed", "updated", "files" (sha256 each) and "docs" (per set, Docs_Files.gd).
static func read_database_record() -> Dictionary:
	if not FileAccess.file_exists(DATABASE_RECORD_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATABASE_RECORD_PATH))
	if parsed is Dictionary:
		return parsed
	return {}


#* Every docs set offered - DOCS_SETS, then the other databases (other_docs_set()), sorted by title:
#? The others: those GitHub had at the last look (or seen, folder names), and those downloaded.
static func docs_sets(seen: Variant = null) -> Array:
	var names := {}
	if seen == null:
		seen = last_update_check(SETTING_DOCS_CHECK).get("others", [])
	if seen is Array:
		for folder_name in seen:
			names[String(folder_name)] = true
	var downloaded = read_database_record().get("docs", {})
	if downloaded is Dictionary:
		for id in downloaded:
			var entry = downloaded[id]
			if String(id).begins_with(OTHER_DOCS_ID_PREFIX) and entry is Dictionary:
				names[String(entry.get("folder", "")).trim_prefix(DOCS_REPOSITORY_FOLDER + "/")] = true
	var others := []
	for folder_name in names:
		if is_other_docs_database(folder_name):
			others.append(other_docs_set(folder_name))
	others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["title"]).naturalnocasecmp_to(String(b["title"])) < 0)
	return DOCS_SETS + others


#* The docs set of a database outside DOCS_SETS:
static func other_docs_set(folder_name: String) -> Dictionary:
	return {
		"id": OTHER_DOCS_ID_PREFIX + folder_name,
		"title": docs_database_title(folder_name),
		"repository": CANDY_ARTS_GITHUB_REPOSITORY,
		"repository_id": CANDY_ARTS_GITHUB_REPOSITORY_ID,
		"branch": "main",
		"folder": DOCS_REPOSITORY_FOLDER.path_join(folder_name),
		"other": true,
	}


#* Whether a folder name of DOCS_REPOSITORY_FOLDER can be an other database (one folder, not in DOCS_SETS):
static func is_other_docs_database(folder_name: String) -> bool:
	if not is_safe_relative_path(folder_name) or "/" in folder_name:
		return false
	for docs_set in DOCS_SETS:
		if String(docs_set["folder"]) == DOCS_REPOSITORY_FOLDER.path_join(folder_name):
			return false
	return true


#* The other databases of a Docs_Source.fetch_tree() answer - the names of DOCS_REPOSITORY_FOLDER's zips:
static func other_docs_databases(tree: Dictionary) -> PackedStringArray:
	var found: PackedStringArray = []
	var prefix := DOCS_REPOSITORY_FOLDER + "/"
	for path in tree.get("files", {}):
		var file_name := String(path).trim_prefix(prefix)
		if String(path).begins_with(prefix) and file_name.get_extension().to_lower() == "zip" and is_other_docs_database(file_name.get_basename()):
			found.append(file_name.get_basename())
	found.sort()
	return found


#* A docs set's zip in its repository ("DOCUMENTATION/Candy_Dialogue_Engine.zip"):
static func docs_zip_path(docs_set: Dictionary) -> String:
	return String(docs_set["folder"]) + ".zip"


#* A downloaded database's title (its database.json's), else its folder's name:
static func docs_database_title(folder_name: String) -> String:
	var path := DOCS_DATABASES_FOLDER.path_join(folder_name).path_join("database.json")
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("title") is String and String(parsed["title"]).strip_edges() != "":
			return String(parsed["title"]).strip_edges()
	return folder_name.replace("_", " ")


#* Returns an error message, or "":
static func write_database_record(record: Dictionary) -> String:
	record["format"] = RECORD_FORMAT
	return write_file(DATABASE_RECORD_PATH, (JSON.stringify(record, "\t") + "\n").to_utf8_buffer())


#* The version of Candy Database in DATABASE_FOLDER (its plugin.cfg's), or "" when it isn't there:
static func installed_database_version() -> String:
	var config := ConfigFile.new()
	if config.load(DATABASE_FOLDER.path_join("plugin.cfg")) != OK:
		return ""
	return str(config.get_value("plugin", "version", "?"))


#* Candy Wizard's folder ("res://addons/Candy_DE_Wizard", unless it was renamed):
static func wizard_folder() -> String:
	return _WIZARD_ANCHOR.resource_path.get_base_dir().get_base_dir()


#* Keeps the release's post notes, or removes the last ones (text ""). Returns an error message, or "":
static func save_post_notes(text: String) -> String:
	if text == "":
		if FileAccess.file_exists(POST_NOTES_PATH):
			DirAccess.remove_absolute(POST_NOTES_PATH)
		return ""
	DirAccess.make_dir_recursive_absolute(POST_NOTES_PATH.get_base_dir())
	var file := FileAccess.open(POST_NOTES_PATH, FileAccess.WRITE)
	if file == null:
		return "Couldn't write the release's notes, %s (%s)." % [POST_NOTES_PATH, error_string(FileAccess.get_open_error())]
	file.store_string(text + "\n")
	file.close()
	return ""


static func post_notes_pending() -> bool:
	return bool(EditorInterface.get_editor_settings().get_project_metadata(METADATA_SECTION, METADATA_POST_NOTES_PENDING, false))


static func set_post_notes_pending(pending: bool) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(METADATA_SECTION, METADATA_POST_NOTES_PENDING, pending)


#* The tools not opened since the install (marked in the dock's drop-down):
static func unopened_tools() -> Array:
	var names = EditorInterface.get_editor_settings().get_project_metadata(METADATA_SECTION, METADATA_UNOPENED_TOOLS, [])
	if names is Array:
		return names
	return []


static func set_unopened_tools(names: Array) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(METADATA_SECTION, METADATA_UNOPENED_TOOLS, names.duplicate())


#* Whether a Candy_DE folder exists at all, installed by Candy Wizard or not:
static func candy_de_folder_exists() -> bool:
	return DirAccess.dir_exists_absolute(CANDY_DE_FOLDER)


#==============================================================================
#  SCRIPT VARIABLES
#==============================================================================

#? Wizard answers replace the literal of "var <name> = <value>" lines (a string, number,
#? true, false or null). The rest of the line is kept.

#* Matches a variable's declaration; group 1 is its literal value:
#! Same pattern as Release_Tools/Build_Release.gd's _variable_literal().
static func variable_regex(variable: String) -> RegEx:
	return RegEx.create_from_string(r'(?m)^var\s+' + variable + r'(?:\s*:\s*\w+)?\s*:?=\s*("(?:[^"\\\n]|\\.)*"|-?\d+(?:\.\d+)?|true|false|null)')


#* A script's text with a variable's value replaced, or "" if the variable can't be found:
static func set_variable(text: String, variable: String, value: Variant) -> String:
	if not variable.is_valid_identifier():
		return ""
	var found := variable_regex(variable).search(text)
	if found == null:
		return ""
	#? JSON gives every number as a float: keep an int variable an int.
	var current = str_to_var(found.get_string(1))
	if typeof(current) == TYPE_INT and typeof(value) == TYPE_FLOAT:
		value = int(value)
	return text.substr(0, found.get_start(1)) + var_to_str(value) + text.substr(found.get_end(1))


#==============================================================================
#  INPUT EVENTS
#==============================================================================

#* An input event rebuilt from the manifest's plain data, or null for an unknown type:
#! Reads what Release_Tools/Build_Release.gd's _event_to_data() writes.
static func event_from_data(data: Dictionary) -> InputEvent:
	var event: InputEvent = null
	match data.get("type", ""):
		"key":
			var key_event := InputEventKey.new()
			key_event.keycode = int(data.get("keycode", 0)) as Key
			key_event.physical_keycode = int(data.get("physical_keycode", 0)) as Key
			key_event.key_label = int(data.get("key_label", 0)) as Key
			key_event.unicode = int(data.get("unicode", 0))
			event = key_event
		"mouse_button":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(data.get("button_index", 0)) as MouseButton
			event = mouse_event
		"joypad_button":
			var button_event := InputEventJoypadButton.new()
			button_event.button_index = int(data.get("button_index", 0)) as JoyButton
			event = button_event
		"joypad_motion":
			var motion_event := InputEventJoypadMotion.new()
			motion_event.axis = int(data.get("axis", 0)) as JoyAxis
			motion_event.axis_value = float(data.get("axis_value", 0.0))
			event = motion_event
		_:
			return null
	#? -1 is "all devices", which the Input Map uses for its events.
	event.device = int(data.get("device", -1))
	if event is InputEventWithModifiers:
		event.shift_pressed = bool(data.get("shift", false))
		event.ctrl_pressed = bool(data.get("ctrl", false))
		event.alt_pressed = bool(data.get("alt", false))
		event.meta_pressed = bool(data.get("meta", false))
		event.command_or_control_autoremap = bool(data.get("command_or_control_autoremap", false))
	return event


#==============================================================================
#  FILES
#==============================================================================

#* Deletes a folder and everything in it. Returns false if something couldn't be removed:
#! Only for folders Candy Wizard created itself.
static func remove_folder(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return not DirAccess.dir_exists_absolute(path)
	dir.include_hidden = true
	var removed_all := true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var entry_path := path.path_join(entry)
		if dir.current_is_dir():
			if not remove_folder(entry_path):
				removed_all = false
		elif DirAccess.remove_absolute(entry_path) != OK:
			removed_all = false
		entry = dir.get_next()
	dir.list_dir_end()
	if DirAccess.remove_absolute(path) != OK:
		removed_all = false
	return removed_all


#* Writes a file, making its folder. Returns an error message, or "":
static func write_file(path: String, bytes: PackedByteArray) -> String:
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


#* Copies a file, making the target's folder. Returns an error message, or "":
static func copy_file(from: String, to: String) -> String:
	var dir_error := DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	if dir_error != OK:
		return "Couldn't create the folder %s (%s)." % [to.get_base_dir(), error_string(dir_error)]
	var error := DirAccess.copy_absolute(from, to)
	if error != OK:
		return "Couldn't copy %s to %s (%s)." % [from, to, error_string(error)]
	return ""


#* Removes a file and its .uid / .import. Returns false if one couldn't be removed:
static func remove_with_generated(path: String) -> bool:
	var removed_all := true
	for candidate in [path, path + ".uid", path + ".import"]:
		if FileAccess.file_exists(candidate) and DirAccess.remove_absolute(candidate) != OK:
			removed_all = false
	return removed_all


#* Removes the now-empty folders (inside base) that held the given files, deepest first:
static func remove_emptied_folders(base: String, paths: PackedStringArray) -> void:
	for relative in paths:
		var folder := relative.get_base_dir()
		while folder != "":
			if not remove_if_empty(base.path_join(folder)) and DirAccess.dir_exists_absolute(base.path_join(folder)):
				break
			folder = folder.get_base_dir()


#* Removes a folder if nothing is in it, hidden files included. Returns whether it was removed:
static func remove_if_empty(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.include_hidden = true
	if not dir.get_files().is_empty() or not dir.get_directories().is_empty():
		return false
	return DirAccess.remove_absolute(path) == OK


#* Whether a path from outside stays inside the folder it's joined to:
static func is_safe_relative_path(path: String) -> bool:
	if path == "" or path.begins_with("/") or "\\" in path or ":" in path:
		return false
	for part in path.split("/"):
		if part == "" or part == "." or part == "..":
			return false
	return true


#* A record's file list (path -> entry) without paths leaving the folder they're joined to:
#? Records are project files, which may come from someone else.
static func safe_record_files(listed: Variant, prefix: String = "") -> Dictionary:
	var safe := {}
	if not listed is Dictionary:
		return safe
	for path in listed:
		if is_safe_relative_path(String(path)) and String(path).begins_with(prefix):	#/ prefix: e.g. "Candy_DE/", or ""
			safe[path] = listed[path]
	return safe


#* Opens a web page, only http(s):
#? A notes link must never open a local file or program.
static func open_web_link(address: String) -> void:
	var link := address.strip_edges()
	if link.to_lower().begins_with("https://") or link.to_lower().begins_with("http://"):
		OS.shell_open(link)
	else:
		push_warning("Candy Wizard: the link \"%s\" wasn't opened (only web links are)." % link)


#* Has Godot scan the project's files, and waits until it's done:
static func scan_filesystem(tree: SceneTree) -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	file_system.scan()
	await tree.process_frame
	while file_system.is_scanning():
		await tree.process_frame
	await tree.process_frame


#^ Quiet time (ms) before when_imported() counts Godot's work as done:
#? Godot starts importing new files a moment after its scan ends, and is_scanning() is false while it imports.
const IMPORT_QUIET_MSEC := 1000
#^ Longest wait (ms), should an import never report its end:
const IMPORT_MAX_MSEC := 600000


#* Calls done once Godot has finished scanning and importing the project's files:
#? A Callable rather than an await, so a window closed meanwhile isn't resumed (done is then invalid).
static func when_imported(tree: SceneTree, done: Callable) -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	var state := {"importing": false}
	var on_start := func(_files: PackedStringArray) -> void:
		state["importing"] = true
	var on_end := func(_files: PackedStringArray) -> void:
		state["importing"] = false
	file_system.resources_reimporting.connect(on_start)
	file_system.resources_reimported.connect(on_end)
	var started := Time.get_ticks_msec()
	var quiet_since := started
	while Time.get_ticks_msec() - started < IMPORT_MAX_MSEC:
		await tree.process_frame
		var now := Time.get_ticks_msec()
		if file_system.is_scanning() or state["importing"]:
			quiet_since = now
		elif now - quiet_since >= IMPORT_QUIET_MSEC:
			break
	file_system.resources_reimporting.disconnect(on_start)
	file_system.resources_reimported.disconnect(on_end)
	if done.is_valid():
		done.call()


#* "2026-09-29 23:35:42" as "on 29 Sep 2026 at 23:35":
static func readable_date(date_time: String) -> String:
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var parts := date_time.split(" ")
	var date := parts[0].split("-")
	if date.size() != 3:
		return "on " + date_time
	var text := "on %d %s %s" % [date[2].to_int(), months[clampi(date[1].to_int() - 1, 0, 11)], date[0]]
	if parts.size() > 1:
		text += " at " + parts[1].substr(0, 5)
	return text


#* A size in bytes, readable ("1.4 MB"):
static func readable_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / (1024.0 * 1024.0))
