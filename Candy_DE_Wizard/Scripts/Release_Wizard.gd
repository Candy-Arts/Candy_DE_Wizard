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


const Package = preload("Package.gd")
const ReleaseSource = preload("Release_Source.gd")

var release: Dictionary = {}			#/ GitHub's latest release, or {"error": ...}
var package = null						#/ Package.gd, once opened and verified
var prepared_from := ""					#/ The source the package was prepared from
var source_text := ""
var download_path := ""
var question_rows: Array = []
var release_source: Node = null

#^ Release page:
var source_prompt: Label
var github_option: CheckBox
var zip_option: CheckBox
var release_card: VBoxContainer
var release_title: Label
var release_details: Label
var release_link: Button
var release_page_url := ""
var retry_button: Button
var release_status: HBoxContainer
var release_status_icon: TextureRect
var release_status_label: Label
var zip_path_edit: LineEdit
var zip_browse_button: Button
var zip_info: Label
var source_progress: ProgressBar
var zip_dialog: EditorFileDialog

#^ Notes page (the release's pre notes):
var notes_text: RichTextLabel

#^ Questions page:
var questions_box: VBoxContainer

#^ Tests only, set before the wizard is added - another repository (name, ID) and a stand-in for GitHub's API:
var test_repository := ""
var test_repository_id := 0
var test_api_base := ""


#==============================================================================
#  TO OVERRIDE
#==============================================================================

#* Why a release can't be used by this wizard, or "" (version is the release's):
func _release_problem(_version: String) -> String:
	return ""


#* Why this wizard can't use any release now, or "":
func _blocking_problem() -> String:
	return ""


#* The one version this wizard takes ("1.2.0"), or "" for the latest:
func _wanted_version() -> String:
	return ""


#* The manifest's questions this wizard asks:
func _questions_to_ask() -> Array:
	return package.manifest.get("questions", [])


#* The release page's first line, when the zip is the only choice:
func _zip_only_prompt() -> String:
	return "Choose the %s release zip." % _package_title()


#* Whether the releases are Candy Wizard's own rather than Candy DE's:
func _uses_wizard_releases() -> bool:
	return false


func _package_title() -> String:
	if _uses_wizard_releases():
		return "Candy Wizard"
	return "Candy DE"


#* A release zip's name, as an example:
func _zip_example() -> String:
	if _uses_wizard_releases():
		return "%s_1.0.1.zip" % Utils.WIZARD_PACKAGE_NAME
	if _wanted_version() != "":
		return "%s_%s.zip" % [Utils.PACKAGE_NAME, _wanted_version()]
	return "%s_1.2.0.zip" % Utils.PACKAGE_NAME


#* Why a release can't be used (not the wanted version, or _release_problem()), or "":
func _version_problem(version: String) -> String:
	var wanted := _wanted_version()
	if wanted != "" and Utils.compare_versions(version, wanted) != 0:
		return "This is %s %s, and this wizard needs %s %s." % [_package_title(), version, _package_title(), wanted]
	return _release_problem(version)


#* What the GitHub release is called ("the latest release", "release 1.2.0"):
func _release_wording() -> String:
	if _wanted_version() != "":
		return "release %s" % _wanted_version()
	return "the latest release"


#==============================================================================
#  RELEASE PAGE
#==============================================================================

#* Starts looking for the latest release (or offers only the zip, without a repository):
func _start_source() -> void:
	release_source = ReleaseSource.new()
	if _uses_wizard_releases():
		release_source.use_wizard_repository()
	if test_repository != "":
		release_source.repository = test_repository
	if test_repository_id != 0:
		release_source.repository_id = test_repository_id
	if test_api_base != "":
		release_source.api_base = test_api_base
	add_child(release_source)
	release_source.download_progress.connect(_on_download_progress)
	if release_source.repository == "" or release_source.repository_id == 0:
		_use_zip_only()
	else:
		_fetch_release()


