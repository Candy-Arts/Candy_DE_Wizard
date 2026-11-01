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


#+ For the 1.1.3 upgrade's report: the settings of Candy DE's nodes (engines, UI elements, media
#+ players) that work differently in 1.2, scene by scene. A setting is listed when 1.2 renamed or
#+ removed it, or when its value changes: a default that changed (vn_mode, default_z...), or
#+ 1.2's own scene replacing the developer's 1.1.3 one with other values.
#+ 1.1.3's settings come from the upgrade data (each script's "exports"), 1.2's from the release,
#+ and what to say from Data/Upgrade_Settings_Notes.json:
#+ - scripts: 1.1.3 script -> 1.2 script ("" removed), when the path changed;
#+ - scenes: 1.1.3 shipped scene -> 1.2's, when the path changed;
#+ - settings: 1.1.3 script -> setting -> {new (renamed to), removed, values (1.1.3 value -> 1.2's,
#+   to compare), quiet (no comparing), check (always listed when stored), note};
#+ - new_settings: 1.2 script -> setting -> {old (the value that behaves as 1.1.3 did, if any), note},
#+   for settings new in 1.2 that need setting up (listed when 1.2's value differs from old, or always
#+   in the developer's scenes when there's no old);
#+ - behaviour: what works differently with nothing to set.

const Utils = preload("Wizard_Utils.gd")
const SceneSettings = preload("Scene_Settings.gd")

const NOTES_PATH := "Data/Upgrade_Settings_Notes.json"
#^ Longest value shown:
const VALUE_LENGTH := 90
#^ Instanced scenes followed, at most:
const MAX_DEPTH := 6

#^ Set before review():
var install_folder := ""		#/ The 1.1.3 install folder
var old_scripts := {}			#/ The upgrade data's "scripts" (relative path -> {exports...})
var shipped := {}				#/ The upgrade data's "files": 1.1.3's shipped files (relative paths)
var package = null				#/ Package.gd: 1.2.0

var notes := {}
var _parsed := {}				#/ Scene path -> SceneSettings.parse_scene(), files and package alike
var _new_exports := {}			#/ 1.2 script -> its exports
var _new_enums := {}			#/ 1.2 script -> its enums


func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Utils.wizard_folder().path_join(NOTES_PATH)))
	if parsed is Dictionary:
		notes = parsed


#* What works differently with nothing to set:
func behaviour() -> Array:
	return notes.get("behaviour", [])


#* The developer's scenes: [{scene, shown, nodes: [{node, script, items}]}], those with something to say.
#* scenes: [[res:// path, path shown]].
func review_own(scenes: Array) -> Array:
	var found: Array = []
	for entry in scenes:
		var nodes := _review_scene(String(entry[0]), "")
		if not nodes.is_empty():
			found.append({"scene": entry[0], "shown": entry[1], "nodes": nodes})
	return found


#* The 1.1.3 scenes 1.2's own replace (relative to the install folder), compared with 1.2's.
#* The Candy_Default.tscn templates, which developers duplicate rather than use, are best left
#* out unless the developer changed them.
#* [{scene, shown (1.2's), nodes}].
func review_replaced(relative_scenes: PackedStringArray) -> Array:
	var found: Array = []
	var moved: Dictionary = notes.get("scenes", {})
	for relative in relative_scenes:
		var new_relative := String(moved.get(relative, relative))
		if new_relative == "" or not package.files().has(Utils.PACKAGE_NAME + "/" + new_relative):
			continue
		var nodes := _review_scene(install_folder.path_join(relative), _package_path(new_relative))
		if not nodes.is_empty():
			found.append({"scene": relative, "shown": new_relative, "nodes": nodes})
	return found


#* new_scene "" (the developer's scene, kept with 1.2's scripts) or 1.2's scene replacing it.
func _review_scene(scene_path: String, new_scene: String) -> Array:
	var scene := _scene(scene_path)
	var replacement := {}
	if new_scene != "":
		replacement = _scene(new_scene)
	var reviewed: Array = []
	for node in scene.get("nodes", []):
		var old_side := _node_side(scene, node, 0, false)
		var old_script := String(old_side["script"])
		if old_script == "" or not old_scripts.has(old_script):
			continue
		var new_side := _node_side(scene, node, 0, true)
		var new_values := {}
		if new_scene != "":
			var counterpart = _find_node(replacement, String(node["path"]))
			if counterpart == null:
				continue
			new_side = _node_side(replacement, counterpart, 0, true)
			new_values = counterpart["values"]
		var items := _review_node(old_script, node["values"], old_side["base"], new_side, new_values, new_scene != "")
		if not items.is_empty():
			reviewed.append({"node": node["path"], "script": old_script.get_file(), "items": items})
	#? Nodes with the same findings (a row of speech bubbles) are listed together.
	var merged: Array = []
	var by_findings := {}
	for entry in reviewed:
		var key := "%s\n%s" % [entry["script"], var_to_str(entry["items"])]
		if by_findings.has(key):
			by_findings[key]["node"] += ", " + String(entry["node"])
		else:
			by_findings[key] = entry
			merged.append(entry)
	return merged


