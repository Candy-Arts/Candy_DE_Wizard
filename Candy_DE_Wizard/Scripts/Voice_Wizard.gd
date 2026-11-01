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


const VoiceFiles = preload("Voice_Files.gd")

enum Step { BACKUP, REVIEW, MOVING, DONE }

const STEP_HEADINGS := {
	Step.BACKUP: "Back up the project",
	Step.REVIEW: "Where the voice files go",
	Step.MOVING: "Moving the voice files",
}

#^ Header step index per step:
const STEP_MARKERS := {
	Step.BACKUP: 0,
	Step.REVIEW: 1,
	Step.MOVING: 2,
	Step.DONE: 2,
}

#^ Files listed per list before only counting:
const LISTED_FILES := 15

var to_layout := {}				#/ The layout Candy_Properties.gd sets
var gathered := {}				#/ VoiceFiles.spoken_lines(), read once
var move_plan := {}
var voice_files = null			#/ Voice_Files.gd, once moving
var move_succeeded := false

#^ Pages:
var from_folder_edit: LineEdit
var from_path_edit: LineEdit
var from_note: Label
var summary_text: RichTextLabel
var done_banner: Dictionary
var done_text: RichTextLabel


func _ready() -> void:
	title = "Move Voice Files"
	to_layout = VoiceFiles.current_layout()
	super()
	#? Wider, for long paths:
	min_size = Vector2i(Style.px(940), Style.px(640))
	var from_layout := VoiceFiles.recorded_layout()
	if from_layout.is_empty():
		from_layout = to_layout
		from_note.text = "Candy Wizard has no record of how they're arranged, so these are Candy_Properties.gd's settings. If you've changed voice_folder or voice_path since the files were arranged, write the old values here."
	else:
		from_note.text = "As Candy Wizard last arranged them. Correct it if they were arranged by hand since. The other column is what Candy_Properties.gd sets."
	if not from_layout.is_empty():
		from_folder_edit.text = from_layout["voice_folder"]
		from_path_edit.text = from_layout["voice_path"]
	_show_step(Step.BACKUP)


func _build_pages() -> Dictionary:
	var built := {}
	built[Step.BACKUP] = _build_backup_page("Moving voice files changes where your own files are: each file a dialogue line uses goes where voice_folder and voice_path (Candy_Properties.gd) now say. Files no line uses stay where they are, and no file is ever deleted. You can back up the project first.")
	built[Step.REVIEW] = _build_review_page()
	built[Step.MOVING] = _build_progress_page()
	var done_page := VBoxContainer.new()
	done_page.add_theme_constant_override("separation", Style.px(14))
	done_banner = _build_result_banner(done_page)
	done_text = _rich_text()
	done_page.add_child(done_text)
	built[Step.DONE] = done_page
	return built


func _step_names() -> PackedStringArray:
	return PackedStringArray(["Backup", "Review", "Move"])


func _subtitle() -> String:
	return "Arranges the voice files as voice_path says."


#* Review page - current (editable) and new layouts, then the summary:
func _build_review_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Style.px(12))
	var box := Style.card_box(page)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Style.px(12))
	grid.add_theme_constant_override("v_separation", Style.px(6))
	box.add_child(grid)
	grid.add_child(Control.new())
	grid.add_child(_column_title("Folder", "Arranged now as"))
	grid.add_child(_column_title("FolderCreate", "Will be arranged as"))

	from_folder_edit = _layout_row(grid, "voice_folder")
	from_path_edit = _layout_row(grid, "voice_path")
	from_note = Style.caption("")
	box.add_child(from_note)

	summary_text = _rich_text()
	page.add_child(summary_text)
	return page


func _column_title(icon_name: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(6))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(Style.icon_rect(Style.icon(icon_name), 16))
	row.add_child(Style.label(text, "bold"))
	return row


#* Layout row (name, current value field, Candy_Properties.gd's value). Returns the field:
func _layout_row(grid: GridContainer, variable: String) -> LineEdit:
	grid.add_child(Style.label(variable))
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.x = Style.px(200)
	edit.add_theme_font_override("font", Style.font("source"))
	edit.text_changed.connect(func(_text: String) -> void: _fill_summary())
	grid.add_child(edit)
	var value := Style.label(str(to_layout.get(variable, "?")), "source")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.custom_minimum_size.x = Style.px(200)
	value.clip_text = true
	value.tooltip_text = "Set in Candy_Properties.gd."
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(value)
	return edit


#==============================================================================
#  NAVIGATION
#==============================================================================

func _show_step(new_step: int) -> void:
	_show_page(new_step)
	_set_step_marker(STEP_MARKERS[step], step == Step.DONE and move_succeeded)
	if step == Step.DONE:
		heading_label.text = ""
	else:
		heading_label.text = STEP_HEADINGS[step]
	if step == Step.REVIEW:
		#? Read the dialogues once; the plan follows the fields:
		gathered = VoiceFiles.spoken_lines()
		_fill_summary()
	_update_buttons()


