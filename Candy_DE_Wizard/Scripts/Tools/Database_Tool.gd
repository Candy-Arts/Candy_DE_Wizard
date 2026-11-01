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


const Style = preload("../UI_Style.gd")

#^ Candy DE's user data folder:
#! Must match Candy_DE/Scripts/Classes/Candy_User_Data.gd.
const USER_DATA_FOLDER := "res://Candy_DE/Scripts/User_Data"

#^ Hooks are the Functions scripts named with this prefix:
const HOOK_PREFIX := "X_"

#^ Most links in a card's column, before it takes another column:
const MAX_ROWS := 6

#^ The hook arguments table, in Data_Tables, listed with the hooks:
const HOOK_ARGUMENTS := "Hook_Arguments"

#^ Which tool this is - DATABASE or HOOKS (set before adding it):
const DATABASE := "database"
const HOOKS := "hooks"
var kind := DATABASE

#^ Cards, in order - {"id", "tool", "title", "icon", "caption"}:
const CATEGORIES: Array[Dictionary] = [
	{"id": "settings", "tool": DATABASE, "title": "Settings", "icon": "Tools", "caption": "Core settings."},
	{"id": "data", "tool": DATABASE, "title": "Data Tables", "icon": "Grid", "caption": "The data dialogues read, in Data_Tables."},
	{"id": "localization", "tool": DATABASE, "title": "Localization Tables", "icon": "Translation", "caption": "Texts per language, in Localization_Tables."},
	{"id": "arguments", "tool": HOOKS, "title": "Hook Arguments", "icon": "Grid", "caption": "Your own arguments for each hook."},
	{"id": "hooks", "tool": HOOKS, "title": "Hooks", "icon": "Signals", "caption": "Called by Candy DE as dialogues run."},
	{"id": "functions", "tool": HOOKS, "title": "Functions", "icon": "MemberMethod", "caption": "Called by Candy DE or your game code."},
]

#^ Shown names and tooltips of the scripts Candy DE ships, by file name - [name, tooltip]:
#? Other scripts get their file name, with spaces.
const SCRIPTS := {
	#@ Settings:
	"Candy_Properties": ["Properties", "Candy DE's settings: folders, symbols, voices, writing, defaults..."],
	"CandyRef_Shortcuts": ["CandyRef", "Your own CandyRef symbols: shortcut and lookup symbols."],
	#@ Data tables:
	"Actors": ["Actors", "Each actor's data: names, portraits, voices, display settings..."],
	"Flags": ["Flags", "Your dialogue flags, read and set by dialogues."],
	"Hook_Arguments": ["Hook Arguments", "Your own arguments for each hook (user_args)."],
	"Lexicon": ["Lexicon", "Keywords to highlight, give a tooltip or make clickable in dialogue displays."],
	"Player_Refs": ["Players", "Which actors are the player(s), and the actor holding the player's data."],
	"Roles": ["Roles", "Stand-ins for actors when the speaker or a target isn't known in advance."],
	"Substitution_Table": ["Substitution", "Words that change with an actor's properties (he / she...)."],
	"Text_Events": ["Text Events", "Events every spoken line can run from its markers."],
	"Variables": ["Variables", "Variables readable inside dialogue lines."],
	"Literal_Variables": ["Literal Variables", "Variables whose value text variables display as written, such as a name the player typed."],
	#@ Localization tables:
	"Display_Names": ["Display Names", "Actors' names, per language."],
	#@ Hooks:
	"X_Bridge": ["Bridge Command", "Called by the Bridge command, before the Block it bridges to runs."],
	"X_Choice_Selected": ["Choice Selected", "Called when a choice is selected, by the player or by a timer."],
	"X_Command_Start": ["Command Start", "Called when a new command is processed."],
	"X_Dialogue_End": ["Dialogue End", "Called when a dialogue ends."],
	"X_Dialogue_Resumed": ["Dialogue Resumed", "Called when a suspended dialogue is resumed."],
	"X_Dialogue_Start": ["Dialogue Start", "Called when a dialogue starts, right before its first line runs."],
	"X_Dialogue_Suspended": ["Dialogue Suspended", "Called when a dialogue is suspended."],
	"X_End": ["End Command", "Called by the End command, before the dialogue ends."],
	"X_Flag_Changed": ["Flag Changed", "Called by the Flag command when a flag's value changes."],
	"X_Jump": ["Jump Command", "Called by the Jump command, before it leaves the current Block."],
	"X_New_Line": ["New Line", "Called when a new line is processed."],
	"X_New_Speech_Display": ["Speech Display", "Called when a spoken line starts being displayed."],
	"X_New_Speech_Start": ["Speech Start", "Called when a new spoken line is processed."],
	"X_Return": ["Return Command", "Called by the Return command, before it leaves the current Block."],
	"X_Speech_Advance": ["Speech Advance", "Called when a spoken line is advanced, by the player or by auto-advance."],
	#@ Functions:
	"Change_Game_State": ["Change Game State", "Change the game's state when a dialogue starts or ends."],
	"Clear_Bg_Layers_Ood": ["Clear Background Layers", "Clear the background layers while no dialogue runs (clear_bg_layers_ood())."],
	"Clear_Busts_Ood": ["Clear Busts", "Clear the VN busts while no dialogue runs (clear_busts_ood())."],
	"Llm_Query": ["LLM Query", "Query a large language model, for actors set to use one."],
	"On_Lexicon_Clicked": ["Lexicon Clicked", "When a clickable Lexicon keyword is clicked."],
	"On_Lexicon_Hovered": ["Lexicon Hovered", "When the mouse enters or leaves a Lexicon keyword."],
	"Open_General_History": ["General History", "Open the history of every dialogue engine (open_general_history())."],
	"Open_Instance_History": ["Instance History", "Open one dialogue engine's history (open_instance_history())."],
	"Tts": ["Text to Speech", "Speak a voiced line with text-to-speech, when its TTS mode isn't Off."],
}

