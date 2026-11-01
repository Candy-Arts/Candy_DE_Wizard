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


#+ Reads settings from text: a script's exported variables with their defaults, a scene's
#+ nodes with the values they store. Values stay text, as written.


#* A script's exported variables: name -> default as written ("" when it has none).
static func exports(script_text: String) -> Dictionary:
	var found := {}
	var pending := false
	var open_name := ""		#/ A default still open on the next lines (a dictionary...)
	var with_var := RegEx.create_from_string(r'^(@export\w*(\(.*?\))?\s+)+var\s+(\w+)\s*(:\s*[^=]*?)?\s*(:?=\s*(.*?))?\s*(#.*)?$')
	var bare_var := RegEx.create_from_string(r'^var\s+(\w+)\s*(:\s*[^=]*?)?\s*(:?=\s*(.*?))?\s*(#.*)?$')
	var annotation := RegEx.create_from_string(r'^@export\w*(\(.*\))?$')
	for raw_line in script_text.replace("\r\n", "\n").split("\n"):
		var line := raw_line.strip_edges()
		if open_name != "":
			found[open_name] += "\n" + _without_comment(line)
			if _depth(found[open_name]) <= 0:
				open_name = ""
			continue
		if line.begins_with("@export_group") or line.begins_with("@export_subgroup") or line.begins_with("@export_category"):
			continue
		var matched := with_var.search(line)
		if matched != null:
			found[matched.get_string(3)] = matched.get_string(6).strip_edges()
			if _depth(found[matched.get_string(3)]) > 0:
				open_name = matched.get_string(3)
			pending = false
			continue
		if annotation.search(line) != null:
			pending = true
			continue
		if pending:
			matched = bare_var.search(line)
			if matched != null:
				found[matched.get_string(1)] = matched.get_string(4).strip_edges()
				if _depth(found[matched.get_string(1)]) > 0:
					open_name = matched.get_string(1)
			pending = false
	return found


#* Brackets a value leaves open (strings skipped):
static func _depth(text: String) -> int:
	var depth := 0
	var quote := ""
	for character in text:
		if quote != "":
			if character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character in "{[(":
			depth += 1
		elif character in "}])":
			depth -= 1
	return depth


static func _without_comment(line: String) -> String:
	var quote := ""
	for index in line.length():
		var character := line[index]
		if quote != "":
			if character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "#":
			return line.left(index).strip_edges()
	return line


#* A script's enums: name -> {member: value}.
static func enums(script_text: String) -> Dictionary:
	var found := {}
	var text := RegEx.create_from_string(r'#[^\n]*').sub(script_text.replace("\r\n", "\n"), "", true)
	for declared in RegEx.create_from_string(r'enum\s+(\w+)\s*\{([^}]*)\}').search_all(text):
		var members := {}
		var next := 0
		for member in declared.get_string(2).split(","):
			var parts := member.split("=")
			var member_name := parts[0].strip_edges()
			if member_name == "":
				continue
			if parts.size() > 1 and parts[1].strip_edges().is_valid_int():
				next = parts[1].strip_edges().to_int()
			members[member_name] = next
			next += 1
		found[declared.get_string(1)] = members
	return found


#* A value as written, with an enum member ("MouseModes.None") as its number and a typed
#* collection's type left out, for comparing:
static func normalized_value(value: String, script_enums: Dictionary) -> String:
	var text := value.strip_edges()
	var member := RegEx.create_from_string(r'^(\w+)\.(\w+)$').search(text)
	if member != null and script_enums.has(member.get_string(1)) and script_enums[member.get_string(1)].has(member.get_string(2)):
		return str(script_enums[member.get_string(1)][member.get_string(2)])
	var typed := RegEx.create_from_string(r'^(Dictionary|Array)\[[^(]*\]\((.*)\)$').search(text.replace("\n", " "))
	if typed != null:
		text = typed.get_string(2)
	#? Trailing commas and spacing don't change a collection.
	return RegEx.create_from_string(r',\s*([}\]])').sub(text.replace("\n", " "), "$1", true)


#* Whether a value is a node reference (a scene's own structure, not a setting to compare):
static func is_node_reference(value: String) -> bool:
	var text := value.strip_edges()
	return text.begins_with("NodePath(") or text == "self" or text.begins_with("ExtResource(") or text.begins_with("SubResource(")


#* A scene's resources and nodes:
#* {"ext": {id: {type, path}}, "nodes": [{path, script (ext id or ""), instance (ext id or ""), values: {name: text}}]}.
#* A node's path is from the root ("." for the root itself).
static func parse_scene(scene_text: String) -> Dictionary:
	var ext := {}
	var nodes: Array = []
	var current = null
	var current_name := ""
	var header := RegEx.create_from_string(r'^\[(\w+)(.*)\]$')
	var attribute := RegEx.create_from_string(r'(\w+)=("(?:[^"\\]|\\.)*"|\S+)')
	var assignment := RegEx.create_from_string(r'^([A-Za-z_][\w/:]*) = (.*)$')
	for line in scene_text.replace("\r\n", "\n").split("\n"):
		var section := header.search(line)
		if section != null:
			if current != null and current_name != "":
				current["values"][current_name] = String(current["values"][current_name]).strip_edges()
			current = null
			current_name = ""
			var attributes := {}
			for found in attribute.search_all(section.get_string(2)):
				attributes[found.get_string(1)] = found.get_string(2).trim_prefix("\"").trim_suffix("\"")
			match section.get_string(1):
				"ext_resource":
					ext[attributes.get("id", "")] = {"type": attributes.get("type", ""), "path": attributes.get("path", "")}
				"node":
					var node_path := "."
					if attributes.has("parent"):
						if attributes["parent"] == ".":
							node_path = attributes.get("name", "")
						else:
							node_path = String(attributes["parent"]).path_join(attributes.get("name", ""))
					var instance := ""
					if attributes.has("instance"):
						instance = _ext_id(attributes["instance"])
					current = {"path": node_path, "script": "", "instance": instance, "values": {}}
					nodes.append(current)
			continue
		if current == null:
			continue
		var value := assignment.search(line)
		if value != null:
			if current_name != "":
				current["values"][current_name] = String(current["values"][current_name]).strip_edges()
			current_name = value.get_string(1)
			if current_name == "script":
				current["script"] = _ext_id(value.get_string(2))
				current_name = ""
			else:
				current["values"][current_name] = value.get_string(2)
		elif current_name != "":
			#? A value written over several lines (a dictionary, an array).
			current["values"][current_name] += "\n" + line
	if current != null and current_name != "":
		current["values"][current_name] = String(current["values"][current_name]).strip_edges()
	return {"ext": ext, "nodes": nodes}


#* 'ExtResource("1_abc")' -> "1_abc":
static func _ext_id(text: String) -> String:
	var found := RegEx.create_from_string(r'ExtResource\(\s*"([^"]*)"\s*\)').search(text)
	if found == null:
		return ""
	return found.get_string(1)


#* Whether two values, as written, are the same (numbers compared as numbers):
static func same_value(a: String, b: String) -> bool:
	if a.replace(" ", "").strip_edges() == b.replace(" ", "").strip_edges():
		return true
	#? Only numbers are read: other values (enum names, expressions) are compared as written.
	if a.strip_edges().is_valid_float() and b.strip_edges().is_valid_float():
		return is_equal_approx(a.strip_edges().to_float(), b.strip_edges().to_float())
	return false
