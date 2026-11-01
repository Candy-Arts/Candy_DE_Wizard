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
const Runner = preload("../Test_Runner.gd")

#^ Testing scene exports the tool sets:
const EXPORTS := Runner.EXPORTS
#^ Max line summary length, in characters:
const SUMMARY_LENGTH := 80

#^ Remembered choices - "scene" and the four EXPORTS (missing = the scene's value):
var choices := {}
var scene_problems: PackedStringArray = []
var scene_info := {}			#/ CandyDEData.scene_exports() of the chosen scene ({} for none)
var dialogue_problems: PackedStringArray = []
var conversations := {}			#/ The chosen dialogue's conversations
var dialogue_problem := ""		#/ Why the chosen dialogue can't be read, or ""
#^ Refresh when shown:
var stale := false

var scene_select: OptionButton
var open_button: Button
var exports_text: RichTextLabel
var dialogue_select: OptionButton
var conversation_select: OptionButton
var block_select: OptionButton
var line_select: OptionButton
var run_panel: PanelContainer		#/ Accent: candy blue when ready, red when not
var run_text: RichTextLabel
var test_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", Style.px(8))
	var saved = EditorInterface.get_editor_settings().get_project_metadata(Runner.METADATA_SECTION, Runner.METADATA_KEY, {})
	if saved is Dictionary:
		choices = saved.duplicate()

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

	_build_scene_card(cards)
	_build_start_card(cards)
	_build_run_card(cards)

	visibility_changed.connect(func() -> void:
		if stale and is_visible_in_tree():
			refresh())
	refresh()


#* The testing scene card:
func _build_scene_card(cards: HBoxContainer) -> void:
	var box := Style.card_box(cards)
	Style.card_title(box, "PackedScene", "Testing scene")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(6))
	box.add_child(row)
	scene_select = _new_select("The scene to run, from testing_scenes_folder.")
	scene_select.custom_minimum_size.x = Style.px(200)
	scene_select.item_selected.connect(func(_index: int) -> void:
		_remember()
		_read_scene()
		_update_run())
	row.add_child(scene_select)
	open_button = Style.button("", "Edit", func() -> void:
		EditorInterface.open_scene_from_path(_selected(scene_select)))
	open_button.tooltip_text = "Open the testing scene in the editor."
	row.add_child(open_button)

	var caption := Style.caption("Its root must export:")
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(caption)
	#? Not wrapped: its width comes from its content.
	exports_text = Style.rich_text(false)
	exports_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	exports_text.fit_content = true
	exports_text.scroll_active = false
	box.add_child(exports_text)


#* The start card - dialogue, conversation, block and line:
func _build_start_card(cards: HBoxContainer) -> void:
	var box := Style.card_box(cards)
	box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.get_parent().size_flags_stretch_ratio = 1.2
	Style.card_title(box, "Play", "Start at")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Style.px(10))
	grid.add_theme_constant_override("v_separation", Style.px(6))
	box.add_child(grid)

	dialogue_select = _add_select_row(grid, "Dialogue", "The dialogue file, from dialogues_folder.")
	#? A new dialogue, conversation or block starts at line 0:
	dialogue_select.item_selected.connect(func(_index: int) -> void:
		_remember()
		choices["line"] = "0"
		_read_dialogue()
		_fill_conversations()
		_remember())
	conversation_select = _add_select_row(grid, "Conversation", "The conversation to start in.")
	conversation_select.item_selected.connect(func(_index: int) -> void:
		_remember()
		choices["line"] = "0"
		_fill_blocks()
		_remember())
	block_select = _add_select_row(grid, "Block", "The block to start in.")
	block_select.item_selected.connect(func(_index: int) -> void:
		_remember()
		choices["line"] = "0"
		_fill_lines()
		_remember())
	line_select = _add_select_row(grid, "Line", "The line to start at.")
	line_select.item_selected.connect(func(_index: int) -> void:
		_remember()
		_update_run())


#* The run card, with the Test button:
func _build_run_card(cards: HBoxContainer) -> void:
	var box := Style.card_box(cards)
	run_panel = box.get_parent()
	run_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_panel.custom_minimum_size.x = Style.px(300)
	Style.card_title(box, "PlayScene", "Run")
	run_text = Style.rich_text(false)
	run_text.custom_minimum_size = Vector2(Style.px(260), Style.px(96))
	box.add_child(run_text)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", Style.px(6))
	box.add_child(actions)
	var note := Style.caption("The scene file isn't changed.")
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(note)
	test_button = Style.button("Test", "PlayScene", _test)
	test_button.tooltip_text = "Run the testing scene from the chosen line. It runs like any scene: stop it from the editor's run bar."
	Style.make_primary(test_button)
	actions.add_child(test_button)


