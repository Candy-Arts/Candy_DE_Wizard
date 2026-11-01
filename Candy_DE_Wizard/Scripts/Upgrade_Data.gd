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


const ScriptFunctions = preload("Script_Functions.gd")
const CandyDEData = preload("Candy_DE_Data.gd")

const PROPERTIES_PATH := "res://Candy_DE/Scripts/User_Data/Candy_Properties.gd"
const DATA_TABLES_FOLDER := "res://Candy_DE/Scripts/User_Data/Data_Tables"
const LOCALIZATION_TABLES_FOLDER := "res://Candy_DE/Scripts/User_Data/Localization_Tables"

#^ The notes' levels: something to check, or to know:
const CHECK := "check"
const INFO := "info"

#^ Candy_Properties.gd settings kept under the same name:
const COPIED_SETTINGS := ["language", "vardict_symbol", "role_symbol", "separator_symbol", "while_safety_break",
		"default_sprite_extension", "default_animated_sprite_extension"]
#^ Renamed settings, 1.1.3 name -> 1.2 name:
#? In 1.2 both apply to every spritesheet / frame folder (1.1.3's default of 1 is kept).
const RENAMED_SETTINGS := {"cs_sprite_fps": "default_sprite_fps", "animated_image_fps": "default_animated_image_fps"}
#^ Text variables - 1.2's own symbols replace 1.1.3's defaults (dialogues are rewritten to them):
const TEXT_VAR_SETTINGS := {"text_var_symbol_start": "text_var_start_symbol", "text_var_symbol_end": "text_var_end_symbol"}
const TEXT_VAR_DEFAULTS := {"text_var_symbol_start": "{)", "text_var_symbol_end": "}"}
#^ The 1.1.3 setting giving both of 1.2's substitution symbols:
const SUBSTITUTION_SETTING := "substitution_symbol"
const SUBSTITUTION_SETTINGS := ["substitution_start_symbol", "substitution_end_symbol"]
#^ The developer may have added tags to these:
const BBCODE_CONSTANTS := ["BBCODE_TAGS_SIMPLE", "BBCODE_TAGS_EQUALS", "BBCODE_TAGS_SPACE"]
#^ 1.2's new symbols, which the developer's own must not contain:
#? The text event and lexicon escape ones are read from 1.2's Candy_Properties.gd.
const CANDY_REF_SYMBOL := "¢"
const NEW_SYMBOL_SETTINGS := ["text_event_start_symbol", "text_event_end_symbol",
	"lexicon_escape_start_symbol", "lexicon_escape_end_symbol"]

#^ Candy_Database.gd variables copied as written into the table declaring them:
const COPIED_TABLES := ["variables", "flags", "player_refs", "current_player"]
#^ Moved into Candy_Properties.gd:
const PROPERTIES_TABLES := ["general_dialogue_history"]
#^ Candy Dialogue Creator's lists: not Candy DE data in 1.2:
const DROPPED_TABLES := ["creator_flag_list", "creator_disposition_list", "creator_actor_list", "creator_role_list"]

#^ Actors - 1.1.3's colour keys -> 1.2's BBCode wraps:
const ACTOR_COLORS := {
	"BoxTextColor": "BoxTextBBCode",
	"BoxSpeakerColor": "BoxSpeakerBBCode",
	"BubbleTextColor": "BubblesTextBBCode",
	"SubtitleTextColor": "SubtitlesTextBBCode",
	"SubtitleSpeakerColor": "SubtitlesSpeakerBBCode",
	"ChatTextColor": "ChatTextBBCode",
	"ChatSpeakerColor": "ChatSpeakerBBCode",
	"BarkTextColor": "BarksTextBBCode",
}
#^ The wraps SpeakerBBCode's opening tags go into (after the colour):
const SPEAKER_BBCODE_KEYS := ["BoxSpeakerBBCode", "SubtitlesSpeakerBBCode", "ChatSpeakerBBCode"]

#^ 1.1.3's engine enums, by value:
const DIALOGUE_MODES := ["Box", "Subtitles", "Chat", "Bubbles", "VN_Bubbles", "Barks", "Voice"]
const TTS_MODES := ["Off", "Simple", "Advanced"]
#^ A 1.1.3 engine's settings when its scene stores none:
const ENGINE_DEFAULTS := {"dialogue_mode": "Box", "bubbles_exempt_mode": "Box", "text_to_speech": "Off"}
#^ Substitution rules' type hints (Spoken_Line.gd):
const TYPE_HINTS := ["int", "float", "bool", "string", "array", "dict", "dictionary"]

