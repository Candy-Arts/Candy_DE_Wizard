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
extends Window


signal wizard_closed

const Utils = preload("Wizard_Utils.gd")
const Style = preload("UI_Style.gd")
const ProjectBackup = preload("Project_Backup.gd")

#^ Set before adding to the tree:
var wizard_version := ""

var step: int = 0
var busy := false
var backup_path := ""
var restarting := false					#/ Closed to restart the editor
var importing_files := false			#/ Godot is still importing what the wizard wrote: no restart yet

#^ Layout:
var heading_label: Label
var pages := {}
var error_label: Label
var error_row: Control
var back_button: Button
var next_button: Button
var cancel_button: Button

#^ Steps, in the header:
var step_circles: Array[PanelContainer] = []
var step_numbers: Array[Label] = []
var step_labels: Array[Label] = []

#^ Backup page:
var backup_check: CheckBox
var backup_folder_edit: LineEdit
var backup_browse_button: Button
var folder_dialog: EditorFileDialog

#^ Progress page:
var work_progress: ProgressBar
var work_status: Label

var layout_root: Control = null			#/ Everything the window shows
var _last_needed := Vector2i.ZERO		#/ The size the content asked for last frame


func _ready() -> void:
	transient = true
	exclusive = true
	#? No wrap_controls: autowrapped labels report a huge height before getting a width.
	#? _fit_content() grows the window instead.
	wrap_controls = false
	close_requested.connect(_on_cancel_pressed)
	min_size = Vector2i(Style.px(760), Style.px(580))
	_build_layout()


func _process(_delta: float) -> void:
	#? Show the labels while they have text:
	error_row.visible = error_label.text != ""
	heading_label.visible = heading_label.text != ""
	_fit_content()


#* Grow the window to fit its content (never shrink):
func _fit_content() -> void:
	if not visible or layout_root == null:
		_last_needed = Vector2i.ZERO
		return
	var minimum := layout_root.get_combined_minimum_size()
	var needed := Vector2i(int(ceil(minimum.x)), int(ceil(minimum.y)))
	#% Only a size asked two frames in a row (a label just shown reports a huge height for a frame):
	var settled := needed == _last_needed
	_last_needed = needed
	if not settled or (needed.x <= size.x and needed.y <= size.y):
		return
	var limit := Vector2i.ZERO
	if is_embedded():
		#? Single-window mode:
		limit = Vector2i(get_tree().root.get_visible_rect().size)
	else:
		limit = DisplayServer.screen_get_usable_rect(current_screen).size
	var fitted := Vector2i(maxi(size.x, mini(needed.x, limit.x)), maxi(size.y, mini(needed.y, limit.y)))
	if fitted == size:
		return
	size = fitted
	move_to_center()


#==============================================================================
#  TO OVERRIDE
#==============================================================================

#* Pages, by step:
func _build_pages() -> Dictionary:
	return {}


#* Header step names:
func _step_names() -> PackedStringArray:
	return PackedStringArray()


#* Line under the title:
func _subtitle() -> String:
	return ""


#* Set the footer's buttons for the current step:
func _update_buttons() -> void:
	pass


func _on_back_pressed() -> void:
	pass


func _on_next_pressed() -> void:
	pass


func _on_cancel_pressed() -> void:
	pass


#* Close and free the wizard:
func _close() -> void:
	hide()
	wizard_closed.emit()
	queue_free()


#==============================================================================
#  LAYOUT
#==============================================================================

func _build_layout() -> void:
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", EditorInterface.get_base_control().get_theme_stylebox("panel", "AcceptDialog"))
	add_child(background)
	layout_root = background
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	background.add_child(column)

	column.add_child(_build_header())

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right"]:
		body.add_theme_constant_override(side, Style.px(24))
	for side in ["margin_top", "margin_bottom"]:
		body.add_theme_constant_override(side, Style.px(18))
	column.add_child(body)
	var body_column := VBoxContainer.new()
	body_column.add_theme_constant_override("separation", Style.px(12))
	body.add_child(body_column)

	heading_label = Style.label("", "bold", 1.25)
	body_column.add_child(heading_label)
	var page_holder := VBoxContainer.new()
	page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_column.add_child(page_holder)
	pages = _build_pages()
	for page in pages.values():
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page_holder.add_child(page)

	var error_box := Style.card_box(body_column, Style.color("error_color"))
	error_row = error_box.get_parent()
	var error_line := HBoxContainer.new()
	error_line.add_theme_constant_override("separation", Style.px(8))
	error_box.add_child(error_line)
	error_line.add_child(Style.icon_rect(Style.icon("StatusError"), 16))
	error_label = Label.new()
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	error_line.add_child(error_label)
	error_row.visible = false

	column.add_child(_build_footer())


