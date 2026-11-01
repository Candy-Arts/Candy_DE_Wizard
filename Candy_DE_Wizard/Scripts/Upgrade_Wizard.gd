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


const Upgrader = preload("Upgrader.gd")
const UpgradeData = preload("Upgrade_Data.gd")
const ReportWindow = preload("Report_Window.gd")

enum Step { SOURCE, NOTES, BACKUP, REVIEW, UPGRADING, DONE }

const STEP_HEADINGS := {
	Step.SOURCE: "Choose release %s" % Upgrader.TO_VERSION,
	Step.NOTES: "Before you upgrade",
	Step.BACKUP: "Back up the project",
	Step.REVIEW: "Ready to upgrade",
	Step.UPGRADING: "Upgrading Candy DE",
}

#^ Where each step is in the header's list of steps:
const STEP_MARKERS := {
	Step.SOURCE: 0,
	Step.NOTES: 1,
	Step.BACKUP: 2,
	Step.REVIEW: 3,
	Step.UPGRADING: 4,
	Step.DONE: 4,
}

#^ How many paths a list names before only counting them:
const LISTED_FILES := 8

var install_folder := ""				#/ The 1.1.3 install folder
var upgrader = null
var upgrade_succeeded := false

#^ Review page:
var review_text: RichTextLabel

#^ Done page:
var done_banner: Dictionary
var done_text: RichTextLabel
var open_report_button: Button
var report_window: Window = null
var open_copy_button: Button


func _ready() -> void:
	title = "Upgrade Candy Dialogue Engine"
	install_folder = Upgrader.find_install()
	super()
	#? As big as the install and update wizards:
	min_size = Vector2i(Style.px(840), Style.px(720))
	_show_step(Step.SOURCE)
	_start_source()


func _wanted_version() -> String:
	return Upgrader.TO_VERSION


#? An upgrade from 1.1.3 shows the update notes.
func _notes_flow() -> String:
	return Utils.NOTES_UPDATE


#* Candy DE isn't upgraded while GitHub has a newer Candy Wizard:
#? Its upgrade may be better.
func _blocking_problem() -> String:
	var newer_wizard := Utils.newer_wizard_version(wizard_version)
	if newer_wizard != "":
		return "Update Candy Wizard to %s first (the button beside its version, in the dock): Candy DE is only upgraded with the latest Candy Wizard." % newer_wizard
	return ""


#* No questions - the one 1.2.0 asks (voice_path) is answered with 1.1.3's layout:
func _questions_to_ask() -> Array:
	return []


func _zip_only_prompt() -> String:
	return "Choose the Candy DE %s release zip to upgrade to." % Upgrader.TO_VERSION


#* The report's window, one at a time:
func _show_report() -> void:
	if report_window != null and is_instance_valid(report_window):
		report_window.grab_focus()
		return
	report_window = ReportWindow.new()
	report_window.wizard_version = wizard_version
	EditorInterface.get_base_control().add_child(report_window)
	report_window.popup_centered(report_window.min_size)


#==============================================================================
#  LAYOUT
#==============================================================================

func _build_pages() -> Dictionary:
	var built := {}
	built[Step.SOURCE] = _build_source_page()
	built[Step.NOTES] = _build_notes_page()
	built[Step.BACKUP] = _build_backup_page("The upgrade sets Candy DE %s aside, installs %s, and moves and converts your settings, data and media into it. It also changes the project settings, and files in your custom folders. A backup is required: it's the way back once you've worked on the upgraded project." % [Upgrader.FROM_VERSION, Upgrader.TO_VERSION])
	#? Required: the box stays ticked.
	backup_check.disabled = true
	backup_check.text = "Back up the project first (required)"
	var review_page := VBoxContainer.new()
	review_text = _rich_text()
	review_page.add_child(review_text)
	built[Step.REVIEW] = review_page
	built[Step.UPGRADING] = _build_progress_page()
	var done_page := VBoxContainer.new()
	done_page.add_theme_constant_override("separation", Style.px(14))
	done_banner = _build_result_banner(done_page)
	done_text = _rich_text()
	done_page.add_child(done_text)
	var done_buttons := HBoxContainer.new()
	done_buttons.add_theme_constant_override("separation", Style.px(8))
	done_page.add_child(done_buttons)
	open_report_button = Style.button("Open the Report", "File", _show_report)
	open_report_button.visible = false
	done_buttons.add_child(open_report_button)
	#? Godot ignores the copy: open it in the system's file manager.
	open_copy_button = Style.button("Open the %s Copy" % Upgrader.FROM_VERSION, "Folder", func() -> void: OS.shell_open(ProjectSettings.globalize_path(Upgrader.ASIDE_FOLDER)))
	open_copy_button.visible = false
	done_buttons.add_child(open_copy_button)
	built[Step.DONE] = done_page
	return built


