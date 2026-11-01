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


const Updater = preload("Updater.gd")
const UpdateSteps = preload("Update_Steps.gd")

enum Step { SOURCE, NOTES, BACKUP, QUESTIONS, REVIEW, UPDATING, DONE }

const STEP_HEADINGS := {
	Step.SOURCE: "Choose the release",
	Step.NOTES: "Before you update",
	Step.BACKUP: "Back up the project",
	Step.QUESTIONS: "New preferences",
	Step.REVIEW: "Ready to update",
	Step.UPDATING: "Updating Candy DE",
}

#^ Where each step is in the header's list of steps:
const STEP_MARKERS := {
	Step.SOURCE: 0,
	Step.NOTES: 1,
	Step.BACKUP: 2,
	Step.QUESTIONS: 3,
	Step.REVIEW: 4,
	Step.UPDATING: 5,
	Step.DONE: 5,
}

#^ How many paths a list names before only counting them:
const LISTED_FILES := 12
#^ Choice rows shown before the list scrolls:
const VISIBLE_CHOICES := 3

#^ Each file status with a heading in the review - [status, icon, heading, what happens]:
const FILE_GROUPS := [
	[Updater.OVERWRITTEN, "StatusWarning", "Yours, overwritten", "Changed by you: the release's versions replace them. Yours are kept in the update's Previous folder, so you can add your code again."],
	[Updater.EXISTING, "StatusWarning", "Your own files, overwritten", "This release adds files of its own where you have yours. Yours are kept in the update's Previous folder."],
	[Updater.UPDATED, "Reload", "Updated", "Not changed by you: the new version replaces them."],
	[Updater.ADDED, "Add", "Added", "New in this release."],
	[Updater.REMOVED, "Remove", "Removed", "No longer part of Candy DE. Each is kept in the update's Previous folder."],
	[Updater.TEMPLATE_CHANGED, "StatusWarning", "Your files the release changed", "Updates never overwrite your files: yours stay, and the release's versions are saved in the update's New folder, to compare."],
	[Updater.LEFT, "Info", "Left in place", "No longer part of Candy DE, but changed by you: they stay, and are yours from now on."],
]

#^ The choices, per status, as [[choice, label], ...]. The first is the default:
const CHOICES := {
	Updater.DELETED: [[Updater.LEAVE_OUT, "Leave it out"], [Updater.RESTORE, "Restore it"]],
}
const CHOICE_REASONS := {
	Updater.DELETED: "Deleted by you",
}

#^ The overwrite warning's size when its list of files is long enough to scroll:
const OVERWRITE_DIALOG_SIZE := Vector2i(680, 520)
const OVERWRITE_DIALOG_MIN_HEIGHT := 280

var record: Dictionary = {}
var updater = null
var choices := {}						#/ Path -> choice, kept across plans
var update_succeeded := false

#^ Review page:
var choices_card: VBoxContainer
var choices_scroll: ScrollContainer
var choices_list: VBoxContainer
var review_text: RichTextLabel

#^ Done page:
var done_banner: Dictionary
var done_text: RichTextLabel
var open_folder_button: Button


func _ready() -> void:
	title = "Update Candy Dialogue Engine"
	record = Utils.read_record()
	super()
	#? As big as the install wizard: the release page, the review and six steps need it.
	min_size = Vector2i(Style.px(840), Style.px(720))
	_show_step(Step.SOURCE)
	_start_source()


#* Candy DE isn't updated while GitHub has a newer Candy Wizard (that look may end after opening):
func _blocking_problem() -> String:
	var newer_wizard := Utils.newer_wizard_version(wizard_version)
	if newer_wizard != "":
		return "Update Candy Wizard to %s first (the button beside its version, in the dock): Candy DE is only updated with the latest Candy Wizard." % newer_wizard
	return ""


func _release_problem(version: String) -> String:
	var installed := String(record.get("version", ""))
	var comparison := Utils.compare_versions(version, installed)
	if comparison == 0:
		return "Candy DE %s is installed already: it's up to date." % installed
	if comparison < 0:
		return "Candy DE %s is installed, which is newer than this release (%s)." % [installed, version]
	return ""


func _questions_to_ask() -> Array:
	var answered: Dictionary = record.get("answers", {})
	var asked := []
	for question in package.manifest.get("questions", []):
		if not answered.has(String(question.get("id", ""))):
			asked.append(question)
	return asked