#^ Set before convert_data():
var old_properties := ""				#/ The developer's 1.1.3 Candy_Properties.gd
var old_database := ""					#/ Their Candy_Database.gd, or "" when it's unchanged
var old_localizations := ""				#/ Their Candy_Localizations.gd, or "" when it's unchanged
var known_variables := {}				#/ "properties", "database", "localizations" -> 1.1.3's names
var folder_values := {}					#/ Folder setting -> the value 1.2 gets
var engine := ENGINE_DEFAULTS.duplicate()	#/ The 1.1.3 engine's settings (engine_settings())
var current := {}						#/ res:// path -> text: 1.2's user data scripts, as installed

#^ What convert_data() gives:
var written := {}						#/ res:// path -> text: the scripts changed or added
var notes: Array = []					#/ [{level, text, items}], for the report (_note())

var roles_renamed := 0					#/ Role keys that lost the role symbol
var actors_converted := 0				#/ Actors whose Candy DE keys were converted

var _texts := {}						#/ res:// path -> text, as converted so far
var _owners := {}						#/ Variable name -> the res:// path declaring it in 1.2


#==============================================================================
#  CONVERTING
#==============================================================================

#* Converts the user data into written, with notes:
func convert_data() -> void:
	written.clear()
	notes.clear()
	_texts.clear()
	_owners.clear()
	for path in current:
		_texts[path] = String(current[path]).replace("\r\n", "\n")
		for declaration in ScriptFunctions.declarations(_texts[path]):
			_owners[declaration["name"]] = path
	var role_symbol := "°"
	var old := _declared(old_properties)
	if old.has("role_symbol"):
		var value = str_to_var(old["role_symbol"]["value"])
		if value is String:
			role_symbol = value

	_convert_properties(old)
	if old_database != "":
		_convert_database(_declared(old_database), role_symbol)
	if old_localizations != "":
		_convert_localizations(_declared(old_localizations))

	for path in _texts:
		if not current.has(path) or _texts[path] != String(current[path]).replace("\r\n", "\n"):
			written[path] = _texts[path]


func _convert_properties(old: Dictionary) -> void:
	for setting in COPIED_SETTINGS:
		if old.has(setting):
			_replace(setting, old[setting]["value"])
	for setting in RENAMED_SETTINGS:
		if old.has(setting):
			_replace(RENAMED_SETTINGS[setting], old[setting]["value"])

	var custom_text_vars := false
	for setting in TEXT_VAR_SETTINGS:
		if old.has(setting) and str_to_var(old[setting]["value"]) != TEXT_VAR_DEFAULTS[setting]:
			custom_text_vars = true
	if custom_text_vars:
		for setting in TEXT_VAR_SETTINGS:
			if old.has(setting):
				_replace(TEXT_VAR_SETTINGS[setting], old[setting]["value"])
		_note(INFO, "Your own text variable symbols are kept (text_var_start_symbol, text_var_end_symbol).")
	else:
		_note(INFO, "Text variables are written ¤…¤ in 1.2, instead of 1.1.3's {)…}: the dialogue converter rewrites them.")
	if old.has(SUBSTITUTION_SETTING):
		for setting in SUBSTITUTION_SETTINGS:
			_replace(setting, old[SUBSTITUTION_SETTING]["value"])

	for setting in folder_values:
		_replace(setting, _literal(String(folder_values[setting]), 0))

	for constant in BBCODE_CONSTANTS:
		if not old.has(constant):
			continue
		var theirs := evaluate(old[constant]["value"])
		var ours := evaluate(_value_text(constant))
		if not theirs["ok"] or not ours["ok"] or theirs["value"] != ours["value"]:
			_replace(constant, old[constant]["value"])

	#? 1.2's new symbols must not be inside the developer's own:
	var new_symbols := {"candy_ref_symbol": CANDY_REF_SYMBOL}
	for setting in NEW_SYMBOL_SETTINGS:
		var new_value = str_to_var(_value_text(setting))
		if new_value is String and String(new_value) != "":
			new_symbols[setting] = new_value
	for setting in ["vardict_symbol", "role_symbol", "separator_symbol", SUBSTITUTION_SETTING, "text_var_symbol_start", "text_var_symbol_end"]:
		if not old.has(setting):
			continue
		var value = str_to_var(old[setting]["value"])
		if not value is String:
			continue
		var reported: PackedStringArray = []		#/ The start and end symbols of a pair are often the same
		for new_setting in new_symbols:
			var new_symbol := String(new_symbols[new_setting])
			if new_symbol in reported or not String(value).contains(new_symbol):
				continue
			reported.append(new_symbol)
			_note(CHECK, "Your %s (%s) contains %s, 1.2's new %s: change one of them in Candy_Properties.gd (the Symbols tool checks them)." % [setting, value, new_symbol, new_setting])

	_carry_added(old, "properties", "Candy_Properties.gd", DATA_TABLES_FOLDER)


