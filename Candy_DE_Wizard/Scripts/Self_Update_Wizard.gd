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
extends "Release_Wizard.gd"


const SelfUpdater = preload("Self_Updater.gd")

enum Step { SOURCE, REVIEW, UPDATING, DONE }

const STEP_HEADINGS := {
	Step.SOURCE: "Choose the release",
	Step.REVIEW: "Ready to update Candy Wizard",
	Step.UPDATING: "Updating Candy Wizard",
}

#^ Header step index per step:
const STEP_MARKERS := {
	Step.SOURCE: 0,
	Step.REVIEW: 1,
	Step.UPDATING: 2,
	Step.DONE: 2,
}

#^ Seconds before restarting:
const RESTART_DELAY := 2.5
#^ Paths listed before only counting:
const LISTED_FILES := 8

var updater = null
var update_succeeded := false
#^ Off in tests only:
var restart_after_update := true

#^ Pages:
var review_text: RichTextLabel
var done_banner: Dictionary
var done_text: RichTextLabel


func _ready() -> void:
	title = "Update Candy Wizard"
	super()
	#? Install wizard's height, for the release page:
	min_size = Vector2i(Style.px(760), Style.px(720))
	_show_step(Step.SOURCE)
	_start_source()


func _uses_wizard_releases() -> bool:
	return true


func _release_problem(version: String) -> String:
	var comparison := Utils.compare_versions(version, wizard_version)
	if comparison == 0:
		return "Candy Wizard %s is installed already: it's up to date." % wizard_version
	if comparison < 0:
		return "Candy Wizard %s is installed, which is newer than this release (%s)." % [wizard_version, version]
	return ""


#==============================================================================
#  LAYOUT
#==============================================================================

func _build_pages() -> Dictionary:
	var built := {}
	built[Step.SOURCE] = _build_source_page()
	review_text = _rich_text()
	built[Step.REVIEW] = review_text
	built[Step.UPDATING] = _build_progress_page()
	var done_page := VBoxContainer.new()
	done_page.add_theme_constant_override("separation", Style.px(14))
	done_banner = _build_result_banner(done_page)
	done_text = _rich_text()
	done_page.add_child(done_text)
	built[Step.DONE] = done_page
	return built


func _step_names() -> PackedStringArray:
	return PackedStringArray(["Release", "Review", "Update"])


func _subtitle() -> String:
	return "Brings Candy Wizard %s up to date. Your project isn't touched." % wizard_version


#==============================================================================
#  NAVIGATION
#==============================================================================

func _show_step(new_step: int) -> void:
	_show_page(new_step)
	_set_step_marker(STEP_MARKERS[step], step == Step.DONE and update_succeeded)
	if step == Step.DONE:
		heading_label.text = ""
	else:
		heading_label.text = STEP_HEADINGS[step]
	if step == Step.REVIEW:
		_fill_review()
	_update_buttons()


func _update_buttons() -> void:
	back_button.visible = step != Step.DONE
	back_button.disabled = busy or step != Step.REVIEW
	next_button.disabled = busy or not _can_go_next()
	cancel_button.disabled = step == Step.UPDATING or (step == Step.DONE and update_succeeded)
	cancel_button.text = "Cancel"
	next_button.visible = true
	next_button.icon = null
	match step:
		Step.REVIEW:
			_set_next("Update Candy Wizard", "primary")
			next_button.icon = Style.icon("Reload")
		Step.DONE:
			_set_next("Restart Now", "primary")
			next_button.icon = Style.icon("Reload")
			next_button.visible = update_succeeded
			cancel_button.text = "Close"
		_:
			_set_next("Next", "primary")


func _can_go_next() -> bool:
	match step:
		Step.SOURCE:
			return _source_chosen()
		Step.REVIEW:
			return updater != null and updater.problem == ""
		Step.UPDATING:
			return false
	return true


func _on_back_pressed() -> void:
	error_label.text = ""
	if step == Step.REVIEW:
		_show_step(Step.SOURCE)


func _on_next_pressed() -> void:
	error_label.text = ""
	match step:
		Step.SOURCE:
			if await _prepare_package():
				_show_step(Step.REVIEW)
		Step.REVIEW:
			_update()
		Step.DONE:
			_restart()


func _on_cancel_pressed() -> void:
	if step == Step.UPDATING:
		return
	if step == Step.DONE and update_succeeded:
		#? Old code on new files: only a restart is safe.
		_restart()
		return
	_close()


#==============================================================================
#  REVIEW AND UPDATE
#==============================================================================

func _fill_review() -> void:
	updater = SelfUpdater.new()
	updater.package = package
	updater.wizard_version = wizard_version
	updater.plan()
	review_text.clear()
	if updater.problem != "":
		Style.rich_item(review_text, "StatusError", _colored(_escaped(updater.problem), "error_color"))
		return
	Style.rich_heading(review_text, "Candy Wizard %s → %s" % [wizard_version, package.version()])
	Style.rich_item(review_text, "Folder", "In %s" % Style.code(updater.folder))
	_add_files("Reload", "Updated", updater.changed)
	_add_files("Add", "Added", updater.added)
	_add_files("Remove", "Removed", updater.removed)
	if updater.changed.is_empty() and updater.added.is_empty() and updater.removed.is_empty():
		Style.rich_item(review_text, "StatusSuccess", _dim("Candy Wizard's files are already this release's."))

	Style.rich_heading(review_text, "What happens")
	Style.rich_item(review_text, "Save", "Candy Wizard as it is now is copied first, to %s." % Style.code("user://candy_wizard/wizard_backups"))
	Style.rich_item(review_text, "Reload", "Then the editor restarts, to load the new version (your open scenes are saved first).")
	Style.rich_item(review_text, "StatusSuccess", "Candy DE and the rest of your project aren't changed. Candy Wizard keeps its records in %s, which stays." % Style.code("Candy_DE/.Install"))


func _add_files(icon_name: String, heading: String, paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	Style.rich_item(review_text, icon_name, "%s (%d)" % [heading, paths.size()])
	review_text.push_indent(1)
	for index in mini(paths.size(), LISTED_FILES):
		review_text.append_text(_dim(_escaped(paths[index])))
		review_text.newline()
	if paths.size() > LISTED_FILES:
		review_text.append_text(_dim("and %d more" % (paths.size() - LISTED_FILES)))
		review_text.newline()
	review_text.pop()


func _update() -> void:
	busy = true
	_show_step(Step.UPDATING)
	updater.progress.connect(_on_work_progress)
	var update_error: String = await updater.update(get_tree())
	update_succeeded = update_error == ""
	busy = false
	done_text.clear()
	if update_succeeded:
		_set_result_banner(done_banner, true, "Candy Wizard %s is installed" % package.version(), "The editor restarts in a moment, to load it.")
		Style.rich_item(done_text, "Save", "The previous version, %s, is in %s." % [wizard_version, Style.code(ProjectSettings.globalize_path(updater.backup_folder))])
	else:
		_set_result_banner(done_banner, false, "Candy Wizard wasn't updated", "")
		Style.rich_item(done_text, "StatusError", _colored(_escaped(update_error), "error_color"))
	_show_step(Step.DONE)
	if update_succeeded and restart_after_update:
		await get_tree().create_timer(RESTART_DELAY).timeout
		_restart()


func _restart() -> void:
	if not restart_after_update:
		return
	_close()
	EditorInterface.restart_editor(true)
