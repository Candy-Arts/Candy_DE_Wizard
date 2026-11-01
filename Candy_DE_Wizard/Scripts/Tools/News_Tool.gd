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


const Utils = preload("../Wizard_Utils.gd")
const Style = preload("../UI_Style.gd")
const News = preload("../News.gd")

#^ Seconds between the dock's looks on GitHub:
const UPDATE_CHECK_INTERVAL := 24 * 60 * 60
const REFRESH_TEXT := "Refresh"
const CHECKING_TEXT := "Checking…"
#^ How long the Refresh button shows the result:
const RESULT_SECONDS := 2.5
const RESULT_TEXTS := {
	News.Result.UPDATED: "Updated",
	News.Result.UNCHANGED: "Up to date",
	News.Result.FAILED: "Couldn't refresh",
	News.Result.NO_SOURCE: "No news source",
}
#^ The Refresh button's result when only some of the news could be downloaded:
const PARTLY_TEXT := "Partly refreshed"
const REFRESH_TOOLTIP := "Look for news now, on Candy Arts' GitHub repository: Candy DE's news and Candy Arts'. Nothing is sent but the requests for the news itself."
const UNREAD_MARK_SIZE := 14
const NEW_ITEM_TOOLTIP := "You're reading this news for the first time."
const UNREAD_AHEAD_TOOLTIP := "There's news you haven't read further on."

#^ An item was read, or the news changed:
signal unread_changed

#^ Tests only - a local stand-in for GitHub's API:
var test_api_base := ""

var news: Node
var auto_box: CheckBox
var refresh_button: Button
var previous_button: Button
var next_button: Button
var news_text: RichTextLabel
#^ Unread marks - beside the title (the item shown is new), beside Next (unread items further on):
var new_item_mark: TextureRect
var unread_ahead_mark: TextureRect
var items: Array = []						#/ [{id, text}]
var index := 0
#^ The item shown was unread when it was first seen:
var showing_new := false
#^ Auto look done this session (even if it failed):
var looked := false
#^ Look counter, so an older look's timer doesn't reset a newer one's text:
var check_count := 0


func _ready() -> void:
	news = News.new()
	add_child(news)

	var box := Style.card_box(self)
	box.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title_row := Style.card_title(box, "Notification", "News")
	new_item_mark = _unread_mark()
	title_row.add_child(new_item_mark)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	previous_button = Style.button("Previous", "Back", _show_item.bind(-1))
	title_row.add_child(previous_button)
	next_button = Style.button("Next", "Forward", _show_item.bind(1))
	next_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(next_button)
	unread_ahead_mark = _unread_mark()
	title_row.add_child(unread_ahead_mark)
	var divider := VSeparator.new()
	divider.custom_minimum_size.x = Style.px(8)
	title_row.add_child(divider)
	auto_box = CheckBox.new()
	auto_box.text = "Auto"
	auto_box.tooltip_text = "Look for news when the editor opens, at most once a day."
	auto_box.set_pressed_no_signal(News.auto())
	auto_box.toggled.connect(func(pressed: bool) -> void: News.set_auto(pressed))
	title_row.add_child(auto_box)
	refresh_button = Style.button(REFRESH_TEXT, "Reload", check.bind(true))
	refresh_button.tooltip_text = REFRESH_TOOLTIP
	#? Left-aligned: the button keeps its widest text's width.
	refresh_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_row.add_child(refresh_button)
	_fit_refresh_button()

	#? Scrolls by itself: the bottom panel takes its content's height.
	news_text = Style.rich_text(false)
	news_text.custom_minimum_size.y = Style.px(96)
	news_text.meta_clicked.connect(func(meta: Variant) -> void: Utils.open_web_link(str(meta)))
	box.add_child(news_text)

	#? An item counts as read once it's on screen, not while another tool hides it.
	visibility_changed.connect(_mark_shown_item)
	_load_items()


#==============================================================================
#  LOOKING ON GITHUB
#==============================================================================

