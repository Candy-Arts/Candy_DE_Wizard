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


const Utils = preload("../Wizard_Utils.gd")
const Style = preload("../UI_Style.gd")
const ReleaseSource = preload("../Release_Source.gd")
const DocsSource = preload("../Docs_Source.gd")
const Package = preload("../Package.gd")
const DatabaseInstaller = preload("../Database_Installer.gd")
const DocsFiles = preload("../Docs_Files.gd")

#^ Emitted after a look, install or download, for the dock's drop-down:
signal updates_changed

#^ Seconds between automatic looks on GitHub:
const UPDATE_CHECK_INTERVAL := 24 * 60 * 60
#^ Locally changed files the confirmation lists by name:
const LISTED_FILES := 8

#^ Checked against a release's wizard_min. Set before adding the tool:
var wizard_version := ""
#^ Tests only - a local stand-in for GitHub's API and raw files:
var test_api_base := ""
var test_raw_base := ""

var database_status: Dictionary = {}		#/ {"icon", "label", "button"}
var docs_status: Dictionary = {}			#/ Set id -> {"icon", "label", "button"}
var candy_card: Control					#/ Hidden until Candy Database is installed, like others_card
var others_card: Control					#/ The databases unrelated to Candy DE, hidden when there's none
var others_rows: GridContainer
var other_rows: PackedStringArray = []		#/ What others_rows shows - "id\ntitle" each
#^ Whether the Candy Database card's button checks for updates, rather than installing or updating:
var database_button_checks := false
var progress_bar: ProgressBar
var result_text: RichTextLabel
var busy := false
var checking := false
#^ Automatic look done this session:
#? Even if it failed: a failed look isn't kept, so it would repeat each time the tool is shown.
var release_looked := false
var docs_looked := false


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

	database_status = _add_card(cards, "Help", "Candy Database", "The documentation browser.", _on_database_button)
	_add_result(database_status["box"])
	var candy_rows := _add_docs_card(cards, "Candy Dialogue Engine", "Related documentation.")
	candy_card = candy_rows.get_parent().get_parent()
	candy_card.visible = false
	for docs_set in Utils.DOCS_SETS:
		docs_status[docs_set["id"]] = _add_docs_row(candy_rows, docs_set)
	others_rows = _add_docs_card(cards, "Other Documentation", "Unrelated to Candy Dialogue Engine.")
	others_card = others_rows.get_parent().get_parent()
	others_card.visible = false

	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			check(false, true))
	refresh()


#* Add the progress and result under a card's status:
func _add_result(box: VBoxContainer) -> void:
	box.get_parent().custom_minimum_size.x = Style.px(270)
	var status_row := database_status["icon"].get_parent() as Control
	progress_bar = ProgressBar.new()
	progress_bar.max_value = 1.0
	progress_bar.step = 0.001
	progress_bar.visible = false
	box.add_child(progress_bar)
	box.move_child(progress_bar, status_row.get_index() + 1)
	result_text = Style.rich_text(false)
	result_text.fit_content = true
	result_text.size_flags_vertical = Control.SIZE_FILL
	result_text.visible = false
	result_text.meta_clicked.connect(_on_meta_clicked)
	box.add_child(result_text)
	box.move_child(result_text, progress_bar.get_index() + 1)


#* Add a card listing documentation, return the grid its rows go in (_add_docs_row()):
func _add_docs_card(parent: Node, title: String, caption: String) -> GridContainer:
	var box := Style.card_box(parent)
	box.get_parent().custom_minimum_size.x = Style.px(380)
	Style.card_title(box, "HelpSearch", title)
	var caption_label := Style.caption(caption)
	caption_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(caption_label)
	var rows := GridContainer.new()
	rows.columns = 4	#/ Title, status icon, status, button
	rows.add_theme_constant_override("h_separation", Style.px(6))
	rows.add_theme_constant_override("v_separation", Style.px(4))
	box.add_child(rows)
	return rows


