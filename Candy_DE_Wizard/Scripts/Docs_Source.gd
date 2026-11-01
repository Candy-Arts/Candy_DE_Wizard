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
extends "Release_Source.gd"


signal files_progress(done: int, total: int)

#^ Raw files base. For tests only:
var raw_base := "https://raw.githubusercontent.com"

#^ Files downloaded at once:
const PARALLEL_DOWNLOADS := 4
#^ Seconds one file's download gets:
const FILE_TIMEOUT := 60.0
#^ API_HEADERS asking for the file itself:
const FILE_HEADERS := [
	"Accept: application/vnd.github.raw+json",
	"X-GitHub-Api-Version: 2022-11-28",
	"User-Agent: Candy-Wizard",
]

var workers: Array[HTTPRequest] = []


#* A branch's files - {"commit", "files" = {path = git hash}, "folders" = {path = git hash}}, or {"error"}:
#? Asked by repo_id; repo (the name) is for messages.
func fetch_tree(repo: String, repo_id: int, branch: String) -> Dictionary:
	if repo_id == 0:
		return {"error": "No repository is set up for this documentation in this version of Candy Wizard."}
	var ref = await _get_json("%s/git/ref/heads/%s" % [repository_url(repo_id), branch.uri_encode()], missing_text("The documentation's repository (or its %s branch)" % branch))
	if ref is Dictionary and ref.has("error"):
		return ref
	if not ref is Dictionary or not ref.get("object") is Dictionary:
		return {"error": "GitHub's answer couldn't be read."}
	var commit := String(ref["object"].get("sha", ""))
	var listing = await _get_json("%s/git/trees/%s?recursive=1" % [repository_url(repo_id), commit], "%s's files weren't found on GitHub." % repo)
	if listing is Dictionary and listing.has("error"):
		return listing
	if not listing is Dictionary or not listing.get("tree") is Array:
		return {"error": "GitHub's answer couldn't be read."}
	if bool(listing.get("truncated", false)):
		return {"error": "%s has too many files for GitHub to list them all at once." % repo}
	var files := {}
	var folders := {}
	for entry in listing["tree"]:
		if not entry is Dictionary:
			continue
		match String(entry.get("type", "")):
			"blob":
				files[String(entry.get("path", ""))] = String(entry.get("sha", ""))
			"tree":
				folders[String(entry.get("path", ""))] = String(entry.get("sha", ""))
	return {"commit": commit, "files": files, "folders": folders}


#* API request's JSON answer, or {"error"}:
func _get_json(url: String, not_found: String) -> Variant:
	http.download_file = ""
	http.timeout = API_TIMEOUT
	var error := http.request(url, API_HEADERS)
	if error != OK:
		return {"error": "Couldn't contact GitHub (%s)." % error_string(error)}
	var response: Array = await http.request_completed
	var response_error := _response_error(response, "Checking GitHub", not_found)
	if response_error != "":
		return {"error": response_error}
	var parsed = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if parsed == null:
		return {"error": "GitHub's answer couldn't be read."}
	return parsed


#* One file of a branch - {"bytes", "etag"}, {"unchanged" = true} if it matches etag, or {"error"}:
#? Asked by repo_id; _repo (the name) is unused, kept so every fetch takes the same arguments.
func fetch_file(_repo: String, repo_id: int, branch: String, path: String, etag: String, max_bytes: int) -> Dictionary:
	if repo_id == 0:
		return {"error": "No repository is set up for this in this version of Candy Wizard."}
	var headers := PackedStringArray(FILE_HEADERS)
	if etag != "":
		headers.append("If-None-Match: " + etag)
	http.download_file = ""
	http.timeout = API_TIMEOUT
	http.body_size_limit = max_bytes
	var error := http.request("%s/contents/%s?ref=%s" % [repository_url(repo_id), _encoded_path(path), branch.uri_encode()], headers)
	if error != OK:
		http.body_size_limit = -1
		return {"error": "Couldn't contact GitHub (%s)." % error_string(error)}
	var response: Array = await http.request_completed
	http.body_size_limit = -1
	if int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) == 304:
		return {"unchanged": true}
	var response_error := _response_error(response, "Checking GitHub", "It isn't on GitHub, or isn't public.")
	if response_error != "":
		return {"error": response_error}
	var found_etag := ""
	for header in response[2]:
		if String(header).to_lower().begins_with("etag:"):
			found_etag = String(header).substr(5).strip_edges()
	return {"bytes": response[3], "etag": found_etag}


#* Download wanted ({path = git hash}) at a commit, into memory - {"files" = {path = bytes}}, or {"error"}:
func download_files(repo: String, commit: String, wanted: Dictionary) -> Dictionary:
	var queue: Array = wanted.keys()
	var state := {"error": "", "next": 0, "done": 0, "running": 0, "files": {}}
	if queue.is_empty():
		return {"files": {}}
	files_progress.emit(0, queue.size())
	for index in mini(PARALLEL_DOWNLOADS, queue.size()):
		var request := HTTPRequest.new()
		#? Not threaded: cancelling a threaded request freezes the editor until the server answers.
		request.timeout = FILE_TIMEOUT
		add_child(request)
		workers.append(request)
		state["running"] += 1
		_download_next(request, repo, commit, queue, wanted, state)
	while state["running"] > 0 and state["error"] == "":
		await get_tree().process_frame
	#? Cancel the rest. A cancelled request never completes; its _download_next() ends with it.
	for request in workers:
		request.cancel_request()
		request.queue_free()
	workers.clear()
	if state["error"] != "":
		return {"error": state["error"]}
	return {"files": state["files"]}


#* One parallel download - take queued files until none are left or one failed:
func _download_next(request: HTTPRequest, repo: String, commit: String, queue: Array, wanted: Dictionary, state: Dictionary) -> void:
	while state["error"] == "" and state["next"] < queue.size():
		var path := String(queue[state["next"]])
		state["next"] += 1
		var error := request.request("%s/%s/%s/%s" % [raw_base, repo, commit, _encoded_path(path)], DOWNLOAD_HEADERS)
		if error != OK:
			state["error"] = "Couldn't start downloading %s (%s)." % [path.get_file(), error_string(error)]
			break
		var response: Array = await request.request_completed
		if state["error"] != "":
			break
		var response_error := _response_error(response, "Downloading %s" % path.get_file(), "%s isn't on GitHub anymore: check again for updates." % path)
		if response_error != "":
			state["error"] = response_error
			break
		var bytes: PackedByteArray = response[3]
		if Utils.git_blob_hash(path, bytes, false) != String(wanted[path]):	#/ Downloaded by name (raw has no IDs): must match the hash fetch_tree() got by ID
			state["error"] = "%s didn't download right (it doesn't match GitHub's list). Try again." % path
			break
		state["files"][path] = bytes
		state["done"] += 1
		files_progress.emit(state["done"], queue.size())
	state["running"] -= 1


#* URL-encode each path part:
func _encoded_path(path: String) -> String:
	var encoded: PackedStringArray = []
	for part in path.split("/"):
		encoded.append(part.uri_encode())
	return "/".join(encoded)