func _zip_only_prompt() -> String:
	return "Choose the Candy DE release zip to update to."


func _notes_flow() -> String:
	return Utils.NOTES_UPDATE


#==============================================================================
#  LAYOUT
#==============================================================================

func _build_pages() -> Dictionary:
	var built := {}
	built[Step.SOURCE] = _build_source_page()
	built[Step.NOTES] = _build_notes_page()
	built[Step.BACKUP] = _build_backup_page("Updating replaces Candy DE's files, the ones you changed included, and may change your settings files and the project settings. Every file it changes is kept in Candy_DE/.Install/Updates first, but a full backup is safer.")
	built[Step.QUESTIONS] = _build_questions_page()
	built[Step.REVIEW] = _build_review_page()
	built[Step.UPDATING] = _build_progress_page()
	var done_page := VBoxContainer.new()
	done_page.add_theme_constant_override("separation", Style.px(14))
	done_banner = _build_result_banner(done_page)
	done_text = _rich_text()
	done_page.add_child(done_text)
	open_folder_button = Style.button("Open the Update's Folder", "Folder", func() -> void: OS.shell_open(ProjectSettings.globalize_path(updater.folder)))
	open_folder_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	open_folder_button.visible = false
	done_page.add_child(open_folder_button)
	built[Step.DONE] = done_page
	return built


func _step_names() -> PackedStringArray:
	return PackedStringArray(["Release", "Notes", "Backup", "Preferences", "Review", "Update"])


func _subtitle() -> String:
	return "Brings Candy Dialogue Engine %s up to date, keeping your own files and settings." % String(record.get("version", ""))


#* The choices (Candy DE's files the developer deleted), above the summary:
func _build_review_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Style.px(12))
	choices_card = Style.card_box(page, Style.color("warning_color"))
	choices_card.add_theme_constant_override("separation", Style.px(8))
	Style.card_title(choices_card, "StatusWarning", "Your choices")
	choices_card.add_child(Style.caption("Files of Candy DE's that you deleted. The update leaves them out, unless you ask for them back."))
	choices_scroll = ScrollContainer.new()
	choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices_card.add_child(choices_scroll)
	choices_list = VBoxContainer.new()
	choices_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_list.add_theme_constant_override("separation", Style.px(4))
	choices_scroll.add_child(choices_list)
	review_text = _rich_text()
	page.add_child(review_text)
	return page


#==============================================================================
#  NAVIGATION
#==============================================================================

func _show_step(new_step: int) -> void:
	_show_page(new_step)
	_set_step_marker(STEP_MARKERS[step], step == Step.DONE and update_succeeded)
	if step == Step.DONE:
		#? The result banner heads the last page.
		heading_label.text = ""
	else:
		heading_label.text = STEP_HEADINGS[step]
	if step == Step.NOTES:
		heading_label.text = "Before you update to Candy DE %s" % package.version()
		_fill_notes_page()
	if step == Step.REVIEW:
		_plan()
	_update_buttons()


func _update_buttons() -> void:
	back_button.visible = step != Step.DONE
	back_button.disabled = busy or step == Step.SOURCE or step == Step.UPDATING
	next_button.disabled = busy or not _can_go_next()
	cancel_button.disabled = step == Step.UPDATING
	cancel_button.text = "Cancel"
	next_button.visible = true
	next_button.icon = null
	match step:
		Step.REVIEW:
			_set_next("Update", "primary")
			next_button.icon = Style.icon("Reload")
		Step.DONE:
			_set_restart_button(update_succeeded)
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
		Step.REVIEW:
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
					_show_step(Step.REVIEW)
				else:
					_show_step(Step.QUESTIONS)
		Step.QUESTIONS:
			if _check_answers():
				_show_step(Step.REVIEW)
		Step.REVIEW:
			_update()
		Step.DONE:
			#? The post notes wait for the restart (Wizard_Dock.gd).
			restarting = true
			_close()
			EditorInterface.restart_editor(true)


func _on_cancel_pressed() -> void:
	if step == Step.UPDATING:
		return
	_close()


#==============================================================================
#  REVIEW
#==============================================================================

#* Works out the update (nothing is changed), then shows it:
func _plan() -> void:
	updater = Updater.new()
	updater.package = package
	updater.record = record
	updater.new_answers = _answers()
	updater.choices = choices
	updater.source_text = source_text
	updater.wizard_version = wizard_version
	updater.plan()
	_build_choice_rows()
	_fill_review()


