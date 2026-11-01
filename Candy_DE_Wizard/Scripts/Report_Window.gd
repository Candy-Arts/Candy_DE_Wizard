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


#+ Shows the 1.1.3 upgrade's report: its BBCode copy (Upgrader.REPORT_BBCODE_PATH), or the
#+ plain report when there's no copy (an upgrade by an older Candy Wizard).

const Upgrader = preload("Upgrader.gd")
#^ Pixels between paragraphs (at the editor's scale):
const REPORT_SPACING := 6

var report_text: RichTextLabel


func _ready() -> void:
	title = "Candy DE %s Upgrade Report" % Upgrader.FROM_VERSION
	super()
	#? Wizards' width, so the report wraps the same:
	min_size = Vector2i(Style.px(840), Style.px(580))
	_show_page(0)
	if FileAccess.file_exists(Upgrader.REPORT_BBCODE_PATH):
		report_text.text = FileAccess.get_file_as_string(Upgrader.REPORT_BBCODE_PATH).strip_edges()
	else:
		report_text.text = Style.escaped(FileAccess.get_file_as_string(Upgrader.REPORT_PATH).strip_edges())
	_update_buttons()


func _build_pages() -> Dictionary:
	report_text = _rich_text()
	#? Room between paragraphs and list items, so the report doesn't read as one block:
	report_text.add_theme_constant_override("paragraph_separation", Style.px(REPORT_SPACING))
	return {0: report_text}


func _subtitle() -> String:
	return "What the upgrade from %s did, and what's left to do by hand." % Upgrader.FROM_VERSION


func _update_buttons() -> void:
	cancel_button.visible = false
	back_button.text = "Open as Text"
	back_button.icon = Style.icon("File")
	back_button.visible = FileAccess.file_exists(Upgrader.REPORT_PATH)
	_set_next("Close", "primary")


#? Back opens the plain report, in the system's text editor.
func _on_back_pressed() -> void:
	OS.shell_open(ProjectSettings.globalize_path(Upgrader.REPORT_PATH))


func _on_next_pressed() -> void:
	_close()


func _on_cancel_pressed() -> void:
	_close()
