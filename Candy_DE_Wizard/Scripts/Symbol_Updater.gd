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

#! A copy of Candy DC's CandySymbolUpdater (Core/symbol_updater.gd): change both together.
#? Rewrites a 1.2 dialogue from the Candy DE symbols it was written with to others.
#? Symbols are keyed by their Candy_Properties.gd variable names, as in an export's Meta.
#? Each symbol is rewritten only where Candy DE reads it, following its own parsing:
#? - Every value: a leading expression symbol (doubled: escaped), a leading role symbol.
#? - Expressions: the variable dictionary, role and CandyRef symbols, outside quoted text.
#? - Entry names: a role, at the start or after the last "/" (CS targets).
#? - Spoken text: text variables, word substitutions (and their separator), text events and
#?   lexicon escapes, with their doubled symbols (literal ones).
#? Quoted text in expressions and Comment lines are never changed.

const DialogueConverter = preload("Dialogue_Converter.gd")

const LEVEL_CHECK := DialogueConverter.LEVEL_CHECK
const LEVEL_NOTE := DialogueConverter.LEVEL_NOTE

#^ Where a file keeps its symbols (an export's under "Meta"):
const SYMBOLS_KEY := "Symbols"

#^ [label, Candy_Properties.gd variable], in Candy DC's Settings > Project > Symbols order:
const SYMBOLS := [
	["Expression", "candy_ref_symbol"],
	["Variable dictionary", "vardict_symbol"],
	["Role", "role_symbol"],
	["Text variable start", "text_var_start_symbol"],
	["Text variable end", "text_var_end_symbol"],
	["Substitution start", "substitution_start_symbol"],
	["Substitution end", "substitution_end_symbol"],
	["Separator", "separator_symbol"],
	["Text event start", "text_event_start_symbol"],
	["Text event end", "text_event_end_symbol"],
	["Lexicon escape start", "lexicon_escape_start_symbol"],
	["Lexicon escape end", "lexicon_escape_end_symbol"],
]

const EXPRESSION := "candy_ref_symbol"
const VARDICT := "vardict_symbol"
const ROLE := "role_symbol"
const SEPARATOR := "separator_symbol"
#^ CandyRef_Shortcuts.gd's tables, kept under their names beside the other symbols:
const SHORTCUTS := "SHORTCUT_SYMBOLS"
const LOOKUPS := "LOOKUP_SYMBOLS"
const KIND_SHORTCUT := "shortcut"
const KIND_LOOKUP := "lookup"
#^ CandyRef's node symbol, fixed:
const NODE_SYMBOL := "$"
#^ Symbol pairs of spoken text, in the order Candy DE reads them - [start, end]:
const TEXT_VAR := ["text_var_start_symbol", "text_var_end_symbol"]
const SUBSTITUTION := ["substitution_start_symbol", "substitution_end_symbol"]
const TEXT_EVENT := ["text_event_start_symbol", "text_event_end_symbol"]
const LEXICON := ["lexicon_escape_start_symbol", "lexicon_escape_end_symbol"]
const PAIRS := [TEXT_VAR, SUBSTITUTION, TEXT_EVENT, LEXICON]

const SPOKEN_LINE := "Spoken_Line"
const COMMENT_LINE := "Comment"
const VARIATIONS_KEY := "Variations"
const SPEECH_KEY := "Text"
const TEXT_KEY := DialogueConverter.TEXT_KEY
#^ Candy DC's own data in a line (CandyDialogue.META_KEY):
const META_KEY := "CandyDC"

var notes: Array = []
#^ Values the update changed:
var changed_values := 0

var _old: Dictionary = {}
var _new: Dictionary = {}
#^ Every symbol an expression can hold, { what it reads: symbol } (reference_symbols()):
var _old_refs: Dictionary = {}
var _new_refs: Dictionary = {}
#^ [old symbol, new symbol, what it reads], longest old symbol first:
var _sigils: Array = []
var _where: PackedStringArray = []
#^ "<where>\n<text>" of each note, so a value is noted once per problem:
var _noted: Dictionary = {}


func _init(old_symbols: Dictionary, new_symbols: Dictionary) -> void:
	_old = old_symbols.duplicate()
	_new = new_symbols.duplicate()
	_old_refs = reference_symbols(_old)
	_new_refs = reference_symbols(_new)
	for identity in _old_refs:
		#? One the new symbols lack keeps its old symbol (and is reported where it's used).
		_sigils.append([str(_old_refs[identity]), str(_new_refs.get(identity, _old_refs[identity])), identity])
	_sigils.sort_custom(func(a, b): return str(a[0]).length() > str(b[0]).length())


