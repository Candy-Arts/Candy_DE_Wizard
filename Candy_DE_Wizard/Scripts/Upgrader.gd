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
const ScriptFunctions = preload("Script_Functions.gd")
const UpgradeData = preload("Upgrade_Data.gd")
const Style = preload("UI_Style.gd")
const Installer = preload("Installer.gd")
const VoiceFiles = preload("Voice_Files.gd")
const CodeScan = preload("Code_Scan.gd")
const SettingsReview = preload("Settings_Review.gd")
#^ 1.1.3's (and 1.0's) install scripts, which developers ran from the project's root: not theirs to update.
const OLD_INSTALL_SCRIPTS := ["res://Candy_DE_Install.gd", "res://1_0_to_1_1_patcher.gd"]

const FROM_VERSION := "1.1.3"
const TO_VERSION := "1.2.0"
#^ In Candy Wizard's folder:
const DATA_PATH := "Data/Candy_DE_1.1.3.json"
const DATA_FORMAT := 2

#^ Where the 1.1.3 install goes, and the upgrade's report:
const ASIDE_FOLDER := "res://Candy_DE/.Install/Candy_DE_1.1.3"
const REPORT_PATH := "res://Candy_DE/.Install/Upgrade_Report.txt"
#^ Its copy in BBCode, for the Upgrade Report window (Report_Window.gd):
const REPORT_BBCODE_PATH := "res://Candy_DE/.Install/Upgrade_Report_BBCode.txt"
#^ The BBCode copy's title and headings, against the editor's font size:
const REPORT_TITLE_SCALE := 1.6
const REPORT_HEADING_SCALE := 1.3
#^ In ASIDE_FOLDER - copies of the scripts and scenes of custom folders, by their res:// path:
const CUSTOM_COPIES := "Custom_Folders"
#^ 1.1.3's voice layout, for 1.2's voice_path:
const VOICE_PATH := "{actor}/{conversation}/{block}"

#^ In the 1.1.3 install folder:
const PROPERTIES_SCRIPT := "Scripts/User_Data/Candy_Properties.gd"
const DATABASE_SCRIPT := "Scripts/User_Data/Candy_Database.gd"
const LOCALIZATIONS_SCRIPT := "Scripts/User_Data/Candy_Localizations.gd"
const FUNCTIONS_SCRIPT := "Scripts/User_Data/Candy_Functions.gd"	#/ The candy_de autoload
#^ Files only a 1.1.3 install has together:
const INSTALL_MARKERS := ["Scripts/Candy_Engine.gd", PROPERTIES_SCRIPT, DATABASE_SCRIPT, LOCALIZATIONS_SCRIPT, FUNCTIONS_SCRIPT]

#^ The folder settings holding data (media, dialogues, exports), which moves back:
#? The other folder settings hold scenes, which the developer moves back by hand.
const DATA_FOLDER_SETTINGS := ["dialogues_folder", "portraits_folder", "busts_folder", "sprite_folder", "voice_folder",
		"background_folder", "image_folder", "video_folder", "audio_folder", "export_folder"]
#^ What stays in the set-aside copy - these folders of the install folder, and these files anywhere in it:
#? 1.2 starts with only its own scenes and scripts.
const FRESH_FOLDERS := ["Scenes", "Scripts"]
const FRESH_EXTENSIONS := ["gd", "tscn", "scn"]
#^ 1.2's one Animation_Libraries folder:
#? In background_folder, 1.1.3 kept each layer's libraries in <layer folder>/Animation_Libraries.
const LIBRARIES_FOLDER := "Animation_Libraries"
#^ Copied from custom folders into the set-aside copy (the developer may port them in place):
const CODE_EXTENSIONS := ["gd", "tscn", "scn", "tres", "res"]
#^ Files Godot keeps next to a file, which go with it:
const SIBLING_EXTENSIONS := ["uid", "import"]

#^ Where a folder setting points:
const FOLDER_DEFAULT := "default"		#/ 1.1.3's default: takes 1.2's
const FOLDER_INSIDE := "inside"			#/ A custom folder inside the install folder: same place in 1.2's (scene folders: 1.2's default)
const FOLDER_OUTSIDE := "outside"		#/ A custom folder elsewhere: stays

#^ What happens to each file of the install folder (unchanged 1.1.3 files are only counted):
const MOVED := "moved"				#/ Brought back into the new Candy_DE folder ("replaces": over 1.2's)
const LEFT := "left"				#/ A scene, a script, or in Scenes / Scripts: stays in the copy
const CONVERTED := "converted"		#/ User data: read into 1.2's settings and tables
const CODE := "code"				#/ A 1.1.3 script the developer changed: stays, its functions listed
const CLASH := "clash"				#/ Another of their files takes its place: stays in the copy
#^ What happens in custom folders:
const RENAME := "rename"			#/ A voice file in a variation folder written with ":"
const LIBRARY := "library"			#/ A BG animation library, to the shared folder
const COPY := "copy"				#/ A script or scene, copied into the set-aside copy
const ADDED := "added"				#/ 1.2's file (an animation library) the custom folder lacks

#^ Set before plan():
var package = null						#/ Package.gd: Candy DE 1.2.0, opened and verified
var install_folder := ""				#/ The 1.1.3 install folder (find_install())
var source_text := ""					#/ Where the release came from, for the record
var wizard_version := ""

#^ The plan (plan() fills it in):
var problem := ""						#/ Why the upgrade can't be made at all
var folders: Array = []					#/ [{setting, value, kind, from, to}]: the folder settings
var files: Array = []					#/ [{path, status, to}]: the install folder's files worth listing
var unchanged := 0						#/ 1.1.3 files the developer didn't change: left behind
var custom_changes: Array = []			#/ [{from, to, status}]: in custom folders
var code_changes: Array = []			#/ [{path, changed, added, removed, rest_changed}]
var voice_layout: Dictionary = {}		#/ The layout 1.2's voice files are in: {voice_folder, voice_path}
var data_writes: Dictionary = {}		#/ res:// path -> text: the user data scripts converted (Upgrade_Data.gd)
var notes: Array = []					#/ [{level, text, items}]: what the conversion says (Upgrade_Data.gd)
var code_findings: Array = []			#/ [{rule, hits}]: the developer's code and scenes using what 1.2 changed (Code_Scan.gd)
var roles_renamed := 0					#/ Role keys that lost the role symbol
var old_install_scripts: PackedStringArray = []	#/ OLD_INSTALL_SCRIPTS still in the project
var own_settings: Array = []			#/ [{scene, shown, nodes}]: settings of the developer's scenes that change (Settings_Review.gd)
var replaced_settings: Array = []		#/ The same, for 1.1.3's scenes 1.2's own replace
var behaviour: Array = []				#/ What works differently with nothing to set
var actors_converted := 0				#/ Actors whose Candy DE keys were converted
var engine: Dictionary = {}				#/ The 1.1.3 engine's settings, from its Candy_UI.tscn
var release_added: PackedStringArray = []	#/ 1.2's media files the developer didn't have (where they end up)

#^ What upgrade() did:
var report_path := ""