func _step_names() -> PackedStringArray:
	return PackedStringArray(["Release", "Notes", "Backup", "Review", "Upgrade"])


func _subtitle() -> String:
	return "Brings Candy Dialogue Engine %s, installed by hand, to %s, with your settings, data and media." % [Upgrader.FROM_VERSION, Upgrader.TO_VERSION.trim_suffix(".0")]


#==============================================================================
#  NAVIGATION
#==============================================================================

func _show_step(new_step: int) -> void:
	_show_page(new_step)
	_set_step_marker(STEP_MARKERS[step], step == Step.DONE and upgrade_succeeded)
	if step == Step.DONE:
		#? The result banner heads the last page.
		heading_label.text = ""
	else:
		heading_label.text = STEP_HEADINGS[step]
	if step == Step.NOTES:
		heading_label.text = "Before you upgrade to Candy DE %s" % package.version()
		_fill_notes_page()
	if step == Step.REVIEW:
		_plan()
	_update_buttons()


func _update_buttons() -> void:
	back_button.visible = step != Step.DONE
	back_button.disabled = busy or step == Step.SOURCE or step == Step.UPGRADING
	next_button.disabled = busy or not _can_go_next()
	cancel_button.disabled = step == Step.UPGRADING
	cancel_button.text = "Cancel"
	next_button.visible = true
	next_button.icon = null
	match step:
		Step.REVIEW:
			_set_next("Upgrade", "primary")
			next_button.icon = Style.icon("Reload")
		Step.DONE:
			_set_restart_button(upgrade_succeeded)
			cancel_button.text = "Close"
		_:
			_set_next("Next", "primary")


func _can_go_next() -> bool:
	match step:
		Step.SOURCE:
			return _source_chosen()
		Step.REVIEW:
			return upgrader != null and upgrader.problem == ""
		Step.UPGRADING:
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
		Step.REVIEW:
			_show_step(Step.BACKUP)


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
				_show_step(Step.REVIEW)
		Step.REVIEW:
			_upgrade()
		Step.DONE:
			#? The post notes wait for the restart (Wizard_Dock.gd).
			restarting = true
			_close()
			EditorInterface.restart_editor(true)


func _on_cancel_pressed() -> void:
	if step == Step.UPGRADING:
		return
	_close()


#==============================================================================
#  REVIEW
#==============================================================================

#* Works out the upgrade (nothing is changed), then shows it:
func _plan() -> void:
	upgrader = Upgrader.new()
	upgrader.package = package
	upgrader.install_folder = install_folder
	upgrader.source_text = source_text
	upgrader.wizard_version = wizard_version
	upgrader.plan()
	_fill_review()


