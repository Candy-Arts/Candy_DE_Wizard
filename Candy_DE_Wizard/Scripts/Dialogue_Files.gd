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
const DialogueConverter = preload("Dialogue_Converter.gd")
const VariationRepair = preload("Variation_Repair.gd")
const LineSchemas = preload("Line_Schemas.gd")

const KIND_DIALOGUE := "Dialogue"
const KIND_SAVE := "Save"
const KIND_PRESETS := "Presets"

#^ What inspect() found:
const STATUS_CONVERT := "convert"
const STATUS_CURRENT := "current"
const STATUS_OLD := "old"
const STATUS_UNREADABLE := "unreadable"

#^ Planned files are OUTCOME_CONVERTED, with their "text":
const OUTCOME_CONVERTED := "converted"
const OUTCOME_SKIPPED := "skipped"
const OUTCOME_FAILED := "failed"

const BACKUP_FOLDER := CandyDEData.CONVERSION_BACKUPS_FOLDER
const BACKUP_KIND_FOLDER := "1.1 to 1.2"
const LOG_FILE := "Conversion Log.txt"
const PRESET_KEYS := ["USER PRESETS", "PROFILE PRESETS"]
const VERSION_HEADER := "Creator Version:"
const COMMENT := "#"
#^ Where a dialogue records its symbols, in its Meta (Symbol_Updater.SYMBOLS_KEY):
const SYMBOLS_KEY := "Symbols"

#^ Written file's meta (CandyDialogueExport.export_text(), CandySaves.DIALOGUE_VERSION):
const DIALOGUE_VERSION := "1.2"
const EXPORTED_BY := "Candy Wizard"


#==============================================================================
#  READING
#==============================================================================

#* Inspect a file - {"path", "kind", "version", "status", "problem", "data", "header" ("#" lines), "raw"}:
static func inspect(path: String) -> Dictionary:
	var info := {"path": path, "kind": "", "version": "", "status": STATUS_UNREADABLE,
		"problem": "", "data": {}, "header": PackedStringArray(), "raw": ""}
	if not FileAccess.file_exists(path):
		info["problem"] = "The file doesn't exist."
		return info
	var raw := FileAccess.get_file_as_string(path)
	info["raw"] = raw
	var header := PackedStringArray()
	var body := PackedStringArray()
	for line in raw.split("\n"):
		if line.strip_edges().begins_with(COMMENT):
			if body.is_empty():
				header.append(line.strip_edges())
			continue
		body.append(line)
	info["header"] = header
	var data = _parse("\n".join(body))
	if not data is Dictionary:
		data = _parse_as_candy_de(raw)
	if not data is Dictionary:
		info["problem"] = "This isn't a dialogue file Candy Wizard can read."
		return info
	info["data"] = data

	var version := ""
	if _preset_key(data) != "":
		info["kind"] = KIND_PRESETS
		for line in header:
			var at := line.find(VERSION_HEADER)
			if at >= 0:
				version = line.substr(at + VERSION_HEADER.length()).strip_edges()
	elif data.get("Meta") is Dictionary and data.get("Dialogue") is Dictionary:
		info["kind"] = KIND_DIALOGUE
		version = str(data["Meta"].get("Dialogue Version", ""))
	elif data.get("Dialogue") is Dictionary and (data.has("Dialogue Version") or data.has("Type")):
		info["kind"] = KIND_SAVE
		version = str(data.get("Dialogue Version", ""))
	elif data.get("Dialogue") is Dictionary or _looks_like_conversations(data):
		info["kind"] = KIND_DIALOGUE
	else:
		info["problem"] = "This isn't a dialogue file Candy Wizard can read."
		return info
	version = version.strip_edges()
	info["version"] = version

	if version.begins_with("1.2"):
		info["status"] = STATUS_CURRENT
		info["problem"] = "Already in the 1.2 format."
	elif version.begins_with("1.0"):
		info["status"] = STATUS_OLD
		info["problem"] = "A 1.0 file: convert it to 1.1 with Candy Dialogue Creator 1.1's converter first."
	elif version.begins_with("1.1") or _has_old_commands(data):
		info["status"] = STATUS_CONVERT
	elif version == "":
		info["status"] = STATUS_CURRENT
		info["problem"] = "Nothing in it was written for Candy DE 1.1."
	else:
		info["status"] = STATUS_UNREADABLE
		info["problem"] = "Unknown format version: %s." % version
	if info["status"] == STATUS_CONVERT and info["kind"] != KIND_DIALOGUE:
		#? Candy DC's own files are Candy DC's to convert:
		info["status"] = STATUS_UNREADABLE
		info["problem"] = "A Candy Dialogue Creator %s file: convert it with Candy DC's Dialogue Converter (Edit > Dialogue Converter...)." % String(info["kind"]).to_lower()
	return info


