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


const TEXT_KEY := "Text"

#^ Variation names (CandyVariations):
const SEPARATOR := "_"
const RANDOM_PREFIX := "#"
const TTS_TAG := "TTS"
const MAX_LENGTH := 64
#^ Characters no file or folder may contain on Windows, macOS or Linux:
const RESERVED_CHARACTERS := "/\\:*?\"<>|"
const WINDOWS_RESERVED := [
	"CON", "PRN", "AUX", "NUL",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
]

var entries: Array = []
var _renames: Array = []				#/ [[variations array, index, fixed name]]
var _names: Array = []					#/ Every variation name, fixed
#^ Lowercased -> spelling (see repair_name()):
var _known_languages: Dictionary = {}
var _known_tags: Dictionary = {}


#* Check conversations ({conversation = {block = {"Text" = [lines]}}}):
#? Not static (no class name): VariationRepair.new().check(conversations).
func check(conversations: Dictionary) -> RefCounted:
	for conversation in conversations:
		var blocks = conversations[conversation]
		if not blocks is Dictionary:
			continue
		for block in blocks:
			var block_data = blocks[block]
			if not block_data is Dictionary or not block_data.get(TEXT_KEY) is Array:
				continue
			var text_lines: Array = block_data[TEXT_KEY]
			for index in text_lines.size():
				_walk(text_lines[index], "%s > %s > line %d" % [conversation, block, index], true)
	return self


#* Names that can't be fixed - the file mustn't be converted:
func has_problems() -> bool:
	for entry in entries:
		if not entry["problems"].is_empty():
			return true
	return false


func has_fixes() -> bool:
	for entry in entries:
		if not entry["fixes"].is_empty():
			return true
	return false


#* Renames the variations. Only once has_problems() is false:
func apply() -> void:
	for rename in _renames:
		var list: Array = rename[0]
		var index: int = rename[1]
		var entry: Dictionary = list[index]
		list[index] = {rename[2]: entry.values()[0]}


#* top - value is the line itself, whose type isn't a step of where:
func _walk(value: Variant, where: String, top: bool) -> void:
	if value is Dictionary:
		for key in value:
			var child = value[key]
			var child_where := where
			if not top:
				child_where = "%s > %s" % [where, key]
			if str(key) == "Spoken_Line" and child is Dictionary and child.get("Variations") is Array:
				_check_variations(child["Variations"], child_where)
			_walk(child, child_where, false)
	elif value is Array:
		for item in value:
			_walk(item, where, false)


#* Variations are named entries, [{"Default" = {...}}, ...]:
func _check_variations(list: Array, where: String) -> void:
	var taken := {}			#/ Fixed name -> the name in the file
	for index in list.size():
		var item = list[index]
		if not item is Dictionary or item.size() != 1:
			continue
		var old_name := str(item.keys()[0])
		var result := repair_name(old_name, _known_languages, _known_tags)
		var fixed: String = result["name"]
		var problems: Array = result["problems"]
		if problems.is_empty():
			if not taken.has(fixed):
				taken[fixed] = old_name
			elif taken[fixed] == old_name:
				problems.append("Another variation of this line has the same name.")
			else:
				problems.append("Once fixed, it would have the same name as another variation of this line, \"%s\": \"%s\"." % [taken[fixed], fixed])

		if not result["fixes"].is_empty() or not problems.is_empty():
			entries.append({
				"where": where,
				"variation": old_name,
				"fixed": fixed,
				"fixes": result["fixes"],
				"problems": problems,
			})
		if problems.is_empty():
			_names.append(fixed)
			if fixed != old_name:
				_renames.append([list, index, fixed])


#==============================================================================
#  NAMES (CandyVariations)
#==============================================================================

#* "" when the name is usable, otherwise why it isn't:
static func validate_language(text: String) -> String:
	return _validate_token(text, false)


#* Custom tags may carry one "=" - a key and a value, both non-empty:
static func validate_custom_tag(text: String) -> String:
	var problem := _validate_token(text, true)
	if problem != "":
		return problem
	var parts := text.split("=", true)
	if parts.size() > 2:
		return "A tag can hold only one \"=\"."
	if parts.size() == 2 and (parts[0] == "" or parts[1] == ""):
		return "Write a tag as key=value, with both parts filled in."
	#? "Default_TTS" must always mean the TTS twin of "Default".
	if text.to_upper() == TTS_TAG:
		return "\"%s\" is reserved: every variation already has a TTS version." % TTS_TAG
	return ""