func _fill_review() -> void:
	review_text.clear()
	if upgrader.problem != "":
		Style.rich_item(review_text, "StatusError", _colored(_escaped(upgrader.problem), "error_color"))
		_update_buttons()
		return
	Style.rich_heading(review_text, "Candy DE %s → %s" % [Upgrader.FROM_VERSION, package.version()])
	Style.rich_item(review_text, "Save", "Candy DE %s, in %s, is set aside in %s, without the files brought back below (moved, not copied). Godot ignores it." % [Upgrader.FROM_VERSION, Style.code(install_folder), Style.code(Upgrader.ASIDE_FOLDER)])
	Style.rich_item(review_text, "AssetLib", "Candy DE %s is installed in %s." % [package.version(), Style.code(Utils.CANDY_DE_FOLDER)])

	Style.rich_heading(review_text, "Brought into %s" % package.version().trim_suffix(".0"))
	var converted: PackedStringArray = []
	for entry in upgrader.files_with(Upgrader.CONVERTED):
		converted.append(Style.code(String(entry["path"]).get_file()))
	Style.rich_item(review_text, "Edit", "Your settings and data, converted: %s. %s" % [", ".join(converted), _dim("%d script(s) written." % upgrader.data_writes.size())])
	_add_moved_files(review_text)
	_add_folder_changes(review_text)
	_add_custom_folders(review_text)

	Style.rich_heading(review_text, "Kept in the %s copy" % Upgrader.FROM_VERSION)
	Style.rich_item(review_text, "PackedScene", "%s starts with only its own scenes and scripts, which work as they are. Yours stay in the %s copy: move back what you need by hand. The report lists them, and what to know." % [package.version(), Upgrader.FROM_VERSION])
	var left: Array = upgrader.files_with(Upgrader.LEFT) + upgrader.files_with(Upgrader.CODE)
	if not left.is_empty():
		Style.rich_item(review_text, "File", "Your scenes, scripts and other files of the Scenes and Scripts folders, and the %s ones you changed (%d):" % [Upgrader.FROM_VERSION, left.size()])
		_add_paths(review_text, left.map(func(entry: Dictionary) -> String: return String(entry["path"]).trim_prefix(install_folder + "/")))
	Style.rich_item(review_text, "File", _dim("%d file(s) of Candy DE %s you didn't change: %s has its own." % [upgrader.unchanged, Upgrader.FROM_VERSION, package.version()]))

	Style.rich_heading(review_text, "For you to do afterwards")
	var to_do := false
	var dialogues := _moved_count("dialogues_folder")
	if dialogues > 0:
		Style.rich_item(review_text, "StatusWarning", "Convert your %d dialogue(s) once upgraded, with the Dialogue Converter tool: they're moved as they are, and 1.2 reads 1.1.3 dialogues differently." % dialogues)
		to_do = true
	if not left.is_empty():
		Style.rich_item(review_text, "StatusWarning", "Move back the scenes and scripts you need, from the %s copy." % Upgrader.FROM_VERSION)
		to_do = true
	for entry in upgrader.folders:
		if entry.get("reset", false):
			Style.rich_item(review_text, "StatusWarning", "%s pointed at %s, whose scenes stay in the %s copy: it's %s's %s now. Set it again once you've moved them back." % [Style.code(entry["setting"]), Style.code(entry["from"]), Upgrader.FROM_VERSION, package.version(), Style.code(entry["to"])])
			to_do = true
	for entry in upgrader.code_changes:
		var counts: PackedStringArray = []
		for kind in ["changed", "added", "removed"]:
			if not entry[kind].is_empty():
				counts.append("%d %s" % [entry[kind].size(), kind])
		if entry["rest_changed"]:
			counts.append("changes outside functions")
		Style.rich_item(review_text, "StatusWarning", "Redo your changes to %s in 1.2: %s. The report lists the functions." % [Style.code(String(entry["path"]).get_file()), ", ".join(counts)])
		to_do = true
	for note in upgrader.notes:
		if note["level"] == UpgradeData.CHECK:
			Style.rich_item(review_text, "StatusWarning", _escaped(String(note["text"])))
			to_do = true
	if not upgrader.code_findings.is_empty():
		var lines := 0
		var scanned_files := {}
		for finding in upgrader.code_findings:
			lines += finding["hits"].size()
			for hit in finding["hits"]:
				scanned_files[hit["path"]] = true
		Style.rich_item(review_text, "StatusWarning", "Update your code and scenes: %d line(s) in %d file(s) use names, keys or values that %s renamed, removed or reads differently. The report lists them, with what to write instead." % [lines, scanned_files.size(), package.version()])
		to_do = true
	var settings := 0
	for entry in upgrader.own_settings + upgrader.replaced_settings:
		for node in entry["nodes"]:
			settings += node["items"].size()
	if settings > 0:
		Style.rich_item(review_text, "StatusWarning", "Check your engine and UI element settings: %d setting(s) of your scenes, or of the %s scenes %s's replace, are renamed, removed or get another value. The report lists them, with what to set to keep %s's behaviour." % [settings, Upgrader.FROM_VERSION, package.version(), Upgrader.FROM_VERSION])
		to_do = true
	var clashes: Array = upgrader.files_with(Upgrader.CLASH)
	for entry in upgrader.custom_changes:
		if entry["status"] == Upgrader.CLASH:
			clashes.append(entry)
	if not clashes.is_empty():
		Style.rich_item(review_text, "StatusWarning", "%d file(s) can't be brought back: something else is in their place. They stay where they are." % clashes.size())
		_add_paths(review_text, clashes.map(func(entry: Dictionary) -> String: return String(entry.get("path", entry.get("from", ""))).trim_prefix(install_folder + "/")))
		to_do = true
	if not to_do:
		Style.rich_item(review_text, "StatusSuccess", _dim("Nothing: everything is carried over."))

	Style.rich_heading(review_text, "Project settings")
	Style.rich_item(review_text, "Tools", "The %s autoload points to %s's engine, and %s's input actions are added where missing." % [Style.code("candy_de"), package.version(), package.version()])

	Style.rich_heading(review_text, "Backup")
	_add_backup_item(review_text)
	_update_buttons()


