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
extends VBoxContainer


const CandyDEData = preload("../Candy_DE_Data.gd")
const Style = preload("../UI_Style.gd")
const Rules = preload("../Symbol_Rules.gd")

#^ The Symbols card's columns of categories, stacked top to bottom - [icon, title, variables] each:
const CATEGORY_COLUMNS := [
	[["Script", "Expressions", ["candy_ref_symbol", "vardict_symbol", "role_symbol"]],
		["String", "Text variables", ["text_var_start_symbol", "text_var_end_symbol"]]],
	[["ReplaceText", "Word substitution", ["substitution_start_symbol", "substitution_end_symbol", "separator_symbol"]],
		["Signals", "Text events", ["text_event_start_symbol", "text_event_end_symbol"]]],
	[["Help", "Lexicon", ["lexicon_escape_start_symbol", "lexicon_escape_end_symbol"]]],
]

#^ Each symbol's description and examples:
#? In examples, {c} {v} {r} {ts} {te} {ss} {se} {sep} {es} {ee} {ls} {le} are the current symbols.
const DESCRIPTIONS := {
	"candy_ref_symbol": ["Marks a value as an expression, written like GDScript. Double it to write text that starts with it.",
		["{c}globals.hp + 1", "{c}{c}50   (shows {c}50)"]],
	"vardict_symbol": ["Reads a value of the variables table (Data_Tables/Variables.gd).",
		["{c}{v}score", "You have {ts}{v}gold{te} gold."]],
	"role_symbol": ["Reads the actor a role is assigned to (Data_Tables/Roles.gd), or one of that actor's values.",
		["{c}{r}npc1.Age", "{ts}{r}npc1{te} waves."]],
	"text_var_start_symbol": ["Starts a text variable: a value put into spoken text, such as an actor's name or a variable. Double it to display it.",
		["Hi, {ts}Alice{te}!", "{ts}{c}globals.hp + 1{te} HP left.", "50{ts}{ts}   (shows 50{ts})"]],
	"text_var_end_symbol": ["Ends a text variable: a value put into spoken text, such as an actor's name or a variable. Double it to display it.",
		["Hi, {ts}Alice{te}!", "{ts}{c}globals.hp + 1{te} HP left.", "50{te}{te}   (shows 50{te})"]],
	"substitution_start_symbol": ["Starts a word substitution token: the word from the substitution table that fits an actor. Double it to display it.",
		["{ss}he{sep}Alice{se} waves.", "{ss}{ss} Item   (shows {ss} Item)"]],
	"substitution_end_symbol": ["Ends a word substitution token: the word from the substitution table that fits an actor. Double it to display it.",
		["{ss}he{sep}Alice{se} waves.", "{se}{se} Item   (shows {se} Item)"]],
	"separator_symbol": ["Splits a word substitution token into its parts (word, actor, property), and the substitution table's rules.",
		["{ss}he{sep}Alice{sep}Gender{se}", ">={sep}18"]],
	"text_event_start_symbol": ["Starts a text event marker: the event of that name runs when the writing reaches it (the line's Text_Events, then Data_Tables/Text_Events.gd). Double it to display it.",
		["Wait{es}boom{ee}... what was that?", "A dagger: {es}{es}   (shows {es})"]],
	"text_event_end_symbol": ["Ends a text event marker: the event of that name runs when the writing reaches it (the line's Text_Events, then Data_Tables/Text_Events.gd). Double it to display it.",
		["Wait{es}boom{ee}... what was that?", "A dagger: {ee}{ee}   (shows {ee})"]],
	"lexicon_escape_start_symbol": ["Starts a lexicon escape: the text up to the end symbol is displayed as written, never formatted by the lexicon, and the symbols aren't displayed. Input scenes escape what the player types with it. Double it to display it.",
		["{ls}Alice{le} is just a name here.", "{ls}{ls}5   (shows {ls}5)"]],
	"lexicon_escape_end_symbol": ["Ends a lexicon escape: the text since the start symbol is displayed as written, never formatted by the lexicon, and the symbols aren't displayed. Input scenes escape what the player types with it. Double it to display it.",
		["{ls}Alice{le} is just a name here.", "5{le}{le}   (shows 5{le})"]],
}

#^ Optional symbol missing from this Candy DE (_missing_optional()):
const MISSING_OPTIONAL_TEXT := "Not in this project's Candy DE: it comes with a later version. Update Candy DE to use it."

var saved := {}				#/ Variable -> its value in Candy_Properties.gd (null: not found)
var edits := {}				#/ Variable -> LineEdit
var status_icons := {}		#/ Variable -> TextureRect
var problems := {}			#/ Variable -> PackedStringArray, from the last check
var focused := "candy_ref_symbol"