func _build_source_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Style.px(14))
	#? Only when the zip is the only choice.
	source_prompt = _wrapped_label("")
	source_prompt.visible = false
	page.add_child(source_prompt)
	var group := ButtonGroup.new()

	github_option = CheckBox.new()
	var wording := _release_wording()
	github_option.text = "%s%s, downloaded from GitHub" % [wording.left(1).to_upper(), wording.substr(1)]
	github_option.button_group = group
	github_option.button_pressed = true
	github_option.toggled.connect(func(_on: bool) -> void: _update_source_controls())
	page.add_child(github_option)
	_build_release_card(page)

	zip_option = CheckBox.new()
	if _wanted_version() != "":
		zip_option.text = "The %s %s release zip on this computer" % [_package_title(), _wanted_version()]
	else:
		zip_option.text = "A %s release zip on this computer" % _package_title()
	zip_option.button_group = group
	zip_option.toggled.connect(func(_on: bool) -> void: _update_source_controls())
	page.add_child(zip_option)

	var zip_box := Style.card_box(page)
	zip_box.add_theme_constant_override("separation", Style.px(10))
	Style.card_title(zip_box, "File", "Release zip")
	zip_box.add_child(Style.caption("Such as %s. It's checked before anything is written to the project." % _zip_example()))
	var zip_row := HBoxContainer.new()
	zip_row.add_theme_constant_override("separation", Style.px(6))
	zip_path_edit = LineEdit.new()
	zip_path_edit.editable = false
	zip_path_edit.placeholder_text = "No file chosen"
	zip_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zip_row.add_child(zip_path_edit)
	zip_browse_button = Style.button("Browse…", "FolderBrowse", func() -> void: zip_dialog.popup_file_dialog())
	zip_row.add_child(zip_browse_button)
	zip_box.add_child(zip_row)
	zip_info = Style.caption("")
	zip_info.visible = false
	zip_box.add_child(zip_info)

	zip_dialog = EditorFileDialog.new()
	zip_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	zip_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	zip_dialog.filters = PackedStringArray(["*.zip ; Zip archives"])
	zip_dialog.title = "Choose a %s release zip" % _package_title()
	zip_dialog.file_selected.connect(func(path: String) -> void:
		zip_path_edit.text = path
		_update_zip_info()
		_update_buttons())
	add_child(zip_dialog)
	return page


#* The GitHub release's card - version, date, and why it can't be used (when it can't):
func _build_release_card(page: Control) -> void:
	release_card = Style.card_box(page)
	release_card.add_theme_constant_override("separation", Style.px(8))

	var title_row := Style.card_title(release_card, "AssetLib", "")
	release_title = title_row.get_child(title_row.get_child_count() - 1)
	release_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry_button = Style.button("Check Again", "Reload", func() -> void: _fetch_release())
	retry_button.flat = true
	title_row.add_child(retry_button)
	release_link = Style.button("View on GitHub", "ExternalLink", func() -> void: Utils.open_web_link(release_page_url))
	release_link.flat = true
	release_link.tooltip_text = "Opens the release's page in your browser."
	title_row.add_child(release_link)
	release_details = Style.caption("")
	release_card.add_child(release_details)

	release_status = HBoxContainer.new()
	release_status.add_theme_constant_override("separation", Style.px(8))
	release_status_icon = Style.icon_rect(null, 16)
	release_status_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	release_status.add_child(release_status_icon)
	release_status_label = _wrapped_label("")
	release_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	release_status.add_child(release_status_label)
	release_card.add_child(release_status)

	source_progress = ProgressBar.new()
	source_progress.visible = false
	release_card.add_child(source_progress)


#* The chosen zip's name and size, under its path:
func _update_zip_info() -> void:
	var zip_file: FileAccess = null
	if FileAccess.file_exists(zip_path_edit.text):
		zip_file = FileAccess.open(zip_path_edit.text, FileAccess.READ)
	#? Unreadable: nothing here (checking it says why).
	zip_info.visible = zip_file != null
	if zip_info.visible:
		zip_info.text = "%s  ·  %s" % [zip_path_edit.text.get_file(), Utils.readable_size(zip_file.get_length())]