func _add_select_row(grid: GridContainer, text: String, tooltip: String) -> OptionButton:
	var row_label := Style.label(text)
	grid.add_child(row_label)
	var select := _new_select(tooltip)
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(select)
	return select


func _new_select(tooltip: String) -> OptionButton:
	var select := OptionButton.new()
	select.tooltip_text = tooltip
	#? Keep long summaries from widening the panel:
	select.fit_to_longest_item = false
	select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	select.custom_minimum_size.x = Style.px(220)
	return select


#==============================================================================
#  CHOICES
#==============================================================================

#* Read the scenes and dialogues again, keeping the choices (on file changes):
func refresh() -> void:
	if scene_select == null or not CandyDEData.is_available():
		return
	#% Deferred while hidden (it instantiates the testing scene):
	if not is_visible_in_tree():
		stale = true
		return
	stale = false
	_fill_scenes()
	_fill_dialogues()


func _fill_scenes() -> void:
	var gathered := CandyDEData.testing_scenes()
	scene_problems = gathered["problems"]
	var prefix := str(CandyDEData.property("testing_scenes_folder")).trim_suffix("/") + "/"
	var entries := []
	for path in gathered["names"]:
		entries.append([path.trim_prefix(prefix), path])
	_fill(scene_select, entries, String(choices.get("scene", "")))
	_read_scene()


#* Read the chosen scene's exports, and show which it has:
func _read_scene() -> void:
	scene_info = {}
	var scene_path := _selected(scene_select)
	open_button.disabled = scene_path == ""
	if scene_path != "":
		scene_info = CandyDEData.scene_exports(scene_path, EXPORTS)

	exports_text.clear()
	for variable in EXPORTS:
		if scene_info.is_empty() or not scene_info["problems"].is_empty():
			Style.rich_item(exports_text, "StatusWarning", _dim(Style.code(variable)), Style.dim())
		elif scene_info["values"].has(variable):
			Style.rich_item(exports_text, "StatusSuccess", Style.code(variable))
		else:
			Style.rich_item(exports_text, "StatusError", "%s  %s" % [Style.code(variable), Style.colored("not exported", "error_color")])


func _fill_dialogues() -> void:
	var gathered := CandyDEData.dialogue_names()
	dialogue_problems = gathered["problems"]
	var entries := []
	for dialogue_name in gathered["names"]:
		entries.append([dialogue_name, dialogue_name])
	_fill(dialogue_select, entries, _wanted("dialogue"))
	_read_dialogue()
	_fill_conversations()


func _read_dialogue() -> void:
	conversations = {}
	dialogue_problem = ""
	var dialogue_name := _selected(dialogue_select)
	if dialogue_name == "":
		return
	var read := CandyDEData.read_dialogue(dialogue_name)
	conversations = read["conversations"]
	dialogue_problem = read["problem"]


func _fill_conversations() -> void:
	var entries := []
	for conversation in conversations:
		if conversations[conversation] is Dictionary:
			entries.append([str(conversation), str(conversation)])
	_fill(conversation_select, entries, _wanted("conversation"))
	_fill_blocks()


#* The chosen conversation's blocks with a "Text" array:
func _fill_blocks() -> void:
	var entries := []
	var conversation = conversations.get(_selected(conversation_select))
	if conversation is Dictionary:
		for block in conversation:
			if conversation[block] is Dictionary and conversation[block].get("Text") is Array:
				entries.append([str(block), str(block)])
	_fill(block_select, entries, _wanted("block"))
	_fill_lines()


#* The chosen block's lines, with index and summary:
func _fill_lines() -> void:
	var entries := []
	var lines := _block_lines()
	for index in lines.size():
		entries.append(["%d    %s" % [index, _line_summary(lines[index])], str(index)])
	_fill(line_select, entries, _wanted("line"))
	_update_run()


#* The chosen block's lines ([] for none):
func _block_lines() -> Array:
	var conversation = conversations.get(_selected(conversation_select))
	if not conversation is Dictionary:
		return []
	var block = conversation.get(_selected(block_select))
	if not block is Dictionary or not block.get("Text") is Array:
		return []
	return block["Text"]


#* Fill a drop-down with [text, value] entries, selecting wanted (else the first):
func _fill(select: OptionButton, entries: Array, wanted: String) -> void:
	select.clear()
	select.disabled = entries.is_empty()
	if entries.is_empty():
		select.add_item("None")
		select.set_item_metadata(0, "")
		return
	var chosen := 0
	for index in entries.size():
		select.add_item(entries[index][0])
		select.set_item_metadata(index, entries[index][1])
		if entries[index][1] == wanted:
			chosen = index
	select.select(chosen)


func _selected(select: OptionButton) -> String:
	if select.selected == -1:
		return ""
	return str(select.get_item_metadata(select.selected))