#* A row per file needing a choice:
#? Only rebuilt with a new plan: a choice changes the summary only.
func _build_choice_rows() -> void:
	for child in choices_list.get_children():
		child.queue_free()
	var count := 0
	for entry in updater.files:
		if not entry.has("choice"):
			continue
		count += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Style.px(8))
		choices_list.add_child(row)
		row.add_child(Style.icon_rect(Style.icon("File"), 16))
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(names)
		var path_label := Style.label(String(entry["path"]).trim_prefix(Utils.PACKAGE_NAME + "/"), "source")
		path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		path_label.tooltip_text = String(entry["path"])
		path_label.mouse_filter = Control.MOUSE_FILTER_PASS
		names.add_child(path_label)
		#? Unwrapped, so the row's height is known before it has a width.
		var reason := Style.caption(CHOICE_REASONS[entry["status"]])
		reason.autowrap_mode = TextServer.AUTOWRAP_OFF
		names.add_child(reason)
		var options := OptionButton.new()
		options.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		options.custom_minimum_size.x = Style.px(190)
		var allowed: Array = CHOICES[entry["status"]]
		for index in allowed.size():
			options.add_item(allowed[index][1])
			options.set_item_metadata(index, allowed[index][0])
			if allowed[index][0] == entry["choice"]:
				options.select(index)
		var path := String(entry["path"])
		options.item_selected.connect(func(index: int) -> void:
			choices[path] = options.get_item_metadata(index)
			updater.choices = choices
			updater.plan()
			_fill_review())
		row.add_child(options)
	choices_card.get_parent().visible = count > 0
	#? Room for VISIBLE_CHOICES rows; more scroll.
	var height := 0.0
	var rows := choices_list.get_children().filter(func(child: Node) -> bool: return not child.is_queued_for_deletion())
	for index in mini(rows.size(), VISIBLE_CHOICES):
		height += rows[index].get_combined_minimum_size().y
		if index > 0:
			height += choices_list.get_theme_constant("separation")
	choices_scroll.custom_minimum_size.y = height


func _fill_review() -> void:
	review_text.clear()
	if updater.problem != "":
		Style.rich_item(review_text, "StatusError", _colored(_escaped(updater.problem), "error_color"))
		_update_buttons()
		return
	Style.rich_heading(review_text, "Candy DE %s → %s" % [String(record.get("version", "")), package.version()])
	Style.rich_item(review_text, "Save", "Every file the update replaces or removes is kept first in %s." % Style.code(updater.folder.path_join("Previous")))
	var overwritten: Array = updater.overwritten_files()
	if not overwritten.is_empty():
		Style.rich_item(review_text, "StatusWarning", _colored("%s overwritten: \"Update\" lists them, and asks before anything changes." % _files_you_changed(overwritten.size()), "warning_color"))

	if not updater.to_do.is_empty():
		Style.rich_heading(review_text, "To do by hand afterwards")
		_add_to_do(review_text)

	Style.rich_heading(review_text, "Files")
	var listed := false
	for group in FILE_GROUPS:
		listed = _add_file_group(review_text, group) or listed
	var choice_count := 0
	for entry in updater.files:
		if entry.has("choice"):
			choice_count += 1
	if choice_count > 0:
		Style.rich_item(review_text, "StatusWarning", "%d as you choose above" % choice_count)
		listed = true
	if updater.unchanged > 0:
		Style.rich_item(review_text, "StatusSuccess", _dim("%d already as the release has them" % updater.unchanged))
	elif not listed:
		Style.rich_item(review_text, "StatusSuccess", _dim("No file changes."))

	var shown_steps := []
	for result in updater.step_results:
		if result["result"] != UpdateSteps.MANUAL:
			shown_steps.append(result)
	if not shown_steps.is_empty():
		Style.rich_heading(review_text, "Changes made by the update")
		for result in shown_steps:
			_add_step_result(review_text, result)

	if not updater.settings.is_empty():
		Style.rich_heading(review_text, "Project settings")
		for setting in updater.settings:
			var text: String = _styled_code(setting["text"])
			if setting["warning"]:
				text = _colored(text, "warning_color")
			Style.rich_item(review_text, setting["icon"], text)

	Style.rich_heading(review_text, "Backup")
	_add_backup_item(review_text)
	_update_buttons()


