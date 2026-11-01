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
extends EditorDock


const Utils = preload("Wizard_Utils.gd")
const Style = preload("UI_Style.gd")
const InstallWizard = preload("Install_Wizard.gd")
const RemoveWizard = preload("Remove_Wizard.gd")
const UpdateWizard = preload("Update_Wizard.gd")
const SelfUpdateWizard = preload("Self_Update_Wizard.gd")
const UpgradeWizard = preload("Upgrade_Wizard.gd")
const Upgrader = preload("Upgrader.gd")
const NotesWindow = preload("Notes_Window.gd")
const ReportWindow = preload("Report_Window.gd")
const ReleaseSource = preload("Release_Source.gd")
const FoldersTool = preload("Tools/Folders_Tool.gd")
const SymbolsTool = preload("Tools/Symbols_Tool.gd")
const TestTool = preload("Tools/Test_Tool.gd")
const DialoguesTool = preload("Tools/Dialogues_Tool.gd")
const SymbolUpdaterTool = preload("Tools/Symbol_Updater_Tool.gd")
const DatabaseTool = preload("Tools/Database_Tool.gd")
const DocsTool = preload("Tools/Docs_Tool.gd")
const NewsTool = preload("Tools/News_Tool.gd")
const News = preload("News.gd")
const CandyDEData = preload("Candy_DE_Data.gd")

#^ Last tool shown, per project:
const METADATA_SECTION := "candy_wizard"
const METADATA_TOOL := "tool"
#^ The tool shown first, and when the one shown last isn't listed:
const SETUP_TOOL := "Setup"

#^ Seconds between looks for a newer release:
const UPDATE_CHECK_INTERVAL := 24 * 60 * 60

#^ Update button tooltips, with and without a known newer release:
const UPDATE_TOOLTIP := "Update Candy DE to a newer release, from GitHub or a zip. Your changes are kept."
const CHECK_TOOLTIP := "Look on GitHub for a newer Candy DE release, or update from a zip. Your changes are kept."

#^ Set before adding the dock:
var wizard_version := ""

var wizard: Window = null
var notes_window: Window = null
var report_window: Window = null
var tool_select: OptionButton
#^ Tools, in drop-down order - {"name", "icon", "panel", "needs_candy_de", "group_start"}:
var tools: Array[Dictionary] = []
#^ The next _add_tool() begins a group (_add_tool_separator()):
var next_tool_starts_group := false
var shown_tool := ""

#^ Setup:
var status_card: PanelContainer
var status_icon: TextureRect
var status_title: Label
var status_details: Label
var install_button: Button
var notes_button: Button
var update_button: Button
var remove_button: Button
var upgrade_button: Button
var report_button: Button				#/ The 1.1.3 upgrade's report
var update_checked := false				#/ Asked GitHub this session
var wizard_update_button: Button		#/ In the header, beside Candy Wizard's version
var docs_tool: Control					#/ Docs: looked at by the daily check too
var news_tool: Control					#/ News: looked for by the daily check too


func _init() -> void:
	title = "Candy Dialogue"
	layout_key = "Candy_Wizard"
	default_slot = DOCK_SLOT_BOTTOM
	available_layouts = DOCK_LAYOUT_ALL


func _ready() -> void:
	dock_icon = Style.logo(16)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, Style.px(6))
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Style.px(8))
	margin.add_child(column)

	column.add_child(_build_header())
	#@ The drop-down's order, in groups:
	news_tool = NewsTool.new()
	#? Deferred: the drop-down is rebuilt, and reading news can happen while it's being used.
	news_tool.unread_changed.connect(_update_tool_list, CONNECT_DEFERRED)
	_add_tool(column, "News", "Notification", news_tool, false)
	_add_tool_separator()
	_add_tool(column, "Test", "PlayScene", TestTool.new(), true)
	_add_tool_separator()
	_add_tool(column, "Data", "Script", DatabaseTool.new(), true)
	_add_tool(column, "Folders", "Folder", FoldersTool.new(), true)
	var hooks_tool := DatabaseTool.new()
	hooks_tool.kind = DatabaseTool.HOOKS
	_add_tool(column, "Hook Functions", "Signals", hooks_tool, true)
	_add_tool(column, "Symbols", "KeyboardLabel", SymbolsTool.new(), true)
	_add_tool_separator()
	_add_tool(column, SETUP_TOOL, "Tools", _build_setup(), false)
	docs_tool = DocsTool.new()
	docs_tool.wizard_version = wizard_version
	docs_tool.updates_changed.connect(_update_tool_list)
	_add_tool(column, "Docs", "Help", docs_tool, false)
	_add_tool(column, "Dialogue Converter", "FileList", DialoguesTool.new(), true)
	_add_tool(column, "Symbol Updater", "ReplaceText", SymbolUpdaterTool.new(), true)

	#? Setup the first time, then the tool shown last (saved when one is chosen):
	shown_tool = str(EditorInterface.get_editor_settings().get_project_metadata(METADATA_SECTION, METADATA_TOOL, SETUP_TOOL))
	#? The Dialogue Converter was named Dialogues:
	if shown_tool == "Dialogues":
		shown_tool = "Dialogue Converter"
	tool_select.item_selected.connect(func(index: int) -> void:
		_show_tool(String(tool_select.get_item_metadata(index)))
		EditorInterface.get_editor_settings().set_project_metadata(METADATA_SECTION, METADATA_TOOL, shown_tool)
		_mark_opened(shown_tool))

	EditorInterface.get_resource_filesystem().filesystem_changed.connect(refresh)
	refresh()
	_show_notes_on_start()