func _convert_database(old: Dictionary, role_symbol: String) -> void:
	for table in COPIED_TABLES + PROPERTIES_TABLES:
		if old.has(table):
			_replace(table, old[table]["value"])
	#? 1.2 reads text event markers and lexicon escapes in the values text variables display:
	for table in ["variables", "actors"]:
		if old.has(table):
			_note_text_symbols(table, String(old[table]["value"]))
			_note_stored_references(table, String(old[table]["value"]))
	if old.has("roles"):
		_replace("roles", _convert_roles(old["roles"]["value"], role_symbol))
	if old.has("actors"):
		_replace("actors", _convert_actors(old["actors"]["value"]))
	if old.has("lexicon"):
		_replace("lexicon", _convert_lexicon(old["lexicon"]["value"]))
		_note(CHECK, "lexicon: 1.2 finds keywords as whole words in every language, so a keyword next to an accented or non-Latin letter (\"ric\" in \"Éric\") is no longer formatted, as it was in 1.1.3. If your dialogues relied on it, set word rules in Lexicon_Word_Rules.gd.")
	if old.has("substitution_table"):
		var separator := "¦"
		var properties := _declared(old_properties)
		if properties.has("separator_symbol") and str_to_var(properties["separator_symbol"]["value"]) is String:
			separator = str_to_var(properties["separator_symbol"]["value"])
		_replace("substitution_table", _convert_substitution(old["substitution_table"]["value"], separator))
	var dropped: PackedStringArray = []
	for table in DROPPED_TABLES:
		if old.has(table):
			dropped.append(table)
	if not dropped.is_empty():
		_note(INFO, "Candy Dialogue Creator's lists (%s) aren't Candy DE data in 1.2: they stay in the 1.1.3 copy's Candy_Database.gd." % ", ".join(dropped))
	_carry_added(old, "database", "Candy_Database.gd", DATA_TABLES_FOLDER)


func _convert_localizations(old: Dictionary) -> void:
	for table in old:
		if table in known_variables.get("localizations", []) and old[table]["kind"] == "var":
			_replace(table, old[table]["value"])
	_carry_added(old, "localizations", "Candy_Localizations.gd", LOCALIZATION_TABLES_FOLDER)


#* Variables the developer added to a 1.1.3 user data script, each into a table script of its own:
#? Not 1.1.3's own. Constants they added are noted.
func _carry_added(old: Dictionary, script_key: String, script_name: String, folder: String) -> void:
	var known: Array = known_variables.get(script_key, [])
	for variable_name in old:
		if variable_name in known:
			continue
		if old[variable_name]["kind"] != "var":
			_note(CHECK, "Your constant %s in %s isn't carried over: 1.2's table scripts only hold variables." % [variable_name, script_name])
			continue
		var path := folder.path_join(_table_file_name(variable_name))
		var number := 2
		while _texts.has(path):
			path = folder.path_join(_table_file_name(variable_name).get_basename() + "_%d.gd" % number)
			number += 1
		_texts[path] = "extends CandyDataTable\n\n\n#? Carried over from %s (Candy DE 1.1.3) by Candy Wizard's upgrade.\n%s\n" % [script_name, old[variable_name]["declaration"]]
		_note(INFO, "Your variable %s (from %s) is now in %s." % [variable_name, script_name, path.get_file()])


#* A table script's file name for a variable - "quest_log" -> "Quest_Log.gd":
static func _table_file_name(variable_name: String) -> String:
	var parts: PackedStringArray = []
	for part in variable_name.split("_", false):
		parts.append(part.left(1).to_upper() + part.substr(1))
	return "_".join(parts) + ".gd"


#==============================================================================
#  TABLES
#==============================================================================

