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


signal download_progress(downloaded: int, total: int)

const Utils = preload("Wizard_Utils.gd")

const API_HEADERS := [
	"Accept: application/vnd.github+json",
	"X-GitHub-Api-Version: 2022-11-28",
	"User-Agent: Candy-Wizard",
]
const DOWNLOAD_HEADERS := [
	"User-Agent: Candy-Wizard",
]

#^ How many releases are read, newest first. Only the newest installable one is offered:
const RELEASES_READ := 30
#^ Read to find one version (fetch_release()) - GitHub's most, so older versions are found:
const RELEASES_READ_ALL := 100
#^ Seconds GitHub's API gets to answer (downloads have no limit):
const API_TIMEOUT := 20.0
#^ The first Candy DE version with a release zip (earlier ones are installed by hand):
const FIRST_PACKAGED_VERSION := "1.2.0"

#^ What's looked for, set before the node is used (Candy DE's releases by default):
var repository := Utils.GITHUB_REPOSITORY		#/ "owner/repository", for messages; empty: none set up
var repository_id := Utils.GITHUB_REPOSITORY_ID	#/ What GitHub is asked by; 0: none set up
var package_name := Utils.PACKAGE_NAME			#/ Release zips are named <package_name>_<version>.zip
var title := "Candy DE"							#/ For messages
var first_packaged_version := FIRST_PACKAGED_VERSION	#/ "": every release has a zip
#^ Where GitHub's API is. Only tests change it (a local stand-in for GitHub):
var api_base := "https://api.github.com"

var http: HTTPRequest = null
var downloading := false


func _ready() -> void:
	http = HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	set_process(false)


func _process(_delta: float) -> void:
	if downloading:
		download_progress.emit(http.get_downloaded_bytes(), http.get_body_size())


#* Looks for Candy Wizard's own releases instead of Candy DE's:
func use_wizard_repository() -> void:
	repository = Utils.WIZARD_GITHUB_REPOSITORY
	repository_id = Utils.WIZARD_GITHUB_REPOSITORY_ID
	package_name = Utils.WIZARD_PACKAGE_NAME
	title = "Candy Wizard"
	first_packaged_version = ""


#* Looks for Candy Database's releases instead of Candy DE's:
func use_database_repository() -> void:
	repository = Utils.DATABASE_GITHUB_REPOSITORY
	repository_id = Utils.DATABASE_GITHUB_REPOSITORY_ID
	package_name = Utils.DATABASE_PACKAGE_NAME
	title = "Candy Database"
	first_packaged_version = ""


#* Where GitHub's API has a repository, by its ID:
func repository_url(id: int) -> String:
	return "%s/repositories/%d" % [api_base, id]


#* The message for a repository GitHub doesn't have under its ID:
static func missing_text(what: String) -> String:
	return "%s isn't on GitHub, or isn't public." % what


#* The newest published release Candy Wizard can install, or {"error"}:
func fetch_latest_release() -> Dictionary:
	var listed = await _fetch_releases(RELEASES_READ)
	if listed is Dictionary:
		return listed

	#? GitHub lists by creation date (a fix to an older version can come later): compare versions.
	var newest := {}
	var installable := {}
	for found in listed:
		if newest.is_empty() or Utils.compare_versions(found["version"], newest["version"]) > 0:
			newest = found
		if found.has("asset_url"):
			if installable.is_empty() or Utils.compare_versions(found["version"], installable["version"]) > 0:
				installable = found
	if not installable.is_empty():
		return installable	#/ "version", "date", "notes" (Markdown), "page_url", "tag", "asset_name", "asset_url", "asset_size"
	if newest.is_empty():
		return {"error": "There's no %s release on GitHub yet." % title}
	if first_packaged_version != "" and Utils.compare_versions(newest["version"], first_packaged_version) < 0:
		newest["error"] = "%s %s can't be installed by Candy Wizard, which installs %s %s and later. Earlier versions are installed by hand." % [title, newest["version"], title, first_packaged_version.trim_suffix(".0")]
	else:
		newest["error"] = "%s %s has no release zip (%s_%s.zip) to download." % [title, newest["version"], package_name, newest["version"]]
	return newest	#/ The newest release's details, with "error"


#* One published release by version (its tag may be "v1.2.0" or "1.2"), as fetch_latest_release():
#? On failure holds "error", and the release's details when it has no zip.
func fetch_release(version: String) -> Dictionary:
	var listed = await _fetch_releases(RELEASES_READ_ALL)
	if listed is Dictionary:
		return listed
	#? Two releases may give the version ("1.2" and "1.2.0"): the one with a zip is taken.
	var without_zip := {}
	for found in listed:
		if Utils.compare_versions(found["version"], version) != 0:
			continue
		if found.has("asset_url"):
			return found
		if without_zip.is_empty():
			without_zip = found
	if without_zip.is_empty():
		return {"error": "%s %s isn't among the releases on GitHub." % [title, version]}
	without_zip["error"] = "%s %s has no release zip (%s_%s.zip) to download." % [title, without_zip["version"], package_name, without_zip["version"]]
	return without_zip


