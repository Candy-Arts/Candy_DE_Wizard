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


#+ Finds, in the developer's own scripts and scenes, what Candy DE 1.2 renamed, removed or reads
#+ differently (Data/Upgrade_Code_Rules.json), for the upgrade report.
#+ A rule: {id, group, files (extensions), regex (one line), old, new, note, check, role_symbol}:
#+ old, new and note write code in backticks; "check" marks a rule that may be a false alarm
#+ (the name has other uses, or the value may be plain text); "role_symbol" one whose ° is the
#+ project's role symbol.
#+ Only names written out are found: code that builds them, or reads them through variables, isn't.

const Utils = preload("Wizard_Utils.gd")

const RULES_PATH := "Data/Upgrade_Code_Rules.json"
#^ The files searched:
const EXTENSIONS := ["gd", "tscn", "tres"]


#* The rules, or [] when the file is missing or damaged. Rules marked "role_symbol" are
#* written with 1.1.3's default, °: the project's own replaces it.
static func load_rules(role_symbol: String = "°") -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Utils.wizard_folder().path_join(RULES_PATH)))
	if not parsed is Array:
		return []
	var rules: Array = []
	for rule in parsed:
		if not rule is Dictionary or not rule.has("regex"):
			continue
		var pattern := String(rule["regex"])
		if rule.get("role_symbol", false):
			pattern = pattern.replace("°", _regex_escaped(role_symbol))
		var regex := RegEx.create_from_string(pattern)
		if not regex.is_valid():
			push_warning("Candy Wizard: the code rule %s has an invalid pattern." % rule.get("id", "?"))
			continue
		var compiled: Dictionary = rule.duplicate()
		compiled["compiled"] = regex
		rules.append(compiled)
	return rules


static func _regex_escaped(text: String) -> String:
	var escaped := ""
	for character in text:
		if character in "\\^$.|?*+()[]{}":
			escaped += "\\"
		escaped += character
	return escaped


#* The project's files to search: every script and scene under res://, but for the skipped
#* folders, hidden ones and those Godot ignores (.gdignore).
static func project_files(skipped: PackedStringArray) -> PackedStringArray:
	var found: PackedStringArray = []
	_walk("res://", skipped, found)
	return found


static func _walk(folder: String, skipped: PackedStringArray, found: PackedStringArray) -> void:
	if folder.trim_suffix("/") in skipped or FileAccess.file_exists(folder.path_join(".gdignore")):
		return
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() in EXTENSIONS:
			found.append(folder.path_join(file_name))
	for sub_folder in dir.get_directories():
		if not sub_folder.begins_with("."):
			_walk(folder.path_join(sub_folder), skipped, found)


#* Every rule a file matches: [{rule, hits: [{path, line, text}]}], in the rules' order.
#* shown_paths: path -> the path the report gives (a file moved aside), else the path itself.
static func scan(rules: Array, paths: PackedStringArray, shown_paths: Dictionary = {}) -> Array:
	var hits_by_rule := {}
	for path in paths:
		var extension := path.get_extension().to_lower()
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		var lines := text.replace("\r\n", "\n").split("\n")
		for index in lines.size():
			var line := lines[index]
			#? A commented-out line breaks nothing.
			if extension == "gd" and line.strip_edges().begins_with("#"):
				continue
			#? A line a rule found needs no "check" rule (one that may be a false alarm) as well.
			var matched: Array = []
			var found_change := false
			for rule_index in rules.size():
				var rule: Dictionary = rules[rule_index]
				if not extension in rule.get("files", EXTENSIONS):
					continue
				if (rule["compiled"] as RegEx).search(line) == null:
					continue
				matched.append(rule_index)
				if not rule.get("check", false):
					found_change = true
			for rule_index in matched:
				if found_change and rules[rule_index].get("check", false):
					continue
				if not hits_by_rule.has(rule_index):
					hits_by_rule[rule_index] = []
				hits_by_rule[rule_index].append({"path": shown_paths.get(path, path), "line": index + 1, "text": line.strip_edges()})
	var findings: Array = []
	for rule_index in rules.size():
		if hits_by_rule.has(rule_index):
			var rule: Dictionary = rules[rule_index].duplicate()
			rule.erase("compiled")
			findings.append({"rule": rule, "hits": hits_by_rule[rule_index]})
	return findings