var details_title: Label
var details_text: RichTextLabel			#/ What the focused symbol does, and its problems
var restrictions_text: RichTextLabel	#/ What it can't be
var state_icon: TextureRect
var state_label: Label
var defaults_button: Button
var revert_button: Button
var save_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", Style.px(8))

	#? Horizontal scroll only: the bottom panel takes its content's height.
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", Style.px(8))
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)

	#Ł One card for every symbol, in categories:
	var symbols_box := Style.card_box(cards)
	Style.card_title(symbols_box, "KeyboardLabel", "Symbols")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", Style.px(16))
	symbols_box.add_child(columns)
	for column_categories in CATEGORY_COLUMNS:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", Style.px(6))
		columns.add_child(column)
		for category in column_categories:
			if column.get_child_count() > 0:
				column.add_child(_gap())
			column.add_child(_category_title(category[0], category[1]))
			for variable in category[2]:
				column.add_child(_build_row(variable))

	_build_details(cards)
	_load()


#* A category's title in the Symbols card - icon and dimmed name:
func _category_title(icon_name: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(6))
	row.add_child(Style.icon_rect(Style.icon(icon_name), 16))
	var title := Style.label(text, "bold")
	title.add_theme_color_override("font_color", Style.dim())
	row.add_child(title)
	return row


#* Space between two categories of a column:
func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = Style.px(4)
	return gap


#* A symbol's row - name, field, status icon:
func _build_row(variable: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(8))
	var symbol := _symbol(variable)
	var name_label := Style.label(symbol["label"])
	name_label.custom_minimum_size.x = Style.px(88)
	row.add_child(name_label)

	var edit := LineEdit.new()
	edit.custom_minimum_size.x = Style.px(72)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_override("font", Style.font("source"))
	edit.add_theme_font_size_override("font_size", Style.font_size(1.15))
	edit.select_all_on_focus = true
	edit.tooltip_text = symbol["title"]
	edit.text_changed.connect(func(_text: String) -> void: _check())
	edit.focus_entered.connect(func() -> void:
		focused = variable
		_show_details())
	row.add_child(edit)
	edits[variable] = edit

	var status := Style.icon_rect(null, 16)
	row.add_child(status)
	status_icons[variable] = status
	return row


#* The details card, with the save buttons:
func _build_details(cards: HBoxContainer) -> void:
	var box := Style.card_box(cards)
	var panel: Control = box.get_parent()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = Style.px(380)

	var title_row := Style.card_title(box, "Info", "")
	details_title = title_row.get_child(title_row.get_child_count() - 1)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", Style.px(16))
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)
	details_text = Style.rich_text(false)
	details_text.custom_minimum_size = Vector2(Style.px(200), Style.px(150))
	details_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(details_text)
	restrictions_text = Style.rich_text(false)
	restrictions_text.custom_minimum_size = Vector2(Style.px(200), Style.px(150))
	restrictions_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(restrictions_text)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", Style.px(6))
	box.add_child(actions)
	state_icon = Style.icon_rect(null, 16)
	actions.add_child(state_icon)
	state_label = Style.label("")
	state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_label.clip_text = true
	actions.add_child(state_label)
	defaults_button = Style.button("Defaults", "Reload", _use_defaults)
	defaults_button.tooltip_text = "Put Candy DE's own symbols back in the fields. Nothing is saved until you press Save."
	actions.add_child(defaults_button)
	revert_button = Style.button("Revert", "", _revert)
	revert_button.tooltip_text = "Go back to the symbols saved in Candy_Properties.gd."
	actions.add_child(revert_button)
	save_button = Style.button("Save", "Save", _save)
	save_button.tooltip_text = "Write the symbols into Candy_Properties.gd."
	Style.make_primary(save_button)
	actions.add_child(save_button)


#==============================================================================
#  VALUES
#==============================================================================

#* Read the symbols from Candy_Properties.gd:
func _load() -> void:
	for symbol in Rules.SYMBOLS:
		var variable: String = symbol["variable"]
		var value = CandyDEData.property(variable)
		var edit: LineEdit = edits[variable]
		var untouched: bool = not saved.has(variable) or edit.text == str(saved[variable])
		saved[variable] = value
		edit.editable = value is String
		if not value is String:
			edit.text = ""
			edit.placeholder_text = "?"
		elif untouched:	#/ Fields being edited keep their text
			edit.text = value
	_check()


#* Reload (on file changes):
func refresh() -> void:
	if edits.is_empty() or not CandyDEData.is_available():
		return
	_load()


func _values() -> Dictionary:
	var values := {}
	for variable in edits:
		values[variable] = edits[variable].text
	return values


#* Unsaved symbols:
func _changes() -> Dictionary:
	var changes := {}
	for variable in edits:
		if saved[variable] is String and edits[variable].text != saved[variable]:
			changes[variable] = edits[variable].text
	return changes


