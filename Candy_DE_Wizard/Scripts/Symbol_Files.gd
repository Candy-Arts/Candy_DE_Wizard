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
const DialogueFiles = preload("Dialogue_Files.gd")
const DialogueOptions = preload("Dialogue_Options.gd")
const DialogueConverter = preload("Dialogue_Converter.gd")
const SymbolUpdater = preload("Symbol_Updater.gd")
const Rules = preload("Symbol_Rules.gd")

#^ What inspect() found:
const STATUS_UPDATE := "update"
const STATUS_MATCH := "match"
const STATUS_NOT_STORED := "not stored"
const STATUS_NOT_CURRENT := "not current"
const STATUS_OTHER_KIND := "other kind"
const STATUS_UNREADABLE := "unreadable"

#^ Planned files are OUTCOME_CONVERTED, with their "text":
const OUTCOME_UPDATED := DialogueFiles.OUTCOME_CONVERTED
const OUTCOME_SKIPPED := DialogueFiles.OUTCOME_SKIPPED
const OUTCOME_FAILED := DialogueFiles.OUTCOME_FAILED

#^ Candy DC's Symbol Updater backs up in the same place (CandySymbolUpdater):
const BACKUP_KIND_FOLDER := "Symbols"
const LOG_FILE := "Symbol Update Log.txt"


#==============================================================================
#  THE PROJECT'S SYMBOLS
#==============================================================================

#* The symbols Candy DE reads - Candy_Properties.gd's, and CandyRef_Shortcuts.gd's tables:
#? {"symbols", "problem" ("" if they can be used)}.
static func project_symbols() -> Dictionary:
	var symbols := {}
	var problems: PackedStringArray = []
	for symbol in Rules.SYMBOLS:
		var variable: String = symbol["variable"]
		var value = CandyDEData.property(variable)
		if value is String:
			symbols[variable] = value
		elif symbol.get("optional", false):
			#? A Candy DE from before the symbol existed doesn't read it.
			symbols[variable] = symbol["default"]
		else:
			symbols[variable] = ""
			problems.append("Candy_Properties.gd has no \"var %s = ...\" line with a plain value." % variable)
	symbols[SymbolUpdater.SHORTCUTS] = {}
	symbols[SymbolUpdater.LOOKUPS] = {}
	if FileAccess.file_exists(CandyDEData.USER_SHORTCUTS_PATH):
		var tables := SymbolUpdater.read_candy_ref_tables(FileAccess.get_file_as_string(CandyDEData.USER_SHORTCUTS_PATH))
		symbols[SymbolUpdater.SHORTCUTS] = tables[SymbolUpdater.SHORTCUTS]
		symbols[SymbolUpdater.LOOKUPS] = tables[SymbolUpdater.LOOKUPS]
		if str(tables["problem"]) != "":
			problems.append("CandyRef_Shortcuts.gd: %s" % tables["problem"])
	if problems.is_empty():
		var unusable := SymbolUpdater.symbol_problems(symbols)
		if unusable != "":
			problems.append(unusable)
	return {"symbols": symbols, "problem": " ".join(problems)}


#* The symbols a dialogue the Dialogue Converter writes is written with:
#? The converter writes the 1.2 symbols, but keeps the 1.1 variable dictionary, role and separator symbols.
#? old_symbols / new_symbols: the converter's, by its keys.
static func converted_symbols(old_symbols: Dictionary, new_symbols: Dictionary) -> Dictionary:
	var symbols: Dictionary = project_symbols()["symbols"]
	for key in DialogueOptions.NEW_SYMBOL_SETTINGS:
		if new_symbols.has(key):
			symbols[DialogueOptions.NEW_SYMBOL_SETTINGS[key]] = str(new_symbols[key])
	var old := DialogueConverter.default_old_symbols()
	old.merge(old_symbols, true)
	for variable in [SymbolUpdater.VARDICT, SymbolUpdater.ROLE, SymbolUpdater.SEPARATOR]:
		symbols[variable] = str(old.get(variable, symbols.get(variable, "")))
	return symbols


#==============================================================================
#  READING
#==============================================================================