#* Add a docs set's row - its title, status line and action button:
func _add_docs_row(rows: GridContainer, docs_set: Dictionary) -> Dictionary:
	var title_label := Style.label(docs_set["title"], "bold")
	title_label.custom_minimum_size.x = Style.px(150)
	rows.add_child(title_label)
	var status_icon := Style.icon_rect(null, 16)
	rows.add_child(status_icon)
	var status_label := Style.label("")
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(status_label)
	var button := Style.button("", "AssetLib", _download_docs.bind(docs_set))
	rows.add_child(button)
	return {"icon": status_icon, "label": status_label, "button": button}


#* Give each other database a row, if they changed:
func _sync_other_rows(sets: Array) -> void:
	var listed: PackedStringArray = []
	for docs_set in sets:
		if docs_set.get("other", false):
			listed.append("%s\n%s" % [docs_set["id"], docs_set["title"]])	#/ A new title remakes the rows too
	if listed == other_rows:
		return
	for row in other_rows:
		docs_status.erase(row.get_slice("\n", 0))
	for child in others_rows.get_children():
		others_rows.remove_child(child)
		child.queue_free()
	other_rows = listed
	for docs_set in sets:
		if docs_set.get("other", false):
			docs_status[docs_set["id"]] = _add_docs_row(others_rows, docs_set)


