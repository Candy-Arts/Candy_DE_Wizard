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


const CandyDEData = preload("../Candy_DE_Data.gd")
const Style = preload("../UI_Style.gd")
const DialogueOptions = preload("../Dialogue_Options.gd")
const ConverterWizard = preload("../Converter_Wizard.gd")

#^ 1.1 dialogues listed by name, before "and N more":
const LISTED_DIALOGUES := 5

var stale := false						#/ The files changed while the tool was hidden
var converter_wizard: Window = null

var status_card: PanelContainer
var status_icon: TextureRect
var status_title: Label
var status_details: Label
var convert_button: Button
var list_text: RichTextLabel


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

	var box := Style.card_box(cards)
	status_card = box.get_parent()
	status_card.custom_minimum_size.x = Style.px(380)
	Style.card_title(box, "FileList", "Dialogue formats")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Style.px(10))
	box.add_child(row)
	status_icon = Style.icon_rect(null, 24)
	row.add_child(status_icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	status_title = Style.label("")
	texts.add_child(status_title)
	status_details = Style.caption("")
	texts.add_child(status_details)
	convert_button = Style.button("Convert 1.1 Dialogues…", "Reload", _open_converter)
	convert_button.tooltip_text = "Convert the dialogues written for Candy DE 1.1.3 to the 1.2 format. Each is backed up beside it first."
	convert_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(convert_button)

	var list_box := Style.card_box(cards)
	list_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.get_parent().custom_minimum_size.x = Style.px(260)
	Style.card_title(list_box, "Info", "In the 1.1 format")
	list_text = Style.rich_text(false)
	list_text.fit_content = true
	list_text.meta_clicked.connect(func(path) -> void: EditorInterface.get_file_system_dock().navigate_to_path(str(path)))
	list_box.add_child(list_text)

	visibility_changed.connect(func() -> void:
		if stale and is_visible_in_tree():
			refresh())
	refresh()


func _exit_tree() -> void:
	if converter_wizard != null and is_instance_valid(converter_wizard):
		converter_wizard.queue_free()


#* Read the dialogues' formats again (on file changes):
func refresh() -> void:
	if status_card == null or not CandyDEData.is_available():
		return
	#% Deferred while hidden (every dialogue is read):
	if not is_visible_in_tree():
		stale = true
		return
	stale = false
	var found := DialogueOptions.dialogue_formats()
	var to_convert: Array = found["convert"]
	list_text.clear()
	Style.make_plain(convert_button)
	convert_button.disabled = to_convert.is_empty()
	if found["problem"] != "":
		_show_status("StatusWarning", Style.color("warning_color"), "Can't read the dialogues", found["problem"])
	elif to_convert.is_empty() and found["total"] == 0:
		_show_status("Info", Color.TRANSPARENT, "No dialogues yet", "In %s." % found["folder"])
	elif to_convert.is_empty() and not found["unreadable"].is_empty():
		_show_status("Info", Color.TRANSPARENT, "Nothing left to convert", "%d in %s, of which %d can't be converted." % [found["total"], found["folder"], found["unreadable"].size()])
	elif to_convert.is_empty():
		_show_status("StatusSuccess", Style.color("success_color"), "Every dialogue is in the 1.2 format", "%d in %s." % [found["total"], found["folder"]])
	else:
		_show_status("StatusWarning", Style.color("warning_color"), "%d dialogue%s to convert" % [to_convert.size(), _plural(to_convert.size())],
			"Written for Candy DE 1.1.3: 1.2 can't run %s until %s converted." % [_them(to_convert.size()), _they_are(to_convert.size())])
		Style.make_primary(convert_button)

	if to_convert.is_empty():
		list_text.push_color(Style.dim())
		list_text.add_text("Dialogues written for Candy DE 1.1.3 show here. The converter rewrites them for 1.2, as Candy Dialogue Creator's Dialogue Converter does.")
		list_text.pop()
		list_text.newline()
	else:
		var prefix := String(found["folder"]).trim_suffix("/") + "/"
		for index in min(to_convert.size(), LISTED_DIALOGUES):
			var path: String = to_convert[index]
			Style.rich_item(list_text, "File", "[url=%s]%s[/url]" % [path, Style.escaped(path.trim_prefix(prefix))])
		if to_convert.size() > LISTED_DIALOGUES:
			Style.rich_item(list_text, "GuiEllipsis", "[color=#%s]and %d more[/color]" % [Style.dim().to_html(false), to_convert.size() - LISTED_DIALOGUES])
	var unreadable: Array = found["unreadable"]
	if not unreadable.is_empty():
		Style.rich_item(list_text, "StatusWarning", Style.colored("%d file%s can't be converted: the converter's first page says why." % [unreadable.size(), _plural(unreadable.size())], "warning_color"))
		#? The converter lists them, even with nothing to convert:
		convert_button.disabled = false


func _show_status(icon_name: String, accent: Color, title: String, details: String) -> void:
	status_icon.texture = Style.icon(icon_name)
	status_title.text = title
	status_details.text = details
	status_card.add_theme_stylebox_override("panel", Style.card(accent))


func _open_converter() -> void:
	if converter_wizard != null and is_instance_valid(converter_wizard):
		converter_wizard.grab_focus()
		return
	converter_wizard = ConverterWizard.new()
	converter_wizard.wizard_version = _wizard_version()
	converter_wizard.wizard_closed.connect(refresh)
	EditorInterface.get_base_control().add_child(converter_wizard)
	converter_wizard.popup_centered(converter_wizard.min_size)


#* Candy Wizard's version, from the dock:
func _wizard_version() -> String:
	var node := get_parent()
	while node != null:
		if "wizard_version" in node:
			return String(node.get("wizard_version"))
		node = node.get_parent()
	return ""


func _plural(count: int) -> String:
	if count == 1:
		return ""
	return "s"


func _them(count: int) -> String:
	if count == 1:
		return "it"
	return "them"


func _they_are(count: int) -> String:
	if count == 1:
		return "it's"
	return "they're"
