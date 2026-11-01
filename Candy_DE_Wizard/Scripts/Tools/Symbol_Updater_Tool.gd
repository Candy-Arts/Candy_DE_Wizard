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
const Utils = preload("../Wizard_Utils.gd")
const DialogueOptions = preload("../Dialogue_Options.gd")
const Rules = preload("../Symbol_Rules.gd")
const SymbolFiles = preload("../Symbol_Files.gd")
const SymbolUpdater = preload("../Symbol_Updater.gd")

#^ Results and checks listed in the last update's card, before "and N more":
const LISTED_RESULTS := 6
const LISTED_CHECKS := 5

var stale := false						#/ The files changed while the tool was hidden
var busy := false
var project := {}						#/ SymbolFiles.project_symbols()
var infos := {}							#/ Path -> SymbolFiles.inspect(), without its data
var folder := ""
var results: Array = []					#/ The last update's

var status_card: PanelContainer
var status_icon: TextureRect
var status_title: Label
var status_details: Label
var file_tree: Tree
var count_label: Label
var update_button: Button
var record_button: Button
var details_title: Label
var details_grid: GridContainer
var details_text: RichTextLabel
var done_card: PanelContainer
var done_title: Label
var done_text: RichTextLabel
var log_button: Button


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

	_build_list(cards)
	_build_details(cards)
	_build_done(cards)

	visibility_changed.connect(func() -> void:
		if stale and is_visible_in_tree():
			refresh())
	refresh()


#* The dialogues card - status, list, buttons:
func _build_list(cards: HBoxContainer) -> void:
	var box := Style.card_box(cards)
	status_card = box.get_parent()
	status_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_card.custom_minimum_size.x = Style.px(440)
	Style.card_title(box, "ReplaceText", "Dialogue symbols")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(10))
	box.add_child(row)
	status_icon = Style.icon_rect(null, 24)
	row.add_child(status_icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	status_title = Style.label("")
	texts.add_child(status_title)
	status_details = Style.caption("")
	texts.add_child(status_details)

	file_tree = Tree.new()
	file_tree.custom_minimum_size.y = Style.px(150)
	file_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_tree.hide_root = true
	file_tree.columns = 2
	file_tree.column_titles_visible = true
	file_tree.set_column_title(0, "Dialogue")
	file_tree.set_column_title(1, "Symbols")
	file_tree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
	file_tree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)
	file_tree.set_column_expand(1, false)
	file_tree.set_column_custom_minimum_width(1, Style.px(200))
	file_tree.item_edited.connect(_update_button)
	file_tree.item_selected.connect(_show_details)
	box.add_child(file_tree)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", Style.px(6))
	box.add_child(actions)
	actions.add_child(Style.button("Tick All", "", _tick_all.bind(true)))
	actions.add_child(Style.button("Untick All", "", _tick_all.bind(false)))
	count_label = Style.caption("")
	count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(count_label)
	record_button = Style.button("Record Symbols…", "Edit", _record)
	record_button.tooltip_text = "Write the symbols the ticked dialogues were written with into them, for those that don't record theirs. Nothing else in them changes."
	actions.add_child(record_button)
	update_button = Style.button("Update Symbols…", "Reload", _update)
	update_button.tooltip_text = "Rewrite the ticked dialogues with the project's symbols. Each is backed up beside it first."
	Style.make_primary(update_button)
	actions.add_child(update_button)


#* The details card - the selected dialogue's symbols that differ from the project's:
func _build_details(cards: HBoxContainer) -> void:
	var box := Style.card_box(cards)
	box.get_parent().custom_minimum_size.x = Style.px(360)
	var title_row := Style.card_title(box, "Info", "")
	details_title = title_row.get_child(title_row.get_child_count() - 1)

	details_grid = GridContainer.new()
	details_grid.columns = 3
	details_grid.add_theme_constant_override("h_separation", Style.px(16))
	details_grid.add_theme_constant_override("v_separation", Style.px(4))
	box.add_child(details_grid)

	details_text = Style.rich_text(false)
	details_text.fit_content = true
	details_text.custom_minimum_size.x = Style.px(320)
	box.add_child(details_text)


