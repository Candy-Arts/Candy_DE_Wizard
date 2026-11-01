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
extends "Wizard.gd"


const DialogueFiles = preload("Dialogue_Files.gd")
const DialogueOptions = preload("Dialogue_Options.gd")
const DialogueConverter = preload("Dialogue_Converter.gd")
const SymbolFiles = preload("Symbol_Files.gd")

enum Step { FILES, PROJECT, REVIEW, CONVERTING, DONE }

const STEP_HEADINGS := {
	Step.FILES: "Dialogues to convert",
	Step.PROJECT: "Your 1.1 project",
	Step.REVIEW: "What the conversion does",
	Step.CONVERTING: "Converting",
}

#^ Where each step is in the header's list of steps:
const STEP_MARKERS := {
	Step.FILES: 0,
	Step.PROJECT: 1,
	Step.REVIEW: 2,
	Step.CONVERTING: 3,
	Step.DONE: 3,
}

#^ The 1.1 symbols' fields: [converter key, label]:
const OLD_SYMBOLS := [
	["vardict_symbol", "Variables"],
	["super_vardict_symbol", "Super variables"],
	["singleton_symbol", "Singleton"],
	["super_singleton_symbol", "Super singleton"],
	["node_symbol", "Node"],
	["super_node_symbol", "Super node"],
	["role_symbol", "Role"],
	["file_var_symbol", "File variable"],
	["text_var_symbol_start", "Text variable start"],
	["text_var_symbol_end", "Text variable end"],
	["substitution_symbol", "Substitution"],
	["separator_symbol", "Separator"],
]
const UI_ELEMENT_LABELS := {
	"dialogue_box_path": "Dialogue box",
	"subtitles_path": "Subtitles",
	"chat_path": "Chat",
	"barks_path": "Barks",
}
const PORTRAIT_LABELS := {
	DialogueConverter.PORTRAIT_SPRITE: "Sprite, AnimatedSprite, or not sure",
	DialogueConverter.PORTRAIT_FOLDER: "TextureRect or NinePatchRect",
	DialogueConverter.PORTRAIT_VIDEO: "VideoStreamPlayer",
}

#^ How many files and notes each summary list names before only counting them:
const LISTED_FILES := 12
const LISTED_CHECKS := 8

var formats := {}					#/ Dialogue_Options.dialogue_formats(), read once
var results: Array = []				#/ Dialogue_Files.plan_files(), then convert_files()
var converted_count := 0

#^ Pages:
var file_tree: Tree
var file_count_label: Label
var old_symbol_edits := {}			#/ Converter key -> LineEdit
var symbols_source: Label
var tts_select: OptionButton
var portrait_select: OptionButton
var element_checks := {}			#/ ui_elements_paths key -> CheckBox
var layers_edit: LineEdit
var engine_source: Label
var new_symbols_label: RichTextLabel
var summary_text: RichTextLabel
var done_banner: Dictionary
var done_text: RichTextLabel
var log_button: Button


func _ready() -> void:
	title = "Convert Dialogues"
	super()
	#? Wider and taller: the 1.1 project's settings sit side by side.
	min_size = Vector2i(Style.px(920), Style.px(680))
	formats = DialogueOptions.dialogue_formats()
	_fill_files()
	_fill_options()
	_show_step(Step.FILES)


