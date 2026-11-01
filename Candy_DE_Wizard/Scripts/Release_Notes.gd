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
extends RefCounted


const Style = preload("UI_Style.gd")

#^ GitHub alerts - [icon, editor color, title]:
const ALERTS := {
	"NOTE": ["Info", "accent_color", "Note"],
	"TIP": ["Info", "success_color", "Tip"],
	"IMPORTANT": ["Info", "accent_color", "Important"],
	"WARNING": ["StatusWarning", "warning_color", "Warning"],
	"CAUTION": ["StatusError", "error_color", "Caution"],
}

#^ Line break that doesn't end a paragraph or list item:
const LINE_SEPARATOR := "\u2028"

#^ Heading font size factors, by level:
const HEADING_SIZES := [1.3, 1.15, 1.0]

static var _list_item := RegEx.create_from_string(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
static var _heading := RegEx.create_from_string(r"^(#{1,6})\s+(.*?)\s*#*$")
static var _rule := RegEx.create_from_string(r"^([-*_])(\s*\1){2,}$")
static var _alert := RegEx.create_from_string(r"^\[!(\w+)\]\s*$")
static var _html_break := RegEx.create_from_string(r"(?i)<br\s*/?>")
static var _link := RegEx.create_from_string(r"!?\[lb\]([^\]]*)\]\(\s*([^)\s]+)(?:\s+\"[^\"]*\")?\s*\)")
static var _bare_url := RegEx.create_from_string(r"https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'\"]")
static var _bold := RegEx.create_from_string(r"\*\*(?=\S)(.+?)(?<=\S)\*\*|(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)")
static var _italic := RegEx.create_from_string(r"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])|(?<!\w)_(?=[^\s_])(.+?)(?<=[^\s_])_(?!\w)")
static var _strike := RegEx.create_from_string(r"~~(?=\S)(.+?)(?<=\S)~~")


#* Append markdown to text (link_base = base for relative links):
static func write(text: RichTextLabel, markdown: String, link_base: String) -> void:
	var lines := markdown.replace("\r\n", "\n").replace("\t", "    ").split("\n")
	_write_lines(text, lines, link_base)


#* Write lines as blocks:
static func _write_lines(text: RichTextLabel, lines: PackedStringArray, link_base: String) -> void:
	var first := true
	var gap := false				#/ A blank line came before the next block
	var list_indents: Array = []	#/ The indent of each open list level
	var index := 0
	while index < lines.size():
		var line := lines[index]
		var stripped := line.strip_edges()
		index += 1

		if stripped == "":
			gap = not first
			list_indents.clear()
			continue

		#% Quote:
		if stripped.begins_with(">"):
			var quoted := PackedStringArray()
			quoted.append(_unquoted(stripped))
			while index < lines.size() and lines[index].strip_edges().begins_with(">"):
				quoted.append(_unquoted(lines[index].strip_edges()))
				index += 1
			_start_block(text, first, gap)
			_write_quote(text, quoted, link_base)
			first = false
			#? The box already has room under it.
			gap = false
			continue

		#% Code block:
		if stripped.begins_with("```"):
			var code := PackedStringArray()
			while index < lines.size() and not lines[index].strip_edges().begins_with("```"):
				code.append(lines[index])
				index += 1
			index += 1
			_start_block(text, first, gap)
			_write_code(text, code)
			first = false
			gap = false
			continue

		var heading := _heading.search(stripped)
		if heading != null:
			#% Heading, always with room above:
			_start_block(text, first, true)
			var level := heading.get_string(1).length()
			text.push_font(Style.font("bold"))
			text.push_font_size(Style.font_size(HEADING_SIZES[mini(level, HEADING_SIZES.size()) - 1]))
			text.append_text(_inline(heading.get_string(2), link_base))
			text.pop()
			text.pop()
			first = false
			gap = false
			list_indents.clear()
			continue

		if _rule.search(stripped) != null:
			_start_block(text, first, gap)
			_write_rule(text)
			first = false
			gap = false
			continue

		var item := _list_item.search(line)
		if item != null:
			_start_block(text, first, gap)
			var indent := item.get_string(1).length()
			while not list_indents.is_empty() and indent < int(list_indents.back()):
				list_indents.pop_back()
			if list_indents.is_empty() or indent > int(list_indents.back()):
				list_indents.append(indent)
			var bullet := item.get_string(2)
			if bullet in ["-", "*", "+"]:
				bullet = "•"
			#? Indented lines continue the item, joined by LINE_SEPARATOR (a newline would end it):
			var item_bbcode := _inline(item.get_string(3), link_base)
			while index < lines.size() and _continues_item(lines[index]):
				item_bbcode += LINE_SEPARATOR + _inline(lines[index].strip_edges(), link_base)
				index += 1
			_write_list_item(text, list_indents.size() - 1, bullet, item_bbcode)
			first = false
			gap = false
			continue

		_start_block(text, first, gap)
		list_indents.clear()
		text.append_text(_inline(stripped, link_base))
		first = false
		gap = false


#* Whether a line continues the list item above:
static func _continues_item(line: String) -> bool:
	var stripped := line.strip_edges()
	if not line.begins_with(" ") or stripped == "" or _list_item.search(line) != null:
		return false
	return not (stripped.begins_with(">") or stripped.begins_with("```") or _heading.search(stripped) != null)


#* End the line before a block, with room after a blank line:
static func _start_block(text: RichTextLabel, first: bool, gap: bool) -> void:
	if first:
		return
	text.newline()	#/ Before the block, so a quote's box doesn't end on an empty line
	if gap:
		_write_spacer(text, true)


#* Short empty line:
static func _write_spacer(text: RichTextLabel, ended: bool) -> void:
	text.push_font_size(Style.px(6))
	text.add_text(" ")
	#Ł Line break, in the small font too (or the line takes full height):
	if ended:
		text.newline()
	text.pop()


static func _unquoted(line: String) -> String:
	var inner := line.trim_prefix(">")
	if inner.begins_with(" "):
		inner = inner.substr(1)
	return inner


#* Quote box; an alert gets its color, icon and title:
static func _write_quote(text: RichTextLabel, lines: PackedStringArray, link_base: String) -> void:
	var accent := Style.dim()
	var alert: Array = []
	var found := _alert.search(lines[0].strip_edges())
	if found != null and ALERTS.has(found.get_string(1).to_upper()):
		alert = ALERTS[found.get_string(1).to_upper()]
		accent = Style.color(alert[1])
		lines = lines.slice(1)

	#? Two cells: an accent bar, and the quote on a card background.
	var background := Style.card().bg_color
	text.push_table(2)
	text.set_table_column_expand(0, false)
	text.set_table_column_expand(1, true, 1, false)
	text.push_cell()
	text.set_cell_row_background_color(accent, accent)
	text.set_cell_size_override(Vector2(Style.px(3), 0), Vector2(Style.px(3), 100000))
	text.set_cell_padding(Rect2())
	text.pop()
	text.push_cell()
	text.set_cell_row_background_color(background, background)
	#? Spacer lines, not vertical cell padding: the top's goes outside the box, the bottom's is doubled.
	text.set_cell_padding(Rect2(Style.px(10), 0, Style.px(10), 0))
	_write_spacer(text, true)
	if not alert.is_empty():
		text.add_image(Style.icon(alert[0]), Style.px(16), Style.px(16), accent, INLINE_ALIGNMENT_CENTER)
		text.add_text("  ")
		text.push_font(Style.font("bold"))
		text.push_color(accent)
		text.add_text(alert[2])
		text.pop()
		text.pop()
		if not lines.is_empty():
			text.newline()
	_write_lines(text, lines, link_base)
	text.newline()
	_write_spacer(text, false)
	text.pop()
	text.pop()


static func _write_code(text: RichTextLabel, lines: PackedStringArray) -> void:
	text.push_indent(1)
	text.push_mono()
	text.push_color(Style.color("font_color").lerp(Color.WHITE, 0.35))
	text.add_text("\n".join(lines))
	text.pop()
	text.pop()
	text.pop()


#* Horizontal rule:
static func _write_rule(text: RichTextLabel) -> void:
	var line_color := Style.color("font_color")
	line_color.a = 0.15
	text.push_table(1)
	text.set_table_column_expand(0, true, 1, false)
	text.push_cell()
	text.set_cell_row_background_color(line_color, line_color)
	text.set_cell_size_override(Vector2(0, Style.px(1)), Vector2(100000, Style.px(1)))
	text.set_cell_padding(Rect2())
	text.pop()
	text.pop()


#* One list item:
static func _write_list_item(text: RichTextLabel, level: int, bullet: String, bbcode: String) -> void:
	#@ Step 1 - Nest with indents (a list's level doesn't indent it), one step whatever the level (even 0):
	for step in level:
		text.push_indent(1)
	#@ Step 2 - One list per item, so each keeps its own number:
	text.push_list(0, RichTextLabel.LIST_DOTS, false, bullet)
	text.append_text(bbcode)
	text.pop()
	for step in level:
		text.pop()


#==============================================================================
#  INLINE
#==============================================================================

#* Inline Markdown to BBCode:
static func _inline(line: String, link_base: String) -> String:
	var result := ""
	var parts := line.split("`")
	for index in parts.size():
		if index % 2 == 1 and index < parts.size() - 1:
			result += Style.code(parts[index])
		elif index % 2 == 1:
			#? Lone backtick:
			result += _emphasized("`" + parts[index], link_base)
		else:
			result += _emphasized(parts[index], link_base)
	return result


#* Text without code spans to BBCode:
static func _emphasized(segment: String, link_base: String) -> String:
	var bbcode := Style.escaped(_html_break.sub(segment, "", true))
	#@ Step 1 - Set links aside, so emphasis leaves their addresses intact:
	var links: Array = []
	var found := _link.search(bbcode)
	while found != null:
		var link := _link_bbcode(found.get_string(2), _emphasis(found.get_string(1)), link_base)
		var token := "\u0001%d\u0001" % links.size()
		links.append(link)
		bbcode = bbcode.substr(0, found.get_start()) + token + bbcode.substr(found.get_end())
		found = _link.search(bbcode, found.get_start() + token.length())
	found = _bare_url.search(bbcode)
	while found != null:
		var token := "\u0001%d\u0001" % links.size()
		links.append(_link_bbcode(found.get_string(), found.get_string(), link_base))
		bbcode = bbcode.substr(0, found.get_start()) + token + bbcode.substr(found.get_end())
		found = _bare_url.search(bbcode, found.get_start() + token.length())
	bbcode = _emphasis(bbcode)
	#@ Step 2 - Put the links back:
	for index in links.size():
		bbcode = bbcode.replace("\u0001%d\u0001" % index, links[index])
	return bbcode


static func _emphasis(bbcode: String) -> String:
	bbcode = _bold.sub(bbcode, "[b]$1$2[/b]", true)
	bbcode = _italic.sub(bbcode, "[i]$1$2[/i]", true)
	return _strike.sub(bbcode, "[s]$1[/s]", true)


#* Link BBCode. In-page links ("#...") keep only their label:
static func _link_bbcode(address: String, label_bbcode: String, link_base: String) -> String:
	if address.begins_with("#"):
		return label_bbcode
	if not "://" in address and not address.begins_with("mailto:"):
		address = link_base.path_join(address.trim_prefix("./"))
	return "[color=#%s][url=%s]%s[/url][/color]" % [Style.color("accent_color").to_html(false), address.replace("]", "%5D"), label_bbcode]
