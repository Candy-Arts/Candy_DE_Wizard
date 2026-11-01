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


#^ Top-level function line; group 1 is its name:
const _FUNCTION_PATTERN := r'^(?:static\s+)?func\s+([A-Za-z_]\w*)'
#^ Standalone annotation line, belongs to the function below:
const _ANNOTATION_PATTERN := r'^@\w+(?:\(.*\))?\s*$'


#* Split a script, in the script's order - {"functions" = {name = text}, "rest" = text}:
static func split(text: String) -> Dictionary:
	var function_regex := RegEx.create_from_string(_FUNCTION_PATTERN)
	var annotation_regex := RegEx.create_from_string(_ANNOTATION_PATTERN)
	var functions := {}		#/ Name -> Array of lines (an Array: it's changed in place)
	var rest: PackedStringArray = []
	var current: Variant = null		#/ The function being read, or null outside functions
	var pending: PackedStringArray = []		#/ Annotation lines waiting for the next line
	for raw_line in text.replace("\r\n", "\n").split("\n"):
		var line := _without_comment(raw_line).strip_edges(false, true)
		if line == "":
			continue
		var top_level := not (line.begins_with("\t") or line.begins_with(" "))
		if top_level and annotation_regex.search(line) != null:
			pending.append(line)
			continue
		if top_level:
			var found := function_regex.search(line)
			if found != null:
				current = found.get_string(1)
				functions[current] = Array(pending)
			else:
				current = null
				rest.append_array(pending)
			pending.clear()
		if current == null:
			rest.append(line)
		else:
			functions[current].append(line)
	rest.append_array(pending)
	var texts := {}
	for function_name in functions:
		texts[function_name] = "\n".join(PackedStringArray(functions[function_name]))
	return {"functions": texts, "rest": "\n".join(rest)}


#* Hash a script's parts - {"functions" = {name = sha256}, "rest" = sha256}:
static func hashes(text: String) -> Dictionary:
	var parts := split(text)
	var function_hashes := {}
	for function_name in parts["functions"]:
		function_hashes[function_name] = _hash(parts["functions"][function_name])
	return {"functions": function_hashes, "rest": _hash(parts["rest"])}


#* Compare a script with its original's hashes():
#? {"changed": [names], "added": [names], "removed": [names], "rest_changed": bool}.
static func changes(original: Dictionary, text: String) -> Dictionary:
	var now := hashes(text)
	var original_functions: Dictionary = original.get("functions", {})
	var changed: PackedStringArray = []
	var added: PackedStringArray = []
	var removed: PackedStringArray = []
	for function_name in now["functions"]:
		if not original_functions.has(function_name):
			added.append(function_name)
		elif original_functions[function_name] != now["functions"][function_name]:
			changed.append(function_name)
	for function_name in original_functions:
		if not now["functions"].has(function_name):
			removed.append(function_name)
	return {
		"changed": changed,
		"added": added,
		"removed": removed,
		"rest_changed": String(original.get("rest", "")) != now["rest"],
	}


#* Top-level var/const declarations, positions in text - [{kind, name, start, value_start, value_end}]:
#? text must use "\n" line endings.
static func declarations(text: String) -> Array:
	var regex := RegEx.create_from_string(r'(?m)^(var|const)\s+([A-Za-z_]\w*)(?:\s*:\s*[A-Za-z_][\w\[\], ]*?)?\s*(:=|=)?')
	var found_all := []
	for found in regex.search_all(text):
		var entry := {"kind": found.get_string(1), "name": found.get_string(2), "start": found.get_start()}
		var position := found.get_end()
		#% No value - both at the declaration's end:
		if found.get_string(3) == "":
			entry["value_start"] = position
			entry["value_end"] = position
		else:
			while position < text.length() and (text[position] == " " or text[position] == "\t"):
				position += 1
			entry["value_start"] = position
			entry["value_end"] = _value_end(text, position)
		found_all.append(entry)
	return found_all


#* End of a declaration's value, before any trailing comment:
static func _value_end(text: String, from: int) -> int:
	var depth := 0
	var quote := ""
	var last_code := from		#/ Just after the last character that isn't a comment or a space
	var index := from
	while index < text.length():
		var character := text[index]
		if quote != "":
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
			last_code = index + 1
		elif character == "\"" or character == "'":
			quote = character
			last_code = index + 1
		elif character == "#":
			var line_end := text.find("\n", index)
			if line_end == -1:
				break
			index = line_end
			continue
		elif character == "\n":
			if depth <= 0:
				break
		elif character == "\\" and index + 1 < text.length() and text[index + 1] == "\n":
			#? Line continuation:
			index += 2
			continue
		elif character != " " and character != "\t" and character != "\r":
			if character in ["(", "[", "{"]:
				depth += 1
			elif character in [")", "]", "}"]:
				depth -= 1
			last_code = index + 1
		index += 1
	return last_code


#* Strip a line's comment:
static func _without_comment(line: String) -> String:
	var quote := ""
	var index := 0
	while index < line.length():
		var character := line[index]
		if quote != "":
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "#":
			return line.substr(0, index)
		index += 1
	return line


static func _hash(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var bytes := text.to_utf8_buffer()
	if bytes.size() > 0:
		context.update(bytes)
	return context.finish().hex_encode()