#* The last update's card, hidden until there's one:
func _build_done(cards: HBoxContainer) -> void:
	var box := Style.card_box(cards)
	done_card = box.get_parent()
	done_card.custom_minimum_size.x = Style.px(360)
	done_card.visible = false
	var title_row := Style.card_title(box, "StatusSuccess", "")
	done_title = title_row.get_child(title_row.get_child_count() - 1)
	done_text = Style.rich_text(false)
	done_text.fit_content = true
	done_text.custom_minimum_size.x = Style.px(320)
	done_text.meta_clicked.connect(func(path) -> void: EditorInterface.get_file_system_dock().navigate_to_path(str(path)))
	box.add_child(done_text)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", Style.px(6))
	box.add_child(actions)
	log_button = Style.button("Open Log", "File", _open_log)
	log_button.tooltip_text = "Open the update's log, which lists every line to check."
	actions.add_child(log_button)
	var dismiss := Style.button("Dismiss", "", func() -> void: done_card.visible = false)
	dismiss.flat = true
	actions.add_child(dismiss)


#==============================================================================
#  READING
#==============================================================================

#* Read the project's symbols and every dialogue's again (on file changes):
func refresh() -> void:
	if status_card == null or busy or not CandyDEData.is_available():
		return
	#% Deferred while hidden (every dialogue is read):
	if not is_visible_in_tree():
		stale = true
		return
	stale = false

	#Ł Remember the selection and ticks across the reload:
	var selected := ""
	var ticks := {}		#/ Path -> ticked, for the rows that could be ticked
	if file_tree.get_root() != null:
		if file_tree.get_selected() != null:
			selected = str(file_tree.get_selected().get_metadata(0))
		for item in file_tree.get_root().get_children():
			if item.is_editable(0):
				ticks[str(item.get_metadata(0))] = item.is_checked(0)

	project = SymbolFiles.project_symbols()
	var formats := DialogueOptions.dialogue_formats()
	folder = str(formats["folder"])
	infos.clear()
	file_tree.clear()
	file_tree.create_item()
	var to_update := 0
	var not_recorded := 0
	var to_select: TreeItem = null
	for path in formats["all"]:
		var info := SymbolFiles.inspect(path, project["symbols"])
		info.erase("data")
		info.erase("raw")
		infos[path] = info
		var item := _add_item(path, info, ticks)
		if str(info["status"]) == SymbolFiles.STATUS_NOT_STORED:
			not_recorded += 1
		if str(info["status"]) == SymbolFiles.STATUS_UPDATE:
			to_update += 1
			if to_select == null:
				to_select = item
		if path == selected:
			to_select = item
	if to_select == null and file_tree.get_root().get_child_count() > 0:
		to_select = file_tree.get_root().get_child(0)

	var total: int = formats["all"].size()
	if str(formats["problem"]) != "":
		_show_status("StatusWarning", Style.color("warning_color"), "Can't read the dialogues", str(formats["problem"]))
	elif str(project["problem"]) != "":
		_show_status("StatusError", Style.color("error_color"), "The project's symbols can't be used", "%s Fix them in the Symbols tool." % project["problem"])
	elif total == 0:
		_show_status("Info", Color.TRANSPARENT, "No dialogues yet", "In %s." % folder)
	elif to_update == 0 and not_recorded > 0:
		_show_status("Info", Color.TRANSPARENT, "No dialogue to update", "%d in %s. %d %s record the symbols %s written with: Record Symbols… adds them." % [total, folder, not_recorded, _do_not(not_recorded), _it_was(not_recorded)])
	elif to_update == 0:
		_show_status("StatusSuccess", Style.color("success_color"), "No dialogue to update", "%d in %s." % [total, folder])
	else:
		_show_status("StatusWarning", Style.color("warning_color"), "%d dialogue%s with other symbols" % [to_update, _plural(to_update)],
			"Candy DE will misread %s until %s updated to the project's symbols." % [_them(to_update), _they_are(to_update)])

	if to_select != null:
		to_select.select(0)
		file_tree.scroll_to_item(to_select)
	_show_details()
	_update_button()


#* A dialogue's row - ticked when it has other symbols, dimmed when nothing can be done to it:
#? ticks: the rows ticked before a reload (path -> ticked). Rows not recording their symbols start unticked.
func _add_item(path: String, info: Dictionary, ticks: Dictionary) -> TreeItem:
	var item := file_tree.create_item(file_tree.get_root())
	item.set_metadata(0, path)
	item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	item.set_text(0, path.trim_prefix(folder + "/"))
	item.set_tooltip_text(0, path)
	var status := str(info["status"])
	var updatable := status == SymbolFiles.STATUS_UPDATE
	var tickable := updatable or status == SymbolFiles.STATUS_NOT_STORED
	item.set_editable(0, tickable)
	item.set_checked(0, tickable and bool(ticks.get(path, updatable)))
	match status:
		SymbolFiles.STATUS_UPDATE:
			var count: int = info["differences"].size()
			item.set_text(1, "%d don't match" % count)
			if count == 1:
				item.set_text(1, "1 doesn't match")
			item.set_icon(1, Style.icon("StatusWarning"))
			item.set_tooltip_text(1, "Select it to see which.")
		SymbolFiles.STATUS_MATCH:
			item.set_text(1, "Match")
			item.set_icon(1, Style.icon("StatusSuccess"))
		SymbolFiles.STATUS_NOT_STORED:
			item.set_text(1, "Not recorded")
			item.set_icon(1, Style.icon("NodeInfo"))
		SymbolFiles.STATUS_NOT_CURRENT:
			item.set_text(1, "1.1 format")
			item.set_icon(1, Style.icon("StatusError"))
		_:
			item.set_text(1, "Can't be updated")
			item.set_icon(1, Style.icon("StatusError"))
	if not updatable:
		item.set_tooltip_text(1, str(info["problem"]))
	if not tickable:
		item.set_custom_color(0, Style.dim())
		item.set_custom_color(1, Style.dim())
	return item