#==============================================================================
#  SYMBOLS
#==============================================================================

#* Candy_Properties.gd variable of every symbol:
static func variables() -> Array:
	var result: Array = []
	for symbol in SYMBOLS:
		result.append(str(symbol[1]))
	return result


#* A symbol's label ("Role"):
static func label(variable: String) -> String:
	for symbol in SYMBOLS:
		if str(symbol[1]) == variable:
			return str(symbol[0])
	return variable


#==============================================================================
#  CANDYREF SYMBOLS
#==============================================================================
#? CandyRef_Shortcuts.gd's SHORTCUT_SYMBOLS ({symbol: target}) and LOOKUP_SYMBOLS
#? ({symbol: {"keys", "entries"}}), kept under those names beside the other symbols.
#? A symbol is known by what it reads (its target), so a changed one is found again.

#* The two tables as a list ([{ "kind", "symbol", "target" | "keys" + "entries" }]):
static func entries_of(tables: Dictionary) -> Array:
	var result: Array = []
	var shortcuts = tables.get(SHORTCUTS, {})
	if shortcuts is Dictionary:
		for symbol in shortcuts:
			result.append({"kind": KIND_SHORTCUT, "symbol": str(symbol), "target": str(shortcuts[symbol])})
	var lookups = tables.get(LOOKUPS, {})
	if lookups is Dictionary:
		for symbol in lookups:
			var lookup = lookups[symbol]
			if lookup is Dictionary:
				result.append({"kind": KIND_LOOKUP, "symbol": str(symbol),
					"keys": str(lookup.get("keys", "")), "entries": str(lookup.get("entries", ""))})
	return result


#* An entry of the list, for the user ("Shortcut to globals.inventory"):
static func entry_label(entry: Dictionary) -> String:
	if str(entry.get("kind", "")) == KIND_LOOKUP:
		return "Lookup in %s, then %s" % [str(entry.get("keys", "")), str(entry.get("entries", ""))]
	return "Shortcut to %s" % str(entry.get("target", ""))


#* Every symbol an expression can hold, { what it reads: symbol }:
#? The variable dictionary and role symbols, then the CandyRef ones.
static func reference_symbols(symbols: Dictionary) -> Dictionary:
	var result := {}
	for variable in [VARDICT, ROLE]:
		if str(symbols.get(variable, "")) != "":
			result[variable] = str(symbols[variable])
	for entry in entries_of(symbols):
		result[identity_of(entry)] = str(entry["symbol"])
	return result


#* A reference symbol's label, by what it reads:
static func reference_label(identity: String) -> String:
	if identity == VARDICT or identity == ROLE:
		return label(identity)
	if identity.begins_with(KIND_LOOKUP + ":"):
		var parts := identity.substr(KIND_LOOKUP.length() + 1).split("|")
		return entry_label({"kind": KIND_LOOKUP, "keys": parts[0], "entries": parts[parts.size() - 1]})
	return entry_label({"kind": KIND_SHORTCUT, "target": identity.substr(KIND_SHORTCUT.length() + 1)})


#* What an entry of the list reads ("shortcut:globals.inventory"), which a changed symbol keeps:
static func identity_of(entry: Dictionary) -> String:
	if str(entry.get("kind", "")) == KIND_LOOKUP:
		return "%s:%s|%s" % [KIND_LOOKUP, str(entry.get("keys", "")), str(entry.get("entries", ""))]
	return "%s:%s" % [KIND_SHORTCUT, str(entry.get("target", ""))]


#* Read CandyRef_Shortcuts.gd's two tables (from its text):
#? Returns { SHORTCUTS, LOOKUPS, "problem" } ("" if both were read).
static func read_candy_ref_tables(text: String) -> Dictionary:
	var result := {SHORTCUTS: {}, LOOKUPS: {}, "problem": ""}
	var unread: Array = []
	for table in [SHORTCUTS, LOOKUPS]:
		var literal := extract_expression(text, table)
		#% No such table - Candy DE reads it as empty:
		if literal == "":
			continue
		var value = str_to_var(literal)
		#% Single quotes and the like - read as an expression (literals only, nothing runs on an object):
		if not value is Dictionary:
			var expression := Expression.new()
			if expression.parse(literal) == OK:
				value = expression.execute([], null, false)
		if value is Dictionary:
			result[table] = value
		else:
			unread.append(table)
	if not unread.is_empty():
		result["problem"] = "Couldn't read %s." % " or ".join(unread)
	return result