#* Inspect a dialogue for an update to new_symbols:
#? Dialogue_Files.inspect()'s info, with "status", "problem", "symbols" (the ones it records)
#? and "differences" (SymbolUpdater.differences()).
static func inspect(path: String, new_symbols: Dictionary) -> Dictionary:
	var info := DialogueFiles.inspect(path)
	info["symbols"] = {}
	info["differences"] = []
	if str(info["kind"]) == "":
		info["status"] = STATUS_UNREADABLE
		return info
	if str(info["kind"]) != DialogueFiles.KIND_DIALOGUE:
		info["status"] = STATUS_OTHER_KIND
		info["problem"] = "A Candy Dialogue Creator %s file: update it with Candy Dialogue Creator's Symbol Updater (Edit > Symbol Updater...)." % str(info["kind"]).to_lower()
		return info
	if str(info["status"]) != DialogueFiles.STATUS_CURRENT:
		info["status"] = STATUS_NOT_CURRENT
		info["problem"] = "Not in the 1.2 format: convert it with the Dialogue Converter tool first."
		return info
	var defaults := {}
	for symbol in Rules.SYMBOLS:
		defaults[symbol["variable"]] = symbol["default"]
	var stored := SymbolUpdater.stored_symbols(info["data"], defaults)
	if stored.is_empty():
		info["status"] = STATUS_NOT_STORED
		info["problem"] = "It doesn't record the symbols it was written with, so they can't be compared or updated. Tick it and press Record Symbols… to record them: the symbols you enter are written into it, and nothing else changes."
		return info
	info["symbols"] = stored
	info["differences"] = SymbolUpdater.differences(stored, new_symbols)
	if info["differences"].is_empty():
		info["status"] = STATUS_MATCH
		info["problem"] = "Its symbols match the project's."
		return info
	var unusable := SymbolUpdater.symbol_problems(stored)
	if unusable != "":
		info["status"] = STATUS_UNREADABLE
		info["problem"] = "The symbols it records can't be used: %s" % unusable
		return info
	info["status"] = STATUS_UPDATE
	info["problem"] = ""
	return info


#==============================================================================
#  UPDATING
#==============================================================================

#* Update files in memory, writing nothing. One result per file:
#? Result: {"path", "outcome", "message", "notes", "changed" (values changed), "text", "raw", "backup"}.
static func plan_files(paths: Array, new_symbols: Dictionary) -> Array:
	var results: Array = []
	for path in paths:
		results.append(_plan_file(str(path), new_symbols))
	return results


static func _plan_file(path: String, new_symbols: Dictionary) -> Dictionary:
	var info := inspect(path, new_symbols)
	var result := {"path": path, "outcome": OUTCOME_SKIPPED, "message": str(info["problem"]),
		"notes": [], "changed": 0, "text": "", "raw": "", "backup": ""}
	match str(info["status"]):
		STATUS_MATCH:
			return result
		STATUS_UPDATE:
			pass
		_:
			result["outcome"] = OUTCOME_FAILED
			return result
	var unusable := SymbolUpdater.symbol_problems(new_symbols)
	if unusable != "":
		result["outcome"] = OUTCOME_FAILED
		result["message"] = "The project's symbols can't be used: %s Fix them in the Symbols tool." % unusable
		return result

	var data: Dictionary = info["data"]
	var conversations = data.get("Dialogue")
	if not conversations is Dictionary:
		result["outcome"] = OUTCOME_FAILED
		result["message"] = "Its Dialogue isn't a dictionary."
		return result
	var updater = SymbolUpdater.new(info["symbols"], new_symbols)
	var updated: Dictionary = updater.update_conversations(conversations)

	result["outcome"] = OUTCOME_UPDATED
	result["message"] = ""
	result["notes"] = updater.notes
	result["changed"] = updater.changed_values
	result["text"] = _file_text(info, updated, new_symbols)
	result["raw"] = info["raw"]
	return result


#* Record the symbols dialogues were written with, in memory, writing nothing. One result per file:
#? For dialogues that don't record theirs (STATUS_NOT_STORED). Nothing else in them changes.
#? Result as plan_files()', with "recorded": true.
static func plan_records(paths: Array, symbols: Dictionary) -> Array:
	var results: Array = []
	var unusable := SymbolUpdater.symbol_problems(symbols)
	for path in paths:
		var info := inspect(str(path), symbols)
		var result := {"path": str(path), "outcome": OUTCOME_FAILED, "message": "", "notes": [], "changed": 0,
			"text": "", "raw": "", "backup": "", "recorded": true}
		results.append(result)
		match str(info["status"]):
			STATUS_NOT_STORED:
				pass
			STATUS_MATCH, STATUS_UPDATE:
				result["outcome"] = OUTCOME_SKIPPED
				result["message"] = "It already records its symbols."
				continue
			_:
				result["message"] = str(info["problem"])
				continue
		if unusable != "":
			result["message"] = "The symbols entered can't be used: %s" % unusable
			continue
		#? Wrapped (Meta and Dialogue), or bare (conversations at the root):
		var data: Dictionary = info["data"]
		var conversations = data
		if data.has("Dialogue"):
			conversations = data["Dialogue"]
		if not conversations is Dictionary:
			result["message"] = "Its Dialogue isn't a dictionary."
			continue
		result["outcome"] = OUTCOME_UPDATED
		result["text"] = _file_text(info, conversations, symbols)
		result["raw"] = info["raw"]
	return results