#* Header - logo, tool drop-down, Candy Wizard's version:
func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(8))
	row.add_child(Style.icon_rect(Style.logo(22), 22))
	var divider := VSeparator.new()
	divider.custom_minimum_size.x = Style.px(8)
	row.add_child(divider)

	tool_select = OptionButton.new()
	tool_select.tooltip_text = "The Candy Dialogue tool to show."
	tool_select.custom_minimum_size.x = Style.px(130)
	#? The editor's separators are faint in its menus: a lighter line, toward the text color.
	var separator_line := StyleBoxLine.new()
	separator_line.color = Color(Style.color("font_color"), 0.25)
	separator_line.thickness = maxi(Style.px(1), 1)
	separator_line.content_margin_top = Style.px(3)
	separator_line.content_margin_bottom = Style.px(3)
	tool_select.get_popup().add_theme_stylebox_override("separator", separator_line)
	row.add_child(tool_select)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var version := Style.caption("Wizard %s" % wizard_version)
	version.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(version)
	wizard_update_button = Style.button("", "Reload", _open_wizard.bind(SelfUpdateWizard))
	wizard_update_button.flat = true
	#? Hidden in Candy Wizard's development project:
	wizard_update_button.visible = not FileAccess.file_exists(Utils.WIZARD_BUILDER_PATH)
	row.add_child(wizard_update_button)
	return row


#* Add a tool (needs_candy_de = listed only once Candy DE is installed):
func _add_tool(column: VBoxContainer, tool_name: String, tool_icon: String, panel: Control, needs_candy_de: bool) -> void:
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.visible = false
	column.add_child(panel)
	tools.append({"name": tool_name, "icon": tool_icon, "panel": panel, "needs_candy_de": needs_candy_de, "group_start": next_tool_starts_group})
	next_tool_starts_group = false


#* End a group of tools - a separator in the drop-down, between groups with tools listed:
func _add_tool_separator() -> void:
	next_tool_starts_group = true


#* List usable tools; show shown_tool if listed, else Setup:
func _update_tool_list() -> void:
	#? A 1.1.3 install (with a Candy_Properties.gd too) doesn't count:
	var installed := CandyDEData.is_available() and Upgrader.find_install() == ""
	tool_select.clear()
	var listed := false
	var unopened := Utils.unopened_tools()
	var shown_entries: Array[Dictionary] = []
	var any_marked := false
	var separate := false	#/ A group ended after a listed tool
	for entry in tools:
		if entry["group_start"]:
			separate = not shown_entries.is_empty()
		if entry["needs_candy_de"] and not installed:
			continue
		if separate:
			shown_entries.append({"separator": true})
			separate = false
		var icon := Style.icon(entry["icon"])
		var tooltip := ""
		var marked := false
		if entry["panel"] == docs_tool:
			var waiting := DocsTool.updates_waiting()
			if not waiting.is_empty():
				icon = Style.icon("StatusWarning")
				tooltip = "On GitHub: %s." % ", ".join(waiting)
		elif entry["panel"] == news_tool and News.has_unread():
			marked = true
			tooltip = "There's news you haven't read."
		if entry["name"] in unopened:
			marked = true
			if tooltip == "":
				tooltip = "New: open it once to see what it does."
		any_marked = any_marked or marked
		shown_entries.append({"name": entry["name"], "icon": icon, "tooltip": tooltip, "marked": marked})
	for shown in shown_entries:
		if shown.get("separator", false):
			tool_select.add_separator()
			continue
		var icon: Texture2D = shown["icon"]
		#? Every icon gets the mark's room while one has it, so the names stay aligned:
		if any_marked:
			icon = Style.unread_badge(icon, shown["marked"])
		tool_select.add_icon_item(icon, shown["name"])
		tool_select.set_item_metadata(tool_select.item_count - 1, shown["name"])
		tool_select.set_item_tooltip(tool_select.item_count - 1, shown["tooltip"])
		if shown["name"] == shown_tool:
			listed = true
	if listed:
		_show_tool(shown_tool)
	else:
		_show_tool(SETUP_TOOL)