#* The literal a script's variable or constant is set to, or "" (Candy DC's CandyProjectScripts.extract_expression()):
static func extract_expression(text: String, variable_name: String) -> String:
	if not variable_name.is_valid_identifier():
		return ""
	#? var, const, @export, static, typed.
	var pattern := "(?m)^[ \\t]*(?:@export[^\\n]*?[ \\t]+)?(?:static[ \\t]+)?(?:var|const)[ \\t]+" \
		+ variable_name + "\\b[ \\t]*(?::[^=\\n]*?)?=[ \\t]*"
	var regex := RegEx.create_from_string(pattern)
	if regex == null:
		return ""
	var found := regex.search(text)
	if found == null:
		return ""

	#Ł Read until the brackets balance (or the line ends), skipping comments:
	#? Comments are left out, so their quotes and brackets can't unbalance it.
	var segments := PackedStringArray()
	var start := found.get_end()
	var index := start
	var depth := 0
	var in_string := false
	var quote := ""
	while index < text.length():
		var character := text[index]
		if in_string:
			if character == "\\":
				index += 2
				continue
			if character == quote:
				in_string = false
		elif character == "\"" or character == "'":
			in_string = true
			quote = character
		elif character == "[" or character == "{" or character == "(":
			depth += 1
		elif character == "]" or character == "}" or character == ")":
			depth -= 1
			if depth <= 0:
				index += 1
				break
		elif character == "#":
			segments.append(text.substr(start, index - start))
			if depth == 0:
				start = index
				break
			#Ł Skip to the line break:
			index = text.find("\n", index)
			if index == -1:
				index = text.length()
			start = index
			continue
		elif character == "\n" and depth == 0:
			break
		index += 1
	segments.append(text.substr(start, index - start))
	return "".join(segments).strip_edges()


#==============================================================================
#  COMPARING
#==============================================================================

#* Whether two sets of symbols are the same:
static func same_symbols(a: Dictionary, b: Dictionary) -> bool:
	return differences(a, b).is_empty()


#* The symbols two sets don't share - [{"label", "old", "new"}] ("" for a CandyRef symbol one lacks):
static func differences(old_symbols: Dictionary, new_symbols: Dictionary) -> Array:
	var result: Array = []
	for variable in variables():
		var old_symbol := str(old_symbols.get(variable, ""))
		var new_symbol := str(new_symbols.get(variable, ""))
		if old_symbol != new_symbol:
			result.append({"label": label(variable), "old": old_symbol, "new": new_symbol})
	var old_refs := reference_symbols(old_symbols)
	var new_refs := reference_symbols(new_symbols)
	for identity in old_refs:
		if identity == VARDICT or identity == ROLE:
			continue
		if str(new_refs.get(identity, "")) != str(old_refs[identity]):
			result.append({"label": reference_label(identity), "old": str(old_refs[identity]), "new": str(new_refs.get(identity, ""))})
	for identity in new_refs:
		if not old_refs.has(identity):
			result.append({"label": reference_label(identity), "old": "", "new": str(new_refs[identity])})
	return result


#* What makes a set of symbols unusable ("" if nothing):
#? Spoken text's pairs must differ from each other (a pair's start and end may be the same).
#? Expression symbols ($, the CandyRef ones) must differ from each other and from the expression symbol.
static func symbol_problems(symbols: Dictionary) -> String:
	for variable in variables():
		if str(symbols.get(variable, "")) == "":
			return "The %s symbol is empty." % label(variable)
	var owners := {}
	for group in [[EXPRESSION], [VARDICT], [ROLE], [SEPARATOR]] + PAIRS:
		var seen: Array = []
		for variable in group:
			var symbol := str(symbols.get(variable, ""))
			if symbol in seen:
				continue
			seen.append(symbol)
			if owners.has(symbol):
				return "The %s and %s symbols are the same (%s)." % [label(owners[symbol]), label(variable), symbol]
			owners[symbol] = variable

	var taken := {str(symbols.get(EXPRESSION, "")): label(EXPRESSION), NODE_SYMBOL: "node symbol"}
	var references := reference_symbols(symbols)
	for identity in references:
		var symbol := str(references[identity])
		var what := reference_label(identity).to_lower()
		if taken.has(symbol):
			return "The %s and the %s use the same symbol (%s)." % [taken[symbol], what, symbol]
		taken[symbol] = what
	return ""


