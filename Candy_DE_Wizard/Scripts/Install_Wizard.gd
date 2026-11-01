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


const Installer = preload("Installer.gd")

enum Step { SOURCE, NOTES, BACKUP, QUESTIONS, SUMMARY, INSTALLING, DONE }

const STEP_HEADINGS := {
	Step.SOURCE: "Choose the release",
	Step.NOTES: "Before you install",
	Step.BACKUP: "Back up the project",
	Step.QUESTIONS: "Your preferences",
	Step.SUMMARY: "Ready to install",
	Step.INSTALLING: "Installing Candy DE",
}

#^ Where each step is in the header's list of steps:
const STEP_MARKERS := {
	Step.SOURCE: 0,
	Step.NOTES: 1,
	Step.BACKUP: 2,
	Step.QUESTIONS: 3,
	Step.SUMMARY: 4,
	Step.INSTALLING: 5,
	Step.DONE: 5,
}

#^ The last page's advice: [icon, BBCode]:
const FINAL_NOTES := [
	["Reload", "Restart the editor, so Godot registers Candy DE's classes and autoloads."],
	["Edit", "Your settings and data go in [code]Candy_DE/Scripts/User_Data[/code]. Updates never overwrite those files."],
	["Info", "Updates replace every Candy DE engine file. If you've changed one, the update lists it first and lets you abort, back it up, or overwrite it."],
]

var install_succeeded := false
var installer = null

#^ Summary page:
var summary_text: RichTextLabel

#^ Done page:
var done_banner: Dictionary
var done_text: RichTextLabel


func _ready() -> void:
	title = "Install Candy Dialogue Engine"
	super()
	#? Taller for the release page; wider for the header's six steps.
	min_size = Vector2i(Style.px(840), Style.px(720))
	_show_step(Step.SOURCE)
	_start_source()


func _zip_only_prompt() -> String:
	return "Choose the Candy DE release zip to install."


#==============================================================================
#  LAYOUT
#==============================================================================

func _build_pages() -> Dictionary:
	var built := {}
	built[Step.SOURCE] = _build_source_page()
	built[Step.NOTES] = _build_notes_page()
	built[Step.BACKUP] = _build_backup_page("Installing Candy DE adds a Candy_DE folder to the project and changes its settings (autoloads and input actions). You can back up the project first.")
	built[Step.QUESTIONS] = _build_questions_page()
	summary_text = _rich_text()
	built[Step.SUMMARY] = summary_text
	built[Step.INSTALLING] = _build_progress_page()
	var done_page := VBoxContainer.new()
	done_page.add_theme_constant_override("separation", Style.px(14))
	done_banner = _build_result_banner(done_page)
	done_text = _rich_text()
	done_page.add_child(done_text)
	built[Step.DONE] = done_page
	return built


func _step_names() -> PackedStringArray:
	return PackedStringArray(["Release", "Notes", "Backup", "Preferences", "Review", "Install"])


func _subtitle() -> String:
	return "Adds Candy Dialogue Engine to this project."


#==============================================================================
#  NAVIGATION
#==============================================================================

func _show_step(new_step: int) -> void:
	_show_page(new_step)
	_set_step_marker(STEP_MARKERS[step], step == Step.DONE and install_succeeded)
	if step == Step.DONE:
		#? The result banner heads the last page.
		heading_label.text = ""
	else:
		heading_label.text = STEP_HEADINGS[step]
	if step == Step.NOTES:
		heading_label.text = "Before you install Candy DE %s" % package.version()
		_fill_notes_page()
	if step == Step.SUMMARY:
		_fill_summary()
	_update_buttons()