#* What a node's settings become: items (markup, `code` in backticks).
func _review_node(old_script: String, values: Dictionary, old_base: Dictionary, new_side: Dictionary, new_values: Dictionary, replaced: bool) -> Array:
	var items: Array = []
	var new_script := new_script_of(old_script)
	var setting_notes: Dictionary = notes.get("settings", {}).get(old_script, {})
	var old_defaults: Dictionary = old_scripts[old_script].get("exports", {})
	var new_defaults := _exports(new_script)
	for setting in old_defaults:
		var note: Dictionary = setting_notes.get(setting, {})
		var stored: bool = values.has(setting)
		var old_value := String(values.get(setting, old_base.get(setting, old_defaults[setting])))
		var text := String(note.get("note", ""))
		if note.get("removed", false):
			if stored:
				items.append(_line("`%s = %s`: removed in 1.2." % [setting, _shown(old_value)], text))
			continue
		var new_setting := String(note.get("new", setting))
		if new_script == "" or not new_defaults.has(new_setting):
			if stored:
				items.append(_line("`%s = %s`: 1.2 has no such setting." % [setting, _shown(old_value)], text))
			continue
		if not replaced and stored and new_setting != setting:
			items.append(_line("`%s = %s`: renamed `%s` in 1.2, so this value is dropped: set it again." % [setting, _shown(old_value), new_setting], text))
			continue
		if not replaced and stored and note.get("values", {}).has(old_value.strip_edges()):
			items.append(_line("`%s = %s`: write it `%s` in 1.2, or the value is dropped." % [setting, _shown(old_value), note["values"][old_value.strip_edges()]], text))
			continue
		if note.get("check", false) and stored and not replaced:
			items.append(_line("`%s = %s`: check it." % [setting, _shown(old_value)], text))
			continue
		if note.get("quiet", false) or note.get("check", false) or (stored and not replaced):
			continue
		var compared := String(note.get("values", {}).get(old_value.strip_edges(), old_value))
		var new_value := String(new_values.get(new_setting, new_side["base"].get(new_setting, new_defaults[new_setting])))
		if SceneSettings.is_node_reference(compared) or SceneSettings.is_node_reference(new_value):
			continue
		var old_enums: Dictionary = old_scripts[old_script].get("enums", {})
		if SceneSettings.same_value(SceneSettings.normalized_value(compared, old_enums), SceneSettings.normalized_value(new_value, _enums(new_script))):
			continue
		new_value = _member_name(new_value, compared, _enums(new_script))
		var named := "`%s`" % new_setting
		if new_setting != setting:
			named = "`%s` (1.1.3's `%s`)" % [new_setting, setting]
		if replaced:
			items.append(_line("%s: `%s` in your 1.1.3 scene, `%s` in 1.2's." % [named, _shown(old_value), _shown(new_value)], text))
		else:
			items.append(_line("%s: `%s` in 1.1.3, `%s` in 1.2 (its default changed)." % [named, _shown(old_value), _shown(new_value)], text))
	var new_notes: Dictionary = notes.get("new_settings", {}).get(new_script, {})
	for setting in new_notes:
		var entry: Dictionary = new_notes[setting]
		if not entry.has("old"):
			if not replaced:
				items.append(_line("`%s`:" % setting, String(entry.get("note", ""))))
			continue
		if not new_defaults.has(setting):
			continue
		var new_value := String(new_values.get(setting, new_side["base"].get(setting, new_defaults[setting])))
		if not SceneSettings.same_value(String(entry["old"]), new_value):
			items.append(_line("`%s`: `%s` in 1.2 (new; 1.1.3 worked as `%s`)." % [setting, _shown(new_value), entry["old"]], String(entry.get("note", ""))))
	return items