#* A tool chosen in the drop-down loses its "not opened yet" mark:
func _mark_opened(tool_name: String) -> void:
	var unopened := Utils.unopened_tools()
	if tool_name in unopened:
		unopened.erase(tool_name)
		Utils.set_unopened_tools(unopened)
		#? Deferred: the drop-down is still handling the selection.
		_update_tool_list.call_deferred()


func _show_tool(tool_name: String) -> void:
	shown_tool = tool_name
	for entry in tools:
		entry["panel"].visible = entry["name"] == tool_name
	for index in tool_select.item_count:
		if tool_select.get_item_metadata(index) == tool_name:
			tool_select.select(index)


#==============================================================================
#  SETUP
#==============================================================================

#* Setup tool - status card and wizard buttons:
func _build_setup() -> Control:
	var panel := VBoxContainer.new()
	status_card = PanelContainer.new()
	panel.add_child(status_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(14))
	status_card.add_child(row)
	status_icon = Style.icon_rect(null, 36)
	row.add_child(status_icon)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.alignment = BoxContainer.ALIGNMENT_CENTER
	text_column.add_theme_constant_override("separation", Style.px(2))
	row.add_child(text_column)
	status_title = Style.label("", "bold", 1.15)
	text_column.add_child(status_title)
	status_details = Style.caption("")
	text_column.add_child(status_details)

	install_button = Style.button("Install Candy Dialogue Engine", "AssetLib", _open_wizard.bind(InstallWizard))
	install_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Style.make_primary(install_button)
	row.add_child(install_button)
	upgrade_button = Style.button("Upgrade to %s…" % Upgrader.TO_VERSION.trim_suffix(".0"), "Reload", _open_wizard.bind(UpgradeWizard))
	upgrade_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(upgrade_button)
	report_button = Style.button("Upgrade Report", "File", _show_report)
	report_button.tooltip_text = "What the upgrade from %s did, and what's left to do by hand." % Upgrader.FROM_VERSION
	report_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(report_button)
	notes_button = Style.button("Notes", "File", _show_post_notes)
	notes_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(notes_button)
	update_button =Style.button("Update", "Reload", _open_wizard.bind(UpdateWizard))
	update_button.tooltip_text = UPDATE_TOOLTIP
	update_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(update_button)
	remove_button = Style.button("Remove", "Remove", _open_wizard.bind(RemoveWizard))
	remove_button.tooltip_text = "Remove Candy DE from this project."
	remove_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(remove_button)
	return panel


func _exit_tree() -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	if file_system.filesystem_changed.is_connected(refresh):
		file_system.filesystem_changed.disconnect(refresh)
	if wizard != null and is_instance_valid(wizard):
		wizard.queue_free()
	if notes_window != null and is_instance_valid(notes_window):
		notes_window.queue_free()
	if report_window != null and is_instance_valid(report_window):
		report_window.queue_free()


