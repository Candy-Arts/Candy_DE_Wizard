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
const CandyDEData = preload("Candy_DE_Data.gd")
const DialogueConverter = preload("Dialogue_Converter.gd")
const DialogueFiles = preload("Dialogue_Files.gd")
const UpgradeData = preload("Upgrade_Data.gd")
const Upgrader = preload("Upgrader.gd")

const METADATA_SECTION := "candy_wizard"
const METADATA_OLD_SYMBOLS := "converter_old_symbols"
const METADATA_PROJECT := "converter_project"

#^ Converter key -> Candy_Properties.gd setting, for the 1.2 symbols:
const NEW_SYMBOL_SETTINGS := {
	"expression": "candy_ref_symbol",
	"text_var_start": "text_var_start_symbol",
	"text_var_end": "text_var_end_symbol",
	"substitution_start": "substitution_start_symbol",
	"substitution_end": "substitution_end_symbol",
	"text_event_start": "text_event_start_symbol",
	"text_event_end": "text_event_end_symbol",
	"lexicon_escape_start": "lexicon_escape_start_symbol",
	"lexicon_escape_end": "lexicon_escape_end_symbol",
}

#^ In the 1.1.3 copy:
const PROPERTIES_SCRIPT := "Scripts/User_Data/Candy_Properties.gd"
const UI_SCENE := "Scenes/Candy_UI.tscn"
const DEFAULT_BG_SCENES := "Scenes/Background_Scenes"
#^ Candy DE's own background scene template, whose layers aren't the developer's:
const BG_TEMPLATE := "Candy_Default.tscn"

#^ The portrait node's type -> how PortraitPlay converts:
const PORTRAIT_TYPES := {
	"Sprite2D": DialogueConverter.PORTRAIT_SPRITE,
	"AnimatedSprite2D": DialogueConverter.PORTRAIT_SPRITE,
	"TextureRect": DialogueConverter.PORTRAIT_FOLDER,
	"NinePatchRect": DialogueConverter.PORTRAIT_FOLDER,
	"VideoStreamPlayer": DialogueConverter.PORTRAIT_VIDEO,
}


#==============================================================================
#  DIALOGUES
#==============================================================================

#* The dialogues of dialogues_folder (backups left out), by format:
#? {"folder", "total", "all", "convert" (in the 1.1 format), "unreadable", "problem"}.
static func dialogue_formats() -> Dictionary:
	var found := {"folder": "", "total": 0, "all": [], "convert": [], "unreadable": [], "problem": ""}
	var folder = CandyDEData.property("dialogues_folder")
	if not folder is String:
		found["problem"] = "dialogues_folder isn't set in Candy_Properties.gd."
		return found
	found["folder"] = String(folder).trim_suffix("/")
	var gathered := CandyDEData.dialogue_names()
	for dialogue_name in gathered["names"]:
		var path: String = String(found["folder"]).path_join(dialogue_name + ".txt")
		found["total"] += 1
		found["all"].append(path)
		var info := DialogueFiles.inspect(path)
		match String(info["status"]):
			DialogueFiles.STATUS_CONVERT:
				found["convert"].append(path)
			DialogueFiles.STATUS_OLD, DialogueFiles.STATUS_UNREADABLE:
				found["unreadable"].append(path)
	return found


#==============================================================================
#  THE 1.1.3 COPY
#==============================================================================

#* The 1.1.3 install set aside, or {}:
#? {"folder": where it is, "install_folder": where it was (its scenes' paths point there)}.
static func old_install() -> Dictionary:
	var record := Utils.read_record()
	var folder := Upgrader.ASIDE_FOLDER
	var install_folder := Utils.CANDY_DE_FOLDER
	if record.get("upgraded_from") is Dictionary:
		var upgraded: Dictionary = record["upgraded_from"]
		folder = String(upgraded.get("aside", folder))
		install_folder = String(upgraded.get("folder", install_folder))
	if not FileAccess.file_exists(folder.path_join(PROPERTIES_SCRIPT)):
		return {}
	return {"folder": folder, "install_folder": install_folder}


#* The 1.1 symbols the copy's Candy_Properties.gd sets (only those it has):
static func old_symbols_found(install: Dictionary) -> Dictionary:
	var found := {}
	if install.is_empty():
		return found
	var text := FileAccess.get_file_as_string(String(install["folder"]).path_join(PROPERTIES_SCRIPT))
	for key in DialogueConverter.default_old_symbols():
		var value = _setting(text, key)
		if value is String:
			found[key] = value
	return found