#^ Plan internals:
var _data: Dictionary = {}				#/ Data/Candy_DE_1.1.3.json
var _old_properties := ""				#/ The developer's Candy_Properties.gd
var _new_properties := ""				#/ 1.2.0's
var _release_files: Dictionary = {}		#/ res:// path -> sha256, of 1.2.0's files
var _targets: Dictionary = {}			#/ res:// path a file goes to -> where it comes from
var _replaced_autoloads: Dictionary = {}	#/ Autoload names pointing into the install folder now


#==============================================================================
#  FINDING 1.1.3
#==============================================================================

#* The 1.1.3 install folder ("res://Candy_DE", or another name), or "" if there's none:
static func find_install() -> String:
	var candidates: PackedStringArray = []
	#Ł Through the candy_de autoload (hand-installed, so possibly renamed):
	var autoload := "autoload/candy_de"
	if ProjectSettings.has_setting(autoload):
		var path := String(ProjectSettings.get_setting(autoload)).trim_prefix("*")
		if path.begins_with("uid://"):
			var id := ResourceUID.text_to_id(path)
			if ResourceUID.has_id(id):
				path = ResourceUID.get_id_path(id)
		var suffix := "/" + FUNCTIONS_SCRIPT
		if path.ends_with(suffix) and path.length() > ("res://" + suffix).length():
			candidates.append(path.trim_suffix(suffix))
	candidates.append(Utils.CANDY_DE_FOLDER)	#/ Else res://Candy_DE
	for folder in candidates:
		if is_install(folder):
			return folder
	return ""


#* Whether a folder holds a 1.1.3 install - its user data scripts and engine, together:
static func is_install(folder: String) -> bool:
	for marker in INSTALL_MARKERS:
		if not FileAccess.file_exists(folder.path_join(marker)):
			return false
	return true


#==============================================================================
#  PLAN
#==============================================================================

#* Works out what the upgrade does, without changing anything. Sets problem if it can't:
func plan() -> void:
	_reset()
	problem = _check()
	if problem != "":
		return
	_old_properties = FileAccess.get_file_as_string(install_folder.path_join(PROPERTIES_SCRIPT))
	_new_properties = package.read(Utils.PACKAGE_NAME + "/" + PROPERTIES_SCRIPT).get_string_from_utf8()
	var release_files: Dictionary = package.files()
	for path in release_files:
		_release_files["res://" + String(path)] = String(release_files[path].get("sha256", ""))
	_plan_folders()
	_plan_install_files()
	_plan_custom_folders()
	_plan_release_media()
	for entry in folders:
		if entry["setting"] == "voice_folder":
			voice_layout = {"voice_folder": String(entry["to"]) + "/", "voice_path": VOICE_PATH}
	_plan_conversion()
	_plan_autoloads()
	_plan_code_scan()


func _reset() -> void:
	problem = ""
	folders.clear()
	files.clear()
	unchanged = 0
	custom_changes.clear()
	code_changes.clear()
	voice_layout = {}
	data_writes.clear()
	notes.clear()
	code_findings.clear()
	old_install_scripts.clear()
	own_settings.clear()
	replaced_settings.clear()
	behaviour.clear()
	roles_renamed = 0
	actors_converted = 0
	engine = {}
	release_added.clear()
	_replaced_autoloads.clear()
	_data = {}
	_release_files.clear()
	_targets.clear()


func _check() -> String:
	if package == null or package.version() != TO_VERSION:
		return "The upgrade installs Candy DE %s, and must be given that release." % TO_VERSION
	var data_path := Utils.wizard_folder().path_join(DATA_PATH)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if not parsed is Dictionary or int(parsed.get("format", 0)) != DATA_FORMAT or String(parsed.get("version", "")) != FROM_VERSION:
		return "Candy Wizard's data on Candy DE %s (%s) is missing or damaged: reinstall Candy Wizard." % [FROM_VERSION, data_path]
	_data = parsed
	if install_folder == "" or not is_install(install_folder):
		return "This project has no Candy DE %s install to upgrade." % FROM_VERSION
	if install_folder != Utils.CANDY_DE_FOLDER and Utils.candy_de_folder_exists():
		return "Candy DE %s is installed in %s, and this project also has a %s folder, where %s would be installed. Move or rename %s first." % [
				FROM_VERSION, install_folder, Utils.CANDY_DE_FOLDER, TO_VERSION, Utils.CANDY_DE_FOLDER]
	return ""


#* Where each folder setting points, and where its files go:
func _plan_folders() -> void:
	var shipped: Dictionary = _data.get("folders", {})
	for setting in shipped:
		var default_path := install_folder.path_join(String(shipped[setting]))
		var value := _setting(_old_properties, setting)
		if value == "":
			#? A deleted setting: 1.1.3's default is the closest to what they had.
			value = default_path
		var from := value.trim_suffix("/")
		var entry := {"setting": setting, "value": value, "from": from}
		#? An install renamed by hand may still point into res://Candy_DE:
		if from == default_path or from == Utils.CANDY_DE_FOLDER.path_join(String(shipped[setting])):
			entry["kind"] = FOLDER_DEFAULT
			var new_default := _setting(_new_properties, setting).trim_suffix("/")
			#? 1.2's default only inside Candy_DE (1.2's export_folder is in user://; their exports stay):
			if new_default.begins_with(Utils.CANDY_DE_FOLDER + "/"):
				entry["to"] = new_default
			else:
				entry["to"] = Utils.CANDY_DE_FOLDER.path_join(String(shipped[setting]))
		elif from == install_folder or from.begins_with(install_folder + "/"):
			entry["kind"] = FOLDER_INSIDE
			if not setting in DATA_FOLDER_SETTINGS:
				#? A scene folder's scenes stay in the copy, so it takes 1.2's default:
				entry["to"] = _setting(_new_properties, setting).trim_suffix("/")
				entry["reset"] = true
			elif from == install_folder:
				entry["to"] = Utils.CANDY_DE_FOLDER
			else:
				entry["to"] = Utils.CANDY_DE_FOLDER.path_join(from.trim_prefix(install_folder + "/"))
		else:
			entry["kind"] = FOLDER_OUTSIDE
			entry["to"] = from
		folders.append(entry)


#* A setting's value in a Candy_Properties.gd, or "" if it has none (or isn't a String):
static func _setting(text: String, setting: String) -> String:
	var found := Utils.variable_regex(setting).search(text)
	if found == null:
		return ""
	var value = str_to_var(found.get_string(1))
	if value is String:
		return value
	return ""


#* Sorts every file of the install folder:
func _plan_install_files() -> void:
	var shipped_files: Dictionary = _data.get("files", {})
	var scripts: Dictionary = _data.get("scripts", {})
	for relative in _main_files(install_folder):
		var path := install_folder.path_join(relative)
		var shipped := shipped_files.has(relative)
		var same := shipped and String(shipped_files[relative].get("sha256", "")) == Utils.content_hash(relative, FileAccess.get_file_as_bytes(path))
		if shipped and not same and shipped_files[relative].has("resource_sha256"):
			same = String(shipped_files[relative]["resource_sha256"]) == Utils.resource_hash(FileAccess.get_file_as_bytes(path), [install_folder + "/"])

		if relative == PROPERTIES_SCRIPT:
			#? Always: settings that are new in 1.2 get values keeping 1.1.3's behaviour.
			_add_file(path, CONVERTED, "")
		elif relative == DATABASE_SCRIPT or relative == LOCALIZATIONS_SCRIPT:
			if same:
				unchanged += 1
			else:
				_add_file(path, CONVERTED, "")
		elif same:
			unchanged += 1
		elif shipped and relative.get_extension() == "gd":
			_add_file(path, CODE, "")
			_add_code_changes(path, scripts.get(relative, {}))
		elif _stays(relative):
			_add_file(path, LEFT, "")
		elif data_folder(path) != null:
			_plan_move(path, _data_target(path))
		else:
			_plan_move(path, Utils.CANDY_DE_FOLDER.path_join(relative))