func _fetch_release() -> void:
	release = {"checking": true}
	_show_release()
	_update_source_controls()
	if _wanted_version() != "":
		release = await release_source.fetch_release(_wanted_version())
	else:
		release = await release_source.fetch_latest_release()
	#? Kept like the dock's daily look, so the dock shows it once the wizard closes (not for tests
	#? or a wanted version).
	if test_repository == "" and test_repository_id == 0 and test_api_base == "" and _wanted_version() == "":
		if _uses_wizard_releases():
			Utils.remember_latest_release(Utils.SETTING_WIZARD_UPDATE_CHECK, release)
		else:
			Utils.remember_latest_release(Utils.SETTING_UPDATE_CHECK, release)
	#? A release this wizard can't use is shown, but can't be chosen.
	if not release.has("error") and release.has("version"):
		var blocking := _blocking_problem()
		var problem := _version_problem(String(release["version"]))
		if blocking != "":
			#? Not the release's fault, but it can't be used now: a warning.
			release["error"] = blocking
		elif problem != "":
			release["error"] = problem
			release["usable_elsewhere"] = true
	if release.has("error"):
		zip_option.button_pressed = true
	elif zip_path_edit.text == "":
		#? Found after "Check Again" with no zip chosen: choose the download.
		github_option.button_pressed = true
	_show_release()
	_update_source_controls()


#* Fills the release card - checking, found, found but unusable here, or GitHub unreachable:
func _show_release() -> void:
	var checking := release.has("checking")
	var found := release.has("version")
	var accent := Color.TRANSPARENT
	#? Only a page GitHub named for the repository's ID: never one found by the name.
	release_page_url = String(release.get("page_url", ""))
	release_link.visible = release_page_url != ""
	retry_button.visible = not checking and not found

	if checking:
		release_title.text = "Checking GitHub…"
		release_details.text = "Looking for %s, in github.com/%s." % [_release_wording(), release_source.repository]
	elif found:
		release_title.text = "%s %s" % [_package_title(), release["version"]]
		var details := PackedStringArray()
		if release["date"] != "":
			details.append("Released %s" % release["date"])
		if release.has("asset_name"):
			details.append("%s  ·  %s" % [release["asset_name"], Utils.readable_size(release["asset_size"])])
		else:
			details.append("The newest release on GitHub")
		release_details.text = "  ·  ".join(details)
	else:
		release_title.text = "No release to download"
		release_details.text = "From github.com/%s." % release_source.repository

	release_status.visible = release.has("error")
	if release.has("error"):
		if release.has("usable_elsewhere"):
			#? A good release, just not for this wizard (already installed...).
			accent = Style.color("success_color")
			release_status_icon.texture = Style.icon("StatusSuccess")
		elif found:
			#? GitHub answered, but its release can't be installed by Candy Wizard.
			accent = Style.color("warning_color")
			release_status_icon.texture = Style.icon("StatusWarning")
		else:
			accent = Style.color("error_color")
			release_status_icon.texture = Style.icon("StatusError")
		release_status_label.text = release["error"]
	release_card.get_parent().add_theme_stylebox_override("panel", Style.card(accent))


#* No release repository is set up - the zip is the only source, so the choice is hidden:
func _use_zip_only() -> void:
	release = {"error": "No release repository is set up."}
	source_prompt.text = _zip_only_prompt()
	source_prompt.visible = true
	github_option.visible = false
	release_card.get_parent().visible = false
	zip_option.visible = false
	zip_option.button_pressed = true
	_update_source_controls()


func _update_source_controls() -> void:
	github_option.disabled = release.has("error") or release.has("checking")
	zip_browse_button.disabled = not zip_option.button_pressed
	_update_buttons()


#* Whether the release page has a choice that can be used:
func _source_chosen() -> bool:
	if github_option.button_pressed:
		return release.has("asset_url") and not release.has("error")
	return zip_path_edit.text != ""