#* The files brought back into Candy_DE, by folder setting:
func _add_moved_files(text: RichTextLabel) -> void:
	var moved: Array = upgrader.files_with(Upgrader.MOVED)
	if moved.is_empty():
		return
	var counts := {}
	for entry in moved:
		var folder = upgrader.data_folder(entry["path"])
		var group := "other files"
		if folder != null:
			group = String(folder["setting"]).trim_suffix("_folder").replace("_", " ")
		counts[group] = int(counts.get(group, 0)) + 1
	var parts: PackedStringArray = []
	for group in counts:
		parts.append("%s %d" % [group, counts[group]])
	Style.rich_item(text, "MoveDown", "Your files, moved into %s (%d): %s." % [Style.code(Utils.CANDY_DE_FOLDER), moved.size(), _dim(", ".join(parts))])
	var kept: Array = moved.filter(func(entry: Dictionary) -> bool: return entry.get("replaces", false))
	if not kept.is_empty():
		Style.rich_item(text, "Edit", "%d of them are kept instead of %s's file of the same name:" % [kept.size(), package.version()])
		_add_paths(text, kept.map(func(entry: Dictionary) -> String: return String(entry["to"]).trim_prefix(Utils.CANDY_DE_FOLDER + "/")))
	if not upgrader.release_added.is_empty():
		Style.rich_item(text, "Add", "%s adds %d file(s) you didn't have:" % [package.version(), upgrader.release_added.size()])
		_add_paths(text, Array(upgrader.release_added).map(func(path: String) -> String: return path.trim_prefix(Utils.CANDY_DE_FOLDER + "/")))


#* The folder settings that change other than with the install folder's name:
func _add_folder_changes(text: RichTextLabel) -> void:
	for entry in upgrader.folders:
		var from := String(entry["from"]).trim_prefix(install_folder + "/")
		var to := String(entry["to"]).trim_prefix(Utils.CANDY_DE_FOLDER + "/")
		if entry["kind"] == Upgrader.FOLDER_OUTSIDE:
			Style.rich_item(text, "Folder", "%s: your folder %s stays where it is." % [Style.code(entry["setting"]), Style.code(entry["from"])])
		elif from != to and not entry.get("reset", false):
			Style.rich_item(text, "Folder", "%s: %s becomes %s." % [Style.code(entry["setting"]), Style.code(from), Style.code(to)])