#* Roles' keys lose the role symbol ("°npc1" -> "npc1"), in the text as written:
func _convert_roles(value_text: String, role_symbol: String) -> String:
	if role_symbol == "":
		return value_text
	var regex := RegEx.create_from_string("([\"'])" + _regex_escaped(role_symbol) + "([^\"'\\n]*[\"']\\s*:)")
	var found := regex.search_all(value_text)
	if not found.is_empty():
		var renamed: Array = []
		for match_result in found:
			var role := match_result.get_string(2)
			role = role.substr(0, role.rfind(match_result.get_string(1))).replace("`", "'")
			renamed.append(note_item("`%s%s` -> `%s`" % [role_symbol, role, role]))
		_note(INFO, "roles: %d key(s) lost the role symbol (\"%snpc1\" is now \"npc1\"). Dialogues still write roles with it; your code and saves use the new keys (see To do)." % [found.size(), role_symbol], renamed)
		roles_renamed = found.size()
	return regex.sub(value_text, "$1$2", true)


#* The actors table, with 1.1.3's keys turned into 1.2's:
func _convert_actors(value_text: String) -> String:
	var parsed := evaluate(value_text)
	if not parsed["ok"] or not parsed["value"] is Dictionary:
		_note(CHECK, "actors couldn't be read, so it's copied as written: convert PortraitOverride, BubblesOverride, TTS, LLM, SpeakerBBCode and the colour keys by hand (see Actors.gd).")
		return value_text
	var actors: Dictionary = parsed["value"]
	var result := {}
	var listed: Array = []
	for actor_key in actors:
		if actors[actor_key] is Dictionary:
			result[actor_key] = _convert_actor(String(actor_key), actors[actor_key])
			var changes := _actor_changes(actors[actor_key], result[actor_key])
			if not changes.is_empty():
				listed.append(note_item("`%s`:" % String(actor_key).replace("`", "'"), changes))
		else:
			result[actor_key] = actors[actor_key]
	actors_converted = listed.size()
	var summary := "actors: Candy DE's keys are renamed for 1.2 in every actor: PortraitOverride -> BoxPortraitMode, BubblesOverride -> DialogueMode, the colour keys (BoxTextColor...) -> BBCode wraps (BoxTextBBCode...), SpeakerBBCode removed (its opening tags go into the speaker wraps); TTS and LLM take a mode name and true / false instead of 1 / -1 (0 is null, not set)."
	if listed.is_empty():
		_note(INFO, summary)
	else:
		_note(INFO, summary + " The values that set something, in %d actor(s):" % listed.size(), listed)
	return _literal(result, 0)


static func _differs(a: Variant, b: Variant) -> bool:
	return typeof(a) != typeof(b) or a != b


#* What _convert_actor() changed in an actor, as note items:
func _actor_changes(old: Dictionary, converted: Dictionary) -> Array:
	var changes: Array = []
	for old_key in ACTOR_COLORS:
		if old.has(old_key) and old[old_key] != null:
			var new_key: String = ACTOR_COLORS[old_key]
			changes.append(note_item("`%s` %s -> `%s` %s" % [old_key, _shown(old[old_key]), new_key, _shown(converted.get(new_key))]))
	if old.has("SpeakerBBCode"):
		var pair = old["SpeakerBBCode"]
		var opening := ""
		if pair is Array and pair.size() > 0:
			opening = str(pair[0])
		elif pair is String:
			opening = pair
		if opening != "":
			changes.append(note_item("`SpeakerBBCode` %s removed: its opening tags are in `BoxSpeakerBBCode`, `SubtitlesSpeakerBBCode` and `ChatSpeakerBBCode`" % _shown(pair)))
	for pair in [["PortraitOverride", "BoxPortraitMode"], ["BubblesOverride", "DialogueMode"], ["TTS", "TTS"], ["LLM", "LLM"]]:
		if old.has(pair[0]) and converted.get(pair[1]) != null and (pair[0] != pair[1] or _differs(old[pair[0]], converted.get(pair[1]))):
			changes.append(note_item("`%s` %s -> `%s` %s" % [pair[0], _shown(old[pair[0]]), pair[1], _shown(converted.get(pair[1]))]))
	if old.has("Short Name"):
		if str(old.get("ShortName", "")) == "":
			changes.append(note_item("`Short Name` -> `ShortName`"))
		else:
			changes.append(note_item("`Short Name` removed (`ShortName` already set)"))
	return changes