func _on_download_progress(downloaded: int, total: int) -> void:
	if total > 0:
		source_progress.max_value = total
		source_progress.value = downloaded


#* Gets the chosen release and checks it, returning whether it can be used:
func _prepare_package() -> bool:
	var chosen := ""
	if github_option.button_pressed:
		chosen = "github:" + String(release.get("version", ""))
	else:
		chosen = "zip:" + zip_path_edit.text
	var blocking := _blocking_problem()
	if blocking != "":
		return _prepare_failed(blocking)
	if package != null and prepared_from == chosen:
		return true

	busy = true
	_update_buttons()
	var zip_path := ""
	if github_option.button_pressed:
		download_path = Utils.TEMP_FOLDER.path_join(release["asset_name"])
		source_progress.value = 0
		source_progress.visible = true
		var download_error: String = await release_source.download(release["asset_url"], download_path)
		source_progress.visible = false
		if download_error != "":
			return _prepare_failed(download_error)
		zip_path = download_path
		source_text = "GitHub release %s" % release["version"]
	else:
		zip_path = zip_path_edit.text
		source_text = "zip file %s" % zip_path.get_file()

	var opened = Package.new()
	if _uses_wizard_releases():
		opened.use_wizard_package()
	var error: String = opened.open(zip_path)
	if error == "":
		error = opened.check_compatibility(wizard_version)
	if error == "":
		error = _version_problem(opened.version())
	if error == "":
		error = opened.verify()
	if error != "":
		opened.close()
		return _prepare_failed(error)
	if package != null:
		package.close()
	package = opened
	prepared_from = chosen
	_build_question_rows()
	busy = false
	_update_buttons()
	return true


func _prepare_failed(message: String) -> bool:
	package = null
	prepared_from = ""
	error_label.text = message
	busy = false
	_update_buttons()
	return false


func _close() -> void:
	if busy and release_source != null:
		release_source.cancel()
	if download_path != "" and FileAccess.file_exists(download_path):
		DirAccess.remove_absolute(download_path)
	if package != null:
		package.close()
	super()


#==============================================================================
#  NOTES
#==============================================================================

#? The release's pre notes (BBCode): the general ones, then this wizard's. A release without
#? any skips the page.

func _build_notes_page() -> Control:
	notes_text = _rich_text()
	notes_text.meta_clicked.connect(func(meta: Variant) -> void: Utils.open_web_link(str(meta)))
	return notes_text


#* Which notes this wizard shows (Utils.NOTES_INSTALL or NOTES_UPDATE):
func _notes_flow() -> String:
	return Utils.NOTES_INSTALL


func _has_pre_notes() -> bool:
	return package != null and package.wizard_notes("pre", _notes_flow()) != ""


func _fill_notes_page() -> void:
	notes_text.text = package.wizard_notes("pre", _notes_flow())
	notes_text.scroll_to_line(0)


#==============================================================================
#  QUESTIONS
#==============================================================================

#? A manifest question: "title", "text", "options" ([{label, value}]), and optionally "custom"
#? (free answer allowed), "tags" (the {tags} it may use), "help" (shown with it), "preview"
#? (an example, "{value}" replaced by the answer) and "preview_tags" (sample tag values).

func _build_questions_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	questions_box = VBoxContainer.new()
	questions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	questions_box.add_theme_constant_override("separation", Style.px(12))
	scroll.add_child(questions_box)
	return scroll


func _build_question_rows() -> void:
	question_rows.clear()
	if questions_box == null:
		#? No questions page (Candy Wizard's releases have no questions).
		return
	for child in questions_box.get_children():
		child.queue_free()
	question_rows.clear()
	for question in _questions_to_ask():
		question_rows.append(_build_question_row(question))


