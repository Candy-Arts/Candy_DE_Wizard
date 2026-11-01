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
extends Node


const CandyDEData = preload("Candy_DE_Data.gd")
const Runner = preload("Test_Runner.gd")
const Utils = preload("Wizard_Utils.gd")

#^ Folder inside the project's data folder:
const FOLDER_NAME := "candy_wizard"
const REQUEST_FILE := "test_request.json"
const RESPONSE_FILE := "test_response.json"
#^ Newest request format read:
const FORMAT := 1
const POLL_SECONDS := 0.25
const MAX_AGE_SECONDS := 10.0

var folder := ""


func _ready() -> void:
	#? ".godot", or "godot" if the project setting says visible:
	var data_folder := "res://.godot"
	if not ProjectSettings.get_setting("application/config/use_hidden_project_data_directory", true):
		data_folder = "res://godot"
	folder = data_folder.path_join(FOLDER_NAME)
	#? Drop a request from before the editor opened:
	DirAccess.remove_absolute(folder.path_join(REQUEST_FILE))
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.timeout.connect(_poll)
	add_child(timer)
	timer.start()


func _poll() -> void:
	var request_path := folder.path_join(REQUEST_FILE)
	if not FileAccess.file_exists(request_path):
		return
	var text := FileAccess.get_file_as_string(request_path)
	DirAccess.remove_absolute(request_path)
	var request = JSON.parse_string(text)
	if not request is Dictionary:
		return
	if Time.get_unix_time_from_system() - float(request.get("sent", 0.0)) > MAX_AGE_SECONDS:
		return
	var answer := _handle(request)
	answer["format"] = FORMAT
	answer["id"] = str(request.get("id", ""))
	_write_response(answer)


#* Run a request's test - {"status", "message"}:
func _handle(request: Dictionary) -> Dictionary:
	if int(request.get("format", 0)) > FORMAT:
		return _error("Candy Dialogue Creator asked in a newer way than this Candy Wizard understands: update Candy Wizard.")
	if not CandyDEData.is_available():
		return _error("Candy Dialogue Engine isn't installed in this project.")
	var named := Runner.dialogue_name(str(request.get("dialogue_file", "")))
	if named["problem"] != "":
		return _error(named["problem"])
	var start := Runner.resolve_start(named["name"], str(request.get("conversation", "")), str(request.get("block", "")), str(request.get("line", "")))
	if start["problem"] != "":
		return _error(start["problem"])
	var scene_path := str(request.get("scene", ""))
	if scene_path == "":
		scene_path = Runner.chosen_scene()
		if scene_path == "":
			return _error("No testing scene to run: testing_scenes_folder has no scene whose root exports dialogue, conversation, block and line. Pick one in Candy Wizard's Test tool.")
	#? Refuse scenes outside the project ("res://../..."):
	elif not scene_path.begins_with("res://") or not Utils.is_safe_relative_path(scene_path.trim_prefix("res://")) or not ResourceLoader.exists(scene_path):
		return _error("The testing scene %s isn't in this project." % scene_path)
	var run_error := Runner.run(scene_path, start["values"])
	if run_error != "":
		return _error(run_error)
	var values: Dictionary = start["values"]
	return {"status": "started", "message": "%s, from %s › %s › %s › line %s." % [scene_path.get_file(), values["dialogue"], values["conversation"], values["block"], values["line"]]}


func _error(message: String) -> Dictionary:
	return {"status": "error", "message": message}


func _write_response(answer: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var temporary_path := folder.path_join(RESPONSE_FILE + ".tmp")
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(answer))
	file.close()
	DirAccess.rename_absolute(temporary_path, folder.path_join(RESPONSE_FILE))