#* File list description, e.g. "Dialogue, format 1.1.0":
static func describe(info: Dictionary) -> String:
	var kind := str(info.get("kind", ""))
	if kind == "":
		return "Not readable"
	var version := str(info.get("version", ""))
	if version == "":
		return kind
	if kind == KIND_PRESETS:
		return "%s, Candy DC %s" % [kind, version]
	return "%s, format %s" % [kind, version]


#* Parse as GDScript data (<null> accepted, as 1.1.3 did), else JSON:
static func _parse(text: String) -> Variant:
	var stripped := text.strip_edges()
	if stripped == "":
		return null
	var data = str_to_var(stripped)
	if data is Dictionary:
		return data
	data = str_to_var(stripped.replace("<null>", "null"))
	if data is Dictionary:
		return data
	data = JSON.parse_string(stripped)
	if data is Dictionary:
		return data
	return null


#* Parse as Candy DE reads a dialogue, or null:
static func _parse_as_candy_de(text: String) -> Variant:
	var expression := Expression.new()
	if expression.parse(CandyDEData._clean_dialogue_source(text)) != OK:
		return null
	var data = expression.execute([], null, false)
	if expression.has_execute_failed() or not data is Dictionary:
		return null
	return data


static func _preset_key(data: Dictionary) -> String:
	for key in PRESET_KEYS:
		if data.get(key) is Dictionary:
			return key
	return ""


