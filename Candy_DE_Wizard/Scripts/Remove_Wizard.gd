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


const Remover = preload("Remover.gd")

enum Step { BACKUP, SUMMARY, REMOVING, DONE }

const STEP_HEADINGS := {
	Step.BACKUP: "Back up the project",
	Step.SUMMARY: "Ready to remove",
	Step.REMOVING: "Removing Candy DE",
}

#^ Where each step is in the header's list of steps:
const STEP_MARKERS := {
	Step.BACKUP: 0,
	Step.SUMMARY: 1,
	Step.REMOVING: 2,
	Step.DONE: 2,
}

#^ Files the summary names per list before only counting them:
const LISTED_FILES := 15

var record: Dictionary = {}
var remove_succeeded := false
var remover = null

#^ Pages:
var summary_text: RichTextLabel
var done_banner: Dictionary
var done_text: RichTextLabel


func _ready() -> void:
	title = "Remove Candy Dialogue Engine"
	record = Utils.read_record()
	super()
	_show_step(Step.BACKUP)


func _build_pages() -> Dictionary:
	var built := {}
	built[Step.BACKUP] = _build_backup_page("Removing Candy DE deletes the whole Candy_DE folder, your own files in it included (dialogues, media, your settings in User_Data...), and removes its autoloads and input actions from the project settings. You can back up the project first.")
	summary_text = _rich_text()
	built[Step.SUMMARY] = summary_text
	built[Step.REMOVING] = _build_progress_page()
	var done_page := VBoxContainer.new()
	done_page.add_theme_constant_override("separation", Style.px(14))
	done_banner = _build_result_banner(done_page)
	done_text = _rich_text()
	done_page.add_child(done_text)
	built[Step.DONE] = done_page
	return built


func _step_names() -> PackedStringArray:
	return PackedStringArray(["Backup", "Review", "Remove"])


func _subtitle() -> String:
	return "Takes Candy Dialogue Engine out of this project."


#==============================================================================
#  NAVIGATION
#==============================================================================

func _show_step(new_step: int) -> void:
	_show_page(new_step)
	_set_step_marker(STEP_MARKERS[step], step == Step.DONE and remove_succeeded)
	if step == Step.DONE:
		#? The result banner heads the last page.
		heading_label.text = ""
	else:
		heading_label.text = STEP_HEADINGS[step]
	if step == Step.SUMMARY:
		_fill_summary()
	_update_buttons()


func _update_buttons() -> void:
	back_button.visible = step != Step.DONE
	back_button.disabled = busy or step == Step.BACKUP or step == Step.REMOVING
	next_button.disabled = busy or step == Step.REMOVING
	cancel_button.disabled = step == Step.REMOVING
	cancel_button.text = "Cancel"
	next_button.visible = true
	next_button.icon = null
	match step:
		Step.SUMMARY:
			_set_next("Remove", "danger")
			next_button.icon = Style.icon("Remove")
		Step.DONE:
			_set_next("Restart Editor", "primary")
			next_button.icon = Style.icon("Reload")
			next_button.visible = remove_succeeded
			cancel_button.text = "Close"
		_:
			_set_next("Next", "primary")


func _on_back_pressed() -> void:
	error_label.text = ""
	if step == Step.SUMMARY:
		_show_step(Step.BACKUP)


func _on_next_pressed() -> void:
	error_label.text = ""
	match step:
		Step.BACKUP:
			if _check_backup():
				_show_step(Step.SUMMARY)
		Step.SUMMARY:
			_remove()
		Step.DONE:
			_close()
			EditorInterface.restart_editor(true)


func _on_cancel_pressed() -> void:
	if step == Step.REMOVING:
		return
	_close()


#==============================================================================
#  SUMMARY AND REMOVAL
#==============================================================================

