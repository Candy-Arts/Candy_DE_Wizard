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

#^ The public keys (written by Make_Release_Keys.gd) - {"keys" = [{"name", "fingerprint", "public" (PEM)}]}:
const KEYS_PATH := "Data/Release_Keys.json"
#^ The signature's file in a release zip - the manifest's name, then this:
const SIGNATURE_SUFFIX := ".sig"

#^ A signature as its file writes it - bytes in hexadecimal:
static var _hex_regex := RegEx.create_from_string(r"^([0-9a-f]{2})+\z")


#* Why a release can't be taken for Candy Arts', or "":
#? signature - its .sig file's text ("" if none). title - the package's name, for messages.
static func problem(manifest_bytes: PackedByteArray, signature: String, title: String) -> String:
	var keys := public_keys()
	if keys.is_empty():
		return "This Candy Wizard has no release keys (%s), so it can't tell whether a release is Candy Arts'. Nothing can be installed with it: get Candy Wizard again from Candy Arts." % KEYS_PATH
	var text := signature.strip_edges().to_lower()
	if text == "":
		return "This zip isn't signed by Candy Arts, so it isn't an official %s release. It was refused." % title
	if _hex_regex.search(text) != null:
		var signature_bytes := text.hex_decode()
		var digest := sha256(manifest_bytes)
		var crypto := Crypto.new()
		for key in keys:
			if crypto.verify(HashingContext.HASH_SHA256, digest, signature_bytes, key):
				return ""
	return "This zip's signature isn't Candy Arts': it isn't an official %s release, or it was changed. It was refused." % title


#* Candy Arts' public keys from KEYS_PATH, empty when the file is missing or holds none:
static func public_keys() -> Array[CryptoKey]:
	var keys: Array[CryptoKey] = []
	var keys_path := Utils.wizard_folder().path_join(KEYS_PATH)
	if not FileAccess.file_exists(keys_path):
		return keys
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(keys_path))
	if not parsed is Dictionary or not parsed.get("keys") is Array:
		return keys
	for entry in parsed["keys"]:
		if not entry is Dictionary or not entry.get("public") is String:
			continue
		var key := CryptoKey.new()
		if key.load_from_string(entry["public"], true) == OK:
			keys.append(key)
	return keys


#* A key's short name - the start of its public PEM's SHA-256 (blanks removed):
static func fingerprint(public_pem: String) -> String:
	var text := public_pem
	for blank in ["\r", "\n", "\t", " "]:
		text = text.replace(blank, "")
	return sha256(text.to_utf8_buffer()).hex_encode().substr(0, 16)


static func sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if bytes.size() > 0:
		context.update(bytes)
	return context.finish()