#* Random tags are "#" followed by a number:
static func validate_random_tag(text: String) -> String:
	if text == "":
		return "Can't be empty."
	var regex := RegEx.create_from_string("^#[0-9]+$")
	if regex == null or regex.search(text) == null:
		return "A random tag is \"#\" followed by a number, like #1 or #12."
	if text.length() > MAX_LENGTH:
		return "Too long."
	return ""


static func _validate_token(text: String, allow_equals: bool) -> String:
	if text == "":
		return "Can't be empty."
	if text.length() > MAX_LENGTH:
		return "Too long."
	if text != text.strip_edges():
		return "Can't start or end with a space."
	if text.contains(SEPARATOR):
		return "Can't contain \"_\": it separates the parts of a variation name."
	if text.contains(RANDOM_PREFIX):
		return "Can't contain \"#\": that marks a random tag."
	if not allow_equals and text.contains("="):
		return "Can't contain \"=\"."

	for index in text.length():
		var character := text[index]
		if character == " " or character == "\t":
			return "Can't contain spaces."
		if character.unicode_at(0) < 32:
			return "Can't contain control characters."
		if RESERVED_CHARACTERS.contains(character):
			return "Can't contain any of  %s" % RESERVED_CHARACTERS

	if text.ends_with("."):
		return "Can't end with a dot."
	if WINDOWS_RESERVED.has(text.to_upper()):
		return "\"%s\" is a reserved file name on Windows." % text
	return ""


#* "S=F" -> "S", "Shout" -> "Shout":
static func tag_key(tag: String) -> String:
	var index := tag.find("=")
	if index < 0:
		return tag
	return tag.substr(0, index)


#* Tag values grouped by key, keys in alphabetical order:
static func group_tags(tags: Array) -> Dictionary:
	var keys: Array = []
	var groups := {}
	for tag in tags:
		var text := str(tag).strip_edges()
		if text == "":
			continue
		var key := tag_key(text)
		if not groups.has(key):
			groups[key] = []
			keys.append(key)
		if not groups[key].has(text):
			groups[key].append(text)

	keys.sort()
	var ordered := {}
	for key in keys:
		var values: Array = groups[key]
		values.sort()
		ordered[key] = values
	return ordered


static func is_random(tag: String) -> bool:
	return tag.begins_with(RANDOM_PREFIX)


static func compose_variation(base: String, random: String, tts: bool) -> String:
	var result := base
	if random != "":
		result += SEPARATOR + random
	if tts:
		result += SEPARATOR + TTS_TAG
	return result


