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


#^ The symbols, in the Symbols tool's order. Symbols with the same "pair" may match:
#? "optional": older Candy DEs may lack it (the text event symbols).
const SYMBOLS := [
	{"variable": "candy_ref_symbol", "label": "Expression", "title": "Expression symbol", "default": "¢", "pair": ""},
	{"variable": "vardict_symbol", "label": "Variables", "title": "Variables symbol", "default": "€", "pair": ""},
	{"variable": "role_symbol", "label": "Roles", "title": "Role symbol", "default": "°", "pair": ""},
	{"variable": "text_var_start_symbol", "label": "Start", "title": "Text variable start", "default": "¤", "pair": "text_var"},
	{"variable": "text_var_end_symbol", "label": "End", "title": "Text variable end", "default": "¤", "pair": "text_var"},
	{"variable": "substitution_start_symbol", "label": "Start", "title": "Substitution start", "default": "•", "pair": "substitution"},
	{"variable": "substitution_end_symbol", "label": "End", "title": "Substitution end", "default": "•", "pair": "substitution"},
	{"variable": "separator_symbol", "label": "Separator", "title": "Separator", "default": "¦", "pair": ""},
	{"variable": "text_event_start_symbol", "label": "Start", "title": "Text event start", "default": "‡", "pair": "text_event", "optional": true},
	{"variable": "text_event_end_symbol", "label": "End", "title": "Text event end", "default": "‡", "pair": "text_event", "optional": true},
	{"variable": "lexicon_escape_start_symbol", "label": "Start", "title": "Lexicon escape start", "default": "¬", "pair": "lexicon_escape", "optional": true},
	{"variable": "lexicon_escape_end_symbol", "label": "End", "title": "Lexicon escape end", "default": "¬", "pair": "lexicon_escape", "optional": true},
]

#^ What the text event and lexicon escape symbols can't contain:
#? Both are read before BBCode, so a tag's brackets would be taken for them.
const BBCODE_BANNED_CHARS := "[]"

#^ The sigils - CandyRef shortcut and lookup symbols:
const SIGILS := ["vardict_symbol", "role_symbol"]

#^ Operators and punctuation of expressions:
#! Must match _OPERATORS in Candy_DE/Scripts/Classes/CandyRef.gd.
const OPERATORS := [
	"**", "==", "!=", "<=", ">=", "&&", "||", "<<", ">>",
	"+", "-", "*", "/", "%",
	"<", ">", "!", "&", "|", "^", "~",
	"(", ")", "[", "]", "{", "}",
	",", ".", ":", "=",
]

#^ CandyRef's node path sigil ($UI/Box/Label):
const NODE_SYMBOL := "$"

#^ Characters that can't start the text variable end symbol:
#? They're used inside text variables (¤Alice.Age¤, ¤¢globals.hp + 1¤), outside brackets and quotes.
const TEXT_VAR_INNER_CHARS := "([{.,:+-*/%<>=!&|^~$"

#^ Characters that can't start the substitution end symbol - token property lists and paths:
const SUBSTITUTION_INNER_CHARS := ",."

#^ Characters the separator can't contain - substitution rules' lists, paths, comparisons, negatives:
const SEPARATOR_BANNED_CHARS := ",.<>=-"


#* Each symbol's problems (variable -> PackedStringArray, empty if valid):
#? user_sigils: the developer's own CandyRef symbols, which the sigils must not take.
static func check(values: Dictionary, user_sigils: PackedStringArray) -> Dictionary:
	var problems := {}
	for symbol in SYMBOLS:
		var variable: String = symbol["variable"]
		problems[variable] = _own_problems(variable, String(values.get(variable, "")), user_sigils)

	#Ł Every symbol differs from the others, and doesn't contain them:
	for symbol in SYMBOLS:
		var value := String(values.get(symbol["variable"], ""))
		if value == "":
			continue
		var reported_pairs: PackedStringArray = []		#/ Report a pair once
		for other in SYMBOLS:
			if other == symbol:
				continue
			if symbol["pair"] != "" and symbol["pair"] == other["pair"]:
				continue
			var other_value := String(values.get(other["variable"], ""))
			if other_value == "" or (other["pair"] != "" and other["pair"] in reported_pairs):
				continue
			if value == other_value:
				problems[symbol["variable"]].append("Same as the %s." % other["title"])
			elif value.contains(other_value):
				problems[symbol["variable"]].append("Contains the %s (%s)." % [other["title"], other_value])
			else:
				continue
			if other["pair"] != "":
				reported_pairs.append(other["pair"])
	return problems


