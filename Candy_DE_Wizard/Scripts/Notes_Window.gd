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


#^ Set before adding to the tree:
var candy_de_version := ""
var notes := ""

var notes_text: RichTextLabel


func _ready() -> void:
	title = "Candy Dialogue Engine %s" % candy_de_version
	super()
	#? Wizards' width, so notes wrap the same:
	min_size = Vector2i(Style.px(840), Style.px(580))
	_show_page(0)
	notes_text.text = notes
	_update_buttons()


func _build_pages() -> Dictionary:
	notes_text = _rich_text()
	notes_text.meta_clicked.connect(func(meta: Variant) -> void: Utils.open_web_link(str(meta)))
	return {0: notes_text}


func _subtitle() -> String:
	return "Notes from the release, for once it's installed."


func _update_buttons() -> void:
	back_button.visible = false
	cancel_button.visible = false
	_set_next("Close", "primary")


func _on_next_pressed() -> void:
	_close()


func _on_cancel_pressed() -> void:
	_close()
