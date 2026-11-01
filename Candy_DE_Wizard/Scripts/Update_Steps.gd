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

#^ Each action, and the fields it needs:
#! Must match STEP_ACTIONS in Release_Tools/Build_Release.gd.
#! A release using an action this list lacks needs a newer Candy Wizard.
const ACTIONS := {
	"move": ["from", "to"],							#/ A file or folder, with its .uid / .import
	"add_variable": ["file", "variable", "text"],	#/ Optional "after": a variable to put it under
	"set_variable": ["file", "variable", "value"],	#/ Optional "only_if": the value it must have now
	"rename_variable": ["file", "from", "to"],
	"replace_text": ["file", "find", "replace"],
	"rename_input_action": ["from", "to"],
	"manual": ["title", "text"],
}

#^ The actions that change a file's text:
const TEXT_ACTIONS := ["add_variable", "set_variable", "rename_variable", "replace_text"]

#^ What apply_text() found:
const DONE := "done"				#/ The text was changed
const ALREADY := "already"			#/ Nothing to do: the change is already there
const FAILED := "failed"			#/ Couldn't be done: see "reason"
const MANUAL := "manual"			#/ A manual step: to be done by hand


#* Why a release's steps can't be used, or "":
static func check(steps: Variant) -> String:
	if steps == null:
		return ""
	if not steps is Array:
		return "The release's update steps can't be read."
	for step in steps:
		if not step is Dictionary:
			return "The release's update steps can't be read."
		var action := String(step.get("action", ""))
		if not ACTIONS.has(action):
			return "This update needs a newer Candy Wizard (it uses the '%s' update step). Update Candy Wizard first." % action
		if String(step.get("version", "")) == "":
			return "An update step (%s) doesn't say which version brought it." % action
		for field in ACTIONS[action]:
			if not step.has(field):
				return "An update step (%s, %s) lacks its '%s'." % [action, step.get("version", ""), field]
		#? Paths to check ("from" / "to" are only names in renames).
		var paths := ["file"]
		if action == "move":
			paths = ["from", "to"]
		for field in paths:
			if step.has(field) and not _is_package_path(str(step[field])):
				return "An update step (%s, %s) names a path outside the Candy_DE folder (%s). It was refused." % [action, step.get("version", ""), step[field]]
	return ""


#* The steps for an update between two versions, oldest first (manifest order within a version):
static func between(steps: Variant, from_version: String, to_version: String) -> Array:
	var chosen := []
	if not steps is Array:
		return chosen
	for step in steps:
		var version := String(step.get("version", ""))
		if Utils.compare_versions(version, from_version) > 0 and Utils.compare_versions(version, to_version) <= 0:
			chosen.append(step)
	#? Stable insertion sort (the lists are short).
	var sorted := []
	for step in chosen:
		var index := sorted.size()
		while index > 0 and Utils.compare_versions(String(sorted[index - 1]["version"]), String(step["version"])) > 0:
			index -= 1
		sorted.insert(index, step)
	return sorted


static func _is_package_path(path: String) -> bool:
	return path.begins_with(Utils.PACKAGE_NAME + "/") and not ".." in path.split("/") and not "\\" in path


#==============================================================================
#  DESCRIPTIONS
#==============================================================================

#* What a step does, in plain words (BBCode, names in code style):
static func describe(step: Dictionary, code: Callable) -> String:
	if String(step.get("description", "")) != "":
		return _escaped(String(step["description"]))
	match String(step.get("action", "")):
		"move":
			return "Move %s to %s" % [code.call(step["from"]), code.call(step["to"])]
		"add_variable":
			return "Add the %s setting to %s" % [code.call(step["variable"]), code.call(String(step["file"]).get_file())]
		"set_variable":
			return "Set %s to %s in %s" % [code.call(step["variable"]), code.call(value_text(step["value"])), code.call(String(step["file"]).get_file())]
		"rename_variable":
			return "Rename the %s setting to %s in %s" % [code.call(step["from"]), code.call(step["to"]), code.call(String(step["file"]).get_file())]
		"replace_text":
			return "Change a part of %s" % code.call(String(step["file"]).get_file())
		"rename_input_action":
			return "Rename the input action %s to %s" % [code.call(step["from"]), code.call(step["to"])]
		"manual":
			return _escaped(String(step["title"]))
	return _escaped(String(step.get("action", "")))


#* What to do by hand when a step failed - its "manual" text, or Candy Wizard's own:
static func manual_text(step: Dictionary, reason: String) -> String:
	if String(step.get("manual", "")) != "":
		return String(step["manual"])
	match String(step.get("action", "")):
		"add_variable":
			return "Add this to %s:\n%s" % [step["file"], step["text"]]
		"set_variable":
			return "In %s, set %s to %s, if that suits your project." % [step["file"], step["variable"], value_text(step["value"])]
		"rename_variable":
			return "In %s, rename the setting %s to %s." % [step["file"], step["from"], step["to"]]
		"replace_text":
			return "In %s, replace:\n%s\nwith:\n%s" % [step["file"], step["find"], step["replace"]]
		"move":
			return "Move %s to %s by hand (%s)." % [step["from"], step["to"], reason]
		"rename_input_action":
			return "In Project Settings → Input Map, rename %s to %s (%s)." % [step["from"], step["to"], reason]
	return reason


