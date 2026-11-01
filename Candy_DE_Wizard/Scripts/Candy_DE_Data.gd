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

#^ The developer's settings:
const PROPERTIES_PATH := "res://Candy_DE/Scripts/User_Data/Candy_Properties.gd"
#^ The developer's own CandyRef symbols (SHORTCUT_SYMBOLS and LOOKUP_SYMBOLS):
#! Same path as USER_SHORTCUTS_PATH in Candy_DE/Scripts/Classes/CandyRef.gd.
const USER_SHORTCUTS_PATH := "res://Candy_DE/Scripts/User_Data/CandyRef_Shortcuts.gd"
#^ Data tables, one variable per script:
const DATA_TABLES_FOLDER := "res://Candy_DE/Scripts/User_Data/Data_Tables"

#^ Media player scripts, by kind. A player whose script extends one (at any depth) is of its kind:
const PLAYER_SCRIPTS := {
	"Audio_Player.gd": "Audio",
	"Audio_Player_2D.gd": "Audio",
	"Audio_Player_3D.gd": "Audio",
	"Image_Player.gd": "Image",
	"Video_Player.gd": "Video",
}

#^ Voice player's media_players_paths key (its folders come from voice_path):
const VOICE_KEY := "Voice"

#^ Dialogue Converter backup folders, left out when reading dialogues:
#! Same as CandyFileConverter.BACKUP_FOLDER in Candy Dialogue Creator.
const CONVERSION_BACKUPS_FOLDER := "Conversion Backups"


#* Whether the project has a Candy DE this can read:
static func is_available() -> bool:
	return FileAccess.file_exists(PROPERTIES_PATH)


#==============================================================================
#  PROPERTIES
#==============================================================================

#* A setting of Candy_Properties.gd, or null if it isn't there (or isn't a plain value):
static func property(variable: String) -> Variant:
	var text := FileAccess.get_file_as_string(PROPERTIES_PATH)
	var found := Utils.variable_regex(variable).search(text)
	if found == null:
		return null
	return str_to_var(found.get_string(1))


#* Writes settings (each declared with a plain value) into Candy_Properties.gd. Returns an error message, or "":
static func set_properties(values: Dictionary) -> String:
	var text := FileAccess.get_file_as_string(PROPERTIES_PATH)
	for variable in values:
		var edited := Utils.set_variable(text, variable, values[variable])
		if edited == "":
			return "Candy_Properties.gd has no \"var %s = ...\" line with a plain value to change." % variable
		text = edited
	var file := FileAccess.open(PROPERTIES_PATH, FileAccess.WRITE)
	if file == null:
		return "Couldn't write Candy_Properties.gd (%s)." % error_string(FileAccess.get_open_error())
	file.store_string(text)
	file.close()
	EditorInterface.get_resource_filesystem().update_file(PROPERTIES_PATH)
	return ""


#* The developer's own CandyRef symbols - the keys of SHORTCUT_SYMBOLS and LOOKUP_SYMBOLS:
static func user_sigils() -> PackedStringArray:
	var sigils: PackedStringArray = []
	if not FileAccess.file_exists(USER_SHORTCUTS_PATH):
		return sigils
	var text := FileAccess.get_file_as_string(USER_SHORTCUTS_PATH)
	for constant in ["SHORTCUT_SYMBOLS", "LOOKUP_SYMBOLS"]:
		var found := RegEx.create_from_string(r"(?m)^const\s+" + constant + r"\b[^=\n]*=\s*").search(text)
		if found != null and text.substr(found.get_end(), 1) == "{":
			sigils.append_array(_dictionary_keys(text, found.get_end()))
	return sigils


#==============================================================================
#  ACTORS
#==============================================================================

#* The keys of the actors table (in Data_Tables, the script declaring 'actors'):
static func actor_names() -> Dictionary:
	var names: PackedStringArray = []
	var problems: PackedStringArray = []
	var declaration := RegEx.create_from_string(r"(?m)^var\s+actors\b[^=\n]*=\s*")
	var found_table := false
	for script_path in _files_in(DATA_TABLES_FOLDER, "gd"):
		var text := FileAccess.get_file_as_string(script_path)
		var found := declaration.search(text)
		if found == null:
			continue
		found_table = true
		if text.substr(found.get_end(), 1) != "{":
			problems.append("The actors table in %s isn't written as a dictionary ({...}), so its actors can't be read." % script_path)
			continue
		for key in _dictionary_keys(text, found.get_end()):
			if not key in names:
				names.append(key)
	if not found_table:
		problems.append("No script in %s declares the actors table." % DATA_TABLES_FOLDER)
	return {"names": names, "problems": problems}