func _build_pages() -> Dictionary:
	var built := {}
	built[Step.FILES] = _build_files_page()
	built[Step.PROJECT] = _build_project_page()
	var review := VBoxContainer.new()
	summary_text = _rich_text()
	review.add_child(summary_text)
	built[Step.REVIEW] = review
	built[Step.CONVERTING] = _build_progress_page()
	var done_page := VBoxContainer.new()
	done_page.add_theme_constant_override("separation", Style.px(14))
	done_banner = _build_result_banner(done_page)
	done_text = _rich_text()
	done_page.add_child(done_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", Style.px(8))
	done_page.add_child(buttons)
	log_button = Style.button("Open Conversion Log", "File", _open_log)
	log_button.tooltip_text = "Every converted line to check, and why, beside the backups."
	buttons.add_child(log_button)
	built[Step.DONE] = done_page
	return built


func _step_names() -> PackedStringArray:
	return PackedStringArray(["Dialogues", "1.1 Project", "Review", "Convert"])


func _subtitle() -> String:
	return "Rewrites dialogues written for Candy DE 1.1.3 in the 1.2 format."


#==============================================================================
#  DIALOGUES
#==============================================================================

func _build_files_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Style.px(10))
	page.add_child(_wrapped_label("Each ticked dialogue is rewritten for 1.2, command by command, as Candy Dialogue Creator's Dialogue Converter does, then saved in its place. The original is backed up beside it first, in Conversion Backups/1.1 to 1.2."))

	file_tree = Tree.new()
	file_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_tree.hide_root = true
	file_tree.columns = 2
	file_tree.column_titles_visible = true
	file_tree.set_column_title(0, "Dialogue")
	file_tree.set_column_title(1, "Format")
	file_tree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
	file_tree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)
	file_tree.set_column_expand(1, false)
	file_tree.set_column_custom_minimum_width(1, Style.px(260))
	file_tree.item_edited.connect(_update_buttons)
	file_tree.create_item()
	page.add_child(file_tree)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(6))
	page.add_child(row)
	row.add_child(Style.button("Tick All", "", _tick_all.bind(true)))
	row.add_child(Style.button("Untick All", "", _tick_all.bind(false)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	file_count_label = Style.caption("")
	file_count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	file_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(file_count_label)
	return page


#* Every dialogue of dialogues_folder - those in the 1.1 format ticked, the others with why not:
func _fill_files() -> void:
	var prefix := String(formats["folder"]) + "/"
	for path in formats["all"]:
		var info := DialogueFiles.inspect(path)
		var item := file_tree.create_item(file_tree.get_root())
		item.set_metadata(0, path)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_text(0, String(path).trim_prefix(prefix))
		item.set_tooltip_text(0, path)
		var convertible := String(info["status"]) == DialogueFiles.STATUS_CONVERT
		item.set_editable(0, convertible)
		item.set_checked(0, convertible)
		item.set_text(1, _format_text(info))
		if convertible:
			item.set_icon(1, Style.icon("StatusWarning"))
		else:
			if String(info["status"]) == DialogueFiles.STATUS_CURRENT:
				item.set_icon(1, Style.icon("StatusSuccess"))
			else:
				item.set_icon(1, Style.icon("StatusError"))
			item.set_custom_color(0, Style.dim())
			item.set_custom_color(1, Style.dim())
		item.set_tooltip_text(1, String(info["problem"]))


#* A file's format, and why it isn't converted if it isn't:
func _format_text(info: Dictionary) -> String:
	var version := String(info["version"])
	match String(info["status"]):
		DialogueFiles.STATUS_CONVERT:
			if version == "":
				return "1.1 (no version, 1.1 commands)"
			return version
		DialogueFiles.STATUS_CURRENT:
			if version == "":
				return "1.2 (no 1.1 commands)"
			return "%s, already converted" % version
		DialogueFiles.STATUS_OLD:
			return "%s: too old (hover for why)" % version
	return "Can't be converted (hover for why)"


func _tick_all(ticked: bool) -> void:
	for item in file_tree.get_root().get_children():
		if item.is_editable(0):
			item.set_checked(0, ticked)
	_update_buttons()


func _ticked_paths() -> Array:
	var paths: Array = []
	for item in file_tree.get_root().get_children():
		if item.is_checked(0):
			paths.append(String(item.get_metadata(0)))
	return paths


#==============================================================================
#  YOUR 1.1 PROJECT
#==============================================================================

#* The 1.1 symbols and the 1.1 engine side by side, the 1.2 symbols below:
func _build_project_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Style.px(10))
	page.add_child(_wrapped_label("What a 1.1 dialogue meant depended on a few things it doesn't hold. Candy Wizard filled them in from what it could find: correct anything your 1.1 project did differently."))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", Style.px(10))
	page.add_child(columns)

	var symbols_box := Style.card_box(columns)
	symbols_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	symbols_box.get_parent().size_flags_stretch_ratio = 1.1
	Style.card_title(symbols_box, "KeyboardLabel", "1.1 symbols")
	symbols_source = Style.caption("")
	symbols_box.add_child(symbols_source)
	var symbol_grid := GridContainer.new()
	symbol_grid.columns = 4
	symbol_grid.add_theme_constant_override("h_separation", Style.px(8))
	symbol_grid.add_theme_constant_override("v_separation", Style.px(4))
	symbols_box.add_child(symbol_grid)
	for entry in OLD_SYMBOLS:
		var symbol_label := Style.label(String(entry[1]))
		symbol_label.tooltip_text = "var %s, in Candy DE 1.1.3's Candy_Properties.gd." % entry[0]
		symbol_label.mouse_filter = Control.MOUSE_FILTER_PASS
		symbol_grid.add_child(symbol_label)
		var edit := LineEdit.new()
		edit.custom_minimum_size.x = Style.px(56)
		edit.add_theme_font_override("font", Style.font("source"))
		edit.tooltip_text = symbol_label.tooltip_text
		symbol_grid.add_child(edit)
		old_symbol_edits[entry[0]] = edit

	var engine_box := Style.card_box(columns)
	engine_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.card_title(engine_box, "Node", "1.1 engine and scenes")
	engine_source = Style.caption("")
	engine_box.add_child(engine_source)
	var engine_grid := GridContainer.new()
	engine_grid.columns = 2
	engine_grid.add_theme_constant_override("h_separation", Style.px(10))
	engine_grid.add_theme_constant_override("v_separation", Style.px(6))
	engine_box.add_child(engine_grid)

	tts_select = OptionButton.new()
	for tts_mode in DialogueConverter.TTS_MODES:
		tts_select.add_item(tts_mode)
	_engine_row(engine_grid, "Text to speech", tts_select, "Your engine's text_to_speech. For lines with TTS on (\"1\"): 1.1 read them in the engine's TTS mode, 1.2 lines name their own mode, so this one is written into them.")

	portrait_select = OptionButton.new()
	for key in PORTRAIT_LABELS:
		portrait_select.add_item(PORTRAIT_LABELS[key])
	_engine_row(engine_grid, "Portrait node", portrait_select, "The portrait_node of your portrait scene. For every spoken line: 1.1's PortraitPlay played a portrait differently depending on this node (looping until replaced, showing its first frame, or playing once). 1.2 counts loops instead.")

	var elements := VBoxContainer.new()
	elements.add_theme_constant_override("separation", 0)
	for element in UI_ELEMENT_LABELS:
		var check := CheckBox.new()
		check.text = UI_ELEMENT_LABELS[element]
		check.tooltip_text = element
		elements.add_child(check)
		element_checks[element] = check
	var elements_label := _engine_row(engine_grid, "Dialogue UI", elements, "The keys of your engine's ui_elements_paths. For Hide, V_Show and I_Show, which become UI_Z: 1.1 moved every dialogue UI element the engine had, 1.2 names each one. Tick only the ones your engine has.")
	elements_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	layers_edit = LineEdit.new()
	layers_edit.placeholder_text = "Sky, Ground…"
	_engine_row(engine_grid, "Background layers", layers_edit, "The children of your background scenes' bg_container, separated by commas. For background commands with no Layers, which meant every layer in 1.1: 1.2 needs each layer named.")

	var new_box := Style.card_box(page)
	Style.card_title(new_box, "KeyboardLabel", "1.2 symbols they're written with")
	new_symbols_label = Style.rich_text(false)
	new_symbols_label.fit_content = true
	new_symbols_label.scroll_active = false
	new_symbols_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	new_box.add_child(new_symbols_label)
	new_box.add_child(Style.caption("From Candy_Properties.gd. To write the dialogues with other symbols, change them first, in the Symbols tool."))
	return page


#* A setting's row (its help as the label's tooltip), returning the label:
func _engine_row(grid: GridContainer, text: String, control: Control, help: String) -> Label:
	var row_label := Style.label(text)
	row_label.tooltip_text = help
	row_label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(row_label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = help
	grid.add_child(control)
	return row_label


#* The fields - last time's entries, else the 1.1.3 copy's, else 1.1.3's defaults:
#? The captions say which.
func _fill_options() -> void:
	var install := DialogueOptions.old_install()
	var copy_name := ""
	if not install.is_empty():
		copy_name = String(install["folder"]).get_file()

	var remembered_symbols := DialogueOptions.remembered_old_symbols()
	var found_symbols := DialogueOptions.old_symbols_found(install)
	var defaults := DialogueConverter.default_old_symbols()
	for key in old_symbol_edits:
		var value := String(defaults.get(key, ""))
		if remembered_symbols.has(key):
			value = String(remembered_symbols[key])
		elif found_symbols.has(key):
			value = String(found_symbols[key])
		old_symbol_edits[key].text = value
	if not remembered_symbols.is_empty():
		symbols_source.text = "As you entered them last time."
	elif not found_symbols.is_empty():
		symbols_source.text = "From your 1.1.3 install's Candy_Properties.gd (kept in .Install/%s)." % copy_name
	else:
		symbols_source.text = "Candy DE 1.1.3's defaults: no 1.1.3 install was found to read them from."

	var remembered_project := DialogueOptions.remembered_project()
	var found_project := DialogueOptions.project_found(install)
	var project := DialogueConverter.default_project()
	for key in found_project:
		project[key] = found_project[key]
	for key in remembered_project:
		project[key] = remembered_project[key]
	tts_select.select(maxi(DialogueConverter.TTS_MODES.find(String(project["tts"])), 0))
	portrait_select.select(maxi(PORTRAIT_LABELS.keys().find(String(project["portrait_node"])), 0))
	var elements = project["ui_elements"]
	for element in element_checks:
		element_checks[element].button_pressed = elements is Array and element in elements
	layers_edit.text = String(project["bg_layers"])
	if not remembered_project.is_empty():
		engine_source.text = "As you entered them last time."
	elif not found_project.is_empty():
		engine_source.text = "From your 1.1.3 install's Candy_UI.tscn and scenes. Hover a setting to see which lines it's for."
	else:
		engine_source.text = "Candy DE 1.1.3's defaults. Hover a setting to see which lines it's for: if your dialogues have none, leave it."

	new_symbols_label.clear()
	var symbols := DialogueOptions.new_symbols()
	var parts: PackedStringArray = [
		"Expression %s" % Style.code(symbols["expression"]),
		"Text variables %s" % Style.code("%s…%s" % [symbols["text_var_start"], symbols["text_var_end"]]),
		"Substitutions %s" % Style.code("%s…%s" % [symbols["substitution_start"], symbols["substitution_end"]]),
		#? 1.1 text only gets these doubled (no text events or lexicon escapes in 1.1), so they still display:
		"Text events %s" % Style.code("%s…%s" % [symbols["text_event_start"], symbols["text_event_end"]]),
		"Lexicon escapes %s" % Style.code("%s…%s" % [symbols.get("lexicon_escape_start", ""), symbols.get("lexicon_escape_end", "")]),
	]
	new_symbols_label.append_text("     ".join(parts))


func _old_symbols() -> Dictionary:
	var symbols := {}
	for key in old_symbol_edits:
		symbols[key] = old_symbol_edits[key].text.strip_edges()
	return symbols


func _project() -> Dictionary:
	var elements: Array = []
	for element in element_checks:
		if element_checks[element].button_pressed:
			elements.append(element)
	return {
		"tts": DialogueConverter.TTS_MODES[maxi(tts_select.selected, 0)],
		"portrait_node": PORTRAIT_LABELS.keys()[maxi(portrait_select.selected, 0)],
		"ui_elements": elements,
		"bg_layers": layers_edit.text.strip_edges(),
	}


#==============================================================================
#  NAVIGATION
#==============================================================================

func _show_step(new_step: int) -> void:
	_show_page(new_step)
	_set_step_marker(STEP_MARKERS[step], step == Step.DONE and converted_count > 0)
	if step == Step.DONE:
		#? The result banner heads the last page.
		heading_label.text = ""
	else:
		heading_label.text = STEP_HEADINGS[step]
	_update_buttons()


func _update_buttons() -> void:
	back_button.visible = step != Step.DONE
	back_button.disabled = busy or step == Step.FILES or step == Step.CONVERTING
	next_button.disabled = busy or step == Step.CONVERTING
	cancel_button.disabled = step == Step.CONVERTING
	cancel_button.text = "Cancel"
	next_button.visible = true
	next_button.icon = null
	var ticked := _ticked_paths().size()
	match step:
		Step.FILES:
			_set_next("Next", "primary")
			next_button.disabled = ticked == 0
			file_count_label.text = "%d of %d dialogue%s ticked" % [ticked, formats["all"].size(), _plural(formats["all"].size())]
		Step.REVIEW:
			var count := _planned_count()
			_set_next("Convert %d Dialogue%s" % [count, _plural(count)], "primary")
			next_button.icon = Style.icon("Reload")
			next_button.disabled = count == 0
		Step.DONE:
			next_button.visible = false
			cancel_button.text = "Close"
		_:
			_set_next("Next", "primary")


func _on_back_pressed() -> void:
	error_label.text = ""
	match step:
		Step.PROJECT:
			_show_step(Step.FILES)
		Step.REVIEW:
			_show_step(Step.PROJECT)


func _on_next_pressed() -> void:
	error_label.text = ""
	match step:
		Step.FILES:
			_show_step(Step.PROJECT)
		Step.PROJECT:
			DialogueOptions.remember(_old_symbols(), _project())
			var new_symbols := DialogueOptions.new_symbols()
			results = DialogueFiles.plan_files(_ticked_paths(), _old_symbols(), new_symbols, _project(),
				SymbolFiles.converted_symbols(_old_symbols(), new_symbols))
			_fill_summary()
			_show_step(Step.REVIEW)
		Step.REVIEW:
			_convert()


func _on_cancel_pressed() -> void:
	if step == Step.CONVERTING:
		return
	_close()


#==============================================================================
#  REVIEW
#==============================================================================

func _planned_count() -> int:
	var count := 0
	for result in results:
		if String(result["outcome"]) == DialogueFiles.OUTCOME_CONVERTED:
			count += 1
	return count


#* The planned conversion - the files, those that can't be converted, and the grouped checks:
func _fill_summary() -> void:
	summary_text.clear()
	var prefix := String(formats["folder"]) + "/"
	var planned: Array = []
	var failed: Array = []
	for result in results:
		if String(result["outcome"]) == DialogueFiles.OUTCOME_CONVERTED:
			planned.append(result)
		else:
			failed.append(result)

	if not planned.is_empty():
		Style.rich_heading(summary_text, "To convert (%d)" % planned.size())
		for index in min(planned.size(), LISTED_FILES):
			var result: Dictionary = planned[index]
			var counts := _note_counts(result)
			var text := Style.code(String(result["path"]).trim_prefix(prefix))
			if counts["check"] > 0:
				text += "  " + Style.colored("%d line%s to check" % [counts["check"], _plural(counts["check"])], "warning_color")
			if counts["note"] > 0:
				text += "  " + _dim("%d note%s" % [counts["note"], _plural(counts["note"])])
			var icon_name := "StatusSuccess"
			if counts["check"] > 0:
				icon_name = "StatusWarning"
			Style.rich_item(summary_text, icon_name, text)
		_add_more(summary_text, planned.size(), LISTED_FILES)

	if not failed.is_empty():
		Style.rich_heading(summary_text, "Not converted (%d)" % failed.size())
		for result in failed:
			Style.rich_item(summary_text, "StatusError", "%s  %s" % [Style.code(String(result["path"]).trim_prefix(prefix)), _colored(_escaped(String(result["message"])), "error_color")])
			for group in DialogueFiles.grouped_notes(result):
				if String(group["level"]) == DialogueConverter.LEVEL_CHECK:
					Style.rich_item(summary_text, "GuiTreeArrowRight", _dim(_escaped(String(group["text"]))))

	var checks := _grouped_checks(planned)
	if not checks.is_empty():
		Style.rich_heading(summary_text, "To check once converted")
		for index in min(checks.size(), LISTED_CHECKS):
			var entry: Dictionary = checks[index]
			Style.rich_item(summary_text, "StatusWarning", "%s  %s" % [_escaped(String(entry["text"])), _dim("(%d line%s)" % [entry["count"], _plural(entry["count"])])])
		_add_more(summary_text, checks.size(), LISTED_CHECKS)
		Style.rich_item(summary_text, "File", _dim("Conversion Log.txt, written beside the backups, lists every line each one is about."))

	Style.rich_heading(summary_text, "Backups")
	Style.rich_item(summary_text, "Save", "Each file is backed up first, beside it, in %s." % Style.code("Conversion Backups/1.1 to 1.2/<date and time>"))
	Style.rich_item(summary_text, "Info", _dim("Candy Wizard's tools leave Conversion Backups folders out: they aren't read as dialogues."))
	_update_buttons()


#* A result's notes, counted by level ({"check", "note"}):
func _note_counts(result: Dictionary) -> Dictionary:
	var counts := {"check": 0, "note": 0}
	for note in result["notes"]:
		if String(note["level"]) == DialogueConverter.LEVEL_CHECK:
			counts["check"] += 1
		else:
			counts["note"] += 1
	return counts


#* The notes to check across the files, by text, most frequent first ([{"text", "count"}]):
#? A note naming a value of its line is its own entry.
func _grouped_checks(planned: Array) -> Array:
	var counts := {}
	for result in planned:
		for note in result["notes"]:
			if String(note["level"]) != DialogueConverter.LEVEL_CHECK:
				continue
			var text := String(note["text"])
			counts[text] = int(counts.get(text, 0)) + 1
	var grouped: Array = []
	for text in counts:
		grouped.append({"text": text, "count": counts[text]})
	grouped.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["count"] > b["count"])
	return grouped


#==============================================================================
#  CONVERTING
#==============================================================================

func _convert() -> void:
	if _planned_count() == 0:
		return
	busy = true
	_show_step(Step.CONVERTING)
	_on_work_progress(0.2, "Backing up and writing the dialogues…")
	await get_tree().process_frame
	DialogueFiles.convert_files(results, wizard_version)
	_on_work_progress(0.8, "Letting Godot scan the files…")
	await Utils.scan_filesystem(get_tree())
	_on_work_progress(1.0, "Done.")
	busy = false
	_fill_done()
	_show_step(Step.DONE)


func _fill_done() -> void:
	done_text.clear()
	var prefix := String(formats["folder"]) + "/"
	var converted: Array = []
	var failed: Array = []
	var checks := 0
	for result in results:
		if String(result["outcome"]) == DialogueFiles.OUTCOME_CONVERTED and String(result["backup"]) != "":
			converted.append(result)
			checks += _note_counts(result)["check"]
		elif String(result["outcome"]) == DialogueFiles.OUTCOME_FAILED:
			failed.append(result)
	converted_count = converted.size()

	var details := "Each was backed up beside it first."
	if checks > 0:
		details = "%d line%s to check: the conversion log lists %s, and why." % [checks, _plural(checks), _them(checks)]
	if converted.is_empty():
		_set_result_banner(done_banner, false, "No dialogue was converted", "")
	elif failed.is_empty():
		_set_result_banner(done_banner, true, "%d dialogue%s converted to 1.2" % [converted.size(), _plural(converted.size())], details)
	else:
		_set_result_banner(done_banner, true, "%d dialogue%s converted, %d not" % [converted.size(), _plural(converted.size()), failed.size()], details)
		done_banner["icon"].texture = Style.icon("StatusWarning")

	if not converted.is_empty():
		Style.rich_heading(done_text, "Converted")
		for index in min(converted.size(), LISTED_FILES):
			var result: Dictionary = converted[index]
			Style.rich_item(done_text, "StatusSuccess", Style.code(String(result["path"]).trim_prefix(prefix)))
		_add_more(done_text, converted.size(), LISTED_FILES)
	if not failed.is_empty():
		Style.rich_heading(done_text, "Not converted")
		for result in failed:
			Style.rich_item(done_text, "StatusError", "%s  %s" % [Style.code(String(result["path"]).trim_prefix(prefix)), _colored(_escaped(String(result["message"])), "error_color")])
	if checks > 0:
		Style.rich_heading(done_text, "Next")
		Style.rich_item(done_text, "StatusWarning", "Open the conversion log, and look at each line it lists in Candy Dialogue Creator: it may not do what it did in 1.1.3.")
	log_button.visible = _log_path() != ""


#* The run's log (beside the first file's backup), or "":
func _log_path() -> String:
	for result in results:
		if String(result.get("backup", "")) != "":
			var path := String(result["backup"]).get_base_dir().path_join(DialogueFiles.LOG_FILE)
			if FileAccess.file_exists(path):
				return path
	return ""


func _open_log() -> void:
	var path := _log_path()
	if path != "":
		OS.shell_open(ProjectSettings.globalize_path(path))


#==============================================================================
#  TEXT
#==============================================================================

func _add_more(text: RichTextLabel, count: int, listed: int) -> void:
	if count > listed:
		Style.rich_item(text, "GuiEllipsis", _dim("and %d more" % (count - listed)))


func _dim(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.dim().to_html(false), text]


func _plural(count: int) -> String:
	if count == 1:
		return ""
	return "s"


func _them(count: int) -> String:
	if count == 1:
		return "it"
	return "them"