#* A dialogue file's new text - as it was, with these conversations and these symbols recorded:
#? Its header comments and other Meta keys are kept. A bare dialogue is wrapped, with a Meta of its own.
static func _file_text(info: Dictionary, conversations: Dictionary, symbols: Dictionary) -> String:
	var data: Dictionary = info["data"]
	var written := {}
	if data.has("Dialogue"):
		written = data.duplicate()
	var meta := {}
	if data.get("Meta") is Dictionary:
		meta = data["Meta"].duplicate()
	if not meta.has("Dialogue Version"):
		meta["Dialogue Version"] = DialogueFiles.DIALOGUE_VERSION
	meta[SymbolUpdater.SYMBOLS_KEY] = symbols.duplicate(true)
	written["Meta"] = meta
	written["Dialogue"] = conversations
	var text := ""
	var header: PackedStringArray = info["header"]
	if not header.is_empty():
		text = "\n".join(header) + "\n\n"
	return text + DialogueFiles.stringify(written) + "\n"


#* Back up and write plan_files()' results, then the log. Sets each result's outcome, message and backup:
static func update_files(results: Array, wizard_version: String) -> void:
	var stamp := DialogueFiles.make_stamp()
	var backup_folders: Array = []
	for result in results:
		if str(result["outcome"]) != OUTCOME_UPDATED or str(result["text"]) == "":
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
	var problem := DialogueFiles.write_file(backup, str(result["raw"]))
	if problem != "":
		result["outcome"] = OUTCOME_FAILED
		result["message"] = "Couldn't back the file up, so it wasn't updated. %s" % problem
		return
	result["backup"] = backup
	problem = DialogueFiles.write_file(path, str(result["text"]))
	if problem != "":
		result["outcome"] = OUTCOME_FAILED
		result["message"] = "Couldn't write the updated file. The original is unchanged. %s" % problem
		return
	result["outcome"] = OUTCOME_UPDATED
	result["message"] = ""


static func backup_path(path: String, stamp: String) -> String:
	return path.get_base_dir().path_join(DialogueFiles.BACKUP_FOLDER).path_join(BACKUP_KIND_FOLDER).path_join(stamp).path_join(path.get_file())


#==============================================================================
#  REPORT
#==============================================================================

#* The run's log:
static func report_lines(results: Array, wizard_version: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var title := "Symbol Updater"
	if not results.is_empty() and results[0].get("recorded", false):
		title = "Symbol Updater, recording symbols"
	lines.append("Candy Wizard %s: %s" % [wizard_version, title])
	lines.append(Time.get_datetime_string_from_system(false, true))
	for result in results:
		lines.append("")
		lines.append(str(result["path"]))
		lines.append("    %s" % outcome_text(result))
		if str(result.get("backup", "")) != "":
			lines.append("    Backup: %s" % result["backup"])
		for group in DialogueFiles.grouped_notes(result):
			var mark := "Check"
			if str(group["level"]) == SymbolUpdater.LEVEL_NOTE:
				mark = "Note"
			lines.append("    %s: %s" % [mark, group["text"]])
			for where in group["wheres"]:
				lines.append("        %s" % where)
	return lines


static func outcome_text(result: Dictionary) -> String:
	match str(result["outcome"]):
		OUTCOME_UPDATED:
			if result.get("recorded", false):
				return "Symbols recorded."
			var changed := int(result.get("changed", 0))
			if changed == 0:
				return "Updated: no value used a changed symbol, only the symbols it records changed."
			var values_word := "values"
			if changed == 1:
				values_word = "value"
			return "Updated: %d %s changed." % [changed, values_word]
		OUTCOME_SKIPPED:
			return "Skipped: %s" % result["message"]
	return "Not updated: %s" % result["message"]
