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


const Utils = preload("Wizard_Utils.gd")
const Signature = preload("Release_Signature.gd")

var zip_path := ""
var manifest: Dictionary = {}
var reader: ZIPReader = null
var zip_entries: Dictionary = {}		#/ Every file in the zip, for quick lookups

#^ What kind of release it is (Candy DE's by default), set before open():
var package_name := Utils.PACKAGE_NAME
var manifest_name := Utils.MANIFEST_NAME
var root := Utils.PACKAGE_NAME + "/"	#/ Every file's path starts with it
var title := "Candy DE"


#* Reads a Candy Wizard release instead of a Candy DE one:
func use_wizard_package() -> void:
	package_name = Utils.WIZARD_PACKAGE_NAME
	manifest_name = Utils.WIZARD_MANIFEST_NAME
	root = "addons/" + Utils.WIZARD_PACKAGE_NAME + "/"
	title = "Candy Wizard"


#* Reads a Candy Database release instead of a Candy DE one:
func use_database_package() -> void:
	package_name = Utils.DATABASE_PACKAGE_NAME
	manifest_name = Utils.DATABASE_MANIFEST_NAME
	root = Utils.DATABASE_FOLDER.trim_prefix("res://") + "/"
	title = "Candy Database"


#* Opens a release zip and reads its manifest, returning an error message or "":
func open(path: String) -> String:
	close()
	reader = ZIPReader.new()
	var error := reader.open(path)
	if error != OK:
		reader = null
		return "Couldn't open '%s' as a zip file (%s)." % [path.get_file(), error_string(error)]
	zip_path = path
	for entry in reader.get_files():
		zip_entries[entry] = true
	if not zip_entries.has(manifest_name):
		return "'%s' isn't a %s release: it has no %s file." % [path.get_file(), title, manifest_name]
	#? Before anything in the zip is believed: its manifest must be signed by Candy Arts.
	var manifest_bytes := reader.read_file(manifest_name)
	var signature := ""
	if zip_entries.has(manifest_name + Signature.SIGNATURE_SUFFIX):
		signature = reader.read_file(manifest_name + Signature.SIGNATURE_SUFFIX).get_string_from_utf8()
	var signature_problem := Signature.problem(manifest_bytes, signature, title)
	if signature_problem != "":
		return signature_problem
	var parsed = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return "The release's manifest (%s) can't be read." % manifest_name
	manifest = parsed
	return _check_manifest()


func close() -> void:
	if reader != null:
		reader.close()
	reader = null
	zip_path = ""
	manifest = {}
	zip_entries = {}


func version() -> String:
	return String(manifest.get("version", ""))


func files() -> Dictionary:
	return manifest.get("files", {})


func read(path: String) -> PackedByteArray:
	return reader.read_file(path)


#* The release's BBCode notes of one kind (a key of Utils.NOTES_FILES), or "", checked by verify():
func notes(kind: String) -> String:
	var entry := _notes_entry(kind)
	if entry.is_empty() or not zip_entries.has(entry["file"]):
		return ""
	return reader.read_file(entry["file"]).get_string_from_utf8().replace("\r\n", "\n").strip_edges()


#* The notes a wizard shows ("pre" or "post") in a flow (Utils.NOTES_INSTALL / NOTES_UPDATE), or "":
#* general pre notes, then the flow's; the flow's post notes, then the general ones.
func wizard_notes(stage: String, flow: String) -> String:
	var general := notes(stage)
	var own := notes(stage + "_" + flow)
	var parts: PackedStringArray = []
	if stage == "pre":
		parts = [general, own]
	else:
		parts = [own, general]
	var shown: PackedStringArray = []
	for part in parts:
		if part != "":
			shown.append(part)
	return "\n\n".join(shown)


#* The manifest's entry for one kind of notes, {"file", "sha256"}, or {} when there's none:
func _notes_entry(kind: String) -> Dictionary:
	var listed = manifest.get("notes", {})
	if not listed is Dictionary or not listed.get(kind) is Dictionary:
		return {}
	return listed[kind]


#* The manifest's shape, and every path it names:
func _check_manifest() -> String:
	if int(manifest.get("format", 0)) > Utils.MANIFEST_FORMAT:
		return "This release was made for a newer version of Candy Wizard. Update Candy Wizard first."
	if manifest.get("package", "") != package_name:
		return "This zip isn't a %s release." % title
	if version() == "":
		return "The release's manifest doesn't give a version."
	#? The version names folders: digits and dots only.
	if not Utils.is_plain_version(version()):
		return "The release's manifest gives a version that can't be read (%s). It was refused." % version()
	var file_list = manifest.get("files")
	if not file_list is Dictionary or file_list.is_empty():
		return "The release's manifest lists no files."
	for path in file_list:
		#? Paths must stay inside the package's folder.
		if not String(path).begins_with(root) or ".." in String(path).split("/") or "\\" in String(path):
			return "The release's manifest names a file outside the %s folder (%s). It was refused." % [root.trim_suffix("/"), path]
	#? Notes only under the names Candy Wizard knows.
	var listed_notes = manifest.get("notes", {})
	if not listed_notes is Dictionary:
		return "The release's manifest lists its notes wrongly."
	for kind in Utils.NOTES_FILES:
		if listed_notes.has(kind) and (not listed_notes[kind] is Dictionary or listed_notes[kind].get("file") != Utils.NOTES_FILES[kind]):
			return "The release's manifest lists its %s notes wrongly." % kind
	if package_name != Utils.PACKAGE_NAME:
		#? A plugin's plugin.cfg gives the version Godot shows: it must agree.
		var config_path := root + "plugin.cfg"
		if not file_list.has(config_path) or not zip_entries.has(config_path):
			return "The release has no plugin.cfg."
		var config := ConfigFile.new()
		if config.parse(reader.read_file(config_path).get_string_from_utf8()) != OK or str(config.get_value("plugin", "version", "")) != version():
			return "The release's plugin.cfg doesn't give version %s, as its manifest does." % version()
	return ""


#* Whether this release can be installed with this Candy Wizard and this Godot version:
func check_compatibility(wizard_version: String) -> String:
	var wizard_min := String(manifest.get("wizard_min", ""))
	if wizard_min != "" and Utils.compare_versions(wizard_version, wizard_min) < 0:
		return "%s %s needs version %s or newer of Candy Wizard (this one is %s). Update Candy Wizard first." % [title, version(), wizard_min, wizard_version]
	var godot_min := String(manifest.get("godot_min", ""))
	if godot_min != "" and Utils.compare_versions(Utils.godot_version(), godot_min) < 0:
		return "%s %s needs Godot %s or newer (this editor is %s)." % [title, version(), godot_min, Utils.godot_version()]
	return ""


#* Checks every file the manifest lists is in the zip, undamaged:
func verify() -> String:
	var file_list := files()
	for path in file_list:
		if not zip_entries.has(path):
			return "The release is incomplete: %s is missing." % path
		var expected := String(file_list[path].get("sha256", ""))
		if Utils.content_hash(path, reader.read_file(path)) != expected:
			return "The release is damaged: %s doesn't match its manifest. Download it again." % path
	for kind in Utils.NOTES_FILES:
		var entry := _notes_entry(kind)
		if entry.is_empty():
			continue
		var notes_path := String(entry["file"])
		if not zip_entries.has(notes_path):
			return "The release is incomplete: %s is missing." % notes_path
		if Utils.content_hash(notes_path, reader.read_file(notes_path)) != String(entry.get("sha256", "")):
			return "The release is damaged: %s doesn't match its manifest. Download it again." % notes_path
	return ""