func _convert_actor(actor_key: String, actor: Dictionary) -> Dictionary:
	var speaker_open := ""
	if actor.has("SpeakerBBCode"):
		var pair = actor["SpeakerBBCode"]
		var speaker_close := ""
		if pair is Array:
			if pair.size() > 0:
				speaker_open = str(pair[0])
			if pair.size() > 1:
				speaker_close = str(pair[1])
		elif pair is String:
			speaker_open = pair
		if speaker_close != "" and not _closes(speaker_open, speaker_close):
			_note(CHECK, "actors[\"%s\"]: SpeakerBBCode's closing tags (%s) don't simply close its opening ones (%s). 1.2 keeps the opening tags only, and closes them itself." % [actor_key, speaker_close, speaker_open])
	#? Colour keys take SpeakerBBCode's tags after the colour; other speaker wraps take them as is:
	var colored := {}
	for old_key in ACTOR_COLORS:
		if actor.has(old_key):
			colored[ACTOR_COLORS[old_key]] = true

	var converted := {}
	for old_key in actor:
		var value = actor[old_key]
		if ACTOR_COLORS.has(old_key):
			var new_key: String = ACTOR_COLORS[old_key]
			var bbcode = _color_bbcode(value)
			if new_key in SPEAKER_BBCODE_KEYS and speaker_open != "":
				if bbcode == null:
					bbcode = speaker_open
				else:
					bbcode += speaker_open
			converted[new_key] = bbcode
		elif old_key == "SpeakerBBCode":
			if speaker_open != "":
				for new_key in SPEAKER_BBCODE_KEYS:
					if not colored.has(new_key):
						converted[new_key] = speaker_open
		elif old_key == "PortraitOverride":
			converted["BoxPortraitMode"] = _three_way(value, "All", "Off")
		elif old_key == "BubblesOverride":
			converted["DialogueMode"] = _bubbles_mode(actor_key, value)
		elif old_key == "TTS":
			converted["TTS"] = _tts_mode(actor_key, value)
		elif old_key == "LLM":
			converted["LLM"] = _three_way(value, true, false)
		elif old_key != "Short Name":
			converted[old_key] = value
	#? 1.1.3's text variables looked for "Short Name": a developer may have added it.
	if actor.has("Short Name") and str(converted.get("ShortName", "")) == "":
		converted["ShortName"] = actor["Short Name"]
	return converted


#* 1 / -1 / 0 -> on / off / null (not set), a value already in 1.2's form kept:
static func _three_way(value: Variant, on_value: Variant, off_value: Variant) -> Variant:
	if not (value is int or value is float):
		return value
	if int(value) > 0:
		return on_value
	if int(value) < 0:
		return off_value
	return null


func _bubbles_mode(actor_key: String, value: Variant) -> Variant:
	if not (value is int or value is float):
		return value
	if int(value) > 0:
		return "Bubbles"
	if int(value) == 0:
		return null
	#? 1.2 has no "never bubbles": left to the engine, as the Dialogue Converter does with ForceBubbles -1.
	_note(CHECK, "actors[\"%s\"]: BubblesOverride -1 (never bubbles) has no equivalent in 1.2, so DialogueMode is left unset (null): the actor uses its engine's mode. In a bubbles engine, an actor with no speech bubble still gets the bubbles exempt mode; if this one has a bubble and must stay out of bubbles, set its DialogueMode (Box, say)." % actor_key)
	return null


func _tts_mode(actor_key: String, value: Variant) -> Variant:
	if not (value is int or value is float):
		return value
	if int(value) < 0:
		return "Off"
	if int(value) == 0:
		return null
	#? 1 switched TTS on, in the engine's mode: 1.2's TTS is the mode itself.
	var mode: String = engine["text_to_speech"]
	_note(CHECK, "actors[\"%s\"]: TTS 1 (always TTS) becomes \"%s\", the TTS mode of the engine in Candy_UI.tscn: check it suits the engines that run their lines." % [actor_key, mode])
	return mode


#* A 1.1.3 actor colour as a 1.2 BBCode wrap, or null:
static func _color_bbcode(value: Variant) -> Variant:
	if value is Color:
		return "[color=#%s]" % value.to_html(true)
	if value is String and value != "":
		return "[color=%s]" % value
	return null