func _update_buttons() -> void:
	back_button.visible = step != Step.DONE
	back_button.disabled = busy or step == Step.SOURCE or step == Step.INSTALLING
	next_button.disabled = busy or not _can_go_next()
	cancel_button.disabled = step == Step.INSTALLING
	cancel_button.text = "Cancel"
	next_button.visible = true
	next_button.icon = null
	match step:
		Step.SUMMARY:
			_set_next("Install", "primary")
			next_button.icon = Style.icon("AssetLib")
		Step.DONE:
			_set_restart_button(install_succeeded)
			cancel_button.text = "Close"
		_:
			_set_next("Next", "primary")


func _can_go_next() -> bool:
	match step:
		Step.SOURCE:
			return _source_chosen()
		Step.INSTALLING:
			return false
	return true


func _on_back_pressed() -> void:
	error_label.text = ""
	match step:
		Step.NOTES:
			_show_step(Step.SOURCE)
		Step.BACKUP:
			if _has_pre_notes():
				_show_step(Step.NOTES)
			else:
				_show_step(Step.SOURCE)
		Step.QUESTIONS:
			_show_step(Step.BACKUP)
		Step.SUMMARY:
			if question_rows.is_empty():
				_show_step(Step.BACKUP)
			else:
				_show_step(Step.QUESTIONS)


func _on_next_pressed() -> void:
	error_label.text = ""
	match step:
		Step.SOURCE:
			if await _prepare_package():
				if _has_pre_notes():
					_show_step(Step.NOTES)
				else:
					_show_step(Step.BACKUP)
		Step.NOTES:
			_show_step(Step.BACKUP)
		Step.BACKUP:
			if _check_backup():
				if question_rows.is_empty():
					_show_step(Step.SUMMARY)
				else:
					_show_step(Step.QUESTIONS)
		Step.QUESTIONS:
			if _check_answers():
				_show_step(Step.SUMMARY)
		Step.SUMMARY:
			_install()
		Step.DONE:
			#? The post notes wait for the restart (Wizard_Dock.gd).
			restarting = true
			_close()
			EditorInterface.restart_editor(true)


func _on_cancel_pressed() -> void:
	if step == Step.INSTALLING:
		return
	_close()


#==============================================================================
#  SUMMARY AND INSTALL
#==============================================================================

func _fill_summary() -> void:
	summary_text.clear()
	_add_existing_autoloads()
	Style.rich_heading(summary_text, "Candy DE %s" % package.version())
	Style.rich_item(summary_text, "File", "From the %s" % _escaped(source_text))
	Style.rich_item(summary_text, "Folder", "%d files, in %s" % [package.files().size(), Style.code("res://Candy_DE")])

	Style.rich_heading(summary_text, "Project settings")
	for entry in package.manifest.get("autoloads", []):
		#? The ones the project already has head the summary (_add_existing_autoloads()).
		if _existing_autoload(entry) == "":
			Style.rich_item(summary_text, "Script", "Autoload %s  %s" % [Style.code(entry["name"]), _dim(_escaped(entry["path"]))])
	for action in package.manifest.get("input_actions", {}):
		if ProjectSettings.has_setting("input/" + String(action)):
			Style.rich_item(summary_text, "InputEventKey", "Input action %s  %s" % [Style.code(action), _dim("already in the project: left as it is")])
		else:
			Style.rich_item(summary_text, "InputEventKey", "Input action %s" % Style.code(action))

	if not question_rows.is_empty():
		Style.rich_heading(summary_text, "Your preferences")
		for row in question_rows:
			Style.rich_item(summary_text, "Edit", "%s: %s" % [_escaped(String(row["question"].get("title", ""))), Style.code(str(_question_value(row)))])

	Style.rich_heading(summary_text, "Backup")
	_add_backup_item(summary_text)


#* An autoload of the release's as the project has it now ("*res://..."), or "" if it doesn't:
func _existing_autoload(entry: Dictionary) -> String:
	return String(ProjectSettings.get_setting("autoload/" + String(entry["name"]), ""))