#* Whether data is bare {conversation = {block = {"Text" = [...]}}}:
static func _looks_like_conversations(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	for conversation in data.values():
		if not conversation is Dictionary:
			return false
		for block in conversation.values():
			if not block is Dictionary or not block.get(DialogueConverter.TEXT_KEY) is Array:
				return false
	return true


static func _has_old_commands(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			var text := str(key)
			if text.begins_with("§") or text == "Spoken Line":
				return true
			if _has_old_commands(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _has_old_commands(item):
				return true
	return false


#==============================================================================
#  CONVERTING
#==============================================================================

#* Convert files in memory, writing nothing. One result per file:
#? written_symbols: recorded in each file's Meta (Symbol_Files.converted_symbols()).
static func plan_files(paths: Array, old_symbols: Dictionary, new_symbols: Dictionary, project: Dictionary, written_symbols: Dictionary = {}) -> Array:
	var schemas = LineSchemas.new()
	var results: Array = []
	for path in paths:
		results.append(_plan_file(str(path), old_symbols, new_symbols, project, schemas, written_symbols))
	return results


static func _plan_file(path: String, old_symbols: Dictionary, new_symbols: Dictionary, project: Dictionary, schemas, written_symbols: Dictionary) -> Dictionary:
	var info := inspect(path)
	var result := {"path": path, "kind": info["kind"], "version": info["version"], "outcome": OUTCOME_SKIPPED,
		"message": str(info["problem"]), "backup": "", "notes": [], "text": "", "raw": ""}
	match str(info["status"]):
		STATUS_CURRENT:
			return result
		STATUS_OLD, STATUS_UNREADABLE:
			result["outcome"] = OUTCOME_FAILED
			return result
	if schemas.problem != "":
		result["outcome"] = OUTCOME_FAILED
		result["message"] = schemas.problem
		return result

	var data: Dictionary = info["data"]
	var conversations: Dictionary = {}
	if data.get("Dialogue") is Dictionary:
		conversations = data["Dialogue"]
	else:
		conversations = data

	var converter = DialogueConverter.new(old_symbols, new_symbols, project, schemas)
	var converted: Dictionary = converter.convert_conversations(conversations, true)
	var notes: Array = converter.notes

	#Ł Repair variation names:
	var repair = VariationRepair.new().check(converted)
	for entry in repair.entries:
		for problem in entry["problems"]:
			notes.append({"where": entry["where"], "level": DialogueConverter.LEVEL_CHECK,
				"text": "Variation %s: %s" % [entry["variation"], problem]})
	if repair.has_problems():
		result["outcome"] = OUTCOME_FAILED
		result["message"] = "Some variation names have problems that can't be fixed (listed below). Fix them in the file, then convert it again."
		result["notes"] = notes
		return result
	for entry in repair.entries:
		var fixes: PackedStringArray = []
		for fix in entry["fixes"]:
			fixes.append("%s %s" % [fix["problem"], fix["fix"]])
		notes.append({"where": entry["where"], "level": DialogueConverter.LEVEL_NOTE,
			"text": "Variation %s renamed %s. %s" % [entry["variation"], entry["fixed"], " ".join(fixes)]})
	repair.apply()

	result["outcome"] = OUTCOME_CONVERTED
	result["message"] = ""
	result["notes"] = notes
	result["text"] = export_text(converted, written_symbols)
	result["raw"] = info["raw"]
	return result


#* Back up and write plan_files()' results, then the log. Sets each result's outcome, message and backup:
static func convert_files(results: Array, wizard_version: String) -> void:
	var stamp := make_stamp()
	var backup_folders: Array = []
	for result in results:
		if str(result["outcome"]) != OUTCOME_CONVERTED or str(result["text"]) == "":
			continue
		_write_file(result, stamp)
		var backup := str(result.get("backup", ""))
		if backup != "" and not (backup.get_base_dir() in backup_folders):
			backup_folders.append(backup.get_base_dir())
	var log_text := "\n".join(report_lines(results, wizard_version)) + "\n"
	for folder in backup_folders:
		var file := FileAccess.open(str(folder).path_join(LOG_FILE), FileAccess.WRITE)
		if file != null:
			file.store_string(log_text)
			file.close()


static func _write_file(result: Dictionary, stamp: String) -> void:
	var path := str(result["path"])
	var backup := backup_path(path, stamp)
	var problem := write_file(backup, str(result["raw"]))
	if problem != "":
		result["outcome"] = OUTCOME_FAILED
		result["message"] = "Couldn't back the file up, so it wasn't converted. %s" % problem
		return
	result["backup"] = backup
	problem = write_file(path, str(result["text"]))
	if problem != "":
		result["outcome"] = OUTCOME_FAILED
		result["message"] = "Couldn't write the converted file. The original is unchanged. %s" % problem
		return
	result["outcome"] = OUTCOME_CONVERTED
	result["message"] = ""


static func backup_path(path: String, stamp: String) -> String:
	return path.get_base_dir().path_join(BACKUP_FOLDER).path_join(BACKUP_KIND_FOLDER).path_join(stamp).path_join(path.get_file())


#* Write a file. Returns an error, or "":
static func write_file(path: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "(%s: %s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_string(text)
	file.close()
	return ""


#* Backup stamp, as Candy DC's (D-2026-10-07_T-08-01-00):
static func make_stamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "D-%04d-%02d-%02d_T-%02d-%02d-%02d" % [now["year"], now["month"], now["day"],
		now["hour"], now["minute"], now["second"]]


#==============================================================================
#  WRITING (CandyDialogueExport.export_text(), CandyVariantFile.stringify())
#==============================================================================

#* Full file text for a dialogue:
#? symbols: the ones it's written with, recorded in its Meta (Symbol_Files.converted_symbols()).
static func export_text(dialogue: Dictionary, symbols: Dictionary = {}) -> String:
	var meta := {
		"Exported By": EXPORTED_BY,
		"Dialogue Version": DIALOGUE_VERSION,
	}
	if not symbols.is_empty():
		meta[SYMBOLS_KEY] = symbols
	var data := {
		"Meta": meta,
		"Dialogue": dialogue,
	}
	var header := "%s Exported By: %s\n" % [COMMENT, EXPORTED_BY]
	header += "%s Dialogue Version: %s\n\n" % [COMMENT, DIALOGUE_VERSION]
	return header + stringify(data) + "\n"


#* GDScript literal, laid out as Candy DC writes it:
static func stringify(value: Variant, depth: int = 0) -> String:
	var indent := "    ".repeat(depth)
	var indent_inner := "    ".repeat(depth + 1)

	if value is Dictionary:
		if value.is_empty():
			return "{}"
		var has_nested := false
		for item in value.values():
			if item is Dictionary or item is Array:
				has_nested = true
				break
		#¦ 1. Flat dictionary on one line:
		if not has_nested:
			var pairs := []
			for key in value.keys():
				pairs.append("%s: %s" % [stringify(key, depth + 1), stringify(value[key], depth + 1)])
			return "{ " + ", ".join(pairs) + " }"
		#¦ 2. Others one key per line:
		var lines := []
		for key in value.keys():
			lines.append("%s%s: %s" % [indent_inner, stringify(key, depth + 1), stringify(value[key], depth + 1)])
		return "{\n" + ",\n".join(lines) + "\n" + indent + "}"

	elif value is Array:
		if value.is_empty():
			return "[]"
		#Ł One element per line:
		var items := []
		for item in value:
			items.append(indent_inner + stringify(item, depth + 1))
		return "[\n" + ",\n".join(items) + "\n" + indent + "]"

	elif value is String or value is StringName:
		return _quote(str(value))

	elif value is bool:
		if value:
			return "true"
		return "false"

	elif value == null:
		return "null"

	elif value is Color:
		return var_to_str(value)

	elif value is int or value is float:
		return str(value)

	return var_to_str(value)


#* Quote a string, escaping control characters:
static func _quote(text: String) -> String:
	var escaped := text.replace("\\", "\\\\")
	escaped = escaped.replace("\"", "\\\"")
	escaped = escaped.replace("\n", "\\n")
	escaped = escaped.replace("\r", "\\r")
	escaped = escaped.replace("\t", "\\t")
	return "\"" + escaped + "\""


#==============================================================================
#  REPORT
#==============================================================================

#* Group a result's notes by text, checks first - [{"text", "level", "wheres" = [...]}]:
static func grouped_notes(result: Dictionary) -> Array:
	var groups: Array = []
	var by_text := {}
	for level in [DialogueConverter.LEVEL_CHECK, DialogueConverter.LEVEL_NOTE]:
		for note in result.get("notes", []):
			if str(note["level"]) != level:
				continue
			var key: String = str(level) + "\n" + str(note["text"])
			if not by_text.has(key):
				by_text[key] = {"text": note["text"], "level": level, "wheres": []}
				groups.append(by_text[key])
			by_text[key]["wheres"].append(note["where"])
	return groups


#* The run's log:
static func report_lines(results: Array, wizard_version: String) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Candy Wizard %s: Dialogue Converter, 1.1 to 1.2" % wizard_version)
	lines.append(Time.get_datetime_string_from_system(false, true))
	for result in results:
		lines.append("")
		lines.append(str(result["path"]))
		lines.append("    %s" % outcome_text(result))
		if str(result.get("backup", "")) != "":
			lines.append("    Backup: %s" % result["backup"])
		for group in grouped_notes(result):
			var mark := "Check"
			if str(group["level"]) == DialogueConverter.LEVEL_NOTE:
				mark = "Note"
			lines.append("    %s: %s" % [mark, group["text"]])
			for where in group["wheres"]:
				lines.append("        %s" % where)
	return lines


static func outcome_text(result: Dictionary) -> String:
	match str(result["outcome"]):
		OUTCOME_CONVERTED:
			return "Converted (%s)." % str(result["kind"]).to_lower()
		OUTCOME_SKIPPED:
			return "Skipped: %s" % result["message"]
	return "Not converted: %s" % result["message"]
