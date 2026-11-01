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
const VoiceFiles = preload("../Voice_Files.gd")
const VoiceWizard = preload("../Voice_Wizard.gd")

#^ Effect players' animation libraries folder, in effects_folder:
#! Must match Candy_DE/Scripts/Media_Players/Effect_Player.gd.
const EFFECT_LIBRARIES_FOLDER := "Animation_Libraries"

var buttons: Array[Button] = []
var result_text: RichTextLabel
#^ Voice layout status, and the move button:
var voice_status_icon: TextureRect
var voice_status_label: Label
var move_button: Button
var voice_wizard: Window = null


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

	var voices := _add_card(cards, "AudioStreamMicrophone", "Voices", "One per spoken line, from the dialogues.", 1)
	_add_button(voices, "Generate Voice Folders", "AudioStreamMicrophone", "In voice_folder: each spoken line's folder, as voice_path lays them out.", _generate_voice_folders)
	move_button = _add_button(voices, "Move Voice Files…", "ToolMove", "Move the voice files to where voice_folder and voice_path now say. Files no line uses are left where they are.", _open_voice_wizard)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", Style.px(6))
	voices.get_parent().add_child(status_row)
	voice_status_icon = Style.icon_rect(null, 16)
	status_row.add_child(voice_status_icon)
	voice_status_label = Style.caption("")
	voice_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_row.add_child(voice_status_label)

	var actors := _add_card(cards, "CharacterBody2D", "Actors", "One per actor, from the actors table.", 1)
	_add_button(actors, "Generate Portrait Folders", "TextureRect", "In portraits_folder.", _generate_actor_folders.bind("portraits_folder", "Portrait"))
	_add_button(actors, "Generate Bust Folders", "Sprite2D", "In busts_folder.", _generate_actor_folders.bind("busts_folder", "Bust"))
	_add_button(actors, "Generate Sprite Folders", "AnimatedSprite2D", "In sprite_folder.", _generate_actor_folders.bind("sprite_folder", "Sprite"))

	var players := _add_card(cards, "PackedScene", "Media players", "One per player, from the UI scenes.", 1)
	_add_button(players, "Generate Audio Folders", "AudioStreamPlayer", "In audio_folder: the audio players of media_players_paths, except Voice.", _generate_player_folders.bind("Audio", "audio_folder"))
	_add_button(players, "Generate Image Folders", "ImageTexture", "In image_folder: the image players of media_players_paths.", _generate_player_folders.bind("Image", "image_folder"))
	_add_button(players, "Generate Video Folders", "VideoStreamPlayer", "In video_folder: the video players of media_players_paths.", _generate_player_folders.bind("Video", "video_folder"))

	var backgrounds := _add_card(cards, "ParallaxBackground", "Backgrounds and effects", "Per layer; one for effects.", 1)
	_add_button(backgrounds, "Generate Background Folders", "ParallaxLayer", "In background_folder: the children of bg_container.", _generate_background_folders)
	_add_button(backgrounds, "Generate Effects Folder", "AnimationLibrary", "In effects_folder: %s, where the animation libraries of every effect player go (Effect_Play's Library)." % EFFECT_LIBRARIES_FOLDER, _generate_effects_folder)

	var result_box := Style.card_box(cards)
	result_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_box.get_parent().custom_minimum_size.x = Style.px(200)
	Style.card_title(result_box, "Info", "Result")
	result_text = Style.rich_text(false)
	result_text.meta_clicked.connect(func(path) -> void: EditorInterface.get_file_system_dock().navigate_to_path(str(path)))
	result_box.add_child(result_text)
	_show_intro()
	refresh()


func _exit_tree() -> void:
	if voice_wizard != null and is_instance_valid(voice_wizard):
		voice_wizard.queue_free()


#* Show whether the voice files follow the recorded layout (on file changes):
func refresh() -> void:
	if voice_status_label == null or not CandyDEData.is_available():
		return
	var current := VoiceFiles.current_layout()
	var recorded := VoiceFiles.recorded_layout()
	Style.make_plain(move_button)
	if recorded.is_empty():
		_show_voice_status("Info", "No record of how the files are arranged.", Style.dim())
	elif VoiceFiles.same_layout(recorded, current):
		_show_voice_status("StatusSuccess", "The files follow voice_path.", Style.dim())
	else:
		var setting := "voice_path"
		if recorded["voice_folder"].trim_suffix("/") != String(current.get("voice_folder", "")).trim_suffix("/"):
			setting = "voice_folder"
		_show_voice_status("StatusWarning", "%s changed: move the files." % setting, Style.color("warning_color"))
		Style.make_primary(move_button)


func _show_voice_status(icon_name: String, text: String, text_color: Color) -> void:
	voice_status_icon.texture = Style.icon(icon_name)
	voice_status_label.text = text
	voice_status_label.add_theme_color_override("font_color", text_color)


func _open_voice_wizard() -> void:
	if voice_wizard != null and is_instance_valid(voice_wizard):
		voice_wizard.grab_focus()
		return
	voice_wizard = VoiceWizard.new()
	voice_wizard.wizard_closed.connect(refresh)
	EditorInterface.get_base_control().add_child(voice_wizard)
	voice_wizard.popup_centered(voice_wizard.min_size)


#* Add a card. Returns its button grid:
func _add_card(parent: Node, icon_name: String, title: String, caption: String, columns: int) -> GridContainer:
	var box := Style.card_box(parent)
	Style.card_title(box, icon_name, title)
	var caption_label := Style.caption(caption)
	caption_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(caption_label)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", Style.px(6))
	grid.add_theme_constant_override("v_separation", Style.px(6))
	box.add_child(grid)
	return grid


