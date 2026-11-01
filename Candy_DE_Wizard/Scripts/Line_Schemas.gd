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

const DATA_PATH := "Data/Line_Schemas.json"
const DATA_FORMAT := 1
#^ The key of a line's editor-only data in Candy DC (CandyDialogue.META_KEY):
const META_KEY := "CandyDC"

var schemas := {}				#/ Line type -> its fields
var problem := ""				#/ Why the schemas couldn't be read, or ""


#* Reads the schemas from Candy Wizard's folder:
func _init() -> void:
	var data_path := Utils.wizard_folder().path_join(DATA_PATH)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if not parsed is Dictionary or int(parsed.get("format", 0)) != DATA_FORMAT or not parsed.get("schemas") is Dictionary:
		problem = "Candy Wizard's line schemas (%s) are missing or damaged: reinstall Candy Wizard." % data_path
		return
	schemas = parsed["schemas"]


#==============================================================================
#  SCHEMAS
#==============================================================================

func field_specs(type: String, _data: Dictionary = {}) -> Array:
	var fields = schemas.get(type, [])
	if fields is Array:
		return fields
	return []


#* A field's default - the schema's "default" (Candy DC's "default_from" isn't used):
func field_default(spec: Dictionary, _line_type: String) -> String:
	return str(spec.get("default", ""))


func is_command_map(spec: Dictionary) -> bool:
	return str(spec.get("widget", "")) == "map" and str(spec.get("entries", "")) == "commands"


#* Whether a list's entries are lines of commands (a text event's Lines):
func is_command_list(spec: Dictionary) -> bool:
	return str(spec.get("widget", "")) == "list" and str(spec.get("entries", "")) == "commands"


func is_value_map(spec: Dictionary) -> bool:
	return str(spec.get("widget", "")) == "map" and str(spec.get("entries", "")) == "values"


#* The spec one entry of a map of values is edited with, named after its key:
func value_spec(map_spec: Dictionary, key: String) -> Dictionary:
	var result := {}
	var stored = map_spec.get("value", {})
	if stored is Dictionary:
		result = stored.duplicate(true)
	result["id"] = key
	return result


#* A new line's map of values - its "start_entries", numbered from 1:
func value_map_defaults(spec: Dictionary) -> Dictionary:
	var result := {}
	var prefix := str(spec.get("entry_prefix", "Entry"))
	var default_value := field_default(value_spec(spec, ""), "")
	for number in int(spec.get("start_entries", 0)):
		result["%s_%d" % [prefix, number + 1]] = default_value
	return result


#* An entry's fields - the map's "fields", or for a map of commands, its command's schema fields:
func map_entry_fields(map_spec: Dictionary, entry_key: String, entry_value: Variant = {}) -> Array:
	if is_command_map(map_spec):
		var data = entry_value
		if not data is Dictionary:
			data = {}
		return field_specs(entry_key, data)
	return _sub_fields(map_spec)


func is_named_list(spec: Dictionary) -> bool:
	return str(spec.get("entry", "")) == "named"


func is_root_map(spec: Dictionary) -> bool:
	if str(spec.get("widget", "")) != "map":
		return false
	return spec.get("root", false) == true


func _sub_fields(spec: Dictionary) -> Array:
	var fields = spec.get("fields", [])
	if fields is Array:
		return fields
	return []


#==============================================================================
#  NORMALIZATION
#==============================================================================

#* Adds every key the schema defines, in groups and list entries too, in schema order:
func normalize_line(line: Dictionary) -> Dictionary:
	var type := ""
	for key in line:
		type = str(key)
		break
	if type == "":
		return line
	if not schemas.has(type):
		#? Candy DC would derive a schema, which adds and reorders nothing.
		return line
	var data = line[type]
	if not data is Dictionary:
		data = {}
	line[type] = normalize_data(data, field_specs(type, data))
	return line


func normalize_data(data: Dictionary, specs: Array) -> Dictionary:
	var result := {}
	var stores := {}		#/ "stored_in" key -> the data's dictionary of that key
	for spec in specs:
		if not (spec is Dictionary and spec.has("id")):
			continue
		var id := str(spec["id"])
		var store := str(spec.get("stored_in", ""))
		if store != "":
			if not stores.has(store):
				var stored = data.get(store, {})
				if not stored is Dictionary:
					stored = {}
				stores[store] = stored
				result[store] = {}
			result[store][id] = _normalize_value(stores[store], spec)
			continue
		match str(spec.get("widget", "line_edit")):
			"group":
				var group = data.get(id, {})
				if not group is Dictionary:
					group = {}
				result[id] = normalize_data(group, _sub_fields(spec))
			"list":
				var array = data.get(id, [])
				var normalized: Array = []
				if array is Array:
					for entry in array:
						if is_command_list(spec):
							#% Each entry is a line of its own command:
							if entry is Dictionary:
								normalized.append(normalize_line(entry))
							else:
								normalized.append(entry)
						else:
							normalized.append(_normalize_entry(entry, spec))
				result[id] = normalized
			"map":
				if is_value_map(spec):
					result[id] = _normalize_value(data, spec)
				elif is_root_map(spec):
					for key in data:
						if str(key) != META_KEY:
							result[key] = _normalize_map_value(data[key], spec, str(key))
				else:
					var map = data.get(id, {})
					var normalized_map := {}
					if map is Dictionary:
						for key in map:
							normalized_map[key] = _normalize_map_value(map[key], spec, str(key))
					result[id] = normalized_map
			_:
				result[id] = _normalize_value(data, spec)

	for key in data:
		if not result.has(key):
			result[key] = data[key]
	#? Unknown keys inside a "stored_in" dictionary are kept too.
	for store in stores:
		for key in stores[store]:
			if not result[store].has(key):
				result[store][key] = stores[store][key]
	return result


#* A plain field's or value map's value, from source (its level's data or "stored_in" dictionary):
func _normalize_value(source: Dictionary, spec: Dictionary) -> Variant:
	var id := str(spec["id"])
	if is_value_map(spec):
		#? Its values are the user's: only a missing map is filled in.
		if not source.has(id):
			return value_map_defaults(spec)
		if source[id] is Dictionary:
			return source[id]
		return {}
	return source.get(id, spec.get("default", ""))


#* A map entry, as a dictionary of its fields:
func _normalize_map_value(value: Variant, spec: Dictionary, key: String) -> Dictionary:
	var entry: Dictionary = {}
	if value is Dictionary:
		entry = value
	return normalize_data(entry, map_entry_fields(spec, key, entry))


func _normalize_entry(entry: Variant, spec: Dictionary) -> Variant:
	var fields := _sub_fields(spec)
	if is_named_list(spec):
		if entry is Dictionary and entry.size() > 0:
			var entry_name := str(entry.keys()[0])
			var value = entry[entry_name]
			if not value is Dictionary:
				value = {}
			return {entry_name: normalize_data(value, fields)}
		return {str(spec.get("entry_prefix", "Entry")) + "_1": normalize_data({}, fields)}
	if entry is Dictionary:
		return normalize_data(entry, fields)
	return normalize_data({}, fields)