#* One group of files - heading, count, what happens, then the first paths. Returns whether it had any:
func _add_file_group(text: RichTextLabel, group: Array) -> bool:
	var paths: PackedStringArray = []
	for entry in updater.files:
		if entry["status"] == group[0]:
			paths.append(String(entry["path"]).trim_prefix(Utils.PACKAGE_NAME + "/"))
	if paths.is_empty():
		return false
	Style.rich_item(text, group[1], "%s (%d)  %s" % [group[2], paths.size(), _dim(group[3])])
	text.push_indent(1)
	for index in mini(paths.size(), LISTED_FILES):
		text.append_text(_dim(_escaped(paths[index])))
		text.newline()
	if paths.size() > LISTED_FILES:
		text.append_text(_dim("and %d more" % (paths.size() - LISTED_FILES)))
		text.newline()
	text.pop()
	return true


func _add_step_result(text: RichTextLabel, result: Dictionary) -> void:
	var description := _styled_code(UpdateSteps.describe(result["step"], Callable(Updater, "_code")))
	match result["result"]:
		UpdateSteps.DONE:
			Style.rich_item(text, "StatusSuccess", description)
		UpdateSteps.ALREADY:
			var note := "already done"
			if String(result.get("note", "")) != "":
				note = String(result["note"])
			Style.rich_item(text, "StatusSuccess", "%s  %s" % [description, _dim(_escaped(note))], Style.dim())
		UpdateSteps.FAILED:
			Style.rich_item(text, "StatusWarning", "%s  %s" % [description, _colored("can't be done automatically: %s. It's in the list to do by hand." % _escaped(String(result.get("reason", ""))), "warning_color")])


func _add_to_do(text: RichTextLabel) -> void:
	for index in updater.to_do.size():
		var item: Dictionary = updater.to_do[index]
		if index > 0:
			#? A little room between two items: their texts can take several lines.
			text.push_font_size(Style.px(5))
			text.add_text(" ")
			text.newline()
			text.pop()
		Style.rich_item(text, "Edit", _styled_code(String(item["title"])))
		text.push_indent(1)
		text.append_text(_dim(_escaped(String(item["text"]))))
		text.newline()
		text.pop()


#* Updater.gd's [code] names, in Candy Wizard's code style:
func _styled_code(bbcode: String) -> String:
	var color := Style.color("font_color").lerp(Color.WHITE, 0.35).to_html(false)
	return bbcode.replace("[code]", "[code][color=#%s]" % color).replace("[/code]", "[/color][/code]")


#==============================================================================
#  OVERWRITE WARNING
#==============================================================================

#* "1 file you changed is" / "3 files you changed are":
func _files_you_changed(count: int) -> String:
	if count == 1:
		return "1 file you changed is"
	return "%d files you changed are" % count


#* Lists the developer's files the update overwrites, and asks to abort or overwrite. Returns whether to go on:
func _confirm_overwrites(overwritten: Array) -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Your changes will be overwritten"
	dialog.ok_button_text = "Overwrite and Update"
	dialog.cancel_button_text = "Abort"

	var counted := "The file listed below will be overwritten."
	if overwritten.size() > 1:
		counted = "The %d files listed below will be overwritten." % overwritten.size()
	var copies := "The update keeps a copy of each in %s." % Style.code(updater.folder.path_join("Previous"))
	if backup_check.button_pressed:
		copies += " The project backup you asked for has them too."

	#? One text for it all (a dialog overlaps its own label and an added control).
	#? Question first, so a long list never pushes it out of view.
	var text := Style.rich_text()
	Style.rich_item(text, "StatusWarning", _colored("The update replaces Candy DE's files that you changed with the release's versions, even where the release didn't change them: your changes could break what Candy DE %s brings. %s" % [_escaped(package.version()), counted], "warning_color"))
	text.newline()
	Style.rich_item(text, "Save", "Back these files up if you haven't yet. After the update, add your own code to the new versions again. " + copies)
	text.newline()
	Style.rich_item(text, "Help", "Abort to back them up first (nothing is changed, and the wizard closes), or overwrite them now?")
	Style.rich_heading(text, "Overwritten")
	for entry in overwritten:
		var line := Style.code(String(entry["path"]).trim_prefix(Utils.PACKAGE_NAME + "/"))
		if entry["status"] == Updater.EXISTING:
			line += "  " + _dim("your own file, where this release adds one of Candy DE's")
		Style.rich_item(text, "File", line)
	dialog.add_child(text)

	var answer := {"value": -1}
	dialog.confirmed.connect(func() -> void: answer["value"] = 1)
	dialog.canceled.connect(func() -> void: answer["value"] = 0)
	add_child(dialog)
	dialog.popup_centered(Vector2i(Style.px(OVERWRITE_DIALOG_SIZE.x), Style.px(OVERWRITE_DIALOG_SIZE.y)))

	#? Opened at its tallest (a long list scrolls); a shorter text shrinks it.
	await get_tree().process_frame
	await get_tree().process_frame
	if answer["value"] == -1 and is_instance_valid(dialog):
		var content_height := text.get_content_height()
		var spare := int(text.size.y) - content_height
		if content_height > 0 and spare > 0:
			dialog.size.y = maxi(dialog.size.y - spare, Style.px(OVERWRITE_DIALOG_MIN_HEIGHT))
			dialog.move_to_center()

	while answer["value"] == -1 and is_instance_valid(dialog):
		await get_tree().process_frame
	if is_instance_valid(dialog):
		dialog.queue_free()
	return answer["value"] == 1