func _show_status(icon_name: String, accent: Color, title: String, details: String) -> void:
	status_icon.texture = Style.icon(icon_name)
	status_title.text = title
	status_details.text = details
	status_card.add_theme_stylebox_override("panel", Style.card(accent))


#==============================================================================
#  DETAILS
#==============================================================================

#* The selected dialogue's symbols that differ from the project's, or why there are none to show:
func _show_details() -> void:
	for child in details_grid.get_children():
		details_grid.remove_child(child)
		child.queue_free()
	details_text.clear()
	var item := file_tree.get_selected()
	if item == null:
		details_title.text = "Symbols"
		details_grid.visible = false
		details_text.push_color(Style.dim())
		details_text.add_text("Select a dialogue to see which of its symbols differ from the project's.")
		details_text.pop()
		return
	var path := str(item.get_metadata(0))
	var info: Dictionary = infos.get(path, {})
	details_title.text = path.trim_prefix(folder + "/")
	var differences: Array = info.get("differences", [])
	details_grid.visible = not differences.is_empty()

	if not differences.is_empty():
		_grid_header("Symbol", "")
		_grid_header("In the dialogue", "The symbol the dialogue was written with, as it records it.")
		_grid_header("In the project", "The symbol Candy DE reads: Candy_Properties.gd's, or CandyRef_Shortcuts.gd's for your own CandyRef symbols.")
		for difference in differences:
			details_grid.add_child(Style.label(str(difference["label"])))
			details_grid.add_child(_symbol_label(str(difference["old"])))
			details_grid.add_child(_symbol_label(str(difference["new"])))
		return

	match str(info.get("status", "")):
		SymbolFiles.STATUS_MATCH:
			Style.rich_item(details_text, "StatusSuccess", "Its symbols match the project's: there's nothing to update.")
		_:
			Style.rich_item(details_text, "NodeInfo", Style.escaped(str(info.get("problem", ""))))


func _grid_header(text: String, tooltip: String) -> void:
	var header := Style.label(text, "bold")
	header.add_theme_color_override("font_color", Style.dim())
	header.tooltip_text = tooltip
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	details_grid.add_child(header)


#* A symbol in the code font, or a dimmed "none":
func _symbol_label(symbol: String) -> Label:
	if symbol == "":
		var none := Style.label("none")
		none.add_theme_color_override("font_color", Style.dim())
		return none
	var text := Style.label(symbol, "source", 1.15)
	return text


#==============================================================================
#  UPDATING
#==============================================================================

func _tick_all(ticked: bool) -> void:
	for item in file_tree.get_root().get_children():
		if item.is_editable(0):
			item.set_checked(0, ticked)
	_update_button()


#* The ticked dialogues with this status (SymbolFiles.STATUS_UPDATE or STATUS_NOT_STORED):
func _ticked_paths(status: String = SymbolFiles.STATUS_UPDATE) -> Array:
	var paths: Array = []
	if file_tree.get_root() == null:
		return paths
	for item in file_tree.get_root().get_children():
		var path := str(item.get_metadata(0))
		if item.is_editable(0) and item.is_checked(0) and str(infos.get(path, {}).get("status", "")) == status:
			paths.append(path)
	return paths


func _update_button() -> void:
	var to_update := _ticked_paths().size()
	var to_record := _ticked_paths(SymbolFiles.STATUS_NOT_STORED).size()
	update_button.disabled = busy or to_update == 0 or str(project.get("problem", "")) != ""
	record_button.disabled = busy or to_record == 0
	if to_record == 0:
		count_label.text = "%d to update" % to_update
	else:
		count_label.text = "%d to update, %d to record" % [to_update, to_record]