func _add_button(grid: GridContainer, text: String, icon_name: String, tooltip: String, action: Callable) -> Button:
	var button := Style.button(text, icon_name, action)
	button.tooltip_text = tooltip
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(button)
	buttons.append(button)
	return button


func _show_intro() -> void:
	result_text.clear()
	result_text.push_color(Style.dim())
	result_text.add_text("Click the buttons to generate folders.\nFolders are never deleted, only added.\nThe folder paths can be customized in the Properties script.")
	result_text.pop()


#==============================================================================
#  GENERATORS
#==============================================================================

func _generate_actor_folders(folder_setting: String, label: String) -> void:
	_generate(label + " folders", folder_setting, CandyDEData.actor_names())


#* Each spoken line's voice folder - voice_folder/<voice_path>/<variant>:
func _generate_voice_folders() -> void:
	var layout := VoiceFiles.current_layout()
	if layout.is_empty():
		_show("Voice folders", PackedStringArray(), PackedStringArray(), PackedStringArray(["voice_folder or voice_path isn't set in Candy_Properties.gd."]))
		return
	var gathered := VoiceFiles.folders(layout)
	var prefix := String(layout["voice_folder"]).trim_suffix("/") + "/"
	var names: PackedStringArray = []
	for folder in gathered["folders"]:
		#? Skip voice_folder itself (empty voice_path):
		if folder + "/" != prefix:
			names.append(folder.trim_prefix(prefix))
	var problems: PackedStringArray = gathered["problems"]
	var recorded := VoiceFiles.recorded_layout()
	if not recorded.is_empty() and not VoiceFiles.same_layout(recorded, layout):
		problems.append("The voice files are still arranged as before voice_folder or voice_path changed: Move Voice Files brings them into these folders.")
	_generate("Voice folders", "voice_folder", {"names": names, "problems": problems})


func _generate_player_folders(kind: String, folder_setting: String) -> void:
	_generate(kind + " folders", folder_setting, CandyDEData.media_player_names(kind))


func _generate_background_folders() -> void:
	_generate("Background folders", "background_folder", CandyDEData.background_layer_names())


#* The effect players' animation libraries folder:
func _generate_effects_folder() -> void:
	_generate("Effects folder", "effects_folder", {"names": PackedStringArray([EFFECT_LIBRARIES_FOLDER]), "problems": PackedStringArray()})


#* Make a folder per name (may hold sub-folders) in folder_setting's folder, made if missing:
#? gathered: {"names", "problems"}, from CandyDEData.
func _generate(title: String, folder_setting: String, gathered: Dictionary) -> void:
	var problems: PackedStringArray = gathered["problems"]
	var base = CandyDEData.property(folder_setting)
	if not base is String or String(base) == "":
		problems.append("%s isn't set in Candy_Properties.gd." % folder_setting)
		_show(title, PackedStringArray(), PackedStringArray(), problems)
		return

	#? The folder itself (releases don't ship empty folders):
	var base_path := String(base).trim_suffix("/")
	var base_created := false
	if not DirAccess.dir_exists_absolute(base_path):
		var base_error := DirAccess.make_dir_recursive_absolute(base_path)
		if base_error != OK:
			problems.append("Couldn't create %s (%s)." % [base_path, error_string(base_error)])
			_show(title, PackedStringArray(), PackedStringArray(), problems)
			return
		base_created = true

	var created: PackedStringArray = []
	var existing: PackedStringArray = []
	for folder_name in gathered["names"]:
		if not _valid_folder_path(folder_name):
			problems.append("'%s' can't be a folder name." % folder_name)
			continue
		var folder_path := String(base).path_join(folder_name)
		if DirAccess.dir_exists_absolute(folder_path):
			existing.append(folder_name)
			continue
		var error := DirAccess.make_dir_recursive_absolute(folder_path)
		if error != OK:
			problems.append("Couldn't create %s (%s)." % [folder_path, error_string(error)])
			continue
		created.append(folder_name)
	if gathered["names"].is_empty() and problems.is_empty() and not base_created:
		problems.append("Nothing to make a folder for.")
	_show(title, created, existing, problems, base_path, base_created)
	if base_created or not created.is_empty():
		EditorInterface.get_resource_filesystem().scan()


func _valid_folder_path(folder_path: String) -> bool:
	for part in folder_path.split("/"):
		if not part.is_valid_filename() or part == "." or part == "..":
			return false
	return true


#* Show a generation's result:
#? folder_created - the base folder was made.
func _show(title: String, created: PackedStringArray, existing: PackedStringArray, problems: PackedStringArray, folder: String = "", folder_created: bool = false) -> void:
	result_text.clear()
	result_text.push_font(Style.font("bold"))
	result_text.add_text(title)
	result_text.pop()
	if folder != "":
		result_text.append_text("   [url=%s]Show in FileSystem[/url]" % folder)
	result_text.newline()
	if folder_created:
		#? Name only: the card is narrow.
		Style.rich_item(result_text, "FolderCreate", "Created the folder %s" % Style.code(folder.get_file()), Style.color("success_color"))
	if not created.is_empty():
		Style.rich_item(result_text, "FolderCreate", "Created %d: %s" % [created.size(), Style.escaped(", ".join(created))], Style.color("success_color"))
	if not existing.is_empty():
		Style.rich_item(result_text, "Folder", "[color=#%s]Already there: %s[/color]" % [Style.dim().to_html(false), Style.escaped(", ".join(existing))])
	for problem in problems:
		Style.rich_item(result_text, "StatusWarning", Style.colored(Style.escaped(problem), "warning_color"))