func _add_custom_folders(text: RichTextLabel) -> void:
	var counts := {Upgrader.RENAME: 0, Upgrader.LIBRARY: 0, Upgrader.COPY: 0}
	for entry in upgrader.custom_changes:
		if counts.has(entry["status"]):
			counts[entry["status"]] += 1
	if counts[Upgrader.RENAME] > 0:
		Style.rich_item(text, "Edit", "%d voice file(s) in your custom voice folder move to variation folders written with %s instead of %s." % [counts[Upgrader.RENAME], Style.code("="), Style.code(":")])
	if counts[Upgrader.LIBRARY] > 0:
		Style.rich_item(text, "Edit", "%d animation librar(ies) in your custom background folder move to its shared %s folder." % [counts[Upgrader.LIBRARY], Style.code(Upgrader.LIBRARIES_FOLDER)])
	if counts[Upgrader.COPY] > 0:
		Style.rich_item(text, "Duplicate", "%d scene(s) and script(s) in your custom folders are copied into the %s copy, to keep their %s versions while you update them." % [counts[Upgrader.COPY], Upgrader.FROM_VERSION, Upgrader.FROM_VERSION])


#* The first paths of a list, indented, then how many more:
func _add_paths(text: RichTextLabel, paths: Array) -> void:
	text.push_indent(1)
	for index in mini(paths.size(), LISTED_FILES):
		text.append_text(_dim(_escaped(String(paths[index]))))
		text.newline()
	if paths.size() > LISTED_FILES:
		text.append_text(_dim("and %d more" % (paths.size() - LISTED_FILES)))
		text.newline()
	text.pop()


#* How many files of a folder setting are brought back:
func _moved_count(setting: String) -> int:
	var count := 0
	for entry in upgrader.files_with(Upgrader.MOVED):
		var folder = upgrader.data_folder(entry["path"])
		if folder != null and folder["setting"] == setting:
			count += 1
	return count


#==============================================================================
#  UPGRADE
#==============================================================================

func _upgrade() -> void:
	var open: PackedStringArray = upgrader.open_files()
	if not open.is_empty():
		error_label.text = "Close these in the editor first (saving one after the upgrade would put it back): " + ", ".join(open)
		return

	busy = true
	_show_step(Step.UPGRADING)
	var backup_error: String = await _run_backup("before_Candy_DE_%s" % package.version())
	if backup_error != "":
		busy = false
		_show_step(Step.REVIEW)
		error_label.text = "The backup failed, so nothing was upgraded: " + backup_error
		return

	upgrader.progress.connect(_on_work_progress)
	var upgrade_error: String = await upgrader.upgrade(get_tree())
	upgrade_succeeded = upgrade_error == ""
	if upgrade_succeeded:
		Utils.set_post_notes_pending(package.wizard_notes("post", _notes_flow()) != "")
		Utils.set_unopened_tools(Utils.TOOLS_TO_OPEN_AFTER_UPGRADE)
	busy = false
	_fill_done(upgrade_error)
	_show_step(Step.DONE)
	if upgrade_succeeded:
		_wait_for_imports()


func _fill_done(upgrade_error: String) -> void:
	done_text.clear()
	open_report_button.visible = upgrader.report_path != "" and FileAccess.file_exists(upgrader.report_path)
	open_copy_button.visible = DirAccess.dir_exists_absolute(Upgrader.ASIDE_FOLDER)
	if upgrade_error != "":
		_set_result_banner(done_banner, false, "Candy DE wasn't upgraded", "")
		Style.rich_item(done_text, "StatusError", _colored(_escaped(upgrade_error), "error_color"))
	else:
		_set_result_banner(done_banner, true, "Candy DE %s is installed" % package.version(), "Upgraded from %s, with your settings, data and media." % Upgrader.FROM_VERSION)
		Style.rich_heading(done_text, "Next")
		Style.rich_item(done_text, "Reload", "Restart the editor, so Godot forgets Candy DE %s's scripts." % Upgrader.FROM_VERSION)
		Style.rich_item(done_text, "File", "The report, %s, lists what's left to do by hand: dialogues to convert, scenes and scripts to move back, and what to check." % Style.code(upgrader.report_path))
		Style.rich_item(done_text, "Save", "Candy DE %s stays in %s until you delete it. Godot ignores it: open it with your file manager." % [Upgrader.FROM_VERSION, Style.code(Upgrader.ASIDE_FOLDER)])
		Style.rich_item(done_text, "Reload", _dim("Then update to the latest release from the dock, as usual."))
	if backup_path != "":
		Style.rich_heading(done_text, "Backup")
		Style.rich_item(done_text, "Save", Style.code(backup_path))