#* Header - logo, title, subtitle, steps:
func _build_header() -> Control:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", Style.band(Style.color("dark_color_2"), SIDE_BOTTOM, Style.BRAND, 2))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Style.px(14))
	header.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", Style.px(14))
	column.add_child(title_row)
	title_row.add_child(Style.icon_rect(Style.logo(40), 40))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_child(titles)
	titles.add_child(Style.label(title, "bold", 1.35))
	var subtitle := Style.caption(_subtitle())
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	titles.add_child(subtitle)

	var names := _step_names()
	if names.is_empty():
		return header
	var steps_row := HBoxContainer.new()
	steps_row.add_theme_constant_override("separation", Style.px(8))
	column.add_child(steps_row)
	for index in names.size():
		if index > 0:
			var line := HSeparator.new()
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.custom_minimum_size.x = Style.px(12)
			steps_row.add_child(line)
		var circle := PanelContainer.new()
		circle.custom_minimum_size = Vector2(Style.px(24), Style.px(24))
		circle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		steps_row.add_child(circle)
		var number := Style.label(str(index + 1), "bold", 0.85)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		circle.add_child(number)
		var step_label := Style.label(names[index])
		steps_row.add_child(step_label)
		step_circles.append(circle)
		step_numbers.append(number)
		step_labels.append(step_label)
	return header


#* Footer - Cancel left; Back and the main button right:
func _build_footer() -> Control:
	var footer := PanelContainer.new()
	var style := Style.band(Style.color("dark_color_2"), SIDE_TOP, Style.color("extra_border_color_1"), 1)
	style.content_margin_top = Style.px(10)
	style.content_margin_bottom = Style.px(10)
	footer.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(8))
	footer.add_child(row)
	cancel_button = Style.button("Cancel", "", _on_cancel_pressed)
	row.add_child(cancel_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	back_button = Style.button("Back", "Back", _on_back_pressed)
	row.add_child(back_button)
	next_button = Style.button("Next", "", _on_next_pressed)
	next_button.custom_minimum_size.x = Style.px(110)
	row.add_child(next_button)
	return footer


#* Show one page:
func _show_page(new_step: int) -> void:
	step = new_step
	for page_step in pages:
		pages[page_step].visible = page_step == step


#* Mark steps before current as done (finished = all done):
func _set_step_marker(current: int, finished: bool) -> void:
	for index in step_circles.size():
		var circle_style := StyleBoxFlat.new()
		circle_style.set_corner_radius_all(Style.px(12))
		var label_color := Style.color("font_color")
		var number_color := Color.WHITE
		var bold := false
		if finished or index < current:
			circle_style.bg_color = Style.BRAND.darkened(0.35)
			label_color = Style.dim()
		elif index == current:
			circle_style.bg_color = Style.BRAND
			bold = true
		else:
			circle_style.draw_center = false
			circle_style.border_color = Style.dim()
			circle_style.set_border_width_all(Style.px(1))
			label_color = Style.dim()
			number_color = Style.dim()
		step_circles[index].add_theme_stylebox_override("panel", circle_style)
		step_numbers[index].add_theme_color_override("font_color", number_color)
		step_labels[index].add_theme_color_override("font_color", label_color)
		if bold:
			step_labels[index].add_theme_font_override("font", Style.font("bold"))
		else:
			step_labels[index].remove_theme_font_override("font")


#* Holds the "Restart Editor" button until Godot has imported the new files:
func _wait_for_imports() -> void:
	importing_files = true
	_update_buttons()
	Utils.when_imported(get_tree(), _on_imports_done)


func _on_imports_done() -> void:
	importing_files = false
	_update_buttons()


#* The last page's "Restart Editor" button (shown = the work succeeded):
func _set_restart_button(shown: bool) -> void:
	next_button.visible = shown
	next_button.icon = Style.icon("Reload")
	if importing_files:
		_set_next("Importing Files…", "plain")
		next_button.disabled = true
		next_button.tooltip_text = "Godot is importing the new files. Restart once it's done."
	else:
		_set_next("Restart Editor", "primary")
		next_button.tooltip_text = ""


#* Main button's text and look: "primary", "danger" or "plain":
func _set_next(text: String, look: String) -> void:
	next_button.text = text
	match look:
		"primary":
			Style.make_primary(next_button)
		"danger":
			Style.make_danger(next_button)
		_:
			Style.make_plain(next_button)


func _rich_text() -> RichTextLabel:
	return Style.rich_text()


func _wrapped_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


#==============================================================================
#  BACKUP
#==============================================================================

#* Backup page (intro = what will change):
func _build_backup_page(intro: String) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Style.px(14))
	page.add_child(_wrapped_label(intro))

	var box := Style.card_box(page)
	box.add_theme_constant_override("separation", Style.px(10))
	var check_row := HBoxContainer.new()
	check_row.add_theme_constant_override("separation", Style.px(8))
	box.add_child(check_row)
	check_row.add_child(Style.icon_rect(Style.icon("Save"), 16))
	backup_check = CheckBox.new()
	backup_check.text = "Back up the project first"
	backup_check.add_theme_font_override("font", Style.font("bold"))
	backup_check.button_pressed = true
	backup_check.toggled.connect(func(_on: bool) -> void: _update_backup_controls())
	check_row.add_child(backup_check)

	box.add_child(Style.caption("A zip of the whole project, except the .godot folder (Godot's cache, rebuilt on its own) and the .git folder. It must be saved outside the project."))

	var folder_row := HBoxContainer.new()
	folder_row.add_theme_constant_override("separation", Style.px(6))
	backup_folder_edit = LineEdit.new()
	backup_folder_edit.placeholder_text = "A folder outside the project"
	backup_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(Utils.SETTING_BACKUP_FOLDER):
		backup_folder_edit.text = String(settings.get_setting(Utils.SETTING_BACKUP_FOLDER))
	folder_row.add_child(backup_folder_edit)
	backup_browse_button = Style.button("Browse…", "FolderBrowse", func() -> void: folder_dialog.popup_file_dialog())
	folder_row.add_child(backup_browse_button)
	box.add_child(folder_row)

	folder_dialog = EditorFileDialog.new()
	folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	folder_dialog.title = "Choose where to save backups"
	folder_dialog.dir_selected.connect(func(path: String) -> void: backup_folder_edit.text = path)
	add_child(folder_dialog)
	return page