#* Whether a file of the install folder stays in the copy:
#? In Scenes / Scripts, in a custom scene folder inside the install folder (with what its scenes use), or any scene or script.
func _stays(relative: String) -> bool:
	if relative.get_slice("/", 0) in FRESH_FOLDERS or relative.get_extension() in FRESH_EXTENSIONS:
		return true
	var path := install_folder.path_join(relative)
	for entry in folders:
		if entry.get("reset", false) and path.begins_with(String(entry["from"]) + "/"):
			return true
	return false


#* Plans the custom folders:
#? Their scripts and scenes are copied; their voice files and BG libraries get 1.2's places, where they are.
func _plan_custom_folders() -> void:
	var walked := {}
	for entry in folders:
		if entry["kind"] != FOLDER_OUTSIDE:
			continue
		var folder_path := String(entry["from"])
		#? Only folders in the project, and not the project itself.
		if not folder_path.begins_with("res://") or folder_path.trim_prefix("res://") == "":
			continue
		for relative in _main_files(folder_path):
			var path := folder_path.path_join(relative)
			if walked.has(path):
				continue
			walked[path] = true
			if relative.get_extension() in CODE_EXTENSIONS:
				custom_changes.append({"from": path, "to": ASIDE_FOLDER.path_join(CUSTOM_COPIES).path_join(path.trim_prefix("res://")), "status": COPY})
			#? A scene folder's files only get copied.
			if data_folder(path) == null:
				continue
			var target := _data_target(path)
			if target == path:
				continue
			var status := RENAME
			if data_folder(path)["setting"] == "background_folder":
				status = LIBRARY
			if FileAccess.file_exists(target) or _targets.has(target):
				custom_changes.append({"from": path, "to": target, "status": CLASH})
			else:
				_targets[target] = path
				custom_changes.append({"from": path, "to": target, "status": status})


#* The data folder setting a file is in ({setting, from, to...}), the innermost when nested, or null:
func data_folder(path: String) -> Variant:
	var found = null
	for entry in folders:
		if not entry["setting"] in DATA_FOLDER_SETTINGS:
			continue
		var from := String(entry["from"])
		if path.begins_with(from + "/") and (found == null or from.length() > String(found["from"]).length()):
			found = entry
	return found


#* Where a file of a data folder goes - the folder's new place:
#? Voice variation folders are written with "=", and BG libraries go in the shared folder.
func _data_target(path: String) -> String:
	var entry: Dictionary = data_folder(path)
	var parts := path.trim_prefix(String(entry["from"]) + "/").split("/")
	if entry["setting"] == "voice_folder":
		#? 1.1.3 named variation folders with ":" tags (Default_S:F), 1.2 with "=".
		for index in parts.size() - 1:
			parts[index] = parts[index].replace(":", "=")
	elif entry["setting"] == "background_folder" and parts.size() >= 3 and parts[1] == LIBRARIES_FOLDER:
		parts.remove_at(0)
	return String(entry["to"]).path_join("/".join(parts))


#* A file brought back into Candy_DE, kept over 1.2's file of the same path:
#? Not if another of their files takes the place first.
func _plan_move(path: String, target: String) -> void:
	if _targets.has(target):
		_add_file(path, CLASH, target)
		return
	if _release_files.has(target) and _release_files[target] == Utils.content_hash(target, FileAccess.get_file_as_bytes(path)):
		#? The same file as 1.2's: nothing to bring back.
		unchanged += 1
		return
	_targets[target] = path
	_add_file(path, MOVED, target)
	if _release_files.has(target):
		files.back()["replaces"] = true


#* 1.2's media files (its animation libraries):
#? Kept where the developer has a file of the same name; otherwise added, also into a custom folder, where the folder setting points.
func _plan_release_media() -> void:
	for entry in folders:
		if not entry["setting"] in DATA_FOLDER_SETTINGS:
			continue
		var new_default := _setting(_new_properties, entry["setting"]).trim_suffix("/")
		if new_default == "":
			continue
		for path in _release_files:
			#? Not a folder's placeholder (.gitkeep).
			if not String(path).begins_with(new_default + "/") or String(path).get_file().begins_with("."):
				continue
			var target := String(entry["to"]).path_join(String(path).trim_prefix(new_default + "/"))
			if _targets.has(target):
				continue
			if target == path:
				release_added.append(path)
			elif not FileAccess.file_exists(target):
				_targets[target] = path
				custom_changes.append({"from": path, "to": target, "status": ADDED, "root": entry["to"]})
				release_added.append(target)


func _add_file(path: String, status: String, target: String) -> void:
	files.append({"path": path, "status": status, "to": target})


func _add_code_changes(path: String, original: Dictionary) -> void:
	var result := ScriptFunctions.changes(original, FileAccess.get_file_as_string(path))
	result["path"] = path
	code_changes.append(result)