#* What the copy says about the 1.1 engine and scenes (only what it could tell):
#? "tts", "ui_elements", "portrait_node", "bg_layers".
static func project_found(install: Dictionary) -> Dictionary:
	var found := {}
	if install.is_empty():
		return found
	var folder := String(install["folder"])
	var ui_path := folder.path_join(UI_SCENE)
	if FileAccess.file_exists(ui_path):
		var ui_text := FileAccess.get_file_as_string(ui_path)
		found["tts"] = UpgradeData.engine_settings(ui_text)["text_to_speech"]
		var paths := _root_dictionary(ui_text, "ui_elements_paths")
		if not paths.is_empty():
			var elements: Array = []
			for element in DialogueConverter.UI_ELEMENTS:
				if paths.has(element):
					elements.append(element)
			found["ui_elements"] = elements
			var portrait_node := _portrait_node(ui_text, String(paths.get("portrait_path", "")), install)
			if portrait_node != "":
				found["portrait_node"] = portrait_node
	var layers := _background_layers(install)
	if not layers.is_empty():
		found["bg_layers"] = ", ".join(layers)
	return found


#* A "var name = value" setting's value, or null:
static func _setting(text: String, variable: String) -> Variant:
	var found := Utils.variable_regex(variable).search(text)
	if found == null:
		return null
	return str_to_var(found.get_string(1))


#* A scene file's sections, [{"header" = "[node name=...]", "lines" = [property lines]}]:
static func _sections(scene_text: String) -> Array:
	var sections: Array = []
	for line in scene_text.replace("\r\n", "\n").split("\n"):
		if line.begins_with("["):
			sections.append({"header": line, "lines": PackedStringArray()})
		elif not sections.is_empty():
			sections.back()["lines"].append(line)
	return sections


#* A header's attribute (name="Portrait" -> "Portrait"), or "":
static func _attribute(header: String, attribute: String) -> String:
	var found := RegEx.create_from_string(" " + attribute + "=\"([^\"]*)\"").search(header)	#/ After a space, so id="..." isn't found inside uid="..."
	if found == null:
		var bare := RegEx.create_from_string(" " + attribute + "=([^ \\]]+)").search(header)
		if bare == null:
			return ""
		return bare.get_string(1)
	return found.get_string(1)


static func _root_section(sections: Array) -> Dictionary:
	for section in sections:
		if String(section["header"]).begins_with("[node ") and not String(section["header"]).contains(" parent="):
			return section
	return {}


#* A property of the scene's root node, as its text ("" if it has none), spanning lines:
static func _root_property(scene_text: String, property: String) -> String:
	var root := _root_section(_sections(scene_text))
	if root.is_empty():
		return ""
	var lines: PackedStringArray = root["lines"]
	for index in lines.size():
		if lines[index].begins_with(property + " = "):
			var value := lines[index].trim_prefix(property + " = ")
			var next := index + 1
			#? A dictionary spans lines until its closing brace.
			while value.count("{") > value.count("}") and next < lines.size():
				value += "\n" + lines[next]
				next += 1
			return value
	return ""


#* The root's dictionary property (Dictionary[String, String]({...}) or {...}), or {}:
static func _root_dictionary(scene_text: String, property: String) -> Dictionary:
	var value := _root_property(scene_text, property)
	var open := value.find("{")
	var close := value.rfind("}")
	if open < 0 or close < open:
		return {}
	var parsed = str_to_var(value.substr(open, close - open + 1))
	if parsed is Dictionary:
		return parsed
	return {}


#* A NodePath("...") value's path, or "":
static func _node_path(value: String) -> String:
	var found := RegEx.create_from_string("NodePath\\(\"([^\"]*)\"\\)").search(value)
	if found == null:
		return ""
	return found.get_string(1)