#* Refresh the install status and the tools:
func refresh() -> void:
	if status_card == null:
		return
	_show_newer_wizard()
	_check_for_updates()
	_update_tool_list()
	for entry in tools:
		if entry["panel"].has_method("refresh"):
			entry["panel"].refresh()
	var record := Utils.read_record()
	install_button.visible = false
	notes_button.visible = false
	update_button.visible = false
	remove_button.visible = false
	upgrade_button.visible = false
	report_button.visible = false
	var old_install := ""
	if record.is_empty():
		old_install = Upgrader.find_install()
	if not record.is_empty():
		var installed_version := String(record.get("version", "?"))
		var history: Array = record.get("updates", [])
		var details := "Installed %s, from the %s." % [Utils.readable_date(String(record.get("installed", ""))), String(record.get("source", "?"))]
		if record.get("upgraded_from") is Dictionary:
			var upgraded: Dictionary = record["upgraded_from"]
			details = "Upgraded from %s %s, from the %s." % [String(upgraded.get("version", "?")), Utils.readable_date(String(upgraded.get("date", ""))), String(record.get("source", "?"))]
			report_button.visible = FileAccess.file_exists(_report_path())
		if not history.is_empty():
			var last: Dictionary = history.back()
			details = "Updated %s, from the %s." % [Utils.readable_date(String(last.get("date", ""))), String(last.get("source", "?"))]
		_show_status(Style.icon("StatusSuccess"), "success_color", "Candy DE %s is installed" % installed_version, details)
		if Utils.is_dev_record(record):
			status_details.text += "\nThis is Candy DE's development project, so Candy Wizard won't update or remove it."
		else:
			notes_button.visible = FileAccess.file_exists(Utils.POST_NOTES_PATH)
			notes_button.tooltip_text = "Show the notes of Candy DE %s's release, for once it's installed." % installed_version
			update_button.visible = true
			remove_button.visible = true
			_show_newer_release(installed_version)
	elif old_install != "":
		_show_status(Style.icon("StatusWarning"), "warning_color", "Candy DE %s is installed" % Upgrader.FROM_VERSION,
			"Installed by hand, in %s. Upgrade it to %s: your settings, data and media are carried over, and a report lists what's left to port by hand." % [old_install, Upgrader.TO_VERSION.trim_suffix(".0")])
		upgrade_button.visible = true
		var newer_wizard := Utils.newer_wizard_version(wizard_version)
		upgrade_button.disabled = newer_wizard != ""
		if newer_wizard != "":
			upgrade_button.tooltip_text = "Update Candy Wizard to %s first: Candy DE is only upgraded with the latest Candy Wizard." % newer_wizard
			Style.make_plain(upgrade_button)
		else:
			upgrade_button.tooltip_text = "Upgrade Candy DE %s to %s. A backup of the project is made first." % [Upgrader.FROM_VERSION, Upgrader.TO_VERSION]
			Style.make_primary(upgrade_button)
	elif Utils.candy_de_folder_exists():
		_show_status(Style.icon("StatusWarning"), "warning_color", "Candy DE wasn't installed by Candy Wizard",
			"This project has a Candy_DE folder with no install record, so Candy Wizard leaves it alone.")
	else:
		_show_status(Style.cross_icon(36), "error_color", "Candy Dialogue Engine isn't installed yet",
			"Install it from a release zip. The wizard checks the release first, and can back up the project before changing anything.")
		install_button.visible = true


#* Update button and status for the latest release, as last checked:
func _show_newer_release(installed_version: String) -> void:
	var latest := String(Utils.last_update_check(Utils.SETTING_UPDATE_CHECK).get("version", ""))
	var newer := latest != "" and Utils.compare_versions(latest, installed_version) > 0
	var newer_wizard := Utils.newer_wizard_version(wizard_version)
	update_button.disabled = newer_wizard != ""	#/ Until the newer Candy Wizard is installed
	update_button.tooltip_text = UPDATE_TOOLTIP
	Style.make_plain(update_button)
	if newer:
		update_button.text = "Update to %s" % latest
	elif Utils.GITHUB_REPOSITORY == "":
		#? Zip only:
		update_button.text = "Update"
	else:
		update_button.text = "Check for Updates"
		update_button.tooltip_text = CHECK_TOOLTIP

	if newer_wizard != "":
		update_button.tooltip_text = "Update Candy Wizard to %s first: Candy DE is only updated with the latest Candy Wizard." % newer_wizard
		if newer:
			_set_status_look(Style.minus_icon(36), Style.neutral())
			status_details.text += "\nCandy DE %s is out, but update Candy Wizard to %s first (the button above)." % [latest, newer_wizard]
		else:
			status_details.text += "\nCandy Wizard %s is out: update it (the button above) before updating Candy DE." % newer_wizard
	elif newer:
		_set_status_look(Style.icon("StatusWarning"), Style.color("warning_color"))
		status_details.text += "\nCandy DE %s is out: update to get it." % latest
		Style.make_primary(update_button)