func _update_backup_controls() -> void:
	backup_folder_edit.editable = backup_check.button_pressed
	backup_browse_button.disabled = not backup_check.button_pressed


#* Validate the backup choice; show why not in the error line:
func _check_backup() -> bool:
	if not backup_check.button_pressed:
		return true
	var problem := ProjectBackup.folder_problem(backup_folder_edit.text)
	if problem != "":
		error_label.text = problem
		return false
	EditorInterface.get_editor_settings().set_setting(Utils.SETTING_BACKUP_FOLDER, backup_folder_edit.text)
	return true


#* Backup line in a summary:
func _add_backup_item(text: RichTextLabel) -> void:
	if backup_check.button_pressed:
		Style.rich_item(text, "Save", "Backed up first, to %s" % Style.code(backup_folder_edit.text))
	else:
		Style.rich_item(text, "StatusWarning", Style.colored("No backup.", "warning_color"))


#* Make the backup, if asked. label goes in its file name. Returns an error, or "":
func _run_backup(label: String) -> String:
	if not backup_check.button_pressed:
		return ""
	var backup = ProjectBackup.new()
	backup.progress.connect(_on_work_progress)
	var backup_error: String = await backup.create(backup_folder_edit.text, label, get_tree())
	if backup_error == "":
		backup_path = backup.backup_path
	return backup_error


#==============================================================================
#  PROGRESS
#==============================================================================

func _build_progress_page() -> Control:
	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", Style.px(14))
	var logo := Style.icon_rect(Style.logo(56), 56)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(logo)
	work_status = Style.label("")
	work_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(work_status)
	work_progress = ProgressBar.new()
	work_progress.max_value = 1.0
	work_progress.step = 0.001
	work_progress.custom_minimum_size.x = Style.px(420)
	work_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(work_progress)
	return page


func _on_work_progress(fraction: float, message: String) -> void:
	work_progress.value = fraction
	work_status.text = message


#==============================================================================
#  RESULT
#==============================================================================

#* Result banner - icon, headline, details:
func _build_result_banner(parent: Node) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(14))
	parent.add_child(row)
	var icon := Style.icon_rect(null, 32)
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var headline := Style.label("", "bold", 1.1)
	texts.add_child(headline)
	var details := Style.caption("")
	texts.add_child(details)
	return {"icon": icon, "headline": headline, "details": details}


func _set_result_banner(banner: Dictionary, succeeded: bool, headline: String, details: String) -> void:
	if succeeded:
		banner["icon"].texture = Style.icon("StatusSuccess")
	else:
		banner["icon"].texture = Style.icon("StatusError")
	banner["headline"].text = headline
	banner["details"].text = details
	banner["details"].visible = details != ""


#==============================================================================
#  TEXT
#==============================================================================

func _escaped(text: String) -> String:
	return Style.escaped(text)


func _color_hex(color_name: String) -> String:
	return Style.color(color_name).to_html(false)


func _colored(text: String, color_name: String) -> String:
	return Style.colored(text, color_name)