#* Symbols a file says it was written with ({} if it doesn't say):
#? data: the parsed file. Missing symbols are filled in from fallback.
static func stored_symbols(data: Dictionary, fallback: Dictionary = {}) -> Dictionary:
	var stored = data.get(SYMBOLS_KEY)
	var meta = data.get("Meta")
	if meta is Dictionary and meta.get(SYMBOLS_KEY) is Dictionary:
		stored = meta[SYMBOLS_KEY]
	if not stored is Dictionary:
		return {}
	var result := {}
	for variable in variables():
		var value = stored.get(variable)
		if value is String:
			result[variable] = value
		else:
			result[variable] = str(fallback.get(variable, ""))
	for table in [SHORTCUTS, LOOKUPS]:
		var value = stored.get(table)
		if not value is Dictionary:
			value = fallback.get(table, {})
		if value is Dictionary:
			result[table] = value.duplicate(true)
		else:
			result[table] = {}
	return result


#==============================================================================
#  DIALOGUE
#==============================================================================

#* Update conversations into a copy:
#? conversations: { conversation: { block: { "Text": [ lines ] } } }.
func update_conversations(conversations: Dictionary) -> Dictionary:
	var result := {}
	for conversation in conversations:
		var blocks = conversations[conversation]
		if not blocks is Dictionary:
			result[conversation] = _copy(blocks)
			continue
		var new_blocks := {}
		for block in blocks:
			var block_data = blocks[block]
			if not block_data is Dictionary or not block_data.get(TEXT_KEY) is Array:
				new_blocks[block] = _copy(block_data)
				continue
			var new_block: Dictionary = block_data.duplicate(true)
			var lines: Array = block_data[TEXT_KEY]
			var new_lines: Array = []
			for i in lines.size():
				_where = PackedStringArray(["%s > %s > line %d" % [conversation, block, i]])
				new_lines.append(_line(lines[i]))
			new_block[TEXT_KEY] = new_lines
			new_blocks[block] = new_block
		result[conversation] = new_blocks
	_where = PackedStringArray()
	return result


func add_note(text: String, level: String = LEVEL_CHECK) -> void:
	var where := " > ".join(_where)
	var key := where + "\n" + text
	if _noted.has(key):
		return
	_noted[key] = true
	notes.append({"where": where, "text": text, "level": level})


func _line(line: Variant) -> Variant:
	#% Comments are for writers: Candy DE never reads them:
	if line is Dictionary and line.has(COMMENT_LINE):
		return _copy(line)
	return _walk(line, "")


func _walk(value: Variant, parent_key: String) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			var child = value[key]
			#% Candy DC's own data:
			if str(key) == META_KEY:
				result[key] = _copy(child)
				continue
			_where.append(str(key))
			var new_key: Variant = key
			if key is String:
				new_key = _entry_name(key)
				if new_key != key and value.has(new_key):
					add_note("Renaming this entry for the new role symbol (%s) would give it the name of another entry: it kept its name." % new_key)
					new_key = key
				_counted(key, new_key)
			var new_child: Variant = null
			if parent_key == SPOKEN_LINE and str(key) == VARIATIONS_KEY and child is Array:
				new_child = _variations(child)
			else:
				new_child = _walk(child, str(key))
			_where.remove_at(_where.size() - 1)
			result[new_key] = new_child
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_walk(item, ""))
		return result
	if value is String:
		return _counted(value, _value(value))
	return value


#* A Spoken_Line's variations ([ { "Default": { "Text": ... } }, ... ]):
func _variations(list: Array) -> Array:
	var result: Array = []
	for item in list:
		if not item is Dictionary or item.size() != 1 or not item.values()[0] is Dictionary:
			result.append(_walk(item, ""))
			continue
		var variation_name: Variant = item.keys()[0]
		var content: Dictionary = item[variation_name]
		_where.append(str(variation_name))
		var new_content := {}
		for key in content:
			var child = content[key]
			if str(key) == SPEECH_KEY and child is String:
				_where.append(str(key))
				new_content[key] = _counted(child, _speech(child))
				_where.remove_at(_where.size() - 1)
			elif str(key) == META_KEY:
				new_content[key] = _copy(child)
			else:
				_where.append(str(key))
				new_content[key] = _walk(child, str(key))
				_where.remove_at(_where.size() - 1)
		_where.remove_at(_where.size() - 1)
		result.append({variation_name: new_content})
	return result


