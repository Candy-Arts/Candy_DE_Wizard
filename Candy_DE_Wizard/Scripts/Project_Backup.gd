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


signal progress(fraction: float, message: String)

const Utils = preload("Wizard_Utils.gd")

#^ Folders at the project's root that backups leave out:
const SKIPPED_FOLDERS := [".godot", ".git"]
#^ Read and written in pieces, so large media files don't fill the memory:
const CHUNK_SIZE := 4 * 1024 * 1024
#^ Bytes written between two editor frames:
const BYTES_PER_FRAME := 16 * 1024 * 1024
#^ The largest file ZIPPacker can store (no Zip64) - a larger one would be left out silently:
const MAX_FILE_SIZE := 0xFFFFFFFF

#^ Where the last backup was saved:
var backup_path := ""


#* Why a backup can't be saved in this folder, or "" if it can:
static func folder_problem(folder: String) -> String:
	if folder.strip_edges() == "":
		return "Choose a folder for the backup."
	if not DirAccess.dir_exists_absolute(folder):
		return "The backup folder doesn't exist."
	var project_root := ProjectSettings.globalize_path("res://")
	#? Windows and macOS paths ignore capitals.
	if is_inside(folder, project_root, OS.get_name() in ["Windows", "macOS"]):
		return "The backup folder must be outside the project: a backup is no use if the project's folder is lost, and the next backup would contain this one."
	return ""


#* Whether folder is container or inside it (ignore_case for paths that ignore capitals):
static func is_inside(folder: String, container: String, ignore_case: bool) -> bool:
	var target := folder.simplify_path().trim_suffix("/")
	var outer := container.simplify_path().trim_suffix("/")
	if ignore_case:
		target = target.to_lower()
		outer = outer.to_lower()
	return target == outer or target.begins_with(outer + "/")


#* Zips the project into folder (label goes into the file name), returning an error message or "":
func create(folder: String, label: String, tree: SceneTree) -> String:
	var problem := folder_problem(folder)
	if problem != "":
		return problem
	var project_root := ProjectSettings.globalize_path("res://").simplify_path()
	progress.emit(0.0, "Listing the project's files…")
	var files: PackedStringArray = []
	var total_bytes := _collect(project_root, "", files)
	await tree.process_frame

	var project_name := String(ProjectSettings.get_setting("application/config/name", "Project")).validate_filename().replace(" ", "_")
	var time_text := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	backup_path = folder.simplify_path().path_join("%s_%s_%s.zip" % [project_name, label, time_text])

	var packer := ZIPPacker.new()
	var error := packer.open(backup_path)
	if error != OK:
		return "Couldn't create the backup file %s (%s)." % [backup_path, error_string(error)]
	var written := 0
	var since_frame := 0
	for relative in files:
		var file := FileAccess.open(project_root.path_join(relative), FileAccess.READ)
		if file == null:
			packer.close()
			DirAccess.remove_absolute(backup_path)
			return "Couldn't read %s for the backup (%s)." % [relative, error_string(FileAccess.get_open_error())]
		if file.get_length() >= MAX_FILE_SIZE:
			_failed(packer)
			return "%s is too large for the backup's zip, which holds files under 4 GB. Move it out of the project for now, or back the project up yourself." % relative
		if packer.start_file(relative) != OK:
			return _failed(packer)
		while file.get_position() < file.get_length():
			var chunk := file.get_buffer(CHUNK_SIZE)
			#? An unreadable file gives nothing: stop, rather than loop.
			if chunk.is_empty():
				_failed(packer)
				return "Couldn't read %s for the backup." % relative
			if packer.write_file(chunk) != OK:
				return _failed(packer)
			written += chunk.size()
			since_frame += chunk.size()
			if since_frame >= BYTES_PER_FRAME:
				since_frame = 0
				_report(written, total_bytes)
				await tree.process_frame
		file.close()
		#? What's left of a file is written when it's closed, and the zip's list when the zip is.
		if packer.close_file() != OK:
			return _failed(packer)
	if packer.close() != OK:
		DirAccess.remove_absolute(backup_path)
		return "Couldn't write the backup (is the disk full?)."
	_report(total_bytes, total_bytes)
	return ""


#* Gives up on a backup that can't be written, removing what was written of it:
func _failed(packer: ZIPPacker) -> String:
	packer.close()
	DirAccess.remove_absolute(backup_path)
	return "Couldn't write the backup (is the disk full?)."


func _report(written: int, total_bytes: int) -> void:
	var fraction := 1.0
	if total_bytes > 0:
		fraction = float(written) / total_bytes
	progress.emit(fraction, "Backing up the project… %s / %s" % [Utils.readable_size(written), Utils.readable_size(total_bytes)])


#* Adds every file under root/relative_folder to files, returning their total size:
func _collect(root: String, relative_folder: String, files: PackedStringArray) -> int:
	var dir := DirAccess.open(root.path_join(relative_folder))
	if dir == null:
		return 0
	dir.include_hidden = true
	var total := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var relative := entry
		if relative_folder != "":
			relative = relative_folder + "/" + entry
		if dir.current_is_dir():
			if not (relative_folder == "" and entry in SKIPPED_FOLDERS):
				total += _collect(root, relative, files)
		else:
			files.append(relative)
			total += FileAccess.get_size(root.path_join(relative))
		entry = dir.get_next()
	dir.list_dir_end()
	return total