#* Repairs a variation name read from a file, and reports what it can't fix:
#? Fixes what has only one sensible reading (stray spaces, empty parts, ":" in tags, trailing dots, "TTS" capitals, known spellings,
#? repeated parts, part order). known_languages / known_tags map lowercase -> spelling, and get every new spelling.
#? Returns {"name": the fixed name, "fixes": [{"problem", "fix"}], "problems": [text]}.
static func repair_name(variation_name: String, known_languages: Dictionary, known_tags: Dictionary) -> Dictionary:
	var fixes: Array = []
	var problems: Array = []

	var parts: Array = []
	for part in variation_name.split(SEPARATOR):
		var text := _trim_spaces(part)
		if text == "":
			_add_fix(fixes, "An empty part: a doubled \"_\", or one at the start or end.", "Removed.")
			continue
		if text != part:
			_add_fix(fixes, "Spaces at the start or end of \"%s\"." % part, "Removed.")
		parts.append(text)
	if parts.is_empty():
		problems.append("The name is empty.")
		return {"name": variation_name, "fixes": fixes, "problems": problems}

	#? Parts in file order, as fixed, to tell whether the order needs fixing:
	var kept: Array = []
	var language := ""
	var first: String = parts[0]
	if first.to_upper() == TTS_TAG or is_random(first):
		problems.append("The name must start with its language, but \"%s\" is a tag." % first)
	elif first.contains("=") or first.contains(":"):
		problems.append("The name must start with its language, but \"%s\" holds \"=\" or \":\", which only tags can." % first)
	else:
		parts.remove_at(0)
		language = _repair_part(first, false, known_languages, fixes)
		var language_problem := validate_language(language)
		if language_problem != "":
			problems.append("Language \"%s\": %s" % [language, language_problem])
		kept.append(language)

	var custom: Array = []
	var randoms: Array = []
	var tts := false
	for part in parts:
		var text: String = part
		if text.to_upper() == TTS_TAG:
			if text != TTS_TAG:
				_add_fix(fixes, "\"%s\": the TTS tag in other capitals." % text, "Written \"%s\"." % TTS_TAG)
			if tts:
				_add_fix(fixes, "\"%s\" appears more than once." % TTS_TAG, "Kept once.")
				continue
			tts = true
			kept.append(TTS_TAG)
		elif is_random(text):
			var random_problem := validate_random_tag(text)
			if random_problem != "":
				problems.append("Random tag \"%s\": %s" % [text, random_problem])
			if randoms.has(text):
				_add_fix(fixes, "\"%s\" appears more than once." % text, "Kept once.")
				continue
			randoms.append(text)
			kept.append(text)
		else:
			var tag := _repair_part(text, true, known_tags, fixes)
			var tag_problem := validate_custom_tag(tag)
			if tag_problem != "":
				problems.append("Tag \"%s\": %s" % [tag, tag_problem])
			if custom.has(tag):
				_add_fix(fixes, "\"%s\" appears more than once." % tag, "Kept once.")
				continue
			custom.append(tag)
			kept.append(tag)

	if randoms.size() > 1:
		problems.append("More than one random tag: %s. A variation has one at most." % ", ".join(PackedStringArray(randoms)))
	var values := group_tags(custom)
	for key in values:
		var key_values: Array = values[key]
		if key_values.size() > 1:
			problems.append("More than one value of the tag \"%s\": %s. A variation has one value of each tag at most." % [key, ", ".join(PackedStringArray(key_values))])

	#? The same order as Candy DC's combinations() gives the custom tags.
	custom.sort()
	var base_parts: Array = [language]
	base_parts.append_array(custom)
	var random := ""
	if randoms.size() == 1:
		random = randoms[0]
	var fixed := compose_variation(SEPARATOR.join(base_parts), random, tts)
	if language != "" and randoms.size() <= 1 and fixed != SEPARATOR.join(kept):
		_add_fix(fixes, "The parts are out of order.", "Put in order: language, custom tags alphabetically, random tag, %s." % TTS_TAG)
	return {"name": fixed, "fixes": fixes, "problems": problems}


#* Fixes a language (is_tag false) or a custom tag, and matches its capitals to the known spelling:
static func _repair_part(text: String, is_tag: bool, known: Dictionary, fixes: Array) -> String:
	var result := text
	if is_tag and result.contains(":"):
		var replaced := result.replace(":", "=")
		_add_fix(fixes, "\":\" in the tag \"%s\"." % result, "Replaced with \"=\": \"%s\"." % replaced)
		result = replaced
	#? Then any spaces the dots hid.
	var undotted := _trim_spaces(result.rstrip("."))
	if undotted != result and undotted != "":
		_add_fix(fixes, "Dots at the end of \"%s\"." % result, "Removed: \"%s\"." % undotted)
		result = undotted
	if is_tag:
		var tight := RegEx.create_from_string("[ \\t]*=[ \\t]*").sub(result, "=", true)
		if tight != result:
			_add_fix(fixes, "Spaces around \"=\" in \"%s\"." % result, "Removed: \"%s\"." % tight)
			result = tight
	var dashed := RegEx.create_from_string("[ \\t]+").sub(result, "-", true)
	if dashed != result:
		_add_fix(fixes, "Spaces in \"%s\"." % result, "Replaced with \"-\": \"%s\"." % dashed)
		result = dashed

	var lowered := result.to_lower()
	if not known.has(lowered):
		known[lowered] = result
	elif str(known[lowered]) != result:
		_add_fix(fixes, "\"%s\" differs only in capitals from \"%s\", already in use." % [result, known[lowered]], "Written \"%s\"." % known[lowered])
		result = str(known[lowered])
	return result


#* Spaces and tabs only - anything else at the ends is left for the checks:
static func _trim_spaces(text: String) -> String:
	return text.lstrip(" \t").rstrip(" \t")


static func _add_fix(fixes: Array, problem: String, fix: String) -> void:
	for entry in fixes:
		if entry["problem"] == problem:
			return
	fixes.append({"problem": problem, "fix": fix})