#* The release's autoloads the project already has, heading the summary:
#? Installing takes them over.
func _add_existing_autoloads() -> void:
	var listed := false
	for entry in package.manifest.get("autoloads", []):
		var existing := _existing_autoload(entry)
		if existing == "":
			continue
		if not listed:
			Style.rich_heading(summary_text, "Your project already has these autoloads")
			listed = true
		if existing == "*" + String(entry["path"]):
			#? Installer.gd records it as the install's (autoloads_adopted).
			Style.rich_item(summary_text, "StatusWarning", "%s  %s" % [Style.code(entry["name"]), _colored("is already set to Candy DE's %s, left by an earlier Candy DE. It becomes this install's: removing Candy DE will remove it too." % _escaped(String(entry["path"]).get_file()), "warning_color")])
		else:
			Style.rich_item(summary_text, "StatusWarning", "%s  %s" % [Style.code(entry["name"]), _colored("is set to %s. It's replaced with Candy DE's %s, and put back if Candy DE is removed." % [_escaped(existing.trim_prefix("*")), _escaped(String(entry["path"]).get_file())], "warning_color")])
	if listed:
		Style.rich_item(summary_text, "Info", _dim("Install to go on, or Cancel to leave the project as it is."))


func _install() -> void:
	busy = true
	_show_step(Step.INSTALLING)

	var backup_error: String = await _run_backup("before_Candy_DE_%s" % package.version())
	if backup_error != "":
		busy = false
		_show_step(Step.SUMMARY)
		error_label.text = "The backup failed, so nothing was installed: " + backup_error
		return

	installer = Installer.new()
	installer.package = package
	installer.answers = _answers()
	installer.source_text = source_text
	installer.wizard_version = wizard_version
	installer.progress.connect(_on_work_progress)
	var install_error: String = await installer.install(get_tree())
	install_succeeded = install_error == ""
	if install_succeeded:
		Utils.set_post_notes_pending(package.wizard_notes("post", _notes_flow()) != "")
		Utils.set_unopened_tools(Utils.TOOLS_TO_OPEN_AFTER_INSTALL)
	busy = false
	_fill_done(install_error)
	_show_step(Step.DONE)
	if install_succeeded:
		_wait_for_imports()


func _fill_done(install_error: String) -> void:
	done_text.clear()
	if install_error != "":
		var details := ""
		if not Utils.candy_de_folder_exists():
			details = "The project was left as it was."
		_set_result_banner(done_banner, false, "Candy DE wasn't installed", details)
		Style.rich_item(done_text, "StatusError", _colored(_escaped(install_error), "error_color"))
	else:
		_set_result_banner(done_banner, true, "Candy DE %s is installed" % package.version(), "In res://Candy_DE, with its autoloads and input actions set up.")
		Style.rich_heading(done_text, "Project settings")
		for autoload_name in installer.autoloads_added:
			Style.rich_item(done_text, "Script", "Autoload %s added" % Style.code(autoload_name))
		for autoload_name in installer.autoloads_replaced:
			Style.rich_item(done_text, "StatusWarning", "Autoload %s replaced" % Style.code(autoload_name))
		for autoload_name in installer.autoloads_adopted:
			Style.rich_item(done_text, "StatusWarning", "Autoload %s  %s" % [Style.code(autoload_name), _dim("already in the project: this install's from now on")])
		for action in installer.actions_added:
			Style.rich_item(done_text, "InputEventKey", "Input action %s added" % Style.code(action))
		for action in installer.actions_kept:
			Style.rich_item(done_text, "InputEventKey", "Input action %s  %s" % [Style.code(action), _dim("already in the project, left as it was")])
		var install_message := String(package.manifest.get("install_message", ""))
		if install_message != "":
			Style.rich_heading(done_text, "From this release")
			Style.rich_item(done_text, "Info", _escaped(install_message))
		Style.rich_heading(done_text, "Before you start")
		for note in FINAL_NOTES:
			Style.rich_item(done_text, note[0], note[1])
	if backup_path != "":
		Style.rich_heading(done_text, "Backup")
		Style.rich_item(done_text, "Save", Style.code(backup_path))