#* What a symbol can't be, for the Symbols tool to show before anything is typed:
static func restrictions(variable: String) -> PackedStringArray:
	var rules: PackedStringArray = [
		"Empty, or with spaces, quotes (\" ') or backslashes",
		"Letters, digits or underscores (names and ordinary text use them)",
		"Another symbol, or anything containing one",
	]
	match variable:
		"candy_ref_symbol":
			rules.append("A first \"-\": number values such as \"-1\" would be read as expressions")
		"vardict_symbol", "role_symbol":
			rules.append("An operator or punctuation mark of expressions, or part of one: + - * / % < > = ! & | ^ ~ ( ) [ ] { } , . :")
			rules.append("\"$\" (node paths: $UI/Box)")
			rules.append("One of your own symbols in CandyRef_Shortcuts.gd")
		"text_var_start_symbol", "text_var_end_symbol":
			rules[2] = "Another symbol, or anything containing one (except each other: both can be the same)"
			if variable == "text_var_end_symbol":
				rules.append("A first character used inside text variables, where it would end them early: %s" % " ".join(TEXT_VAR_INNER_CHARS.split("")))
		"substitution_start_symbol", "substitution_end_symbol":
			rules[2] = "Another symbol, or anything containing one (except each other: both can be the same)"
			if variable == "substitution_end_symbol":
				rules.append("A first \",\" or \".\": tokens use them for lists and property paths (Gender, Age / stats.Age)")
		"separator_symbol":
			rules.append("Any of %s: substitution rules use them for lists, property paths, comparisons (>=) and negative numbers" % " ".join(SEPARATOR_BANNED_CHARS.split("")))
		"text_event_start_symbol", "text_event_end_symbol":
			rules[2] = "Another symbol, or anything containing one (except each other: both can be the same)"
			rules.append("A bracket, %s: markers are read before BBCode, whose tags use them" % " or ".join(BBCODE_BANNED_CHARS.split("")))
		"lexicon_escape_start_symbol", "lexicon_escape_end_symbol":
			rules[2] = "Another symbol, or anything containing one (except each other: both can be the same)"
			rules.append("A bracket, %s: escapes are read before BBCode, whose tags use them" % " or ".join(BBCODE_BANNED_CHARS.split("")))
	return rules


#* The problems a value has on its own, whatever the other symbols are:
static func _own_problems(variable: String, value: String, user_sigils: PackedStringArray) -> PackedStringArray:
	var problems: PackedStringArray = []
	if value == "":
		problems.append("Can't be empty.")
		return problems

	var whitespace := false
	var quotes := false
	var name_chars: PackedStringArray = []
	for index in value.length():
		var character := value[index]
		if character.strip_edges() == "":
			whitespace = true
		elif character in ["\"", "'", "\\"]:
			quotes = true
		elif _is_name_char(character) and not character in name_chars:
			name_chars.append(character)
	if whitespace:
		problems.append("Can't contain spaces.")
	if quotes:
		problems.append("Can't contain quotes or backslashes (\" ' \\).")
	if not name_chars.is_empty():
		problems.append("Can't contain letters, digits or underscores (%s)." % " ".join(name_chars))

	var first := value[0]
	match variable:
		"candy_ref_symbol":
			if first == "-":
				problems.append("Can't start with \"-\": number values such as \"-1\" would be read as expressions.")

		"vardict_symbol", "role_symbol":
			for operator in OPERATORS:
				if operator == value or operator.contains(value):
					problems.append("Expressions use \"%s\" as an operator: it can't be a symbol too." % operator)
					break
			if value.contains(NODE_SYMBOL):
				problems.append("Can't contain \"$\": expressions use it for node paths ($UI/Box).")
			if value in user_sigils:
				problems.append("Already one of your own symbols, in CandyRef_Shortcuts.gd.")

		"text_var_end_symbol":
			if TEXT_VAR_INNER_CHARS.contains(first):
				problems.append("Can't start with \"%s\": it's used inside text variables, which would end there." % first)

		"substitution_end_symbol":
			if SUBSTITUTION_INNER_CHARS.contains(first):
				problems.append("Can't start with \"%s\": substitution tokens use it (Gender, Age / stats.Age)." % first)

		"separator_symbol":
			var found: PackedStringArray = []
			for character in SEPARATOR_BANNED_CHARS.split(""):
				if value.contains(character):
					found.append(character)
			if not found.is_empty():
				var pronoun := "it"
				if found.size() > 1:
					pronoun = "them"
				problems.append("Can't contain %s: substitution rules use %s (lists, property paths, >=, negative numbers)." % [_quoted(found), pronoun])

		"text_event_start_symbol", "text_event_end_symbol", "lexicon_escape_start_symbol", "lexicon_escape_end_symbol":
			var found: PackedStringArray = []
			for character in BBCODE_BANNED_CHARS.split(""):
				if value.contains(character):
					found.append(character)
			if not found.is_empty():
				var read := "markers are"
				if variable.begins_with("lexicon_escape"):
					read = "escapes are"
				problems.append("Can't contain %s: %s read before BBCode, whose tags use %s." % [_quoted(found), read, _pronoun(found)])
	return problems


#* "it" for one character, "them" for several:
static func _pronoun(characters: PackedStringArray) -> String:
	if characters.size() > 1:
		return "them"
	return "it"


#* A letter (of any script), a digit or "_":
static func _is_name_char(character: String) -> bool:
	if character == "_" or "0123456789".contains(character):
		return true
	if character.to_upper() != character.to_lower():	#/ Any script's letters (is_valid_identifier() only knows ASCII)
		return true
	return TextServerManager.get_primary_interface().is_valid_letter(character.unicode_at(0))


#* Characters for a message - "," or ",", "." and "-":
static func _quoted(characters: PackedStringArray) -> String:
	var quoted: PackedStringArray = []
	for character in characters:
		quoted.append("\"%s\"" % character)
	if quoted.size() == 1:
		return quoted[0]
	return ", ".join(quoted.slice(0, quoted.size() - 1)) + " and " + quoted[quoted.size() - 1]