#* Add a card with a status line and an action button:
func _add_card(parent: Node, icon_name: String, title: String, caption: String, action: Callable) -> Dictionary:
	var box := Style.card_box(parent)
	box.get_parent().custom_minimum_size.x = Style.px(230)
	Style.card_title(box, icon_name, title)
	var caption_label := Style.caption(caption)
	caption_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(caption_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(6))
	box.add_child(row)
	var status_icon := Style.icon_rect(null, 16)
	row.add_child(status_icon)
	var status_label := Style.label("")
	row.add_child(status_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var button := Style.button("", "AssetLib", action)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(button)
	return {"box": box, "icon": status_icon, "label": status_label, "button": button}


#==============================================================================
#  STATUS
#==============================================================================

#* Show what's installed and downloaded, and what GitHub had at the last look (on file changes):
func refresh() -> void:
	if result_text == null:
		return
	var installed := Utils.installed_database_version()
	_refresh_database(installed)
	var record := Utils.read_database_record()
	var trees: Dictionary = Utils.last_update_check(Utils.SETTING_DOCS_CHECK).get("trees", {})
	var sets := Utils.docs_sets()
	_sync_other_rows(sets)
	#? The documentation goes in Candy Database's folder: no card until it's there.
	candy_card.visible = installed != ""
	others_card.visible = installed != "" and not other_rows.is_empty()
	for docs_set in sets:
		_refresh_docs(docs_set, record, trees)


func _refresh_database(installed: String) -> void:
	var button: Button = database_status["button"]
	button.disabled = busy or checking
	Style.make_plain(button)
	button.icon = Style.icon("AssetLib")
	database_button_checks = false
	if FileAccess.file_exists(Utils.DATABASE_BUILDER_PATH):
		_set_status(database_status, Style.icon("Info"), "Development project.", Style.dim())
		database_status["label"].tooltip_text = "This is Candy Database's development project: its folder is the source, so Candy Wizard never installs or updates it here."
		_show_check_button(button)
		return
	database_status["label"].tooltip_text = ""
	var latest := String(Utils.last_update_check(Utils.SETTING_DATABASE_UPDATE_CHECK).get("version", ""))
	if installed == "":
		_set_status(database_status, Style.cross_icon(16), "Not installed.", Style.color("font_color"))
		button.text = "Install Candy Database"
		button.tooltip_text = "Download Candy Database's latest release from GitHub, and install it in %s." % Utils.DATABASE_FOLDER
		Style.make_primary(button)
	elif latest != "" and Utils.compare_versions(latest, installed) > 0:
		_set_status(database_status, Style.icon("StatusWarning"), "%s is out (%s here)." % [latest, installed], Style.color("warning_color"))
		button.text = "Update to %s" % latest
		button.icon = Style.icon("Reload")
		button.tooltip_text = "Update Candy Database to %s. The documentation and files of your own in its folder are kept." % latest
		Style.make_primary(button)
	else:
		if EditorInterface.is_plugin_enabled(Utils.DATABASE_FOLDER.get_file()):
			_set_status(database_status, Style.icon("StatusSuccess"), "%s is installed." % installed, Style.color("font_color"))
		else:
			_set_status(database_status, Style.icon("StatusWarning"), "%s is installed, but off." % installed, Style.color("warning_color"))
			database_status["label"].tooltip_text = "Turn it on in Project > Project Settings > Plugins."
		_show_check_button(button)


#* Make the Candy Database card's button Check for Updates:
func _show_check_button(button: Button) -> void:
	database_button_checks = true
	button.text = "Check for Updates"
	button.icon = Style.icon("Reload")
	button.tooltip_text = "Look on GitHub now for a newer Candy Database and newer documentation."


#* Install, update, or check for updates, as the button says:
func _on_database_button() -> void:
	if database_button_checks:
		check(true, true)
	else:
		_install_database()


func _refresh_docs(docs_set: Dictionary, record: Dictionary, trees: Dictionary) -> void:
	var status: Dictionary = docs_status[docs_set["id"]]
	var button: Button = status["button"]
	button.disabled = busy
	button.icon = Style.icon("AssetLib")
	Style.make_plain(button)
	status["label"].tooltip_text = ""
	var downloaded = record.get("docs", {}).get(docs_set["id"], {})
	var on_github := String(trees.get(docs_set["id"], "?"))
	if not downloaded is Dictionary or downloaded.is_empty():
		if on_github == "":
			_set_status(status, Style.icon("Info"), "Not on GitHub yet.", Style.dim())
		else:
			_set_status(status, Style.cross_icon(16), "Not downloaded.", Style.color("font_color"))
			Style.make_primary(button)
		button.text = "Download"
		button.tooltip_text = "Download the documentation from GitHub into %s." % Utils.DOCS_DATABASES_FOLDER
		return
	var date := Utils.readable_date(String(downloaded.get("date", "")))
	if on_github != "" and on_github != "?" and on_github != String(downloaded.get("zip_hash", "")):
		_set_status(status, Style.icon("StatusWarning"), "Updated on GitHub.", Style.color("warning_color"))
		status["label"].tooltip_text = "Downloaded %s." % date
		button.text = "Update"
		button.icon = Style.icon("Reload")
		button.tooltip_text = "Download what changed on GitHub since %s." % date
		Style.make_primary(button)
	else:
		_set_status(status, Style.icon("StatusSuccess"), "Downloaded.", Style.color("font_color"))
		status["label"].tooltip_text = "Downloaded %s." % date
		button.text = "Download Again"
		button.tooltip_text = "Download the files that are missing here or differ from GitHub's."


func _set_status(status: Dictionary, icon: Texture2D, text: String, text_color: Color) -> void:
	status["icon"].texture = icon
	status["label"].text = text
	status["label"].add_theme_color_override("font_color", text_color)


#==============================================================================
#  LOOKING ON GITHUB
#==============================================================================

#* Look up Candy Database's latest release and the docs zips' hashes:
#? forced: now, showing the result; else at most once a day, quietly.
#? everything: also what isn't here yet (tool shown); else only updates (the dock's check).
func check(forced: bool, everything: bool) -> bool:
	if busy or checking:
		return false
	var now := Time.get_unix_time_from_system()
	var problems: PackedStringArray = []
	var installed := Utils.installed_database_version() != ""
	var downloaded = Utils.read_database_record().get("docs", {})
	var look_for_release := not FileAccess.file_exists(Utils.DATABASE_BUILDER_PATH) and (everything or installed)
	var look_for_docs: bool = everything or (installed and downloaded is Dictionary and not downloaded.is_empty())
	var last_release := Utils.last_update_check(Utils.SETTING_DATABASE_UPDATE_CHECK)
	var last_docs := Utils.last_update_check(Utils.SETTING_DOCS_CHECK)
	look_for_release = look_for_release and (forced or (not release_looked and now - float(last_release.get("time", 0.0)) >= UPDATE_CHECK_INTERVAL))
	look_for_docs = look_for_docs and (forced or (not docs_looked and now - float(last_docs.get("time", 0.0)) >= UPDATE_CHECK_INTERVAL))
	if not look_for_release and not look_for_docs:
		return false
	if not forced:
		release_looked = release_looked or look_for_release
		docs_looked = docs_looked or look_for_docs
	checking = true
	refresh()
	if forced:
		_show_working("Looking on GitHub…")

	if look_for_release:
		var source := _new_release_source()
		var latest: Dictionary = await source.fetch_latest_release()
		source.queue_free()
		Utils.remember_latest_release(Utils.SETTING_DATABASE_UPDATE_CHECK, latest)
		if latest.has("error"):
			problems.append("Candy Database: " + String(latest["error"]))

	if look_for_docs:
		var looked: Dictionary = {}
		for docs_set in Utils.DOCS_SETS:
			var key := "%s@%s" % [docs_set["repository"], docs_set["branch"]]
			if looked.has(key):
				continue
			var source := _new_docs_source()
			var tree: Dictionary = await source.fetch_tree(docs_set["repository"], int(docs_set["repository_id"]), docs_set["branch"])
			source.queue_free()
			looked[key] = true
			if tree.has("error"):
				problems.append("Documentation: " + String(tree["error"]))
			else:
				_remember_docs_tree(docs_set["repository"], docs_set["branch"], tree)

	checking = false
	refresh()
	updates_changed.emit()
	if forced:
		_hide_progress()
		if problems.is_empty():
			_show("", [["StatusSuccess", "Checked GitHub.", Style.color("success_color")]])
		else:
			var lines := []
			for problem in problems:
				lines.append(["StatusWarning", Style.colored(Style.escaped(problem), "warning_color"), Style.color("warning_color")])
			_show("", lines)
	return true	#/ GitHub was asked


#* What GitHub has newer, as last looked ("Candy Database 1.0.1", "Candy Dialogue Engine documentation"):
static func updates_waiting() -> PackedStringArray:
	var waiting: PackedStringArray = []
	var installed := Utils.installed_database_version()
	if installed == "":
		return waiting
	var latest := String(Utils.last_update_check(Utils.SETTING_DATABASE_UPDATE_CHECK).get("version", ""))
	if latest != "" and Utils.compare_versions(latest, installed) > 0 and not FileAccess.file_exists(Utils.DATABASE_BUILDER_PATH):
		waiting.append("Candy Database %s" % latest)
	var trees = Utils.last_update_check(Utils.SETTING_DOCS_CHECK).get("trees", {})
	var downloaded = Utils.read_database_record().get("docs", {})
	if not trees is Dictionary or not downloaded is Dictionary:
		return waiting
	for docs_set in Utils.docs_sets():
		var entry = downloaded.get(docs_set["id"], {})
		var on_github := String(trees.get(docs_set["id"], ""))
		if entry is Dictionary and not entry.is_empty() and on_github != "" and on_github != String(entry.get("zip_hash", "")):
			waiting.append(_docs_name(docs_set))
	return waiting


#* A docs set's name in messages ("Candy Database documentation"), apart from Candy Database itself:
static func _docs_name(docs_set: Dictionary) -> String:
	return "%s documentation" % docs_set["title"]


#* Store the zip hashes of a branch's sets ("" if missing on GitHub), and the other databases it has:
func _remember_docs_tree(repo: String, branch: String, tree: Dictionary) -> void:
	var last := Utils.last_update_check(Utils.SETTING_DOCS_CHECK)
	var trees = last.get("trees", {})
	if not trees is Dictionary:
		trees = {}
	var others: PackedStringArray = []
	if repo == Utils.CANDY_ARTS_GITHUB_REPOSITORY and branch == "main":
		others = Utils.other_docs_databases(tree)
	elif last.get("others") is Array:
		others = PackedStringArray(last["others"])
	for docs_set in Utils.docs_sets(Array(others)):
		if docs_set["repository"] == repo and docs_set["branch"] == branch:
			trees[docs_set["id"]] = String(tree["files"].get(Utils.docs_zip_path(docs_set), ""))
	EditorInterface.get_editor_settings().set_setting(Utils.SETTING_DOCS_CHECK, {"time": Time.get_unix_time_from_system(), "trees": trees, "others": Array(others)})


func _new_release_source() -> Node:
	var source := ReleaseSource.new()
	source.use_database_repository()
	if test_api_base != "":
		source.api_base = test_api_base
	add_child(source)
	return source


func _new_docs_source() -> Node:
	var source := DocsSource.new()
	if test_api_base != "":
		source.api_base = test_api_base
	if test_raw_base != "":
		source.raw_base = test_raw_base
	add_child(source)
	return source


#==============================================================================
#  CANDY DATABASE
#==============================================================================

func _install_database() -> void:
	if busy:
		return
	_set_busy(true)
	_show_working("Looking for Candy Database's latest release…")
	var error: String = await _run_database_install()
	_set_busy(false)
	_hide_progress()
	updates_changed.emit()
	if error != "":
		_show("Candy Database", [["StatusWarning", Style.colored(Style.escaped(error), "warning_color"), Style.color("warning_color")]])


#* Download, check and install the latest release (asking before an update):
func _run_database_install() -> String:
	var source := _new_release_source()
	var latest: Dictionary = await source.fetch_latest_release()
	Utils.remember_latest_release(Utils.SETTING_DATABASE_UPDATE_CHECK, latest)
	if latest.has("error"):
		source.queue_free()
		return latest["error"]
	var zip_path := Utils.TEMP_FOLDER.path_join(String(latest["asset_name"]))
	source.download_progress.connect(func(done: int, total: int) -> void:
		if total > 0:
			_show_progress(float(done) / total * 0.5, "Downloading Candy Database %s… %s / %s" % [latest["version"], Utils.readable_size(done), Utils.readable_size(total)]))
	var error: String = await source.download(String(latest["asset_url"]), zip_path)
	source.queue_free()
	if error != "":
		return error

	var package := Package.new()
	package.use_database_package()
	error = package.open(zip_path)
	if error == "":
		error = package.check_compatibility(wizard_version)
	if error == "":
		error = package.verify()
	var installer := DatabaseInstaller.new()
	if error == "":
		installer.package = package
		installer.plan()
		error = installer.problem
	if error == "" and installer.installed_version != "":
		var question := "Update Candy Database %s to %s?\n\n%d of its files change, %d are added and %d removed. The documentation and the files of your own in its folder are kept.\n\nIts tab closes and opens again: save the page you're editing first." % [installer.installed_version, package.version(), installer.changed.size(), installer.added.size(), installer.removed.size()]
		if installer.unrecorded:
			question += "\n\nIt wasn't installed by Candy Wizard, so files it no longer has can't be told apart from yours: none are removed."
		if not await _confirm(question, "Update"):
			package.close()
			DirAccess.remove_absolute(zip_path)
			_show("Candy Database", [["Info", "Update canceled.", Style.dim()]])
			return ""	#/ Canceled
	if error != "":
		package.close()
		DirAccess.remove_absolute(zip_path)
		return error

	installer.progress.connect(func(fraction: float, message: String) -> void: _show_progress(0.5 + fraction * 0.5, message))
	var updating := installer.installed_version != ""
	var version := package.version()
	error = await installer.install(get_tree())
	package.close()
	DirAccess.remove_absolute(zip_path)
	if error != "":
		return error
	var lines := []
	if updating:
		lines.append(["StatusSuccess", "Updated from %s." % installer.installed_version, Style.color("success_color")])
		if not installer.changed.is_empty() or not installer.removed.is_empty():
			lines.append(["Folder", "Previous files: %s." % _folder_link(installer.backup_folder), Style.dim()])
	else:
		lines.append(["StatusSuccess", "Installed: the Candy DB tab.", Style.color("success_color")])
	_show("Candy Database %s" % version, lines)
	return ""	#/ Done


#==============================================================================
#  DOCUMENTATION
#==============================================================================

func _download_docs(docs_set: Dictionary) -> void:
	if busy:
		return
	_set_busy(true)
	_show_working("Looking at the %s on GitHub…" % _docs_name(docs_set))
	var error: String = await _run_docs_download(docs_set)
	_set_busy(false)
	_hide_progress()
	updates_changed.emit()
	if error != "":
		_show(_docs_name(docs_set), [["StatusWarning", Style.colored(Style.escaped(error), "warning_color"), Style.color("warning_color")]])


#* Download a docs set (asking before replacing locally changed files):
func _run_docs_download(docs_set: Dictionary) -> String:
	var source := _new_docs_source()
	var tree: Dictionary = await source.fetch_tree(docs_set["repository"], int(docs_set["repository_id"]), docs_set["branch"])
	if tree.has("error"):
		source.queue_free()
		return tree["error"]
	_remember_docs_tree(docs_set["repository"], docs_set["branch"], tree)
	var files := DocsFiles.new()
	files.docs_set = docs_set
	files.tree = tree
	if files.is_current():
		source.queue_free()
		_show(_docs_name(docs_set), [["StatusSuccess", "Up to date.", Style.color("success_color")]])
		return ""	#/ Nothing to download
	_show_working("Downloading the %s…" % _docs_name(docs_set))
	await files.fetch(source)
	source.queue_free()
	if files.problem != "":
		return files.problem
	if not files.changed_here.is_empty():
		var names := files.changed_here.slice(0, LISTED_FILES)
		var question := "These files of the %s were changed in this project, and the download replaces or removes them:\n\n%s" % [_docs_name(docs_set), "\n".join(names)]
		if files.changed_here.size() > LISTED_FILES:
			question += "\n…and %d more." % (files.changed_here.size() - LISTED_FILES)
		question += "\n\nA copy of each is kept first."
		if not await _confirm(question, "Replace Them"):
			_show(_docs_name(docs_set), [["Info", "Download canceled.", Style.dim()]])
			return ""	#/ Canceled

	_show_working("Writing the %s…" % _docs_name(docs_set))
	var error := files.apply()
	if not files.to_download.is_empty() or not files.to_remove.is_empty():
		_show_progress(1.0, "Loading the files…")
		await Utils.scan_filesystem(get_tree())
	if error != "":
		return error

	var lines := []
	if files.to_download.is_empty() and files.to_remove.is_empty():
		lines.append(["StatusSuccess", "Up to date.", Style.color("success_color")])
	else:
		var text := "Downloaded %d files" % files.to_download.size()
		if not files.to_remove.is_empty():
			text += ", removed %d" % files.to_remove.size()
		lines.append(["StatusSuccess", text + ".", Style.color("success_color")])
		lines.append(["Help", "Candy DB tab open? Choose Database > Refresh there.", Style.dim()])
	if files.backup_folder != "":
		lines.append(["Folder", "Your replaced files: %s." % _folder_link(files.backup_folder), Style.dim()])
	if not files.left_out.is_empty():
		lines.append(["Info", "Skipped: %s." % Style.code(", ".join(files.left_out)), Style.dim()])
	_show(_docs_name(docs_set), lines)
	return ""	#/ Done


#==============================================================================
#  RESULT CARD
#==============================================================================

func _set_busy(value: bool) -> void:
	busy = value
	refresh()


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


func _show_working(message: String) -> void:
	_show_progress(0.0, message)


func _show_progress(fraction: float, message: String) -> void:
	progress_bar.visible = true
	progress_bar.value = fraction
	result_text.visible = true
	result_text.clear()
	result_text.push_color(Style.dim())
	result_text.add_text(message)
	result_text.pop()


func _hide_progress() -> void:
	progress_bar.visible = false


#* Show a result:
#? title - what it's about, or "" for none. lines - [icon name, BBCode, icon color] each.
func _show(title: String, lines: Array) -> void:
	result_text.visible = true
	result_text.clear()
	if title != "":
		result_text.push_font(Style.font("bold"))
		result_text.add_text(title)
		result_text.pop()
		result_text.newline()
	for line in lines:
		Style.rich_item(result_text, line[0], line[1], line[2])


#* A clickable folder link (_on_meta_clicked()):
func _folder_link(path: String) -> String:
	var shown := path
	if not path.begins_with("res://"):
		shown = ProjectSettings.globalize_path(path)
	return "[url=%s]%s[/url]" % [path, Style.code(shown)]


func _on_meta_clicked(meta: Variant) -> void:
	var path := str(meta)
	if path.begins_with("res://"):
		EditorInterface.get_file_system_dock().navigate_to_path(path)
	else:
		OS.shell_open(ProjectSettings.globalize_path(path))