#* Check every symbol and show the result:
func _check() -> void:
	problems = Rules.check(_values(), CandyDEData.user_sigils())
	for variable in edits:
		if _missing_optional(variable):
			problems[variable] = PackedStringArray()
		elif not saved[variable] is String:
			problems[variable] = PackedStringArray(["Candy_Properties.gd has no \"var %s = ...\" line with a plain value." % variable])

	var problem_count := 0
	for variable in edits:
		var edit: LineEdit = edits[variable]
		var icon: TextureRect = status_icons[variable]
		var own: PackedStringArray = problems[variable]
		problem_count += own.size()
		if _missing_optional(variable):
			icon.texture = Style.icon("NodeInfo")
			icon.tooltip_text = MISSING_OPTIONAL_TEXT
		elif own.is_empty():
			icon.texture = Style.icon("StatusSuccess")
			icon.tooltip_text = "Valid."
		else:
			icon.texture = Style.icon("StatusError")
			icon.tooltip_text = "\n".join(own)
		#% Unsaved symbols in candy blue:
		if saved[variable] is String and edit.text != saved[variable]:
			edit.add_theme_color_override("font_color", Style.BRAND)
		else:
			edit.remove_theme_color_override("font_color")

	var changes := _changes()
	save_button.disabled = problem_count > 0 or changes.is_empty()
	revert_button.disabled = changes.is_empty()
	var at_defaults := true
	for symbol in Rules.SYMBOLS:
		if edits[symbol["variable"]].editable and edits[symbol["variable"]].text != symbol["default"]:
			at_defaults = false
	defaults_button.disabled = at_defaults

	if problem_count > 0:
		_show_state("StatusError", "%d problem%s to fix before saving." % [problem_count, _plural(problem_count)], "error_color")
	elif not changes.is_empty():
		_show_state("Edit", "%d unsaved change%s." % [changes.size(), _plural(changes.size())], "font_color")
	else:
		_show_state("StatusSuccess", "Saved in Candy_Properties.gd.", "font_color")
	_show_details()


func _show_state(icon_name: String, text: String, color_name: String) -> void:
	state_icon.texture = Style.icon(icon_name)
	state_label.text = text
	state_label.add_theme_color_override("font_color", Style.color(color_name))


#==============================================================================
#  DETAILS
#==============================================================================

#* Explain the focused symbol:
func _show_details() -> void:
	var symbol := _symbol(focused)
	var value: String = edits[focused].text
	details_title.text = symbol["title"]
	if value != "":
		details_title.text += "   " + value

	var values := _values()
	var tags := {
		"c": values["candy_ref_symbol"], "v": values["vardict_symbol"], "r": values["role_symbol"],
		"ts": values["text_var_start_symbol"], "te": values["text_var_end_symbol"],
		"ss": values["substitution_start_symbol"], "se": values["substitution_end_symbol"],
		"sep": values["separator_symbol"],
		"es": values["text_event_start_symbol"], "ee": values["text_event_end_symbol"],
		"ls": values["lexicon_escape_start_symbol"], "le": values["lexicon_escape_end_symbol"],
	}

	details_text.clear()
	if _missing_optional(focused):
		Style.rich_item(details_text, "NodeInfo", _dim(Style.escaped(MISSING_OPTIONAL_TEXT)))
	var own: PackedStringArray = problems.get(focused, PackedStringArray())
	for problem in own:
		Style.rich_item(details_text, "StatusError", Style.colored(Style.escaped(problem), "error_color"))

	var description: Array = DESCRIPTIONS[focused]
	details_text.append_text(Style.escaped(description[0]))
	details_text.newline()
	for example in description[1]:
		Style.rich_item(details_text, "Play", Style.code(String(example).format(tags, "{_}")))

	#Ł Warn that existing uses keep the old symbol:
	if saved[focused] is String and value != saved[focused]:
		Style.rich_item(details_text, "StatusWarning", Style.colored("Dialogues and data tables written with %s keep it: update the dialogues with the Symbol Updater tool once saved, the data tables by hand, and Candy Dialogue Creator's symbols." % Style.escaped(saved[focused]), "warning_color"))

	restrictions_text.clear()
	Style.rich_heading(restrictions_text, "Can't be")
	for rule in Rules.restrictions(focused):
		Style.rich_item(restrictions_text, "Close", _dim(Style.escaped(rule)))


#==============================================================================
#  ACTIONS
#==============================================================================

func _use_defaults() -> void:
	for symbol in Rules.SYMBOLS:
		if edits[symbol["variable"]].editable:
			edits[symbol["variable"]].text = symbol["default"]
	_check()


func _revert() -> void:
	for variable in edits:
		if saved[variable] is String:
			edits[variable].text = saved[variable]
	_check()


func _save() -> void:
	var changes := _changes()
	if changes.is_empty():
		return
	var error := CandyDEData.set_properties(changes)
	if error != "":
		_show_state("StatusError", error, "error_color")
		return
	for variable in changes:
		saved[variable] = changes[variable]
	_check()


#==============================================================================
#  HELPERS
#==============================================================================

func _symbol(variable: String) -> Dictionary:
	for symbol in Rules.SYMBOLS:
		if symbol["variable"] == variable:
			return symbol
	return {}


#* Whether an optional symbol (Symbol_Rules.gd) is missing from Candy_Properties.gd:
func _missing_optional(variable: String) -> bool:
	return bool(_symbol(variable).get("optional", false)) and not saved.get(variable) is String


func _plural(count: int) -> String:
	if count == 1:
		return ""
	return "s"


func _dim(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.dim().to_html(false), text]