func _build_question_row(question: Dictionary) -> Dictionary:
	var box := Style.card_box(questions_box)
	box.add_theme_constant_override("separation", Style.px(8))
	Style.card_title(box, "Edit", String(question.get("title", "")))
	box.add_child(_wrapped_label(String(question.get("text", ""))))

	var options := OptionButton.new()
	for option in question.get("options", []):
		options.add_item(String(option.get("label", "")))
	var allows_custom := bool(question.get("custom", false))
	if allows_custom:
		options.add_item("Custom…")
	box.add_child(options)

	var custom_edit := LineEdit.new()
	custom_edit.placeholder_text = "Your own value"
	box.add_child(custom_edit)
	var help_label := Style.caption(String(question.get("help", "")))
	box.add_child(help_label)
	var preview_label := Style.caption("")
	preview_label.add_theme_font_override("font", Style.font("source"))
	box.add_child(preview_label)
	var problem_label := _wrapped_label("")
	problem_label.add_theme_color_override("font_color", Style.color("error_color"))
	box.add_child(problem_label)

	var row := {
		"question": question,
		"options": options,
		"custom": custom_edit,
		"help": help_label,
		"preview": preview_label,
		"problem": problem_label,
	}

	#? Start on the value the release ships with.
	var default_value = question.get("default")
	var selected := -1
	var option_list: Array = question.get("options", [])
	for index in option_list.size():
		var option_value = option_list[index].get("value")
		if typeof(option_value) == typeof(default_value) and option_value == default_value:
			selected = index
			break
	if selected == -1 and allows_custom and default_value != null:
		selected = option_list.size()
		custom_edit.text = str(default_value)
	if selected == -1:
		selected = 0
	options.select(selected)

	options.item_selected.connect(func(_index: int) -> void: _refresh_question(row))
	custom_edit.text_changed.connect(func(_text: String) -> void: _refresh_question(row))
	_refresh_question(row)
	return row


func _is_custom(row: Dictionary) -> bool:
	return row["options"].selected >= row["question"].get("options", []).size()


func _question_value(row: Dictionary) -> Variant:
	if _is_custom(row):
		return row["custom"].text.strip_edges()
	return row["question"]["options"][row["options"].selected].get("value")


#* Why an answer can't be used, or "":
func _question_problem(row: Dictionary) -> String:
	if not _is_custom(row):
		return ""
	var value := String(_question_value(row))
	var tags: Array = row["question"].get("tags", [])
	if tags.is_empty():
		return ""
	var tag_regex := RegEx.create_from_string(r"\{[^{}]*\}")
	for found in tag_regex.search_all(value):
		if not found.get_string() in tags:
			return "Unknown tag %s. The tags are %s." % [found.get_string(), ", ".join(PackedStringArray(tags))]
	return ""


func _refresh_question(row: Dictionary) -> void:
	var custom := _is_custom(row)
	row["custom"].visible = custom
	row["help"].visible = custom and row["help"].text != ""
	var problem := _question_problem(row)
	row["problem"].text = problem
	row["problem"].visible = problem != ""
	var preview_template := String(row["question"].get("preview", ""))
	row["preview"].visible = preview_template != "" and problem == ""
	if preview_template != "":
		var value := str(_question_value(row))
		var tag_samples: Dictionary = row["question"].get("preview_tags", {})
		for tag in tag_samples:
			value = value.replace(tag, String(tag_samples[tag]))
		var example := preview_template.replace("{value}", value)
		#? Collapse the empty folders an empty answer leaves in the example.
		var scheme_end := example.find("://")
		if scheme_end != -1:
			var start := example.substr(0, scheme_end + 3)
			var rest := example.substr(scheme_end + 3)
			while "//" in rest:
				rest = rest.replace("//", "/")
			example = start + rest
		row["preview"].text = "Example: " + example


func _check_answers() -> bool:
	for row in question_rows:
		var problem := _question_problem(row)
		if problem != "":
			error_label.text = "%s: %s" % [row["question"].get("title", ""), problem]
			return false
	return true


func _answers() -> Dictionary:
	var answers := {}
	for row in question_rows:
		answers[String(row["question"].get("id", ""))] = _question_value(row)
	return answers


func _dim(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.dim().to_html(false), text]