#* The published releases (not drafts or pre-releases), newest first by creation date:
#? As _release_details() gives them, or a Dictionary holding "error".
func _fetch_releases(count: int) -> Variant:
	if repository == "" or repository_id == 0:
		return {"error": "No release repository is set up in this version of Candy Wizard."}
	var url := "%s/releases?per_page=%d" % [repository_url(repository_id), count]
	http.download_file = ""
	http.timeout = API_TIMEOUT
	var error := http.request(url, API_HEADERS)
	if error != OK:
		return {"error": "Couldn't contact GitHub (%s)." % error_string(error)}
	var response: Array = await http.request_completed
	var response_error := _response_error(response, "Checking GitHub", missing_text("The %s repository" % title))
	if response_error != "":
		return {"error": response_error}
	var parsed = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Array:
		return {"error": "GitHub's answer couldn't be read."}
	var releases := []
	for entry in parsed:
		if not entry is Dictionary or bool(entry.get("draft", false)) or bool(entry.get("prerelease", false)):
			continue
		var found := _release_details(entry)
		if found["version"] != "":
			releases.append(found)
	return releases


#* A release from GitHub's list, and its release zip if it has one:
func _release_details(entry: Dictionary) -> Dictionary:
	var tag := _text(entry, "tag_name")
	var details := {
		"version": tag.trim_prefix("v").trim_prefix("V"),
		"tag": tag,
		"date": _text(entry, "published_at").substr(0, 10),
		"notes": _text(entry, "body"),
		"page_url": _text(entry, "html_url"),
	}
	var assets = entry.get("assets")
	if not assets is Array:
		assets = []
	for asset in assets:
		if not asset is Dictionary or _text(asset, "state", "uploaded") != "uploaded":
			continue
		#? <package_name>_<version>.zip with a plain version only, so Candy_DE_Wizard_1.0.1.zip isn't
		#? taken for another package's.
		var asset_name := _text(asset, "name")
		var prefix := package_name + "_"
		if not asset_name.begins_with(prefix) or not asset_name.to_lower().ends_with(".zip"):
			continue
		var asset_version := asset_name.substr(prefix.length(), asset_name.length() - prefix.length() - 4)
		if not Utils.is_plain_version(asset_version) or Utils.compare_versions(asset_version, details["version"]) != 0:
			continue
		details["asset_name"] = asset_name
		details["asset_url"] = _text(asset, "browser_download_url")
		details["asset_size"] = int(asset.get("size", 0))
		break
	return details


#* A text of GitHub's answer, or fallback when it has none:
static func _text(data: Dictionary, key: String, fallback: String = "") -> String:
	var value = data.get(key)
	if value is String:	#/ GitHub writes null for what a release lacks, which String() can't take
		return value
	return fallback


#* Downloads a file to target_path, returning an error message or "":
func download(url: String, target_path: String) -> String:
	DirAccess.make_dir_recursive_absolute(target_path.get_base_dir())
	http.download_file = target_path
	http.timeout = 0.0
	var error := http.request(url, DOWNLOAD_HEADERS)
	if error != OK:
		http.download_file = ""
		return "Couldn't start the download (%s)." % error_string(error)
	downloading = true
	set_process(true)
	var response: Array = await http.request_completed
	downloading = false
	set_process(false)
	http.download_file = ""
	var response_error := _response_error(response, "The download", "The release zip isn't on GitHub anymore: it may have been replaced. Open the wizard again to get the latest release.")
	if response_error != "":
		DirAccess.remove_absolute(target_path)
		return response_error
	return ""


func cancel() -> void:
	if http != null:
		http.cancel_request()
	downloading = false
	set_process(false)


#* What went wrong with a request_completed response, or "" if it succeeded:
#? not_found - the message for a 404.
func _response_error(response: Array, what: String, not_found: String) -> String:
	var result: int = response[0]
	var code: int = response[1]
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return "%s failed: the file is larger than Candy Wizard takes." % what
	if result != HTTPRequest.RESULT_SUCCESS:
		return "%s failed: couldn't reach the server. Check your internet connection. (%s)" % [what, _result_text(result)]
	if code == 404:
		return not_found
	if code == 403 or code == 429:
		return "GitHub refused the request: it limits how often it can be asked (60 times an hour). %s" % _retry_text(response[2])
	if code < 200 or code >= 300:
		return "%s failed: the server answered with error %d." % [what, code]
	return ""


#* When GitHub's limit is lifted, from its answer's headers:
func _retry_text(headers: PackedStringArray) -> String:
	for header in headers:
		if header.to_lower().begins_with("x-ratelimit-reset:"):
			var reset := header.get_slice(":", 1).strip_edges().to_int()
			var minutes := ceili((reset - Time.get_unix_time_from_system()) / 60.0)
			if minutes > 1:
				return "Try again in %d minutes." % minutes
			if minutes == 1:
				return "Try again in a minute."
	return "Try again in a while."


func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "host not found"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection failed"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "secure connection failed"
		HTTPRequest.RESULT_TIMEOUT:
			return "timed out"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "couldn't save the file"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "too many redirects"
	return "error %d" % result