func new_script_of(old_script: String) -> String:
	return String(notes.get("scripts", {}).get(old_script, old_script))


#* A node's script (relative to the install folder, 1.1.3's) and the values it inherits from the scene
#* it instances: {script, base}. new: as 1.2 has it (1.2's scenes in place of 1.1.3's shipped ones).
func _node_side(scene: Dictionary, node: Dictionary, depth: int, new: bool) -> Dictionary:
	var ext: Dictionary = scene.get("ext", {})
	if String(node["script"]) != "" and ext.has(node["script"]):
		return {"script": _script_relative(String(ext[node["script"]]["path"])), "base": {}}
	if String(node["instance"]) == "" or not ext.has(node["instance"]) or depth >= MAX_DEPTH:
		return {"script": "", "base": {}}
	var instanced := String(ext[node["instance"]]["path"])
	var root = null
	var instanced_scene := {}
	if new:
		var relative := _install_relative(instanced)
		if relative != "" and shipped.has(relative):
			var new_relative := String(notes.get("scenes", {}).get(relative, relative))
			if new_relative == "":
				return {"script": "", "base": {}}
			instanced_scene = _scene(_package_path(new_relative))
	if instanced_scene.is_empty():
		instanced_scene = _scene(instanced)
	root = _find_node(instanced_scene, ".")
	if root == null:
		return {"script": "", "base": {}}
	var inner := _node_side(instanced_scene, root, depth + 1, new)
	var base: Dictionary = inner["base"].duplicate()
	base.merge(root["values"], true)
	return {"script": inner["script"], "base": base}


#* A script path as the upgrade data names it (relative to the install folder), or "":
func _script_relative(path: String) -> String:
	return _install_relative(path)


func _install_relative(path: String) -> String:
	for prefix in [install_folder + "/", "res://First_Install/", Utils.CANDY_DE_FOLDER + "/"]:
		if path.begins_with(prefix):
			return path.trim_prefix(prefix)
	return ""


static func _find_node(scene: Dictionary, node_path: String) -> Variant:
	for node in scene.get("nodes", []):
		if node["path"] == node_path:
			return node
	return null


#* A scene from the project, or 1.2's from the release (_package_path()):
func _scene(path: String) -> Dictionary:
	if _parsed.has(path):
		return _parsed[path]
	var text := ""
	if path.begins_with("package://"):
		text = package.read(path.trim_prefix("package://")).get_string_from_utf8()
	elif FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	var parsed := {}
	if text != "":
		parsed = SceneSettings.parse_scene(text)
	_parsed[path] = parsed
	return parsed


func _package_path(relative: String) -> String:
	return "package://" + Utils.PACKAGE_NAME + "/" + relative


func _exports(new_script: String) -> Dictionary:
	if new_script == "":
		return {}
	if not _new_exports.has(new_script):
		var path := Utils.PACKAGE_NAME + "/" + new_script
		if package.files().has(path):
			_new_exports[new_script] = SceneSettings.exports(package.read(path).get_string_from_utf8())
		else:
			_new_exports[new_script] = {}
	return _new_exports[new_script]


#* A number as the enum member it is, when the 1.1.3 value names one ("MouseModes.None"):
static func _member_name(value: String, named: String, script_enums: Dictionary) -> String:
	var member := RegEx.create_from_string(r'^(\w+)\.\w+$').search(named.strip_edges())
	if member == null or not value.strip_edges().is_valid_int() or not script_enums.has(member.get_string(1)):
		return value
	var members: Dictionary = script_enums[member.get_string(1)]
	for member_name in members:
		if members[member_name] == value.strip_edges().to_int():
			return "%s.%s" % [member.get_string(1), member_name]
	return value


func _enums(new_script: String) -> Dictionary:
	if not _new_enums.has(new_script):
		var path := Utils.PACKAGE_NAME + "/" + new_script
		if package.files().has(path):
			_new_enums[new_script] = SceneSettings.enums(package.read(path).get_string_from_utf8())
		else:
			_new_enums[new_script] = {}
	return _new_enums[new_script]


static func _line(text: String, note: String) -> Dictionary:
	return {"text": text, "note": note}


#* A value on one line, shortened, backticks out (the report's code spans):
static func _shown(value: String) -> String:
	var flat := SceneSettings.normalized_value(value, {}).replace("\t", "").replace("`", "'").strip_edges()
	if flat.length() > VALUE_LENGTH:
		flat = flat.left(VALUE_LENGTH - 3) + "..."
	return flat