func _fill_summary() -> void:
	remover = Remover.new()
	remover.record = record
	remover.plan()

	summary_text.clear()
	var own := Remover.developer_files(record)
	if not own["added"].is_empty() or not own["edited"].is_empty():
		Style.rich_heading(summary_text, "Your own files in Candy_DE are removed too")
		_add_file_items("Added since the install", own["added"])
		_add_file_items("Changed since the install", own["edited"])

	Style.rich_heading(summary_text, "Candy DE %s" % String(record.get("version", "?")))
	Style.rich_item(summary_text, "Remove", "The %s folder goes to the system's trash (or is deleted for good, where the system has none)." % Style.code("res://Candy_DE"))

	Style.rich_heading(summary_text, "Project settings")
	_add_settings_items(summary_text, remover, "will be removed", "will be set back to what it was before the install")
	if not remover.actions_known:
		Style.rich_item(summary_text, "StatusWarning", _colored("This install's record doesn't list the input actions it added (it was made by an older Candy Wizard), so none are removed. Remove them in Project Settings → Input Map if you don't need them.", "warning_color"))

	Style.rich_heading(summary_text, "Backup")
	_add_backup_item(summary_text)


#* The project settings lines, for the summary (what will happen) and the last page (what did):
func _add_settings_items(text: RichTextLabel, from_remover, removed_text: String, restored_text: String) -> void:
	for autoload_name in from_remover.autoloads_removed:
		Style.rich_item(text, "Script", "Autoload %s %s" % [Style.code(autoload_name), removed_text])
	for autoload_name in from_remover.autoloads_restored:
		Style.rich_item(text, "Script", "Autoload %s %s: %s" % [Style.code(autoload_name), restored_text, Style.code(String(from_remover.autoloads_restored[autoload_name]).trim_prefix("*"))])
	for autoload_name in from_remover.autoloads_kept:
		Style.rich_item(text, "Script", "Autoload %s  %s" % [Style.code(autoload_name), _dim("changed since the install: left as it is")])
	for action in from_remover.actions_removed:
		Style.rich_item(text, "InputEventKey", "Input action %s %s" % [Style.code(action), removed_text])


func _add_file_items(heading: String, paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	Style.rich_item(summary_text, "StatusWarning", _colored("%s (%d)" % [heading, paths.size()], "warning_color"))
	for index in min(paths.size(), LISTED_FILES):
		Style.rich_item(summary_text, "File", _dim(_escaped(paths[index])))
	if paths.size() > LISTED_FILES:
		Style.rich_item(summary_text, "GuiEllipsis", _dim("and %d more" % (paths.size() - LISTED_FILES)))


func _dim(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.dim().to_html(false), text]


func _remove() -> void:
	var open := Remover.open_files()
	if not open.is_empty():
		error_label.text = "Close these in the editor first (saving one after the removal would bring it back): " + ", ".join(open)
		return

	busy = true
	_show_step(Step.REMOVING)
	var backup_error: String = await _run_backup("before_removing_Candy_DE_%s" % String(record.get("version", "")))
	if backup_error != "":
		busy = false
		_show_step(Step.SUMMARY)
		error_label.text = "The backup failed, so nothing was removed: " + backup_error
		return

	remover = Remover.new()
	remover.record = record
	remover.progress.connect(_on_work_progress)
	var remove_error: String = await remover.remove(get_tree())
	remove_succeeded = remove_error == ""
	busy = false
	_fill_done(remove_error)
	_show_step(Step.DONE)


func _fill_done(remove_error: String) -> void:
	done_text.clear()
	if remove_error != "":
		_set_result_banner(done_banner, false, "Candy DE wasn't removed", "")
		Style.rich_item(done_text, "StatusError", _colored(_escaped(remove_error), "error_color"))
	else:
		var details := "The Candy_DE folder was deleted."
		if remover.trashed:
			details = "The Candy_DE folder is in the system's trash."
		_set_result_banner(done_banner, true, "Candy DE %s was removed" % String(record.get("version", "?")), details)
		Style.rich_heading(done_text, "Project settings")
		_add_settings_items(done_text, remover, "removed", "set back to what it was before the install")
		Style.rich_heading(done_text, "Next")
		Style.rich_item(done_text, "Reload", "Restart the editor, so Godot forgets Candy DE's classes and autoloads.")
	if backup_path != "":
		Style.rich_heading(done_text, "Backup")
		Style.rich_item(done_text, "Save", Style.code(backup_path))