#* Whether closing tags simply close the opening ones, in reverse ("[b][i]" / "[/i][/b]"):
static func _closes(opening: String, closing: String) -> bool:
	var expected := ""
	for found in RegEx.create_from_string(r'\[([A-Za-z_]+)').search_all(opening):
		expected = "[/%s]" % found.get_string(1) + expected
	return closing.replace(" ", "") == expected


#* The lexicon, with BBCode pairs turned into opening tags and ":" tags into "=" ones:
#? Copied as written when it has neither.
func _convert_lexicon(value_text: String) -> String:
	var parsed := evaluate(value_text)
	if not parsed["ok"] or not parsed["value"] is Dictionary:
		_note(CHECK, "lexicon couldn't be read, so it's copied as written: turn each BBCode pair ([\"[b]\", \"[/b]\"]) into its opening tags (\"[b]\"), and \":\" in variation keys into \"=\", by hand.")
		return value_text
	var changed := false
	var result := {}
	for variation in parsed["value"]:
		var key := String(variation).replace(":", "=")
		if key != variation:
			changed = true
		var entries = parsed["value"][variation]
		if entries is Dictionary:
			var new_entries := {}
			for keyword in entries:
				var entry = entries[keyword]
				if entry is Dictionary and entry.get("BBCode") is Array:
					entry = entry.duplicate()
					var pair: Array = entry["BBCode"]
					var opening := ""
					if pair.size() > 0:
						opening = str(pair[0])
					if pair.size() > 1 and str(pair[1]) != "" and not _closes(opening, str(pair[1])):
						_note(CHECK, "lexicon[\"%s\"][\"%s\"]: BBCode's closing tags (%s) don't simply close its opening ones (%s). 1.2 keeps the opening tags only." % [variation, keyword, pair[1], opening])
					entry["BBCode"] = opening
					changed = true
				new_entries[keyword] = entry
			entries = new_entries
		result[key] = entries
	if not changed:
		return value_text
	_note(INFO, "lexicon is rewritten for 1.2 (BBCode pairs become opening tags, \":\" variation tags become \"=\"): its comments are left in the 1.1.3 copy.")
	return _literal(result, 0)


#* The substitution table, with ":" tags turned into "=" ones:
#? Copied as written when it has none. Notes the rules that work differently in 1.2.
func _convert_substitution(value_text: String, separator: String) -> String:
	var parsed := evaluate(value_text)
	if not parsed["ok"] or not parsed["value"] is Dictionary:
		_note(CHECK, "substitution_table couldn't be read, so it's copied as written: turn \":\" in its variation keys into \"=\" by hand.")
		return value_text
	var changed := false
	var result := {}
	for variation in parsed["value"]:
		var key := String(variation).replace(":", "=")
		if key != variation:
			changed = true
		result[key] = parsed["value"][variation]
		_check_substitution_rules(String(variation), parsed["value"][variation], separator)
	if not changed:
		return value_text
	_note(INFO, "substitution_table is rewritten for 1.2 (\":\" variation tags become \"=\"): its comments are left in the 1.1.3 copy.")
	return _literal(result, 0)


func _check_substitution_rules(variation: String, groups: Variant, separator: String) -> void:
	if not groups is Dictionary:
		return
	for group in groups:
		if not groups[group] is Array:
			continue
		for item in groups[group]:
			if not item is Dictionary:
				continue
			for properties in item:
				if not item[properties] is Dictionary:
					continue
				var property_count := String(properties).split(",").size()
				for rule in item[properties]:
					var values := String(rule).split(",")
					if values.size() > property_count:
						_note(CHECK, "substitution_table[\"%s\"][\"%s\"]: the rule \"%s\" has more values than \"%s\" has properties. 1.1.3 ignored the extra ones; 1.2's rule never matches." % [variation, group, rule, properties])
					for part in values:
						var pieces := part.split(separator)
						if pieces.size() == 3 or (pieces.size() == 2 and pieces[1].strip_edges().to_lower() in TYPE_HINTS):
							_note(CHECK, "substitution_table[\"%s\"][\"%s\"]: the rule \"%s\" has a type hint. In 1.2, the actor's property must also be of that type (an Age stored as \"18\" fails \"¦int\")." % [variation, group, rule])
							break


#==============================================================================
#  TEXT
#==============================================================================