#* A start drop-down's value - the last choice, or the scene's own:
func _wanted(variable: String) -> String:
	if choices.has(variable):
		return str(choices[variable])
	if not scene_info.is_empty() and scene_info["values"].get(variable) != null:
		return str(scene_info["values"][variable])
	return ""


#* Remember the choices:
func _remember() -> void:
	choices = {
		"scene": _selected(scene_select),
		"dialogue": _selected(dialogue_select),
		"conversation": _selected(conversation_select),
		"block": _selected(block_select),
		"line": _selected(line_select),
	}
	EditorInterface.get_editor_settings().set_project_metadata(Runner.METADATA_SECTION, Runner.METADATA_KEY, choices)


#==============================================================================
#  RUN
#==============================================================================

#* What stops the test from running:
func _problems() -> PackedStringArray:
	var problems: PackedStringArray = []
	problems.append_array(scene_problems)
	if not scene_info.is_empty():
		problems.append_array(scene_info["problems"])
		if scene_info["problems"].is_empty():
			var missing: PackedStringArray = []
			for variable in EXPORTS:
				if not scene_info["values"].has(variable):
					missing.append(variable)
			if not missing.is_empty():
				problems.append("The testing scene's root doesn't export %s." % ", ".join(missing))
	problems.append_array(dialogue_problems)
	if dialogue_problem != "":
		problems.append(dialogue_problem)
	elif _selected(dialogue_select) != "":
		if _selected(conversation_select) == "":
			problems.append("The dialogue has no conversations.")
		elif _selected(block_select) == "":
			problems.append("%s has no blocks with lines." % _selected(conversation_select))
		elif _selected(line_select) == "":
			problems.append("%s has no lines." % _selected(block_select))
	return problems


#* Show what will run, or what stops it:
func _update_run() -> void:
	run_text.clear()
	var problems := _problems()
	if problems.is_empty():
		Style.rich_item(run_text, "PackedScene", Style.code(_selected(scene_select).get_file()))
		var start := PackedStringArray([_selected(dialogue_select), _selected(conversation_select), _selected(block_select), "line " + _selected(line_select)])
		Style.rich_item(run_text, "Play", Style.code("  ›  ".join(start)))
		var lines := _block_lines()
		var index := _selected(line_select).to_int()
		if index < lines.size():
			Style.rich_item(run_text, "ArrowRight", _dim(Style.escaped(_line_summary(lines[index]))))
	for problem in problems:
		Style.rich_item(run_text, "StatusError", Style.colored(Style.escaped(problem), "error_color"))
	test_button.disabled = not problems.is_empty()
	if problems.is_empty():
		run_panel.add_theme_stylebox_override("panel", Style.card(Style.BRAND))
	else:
		run_panel.add_theme_stylebox_override("panel", Style.card(Style.color("error_color")))


#* Refresh, then run the testing scene from the chosen line:
func _test() -> void:
	refresh()
	if not _problems().is_empty():
		return
	var values := {
		"dialogue": _selected(dialogue_select),
		"conversation": _selected(conversation_select),
		"block": _selected(block_select),
		"line": _selected(line_select),
	}
	var error := Runner.run(_selected(scene_select), values)
	if error != "":
		Style.rich_item(run_text, "StatusError", Style.colored(Style.escaped(error), "error_color"))


#==============================================================================
#  HELPERS
#==============================================================================

#* A line's summary - its commands, with their main detail:
func _line_summary(line: Variant) -> String:
	if not line is Dictionary or line.is_empty():
		return "?"
	var parts: PackedStringArray = []
	for command in line:
		var detail := _command_detail(str(command), line[command])
		if detail == "":
			parts.append(str(command))
		else:
			parts.append("%s   %s" % [command, detail])
	var summary := "   +   ".join(parts).replace("\n", " ")
	if summary.length() > SUMMARY_LENGTH:
		summary = summary.substr(0, SUMMARY_LENGTH - 1) + "…"
	return summary


#* A command's main detail, or "":
func _command_detail(command: String, data: Variant) -> String:
	if not data is Dictionary:
		return ""
	match command.to_lower():
		"spoken_line":
			var text := ""
			var variants = data.get("Variants")
			if variants is Array and not variants.is_empty() and variants[0] is Dictionary and not variants[0].is_empty():
				var variant = variants[0].get("Default", variants[0].values()[0])
				if variant is Dictionary:
					text = str(variant.get("Text", ""))
			return "%s: %s" % [str(data.get("Reference", "?")), text]
		"comment":
			return str(data.get("Comment", ""))
		"lm":
			return str(data.get("Reference", ""))
		"jump", "bridge":
			var target := PackedStringArray()
			for key in ["Conversation", "Block", "Line"]:
				if str(data.get(key, "")) != "":
					target.append(str(data[key]))
			return "→ " + " › ".join(target)
	return ""


func _dim(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.dim().to_html(false), text]
