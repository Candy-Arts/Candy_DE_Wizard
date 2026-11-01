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


#^ Candy blue, the lollipop's in the logo:
const BRAND := Color("#3096ff")
#^ Button fills, deeper for white text:
const BRAND_FILL := Color("#1f7fe8")
const BRAND_PRESSED := Color("#1a6cc7")

#^ Logo SVG. Preloaded for its path (the folder may be renamed); logo() reads the SVG:
const LOGO := preload("../Icons/Candy_Icon.svg")
const LOGO_SIZE := 256.0		#/ The SVG's own width and height

#^ Disc with a white sign, like StatusSuccess ({color} = disc, {sign} = the sign's path):
const DISC_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
<circle cx="8" cy="8" r="8" fill="#{color}"/>
<path d="{sign}" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
</svg>"""
const CROSS_SIGN := "M5.3 5.3 10.7 10.7M10.7 5.3 5.3 10.7"
const MINUS_SIGN := "M4.6 8H11.4"

static var _textures := {}		#/ "<name> <size in pixels>" -> ImageTexture


#==============================================================================
#  THEME
#==============================================================================

#* Pixels at the editor's scale:
static func px(value: float) -> int:
	return int(round(value * EditorInterface.get_editor_scale()))


static func color(color_name: String) -> Color:
	return EditorInterface.get_editor_theme().get_color(color_name, "Editor")


#* Secondary text color:
static func dim() -> Color:
	return color("font_color").lerp(color("dark_color_2"), 0.35)


#* Neutral status grey (something waiting), readable under white in any theme:
static func neutral() -> Color:
	return color("font_color").lerp(color("base_color"), 0.5)


#^ Stand-ins for editor icons that some Godot versions or builds don't have:
const ICON_FALLBACKS := {
	"AssetLib": ["Load"],
}


#* Icon by name. An SVG of that name in the Icons folder wins (e.g. Icons/AssetLib.svg);
#* otherwise the editor's icon, checked first so a missing one gives a stand-in, not a warning:
static func icon(icon_name: String) -> Texture2D:
	var own_path := LOGO.resource_path.get_base_dir().path_join(icon_name + ".svg")
	if ResourceLoader.exists(own_path):
		return load(own_path)
	var theme := EditorInterface.get_editor_theme()
	for candidate: String in [icon_name] + ICON_FALLBACKS.get(icon_name, []):
		if theme.has_icon(candidate, "EditorIcons"):
			return theme.get_icon(candidate, "EditorIcons")
	return null


static func font(font_name: String) -> Font:
	return EditorInterface.get_editor_theme().get_font(font_name, "EditorFonts")


static func font_size(factor: float = 1.0) -> int:
	return int(round(EditorInterface.get_editor_theme().default_font_size * factor))


#* Logo at size (unscaled pixels):
static func logo(size: float) -> Texture2D:
	var pixels := px(size)
	var key := "logo %d" % pixels
	if not _textures.has(key):
		_textures[key] = _svg_texture(FileAccess.get_file_as_string(LOGO.resource_path), pixels / LOGO_SIZE)
	return _textures[key]


#* Red disc with a white X, at size (unscaled pixels):
static func cross_icon(size: float) -> Texture2D:
	return _disc_icon("cross", CROSS_SIGN, color("error_color"), size)


#* Grey disc with a white minus, at size (unscaled pixels):
static func minus_icon(size: float) -> Texture2D:
	return _disc_icon("minus", MINUS_SIGN, neutral(), size)


static func _disc_icon(icon_name: String, sign_path: String, disc_color: Color, size: float) -> Texture2D:
	var pixels := px(size)
	var key := "%s %d" % [icon_name, pixels]
	if not _textures.has(key):
		_textures[key] = _svg_texture(DISC_SVG.format({"color": disc_color.to_html(false), "sign": sign_path}), pixels / 16.0)
	return _textures[key]


static func _svg_texture(svg: String, svg_scale: float) -> ImageTexture:
	var image := Image.new()
	image.load_svg_from_string(svg, svg_scale)
	return ImageTexture.create_from_image(image)


#==============================================================================
#  STYLEBOXES
#==============================================================================

#* Card style (accent = left edge bar, transparent for none):
static func card(accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	#? Lifted toward the text color, to work in dark and light themes:
	style.bg_color = color("base_color").lerp(color("font_color"), 0.06)
	style.set_corner_radius_all(px(6))
	style.content_margin_left = px(12)
	style.content_margin_right = px(12)
	style.content_margin_top = px(10)
	style.content_margin_bottom = px(10)
	if accent.a > 0.0:
		style.border_color = accent
		style.border_width_left = px(3)
		style.content_margin_left = px(14)
	return style


#* Window header/footer band (edge = side with a line):
static func band(background: Color, edge: Side, edge_color: Color, edge_width: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge_color
	match edge:
		SIDE_TOP:
			style.border_width_top = px(edge_width)
		SIDE_BOTTOM:
			style.border_width_bottom = px(edge_width)
	style.content_margin_left = px(20)
	style.content_margin_right = px(20)
	style.content_margin_top = px(14)
	style.content_margin_bottom = px(14)
	return style


static func _button_box(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(px(4))
	style.content_margin_left = px(14)
	style.content_margin_right = px(14)
	style.content_margin_top = px(5)
	style.content_margin_bottom = px(5)
	return style


#==============================================================================
#  CONTROLS
#==============================================================================

#* Main action button:
static func make_primary(target: Button) -> void:
	_fill_button(target, BRAND_FILL, BRAND, BRAND_PRESSED)


#* Destructive action button:
static func make_danger(target: Button) -> void:
	var red := color("error_color")
	_fill_button(target, red.darkened(0.25), red.darkened(0.1), red.darkened(0.4))


#* Restore a button's editor look:
static func make_plain(target: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		target.remove_theme_stylebox_override(state)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		target.remove_theme_color_override(state)


static func _fill_button(target: Button, normal: Color, hover: Color, pressed: Color) -> void:
	target.add_theme_stylebox_override("normal", _button_box(normal))
	target.add_theme_stylebox_override("hover", _button_box(hover))
	target.add_theme_stylebox_override("pressed", _button_box(pressed))
	target.add_theme_stylebox_override("hover_pressed", _button_box(pressed))
	var focus := _button_box(Color.TRANSPARENT)
	focus.draw_center = false
	focus.border_color = Color(1, 1, 1, 0.6)
	focus.set_border_width_all(px(1))
	target.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		target.add_theme_color_override(state, Color.WHITE)


static func button(text: String, icon_name: String, action: Callable) -> Button:
	var new_button := Button.new()
	new_button.text = text
	if icon_name != "":
		new_button.icon = icon(icon_name)
	new_button.pressed.connect(action)
	return new_button


static func label(text: String, font_name: String = "", size_factor: float = 1.0) -> Label:
	var new_label := Label.new()
	new_label.text = text
	if font_name != "":
		new_label.add_theme_font_override("font", font(font_name))
	if size_factor != 1.0:
		new_label.add_theme_font_size_override("font_size", font_size(size_factor))
	return new_label


#* Secondary text label:
static func caption(text: String) -> Label:
	var new_label := Label.new()
	new_label.text = text
	new_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	new_label.add_theme_color_override("font_color", dim())
	return new_label


#^ The unread mark - an exclamation mark, 16 units tall. Filled with the warning color (yellow):
const UNREAD_SVG := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"6\" height=\"16\" viewBox=\"0 0 6 16\"><rect x=\"1.25\" y=\"1\" width=\"3.5\" height=\"9.5\" rx=\"1.75\" fill=\"%s\"/><circle cx=\"3\" cy=\"13.5\" r=\"2\" fill=\"%s\"/></svg>"


#* Unread mark - a yellow exclamation mark (size in unscaled pixels):
static func unread_mark(size: float) -> ImageTexture:
	return ImageTexture.create_from_image(_unread_image(maxi(px(size), 8)))


#* An icon with the unread mark beside it, on its right (marked false: the mark's room left empty, to align names):
#? The icon alone if it can't be read.
static func unread_badge(base: Texture2D, marked: bool = true) -> Texture2D:
	var image := base.get_image()
	if image == null:
		return base
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var mark := _unread_image(image.get_height())
	var gap := maxi(int(round(image.get_height() / 8.0)), 1)
	var wide := Image.create(image.get_width() + gap + mark.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	wide.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	if marked:
		wide.blend_rect(mark, Rect2i(Vector2i.ZERO, mark.get_size()), Vector2i(image.get_width() + gap, 0))
	return ImageTexture.create_from_image(wide)


#* The unread mark at a height in pixels:
static func _unread_image(height: int) -> Image:
	var hex := "#" + color("warning_color").to_html(false)
	var image := Image.new()
	image.load_svg_from_string(UNREAD_SVG % [hex, hex], height / 16.0)
	image.convert(Image.FORMAT_RGBA8)
	return image


static func icon_rect(texture: Texture2D, size: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(px(size), px(size))
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


#* Add a card, return its content box:
static func card_box(parent: Node, accent: Color = Color.TRANSPARENT) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", card(accent))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", px(6))
	panel.add_child(box)
	return box


#* Card title row:
static func card_title(parent: Node, icon_name: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", px(6))
	if icon_name != "":
		row.add_child(icon_rect(icon(icon_name), 16))
	row.add_child(label(text, "bold"))
	parent.add_child(row)
	return row


#==============================================================================
#  RICH TEXT
#==============================================================================

#* RichTextLabel for rich_item() / rich_heading() lists:
#? framed: on a text panel (pages), else transparent (cards).
static func rich_text(framed: bool = true) -> RichTextLabel:
	var text := RichTextLabel.new()
	if not framed:
		text.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		text.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	text.bbcode_enabled = true
	text.selection_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("line_separation", px(5))
	text.add_theme_font_override("normal_font", font("main"))
	text.add_theme_font_override("bold_font", font("bold"))
	text.add_theme_font_override("italics_font", font("doc_italic"))
	text.add_theme_font_override("mono_font", font("source"))
	text.add_theme_color_override("default_color", color("font_color"))
	return text


static func rich_heading(text: RichTextLabel, heading: String) -> void:
	if text.get_parsed_text() != "":
		text.newline()
	text.push_font(font("bold"))
	text.add_text(heading)
	text.pop()
	text.newline()


#* Icon + BBCode line:
static func rich_item(text: RichTextLabel, icon_name: String, bbcode: String, icon_color: Color = Color.WHITE) -> void:
	text.add_image(icon(icon_name), px(16), px(16), icon_color, INLINE_ALIGNMENT_CENTER)
	text.add_text("  ")
	text.append_text(bbcode)
	text.newline()


#* Escape BBCode:
static func escaped(text: String) -> String:
	return text.replace("[", "[lb]")


#* BBCode in an editor theme color:
static func colored(text: String, color_name: String) -> String:
	return "[color=#%s]%s[/color]" % [color(color_name).to_html(false), text]


#* BBCode for paths and names:
static func code(text: String) -> String:
	return "[code][color=#%s]%s[/color][/code]" % [color("font_color").lerp(Color.WHITE, 0.35).to_html(false), escaped(text)]