#* A script's top-level declarations by name, {kind, value (text), declaration (text)}:
static func _declared(text: String) -> Dictionary:
	var normalized := text.replace("\r\n", "\n")
	var found := {}
	for declaration in ScriptFunctions.declarations(normalized):
		found[declaration["name"]] = {
			"kind": declaration["kind"],
			"value": normalized.substr(declaration["value_start"], declaration["value_end"] - declaration["value_start"]),
			"declaration": normalized.substr(declaration["start"], declaration["value_end"] - declaration["start"]),
		}
	return found


#* A variable's value text in the 1.2 script declaring it, or "":
#* Report 1.2's text event and lexicon escape symbols in a 1.1 table's values:
#? A value a text variable displays is read like spoken text: a marker runs its event, escape symbols vanish.
func _note_text_symbols(table: String, source_text: String) -> void:
	var found: PackedStringArray = []
	for setting in NEW_SYMBOL_SETTINGS:
		var symbol = str_to_var(_value_text(setting))
		if symbol is String and String(symbol) != "" and not String(symbol) in found and source_text.contains(String(symbol)):
			found.append(String(symbol))
	if found.is_empty():
		return
	_note(CHECK, "%s holds %s, which 1.2 reads in the values a text variable displays: a text event marker runs its event, and the lexicon escape symbols aren't displayed. Double each one in the values that should display it (%s)." % [table, " and ".join(found), found[0] + found[0]])


#^ 1.1.3's reference symbols (Candy_Properties.gd settings), with their defaults:
const OLD_REFERENCE_SYMBOLS := {"singleton_symbol": "£", "node_symbol": "$", "vardict_symbol": "€", "role_symbol": "°"}
#^ 1.1.3's file variable prefixes:
const OLD_FILE_PREFIXES := ["v_res://", "v_user://", "sv_res://", "sv_user://"]
#^ Most values listed in a note:
const MAX_LISTED := 30

#* Values in a table that start like a 1.1.3 reference: a dialogue reading one through a super
#* symbol (€€x) resolved it, and 1.2 only resolves a stored value that starts with ¢.
func _note_stored_references(table: String, source_text: String) -> void:
	var parsed := evaluate(source_text)
	if not parsed["ok"]:
		return
	var prefixes: PackedStringArray = []
	var old := _declared(old_properties)
	for setting in OLD_REFERENCE_SYMBOLS:
		var symbol = OLD_REFERENCE_SYMBOLS[setting]
		if old.has(setting) and str_to_var(old[setting]["value"]) is String:
			symbol = str_to_var(old[setting]["value"])
		if String(symbol) != "":
			prefixes.append(String(symbol))
	prefixes.append_array(OLD_FILE_PREFIXES)
	var found: Array = []
	_find_references(parsed["value"], table, prefixes, found)
	if found.is_empty():
		return
	var items: Array = []
	for index in mini(found.size(), MAX_LISTED):
		items.append(note_item("`%s`: %s" % [String(found[index][0]).replace("`", "'"), _shown(found[index][1])]))
	if found.size() > MAX_LISTED:
		items.append(note_item("...and %d more." % (found.size() - MAX_LISTED)))
	_note(CHECK, "%s holds %d value(s) that look like 1.1.3 references. If a dialogue or your code reads one as a reference (through a super symbol, €€x), convert it as dialogues are: 1.2 only reads a stored reference that starts with ¢ (\"€score\" -> \"¢€score\", \"$Game/Player.hp\" -> \"¢$/root/Game/Player.hp\"). Plain text needs nothing." % [table, found.size()], items)


#* Collects [path, value] for every String in value starting with one of prefixes:
static func _find_references(value: Variant, path: String, prefixes: PackedStringArray, found: Array) -> void:
	if value is Dictionary:
		for key in value:
			_find_references(value[key], "%s[%s]" % [path, var_to_str(key)], prefixes, found)
	elif value is Array:
		for index in value.size():
			_find_references(value[index], "%s[%d]" % [path, index], prefixes, found)
	elif value is String:
		for prefix in prefixes:
			if String(value).begins_with(prefix):
				found.append([path, value])
				return


func _value_text(variable_name: String) -> String:
	if not _owners.has(variable_name):
		return ""
	var declared := _declared(_texts[_owners[variable_name]])
	if not declared.has(variable_name):
		return ""
	return declared[variable_name]["value"]


