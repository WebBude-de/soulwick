class_name HostStallNotice
extends CanvasLayer
## What a player sees when the host's game stands still (D-183), child of the LobbyClient so it works
## in the village and in the dungeon (no change to game.tscn). Look only: NetPlayerState holds the
## players, RelayPeer measures (HostStall).
## - Client: from HostStall.NOTICE_MSEC on a small panel in the upper middle, "Warte auf den Host …"
##   with the host's name and the seconds; from HostStall.LEAVE_MSEC on the button "Raum verlassen"
##   (LobbyClient.leave(); the pause menu works too). Gone as soon as the host's game runs again.
## - Host: a short note afterwards when its own game stood still with teammates in the room
##   (RelayPeer.host_hitched, "Deine Mitspieler haben 12 s auf dich gewartet."; in the browser with
##   the tip to keep the tab visible), and in the browser one hint when it opens a room.
## Mouse passes through everything but the button; readable on a phone (sizes in mockup px, UiKit).

const NODE_NAME := &"HostStallNotice"
## Preloaded: work before the global class cache knows the new files.
const HostStallScript := preload("res://online/host_stall.gd")
const WebKeepAliveScript := preload("res://online/web_keep_alive.gd")
## Above the touch controls (25), below the pause menu (GameUI, 30).
const LAYER := 26
## Mockup px: the panel's top as a share of the screen height, the width of its text.
const TOP_SHARE := 0.2
const TEXT_WIDTH := 190.0
## TESTWERT: seconds a host note stays (the last FADE_SECONDS fade out).
const NOTE_SECONDS := 7.0
const FADE_SECONDS := 0.6
const TITLE_COLOR := Color(1.0, 0.85, 0.4)

enum Mode { NONE, WAIT, NOTE }

var _mode := Mode.NONE
var _note_left := 0.0
var _panel: PanelContainer = null
var _title: Label = null
var _sub: Label = null
var _meta: Label = null
var _leave: Button = null
## Tests and tools: how often the wait panel and a host note appeared.
var wait_count := 0
var note_count := 0


## Translated text of key with args; fallback (English) while the key has no translation yet.
static func text(key: StringName, args: Array, fallback: String) -> String:
	var result := Loc.t(key)
	if result.is_empty() or result == String(key):
		result = fallback
	if args.is_empty() or not result.contains("%"):
		return result
	return result % args


## Host note after its game stood still for gap_msec: [title, lines…]. web adds the browser tip.
static func host_away_lines(gap_msec: int, web: bool) -> PackedStringArray:
	var lines := PackedStringArray([
		text(&"NET_HOST_AWAY_TITLE", [], "Your game was paused"),
		text(&"NET_HOST_AWAY", [maxi(1, roundi(float(gap_msec) / 1000.0))], "Your teammates waited %d s for you."),
	])
	if web:
		lines.append(text(&"NET_HOST_AWAY_WEB", [], "In the browser, keep this tab visible – or host with the desktop version."))
	return lines


func _init() -> void:
	name = NODE_NAME
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.get_theme()
	add_child(root)
	_panel = UiKit.panel(&"dark")
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 5, 8))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	root.add_child(_panel)
	var box := UiKit.vbox(int(UiKit.px(3)))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(box)
	_title = UiKit.text_label("", UiKit.SIZE_CARD_NAME, TITLE_COLOR, true)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = UiKit.wrapped_text("", TEXT_WIDTH, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	_sub.name = "Sub"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)
	_meta = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	_meta.name = "Meta"
	_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_meta)
	_leave = UiKit.dialog_button(text(&"LOBBY_LEAVE", [], "Leave room"), "", _on_leave)
	_leave.name = "Leave"
	_leave.focus_mode = Control.FOCUS_ALL
	_leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_leave.visible = false
	box.add_child(_leave)


func _process(delta: float) -> void:
	var lobby := get_parent() as LobbyClient
	var peer := lobby.peer if lobby != null and lobby.is_in_room() else null
	var stall := peer.get_host_stall_msec() if peer != null else 0
	update_wait(stall, _host_name(lobby))
	if _mode == Mode.NOTE:
		_note_left -= delta
		_panel.modulate.a = clampf(_note_left / FADE_SECONDS, 0.0, 1.0)
		if _note_left <= 0.0:
			_hide()
	if _panel.visible:
		_place()


