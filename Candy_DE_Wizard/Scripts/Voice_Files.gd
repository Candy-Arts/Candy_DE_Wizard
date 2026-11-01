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

const CandyDEData = preload("Candy_DE_Data.gd")
const Utils = preload("Wizard_Utils.gd")

#^ voice_path tags:
#! Same as VOICE_PATH_TAGS in Candy_DE/Scripts/Classes/Candy_Voice.gd.
const TAGS := ["{actor}", "{dialogue}", "{conversation}", "{block}", "{line}"]
#^ Variant with no folder of its own:
const DEFAULT_VARIANT := "Default"
#^ File name for an empty Voice value:
const DEFAULT_FILE := "Default"
#^ Moved with their file, never copied (they hold its UID):
const SIDECAR_EXTENSIONS := ["import", "uid"]
#^ Files moved between two editor frames:
const FILES_PER_FRAME := 10

#^ What the last move() did:
var moved: Array = []			#/ [from, to]
var copied: Array = []			#/ [from, to]
var failed: PackedStringArray = []
var folders_removed := 0
var layout_recorded := false


#==============================================================================
#  LAYOUTS
#==============================================================================

#* Layout set in Candy_Properties.gd, or {}:
static func current_layout() -> Dictionary:
	var folder = CandyDEData.property("voice_folder")
	var sub_path = CandyDEData.property("voice_path")
	if not folder is String or not sub_path is String:
		return {}
	return {"voice_folder": folder, "voice_path": sub_path}


#* Recorded layout, or {}:
static func recorded_layout() -> Dictionary:
	if not FileAccess.file_exists(Utils.VOICE_LAYOUT_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Utils.VOICE_LAYOUT_PATH))
	if parsed is Dictionary and parsed.get("voice_folder") is String and parsed.get("voice_path") is String:
		return {"voice_folder": parsed["voice_folder"], "voice_path": parsed["voice_path"]}
	return {}