func _update() -> void:
	var paths := _ticked_paths()
	if paths.is_empty() or busy:
		return
	var question := "Rewrite %d dialogue%s with the project's symbols?\n\nEach is backed up first, beside it, in Conversion Backups/Symbols/<date and time>, with a log of the lines to check." % [paths.size(), _plural(paths.size())]
	if not await _confirm(question, "Update Symbols"):
		return
	busy = true
	_update_button()
	_show_status("Reload", Color.TRANSPARENT, "Updating…", "Backing up and writing the dialogues.")
	await get_tree().process_frame
	project = SymbolFiles.project_symbols()
	results = SymbolFiles.plan_files(paths, project["symbols"])
	SymbolFiles.update_files(results, _wizard_version())
	await Utils.scan_filesystem(get_tree())
	busy = false
	_fill_done()
	refresh()


#==============================================================================
#  RECORDING
#==============================================================================

#* Ask which symbols the ticked dialogues were written with, and write them into them:
func _record() -> void:
	var paths := _ticked_paths(SymbolFiles.STATUS_NOT_STORED)
	if paths.is_empty() or busy:
		return
	var symbols = await _ask_symbols(paths.size())
	if symbols == null:
		return
	busy = true
	_update_button()
	_show_status("Reload", Color.TRANSPARENT, "Recording…", "Backing up and writing the dialogues.")
	await get_tree().process_frame
	results = SymbolFiles.plan_records(paths, symbols)
	SymbolFiles.update_files(results, _wizard_version())
	await Utils.scan_filesystem(get_tree())
	busy = false
	_fill_done()
	refresh()


#* The symbols to record, from a dialog of fields pre-filled with the project's, or null if cancelled:
#? Your own CandyRef symbols are recorded as the project has them.
func _ask_symbols(count: int) -> Variant:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Record Symbols"
	dialog.ok_button_text = "Record Symbols"
	dialog.min_size = Vector2i(Style.px(560), 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Style.px(10))
	dialog.add_child(box)
	var intro := Style.label("Enter the symbols the %d ticked dialogue%s %s written with: the symbols you enter are written into %s, and nothing else in %s changes. The fields start with the project's symbols. If you enter others, %s will then need an update." % [count, _plural(count), _was_were(count), _them(count), _them(count), _they(count)])
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = Style.px(520)
	box.add_child(intro)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Style.px(12))
	grid.add_theme_constant_override("v_separation", Style.px(4))
	box.add_child(grid)
	var edits := {}
	var project_symbols: Dictionary = project.get("symbols", {})
	for symbol in Rules.SYMBOLS:
		var variable: String = symbol["variable"]
		grid.add_child(Style.label(symbol["title"]))
		var edit := LineEdit.new()
		edit.custom_minimum_size.x = Style.px(64)
		edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		edit.add_theme_font_override("font", Style.font("source"))
		edit.select_all_on_focus = true
		edit.text = str(project_symbols.get(variable, symbol["default"]))
		grid.add_child(edit)
		edits[variable] = edit

	var note := Style.caption("Your own CandyRef symbols are recorded as CandyRef_Shortcuts.gd has them.")
	box.add_child(note)
	var problem_label := Style.label("")
	problem_label.add_theme_color_override("font_color", Style.color("error_color"))
	problem_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(problem_label)

	var entered := func() -> Dictionary:
		var values: Dictionary = project_symbols.duplicate(true)
		for variable in edits:
			values[variable] = edits[variable].text.strip_edges()
		return values
	var check := func(_text: String = "") -> void:
		var problem := SymbolUpdater.symbol_problems(entered.call())
		problem_label.text = problem
		problem_label.visible = problem != ""
		dialog.get_ok_button().disabled = problem != ""
	for variable in edits:
		edits[variable].text_changed.connect(check)
	check.call()

	var answer := {"value": -1}
	dialog.confirmed.connect(func() -> void: answer["value"] = 1)
	dialog.canceled.connect(func() -> void: answer["value"] = 0)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	#? The wrapped intro reports a huge height until it has a width: shrink to the content once laid out.
	await get_tree().process_frame
	if is_instance_valid(dialog):
		dialog.reset_size()
		dialog.move_to_center()
	while answer["value"] == -1 and is_instance_valid(dialog):
		await get_tree().process_frame
	var symbols: Variant = null
	if answer["value"] == 1:
		symbols = entered.call()
	if is_instance_valid(dialog):
		dialog.queue_free()
	return symbols


