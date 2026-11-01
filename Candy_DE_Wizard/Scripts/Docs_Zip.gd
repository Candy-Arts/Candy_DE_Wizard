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

#^ Where a downloaded zip is put to be read (ZIPReader only opens files):
const TEMP_ZIP := Utils.TEMP_FOLDER + "/docs_download.zip"


#* A documentation zip's files - {"files" = {path = bytes}, "left_out" = [paths]}, or {"error"}:
#? folder_name - the database's folder, which every path starts with. title - for messages.
#? Nothing in the zip is believed before its manifest's signature is checked.
static func read(zip_bytes: PackedByteArray, folder_name: String, title: String) -> Dictionary:
	var error := Utils.write_file(TEMP_ZIP, zip_bytes)
	if error != "":
		return {"error": error}
	var reader := ZIPReader.new()
	var result := {}
	if reader.open(TEMP_ZIP) != OK:
		result = {"error": "The %s download isn't a zip file that can be read." % title}
	else:
		result = _read_open(reader, folder_name, title)
		reader.close()
	DirAccess.remove_absolute(TEMP_ZIP)
	return result


static func _read_open(reader: ZIPReader, folder_name: String, title: String) -> Dictionary:
	#@ Step 1 - The signature:
	var manifest_name := Utils.DOCS_MANIFEST_NAME
	if not reader.file_exists(manifest_name):
		return {"error": "The %s download has no %s: it isn't a documentation zip." % [title, manifest_name]}
	var manifest_bytes := reader.read_file(manifest_name)
	var signature := ""
	if reader.file_exists(manifest_name + Signature.SIGNATURE_SUFFIX):
		signature = reader.read_file(manifest_name + Signature.SIGNATURE_SUFFIX).get_string_from_utf8()
	var signature_problem := Signature.problem(manifest_bytes, signature, title)
	if signature_problem != "":
		return {"error": signature_problem}

	#@ Step 2 - The manifest:
	var manifest = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not manifest is Dictionary or not manifest.get("files") is Dictionary:
		return {"error": "The %s zip's manifest can't be read." % title}
	if int(manifest.get("format", 0)) > Utils.DOCS_MANIFEST_FORMAT:
		return {"error": "The %s was made for a newer version of Candy Wizard. Update Candy Wizard first." % title}
	if manifest.get("package") != Utils.DOCS_PACKAGE_NAME or manifest.get("database") != folder_name:
		return {"error": "The %s zip holds another database. It was refused." % title}

	#@ Step 3 - Every file, checked against the manifest:
	var files := {}
	var left_out: PackedStringArray = []
	var prefix := folder_name + "/"
	for path in manifest["files"]:
		var relative := String(path)
		if not relative.begins_with(prefix) or not Utils.is_safe_relative_path(relative):
			return {"error": "The %s zip names a file outside its folder (%s). It was refused." % [title, relative]}
		if not relative.get_extension().to_lower() in Utils.DOCS_EXTENSIONS:
			left_out.append(relative)
			continue
		if not reader.file_exists(relative):
			return {"error": "The %s zip is incomplete: %s is missing." % [title, relative]}
		var entry = manifest["files"][path]
		var bytes := reader.read_file(relative)
		if not entry is Dictionary or Signature.sha256(bytes).hex_encode() != String(entry.get("sha256", "")):
			return {"error": "The %s zip is damaged: %s doesn't match its manifest. Download it again." % [title, relative]}
		files[relative] = bytes
	if files.is_empty():
		return {"error": "The %s zip has no files to download." % title}
	left_out.sort()
	return {"files": files, "left_out": left_out}