func _counted(before: String, after: String) -> String:
	if before != after:
		changed_values += 1
	return after


func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


#==============================================================================
#  VALUES
#==============================================================================

func _o(variable: String) -> String:
	return str(_old.get(variable, ""))


func _n(variable: String) -> String:
	return str(_new.get(variable, ""))


func _changed(variable: String) -> bool:
	return _o(variable) != _n(variable)


#* A value - an expression, a role, or text:
func _value(text: String) -> String:
	var expression := _o(EXPRESSION)
	if expression != "" and text.begins_with(expression):
		var body := text.substr(expression.length())
		#% "¢¢…" is the text "¢…":
		if body.begins_with(expression):
			return _escape_expression(body, false)
		return _n(EXPRESSION) + _expression(body)

	var result := text
	var role := _o(ROLE)
	if role != "" and text.begins_with(role):
		result = _n(ROLE) + text.substr(role.length())
	elif _changed(ROLE) and text.begins_with(_n(ROLE)):
		add_note("Starts with the new role symbol (%s), so Candy DE will read it as a role." % _n(ROLE))
	return _escape_expression(result, true)


#* Text starting with the new expression symbol gets it doubled, so it stays text:
func _escape_expression(text: String, note: bool) -> String:
	var expression := _n(EXPRESSION)
	if expression == "" or not text.begins_with(expression):
		return text
	if note:
		add_note("Starts with the new expression symbol (%s): it was doubled, so Candy DE still reads it as text, not an expression." % expression, LEVEL_NOTE)
	return expression + text


#* An expression's body (no expression symbol) - its symbols, outside quoted text:
func _expression(body: String) -> String:
	var result := ""
	var i := 0
	var n := body.length()
	while i < n:
		var c := body[i]
		#¦ 1. Quoted text ("…", '…', &"…", ^"…"), kept as written:
		var quote_at := -1
		if c == "\"" or c == "'":
			quote_at = i
		elif (c == "&" or c == "^") and i + 1 < n and (body[i + 1] == "\"" or body[i + 1] == "'"):
			quote_at = i + 1
		if quote_at != -1:
			var end := _quote_end(body, quote_at)
			var quoted := body.substr(i, end - i)
			_check_quoted(quoted)
			result += quoted
			i = end
			continue

		#¦ 2. A symbol:
		var matched := false
		for sigil in _sigils:
			var old_symbol: String = sigil[0]
			if body.substr(i, old_symbol.length()) == old_symbol:
				if not _new_refs.has(sigil[2]):
					add_note("Uses %s (%s), which the project doesn't have anymore: it was left as it is." % [old_symbol, reference_label(sigil[2]).to_lower()])
				result += str(sigil[1])
				i += old_symbol.length()
				matched = true
				break
		if matched:
			continue

		#¦ 3. Anything else:
		result += c
		i += 1
	return result


#* Index after the quote closing the one at start:
func _quote_end(text: String, start: int) -> int:
	var quote := text[start]
	var i := start + 1
	while i < text.length():
		var c := text[i]
		if c == "\\":
			i += 2
			continue
		if c == quote:
			return i + 1
		i += 1
	return text.length()


func _check_quoted(quoted: String) -> void:
	for variable in variables():
		if _changed(variable) and _o(variable) != "" and quoted.contains(_o(variable)):
			add_note("Quoted text in an expression holds the old %s symbol (%s). Quoted text is never updated: check whether it should be." % [label(variable).to_lower(), _o(variable)])
			return
	for sigil in _sigils:
		if sigil[0] != sigil[1] and quoted.contains(str(sigil[0])):
			add_note("Quoted text in an expression holds the old symbol %s (%s). Quoted text is never updated: check whether it should be." % [sigil[0], reference_label(sigil[2]).to_lower()])
			return


#* An entry name - a role, at the start or after the last "/":
func _entry_name(key: String) -> String:
	var role := _o(ROLE)
	if role == "" or not _changed(ROLE):
		return key
	var slash := key.rfind("/")
	var head := key.substr(0, slash + 1)
	var tail := key.substr(slash + 1)
	if tail.begins_with(role):
		return head + _n(ROLE) + tail.substr(role.length())
	return key