func _update_buttons() -> void:
	back_button.visible = step != Step.DONE
	back_button.disabled = busy or step == Step.BACKUP or step == Step.MOVING
	next_button.disabled = busy or step == Step.MOVING
	cancel_button.disabled = step == Step.MOVING
	cancel_button.text = "Cancel"
	next_button.visible = true
	next_button.icon = null
	match step:
		Step.REVIEW:
			var count := _move_count()
			if count > 0:
				_set_next("Move %d File%s" % [count, _plural(count)], "primary")
				next_button.icon = Style.icon("ToolMove")
			else:
				_set_next("Finish", "primary")
			next_button.disabled = move_plan.is_empty() or not move_plan["problems"].is_empty()
		Step.DONE:
			next_button.visible = false
			cancel_button.text = "Close"
		_:
			_set_next("Next", "primary")


func _on_back_pressed() -> void:
	error_label.text = ""
	if step == Step.REVIEW:
		_show_step(Step.BACKUP)


func _on_next_pressed() -> void:
	error_label.text = ""
	match step:
		Step.BACKUP:
			if _check_backup():
				_show_step(Step.REVIEW)
		Step.REVIEW:
			_move()


func _on_cancel_pressed() -> void:
	if step == Step.MOVING:
		return
	_close()


#==============================================================================
#  SUMMARY
#==============================================================================

func _from_layout() -> Dictionary:
	return {"voice_folder": from_folder_edit.text.strip_edges(), "voice_path": from_path_edit.text.strip_edges()}


func _move_count() -> int:
	if move_plan.is_empty():
		return 0
	return move_plan["moves"].size()


#* Plan the move from the fields and show it:
func _fill_summary() -> void:
	summary_text.clear()
	move_plan = {}
	if to_layout.is_empty():
		Style.rich_item(summary_text, "StatusError", _colored("Candy_Properties.gd has no voice_folder or voice_path with a plain value.", "error_color"))
		_update_buttons()
		return
	if gathered.is_empty():
		_update_buttons()
		return
	move_plan = VoiceFiles.plan(_from_layout(), to_layout, gathered)
	var from_folder: String = move_plan["voice_folder"]
	var to_folder := String(to_layout["voice_folder"]).trim_suffix("/")

	for problem in move_plan["problems"]:
		Style.rich_item(summary_text, "StatusError", _colored(_escaped(problem), "error_color"))
	if not move_plan["problems"].is_empty():
		_update_buttons()
		return

	var moves: Array = move_plan["moves"]
	if moves.is_empty():
		Style.rich_heading(summary_text, "Nothing to move")
		if move_plan["blocked"].is_empty():
			Style.rich_item(summary_text, "StatusSuccess", "Every voice file is where its lines look for it. Finish to have Candy Wizard remember that the files follow voice_path.")
	else:
		Style.rich_heading(summary_text, "To move (%d)" % moves.size())
		if from_folder != to_folder:
			Style.rich_item(summary_text, "Folder", _dim("From %s to %s" % [Style.code(from_folder), Style.code(to_folder)]))
		for index in min(moves.size(), LISTED_FILES):
			var entry: Dictionary = moves[index]
			var targets := PackedStringArray()
			for target in entry["to"]:
				targets.append(Style.code(_relative(target, to_folder)))
			var text := "%s  →  %s" % [Style.code(_relative(entry["from"], from_folder)), ",  ".join(targets)]
			if entry["keep"]:
				text += "  " + _dim("(copied: other lines still use it where it is)")
			elif entry["to"].size() > 1:
				text += "  " + _dim("(copied: lines in each place use it)")
			Style.rich_item(summary_text, "ArrowRight", text)
		_add_more(moves.size())

	var blocked: Array = move_plan["blocked"]
	var unused: PackedStringArray = move_plan["unused"]
	if not blocked.is_empty() or not unused.is_empty():
		Style.rich_heading(summary_text, "Left where they are")
		for index in min(blocked.size(), LISTED_FILES):
			var entry: Dictionary = blocked[index]
			Style.rich_item(summary_text, "StatusWarning", "%s  %s" % [Style.code(_relative(entry["from"], from_folder)), _colored(_escaped(entry["reason"]) + ".", "warning_color")])
		_add_more(blocked.size())
		if not unused.is_empty():
			Style.rich_item(summary_text, "File", "%d file%s no line uses:" % [unused.size(), _plural(unused.size())])
			for index in min(unused.size(), LISTED_FILES):
				Style.rich_item(summary_text, "File", _dim(_escaped(_relative(unused[index], from_folder))))
			_add_more(unused.size())

	Style.rich_heading(summary_text, "Also")
	if move_plan["in_place"] > 0:
		Style.rich_item(summary_text, "StatusSuccess", _dim("%d file%s already where %s lines look for %s." % [move_plan["in_place"], _plural(move_plan["in_place"]), _their(move_plan["in_place"]), _them(move_plan["in_place"])]))
	if move_plan["missing"] > 0:
		Style.rich_item(summary_text, "Info", _dim("%d voice file%s the lines look for %s recorded yet." % [move_plan["missing"], _plural(move_plan["missing"]), _is_not(move_plan["missing"])]))
	if move_plan["placed_by_game"] > 0:
		Style.rich_item(summary_text, "Info", _dim(_escaped(VoiceFiles.placed_by_game_text(move_plan["placed_by_game"]))))
	if move_plan["named_by_game"] > 0:
		Style.rich_item(summary_text, "Info", _dim("Left out: %d spoken line%s naming %s voice file with an expression, which the game decides." % [move_plan["named_by_game"], _plural(move_plan["named_by_game"]), _their(move_plan["named_by_game"])]))
	Style.rich_item(summary_text, "Remove", _dim("Folders the move leaves empty are removed."))
	if not blocked.is_empty():
		Style.rich_item(summary_text, "StatusWarning", _colored("While files are left in the way, Candy Wizard still counts the voice files as arranged the old way: sort those out, then move again.", "warning_color"))

	Style.rich_heading(summary_text, "Backup")
	_add_backup_item(summary_text)
	_update_buttons()