#==============================================================================
#  UPDATE
#==============================================================================

func _update() -> void:
	var open: PackedStringArray = updater.open_files()
	if not open.is_empty():
		error_label.text = "Close these in the editor first (saving one after the update would undo it): " + ", ".join(open)
		return

	#? The developer's changes are overwritten: ask first.
	var overwritten: Array = updater.overwritten_files()
	if not overwritten.is_empty():
		busy = true
		_update_buttons()
		var proceed: bool = await _confirm_overwrites(overwritten)
		busy = false
		if not proceed:
			#? Aborted: nothing changed. Close, so the files can be backed up.
			_close()
			return

	busy = true
	_show_step(Step.UPDATING)
	var backup_error: String = await _run_backup("before_Candy_DE_%s" % package.version())
	if backup_error != "":
		busy = false
		_show_step(Step.REVIEW)
		error_label.text = "The backup failed, so nothing was updated: " + backup_error
		return

	updater.progress.connect(_on_work_progress)
	var update_error: String = await updater.update(get_tree())
	update_succeeded = update_error == ""
	if update_succeeded:
		Utils.set_post_notes_pending(package.wizard_notes("post", _notes_flow()) != "")
	busy = false
	_fill_done(update_error)
	_show_step(Step.DONE)
	if update_succeeded:
		_wait_for_imports()


func _fill_done(update_error: String) -> void:
	done_text.clear()
	open_folder_button.visible = DirAccess.dir_exists_absolute(updater.folder)
	if update_error != "":
		_set_result_banner(done_banner, false, "Candy DE wasn't updated", "")
		Style.rich_item(done_text, "StatusError", _colored(_escaped(update_error), "error_color"))
	else:
		_set_result_banner(done_banner, true, "Candy DE %s is installed" % package.version(), "Updated from %s. What changed is listed in the update's report." % String(record.get("version", "")))
		if not updater.to_do.is_empty():
			Style.rich_heading(done_text, "To do by hand now")
			_add_to_do(done_text)
		var overwritten: Array = updater.overwritten_files()
		if not overwritten.is_empty():
			Style.rich_heading(done_text, "Your changed files")
			Style.rich_item(done_text, "StatusWarning", "%s now as the release has them. Your versions are in %s, and listed in the update's report: add your own code to the new versions again." % [_files_you_changed(overwritten.size()), Style.code(updater.folder.path_join("Previous"))])
		Style.rich_heading(done_text, "Next")
		Style.rich_item(done_text, "Reload", "Restart the editor, so Godot loads the updated scripts.")
		Style.rich_item(done_text, "Folder", "The update's folder, %s, has the files as they were (Previous), the release's versions it didn't install (New), and a report. Godot doesn't load it." % Style.code(updater.folder))
		var install_message := String(package.manifest.get("install_message", ""))
		if install_message != "":
			Style.rich_heading(done_text, "From this release")
			Style.rich_item(done_text, "Info", _escaped(install_message))
	if backup_path != "":
		Style.rich_heading(done_text, "Backup")
		Style.rich_item(done_text, "Save", Style.code(backup_path))