#* A text variable's content, or a part of a word substitution, as Candy DE reads them:
func _inline(part: String) -> String:
	var core := part.strip_edges()
	if core == "":
		return part
	var lead := part.length() - part.strip_edges(true, false).length()
	var trail := part.length() - part.strip_edges(false, true).length()
	return part.substr(0, lead) + _inline_core(core) + part.substr(part.length() - trail)


func _inline_core(core: String) -> String:
	#¦ 1. Expression:
	var expression := _o(EXPRESSION)
	if expression != "" and core.begins_with(expression):
		return _value(core)

	#¦ 2. Role, variable or CandyRef symbol (°npc1, €gold): an expression without the expression symbol:
	for sigil in _sigils:
		if core.begins_with(str(sigil[0])):
			return _expression(core)

	#¦ 3. Text, or an actor with a key path (Alice.Age):
	var result := core
	var split := _path_start(core)
	if split != -1:
		result = core.substr(0, split) + _expression(core.substr(split))
	for identity in _new_refs:
		var symbol := str(_new_refs[identity])
		if symbol != str(_old_refs.get(identity, "")) and result.begins_with(symbol):
			add_note("A text variable or word substitution starts with the new symbol %s (%s), so Candy DE will read it as a reference." % [symbol, reference_label(identity).to_lower()])
	return _escape_expression(result, true)


#* Index where a key path starts ("." or "["), or -1:
func _path_start(text: String) -> int:
	var bracket := text.find("[")
	var dot := text.find(".")
	if bracket == -1:
		return dot
	if dot == -1:
		return bracket
	return mini(bracket, dot)


#==============================================================================
#  SPOKEN TEXT
#==============================================================================

#* A spoken text - evaluated first if it's an expression, then read as written text:
func _speech(text: String) -> String:
	var expression := _o(EXPRESSION)
	if expression != "" and text.begins_with(expression):
		var body := text.substr(expression.length())
		if not body.begins_with(expression):
			return _n(EXPRESSION) + _expression(body)
		#% "¢¢…" is the text "¢…":
		return _escape_expression(_speech_text(body), false)
	return _escape_expression(_speech_text(text), true)


#* Written text, read in Candy DE's order:
#? Units: a String is one character of text, an Array ([text]) a finished piece, which the
#? next steps skip but tokens can hold.
func _speech_text(text: String) -> String:
	var units: Array = []
	for i in text.length():
		units.append(text[i])
	units = _pair_tokens(units, TEXT_VAR, true)
	units = _pair_tokens(units, SUBSTITUTION, false)
	units = _pair_tokens(units, TEXT_EVENT, false)
	units = _lexicon_escapes(units)

	var result := ""
	var run := ""
	for unit in units:
		if unit is String:
			run += unit
			continue
		result += _escape_text(run) + str(unit[0])
		run = ""
	return result + _escape_text(run)


#* Text variables, word substitutions or text events - their tokens and doubled symbols:
#? expression_tokens: a token ends at the first end symbol outside quotes and brackets.
func _pair_tokens(units: Array, pair: Array, expression_tokens: bool) -> Array:
	var start_symbol := _o(pair[0])
	var end_symbol := _o(pair[1])
	if start_symbol == "" or end_symbol == "":
		return units
	var changed := _changed(pair[0]) or _changed(pair[1])
	var result: Array = []
	var i := 0
	while i < units.size():
		#¦ 1. Doubled start symbol, a literal one:
		if _match(units, i, start_symbol + start_symbol):
			_add_literal(result, start_symbol, changed)
			i += start_symbol.length() * 2
			continue

		#¦ 2. Doubled end symbol, a literal one:
		if end_symbol != start_symbol and _match(units, i, end_symbol + end_symbol):
			_add_literal(result, end_symbol, changed)
			i += end_symbol.length() * 2
			continue

		#¦ 3. A token:
		if _match(units, i, start_symbol):
			var inner_start := i + start_symbol.length()
			var end_at := _token_end(units, inner_start, end_symbol, expression_tokens)
			if end_at != -1:
				var inner := units.slice(inner_start, end_at)
				result.append([_n(pair[0]) + _token_content(pair, inner) + _n(pair[1])])
				i = end_at + end_symbol.length()
				continue

		result.append(units[i])
		i += 1
	return result