#* The 1.1 engine's portrait node kind (DialogueConverter.PORTRAIT_*), or "" if it can't tell:
#? From the portrait scene its Candy_UI.tscn instances at portrait_path.
static func _portrait_node(ui_text: String, portrait_path: String, install: Dictionary) -> String:
	if portrait_path == "" or portrait_path.contains("/"):
		return ""
	var sections := _sections(ui_text)
	var resource_id := ""
	for section in sections:
		var header := String(section["header"])
		if header.begins_with("[node ") and _attribute(header, "name") == portrait_path and _attribute(header, "parent") == ".":
			var instance := RegEx.create_from_string("instance=ExtResource\\(\"([^\"]*)\"\\)").search(header)
			if instance != null:
				resource_id = instance.get_string(1)
	if resource_id == "":
		return ""
	var scene_path := ""
	for section in sections:
		var header := String(section["header"])
		if header.begins_with("[ext_resource ") and _attribute(header, "id") == resource_id:
			scene_path = _in_copy(_attribute(header, "path"), install)
	if scene_path == "":
		return ""
	var scene_text := FileAccess.get_file_as_string(scene_path)
	var node_name := _node_path(_root_property(scene_text, "portrait_node"))
	if node_name == "" or node_name.contains("/"):
		return ""
	for section in _sections(scene_text):
		var header := String(section["header"])
		if header.begins_with("[node ") and _attribute(header, "name") == node_name and _attribute(header, "parent") == ".":
			return String(PORTRAIT_TYPES.get(_attribute(header, "type"), ""))
	return ""


#* The layers of the 1.1.3 background scenes - the children of each scene's bg_container:
static func _background_layers(install: Dictionary) -> PackedStringArray:
	var layers: PackedStringArray = []
	var folder := String(install["folder"])
	var properties := FileAccess.get_file_as_string(folder.path_join(PROPERTIES_SCRIPT))
	var scenes_folder := ""
	var setting = _setting(properties, "bg_scenes_folder")
	if setting is String:
		scenes_folder = _in_copy(String(setting).trim_suffix("/"), install)
	if scenes_folder == "" or not DirAccess.dir_exists_absolute(scenes_folder):
		scenes_folder = folder.path_join(DEFAULT_BG_SCENES)
	if not DirAccess.dir_exists_absolute(scenes_folder):
		return layers
	var names := Array(DirAccess.get_files_at(scenes_folder))
	names.sort()
	for file_name in names:
		if not String(file_name).ends_with(".tscn") or file_name == BG_TEMPLATE:
			continue
		var scene_text := FileAccess.get_file_as_string(scenes_folder.path_join(file_name))
		var container := _node_path(_root_property(scene_text, "bg_container"))
		if container == "":
			continue
		for section in _sections(scene_text):
			var header := String(section["header"])
			if header.begins_with("[node ") and _attribute(header, "parent") == container:
				var layer := _attribute(header, "name")
				if layer != "" and not layer in layers:
					layers.append(layer)
	return layers


#* Where a res:// path of the 1.1.3 install is in the copy now, or "":
#? Failing that, a path with a Scenes/ folder is looked up in the copy's Scenes/.
static func _in_copy(path: String, install: Dictionary) -> String:
	var folder := String(install["folder"])
	var install_folder := String(install["install_folder"])
	var candidates: PackedStringArray = []
	if path.begins_with(install_folder + "/"):
		candidates.append(folder.path_join(path.trim_prefix(install_folder + "/")))
	var scenes_at := path.find("/Scenes/")
	if scenes_at >= 0:
		candidates.append(folder.path_join(path.substr(scenes_at + 1)))
	for candidate in candidates:
		if FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate):
			return candidate
	return ""


#==============================================================================
#  1.2 SYMBOLS
#==============================================================================

#* The 1.2 symbols, by the converter's keys (defaults for settings that aren't plain values):
static func new_symbols() -> Dictionary:
	var symbols := DialogueConverter.default_new_symbols()
	for key in NEW_SYMBOL_SETTINGS:
		var value = CandyDEData.property(NEW_SYMBOL_SETTINGS[key])
		if value is String and String(value) != "":
			symbols[key] = value
	return symbols


#==============================================================================
#  REMEMBERED
#==============================================================================

static func remembered_old_symbols() -> Dictionary:
	var value = EditorInterface.get_editor_settings().get_project_metadata(METADATA_SECTION, METADATA_OLD_SYMBOLS, {})
	if value is Dictionary:
		return value
	return {}


static func remembered_project() -> Dictionary:
	var value = EditorInterface.get_editor_settings().get_project_metadata(METADATA_SECTION, METADATA_PROJECT, {})
	if value is Dictionary:
		return value
	return {}


static func remember(old_symbols: Dictionary, project: Dictionary) -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_project_metadata(METADATA_SECTION, METADATA_OLD_SYMBOLS, old_symbols)
	settings.set_project_metadata(METADATA_SECTION, METADATA_PROJECT, project)