#* A value as a script writes it:
#? JSON makes every number a float: a whole one shows as an int.
static func value_text(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT and value == floorf(value) and absf(value) < 1e15:
		return var_to_str(int(value))
	return var_to_str(value)


static func _escaped(text: String) -> String:
	return text.replace("[", "[lb]")


#==============================================================================
#  TEXT STEPS
#==============================================================================

#* Runs a text step on a file's text, returning {"result", "text", "reason"}:
#? result: DONE / ALREADY / FAILED, text: the new text (DONE), reason: why it failed (FAILED).
static func apply_text(step: Dictionary, text: String) -> Dictionary:
	match String(step["action"]):
		"add_variable":
			return _add_variable(step, text)
		"set_variable":
			return _set_variable(step, text)
		"rename_variable":
			return _rename_variable(step, text)
		"replace_text":
			return _replace_text(step, text)
	return {"result": FAILED, "reason": "not a text step"}


static func _add_variable(step: Dictionary, text: String) -> Dictionary:
	if declaration(text, String(step["variable"])) != null:
		return {"result": ALREADY}
	#? The file's own line endings ("\r\n" from git on Windows).
	var line_break := "\n"
	if text.contains("\r\n"):
		line_break = "\r\n"
	var block := String(step["text"]).replace("\r\n", "\n").trim_suffix("\n").replace("\n", line_break)
	var after := String(step.get("after", ""))
	var found: RegExMatch = null
	if after != "":
		found = declaration(text, after)
	if found == null:
		#? At the end of the file, after a blank line.
		var ending := text
		if not ending.ends_with("\n"):
			ending += line_break
		return {"result": DONE, "text": ending + line_break + block + line_break}
	var end := statement_end(text, found.get_start())
	return {"result": DONE, "text": text.substr(0, end) + line_break + block + text.substr(end)}


static func _set_variable(step: Dictionary, text: String) -> Dictionary:
	var variable := String(step["variable"])
	var found := Utils.variable_regex(variable).search(text)
	if found == null:
		if declaration(text, variable) == null:
			return {"result": FAILED, "reason": "the file has no %s setting" % variable}
		return {"result": FAILED, "reason": "%s's value isn't a plain value Candy Wizard can change" % variable}
	var current = str_to_var(found.get_string(1))
	if same_value(current, step["value"]):
		return {"result": ALREADY}
	if step.has("only_if") and not same_value(current, step["only_if"]):
		#? The developer chose another value: theirs stays.
		return {"result": ALREADY, "note": "kept your value, %s" % found.get_string(1)}
	return {"result": DONE, "text": Utils.set_variable(text, variable, step["value"])}


static func _rename_variable(step: Dictionary, text: String) -> Dictionary:
	var from := String(step["from"])
	var to := String(step["to"])
	var found := declaration(text, from)
	if found == null:
		if declaration(text, to) != null:
			return {"result": ALREADY}
		return {"result": FAILED, "reason": "the file has no %s setting" % from}
	if declaration(text, to) != null:
		return {"result": FAILED, "reason": "the file has both %s and %s" % [from, to]}
	var name_start := found.get_start(1)
	return {"result": DONE, "text": text.substr(0, name_start) + to + text.substr(name_start + from.length())}


static func _replace_text(step: Dictionary, text: String) -> Dictionary:
	var find := String(step["find"])
	var replace := String(step["replace"])
	#? Match "\r\n" line endings too (git on Windows).
	var crlf := text.contains("\r\n")
	if crlf:
		find = find.replace("\r\n", "\n").replace("\n", "\r\n")
		replace = replace.replace("\r\n", "\n").replace("\n", "\r\n")
	#? A replacement may hold the text it replaces: leave it alone inside existing replacements,
	#? or running the step again would add to it once more.
	var pieces := PackedStringArray([text])
	if find != "" and replace.contains(find):
		pieces = text.split(replace)
	var found := false
	for index in pieces.size():
		if find != "" and pieces[index].contains(find):
			pieces[index] = pieces[index].replace(find, replace)
			found = true
	if found:
		return {"result": DONE, "text": replace.join(pieces)}
	if replace != "" and text.contains(replace):
		return {"result": ALREADY}
	return {"result": FAILED, "reason": "the text to change isn't in the file, which may have been edited"}


#* A top-level "var <variable>" declaration (annotations allowed); group 1 is the name:
static func declaration(text: String, variable: String) -> RegExMatch:
	if not variable.is_valid_identifier():
		return null
	var regex := RegEx.create_from_string(r"(?m)^(?:@\w+(?:\([^)\n]*\))?\s+)*var\s+(" + variable + r")\b")
	return regex.search(text)


#* Where the statement starting at start ends - its line break, once its brackets are closed:
static func statement_end(text: String, start: int) -> int:
	var depth := 0
	var quote := ""
	var index := start
	while index < text.length():
		var character := text[index]
		if quote != "":
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "#":
			while index < text.length() and text[index] != "\n":
				index += 1
			continue
		elif character in ["(", "[", "{"]:
			depth += 1
		elif character in [")", "]", "}"]:
			depth -= 1
		elif character == "\n" and depth <= 0:
			#? Before a "\r\n"'s "\r": the new lines go before the line break.
			if index > 0 and text[index - 1] == "\r":
				return index - 1
			return index
		index += 1
	return text.length()


#* Whether a script's value equals the manifest's (JSON makes every number a float):
static func same_value(current: Variant, expected: Variant) -> bool:
	var current_number := typeof(current) == TYPE_INT or typeof(current) == TYPE_FLOAT
	var expected_number := typeof(expected) == TYPE_INT or typeof(expected) == TYPE_FLOAT
	if current_number and expected_number:
		return is_equal_approx(float(current), float(expected))
	if typeof(current) != typeof(expected):
		return false
	return current == expected