#* A folder's files, relative to it, sorted, without siblings() (orphan .uid / .import too):
static func _main_files(folder_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	_list_files(folder_path, "", found)
	var main: PackedStringArray = []
	for relative in found:
		if not relative.get_extension() in SIBLING_EXTENSIONS:
			main.append(relative)
	main.sort()
	return main


static func _list_files(folder_path: String, relative_folder: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(folder_path.path_join(relative_folder))
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var relative := entry
		if relative_folder != "":
			relative = relative_folder.path_join(entry)
		if dir.current_is_dir():
			_list_files(folder_path, relative, found)
		else:
			found.append(relative)
		entry = dir.get_next()
	dir.list_dir_end()


#* The .uid and .import files that go with a file:
static func siblings(path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for extension in SIBLING_EXTENSIONS:
		if FileAccess.file_exists(path + "." + extension):
			found.append(path + "." + extension)
	return found


#* Converts the user data (Upgrade_Data.gd) against 1.2.0's scripts as the install writes them:
#? The review shows what it says.
func _plan_conversion() -> void:
	var converter := UpgradeData.new()
	converter.old_properties = FileAccess.get_file_as_string(install_folder.path_join(PROPERTIES_SCRIPT))
	for entry in files_with(CONVERTED):
		if entry["path"] == install_folder.path_join(DATABASE_SCRIPT):
			converter.old_database = FileAccess.get_file_as_string(entry["path"])
		elif entry["path"] == install_folder.path_join(LOCALIZATIONS_SCRIPT):
			converter.old_localizations = FileAccess.get_file_as_string(entry["path"])
	var scripts: Dictionary = _data.get("scripts", {})
	converter.known_variables = {
		"properties": scripts.get(PROPERTIES_SCRIPT, {}).get("variables", []),
		"database": scripts.get(DATABASE_SCRIPT, {}).get("variables", []),
		"localizations": scripts.get(LOCALIZATIONS_SCRIPT, {}).get("variables", []),
	}
	converter.folder_values = _folder_values()
	var ui_scene := install_folder.path_join("Scenes/Candy_UI.tscn")
	if FileAccess.file_exists(ui_scene):
		engine = UpgradeData.engine_settings(FileAccess.get_file_as_string(ui_scene))
	else:
		engine = UpgradeData.ENGINE_DEFAULTS.duplicate()
	converter.engine = engine
	var user_data := Utils.PACKAGE_NAME + "/Scripts/User_Data/"
	var current := {}
	for path in package.files():
		if String(path).begins_with(user_data) and String(path).ends_with(".gd"):
			current["res://" + String(path)] = package.read(path).get_string_from_utf8()
	#? Candy_Properties.gd as the install writes it, with the voice_path answer.
	if current.has(UpgradeData.PROPERTIES_PATH):
		var answered := Utils.set_variable(current[UpgradeData.PROPERTIES_PATH], "voice_path", VOICE_PATH)
		if answered != "":
			current[UpgradeData.PROPERTIES_PATH] = answered
	converter.current = current
	converter.convert_data()
	data_writes = converter.written
	notes = converter.notes
	roles_renamed = converter.roles_renamed
	actors_converted = converter.actors_converted
	#? Functions the developer added to the user data scripts: code to port.
	for script in [PROPERTIES_SCRIPT, DATABASE_SCRIPT, LOCALIZATIONS_SCRIPT]:
		var changes := ScriptFunctions.changes(scripts.get(script, {}), FileAccess.get_file_as_string(install_folder.path_join(script)))
		if not changes["added"].is_empty() or not changes["changed"].is_empty():
			changes["rest_changed"] = false
			changes["path"] = install_folder.path_join(script)
			code_changes.append(changes)


#* Searches the developer's own scripts and scenes for what 1.2 changed: the project's, and
#* their own ones in the install folder (which stay in the 1.1.3 copy, shown there).
func _plan_code_scan() -> void:
	var role_symbol := _setting(_old_properties, "role_symbol")
	if role_symbol == "":
		role_symbol = "°"
	var rules := CodeScan.load_rules(role_symbol)
	var skipped := PackedStringArray([install_folder, Utils.CANDY_DE_FOLDER, Utils.wizard_folder()])
	var paths: PackedStringArray = []
	if rules.is_empty():
		push_warning("Candy Wizard: no rules to search your code with (%s)." % CodeScan.RULES_PATH)
	for path in CodeScan.project_files(skipped):
		if path in OLD_INSTALL_SCRIPTS:
			old_install_scripts.append(path)
		else:
			paths.append(path)
	var shown := {}
	var shipped: Dictionary = _data.get("files", {})
	for entry in files_with(LEFT):
		var path := String(entry["path"])
		if path.get_extension().to_lower() in CodeScan.EXTENSIONS and not shipped.has(_relative(path)):
			paths.append(path)
			shown[path] = _aside_path(path)
	code_findings = CodeScan.scan(rules, paths, shown)
	_plan_settings(paths, shown)


#* Settings of Candy DE's nodes that 1.2 renamed, removed or gives another value: in the developer's
#* scenes, and in 1.1.3's that 1.2's own replace.
func _plan_settings(paths: PackedStringArray, shown: Dictionary) -> void:
	var review := SettingsReview.new()
	review.install_folder = install_folder
	review.old_scripts = _data.get("scripts", {})
	review.shipped = _data.get("files", {})
	review.package = package
	var own: Array = []
	for path in paths:
		if path.get_extension().to_lower() == "tscn":
			own.append([path, shown.get(path, path)])
	own_settings = review.review_own(own)
	var replaced: PackedStringArray = []
	var changed := {}
	for entry in files_with(LEFT):
		changed[_relative(entry["path"])] = true
	for relative in review.shipped:
		if String(relative).get_extension() != "tscn" or not FileAccess.file_exists(install_folder.path_join(relative)):
			continue
		if String(relative).get_file() == "Candy_Default.tscn" and not changed.has(relative):
			continue
		replaced.append(relative)
	replaced_settings = review.review_replaced(replaced)
	behaviour = review.behaviour()


#* The folder settings 1.2's Candy_Properties.gd needs changed (setting -> value):
#? A custom folder keeps the developer's value as written; one inside the install folder keeps its trailing "/" if it had one.
func _folder_values() -> Dictionary:
	var values := {}
	for entry in folders:
		var new_default := _setting(_new_properties, entry["setting"]).trim_suffix("/")
		if entry["to"] == new_default:
			continue
		if entry["kind"] == FOLDER_OUTSIDE:
			values[entry["setting"]] = entry["value"]
		elif String(entry["value"]).ends_with("/"):
			values[entry["setting"]] = String(entry["to"]) + "/"
		else:
			values[entry["setting"]] = entry["to"]
	return values


#* The autoloads now pointing into the 1.1.3 install folder (candy_de, maybe candy_ui):
#? The install replaces them, and the record mustn't put them back if Candy DE is removed.
func _plan_autoloads() -> void:
	for entry in package.manifest.get("autoloads", []):
		var key := "autoload/" + String(entry.get("name", ""))
		if not ProjectSettings.has_setting(key):
			continue
		var path := String(ProjectSettings.get_setting(key)).trim_prefix("*")
		if path.begins_with("uid://"):
			var id := ResourceUID.text_to_id(path)
			if ResourceUID.has_id(id):
				path = ResourceUID.get_id_path(id)
		if path.begins_with(install_folder + "/"):
			_replaced_autoloads[String(entry.get("name", ""))] = true


#==============================================================================
#  UPGRADE
#==============================================================================

#^ What to know when moving scenes back, for the report: [title, text], `code` in backticks.
const MOVE_BACK_CHECKLIST := [
	["Keep their UIDs.", "Move each file with its `.uid` or `.import` file (beside it), so it keeps its UID: what uses it then finds it."],
	["Keep 1.2's own scenes.", "1.2's `Candy_UI.tscn`, `Testing_Scene.tscn` and `Default.tscn` scenes work as they are: bring your changes into them, rather than putting your 1.1.3 versions over them."],
	["Give your scenes 1.2's scripts.", "1.1.3's no longer work. A scene whose script kept its name in 1.2 (`Candy_Engine.gd`, `Choice_Menu.gd`, the media players, the bubbles...) gets 1.2's on its own, by its path. Renamed scripts: `Dialogue_Box.gd` -> `Box_UI.gd`, `Subtitles.gd` -> `Subtitles_UI.gd`, `Backgrounds.gd` -> `BG_UI.gd`, `Bust_Scene.gd` -> `VN_UI.gd`, `History_Display.gd` -> `History_UI.gd`, `Input.gd` -> `Input_UI/Input_Text.gd`. `Portrait.gd` is merged into `Box_UI.gd`; `BG_Player.gd` and `Bust_Player.gd` are gone."],
	["Note your settings first.", "When Godot opens a 1.1.3 scene with 1.2's script, it drops the settings 1.2's script doesn't have, and saving the scene loses them (the 1.1.3 copy keeps them)."],
	["Portraits.", "The portrait is part of the dialogue box: put your portrait nodes under it (or point its portrait exports at them), and set `portrait_area` to the node shown and hidden with the portrait."],
	["Voice players.", "Every UI element that displays spoken lines (dialogue box, subtitles, speech and bark bubbles) needs its own voice player: an `AudioStreamPlayer` (2D or 3D for bubbles) with `Voice_Player.gd`, assigned to `voice_node`. Without one, it plays no voice. The Voice mode's player moved to `ui_elements_paths[\"voice_player_path\"]`."],
	["Text nodes.", "`dialogue_node` and `speaker_node` must be RichTextLabels. Text and speaker colours are now BBCode wraps (`text_bbcode`, `speaker_bbcode`)."],
	["The Chat.", "It was remade (`Chat_Box`, `Chat_Channel`, `Chat_Line`): a 1.1.3 chat scene can't be converted. Build yours from 1.2's."],
	["Engine settings.", "Some were renamed or changed type: `media_players_locations` -> `media_players_paths`, `cs_locations` -> `cs_paths`, `portrait_mode` -> `box_portrait_mode`, `bubble_exempt_mode` -> `bubbles_exempt_mode`; `dialogue_mode`, `text_to_speech` and `tts_advanced_fallback` are names now. Set them again on your engine nodes, including in scenes outside Candy_DE."],
	["Defaults.", "Backgrounds' and busts' `default_z` (1.1.3: 100), frame rates (1.1.3: backgrounds 1 fps for frame folders, 10 for spritesheets; portraits 1 and 8). Set the 1.1.3 values on your scenes if they relied on them."],
]

#* The scenes and scripts open in the editor that the upgrade moves, copies or replaces:
#? They must be closed first: saving one afterwards would write it back where it was.
func open_files() -> PackedStringArray:
	var touched := {}
	for entry in custom_changes:
		touched[entry["from"]] = true
	var found: PackedStringArray = []
	for scene_path in EditorInterface.get_open_scenes():
		if scene_path.begins_with(install_folder + "/") or touched.has(scene_path):
			found.append(scene_path)
	for script in EditorInterface.get_script_editor().get_open_scripts():
		if script.resource_path.begins_with(install_folder + "/") or touched.has(script.resource_path):
			found.append(script.resource_path)
	return found


#* Upgrades 1.1.3 to 1.2.0. Returns an error message, or "":
#? If a step fails, everything is put back as it was.
func upgrade(tree: SceneTree) -> String:
	plan()
	if problem != "":
		return problem
	var journal := []
	var error := await _apply(tree, journal)
	if error != "":
		progress.emit(0.5, "Putting everything back…")
		var failures := _roll_back(journal)
		await Utils.scan_filesystem(tree)
		if failures.is_empty():
			return error + " Nothing was changed: everything was put back as it was."
		return "%s Some files couldn't be put back (%s): take them from your backup." % [error, ", ".join(failures)]

	progress.emit(0.9, "Letting Godot scan the files…")
	await Utils.scan_filesystem(tree)
	var record_error := _update_record()
	_write_report()
	if record_error != "":
		return record_error
	progress.emit(1.0, "Done.")
	return ""


#* Every step of the upgrade, each noted in journal so it can be undone:
func _apply(tree: SceneTree, journal: Array) -> String:
	#? Godot must ignore the 1.1.3 files from now on: its scenes have 1.2's UIDs.
	progress.emit(0.0, "Setting Candy DE %s aside…" % FROM_VERSION)
	for marker in [".gdignore", ".gitignore"]:
		var marker_path := install_folder.path_join(marker)
		if FileAccess.file_exists(marker_path):
			continue
		var marker_file := FileAccess.open(marker_path, FileAccess.WRITE)
		if marker_file == null:
			return "Couldn't write %s (%s)." % [marker_path, error_string(FileAccess.get_open_error())]
		if marker == ".gitignore":
			#? Git keeps 1.1.3 in the project's history already: the copy stays out of it.
			marker_file.store_string("*\n")
		marker_file.close()
		journal.append({"type": "created", "path": marker_path})
	var temporary := _free_folder("res://Candy_DE_%s" % FROM_VERSION)
	var error := _move_folder(install_folder, temporary)
	if error != "":
		return error
	journal.append({"type": "folder_moved", "from": install_folder, "to": temporary})

	progress.emit(0.05, "Installing Candy DE %s…" % TO_VERSION)
	var installer = Installer.new()
	installer.package = package
	installer.answers = _answers()
	installer.source_text = source_text
	installer.wizard_version = wizard_version
	installer.notes_flow = Utils.NOTES_UPDATE
	installer.progress.connect(func(fraction: float, message: String) -> void: progress.emit(0.05 + fraction * 0.45, message))
	journal.append({"type": "installed", "installer": installer})
	error = await installer.install(tree)
	if error != "":
		return error

	error = _move_folder(temporary, ASIDE_FOLDER)
	if error != "":
		return error
	journal.append({"type": "folder_moved", "from": temporary, "to": ASIDE_FOLDER})

	progress.emit(0.5, "Converting your data…")
	for path in data_writes:
		error = _write(path, String(data_writes[path]).to_utf8_buffer())
		if error != "":
			return error
	if not voice_layout.is_empty():
		error = VoiceFiles.record_layout(voice_layout)
		if error != "":
			return error

	var total := maxi(files.size() + custom_changes.size(), 1)
	var count := 0
	for entry in files:
		var from := _aside_path(entry["path"])
		match String(entry["status"]):
			MOVED:
				if entry.get("replaces", false):
					#? Theirs is kept over 1.2's:
					error = _remove_with_siblings(entry["to"])
					if error != "":
						return error
				error = _move(from, entry["to"])
				if error != "":
					return error
				journal.append({"type": "moved", "from": from, "to": entry["to"]})
		count += 1
		if count % 20 == 0:
			progress.emit(0.55 + 0.3 * count / total, "Bringing your files back… %d / %d" % [count, total])
			await tree.process_frame

	for entry in custom_changes:
		match String(entry["status"]):
			RENAME, LIBRARY:
				error = _move(entry["from"], entry["to"])
				if error != "":
					return error
				journal.append({"type": "moved", "from": entry["from"], "to": entry["to"]})
			COPY:
				error = _copy(entry["from"], entry["to"])
				if error != "":
					return error
				journal.append({"type": "created", "path": entry["to"], "root": ASIDE_FOLDER})
			ADDED:
				#? From where the install put it.
				error = _copy(entry["from"], entry["to"])
				if error != "":
					return error
				journal.append({"type": "created", "path": entry["to"], "root": entry["root"]})
		count += 1
		if count % 20 == 0:
			progress.emit(0.55 + 0.3 * count / total, "Updating your custom folders… %d / %d" % [count, total])
			await tree.process_frame
	#? Variation folders renamed, layer library folders emptied: the old folders go.
	for entry in custom_changes:
		if entry["status"] == RENAME or entry["status"] == LIBRARY:
			_remove_empty_folders(String(entry["from"]).get_base_dir(), String(data_folder(entry["from"])["from"]))
	return ""


#* The install's answers - 1.1.3's voice layout:
func _answers() -> Dictionary:
	for question in package.manifest.get("questions", []):
		if String(question.get("variable", "")) == "voice_path":
			return {String(question.get("id", "")): VOICE_PATH}
	return {}


#* Undoes the journal, last first. Returns what couldn't be put back:
func _roll_back(journal: Array) -> PackedStringArray:
	var failures: PackedStringArray = []
	for index in range(journal.size() - 1, -1, -1):
		var entry: Dictionary = journal[index]
		match String(entry["type"]):
			"moved":
				if _move(entry["to"], entry["from"]) != "":
					failures.append(String(entry["from"]))
			"created":
				if DirAccess.remove_absolute(entry["path"]) != OK:
					failures.append(String(entry["path"]))
				elif entry.has("root"):
					_remove_empty_folders(String(entry["path"]).get_base_dir(), entry["root"])
			"folder_moved":
				if _move_folder(entry["to"], entry["from"]) != "":
					failures.append(String(entry["from"]))
			"installed":
				#? This upgrade created Candy_DE (the 1.1.3 files were moved back out first):
				if DirAccess.dir_exists_absolute(Utils.CANDY_DE_FOLDER) and not Utils.remove_folder(Utils.CANDY_DE_FOLDER):
					failures.append(Utils.CANDY_DE_FOLDER)
				var installer = entry["installer"]
				for change in installer.autoload_changes:
					#? One the project already had set this way stays as it was.
					if String(change["name"]) in installer.autoloads_adopted:
						continue
					var previous := String(change["previous"])
					if previous == "":
						ProjectSettings.set_setting("autoload/" + String(change["name"]), null)
					else:
						ProjectSettings.set_setting("autoload/" + String(change["name"]), previous)
				for action in installer.actions_added:
					ProjectSettings.set_setting("input/" + String(action), null)
				ProjectSettings.save()
	return failures


#* The install record, noting the upgrade:
#? The autoloads the install replaced pointed into 1.1.3, which is gone: removing Candy DE mustn't put them back.
func _update_record() -> String:
	var record := Utils.read_record()
	if record.is_empty():
		return "Candy DE %s was installed, but its install record can't be read: updates and removal won't know what it installed." % TO_VERSION
	for change in record.get("autoloads", []):
		if _replaced_autoloads.has(String(change.get("name", ""))):
			change["previous"] = ""
	record["upgraded_from"] = {
		"version": FROM_VERSION,
		"folder": install_folder,
		"date": Time.get_datetime_string_from_system(false, true),
		"aside": ASIDE_FOLDER,
	}
	var file := FileAccess.open(Utils.RECORD_PATH, FileAccess.WRITE)
	if file == null:
		return "Candy DE was upgraded, but its install record couldn't be written (%s)." % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return ""


#* A file of the install folder, where it is once set aside:
func _aside_path(path: String) -> String:
	return ASIDE_FOLDER.path_join(_relative(path))


func _relative(path: String) -> String:
	return path.trim_prefix(install_folder + "/")


#* Removes 1.2's file where the developer's is kept, with its .uid and .import:
#? Godot wrote them when the install was scanned. Renaming onto a file fails on some systems.
func _remove_with_siblings(path: String) -> String:
	for sibling in siblings(path):
		DirAccess.remove_absolute(sibling)
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		return "Couldn't replace %s with your version." % path
	return ""


#* A folder name that doesn't exist yet (base, else "base (2)"...):
static func _free_folder(base: String) -> String:
	var candidate := base
	var number := 2
	while DirAccess.dir_exists_absolute(candidate):
		candidate = "%s (%d)" % [base, number]
		number += 1
	return candidate


func _move_folder(from: String, to: String) -> String:
	var error := _make_folder(to.get_base_dir())
	if error != "":
		return error
	var move_error := DirAccess.rename_absolute(from, to)
	if move_error != OK:
		return "Couldn't move the folder %s to %s (%s)." % [from, to, error_string(move_error)]
	return ""


#* Removes a folder a move emptied, and the ones above it it empties in turn, up to root:
func _remove_empty_folders(folder_path: String, root: String) -> void:
	while folder_path.begins_with(root + "/"):
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
	for sibling in siblings(from):
		DirAccess.rename_absolute(sibling, to + "." + sibling.get_extension())
	return ""


#==============================================================================
#  REPORT
#==============================================================================

#* The report beside the install record, to come back to after the wizard: plain text
#* (REPORT_PATH), and a BBCode copy (REPORT_BBCODE_PATH) the Upgrade Report window shows.
func _write_report() -> void:
	var report: Array = []
	report.append({"kind": "title", "text": "Candy DE %s -> %s" % [FROM_VERSION, TO_VERSION]})
	report.append({"kind": "subtitle", "text": "Upgraded %s, from the %s." % [Time.get_datetime_string_from_system(false, true), _raw(source_text)]})

	report.append({"kind": "heading", "text": "Your 1.1.3 copy"})
	report.append({"kind": "list", "items": [
		_item("Your 1.1.3 install, %s, is set aside in %s." % [_code(install_folder), _code(ASIDE_FOLDER)]),
		_item("Its scenes, scripts and original user data scripts are there as they were. The files brought back into Candy_DE aren't: they were moved, not copied (listed under Done)."),
		_item("Godot ignores it (its scenes have 1.2's UIDs), and so does git: open it with your file manager."),
		_item("Delete it once you've moved back everything you need. Your backup has the whole 1.1.3 project."),
	]})

	var tasks: Array = []
	var dialogues := _moved_from_setting("dialogues_folder")
	if dialogues > 0:
		tasks.append(_task("Convert your dialogues", [_part("%d file(s) were moved unconverted: 1.2 reads 1.1.3 dialogues differently. Candy Wizard's Dialogue Converter tool converts them (Convert 1.1 Dialogues...), with the symbols and settings of the 1.1.3 copy; so does Candy Dialogue Creator (Edit > Dialogue Converter...)." % dialogues)]))
	var left := files_with(LEFT) + files_with(CODE)
	if not left.is_empty():
		var paths: Array = []
		for entry in left:
			paths.append(_item(_code(_relative(entry["path"]))))
		var checklist: Array = []
		for entry in MOVE_BACK_CHECKLIST:
			checklist.append(_item(entry[1], [], entry[0]))
		tasks.append(_task("Move back the scenes and scripts you need", [
			_part("1.2 starts with only its own scenes and scripts. Yours, and the 1.1.3 ones you changed, are in the 1.1.3 copy:", paths),
			_part("What to know when moving them back:", checklist),
		]))
	for entry in folders:
		if entry.get("reset", false):
			tasks.append(_task("Set %s again" % _code(entry["setting"]), [_part("It pointed at %s, whose scenes are in the 1.1.3 copy: it's 1.2's %s now. Set it again once you've moved your scenes back." % [_code(entry["from"]), _code(entry["to"])])]))
	if not code_changes.is_empty():
		var scripts: Array = []
		for entry in code_changes:
			var details: Array = []
			for kind in ["changed", "added", "removed"]:
				if not entry[kind].is_empty():
					var names: PackedStringArray = []
					for function_name in entry[kind]:
						names.append(_code(function_name))
					details.append(_item(", ".join(names), [], kind.capitalize() + ":"))
			if entry["rest_changed"]:
				details.append(_item("Changed outside its functions (variables, constants...)."))
			scripts.append(_item(_code(_relative(entry["path"])), details))
		tasks.append(_task("Redo your changes to Candy DE's code", [_part("Your 1.1.3 versions are in the 1.1.3 copy.", scripts)]))
	var checks: Array = []
	for note in notes:
		if note["level"] == UpgradeData.CHECK:
			checks.append(_note_item(note))
	if not checks.is_empty():
		tasks.append(_task("Check these", [_part("", checks)]))
	tasks.append(_code_task())
	tasks.append(_settings_task())
	var clashes: Array = []
	for entry in files_with(CLASH):
		clashes.append(_item("%s (in the 1.1.3 copy) -> %s" % [_code(_relative(entry["path"])), _code(entry["to"])]))
	for entry in custom_changes:
		if entry["status"] == CLASH:
			clashes.append(_item("%s -> %s" % [_code(entry["from"]), _code(entry["to"])]))
	if not clashes.is_empty():
		tasks.append(_task("Bring back what wasn't", [_part("These files weren't brought back, as something else is in their place:", clashes)]))
	report.append({"kind": "heading", "text": "To do by hand"})
	if tasks.is_empty():
		report.append({"kind": "list", "items": [_item("Nothing.")]})
	for index in tasks.size():
		tasks[index]["number"] = index + 1
		report.append(tasks[index])

	var done: Array = []
	for note in notes:
		if note["level"] == UpgradeData.INFO:
			done.append(_note_item(note))
	var changed_folders: Array = []
	for entry in folders:
		if entry["from"] != entry["to"] and not entry.get("reset", false):
			changed_folders.append(_item("%s: %s -> %s" % [_code(entry["setting"]), _code(entry["from"]), _code(entry["to"])]))
	if not changed_folders.is_empty():
		done.append(_item("", changed_folders, "Folder settings changed:"))
	var moved := files_with(MOVED)
	if not moved.is_empty():
		var moved_items: Array = []
		for entry in moved:
			var kept := ""
			if entry.get("replaces", false):
				kept = " (yours, kept instead of 1.2's)"
			moved_items.append(_item("%s -> %s%s" % [_code(_relative(entry["path"])), _code(entry["to"]), kept]))
		done.append(_item("", moved_items, "Brought back into Candy_DE (%d):" % moved.size()))
	if not release_added.is_empty():
		var added: Array = []
		for path in release_added:
			added.append(_item(_code(path)))
		done.append(_item("", added, "Added by 1.2, as you didn't have them:"))
	var custom_labels := {RENAME: "Renamed (variation folders use \"=\")", LIBRARY: "Moved to the shared Animation_Libraries folder", COPY: "Copied into the 1.1.3 copy, to keep the 1.1.3 version"}
	for status in custom_labels:
		var listed: Array = []
		for entry in custom_changes:
			if entry["status"] == status:
				listed.append(_item("%s -> %s" % [_code(entry["from"]), _code(entry["to"])]))
		if not listed.is_empty():
			done.append(_item("", listed, "%s (%d):" % [custom_labels[status], listed.size()]))
	done.append(_item("%d 1.1.3 file(s) you didn't change were left in the 1.1.3 copy: 1.2 has its own." % unchanged))
	report.append({"kind": "heading", "text": "Done"})
	report.append({"kind": "list", "items": done})

	report_path = REPORT_PATH
	if _write(report_path, (_report_plain(report) + "\n").to_utf8_buffer()) != "":
		report_path = ""
		return
	#? Without its copy, the window shows the plain report.
	_write(REPORT_BBCODE_PATH, (_report_bbcode(report) + "\n").to_utf8_buffer())


#* A conversion note, with what it lists (Upgrade_Data._note()):
func _note_item(note: Dictionary) -> Dictionary:
	return _item(_raw(String(note["text"])), _note_items(note.get("items", [])))


func _note_items(items: Array) -> Array:
	var converted: Array = []
	for entry in items:
		converted.append(_item(String(entry["text"]), _note_items(entry.get("items", []))))
	return converted


#^ Most lines listed for one finding of the code scan:
const MAX_HITS := 25

#* What the developer's code, scenes and saves need: the code scan's findings, then saves.
func _code_task() -> Dictionary:
	var parts: Array = []
	var changes: Array = []
	var checks: Array = []
	for finding in code_findings:
		if finding["rule"].get("check", false):
			checks.append(finding)
		else:
			changes.append(finding)
	if not changes.is_empty():
		parts.append(_part("These lines use names, keys or values that 1.2 renamed, removed or reads differently: update each one."))
		parts.append_array(_finding_parts(changes))
	if not checks.is_empty():
		parts.append(_part("These lines may be fine (the same name has another use, or the value is plain text), but check each one:"))
		parts.append_array(_finding_parts(checks))
	if code_findings.is_empty():
		parts.append(_part("No line of your scripts and scenes uses a name Candy Wizard knows 1.2 changed."))
	if not old_install_scripts.is_empty():
		var scripts: Array = []
		for path in old_install_scripts:
			scripts.append(_item(_code(path)))
		parts.append(_part("Delete 1.1.3's install scripts: they install 1.1.3, and nothing in 1.2 needs them.", scripts))
	var limits := "The search only finds names written out: check code that builds them or reads them through variables, and code in other languages (C#)."
	parts.append(_part(limits))
	var saves: Array = []
	saves.append(_item("keys lose the role symbol (`°npc1` -> `npc1`).", [], "`candy_de.roles`:"))
	saves.append(_item("Candy DE's keys convert as listed under Done (`PortraitOverride` -> `BoxPortraitMode`, `BubblesOverride` -> `DialogueMode`, colours -> BBCode wraps, `SpeakerBBCode` removed; `TTS` and `LLM` take mode names and `true` / `false` instead of -1 / 0 / 1). Names a Name command saved were already translated: 1.2 expects Default-language names, and translates them itself.", [], "`candy_de.actors`:"))
	saves.append(_item("a stored value read as a reference must start with `¢` (`€score` -> `¢€score`).", [], "References in `variables`, actors or your own data:"))
	saves.append(_item("text event and lexicon escape symbols in saved text (player names...) are read by 1.2: double them to display them.", [], "Saved text:"))
	parts.append(_part("If your game saves Candy DE's data, convert saved copies the same way when it loads them:", saves))
	return _task("Update your code, scenes and saves", parts)


#* The settings to look at: the developer's scenes, 1.1.3's that 1.2's replace, then what works differently.
func _settings_task() -> Dictionary:
	var parts: Array = []
	parts.append(_part("1.2 renamed or removed some settings of the engine, UI elements and media players, and changed some defaults. Where one of your nodes relied on 1.1.3's value, even its default, it now works differently: set it again if you need 1.1.3's behaviour."))
	for entry in own_settings:
		parts.append(_part("%s:" % _code(entry["shown"]), _settings_nodes(entry["nodes"]), true))
	for entry in replaced_settings:
		parts.append(_part("%s, replaced by 1.2's %s (bring over what you need):" % [_code(entry["scene"]), _code(entry["shown"])], _settings_nodes(entry["nodes"]), true))
	if own_settings.is_empty() and replaced_settings.is_empty():
		parts.append(_part("None of your scenes' settings changes."))
	var changes: Array = []
	for text in behaviour:
		changes.append(_item(String(text)))
	if not changes.is_empty():
		parts.append(_part("Also works differently, with nothing to set:", changes, true))
	return _task("Check your engine and UI element settings", parts)


func _settings_nodes(nodes: Array) -> Array:
	var items: Array = []
	for node in nodes:
		var lines: Array = []
		for line in node["items"]:
			lines.append(_item(" ".join(_present([String(line["text"]), String(line["note"])]))))
		var node_name := _code(node["node"])
		if node["node"] == ".":
			node_name = "The root"
		items.append(_item("", lines, "%s (%s):" % [node_name, _code(node["script"])]))
	return items


#* The code scan's findings, a part per group, each finding an item with the lines it was found on:
func _finding_parts(findings: Array) -> Array:
	var by_group := {}
	var groups: PackedStringArray = []
	for finding in findings:
		var rule: Dictionary = finding["rule"]
		var group := String(rule.get("group", "Other"))
		if not by_group.has(group):
			by_group[group] = []
			groups.append(group)
		var lines: Array = []
		for index in mini(finding["hits"].size(), MAX_HITS):
			var hit: Dictionary = finding["hits"][index]
			lines.append(_item("%s: %s" % [_code("%s:%d" % [hit["path"], hit["line"]]), _code(String(hit["text"]).left(120))]))
		if finding["hits"].size() > MAX_HITS:
			lines.append(_item("...and %d more." % (finding["hits"].size() - MAX_HITS)))
		var title := "%s -> %s." % [String(rule.get("old", "")), String(rule.get("new", ""))]
		by_group[group].append(_item(String(rule.get("note", "")), lines, title))
	var parts: Array = []
	for group in groups:
		parts.append(_part("%s:" % group, by_group[group], true))
	return parts


#? The report is a list of blocks: {kind "title" / "subtitle" / "heading", text},
#? {kind "list", items} and numbered tasks, {kind "task", title, number, parts [{text, items}]}.
#? Items are {title, text, children (items)}; a title is shown in bold before the text.
#? Texts are written with `code` in backticks (_code()); a value from elsewhere goes through _raw().

func _task(title: String, parts: Array) -> Dictionary:
	return {"kind": "task", "title": title, "number": 0, "parts": parts}


#* A part of a task: text, then a list. A label is bold, and introduces its list.
func _part(text: String, items: Array = [], label: bool = false) -> Dictionary:
	return {"text": text, "items": items, "label": label}


func _item(text: String, children: Array = [], title: String = "") -> Dictionary:
	return {"title": title, "text": text, "children": children}


#* A name or path, shown as code:
func _code(text: String) -> String:
	return "`%s`" % _raw(text)


#* A value from elsewhere, read as written (backticks would start code):
func _raw(text: String) -> String:
	return text.replace("`", "'")


func _plain(text: String) -> String:
	return text.replace("`", "")


func _bbcode(text: String) -> String:
	var spans := text.split("`")
	var result := ""
	for index in spans.size():
		var span := spans[index].replace("[", "[lb]")
		if index % 2 == 1:
			result += "[code]%s[/code]" % span
		else:
			result += span.replace(" -> ", " → ")
	return result


func _report_plain(report: Array) -> String:
	var lines: PackedStringArray = []
	for block in report:
		match String(block["kind"]):
			"title":
				lines.append(_plain(block["text"]))
			"subtitle":
				lines.append(_plain(block["text"]))
			"heading":
				if lines[lines.size() - 1] != "":
					lines.append("")
				lines.append(_plain(block["text"]).to_upper())
				lines.append("")
			"list":
				lines.append_array(_plain_items(block["items"], 0))
			"task":
				lines.append("%d. %s" % [block["number"], _plain(block["title"])])
				for part in block["parts"]:
					if part["text"] != "":
						lines.append("   " + _plain(part["text"]))
					lines.append_array(_plain_items(part["items"], 1))
				lines.append("")
	return "\n".join(lines).strip_edges()


#? Items start with "- ", indented by four spaces a level (three under a task).
func _plain_items(items: Array, depth: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	var indent := "    ".repeat(depth)
	if depth > 0:
		indent = indent.substr(1)
	for item in items:
		lines.append(indent + "- " + " ".join(_present([_plain(item["title"]), _plain(item["text"])])))
		lines.append_array(_plain_items(item["children"], depth + 1))
	return lines


func _report_bbcode(report: Array) -> String:
	var dim := Style.dim().to_html(false)
	var parts: PackedStringArray = []
	var report_kinds: PackedStringArray = []
	for block in report:
		if block["kind"] != "subtitle":
			report_kinds.append(block["kind"])
		match String(block["kind"]):
			"title":
				parts.append("[font_size=%d][b]%s[/b][/font_size]" % [Style.font_size(REPORT_TITLE_SCALE), _bbcode(block["text"])])
			"subtitle":
				#? Right under the title.
				parts[parts.size() - 1] += "\n[color=#%s]%s[/color]" % [dim, _bbcode(block["text"])]
			"heading":
				parts.append("[font_size=%d][b]%s[/b][/font_size]" % [Style.font_size(REPORT_HEADING_SCALE), _bbcode(block["text"])])
			"list":
				parts.append(_bbcode_items(block["items"]))
			"task":
				var lines: PackedStringArray = []
				lines.append("[b]%d.  %s[/b]" % [block["number"], _bbcode(block["title"])])
				for part in block["parts"]:
					if part["text"] != "" and part.get("label", false):
						lines.append("[indent][b]%s[/b][/indent]" % _bbcode(part["text"]))
					elif part["text"] != "":
						lines.append("[indent]%s[/indent]" % _bbcode(part["text"]))
					if not part["items"].is_empty():
						lines.append("[indent]%s[/indent]" % _bbcode_items(part["items"]))
				parts.append("\n".join(lines))
	#? A blank line between blocks, but none under a heading.
	var result := ""
	for index in parts.size():
		if index > 0:
			#? A list ends its own line.
			if report_kinds[index - 1] == "heading" or parts[index - 1].ends_with("[/ul]") or parts[index - 1].ends_with("[/ul][/indent]"):
				result += "\n"
			else:
				result += "\n\n"
		result += parts[index]
	return result


func _bbcode_items(items: Array) -> String:
	var lines: PackedStringArray = []
	for item in items:
		var line := ""
		if item["title"] != "":
			#? A zero-width space first, or the bullet takes the bold font.
			line = "\u200b[b]%s[/b]" % _bbcode(item["title"])
			if item["text"] != "":
				line += " "
		line += _bbcode(item["text"])
		if not item["children"].is_empty():
			line += "\n" + _bbcode_items(item["children"])
		lines.append(line)
	return "[ul]%s[/ul]" % "\n".join(lines)


func _present(texts: Array) -> PackedStringArray:
	var found: PackedStringArray = []
	for text in texts:
		if text != "":
			found.append(text)
	return found


#* How many files of a folder setting were brought back:
func _moved_from_setting(setting: String) -> int:
	var count := 0
	for entry in files_with(MOVED):
		var folder = data_folder(entry["path"])
		if folder != null and folder["setting"] == setting:
			count += 1
	return count


#==============================================================================
#  SUMMARY
#==============================================================================

#* The plan's files with a status - [{path, status, to}]:
func files_with(status: String) -> Array:
	var found := []
	for entry in files:
		if entry["status"] == status:
			found.append(entry)
	return found