func _add_more(count: int) -> void:
	if count > LISTED_FILES:
		Style.rich_item(summary_text, "GuiEllipsis", _dim("and %d more" % (count - LISTED_FILES)))


#* Path relative to a voice folder:
func _relative(path: String, folder: String) -> String:
	return path.trim_prefix(folder + "/")


#==============================================================================
#  MOVING
#==============================================================================

func _move() -> void:
	if move_plan.is_empty() or not move_plan["problems"].is_empty():
		return
	busy = true
	_show_step(Step.MOVING)
	var backup_error: String = await _run_backup("before_moving_voice_files")
	if backup_error != "":
		busy = false
		_show_step(Step.REVIEW)
		error_label.text = "The backup failed, so nothing was moved: " + backup_error
		return

	voice_files = VoiceFiles.new()
	voice_files.progress.connect(_on_work_progress)
	var move_error: String = await voice_files.move(move_plan, to_layout, get_tree())
	move_succeeded = move_error == "" and voice_files.failed.is_empty()
	busy = false
	_fill_done(move_error)
	_show_step(Step.DONE)


func _fill_done(move_error: String) -> void:
	done_text.clear()
	var details := "%d moved, %d copied, %d empty folder%s removed." % [voice_files.moved.size(), voice_files.copied.size(), voice_files.folders_removed, _plural(voice_files.folders_removed)]
	if not move_succeeded:
		_set_result_banner(done_banner, false, "Some voice files couldn't be moved", details)
	elif voice_files.layout_recorded:
		_set_result_banner(done_banner, true, "The voice files follow voice_path", details)
	else:
		_set_result_banner(done_banner, true, "Voice files moved, but some were in the way", details)
		done_banner["icon"].texture = Style.icon("StatusWarning")
	if move_error != "":
		Style.rich_item(done_text, "StatusError", _colored(_escaped(move_error), "error_color"))
	for problem in voice_files.failed:
		Style.rich_item(done_text, "StatusError", _colored(_escaped(problem), "error_color"))
	if voice_files.layout_recorded:
		Style.rich_item(done_text, "StatusSuccess", "Candy Wizard will remember that the files follow %s." % Style.code(to_layout["voice_path"]))
	else:
		Style.rich_item(done_text, "StatusWarning", _colored("Candy Wizard still counts the voice files as arranged the old way, since these were left where they are. Sort them out, then move again: only the files still in the old places move.", "warning_color"))
		var from_folder: String = move_plan["voice_folder"]
		var blocked: Array = move_plan["blocked"]
		for index in min(blocked.size(), LISTED_FILES):
			var entry: Dictionary = blocked[index]
			Style.rich_item(done_text, "File", "%s  %s" % [Style.code(_relative(entry["from"], from_folder)), _dim(_escaped(entry["reason"]) + ".")])
		if blocked.size() > LISTED_FILES:
			Style.rich_item(done_text, "GuiEllipsis", _dim("and %d more" % (blocked.size() - LISTED_FILES)))
	if backup_path != "":
		Style.rich_heading(done_text, "Backup")
		Style.rich_item(done_text, "Save", Style.code(backup_path))


#==============================================================================
#  TEXT
#==============================================================================

func _dim(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.dim().to_html(false), text]


func _plural(count: int) -> String:
	if count == 1:
		return ""
	return "s"


func _their(count: int) -> String:
	if count == 1:
		return "its"
	return "their"


func _them(count: int) -> String:
	if count == 1:
		return "it"
	return "them"


func _is_not(count: int) -> String:
	if count == 1:
		return "isn't"
	return "aren't"