#* Download and show the news:
func check(forced: bool) -> bool:
	if news.busy:
		return false
	#% Not forced (the dock's check): only with Auto on, once a day and per session:
	if not forced:
		if looked or not News.auto() or not News.has_source():
			return false
		if Time.get_unix_time_from_system() - News.last_look() < UPDATE_CHECK_INTERVAL:
			return false
		looked = true
	check_count += 1
	refresh_button.text = CHECKING_TEXT
	refresh_button.disabled = true
	news.api_base = test_api_base
	var result: int = await news.refresh()
	refresh_button.disabled = false
	refresh_button.text = RESULT_TEXTS[result]
	refresh_button.tooltip_text = REFRESH_TOOLTIP
	if news.problem != "":
		refresh_button.tooltip_text += "\n\n" + news.problem
		#? Some news came, some didn't:
		if result != News.Result.FAILED:
			refresh_button.text = PARTLY_TEXT
	var count := check_count
	get_tree().create_timer(RESULT_SECONDS).timeout.connect(func() -> void:
		if count == check_count and not news.busy:
			refresh_button.text = REFRESH_TEXT)

	if result == News.Result.UPDATED:
		_load_items()
	elif items.is_empty():
		_show_placeholder(result)
	return result != News.Result.NO_SOURCE	#/ GitHub was asked


#==============================================================================
#  NEWS ITEMS
#==============================================================================

#* Show the last copy's items, from the first:
func _load_items() -> void:
	items = News.items()
	index = 0
	if items.is_empty():
		_show_placeholder(-1)
	else:
		_show_item(0)
	unread_changed.emit()


#* step - -1 = Previous, 1 = Next, 0 = the current item:
func _show_item(step: int) -> void:
	if items.is_empty():
		return
	var new_index := clampi(index + step, 0, items.size() - 1)
	if new_index != index or step == 0:
		showing_new = false
	index = new_index
	news_text.text = items[index]["text"]
	news_text.scroll_to_line(0)
	previous_button.disabled = index == 0
	next_button.disabled = index >= items.size() - 1
	_mark_shown_item()


#* Message with no news. result - the last look's, or -1 before any:
func _show_placeholder(result: int) -> void:
	showing_new = false
	_update_marks()
	previous_button.disabled = true
	next_button.disabled = true
	var message := "No news yet."
	if not News.has_source():
		message = "No news source is set in this version of Candy Wizard."
	elif result == News.Result.FAILED:
		message = news.problem
	elif news.problem != "":
		message += "\n" + news.problem
	elif result == -1 and (not News.auto() or News.last_look() == 0.0):
		message = "Press Refresh to download the news."
	news_text.clear()
	news_text.push_color(Style.dim())
	news_text.add_text(message)
	news_text.pop()


#==============================================================================
#  UNREAD NEWS
#==============================================================================

#* Remember the item shown as read, if the tool is on screen:
func _mark_shown_item() -> void:
	if is_visible_in_tree() and index < items.size():
		if News.mark_read(items[index]["id"]):
			showing_new = true
			unread_changed.emit()
	_update_marks()


func _update_marks() -> void:
	_set_mark(new_item_mark, showing_new, NEW_ITEM_TOOLTIP)
	var ahead := false
	var ids := News.read_ids()
	for later in range(index + 1, items.size()):
		if not ids.has(items[later]["id"]):
			ahead = true
			break
	_set_mark(unread_ahead_mark, ahead, UNREAD_AHEAD_TOOLTIP)


#* Hidden marks stay transparent rather than invisible, so the row doesn't shift:
func _set_mark(mark: TextureRect, shown: bool, tooltip: String) -> void:
	if shown:
		mark.modulate.a = 1.0
		mark.tooltip_text = tooltip
	else:
		mark.modulate.a = 0.0
		mark.tooltip_text = ""


func _unread_mark() -> TextureRect:
	var mark := Style.icon_rect(Style.unread_mark(UNREAD_MARK_SIZE), UNREAD_MARK_SIZE)
	mark.modulate.a = 0.0
	return mark


#* Size the Refresh button for its widest text, so the row doesn't shift:
func _fit_refresh_button() -> void:
	var widest := 0.0
	for shown in [CHECKING_TEXT] + RESULT_TEXTS.values() + [REFRESH_TEXT]:
		refresh_button.text = shown
		widest = maxf(widest, refresh_button.get_minimum_size().x)
	refresh_button.custom_minimum_size.x = widest