#* Puts a value (text) into the 1.2 script declaring the variable:
func _replace(variable_name: String, value_text: String) -> void:
	if not _owners.has(variable_name):
		_note(CHECK, "1.2 has no %s to carry your value into: it stays in the 1.1.3 copy." % variable_name)
		return
	var path: String = _owners[variable_name]
	var text: String = _texts[path]
	for declaration in ScriptFunctions.declarations(text):
		if declaration["name"] == variable_name and declaration["value_start"] < declaration["value_end"]:
			_texts[path] = text.substr(0, declaration["value_start"]) + value_text + text.substr(declaration["value_end"])
			return


#* A note for the report. items list what it's about, each {text, items}: `code` in backticks.
func _note(level: String, text: String, items: Array = []) -> void:
	notes.append({"level": level, "text": text, "items": items})


#* A note's list item (_note()):
static func note_item(text: String, items: Array = []) -> Dictionary:
	return {"text": text, "items": items}


#* A value as the report shows it, in backticks:
static func _shown(value: Variant) -> String:
	if value == null:
		return "`null`"
	return "`%s`" % var_to_str(value).replace("`", "'")


#* A value written as text, evaluated - {"ok" = true, "value"} or {"ok" = false}:
static func evaluate(value_text: String) -> Dictionary:
	#Ł Color.RED as Color("RED") (Expression can't read Color's named constants):
	var source := RegEx.create_from_string(r'\bColor\.([A-Za-z_]+)\b').sub(value_text, "Color(\"$1\")", true)
	source = CandyDEData._clean_dialogue_source(source)
	var expression := Expression.new()
	if expression.parse(source) != OK:
		return {"ok": false}
	var value = expression.execute([], null, false)
	if expression.has_execute_failed():
		return {"ok": false}
	return {"ok": true, "value": value}


#* A value as GDScript text, laid out like Candy DE's tables:
#? A tab per level, a trailing comma per entry. Arrays of plain values stay on one line.
static func _literal(value: Variant, indent: int) -> String:
	var inner := "\t".repeat(indent + 1)
	var outer := "\t".repeat(indent)
	if value is Dictionary:
		if value.is_empty():
			return "{}"
		var lines: PackedStringArray = []
		for key in value:
			lines.append("%s%s: %s," % [inner, _literal(key, indent + 1), _literal(value[key], indent + 1)])
		return "{\n%s\n%s}" % ["\n".join(lines), outer]
	if value is Array:
		if value.is_empty():
			return "[]"
		var plain := true
		var items: PackedStringArray = []
		for item in value:
			if item is Dictionary or item is Array:
				plain = false
			items.append(_literal(item, indent + 1))
		if plain:
			return "[%s]" % ", ".join(items)
		var lines: PackedStringArray = []
		for item in items:
			lines.append("%s%s," % [inner, item])
		return "[\n%s\n%s]" % ["\n".join(lines), outer]
	if value is String or value is StringName:
		#? JSON's escapes are GDScript's, and a line break stays escaped.
		return JSON.stringify(String(value))
	return var_to_str(value)


static func _regex_escaped(text: String) -> String:
	var escaped := ""
	for character in text:
		if character in "\\^$.|?*+()[]{}":
			escaped += "\\"
		escaped += character
	return escaped


#==============================================================================
#  ENGINE
#==============================================================================

#* The settings of the 1.1.3 engine in a Candy_UI.tscn (its root node), by name:
#? dialogue_mode, bubbles_exempt_mode and text_to_speech. A setting it doesn't store is 1.1.3's default.
static func engine_settings(scene_text: String) -> Dictionary:
	var settings := ENGINE_DEFAULTS.duplicate()
	var in_root := false
	for line in scene_text.replace("\r\n", "\n").split("\n"):
		if line.begins_with("["):
			if in_root:
				break
			in_root = line.begins_with("[node ") and not line.contains(" parent=")
			continue
		if not in_root or not line.contains(" = "):
			continue
		var key := line.get_slice(" = ", 0).strip_edges()
		var number := line.get_slice(" = ", 1).strip_edges().to_int()
		if key == "dialogue_mode" and number >= 0 and number < DIALOGUE_MODES.size():
			settings["dialogue_mode"] = DIALOGUE_MODES[number]
		elif key == "bubble_exempt_mode" and number >= 0 and number < DIALOGUE_MODES.size():
			settings["bubbles_exempt_mode"] = DIALOGUE_MODES[number]
		elif key == "text_to_speech" and number >= 0 and number < TTS_MODES.size():
			settings["text_to_speech"] = TTS_MODES[number]
	return settings