#^ Scripts listed first in their card, in this order, by file name (the others follow, by shown name):
const ORDER := ["Actors", "Player_Refs", "Roles", "Flags", "Variables", "Literal_Variables", "Lexicon", "Substitution_Table", "Text_Events"]

var cards_row: HBoxContainer
var empty_label: Label
#^ The listed scripts, to rebuild only when they change:
var listed: PackedStringArray = []


func _ready() -> void:
	add_theme_constant_override("separation", Style.px(8))

	#? Horizontal scroll only: the bottom panel takes its content's height.
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	cards_row = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", Style.px(8))
	cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards_row)

	empty_label = Style.caption("No user data scripts found in %s." % USER_DATA_FOLDER)
	empty_label.visible = false
	add_child(empty_label)
	refresh()


#* List the user data scripts again, if they changed (on file changes):
func refresh() -> void:
	if cards_row == null:
		return
	var grouped := _scripts_by_category()
	var paths: PackedStringArray = []
	for category in CATEGORIES:
		if category["tool"] == kind:
			paths.append_array(grouped[category["id"]])
	if paths == listed:
		return
	listed = paths

	for child in cards_row.get_children():
		cards_row.remove_child(child)
		child.queue_free()
	for category in CATEGORIES:
		var scripts: PackedStringArray = grouped[category["id"]]
		if category["tool"] == kind and not scripts.is_empty():
			_add_card(category, scripts)
	empty_label.visible = paths.is_empty()


#* The user data scripts, by category id, sorted (ORDER, then shown name):
func _scripts_by_category() -> Dictionary:
	var grouped := {}
	for category in CATEGORIES:
		grouped[category["id"]] = PackedStringArray()
	for path in _files_in(USER_DATA_FOLDER, false):
		grouped["settings"].append(path)
	for path in _files_in(USER_DATA_FOLDER.path_join("Data_Tables"), true):
		if path.get_file().get_basename() == HOOK_ARGUMENTS:
			grouped["arguments"].append(path)
		else:
			grouped["data"].append(path)
	for path in _files_in(USER_DATA_FOLDER.path_join("Localization_Tables"), true):
		grouped["localization"].append(path)
	for path in _files_in(USER_DATA_FOLDER.path_join("Functions"), true):
		if path.get_file().begins_with(HOOK_PREFIX):
			grouped["hooks"].append(path)
		else:
			grouped["functions"].append(path)

	for id in grouped:
		var sorted: Array = Array(grouped[id])
		sorted.sort_custom(_comes_before)
		grouped[id] = PackedStringArray(sorted)
	return grouped


func _comes_before(a: String, b: String) -> bool:
	var rank_a := ORDER.find(a.get_file().get_basename())
	var rank_b := ORDER.find(b.get_file().get_basename())
	if rank_a != rank_b:
		if rank_a == -1:
			return false
		if rank_b == -1:
			return true
		return rank_a < rank_b
	return shown_name(a).naturalnocasecmp_to(shown_name(b)) < 0


#* A folder's .gd files, sub-folders included if recursive:
func _files_in(folder: String, recursive: bool) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.get_extension() == "gd":
			found.append(folder.path_join(file))
	if recursive:
		for sub_folder in dir.get_directories():
			found.append_array(_files_in(folder.path_join(sub_folder), true))
	return found


#* A script's shown name - from SCRIPTS, else its file name with spaces:
static func shown_name(path: String) -> String:
	var file_name := path.get_file().get_basename()
	if SCRIPTS.has(file_name):
		return SCRIPTS[file_name][0]
	if file_name.begins_with(HOOK_PREFIX):
		file_name = file_name.trim_prefix(HOOK_PREFIX)
	return file_name.replace("_", " ")


func _add_card(category: Dictionary, scripts: PackedStringArray) -> void:
	var box := Style.card_box(cards_row)
	Style.card_title(box, category["icon"], category["title"])
	var caption_label := Style.caption(category["caption"])
	caption_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(caption_label)
	var grid := GridContainer.new()
	grid.columns = ceili(float(scripts.size()) / MAX_ROWS)
	grid.add_theme_constant_override("h_separation", Style.px(6))
	grid.add_theme_constant_override("v_separation", Style.px(2))
	box.add_child(grid)

	#? Column-major: GridContainer fills rows, so place link (row, column) by index.
	var rows := ceili(float(scripts.size()) / grid.columns)
	for row in rows:
		for column in grid.columns:
			var index := column * rows + row
			if index < scripts.size():
				grid.add_child(_link(scripts[index]))
			else:
				grid.add_child(Control.new())


#* A button opening a script:
func _link(path: String) -> Button:
	var link := Style.button(shown_name(path), "Script", _open_script.bind(path))
	link.flat = true
	link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var file_name := path.get_file().get_basename()
	var tooltip := path.trim_prefix(USER_DATA_FOLDER + "/")
	if SCRIPTS.has(file_name):
		tooltip = "%s\n%s" % [SCRIPTS[file_name][1], tooltip]
	link.tooltip_text = tooltip
	return link


#* Open a script as the FileSystem dock does - script editor or external editor (or show it in the dock if it can't be loaded):
#? Not edit_script(): it gives an external editor column 0 ("{col}"), which VS Code opens as an empty window.
func _open_script(path: String) -> void:
	var script := load(path) as Script
	if script == null:
		EditorInterface.get_file_system_dock().navigate_to_path(path)
		return
	EditorInterface.edit_resource(script)