#* Ask in a dialog. Returns whether ok_text's button was pressed:
func _confirm(question: String, ok_text: String) -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Candy Wizard"
	dialog.dialog_text = question
	dialog.dialog_autowrap = true
	dialog.ok_button_text = ok_text
	dialog.min_size = Vector2i(Style.px(520), 0)
	var answer := {"value": -1}
	dialog.confirmed.connect(func() -> void: answer["value"] = 1)
	dialog.canceled.connect(func() -> void: answer["value"] = 0)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	while answer["value"] == -1 and is_instance_valid(dialog):
		await get_tree().process_frame
	if is_instance_valid(dialog):
		dialog.queue_free()
	return answer["value"] == 1


#* The last update - what was updated, what wasn't, and the checks:
func _fill_done() -> void:
	done_text.clear()
	var updated: Array = []
	var failed: Array = []
	var checks := {}
	for result in results:
		if str(result["outcome"]) == SymbolFiles.OUTCOME_UPDATED and str(result["backup"]) != "":
			updated.append(result)
			for note in result["notes"]:
				if str(note["level"]) == SymbolUpdater.LEVEL_CHECK:
					checks[str(note["text"])] = int(checks.get(str(note["text"]), 0)) + 1
		elif str(result["outcome"]) == SymbolFiles.OUTCOME_FAILED:
			failed.append(result)

	var title_icon: TextureRect = done_title.get_parent().get_child(0)
	var done_word := "updated"
	if not results.is_empty() and results[0].get("recorded", false):
		done_word = "given their symbols"
	if updated.is_empty():
		done_title.text = "No dialogue was %s" % done_word
		title_icon.texture = Style.icon("StatusError")
	elif failed.is_empty():
		done_title.text = "%d dialogue%s %s" % [updated.size(), _plural(updated.size()), done_word]
		title_icon.texture = Style.icon("StatusSuccess")
	else:
		done_title.text = "%d dialogue%s %s, %d not" % [updated.size(), _plural(updated.size()), done_word, failed.size()]
		title_icon.texture = Style.icon("StatusWarning")

	for index in min(updated.size(), LISTED_RESULTS):
		var result: Dictionary = updated[index]
		var path := str(result["path"])
		Style.rich_item(done_text, "StatusSuccess", "[url=%s]%s[/url]  %s" % [path, Style.code(path.trim_prefix(folder + "/")), _dim(SymbolFiles.outcome_text(result).trim_prefix("Updated: "))])
	_add_more(updated.size(), LISTED_RESULTS)
	for result in failed:
		Style.rich_item(done_text, "StatusError", "%s  %s" % [Style.code(str(result["path"]).trim_prefix(folder + "/")), Style.colored(Style.escaped(str(result["message"])), "error_color")])

	if not checks.is_empty():
		Style.rich_heading(done_text, "To check")
		var texts := checks.keys()
		texts.sort_custom(func(a, b) -> bool: return checks[a] > checks[b])
		for index in min(texts.size(), LISTED_CHECKS):
			var count: int = checks[texts[index]]
			Style.rich_item(done_text, "StatusWarning", "%s  %s" % [Style.escaped(str(texts[index])), _dim("(%d value%s)" % [count, _plural(count)])])
		_add_more(texts.size(), LISTED_CHECKS)
		Style.rich_item(done_text, "File", _dim("The log lists the line of each."))
	log_button.visible = _log_path() != ""
	done_card.visible = true


#* The last update's log (beside the first backup), or "":
func _log_path() -> String:
	for result in results:
		if str(result.get("backup", "")) != "":
			var path := str(result["backup"]).get_base_dir().path_join(SymbolFiles.LOG_FILE)
			if FileAccess.file_exists(path):
				return path
	return ""


func _open_log() -> void:
	var path := _log_path()
	if path != "":
		OS.shell_open(ProjectSettings.globalize_path(path))


#==============================================================================
#  HELPERS
#==============================================================================

#* Candy Wizard's version, from the dock:
func _wizard_version() -> String:
	var node := get_parent()
	while node != null:
		if "wizard_version" in node:
			return String(node.get("wizard_version"))
		node = node.get_parent()
	return ""


func _add_more(count: int, listed: int) -> void:
	if count > listed:
		Style.rich_item(done_text, "GuiEllipsis", _dim("and %d more" % (count - listed)))


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


func _they(count: int) -> String:
	if count == 1:
		return "it"
	return "they"


func _do_not(count: int) -> String:
	if count == 1:
		return "doesn't"
	return "don't"


func _it_was(count: int) -> String:
	if count == 1:
		return "it was"
	return "they were"


func _was_were(count: int) -> String:
	if count == 1:
		return "was"
	return "were"


func _they_are(count: int) -> String:
	if count == 1:
		return "it's"
	return "they're"
