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


const Utils = preload("Wizard_Utils.gd")
const DocsSource = preload("Docs_Source.gd")

#^ How a look went:
enum Result { UPDATED, UNCHANGED, FAILED, NO_SOURCE }

#^ Starts a news item's line (leading spaces allowed):
const ITEM_MARKER := "====="
#^ Auto is on until the developer unticks it:
const DEFAULT_AUTO := true
#^ Largest News.txt taken:
const MAX_BYTES := 256 * 1024

#^ API base ("" = GitHub's). For tests only:
var api_base := ""

var busy := false
#^ Why the last look failed, or "":
var problem := ""

static var _font_regex: RegEx = null
static var _dropcap_font_regex: RegEx = null
static var _image_regex: RegEx = null


#==============================================================================
#  WHAT'S KEPT
#==============================================================================

#* Kept news state, or {}:
static func state() -> Dictionary:
	return Utils.last_update_check(Utils.SETTING_NEWS)


#* Merge values into state():
static func _keep(values: Dictionary) -> void:
	var kept := state().duplicate()
	kept.merge(values, true)
	EditorInterface.get_editor_settings().set_setting(Utils.SETTING_NEWS, kept)


#* Whether the dock looks for news by itself:
static func auto() -> bool:
	return bool(state().get("auto", DEFAULT_AUTO))


static func set_auto(value: bool) -> void:
	_keep({"auto": value})


#* Last look GitHub answered (Unix time), or 0:
static func last_look() -> float:
	return float(state().get("time", 0.0))


#* The sources with a repository, in the order they're shown:
static func sources() -> Array:
	return Utils.NEWS_SOURCES.filter(func(source: Dictionary) -> bool: return int(source.get("repository_id", 0)) != 0)


static func has_source() -> bool:
	return not sources().is_empty()


#* A source's last copy - {text, etag}, or {}:
static func copy(source_id: String) -> Dictionary:
	var copies = state().get("copies", {})
	if copies is Dictionary and copies.get(source_id) is Dictionary:
		return copies[source_id]
	return {}


static func _keep_copy(source_id: String, text: String, etag: String) -> void:
	var copies = state().get("copies", {})
	if copies is Dictionary:
		copies = copies.duplicate()
	else:
		copies = {}
	copies[source_id] = {"text": text, "etag": etag}
	_keep({"copies": copies})


#==============================================================================
#  NEWS ITEMS
#==============================================================================

#* Every source's news items, source after source, safe to show: [{id, text}]
static func items() -> Array:
	var result: Array = []
	for source in sources():
		result.append_array(source_items(str(source["id"])))
	return result


#* A source's items. Their ids start with the source's: "candy_arts/welcome":
static func source_items(source_id: String) -> Array:
	var result: Array = []
	var item_id := ""
	var item_lines: PackedStringArray = []
	var in_item := false
	for line in str(copy(source_id).get("text", "")).replace("\r\n", "\n").split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with(ITEM_MARKER):
			if in_item:
				_add_item(result, source_id, item_id, item_lines)
			item_id = stripped.trim_prefix(ITEM_MARKER).strip_edges()
			item_lines.clear()
			in_item = true
		elif in_item:
			item_lines.append(line)
	if in_item:
		_add_item(result, source_id, item_id, item_lines)
	return result


static func _add_item(result: Array, source_id: String, item_id: String, lines: PackedStringArray) -> void:
	var item := without_resources("\n".join(lines)).strip_edges()
	if item == "":
		return
	#% No identifier on its marker line - its text stands in, so editing it makes it unread again:
	if item_id == "":
		item_id = "text:" + item.sha256_text()
	result.append({"id": source_id + "/" + item_id, "text": item})


#==============================================================================
#  READ ITEMS
#==============================================================================

#* Identifiers of the items already shown:
static func read_ids() -> PackedStringArray:
	return PackedStringArray(state().get("read", []))


static func is_read(item_id: String) -> bool:
	return read_ids().has(item_id)


#* Remember an item as read. Returns whether it was unread:
static func mark_read(item_id: String) -> bool:
	var ids := read_ids()
	if ids.has(item_id):
		return false
	ids.append(item_id)
	_keep({"read": ids})
	return true


#* Whether the last copies have an item not shown yet:
static func has_unread() -> bool:
	var ids := read_ids()
	for item in items():
		if not ids.has(item["id"]):
			return true
	return false


#* Forget the read items a source's last copy no longer has:
#? Only that source's: one that couldn't be downloaded keeps its own.
static func _forget_deleted(source_id: String) -> void:
	var present: Array = source_items(source_id).map(func(item: Dictionary) -> String: return item["id"])
	var ids := read_ids()
	var kept: PackedStringArray = []
	for item_id in ids:
		if not item_id.begins_with(source_id + "/") or present.has(item_id):
			kept.append(item_id)
	if kept.size() != ids.size():
		_keep({"read": kept})


#* Strip tags that load a file ([img], [font], a [dropcap]'s font), as a resource can carry a script:
static func without_resources(bbcode: String) -> String:
	if _font_regex == null:
		_font_regex = RegEx.create_from_string("\\[font[= ][^\\]]*\\]")
		_dropcap_font_regex = RegEx.create_from_string("(\\[dropcap[^\\]]*?)\\s+font=[^\\s\\]]*")
		_image_regex = RegEx.create_from_string("\\[img[^\\]]*\\][^\\[]*\\[/img\\]")
	var out := _image_regex.sub(bbcode, "", true)
	out = out.replace("[img", "[lb]img")	#/ An [img] with no clear end is shown as text
	out = _font_regex.sub(out, "", true)
	out = out.replace("[/font]", "")
	out = _dropcap_font_regex.sub(out, "$1", true)
	return out


#==============================================================================
#  LOOKING ON GITHUB
#==============================================================================

#* Look on GitHub for every source, keep the changed copies:
#? Returns a Result: UPDATED if any source changed, FAILED if none did and one failed.
#? The failures' reasons go in problem.
func refresh() -> int:
	if busy:
		return Result.UNCHANGED
	problem = ""
	if not has_source():
		return Result.NO_SOURCE
	busy = true
	var github := DocsSource.new()
	if api_base != "":
		github.api_base = api_base
	add_child(github)
	var updated := false
	var failures: PackedStringArray = []
	for source in sources():
		var source_id := str(source["id"])
		var kept := copy(source_id)
		var etag := ""
		if str(kept.get("text", "")) != "":
			etag = str(kept.get("etag", ""))
		var answer: Dictionary = await github.fetch_file(str(source.get("repository", "")), int(source["repository_id"]),
			str(source.get("branch", "")), str(source.get("path", "")), etag, MAX_BYTES)
		if answer.has("error"):
			failures.append("%s couldn't be downloaded. %s" % [str(source.get("title", source_id)), str(answer["error"])])
			continue
		if answer.has("unchanged"):
			continue
		var new_text := (answer["bytes"] as PackedByteArray).get_string_from_utf8()
		var changed := new_text != str(kept.get("text", ""))
		_keep_copy(source_id, new_text, str(answer.get("etag", "")))
		if changed:
			updated = true
			_forget_deleted(source_id)
	github.queue_free()
	busy = false
	problem = "\n".join(failures)
	#% GitHub answered for at least one source:
	if failures.size() < sources().size():
		_keep({"time": Time.get_unix_time_from_system()})
	if updated:
		return Result.UPDATED
	if not failures.is_empty():
		return Result.FAILED
	return Result.UNCHANGED
