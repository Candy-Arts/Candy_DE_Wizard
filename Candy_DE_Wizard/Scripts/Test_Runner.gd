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


const CandyDEData = preload("Candy_DE_Data.gd")
const Utils = preload("Wizard_Utils.gd")

#^ Testing scene exports a test sets:
const EXPORTS := ["dialogue", "conversation", "block", "line"]
#^ Inherited scene that runs:
const RUN_SCENE_PATH := Utils.TEMP_FOLDER + "/Test_Run.tscn"
#^ Test tool's choices, per project - {"scene", and the four EXPORTS}:
const METADATA_SECTION := "candy_wizard"
const METADATA_KEY := "test"


#* Run a testing scene with EXPORTS -> String values. Returns an error, or "":
static func run(scene_path: String, values: Dictionary) -> String:
	var info := CandyDEData.scene_exports(scene_path, EXPORTS)
	var problem := exports_problem(info)
	if problem != "":
		return problem
	var text := "[gd_scene format=3]\n\n"
	text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1\"]\n\n" % scene_path.c_escape()
	text += "[node name=\"%s\" instance=ExtResource(\"1\")]\n" % String(info["root_name"]).c_escape()
	for variable in EXPORTS:
		#? Int exports get an int:
		var value: Variant = str(values.get(variable, ""))
		if typeof(info["values"][variable]) == TYPE_INT and String(value).is_valid_int():
			value = String(value).to_int()
		text += "%s = %s\n" % [variable, var_to_str(value)]

	DirAccess.make_dir_recursive_absolute(Utils.TEMP_FOLDER)
	var file := FileAccess.open(RUN_SCENE_PATH, FileAccess.WRITE)
	if file == null:
		return "Couldn't write %s (%s)." % [RUN_SCENE_PATH, error_string(FileAccess.get_open_error())]
	file.store_string(text)
	file.close()
	EditorInterface.play_custom_scene(RUN_SCENE_PATH)
	return ""


#* Why scene_exports() info isn't a testing scene, or "":
static func exports_problem(info: Dictionary) -> String:
	if not info["problems"].is_empty():
		return "\n".join(info["problems"])
	var missing: PackedStringArray = []
	for variable in EXPORTS:
		if not info["values"].has(variable):
			missing.append(variable)
	if not missing.is_empty():
		return "The testing scene's root doesn't export %s." % ", ".join(missing)
	return ""


#* Testing scene to run - the Test tool's choice, else the first valid one, else "":
static func chosen_scene() -> String:
	var choices = EditorInterface.get_editor_settings().get_project_metadata(METADATA_SECTION, METADATA_KEY, {})
	var scenes: PackedStringArray = CandyDEData.testing_scenes()["names"]
	if choices is Dictionary and String(choices.get("scene", "")) in scenes:
		return String(choices["scene"])
	for scene_path in scenes:
		if exports_problem(CandyDEData.scene_exports(scene_path, EXPORTS)) == "":
			return scene_path
	return ""


#==============================================================================
#  STARTING POINTS
#==============================================================================

#* Dialogue file path to load_scripted_dialogue()'s name - {"name", "problem"}:
static func dialogue_name(file_path: String) -> Dictionary:
	var folder = CandyDEData.property("dialogues_folder")
	if not folder is String:
		return {"name": "", "problem": "dialogues_folder isn't set in Candy_Properties.gd."}
	var local := ProjectSettings.localize_path(file_path.replace("\\", "/"))
	if not local.begins_with("res://"):
		return {"name": "", "problem": "%s isn't in this project." % file_path}
	var prefix := ProjectSettings.localize_path(String(folder)).trim_suffix("/") + "/"
	if not local.begins_with(prefix) or local.get_extension() != "txt":
		return {"name": "", "problem": "%s isn't a .txt file in dialogues_folder (%s), where Candy DE looks for dialogues." % [local, prefix.trim_suffix("/")]}
	return {"name": local.trim_prefix(prefix).trim_suffix(".txt"), "problem": ""}


#* Check a starting point, returning {"values" = EXPORTS -> String, "problem"}:
#? Empty means first. Line: index or LM reference.
static func resolve_start(dialogue: String, conversation: String, block: String, line: String) -> Dictionary:
	var result := {"values": {}, "problem": ""}
	var read := CandyDEData.read_dialogue(dialogue)
	if read["problem"] != "":
		result["problem"] = read["problem"]
		return result
	var conversations: Dictionary = read["conversations"]

	if conversation == "":
		for key in conversations:
			if conversations[key] is Dictionary:
				conversation = str(key)
				break
	if not conversations.get(conversation) is Dictionary:
		result["problem"] = "%s has no conversation called \"%s\"." % [dialogue, conversation]
		if conversations.is_empty():
			result["problem"] = "%s has no conversations." % dialogue
		return result

	var blocks: Dictionary = conversations[conversation]
	if block == "":
		for key in blocks:
			if blocks[key] is Dictionary and blocks[key].get("Text") is Array:
				block = str(key)
				break
	if not blocks.get(block) is Dictionary or not blocks[block].get("Text") is Array:
		result["problem"] = "%s has no block called \"%s\" with lines." % [conversation, block]
		if block == "":
			result["problem"] = "%s has no blocks with lines." % conversation
		return result

	var lines: Array = blocks[block]["Text"]
	if line == "":
		line = "0"
	if line.is_valid_int():
		if line.to_int() < 0 or line.to_int() >= lines.size():
			result["problem"] = "%s has no line %s: its lines are 0 to %d." % [block, line, lines.size() - 1]
			if lines.is_empty():
				result["problem"] = "%s has no lines." % block
			return result
	elif not _has_line_mark(lines, line):
		result["problem"] = "%s has no line mark (LM) called \"%s\"." % [block, line]
		return result

	result["values"] = {"dialogue": dialogue, "conversation": conversation, "block": block, "line": line}
	return result


#* Whether a block has an LM with this reference:
#! Follows _find_line_mark() in Candy_DE/Scripts/Classes/Candy_Flow.gd.
static func _has_line_mark(lines: Array, mark: String) -> bool:
	for line in lines:
		if not line is Dictionary:
			continue
		for key in line:
			if str(key).to_lower() == "lm" and line[key] is Dictionary and str(line[key].get("Reference", "")) == mark:
				return true
	return false