#* Header's self-update button:
func _show_newer_wizard() -> void:
	var latest := Utils.newer_wizard_version(wizard_version)
	if latest != "":
		wizard_update_button.text = "Wizard %s is out" % latest
		wizard_update_button.tooltip_text = "Update Candy Wizard to %s." % latest
		wizard_update_button.flat = false
		Style.make_primary(wizard_update_button)
	else:
		wizard_update_button.text = ""
		wizard_update_button.tooltip_text = "Update Candy Wizard, from GitHub or a zip."
		wizard_update_button.flat = true
		Style.make_plain(wizard_update_button)


#* Daily check for Candy DE, Candy Wizard, the Docs tool's updates and the news, once per session:
func _check_for_updates() -> void:
	if update_checked:
		return
	update_checked = true
	news_tool.check(false)
	var record := Utils.read_record()
	var looked := false
	if not record.is_empty() and not Utils.is_dev_record(record):
		looked = await _check_latest(Utils.SETTING_UPDATE_CHECK, false) or looked
	if not FileAccess.file_exists(Utils.WIZARD_BUILDER_PATH):
		looked = await _check_latest(Utils.SETTING_WIZARD_UPDATE_CHECK, true) or looked
	looked = await docs_tool.check(false, false) or looked
	if looked:
		refresh()


#* Look up the latest release (Candy Wizard's if for_wizard, else Candy DE's), kept in setting. Returns whether GitHub was asked:
func _check_latest(setting: String, for_wizard: bool) -> bool:
	var source := ReleaseSource.new()
	if for_wizard:
		source.use_wizard_repository()
	var last := Utils.last_update_check(setting)
	if source.repository == "" or source.repository_id == 0 or Time.get_unix_time_from_system() - float(last.get("time", 0.0)) < UPDATE_CHECK_INTERVAL:
		source.free()
		return false
	add_child(source)
	var latest: Dictionary = await source.fetch_latest_release()
	source.queue_free()
	#? A failed look isn't kept:
	return Utils.remember_latest_release(setting, latest)


func _show_status(icon: Texture2D, color_name: String, title_text: String, details: String) -> void:
	_set_status_look(icon, Style.color(color_name))
	status_title.text = title_text
	status_details.text = details


#* Status card icon and accent:
func _set_status_look(icon: Texture2D, accent: Color) -> void:
	status_icon.texture = icon
	status_card.add_theme_stylebox_override("panel", Style.card(accent))


#* 1.1.3 upgrade report path:
func _report_path() -> String:
	return Upgrader.REPORT_PATH


#* Open a wizard, one at a time:
func _open_wizard(wizard_script: GDScript) -> void:
	if wizard != null and is_instance_valid(wizard):
		wizard.grab_focus()
		return
	wizard = wizard_script.new()
	wizard.wizard_version = wizard_version
	wizard.wizard_closed.connect(refresh)
	wizard.wizard_closed.connect(_on_wizard_closed.bind(wizard))
	EditorInterface.get_base_control().add_child(wizard)
	wizard.popup_centered(wizard.min_size)


#* Show pending post notes, unless restarting (then _show_notes_on_start()):
func _on_wizard_closed(closed_wizard: Window) -> void:
	if not closed_wizard.restarting and Utils.post_notes_pending():
		_show_post_notes()


#* Show pending post notes once the editor has opened and scanned:
func _show_notes_on_start() -> void:
	if not Utils.post_notes_pending():
		return
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().create_timer(0.5).timeout
	if Utils.post_notes_pending():
		_show_post_notes()


#* Show the 1.1.3 upgrade's report window, one at a time:
func _show_report() -> void:
	if report_window != null and is_instance_valid(report_window):
		report_window.grab_focus()
		return
	report_window = ReportWindow.new()
	report_window.wizard_version = wizard_version
	EditorInterface.get_base_control().add_child(report_window)
	report_window.popup_centered(report_window.min_size)


#* Show the post notes window, one at a time:
func _show_post_notes() -> void:
	Utils.set_post_notes_pending(false)
	if notes_window != null and is_instance_valid(notes_window):
		notes_window.grab_focus()
		return
	if not FileAccess.file_exists(Utils.POST_NOTES_PATH):
		return
	notes_window = NotesWindow.new()
	notes_window.wizard_version = wizard_version
	notes_window.candy_de_version = String(Utils.read_record().get("version", ""))
	notes_window.notes = FileAccess.get_file_as_string(Utils.POST_NOTES_PATH).strip_edges()
	EditorInterface.get_base_control().add_child(notes_window)
	notes_window.popup_centered(notes_window.min_size)