## The wait panel for a host that stood still for stall_msec (0 = it runs): shown from
## HostStall.NOTICE_MSEC on, with the leave button from HostStall.LEAVE_MSEC on.
func update_wait(stall_msec: int, host_name := "") -> void:
	if stall_msec < HostStallScript.NOTICE_MSEC:
		if _mode == Mode.WAIT:
			_hide()
		return
	if _mode != Mode.WAIT:
		_mode = Mode.WAIT
		wait_count += 1
		_panel.modulate.a = 1.0
		_set_texts(text(&"NET_HOST_STALL_TITLE", [], "Waiting for the host …"),
				text(&"NET_HOST_STALL_SUB", [], "The host's game is not responding right now. It continues as soon as it runs again."))
	var seconds := text(&"NET_HOST_STALL_SECONDS", [floori(stall_msec / 1000.0)], "for %d s")
	var meta := seconds if host_name.is_empty() else "%s · %s" % [host_name, seconds]
	if _meta.text != meta:
		_meta.text = meta
	_meta.visible = true
	var offer := stall_msec >= HostStallScript.LEAVE_MSEC
	if _leave.visible != offer:
		_leave.visible = offer
	_panel.visible = true


## Host: its game stood still for gap_msec with teammates in the room (RelayPeer.host_hitched).
func show_host_away(gap_msec: int) -> void:
	var lines := host_away_lines(gap_msec, WebKeepAliveScript.is_supported())
	_show_note(lines[0], "\n".join(lines.slice(1)))


## Host in the browser: one hint when it opens a room.
func show_web_host_hint() -> void:
	_show_note(text(&"LOBBY_WEB_HOST_HINT_TITLE", [], "You are the host"),
			text(&"LOBBY_WEB_HOST_HINT", [], "Hosting in the browser: keep this tab visible, or your teammates have to wait."))


func is_waiting() -> bool:
	return _mode == Mode.WAIT and _panel.visible


func is_note_visible() -> bool:
	return _mode == Mode.NOTE and _panel.visible


func is_leave_offered() -> bool:
	return is_waiting() and _leave.visible


func get_title() -> String:
	return _title.text if _panel.visible else ""


## Title, sub line and meta line on screen (empty ones left out).
func get_text() -> String:
	if not _panel.visible:
		return ""
	var parts := PackedStringArray()
	for label: Label in [_title, _sub, _meta]:
		if label.visible and not label.text.is_empty():
			parts.append(label.text)
	return "\n".join(parts)


func get_leave_button() -> Button:
	return _leave


func _show_note(title: String, body: String) -> void:
	if _mode == Mode.WAIT:
		return
	_mode = Mode.NOTE
	note_count += 1
	_note_left = NOTE_SECONDS
	_panel.modulate.a = 1.0
	_set_texts(title, body)
	_meta.visible = false
	_leave.visible = false
	_panel.visible = true
	if is_inside_tree():
		_place()


func _set_texts(title: String, body: String) -> void:
	_title.text = title
	_sub.text = body
	_sub.visible = not body.is_empty()


func _hide() -> void:
	_mode = Mode.NONE
	_panel.visible = false
	_leave.visible = false
	if _leave.has_focus():
		_leave.release_focus()


## Upper middle of the screen (below the top bars and the co-op wait line).
func _place() -> void:
	_panel.reset_size()
	var size := _panel.get_combined_minimum_size()
	var view := _panel.get_parent_area_size()
	_panel.position = Vector2(roundf((view.x - size.x) * 0.5), roundf(view.y * TOP_SHARE))
	_panel.size = size


func _host_name(lobby: LobbyClient) -> String:
	if lobby == null:
		return ""
	for peer: Variant in lobby.get_room_peers():
		if peer is Dictionary and int(peer.get("peerId", 0)) == RelayProtocol.HOST_PEER_ID:
			return str(peer.get("name", ""))
	return ""


func _on_leave() -> void:
	var lobby := get_parent() as LobbyClient
	if lobby != null and lobby.is_in_room():
		lobby.leave()
	_hide()