#* The string keys of the dictionary literal whose "{" is at open_index:
static func _dictionary_keys(text: String, open_index: int) -> PackedStringArray:
	var keys: PackedStringArray = []
	var depth := 0
	var index := open_index
	while index < text.length():
		var character := text[index]
		if character == "#":
			var line_end := text.find("\n", index)
			if line_end == -1:
				break
			index = line_end
		elif character == "\"" or character == "'":
			var string_end := _string_end(text, index)
			if depth == 1:
				#? At the dictionary's own level, a string followed by ":" is a key:
				var after := string_end
				while after < text.length() and text[after] in [" ", "\t", "\n", "\r"]:
					after += 1
				if after < text.length() and text[after] == ":":
					keys.append(text.substr(index + 1, string_end - index - 2).c_unescape())
			index = string_end - 1
		elif character in ["{", "[", "("]:
			depth += 1
		elif character in ["}", "]", ")"]:
			depth -= 1
			if depth == 0:
				break
		index += 1
	return keys


#* The index just after the string literal starting at start:
static func _string_end(text: String, start: int) -> int:
	var quote := text[start]
	if text.substr(start, 3) == quote.repeat(3):
		var close := text.find(quote.repeat(3), start + 3)
		if close == -1:
			return text.length()
		return close + 3
	var index := start + 1
	while index < text.length():
		if text[index] == "\\":
			index += 2
			continue
		if text[index] == quote or text[index] == "\n":
			return index + 1
		index += 1
	return text.length()


#==============================================================================
#  SCENES
#==============================================================================

#* The media players' keys in the dialogue UI scenes, by kind (voice player excluded):
static func media_player_names(kind: String) -> Dictionary:
	var names: PackedStringArray = []
	var problems: PackedStringArray = []
	var folder = property("dialogue_ui_folder")
	if not folder is String:
		problems.append("dialogue_ui_folder isn't set in Candy_Properties.gd.")
		return {"names": names, "problems": problems}
	var scene_paths := _files_in(folder, "tscn")
	if scene_paths.is_empty():
		problems.append("No scenes in %s." % folder)
	for scene_path in scene_paths:
		var root := _instantiate(scene_path, problems)
		if root == null:
			continue
		for node in _nodes_in(root):
			var locations = node.get("media_players_paths")
			if not locations is Dictionary:
				continue
			for key in locations:
				if key == VOICE_KEY:
					continue
				var entry = locations[key]
				#? A path, or [path, false] for a player the engine only names.
				if entry is Array and not entry.is_empty():
					entry = entry[0]
				var player := node.get_node_or_null(NodePath(str(entry)))
				if player == null:
					problems.append("%s: the media player '%s' points to %s, which isn't in the scene." % [scene_path, key, str(entry)])
					continue
				if _player_kind(player) == kind and not key in names:
					names.append(key)
		root.free()
	return {"names": names, "problems": problems}


#* A media player's kind, from its script - "Audio", "Image", "Video", or "" for others:
static func _player_kind(player: Node) -> String:
	var script: Script = player.get_script()
	while script != null:
		var file_name := script.resource_path.get_file()
		if PLAYER_SCRIPTS.has(file_name):
			return PLAYER_SCRIPTS[file_name]
		script = script.get_base_script()
	return ""


#* Background layer names - the children of each bg scene's bg_container:
static func background_layer_names() -> Dictionary:
	var names: PackedStringArray = []
	var problems: PackedStringArray = []
	var folder = property("bg_scenes_folder")
	if not folder is String:
		problems.append("bg_scenes_folder isn't set in Candy_Properties.gd.")
		return {"names": names, "problems": problems}
	var scene_paths := _files_in(folder, "tscn")
	if scene_paths.is_empty():
		problems.append("No scenes in %s." % folder)
	for scene_path in scene_paths:
		var root := _instantiate(scene_path, problems)
		if root == null:
			continue
		var container = root.get("bg_container")
		if container is NodePath:
			container = root.get_node_or_null(container)
		if container is Node:
			for layer in container.get_children():
				if not String(layer.name) in names:
					names.append(String(layer.name))
		else:
			problems.append("%s has no bg_container." % scene_path)
		root.free()
	return {"names": names, "problems": problems}


#* The scene paths of testing_scenes_folder:
static func testing_scenes() -> Dictionary:
	var problems: PackedStringArray = []
	var folder = property("testing_scenes_folder")
	if not folder is String:
		problems.append("testing_scenes_folder isn't set in Candy_Properties.gd.")
		return {"names": PackedStringArray(), "problems": problems}
	var scene_paths := _files_in(folder, "tscn")
	if scene_paths.is_empty():
		problems.append("No scenes in %s (testing_scenes_folder)." % folder)
	return {"names": scene_paths, "problems": problems}


#* A scene root's name and its values of the given exported variables:
#* {"root_name", "values", "problems"}:
static func scene_exports(scene_path: String, variables: Array) -> Dictionary:
	var values := {}
	var problems: PackedStringArray = []
	var root := _instantiate(scene_path, problems)
	if root == null:
		return {"root_name": "", "values": values, "problems": problems}
	#? Read exports from the script: a non-tool script's placeholder instance doesn't mark them:
	var exported: Array[String] = []
	var script: Script = root.get_script()
	if script != null:
		for property_info in script.get_script_property_list():
			if property_info["usage"] & PROPERTY_USAGE_STORAGE:
				exported.append(String(property_info["name"]))
	for variable in variables:
		if variable in exported:
			values[variable] = root.get(variable)
	var root_name := String(root.name)
	root.free()
	return {"root_name": root_name, "values": values, "problems": problems}