#* Record a layout. Returns an error, or "":
static func record_layout(layout: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(Utils.VOICE_LAYOUT_PATH.get_base_dir())
	var file := FileAccess.open(Utils.VOICE_LAYOUT_PATH, FileAccess.WRITE)
	if file == null:
		return "Couldn't write %s (%s)." % [Utils.VOICE_LAYOUT_PATH, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify({"voice_folder": layout["voice_folder"], "voice_path": layout["voice_path"]}, "\t"))
	file.close()
	return ""


static func same_layout(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	return _folder_key(a["voice_folder"]) == _folder_key(b["voice_folder"]) and a["voice_path"] == b["voice_path"]


#* Layout problems, or []:
static func layout_problems(layout: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	if not String(layout["voice_folder"]).begins_with("res://"):
		problems.append("voice_folder must be a folder of the project (res://...).")
	var unknown: PackedStringArray = []
	for found in RegEx.create_from_string(r"\{[^{}]*\}").search_all(String(layout["voice_path"])):
		if not found.get_string() in TAGS and not found.get_string() in unknown:
			unknown.append(found.get_string())
	if not unknown.is_empty():
		problems.append("voice_path has unknown tags: %s. It takes %s." % [", ".join(unknown), ", ".join(TAGS)])
	return problems


#* A line's voice folder for a variant folder ("" for Default), or "" if the game decides it:
#! Follows _folder_path() in Candy_DE/Scripts/Classes/Candy_Voice.gd.
static func line_folder(layout: Dictionary, line: Dictionary, variant_folder: String) -> String:
	var sub_path := String(layout["voice_path"])
	if "{actor}" in sub_path and line["actor"] == null:
		return ""
	var values := {
		"{actor}": str(line["actor"]),
		"{dialogue}": line["dialogue"],
		"{conversation}": line["conversation"],
		"{block}": line["block"],
		"{line}": line["line"],
	}
	for tag in values:
		sub_path = sub_path.replace(tag, values[tag])
	var path := _folder_key(layout["voice_folder"])
	for folder in sub_path.split("/", false):
		if folder.strip_edges() != "":
			path = path.path_join(folder)
	if variant_folder != "":
		path = path.path_join(variant_folder)
	return path


#* Folder of a line's voice file: line_folder(), plus any folder its Voice value names:
#! Follows Spoken_Line.gd and _folder_path() in Candy_Voice.gd (Voice joined after the variant's folder).
static func line_files_folder(layout: Dictionary, line: Dictionary, variant_folder: String) -> String:
	var folder := line_folder(layout, line, variant_folder)
	if folder == "" or not line["voice"] is String:
		return folder
	var sub_folder := String(line["voice"]).get_base_dir()
	if sub_folder == "":
		return folder
	return folder.path_join(sub_folder).simplify_path()


static func _folder_key(folder: String) -> String:
	return folder.trim_suffix("/")


#==============================================================================
#  LINES
#==============================================================================

#* Spoken lines whose voice file follows voice_path, and problems:
static func spoken_lines() -> Dictionary:
	var lines: Array = []
	var gathered := CandyDEData.dialogue_names()
	var problems: PackedStringArray = gathered["problems"]
	var symbols := {
		"expression": str(CandyDEData.property("candy_ref_symbol")),
		"role": str(CandyDEData.property("role_symbol")),
	}
	for dialogue_name in gathered["names"]:
		var read := CandyDEData.read_dialogue(dialogue_name)
		if read["problem"] != "":
			problems.append(read["problem"])
			continue
		var conversations: Dictionary = read["conversations"]
		for conversation in conversations:
			if not conversations[conversation] is Dictionary:
				continue
			for block in conversations[conversation]:
				var block_data = conversations[conversation][block]
				var text_lines = null
				if block_data is Dictionary:
					text_lines = block_data.get("Text")

				#Ł Each line of the block, numbered from 0 ({line}; nested lines take their block line's):
				#! Follows Spoken_Line.gd's voice_line.
				if text_lines is Array:
					for index in text_lines.size():
						var place := {"dialogue": dialogue_name, "conversation": str(conversation), "block": str(block), "line": str(index)}
						_find_lines(text_lines[index], place, symbols, lines)
				else:
					var place := {"dialogue": dialogue_name, "conversation": str(conversation), "block": str(block), "line": ""}
					_find_lines(block_data, place, symbols, lines)
	return {"lines": lines, "problems": problems}	#/ lines: [{"dialogue", "conversation", "block", "line", "actor", "voice", "variants"}]


#* Add the spoken lines in data, nested ones included:
static func _find_lines(data: Variant, place: Dictionary, symbols: Dictionary, lines: Array) -> void:
	if data is Array:
		for item in data:
			_find_lines(item, place, symbols, lines)
	elif data is Dictionary:
		for key in data:
			if str(key).to_lower() == "spoken_line" and data[key] is Dictionary:
				var line := _read_line(data[key], place, symbols)
				if not line.is_empty():
					lines.append(line)
			else:
				_find_lines(data[key], place, symbols, lines)


#* A spoken line's voice info, or {} for a full path:
static func _read_line(speech: Dictionary, place: Dictionary, symbols: Dictionary) -> Dictionary:
	var line := place.duplicate()

	#@ Step 1 - Speaker (null for a role or expression):
	var speaker = _literal(speech.get("Reference", ""), symbols["expression"])
	if speaker is String and symbols["role"] != "" and speaker.begins_with(symbols["role"]):
		speaker = null
	line["actor"] = speaker

	#@ Step 2 - File name:
	var voice = _literal(speech.get("Voice", ""), symbols["expression"])
	if voice is String:
		if voice.begins_with("res://") or voice.begins_with("user://"):
			return {}
		if voice == "":
			voice = DEFAULT_FILE
	line["voice"] = voice	#/ null: decided by the game

	#@ Step 3 - Variant folders:
	#! Follows Spoken_Line.gd's variant selection: TTS variants and ones without text are skipped.
	var variants: PackedStringArray = []
	var entries = speech.get("Variants", [])
	if entries is Array:
		for entry in entries:
			if not entry is Dictionary:
				continue
			for variant_name in entry:
				var variant_text := str(variant_name)
				if variant_text.ends_with("_TTS") or "_TTS_" in variant_text:
					continue
				if not entry[variant_name] is Dictionary or str(entry[variant_name].get("Text", "")) == "":
					continue
				var folder := ""
				if variant_text != DEFAULT_VARIANT:
					folder = variant_text.replace(":", "=")
				if not folder in variants:
					variants.append(folder)
	if variants.is_empty():
		variants.append("")
	line["variants"] = variants	#/ Folders, "" for Default
	return line


#* Text as CandyRef reads it, or null for an expression:
static func _literal(value: Variant, symbol: String) -> Variant:
	var text := str(value)
	if symbol == "" or not text.begins_with(symbol):
		return text
	var body := text.substr(symbol.length())
	if body.begins_with(symbol):
		return body	#/ A doubled symbol escapes it
	return null


#==============================================================================
#  FOLDERS
#==============================================================================

#* Every line's voice folder under a layout ({"folders", "problems"}):
static func folders(layout: Dictionary) -> Dictionary:
	var found: PackedStringArray = []
	var problems := layout_problems(layout)
	if not problems.is_empty():
		return {"folders": found, "problems": problems}
	var gathered := spoken_lines()
	problems.append_array(gathered["problems"])
	var placed_by_game := 0
	for line in gathered["lines"]:
		if _placed_by_game(line, [layout]):
			placed_by_game += 1
			continue
		for variant_folder in line["variants"]:
			var folder := line_files_folder(layout, line, variant_folder)
			if not folder in found:
				found.append(folder)
	if placed_by_game > 0:
		problems.append(placed_by_game_text(placed_by_game))
	found.sort()
	return {"folders": found, "problems": problems}


#* Whether the game places a line's files: no known actor, and a layout with {actor}:
static func _placed_by_game(line: Dictionary, layouts: Array) -> bool:
	if line["actor"] != null:
		return false
	for layout in layouts:
		if "{actor}" in String(layout["voice_path"]):
			return true
	return false


static func placed_by_game_text(count: int) -> String:
	return "Left out: %d spoken line%s whose speaker is given by a role or an expression. voice_path has an {actor} folder, so the game decides where their voice files go." % [count, _plural(count)]


#==============================================================================
#  MOVING
#==============================================================================

#* Plan a move between layouts, changing nothing:
#? gathered - spoken_lines(), if already read.
#? {
#?   "moves": [{"from", "to": [paths], "keep"}]  (keep: some lines still use it where it is)
#?   "blocked": [{"from", "to", "reason"}], "unused": [paths], "in_place": count,
#?   "placed_by_game", "named_by_game", "missing": counts of lines left out / files not found,
#?   "voice_folder", "old_folders", "new_folders": for removing emptied folders,
#?   "problems": what stops the move.
#? }
static func plan(from_layout: Dictionary, to_layout: Dictionary, gathered: Dictionary = {}) -> Dictionary:
	var result := {
		"moves": [], "blocked": [], "unused": PackedStringArray(), "in_place": 0,
		"placed_by_game": 0, "named_by_game": 0, "missing": 0,
		"voice_folder": _folder_key(from_layout["voice_folder"]),
		"old_folders": PackedStringArray(), "new_folders": PackedStringArray(),
		"problems": PackedStringArray(),
	}
	for problem in layout_problems(from_layout):
		result["problems"].append("From: " + problem)
	for problem in layout_problems(to_layout):
		result["problems"].append("To (Candy_Properties.gd): " + problem)
	if gathered.is_empty():
		gathered = spoken_lines()
	result["problems"].append_array(gathered["problems"])
	if not result["problems"].is_empty():
		return result

	#@ Step 1 - Each file's targets:
	var destinations := {}		#/ file -> [paths]
	var listings := {}			#/ folder -> its files' names
	for line in gathered["lines"]:
		if _placed_by_game(line, [from_layout, to_layout]):
			result["placed_by_game"] += 1
			continue
		if line["voice"] == null:
			result["named_by_game"] += 1
			continue
		#? Folders in the Voice value are in line_files_folder():
		var voice_name := String(line["voice"]).get_file()
		for variant_folder in line["variants"]:
			var old_folder := line_files_folder(from_layout, line, variant_folder)
			var new_folder := line_files_folder(to_layout, line, variant_folder)
			if not old_folder in result["old_folders"]:
				result["old_folders"].append(old_folder)
			if not new_folder in result["new_folders"]:
				result["new_folders"].append(new_folder)
			if not listings.has(old_folder):
				listings[old_folder] = _file_names(old_folder)
			var names := _matching_files(listings[old_folder], voice_name)
			if names.is_empty():
				result["missing"] += 1
				continue
			for file_name in names:
				var source := old_folder.path_join(file_name)
				if not destinations.has(source):
					destinations[source] = []
				var target := new_folder.path_join(file_name)
				if not target in destinations[source]:
					destinations[source].append(target)

	#@ Step 2 - Clashes -two files for one place, or a file already there:
	var sources_by_target := {}
	for source in destinations:
		for target in destinations[source]:
			if target != source:
				if not sources_by_target.has(target):
					sources_by_target[target] = []
				sources_by_target[target].append(source)
	var sources := destinations.keys()
	sources.sort()
	for source in sources:
		var targets: Array = destinations[source]
		var reason := ""
		for target in targets:
			if target == source:
				continue
			if sources_by_target[target].size() > 1:
				reason = "other files would go to the same place, %s" % target
			elif FileAccess.file_exists(target):
				reason = "there's already a file at %s" % target
		if reason != "":
			result["blocked"].append({"from": source, "to": targets, "reason": reason})
		elif targets == [source]:
			result["in_place"] += 1
		else:
			var others := targets.filter(func(target: String) -> bool: return target != source)
			result["moves"].append({"from": source, "to": others, "keep": source in targets})

	#@ Step 3 - Unused files:
	for path in _files_under(_folder_key(from_layout["voice_folder"])):
		if not destinations.has(path):
			result["unused"].append(path)
	return result


#* Make a planned move; record the new layout if nothing was left behind. Returns an error, or "":
func move(move_plan: Dictionary, to_layout: Dictionary, tree: SceneTree) -> String:
	moved.clear()
	copied.clear()
	failed.clear()
	folders_removed = 0
	layout_recorded = false
	var moves: Array = move_plan["moves"]
	for index in moves.size():
		var entry: Dictionary = moves[index]
		_move_file(entry["from"], entry["to"], entry["keep"])
		if index % FILES_PER_FRAME == 0:
			progress.emit(0.9 * index / max(moves.size(), 1), "Moving voice files… %d / %d" % [index, moves.size()])
			await tree.process_frame

	progress.emit(0.9, "Removing the folders left empty…")
	folders_removed = _remove_empty_folders(move_plan["old_folders"], move_plan["new_folders"], move_plan["voice_folder"])

	progress.emit(0.95, "Letting Godot scan the files…")
	await Utils.scan_filesystem(tree)

	if failed.is_empty() and move_plan["blocked"].is_empty():
		var record_error := record_layout(to_layout)
		if record_error != "":
			return record_error
		layout_recorded = true
	progress.emit(1.0, "Done.")
	return ""


#* Move a file to its first target, with its sidecars (keeps its UID), copy to the rest:
#? keep - copy to every target instead.
func _move_file(source: String, targets: Array, keep: bool) -> void:
	for index in targets.size():
		var target: String = targets[index]
		var folder_error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if folder_error != OK:
			failed.append("Couldn't create %s (%s): %s wasn't moved." % [target.get_base_dir(), error_string(folder_error), source])
			return
	for index in targets.size():
		var target: String = targets[index]
		if index == 0 and not keep:
			continue
		var copy_error := DirAccess.copy_absolute(source, target)
		if copy_error != OK:
			failed.append("Couldn't copy %s to %s (%s)." % [source, target, error_string(copy_error)])
		else:
			copied.append([source, target])
	if keep:
		return
	var move_error := DirAccess.rename_absolute(source, targets[0])
	if move_error != OK:
		failed.append("Couldn't move %s to %s (%s)." % [source, targets[0], error_string(move_error)])
		return
	moved.append([source, targets[0]])
	for extension in SIDECAR_EXTENSIONS:
		var sidecar: String = source + "." + extension
		if FileAccess.file_exists(sidecar):
			DirAccess.rename_absolute(sidecar, targets[0] + "." + extension)


#* Remove emptied old folders under the voice folder, keeping new_folders. Returns the count:
static func _remove_empty_folders(old_folders: PackedStringArray, new_folders: PackedStringArray, voice_folder: String) -> int:
	var kept := {}
	for folder in new_folders:
		var current := folder
		while current.begins_with(voice_folder + "/") and not kept.has(current):
			kept[current] = true
			current = current.get_base_dir()
	var candidates: PackedStringArray = []
	for folder in old_folders:
		var current := folder
		while current.begins_with(voice_folder + "/") and not current in candidates:
			if not kept.has(current):
				candidates.append(current)
			current = current.get_base_dir()
	#? Deepest first:
	var sorted := Array(candidates)
	sorted.sort_custom(func(a: String, b: String) -> bool: return a.count("/") > b.count("/"))
	var removed := 0
	for folder in sorted:
		if not DirAccess.dir_exists_absolute(folder) or _has_content(folder):
			continue
		if DirAccess.remove_absolute(folder) == OK:
			removed += 1
	return removed


#* Whether a folder holds anything, hidden files included:
static func _has_content(folder: String) -> bool:
	var dir := DirAccess.open(folder)
	if dir == null:
		return true
	dir.include_hidden = true
	return not dir.get_files().is_empty() or not dir.get_directories().is_empty()


#==============================================================================
#  FILES
#==============================================================================

#* A folder's own files, without sidecars:
static func _file_names(folder: String) -> PackedStringArray:
	var names: PackedStringArray = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return names
	for file_name in dir.get_files():
		if not file_name.get_extension() in SIDECAR_EXTENSIONS:
			names.append(file_name)
	return names


#* Files matching a Voice value (any extension if it has none):
static func _matching_files(names: PackedStringArray, voice: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file_name in names:
		if file_name == voice or (voice.get_extension() == "" and file_name.get_basename() == voice):
			found.append(file_name)
	return found


#* Files under a folder, without sidecars, sorted:
static func _files_under(folder: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if not file_name.get_extension() in SIDECAR_EXTENSIONS:
			found.append(folder.path_join(file_name))
	for sub_folder in dir.get_directories():
		found.append_array(_files_under(folder.path_join(sub_folder)))
	found.sort()
	return found


#==============================================================================
#  TEXT
#==============================================================================

static func _plural(count: int) -> String:
	if count == 1:
		return ""
	return "s"