#* A doubled symbol's literal one - text if its symbols change (doubled again if needed), else as written:
func _add_literal(result: Array, symbol: String, changed: bool) -> void:
	if not changed:
		result.append([symbol + symbol])
		return
	for i in symbol.length():
		result.append(symbol[i])


func _match(units: Array, at: int, symbol: String) -> bool:
	if at + symbol.length() > units.size():
		return false
	for i in symbol.length():
		var unit = units[at + i]
		if not unit is String or unit != symbol[i]:
			return false
	return true


#* Index of the end symbol closing a token, or -1:
func _token_end(units: Array, from: int, end_symbol: String, expression_tokens: bool) -> int:
	var depth := 0
	var quote := ""
	var i := from
	while i < units.size():
		var unit = units[i]
		if not unit is String:
			i += 1
			continue
		if expression_tokens:
			if quote != "":
				if unit == "\\":
					i += 2
					continue
				if unit == quote:
					quote = ""
				i += 1
				continue
			if depth == 0 and _match(units, i, end_symbol):
				return i
			if unit == "\"" or unit == "'":
				quote = unit
			elif unit == "(" or unit == "[" or unit == "{":
				depth += 1
			elif (unit == ")" or unit == "]" or unit == "}") and depth > 0:
				depth -= 1
			i += 1
			continue
		if _match(units, i, end_symbol):
			return i
		i += 1
	return -1


#* A token's content:
func _token_content(pair: Array, inner: Array) -> String:
	if pair == TEXT_VAR:
		return _inline(_joined(inner))
	if pair == SUBSTITUTION:
		return _substitution(inner)
	return _joined(inner)


#* A word substitution's parts (word¦actor¦category), each read like a text variable:
func _substitution(inner: Array) -> String:
	var separator := _o(SEPARATOR)
	var parts: Array = [[]]
	var i := 0
	while i < inner.size():
		if separator != "" and _match(inner, i, separator):
			parts.append([])
			i += separator.length()
			continue
		parts.back().append(inner[i])
		i += 1
	var texts := PackedStringArray()
	for part in parts:
		var text := _joined(part)
		if _is_text(part):
			text = _inline(text)
		if _changed(SEPARATOR) and text.contains(_n(SEPARATOR)):
			add_note("A word substitution holds the new separator symbol (%s), so Candy DE will split it there." % _n(SEPARATOR))
		texts.append(text)
	return _n(SEPARATOR).join(texts)


func _joined(units: Array) -> String:
	var result := ""
	for unit in units:
		if unit is String:
			result += unit
		else:
			result += str(unit[0])
	return result


func _is_text(units: Array) -> bool:
	for unit in units:
		if not unit is String:
			return false
	return true


#* Lexicon escapes - each symbol opens or closes one, doubled ones are literal:
func _lexicon_escapes(units: Array) -> Array:
	var start_symbol := _o(LEXICON[0])
	var end_symbol := _o(LEXICON[1])
	if start_symbol == "" or end_symbol == "":
		return units
	var changed := _changed(LEXICON[0]) or _changed(LEXICON[1])
	var result: Array = []
	var inside := false
	var i := 0
	while i < units.size():
		if _match(units, i, start_symbol + start_symbol):
			_add_literal(result, start_symbol, changed)
			i += start_symbol.length() * 2
			continue
		if end_symbol != start_symbol and _match(units, i, end_symbol + end_symbol):
			_add_literal(result, end_symbol, changed)
			i += end_symbol.length() * 2
			continue
		#? The end first: identical symbols take turns.
		if inside and _match(units, i, end_symbol):
			result.append([_n(LEXICON[1])])
			inside = false
			i += end_symbol.length()
			continue
		if not inside and _match(units, i, start_symbol):
			result.append([_n(LEXICON[0])])
			inside = true
			i += start_symbol.length()
			continue
		result.append(units[i])
		i += 1
	return result


#* Text - doubles the new symbols of the pairs that changed, so they're displayed:
func _escape_text(text: String) -> String:
	if text == "":
		return text
	for pair in PAIRS:
		if not (_changed(pair[0]) or _changed(pair[1])):
			continue
		var start_symbol := _n(pair[0])
		var end_symbol := _n(pair[1])
		if start_symbol != "":
			text = text.replace(start_symbol, start_symbol + start_symbol)
		if end_symbol != "" and end_symbol != start_symbol:
			text = text.replace(end_symbol, end_symbol + end_symbol)
	return text