static func _instantiate(scene_path: String, problems: PackedStringArray) -> Node:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		problems.append("Couldn't load %s." % scene_path)
		return null
	var root := scene.instantiate()
	if root == null:
		problems.append("Couldn't open %s." % scene_path)
	return root


#* A node and every node under it:
static func _nodes_in(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	for child in root.get_children():
		nodes.append_array(_nodes_in(child))
	return nodes


#==============================================================================
#  DIALOGUES
#==============================================================================

#* Dialogue names as load_scripted_dialogue() takes them ("Intro", "Town/Shop"), backups left out:
static func dialogue_names() -> Dictionary:
	var names: PackedStringArray = []
	var problems: PackedStringArray = []
	var folder = property("dialogues_folder")
	if not folder is String:
		problems.append("dialogues_folder isn't set in Candy_Properties.gd.")
		return {"names": names, "problems": problems}
	var prefix := String(folder).trim_suffix("/") + "/"
	for path in _files_in(folder, "txt", CONVERSION_BACKUPS_FOLDER):
		names.append(path.trim_prefix(prefix).trim_suffix(".txt"))
	if names.is_empty():
		problems.append("No dialogues in %s (dialogues_folder)." % folder)
	return {"names": names, "problems": problems}


#* A dialogue's conversations - {"conversations", "problem" ("" if read)}:
static func read_dialogue(dialogue_name: String) -> Dictionary:
	var folder = property("dialogues_folder")
	if not folder is String:
		return {"conversations": {}, "problem": "dialogues_folder isn't set in Candy_Properties.gd."}
	var path := String(folder).path_join(dialogue_name + ".txt")
	if not FileAccess.file_exists(path):
		return {"conversations": {}, "problem": "%s doesn't exist." % path}

	var expression := Expression.new()
	if expression.parse(_clean_dialogue_source(FileAccess.get_file_as_string(path))) != OK:
		return {"conversations": {}, "problem": "%s can't be read: %s" % [path, expression.get_error_text()]}
	var result = expression.execute()
	if expression.has_execute_failed():
		return {"conversations": {}, "problem": "%s can't be read: %s" % [path, expression.get_error_text()]}
	if not result is Dictionary:
		return {"conversations": {}, "problem": "%s doesn't hold a dictionary." % path}
	#? Wrapped (with Meta and Dialogue keys), or bare (conversations at the root):
	if result.has("Dialogue"):
		result = result["Dialogue"]
		if not result is Dictionary:
			return {"conversations": {}, "problem": "%s: its Dialogue isn't a dictionary." % path}
	return {"conversations": result, "problem": ""}


#* A dialogue file's text, made readable by Expression:
#! Same as _clean_dialogue_source() in Candy_DE/Scripts/Candy_Engine.gd: change both together.
static func _clean_dialogue_source(text: String) -> String:
	var out := PackedStringArray()
	var length := text.length()
	var index := 0
	var in_quote := ""
	var escaped := false

	while index < length:
		var character := text[index]

		#% Inside a string - copied verbatim:
		if in_quote != "":
			out.append(character)
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == in_quote:
				in_quote = ""
			index += 1
			continue

		#% Opening quote:
		if character == "\"" or character == "'":
			in_quote = character
			out.append(character)
			index += 1
			continue

		#% Comment - skip to the line break:
		if character == "#":
			while index < length and text[index] != "\n":
				index += 1
			continue

		#% Godot's printed null:
		if character == "<" and text.substr(index, 6).to_lower() == "<null>":
			out.append("null")
			index += 6
			continue

		#% Trailing comma before ] or }:
		if character == ",":
			var next := index + 1
			while next < length:
				var look := text[next]
				if look == " " or look == "\t" or look == "\n" or look == "\r":
					next += 1
				elif look == "#":
					while next < length and text[next] != "\n":
						next += 1
				else:
					break
			if next < length and (text[next] == "]" or text[next] == "}"):
				index += 1
				continue

		out.append(character)
		index += 1

	var cleaned := "".join(out).strip_edges()
	if cleaned.ends_with(","):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	return cleaned


#==============================================================================
#  FILES
#==============================================================================

#* Files with this extension in a folder tree, sorted, skipping sub-folders named skipped_folder:
static func _files_in(folder: String, extension: String, skipped_folder: String = "") -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var entry_path := folder.path_join(entry)
		if dir.current_is_dir():
			if entry != skipped_folder:
				found.append_array(_files_in(entry_path, extension, skipped_folder))
		elif entry.get_extension() == extension:
			found.append(entry_path)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
