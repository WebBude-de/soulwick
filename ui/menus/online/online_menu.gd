class_name OnlineMenu
extends VBoxContainer
## The online menu (D-147): the same menu in the main menu ("Online spielen", OnlinePanel) and in
## the village's guild building (VillageUI). Two tabs:
## - Schnelles Spiel: create a room or join one by room code (LobbyClient); inside a room the code
##   and one designed place per player (LobbySlot, D-152: figure in its look, name, host crown,
##   status, ping; free places "Wartet auf Spieler …" with "Code teilen"), Start/Leave. The own
##   place has "Aussehen ändern": the profile editor (ProfileEditor) replaces the room view until it
##   is saved or left; the new look reaches everybody in the room (NetPlayers) and the account
##   (PATCH /me).
## - Gilden: the player's guilds (GuildDirectory). Without a guild only two big buttons "Gilde
##   erstellen" / "Gilde beitreten"; with guilds a list and both buttons small at the top right.
##   A guild shows tag, name, own role, the invite code (founder/officer: copy, renew), the
##   treasury, the members with their role (founder: promote/demote officers; founder/officer:
##   remove), "Gilden-Raum erstellen"
##   (relay mode guild, only members may join) and "Gilde verlassen" with a confirmation.
## Without a lobby (main menu) the room buttons emit launch_requested; the main menu loads the save
## and the village runs the wish (LobbyClient.request_launch). The menu never pauses anything itself;
## the village dialog around it pauses only in single player (Modal, GameMode.pauses_for_menus).
## Keyboard and controller: every button takes focus (arrows / d-pad, Enter / A), Esc goes one step
## back (handle_input); W/A/S/D move the focus too. Sizes in mockup pixels (UiKit.px), texts are
## translation keys (D-111) and are rebuilt on a language change.
## Opening logs in (OnlineSession.ensure_login through the first GET /me/guilds, guest or dev
## account) unless login_on_open is off (tests, "-- offline"). Server gone: a friendly line with
## "Erneut versuchen" on both tabs, the menu stays usable (Back), single player is never affected.

## Main menu only (no lobby): create or join a room in the game that starts now. launch: {action,
## mode, guild_id, guild_name, code} for LobbyClient.request_launch.
signal launch_requested(launch: Dictionary)

enum View { QUICK, GUILDS, CREATE, JOIN, DETAIL, CONFIRM, PROFILE }

## Default width in mockup pixels (the main menu panel area is 296 wide).
const DEFAULT_WIDTH := 262.0
## Scroll heights in mockup pixels: guild list and member list (R8: dialogs stay short).
const LIST_HEIGHT := 66.0
const MEMBERS_HEIGHT := 50.0
const CARD_HEIGHT := 22.0
## Width of the member actions column (founder/officer: promote/demote + remove).
const MEMBER_ACTIONS_WIDTH := 118.0
const BUTTON_WIDTH := 58.0
const BIG_BUTTON_WIDTH := 104.0
const BIG_BUTTON_HEIGHT := 30.0
## Content height in the village dialog (mockup pixels): with the dialog's title, tabs and close
## button it stays on a 270 px high screen; taller views scroll.
const VILLAGE_CONTENT_HEIGHT := 140.0
## Focus frame around the focused control (keyboard / controller).
const FOCUS_BORDER := 1.0
## Gap between the player places of a room (mockup pixels).
const SLOT_GAP := 3.0

## The tab of the last menu (reopening keeps it).
static var remembered_view := View.QUICK
## Log in and load the guild list as soon as the menu opens (off in tests: no network there).
static var login_on_open := true

## The room client (village) or null (main menu: room buttons emit launch_requested).
var lobby: LobbyClient = null
var session: OnlineSession = null
var directory: GuildDirectory = null
var view := View.QUICK
## Guild of the detail view.
var detail_id := ""
## Field of a form the last error belongs to: "name", "tag", "code" or "" (shown under the form).
var form_error_field := ""
## Line under the content: last result of a guild action ("" = none).
var notice := ""
var notice_is_error := false
## Width in mockup pixels.
var menu_width := DEFAULT_WIDTH
## Most height of the content below the tabs in mockup pixels (0 = no limit): taller views scroll
## (the village dialog stays on screen, R8).
var max_content_height := 0.0

## Confirmation view: {text, yes, action (Callable), back (View)}.
var _confirm: Dictionary = {}
var _room_code := ""
var _form_name := ""
var _form_tag := ""
var _invite_input := ""
var _guild_room_code := ""
var _tabs: HBoxContainer = null
var _content: VBoxContainer = null
var _status: Label = null
## Control that gets the focus after a rebuild when nothing of this menu had it.
var _focus_target: Control = null
var _rebuild_queued := false
## What the last build showed (view, guild, loaded, room): a new one gets the default focus.
var _built_key := ""
## Room view: the hint line with the ping and its text without the ping (updated every second, the
## relay measures the round trip every RelayProtocol.HEARTBEAT_SECONDS).
var _room_hint: Label = null
var _room_hint_text := ""
var _ping_left := 0.0
## The places of the room view (ping updates in place) and the NetPlayers they listen to.
var _slots: Array[LobbySlot] = []
var _watched_net: NetPlayers = null
## The profile editor of the PROFILE view (kept across rebuilds while it is open).
var _profile_editor: ProfileEditor = null


static func create(owner_lobby: LobbyClient, online_session: OnlineSession = null, width := DEFAULT_WIDTH, max_height := 0.0) -> OnlineMenu:
	var menu := OnlineMenu.new()
	menu.name = "OnlineMenu"
	menu.lobby = owner_lobby
	menu.session = online_session
	menu.menu_width = width
	menu.max_content_height = max_height
	return menu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", int(UiKit.px(4)))
	custom_minimum_size.x = UiKit.px(menu_width)
	directory = GuildDirectory.new(session)
	# The session is found (or created) on the first guild call, not just by opening the menu.
	directory.session_provider = func() -> OnlineSession: return OnlineSession.of(self) if is_inside_tree() else null
	directory.changed.connect(_queue_rebuild)
	directory.action_finished.connect(_on_action_finished)
	if lobby != null:
		for lobby_signal: Signal in [lobby.state_changed, lobby.room_changed, lobby.error]:
			lobby_signal.connect(_on_lobby_changed)
	_tabs = UiKit.hbox(int(UiKit.px(4)))
	_tabs.name = "Tabs"
	add_child(_tabs)
	add_child(UiKit.separator())
	_content = UiKit.vbox(int(UiKit.px(4)))
	_content.name = "Content"
	if max_content_height > 0.0:
		add_child(_scroll(_content, max_content_height))
	else:
		add_child(_content)
	_status = UiKit.wrapped_text("", menu_width, UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	var start_view := remembered_view if remembered_view == View.GUILDS else View.QUICK
	if is_in_room() or (lobby != null and lobby.is_busy()):
		start_view = View.QUICK
	show_view(start_view)
	# Log in right away: the player sees at once whether the server is there (D-147).
	if wants_login_on_open() and not directory.loaded and not directory.is_busy():
		directory.refresh()


## Opening logs in unless switched off (tests: login_on_open or MainMenu.online_check) or the game
## runs with "-- offline".
static func wants_login_on_open() -> bool:
	var args := OS.get_cmdline_user_args()
	return login_on_open and MainMenu.online_check and not args.has("offline") and not args.has("--offline")


func _process(delta: float) -> void:
	_ping_left -= delta
	if _ping_left > 0.0:
		return
	_ping_left = 1.0
	if _room_hint != null and is_instance_valid(_room_hint) and is_in_room():
		_room_hint.text = _room_hint_line()
	var net := lobby.get_net_players() if lobby != null and is_in_room() else null
	for slot in _slots:
		if is_instance_valid(slot) and not slot.is_empty:
			slot.set_ping(net.get_ping(slot.peer_id) if net != null else -1)


## "Gib diesen Code … · Ping 42 ms" (without the ping until the first round trip).
func _room_hint_line() -> String:
	if lobby != null and lobby.peer != null and lobby.peer.last_rtt_msec >= 0:
		return _room_hint_text + "  ·  " + tr(&"LOBBY_PING") % lobby.peer.last_rtt_msec
	return _room_hint_text


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _content != null:
		_queue_rebuild()


# --- State ---

func is_in_room() -> bool:
	return lobby != null and lobby.is_in_room()


## The tab the view belongs to: QUICK or GUILDS.
func get_tab() -> View:
	return View.QUICK if view == View.QUICK or view == View.PROFILE else View.GUILDS


## Switches the view (tabs, forms, a guild, the confirmation) and rebuilds.
func show_view(new_view: View, guild_id := "") -> void:
	view = new_view
	if new_view == View.DETAIL and not guild_id.is_empty():
		detail_id = guild_id
	if new_view == View.QUICK or new_view == View.GUILDS:
		remembered_view = new_view
	# A failed first load stays visible with "Erneut versuchen" (no new try just by switching tabs).
	if new_view == View.GUILDS and not directory.loaded and not directory.is_busy() and directory.list_error.is_empty():
		directory.refresh()
	if new_view == View.DETAIL and not detail_id.is_empty():
		directory.load_guild(detail_id)
	_rebuild()


## Esc: one step back (forms and a guild -> list, confirmation -> where it came from). false at the
## top of a tab, so the dialog around the menu closes.
func go_back() -> bool:
	match view:
		View.CREATE, View.JOIN, View.DETAIL:
			_set_notice("")
			show_view(View.GUILDS)
			return true
		View.CONFIRM:
			var back: View = _confirm.get("back", View.GUILDS)
			_confirm = {}
			show_view(back)
			return true
		View.PROFILE:
			close_profile_editor()
			return true
	return false


## Keys of the dialog around the menu (Modal.input_handler, MenuPanel.handle_input). true = used.
func handle_input(event: InputEvent) -> bool:
	if view == View.PROFILE and _has_profile_editor():
		# The editor has its own rows (↑/↓, ←/→, 1–8, Enter, Esc).
		return _profile_editor.handle_input(event)
	if MenuInput.is_back(event):
		if go_back():
			UiSound.back(self)
			return true
		return false
	var focused := _focus_owner()
	var moves := MenuInput.is_up(event) or MenuInput.is_down(event) or MenuInput.is_left(event) or MenuInput.is_right(event)
	if focused == null:
		# Nothing of the menu has the focus yet (mouse users): the first key gives it.
		if moves or MenuInput.is_accept(event):
			focus_default()
			return true
		return false
	# W/A/S/D (the arrows move the focus in the GUI already).
	if moves and not focused is LineEdit:
		var next: Control = null
		if MenuInput.is_down(event) or MenuInput.is_right(event):
			next = focused.find_next_valid_focus()
		else:
			next = focused.find_prev_valid_focus()
		if next != null and is_ancestor_of(next):
			next.grab_focus()
		return true
	return false


## Gives the focus to the view's main control (first button, or the text field of a form).
func focus_default() -> void:
	if _focus_target != null and is_instance_valid(_focus_target) and _focus_target.is_inside_tree() and _focus_target.is_visible_in_tree():
		_focus_target.grab_focus()


# --- Building ---

func _queue_rebuild(_value: Variant = null) -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if _content == null or not is_instance_valid(_content):
		return
	if view == View.PROFILE and _has_profile_editor():
		# Players joining or leaving must not throw away what the player is editing.
		_update_status()
		return
	if view == View.PROFILE and not is_in_room():
		view = View.QUICK
	_slots.clear()
	var focused := _focus_owner()
	var focused_name := String(focused.name) if focused != null else ""
	var had_focus := focused != null
	for row: Control in [_tabs, _content]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	_focus_target = null
	_build_tabs()
	match view:
		View.QUICK:
			if is_in_room():
				_build_room()
			else:
				_build_quick()
		View.GUILDS:
			_build_guilds()
		View.CREATE:
			_build_create()
		View.JOIN:
			_build_join()
		View.DETAIL:
			_build_detail()
		View.CONFIRM:
			_build_confirm()
		View.PROFILE:
			_build_profile()
	_update_status()
	# The focus stays on the control of the same name while the view shows the same thing, else it
	# goes to the view's main control (e.g. a guild that finished loading: "Gilden-Raum erstellen").
	var key := "%d|%s|%s|%s" % [view, detail_id, directory.get_detail(detail_id).is_empty(), is_in_room()]
	var same_view := key == _built_key
	_built_key = key
	var again := find_child(focused_name, true, false) as Control if not focused_name.is_empty() and same_view else null
	if again != null and again.focus_mode != Control.FOCUS_NONE and again.is_visible_in_tree() and not (again is BaseButton and (again as BaseButton).disabled):
		again.grab_focus()
	elif had_focus or _wants_initial_focus():
		focus_default()


## The first build of a visible menu takes the focus, so keys work at once.
func _wants_initial_focus() -> bool:
	return is_visible_in_tree() and get_viewport() != null and get_viewport().gui_get_focus_owner() == null


func _build_tabs() -> void:
	var quick := _button(&"LOBBY_QUICK_TITLE", func() -> void:
		_set_notice("")
		show_view(View.QUICK), get_tab() == View.QUICK, 0.0)
	quick.name = "TabQuick"
	quick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(quick)
	var guilds := _button(&"GUILD_TAB", func() -> void:
		_set_notice("")
		show_view(View.GUILDS), get_tab() == View.GUILDS, 0.0)
	guilds.name = "TabGuilds"
	guilds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(guilds)


## Quick game outside a room: create a room, or type a code (6 characters, only the unambiguous
## alphabet, upper case) and join.
func _build_quick() -> void:
	var hint := tr(&"LOBBY_QUICK_HINT")
	if lobby == null:
		hint += " " + tr(&"ONLINE_MENU_VILLAGE_HINT")
	_content.add_child(UiKit.wrapped_text(hint, menu_width, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	_add_connection_state()
	var busy := lobby != null and lobby.is_busy()
	var create := _button(&"LOBBY_CREATE", _create_quick_room, true, BIG_BUTTON_WIDTH)
	create.name = "CreateRoom"
	create.disabled = busy
	create.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(create)
	_focus_target = create
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var code := _line_edit("RoomCode", &"LOBBY_CODE_PLACEHOLDER", _room_code, RelayProtocol.ROOM_CODE_LENGTH, 70.0)
	code.editable = not busy
	row.add_child(code)
	var join := _button(&"LOBBY_JOIN", _join_room, false, BUTTON_WIDTH + 10.0)
	join.name = "JoinRoom"
	join.disabled = busy or not RelayProtocol.is_valid_code(_room_code)
	row.add_child(join)
	code.text_changed.connect(func(text: String) -> void:
		var normalized := RelayProtocol.normalize_code(text)
		if normalized != text:
			code.text = normalized
			code.caret_column = normalized.length()
		_room_code = normalized
		join.disabled = (lobby != null and lobby.is_busy()) or not RelayProtocol.is_valid_code(normalized))
	code.text_submitted.connect(func(_text: String) -> void:
		if not join.disabled:
			_join_room())
	_content.add_child(row)


## Login state of the menu on the quick tab: "Anmelden ..." while the first call runs, a friendly
## line with "Erneut versuchen" when the server is not there (the guild tab shows the same).
func _add_connection_state() -> void:
	if directory.loaded:
		return
	if directory.is_busy():
		var waiting := _centered(UiKit.text_label(&"LOBBY_STATUS_LOGGING_IN", UiKit.SIZE_BODY, UiKit.COLOR_MUTED))
		waiting.name = "ConnectionState"
		_content.add_child(waiting)
		return
	if directory.list_error.is_empty():
		return
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.name = "ConnectionState"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var text := UiKit.wrapped_text(GuildDirectory.error_text(directory.list_error), 0.0, UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
	text.name = "OfflineHint"
	# Takes the width next to the button and wraps (the menu never grows wider).
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	var retry := _button(&"GUILD_RETRY", directory.refresh, false, BUTTON_WIDTH + 10.0)
	retry.name = "Retry"
	row.add_child(retry)
	_content.add_child(row)


## In a room (village): the code with "Kopieren", the hint with the ping, one place per player
## (LobbySlot) and Start (host) / Leave.
func _build_room() -> void:
	var peers := lobby.get_room_peers()
	var net := _watch_net_players()
	if lobby.is_guild_room():
		var title := tr(&"GUILD_ROOM_TITLE") % lobby.room_guild_name if not lobby.room_guild_name.is_empty() else tr(&"GUILD_ROOM_TITLE_PLAIN")
		_content.add_child(_centered(UiKit.text_label(title, UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)))
	var code_row := UiKit.hbox(int(UiKit.px(6)))
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var caption := UiKit.eyebrow(tr(&"LOBBY_ROOM_CODE"), UiKit.COLOR_MUTED)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_row.add_child(caption)
	var code := UiKit.text_label(lobby.get_room_code(), UiKit.SIZE_TITLE_LARGE, UiKit.COLOR_GOLD, true)
	code.name = "RoomCodeLabel"
	code_row.add_child(code)
	# For Discord: the code into the clipboard; the button says it worked.
	var copy := _button(&"GUILD_COPY", func() -> void: pass, false, 0.0)
	copy.name = "CopyRoomCode"
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.pressed.connect(func() -> void:
		_copy_room_code()
		copy.text = tr(&"LOBBY_CODE_COPIED"))
	code_row.add_child(copy)
	_content.add_child(code_row)
	var host_name := str(peers[0].get("name", "")) if not peers.is_empty() and peers[0] is Dictionary else ""
	if net != null and not peers.is_empty() and peers[0] is Dictionary and not net.get_player_name_of(RelayProtocol.HOST_PEER_ID).is_empty():
		host_name = net.get_player_name_of(RelayProtocol.HOST_PEER_ID)
	_room_hint_text = tr(&"LOBBY_SHARE_HINT") if lobby.is_host() else tr(&"LOBBY_JOINED_HINT") % host_name
	_room_hint = _centered(UiKit.text_label(_room_hint_line(), UiKit.SIZE_BODY, UiKit.COLOR_MUTED))
	_room_hint.name = "RoomHint"
	_content.add_child(_room_hint)
	# The host's last guild run paid into the treasury (POST /runs guildPayout, D-081).
	var run := lobby.net_run
	if lobby.is_guild_room() and run != null and run.last_guild_treasury >= 0:
		var paid := UiKit.text_label(tr(&"GUILD_RUN_PAYOUT") % [run.last_guild_payout, run.last_guild_treasury], UiKit.SIZE_BODY, UiKit.COLOR_GOLD)
		paid.name = "GuildPayout"
		_content.add_child(_centered(paid))
	var max_players := int(lobby.room.get("maxPlayers", RelayProtocol.MAX_ROOM_PLAYERS))
	_content.add_child(_build_slots(peers, max_players, net))
	var actions := UiKit.hbox(int(UiKit.px(4)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	if lobby.is_host():
		var start := _button(&"LOBBY_START", lobby.start_run, true, BUTTON_WIDTH + 10.0)
		start.name = "StartRun"
		# Until the relay confirmed the end of the last run (end_run -> run_ended) the room is closed.
		start.disabled = lobby.is_busy() or lobby.is_run_started()
		start.tooltip_text = tr(&"LOBBY_START_HINT")
		actions.add_child(start)
		_focus_target = start
	else:
		actions.add_child(UiKit.text_label(&"LOBBY_WAIT_FOR_HOST", UiKit.SIZE_BODY, UiKit.COLOR_MUTED))
	var leave := _button(&"LOBBY_CLOSE_ROOM" if lobby.is_host() else &"LOBBY_LEAVE", lobby.leave, false, BUTTON_WIDTH + 10.0)
	leave.name = "LeaveRoom"
	leave.disabled = lobby.is_busy()
	actions.add_child(leave)
	if _focus_target == null:
		_focus_target = leave
	_content.add_child(actions)


## One LobbySlot per place: players in room order (host first), then the free places.
func _build_slots(peers: Array, max_players: int, net: NetPlayers) -> Control:
	var row := UiKit.hbox(int(UiKit.px(SLOT_GAP)))
	row.name = "LobbyPlayers"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var places := maxi(1, max_players)
	# The village dialog scrolls: leave room for its scroll bar.
	var usable := menu_width - (6.0 if max_content_height > 0.0 else 0.0)
	var slot_width := floorf((usable - SLOT_GAP * (places - 1)) / places)
	var share_offered := false
	for i in places:
		var slot: LobbySlot = null
		if i < peers.size() and peers[i] is Dictionary:
			var peer: Dictionary = peers[i]
			var peer_id := int(peer.get("peerId", 0))
			var own := peer_id == lobby.get_peer_id()
			var look: Dictionary = PlayerProfile.current().look if own else (net.get_look(peer_id) if net != null else {})
			var player_name := net.get_player_name_of(peer_id) if net != null else ""
			if player_name.is_empty():
				player_name = str(peer.get("name")) if peer.get("name") != null else "?"
			var status := LobbySlot.Status.CONNECTING
			if lobby.is_run_started():
				status = LobbySlot.Status.IN_RUN
			elif net != null and net.get_player_for_peer(peer_id) != null:
				status = LobbySlot.Status.READY
			var ping := net.get_ping(peer_id) if net != null else -1
			slot = LobbySlot.create_player(i, player_name, look, peer_id == RelayProtocol.HOST_PEER_ID, own, status, ping,
					slot_width, open_profile_editor if own else Callable())
			slot.peer_id = peer_id
			slot.tooltip_text = {"android": "Android", "ios": "iOS"}.get(str(peer.get("platform", "")), "PC")
		else:
			var share := Callable()
			if not share_offered:
				share = _copy_room_code
				share_offered = true
			slot = LobbySlot.create_empty(i, slot_width, share)
		row.add_child(slot)
		_slots.append(slot)
	return row


func _copy_room_code() -> void:
	if lobby == null or lobby.get_room_code().is_empty():
		return
	DisplayServer.clipboard_set(lobby.get_room_code())
	UiSound.click(self)
	_set_notice(tr(&"LOBBY_CODE_COPIED"))


## Rebuilds the room when players appear or change their look (not for the pings: those update in
## place every second).
func _watch_net_players() -> NetPlayers:
	var net := lobby.get_net_players() if lobby != null else null
	if net == _watched_net:
		return net
	if _watched_net != null and is_instance_valid(_watched_net):
		if _watched_net.players_changed.is_connected(_queue_rebuild):
			_watched_net.players_changed.disconnect(_queue_rebuild)
		if _watched_net.looks_changed.is_connected(_queue_rebuild):
			_watched_net.looks_changed.disconnect(_queue_rebuild)
	_watched_net = net
	if net != null:
		net.players_changed.connect(_queue_rebuild)
		net.looks_changed.connect(_queue_rebuild)
	return net


## The own place's "Aussehen ändern": the profile editor instead of the room view.
func open_profile_editor() -> void:
	if not is_in_room():
		return
	UiSound.click(self)
	show_view(View.PROFILE)


## Back to the room view (also after saving).
func close_profile_editor() -> void:
	_profile_editor = null
	show_view(View.QUICK)


func get_profile_editor() -> ProfileEditor:
	return _profile_editor if _has_profile_editor() else null


func get_slots() -> Array[LobbySlot]:
	var result: Array[LobbySlot] = []
	for slot in _slots:
		if is_instance_valid(slot):
			result.append(slot)
	return result


func _has_profile_editor() -> bool:
	return _profile_editor != null and is_instance_valid(_profile_editor) and _profile_editor.is_inside_tree()


func _build_profile() -> void:
	var profile := PlayerProfile.current()
	var usable := menu_width - (6.0 if max_content_height > 0.0 else 0.0)
	_profile_editor = ProfileEditor.create(profile.player_name, profile.look, false, usable)
	_profile_editor.saved.connect(close_profile_editor)
	_profile_editor.cancelled.connect(close_profile_editor)
	_content.add_child(_profile_editor)


## Guild list, or the two big buttons without a guild, or loading / offline.
func _build_guilds() -> void:
	if not directory.loaded:
		if directory.is_busy() or directory.list_error.is_empty():
			var loading := _centered(UiKit.text_label(&"GUILD_LOADING", UiKit.SIZE_BODY, UiKit.COLOR_MUTED))
			loading.name = "GuildsLoading"
			_content.add_child(loading)
			return
		var error := UiKit.wrapped_text(GuildDirectory.error_text(directory.list_error), menu_width, UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
		error.name = "GuildsError"
		error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(error)
		var retry := _button(&"GUILD_RETRY", directory.refresh, true, BUTTON_WIDTH + 10.0)
		retry.name = "Retry"
		retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_content.add_child(retry)
		_focus_target = retry
		return
	if directory.guilds.is_empty():
		_build_no_guild()
		return
	var header := UiKit.hbox(int(UiKit.px(3)))
	var title := UiKit.text_label(tr(&"GUILD_LIST_TITLE") % [directory.guilds.size(), directory.max_guilds], UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	var create := _button(&"GUILD_CREATE", func() -> void: _open_form(View.CREATE), false, 0.0)
	create.name = "CreateGuild"
	create.disabled = directory.is_at_limit()
	if create.disabled:
		create.tooltip_text = GuildDirectory.error_text(ApiResult.GUILD_LIMIT_REACHED)
	header.add_child(create)
	var join := _button(&"GUILD_JOIN", func() -> void: _open_form(View.JOIN), false, 0.0)
	join.name = "JoinGuild"
	join.disabled = directory.is_at_limit()
	header.add_child(join)
	_content.add_child(header)
	var rows := UiKit.vbox(int(UiKit.px(2)))
	rows.name = "GuildList"
	for guild in directory.guilds:
		var entry := _guild_card(guild)
		rows.add_child(entry)
		if _focus_target == null:
			_focus_target = entry
	_content.add_child(_list_area(rows, LIST_HEIGHT))


## One guild of the list as a card: tag, name, own role and members, treasury on the right.
func _guild_card(guild: Dictionary) -> Button:
	var id: String = guild.id
	var card := UiKit.menu_button("", "", func() -> void:
		_set_notice("")
		show_view(View.DETAIL, id))
	card.name = "Guild_%s" % _safe_name(id)
	card.custom_minimum_size.y = UiKit.px(CARD_HEIGHT)
	_make_focusable(card)
	var row := UiKit.hbox(int(UiKit.px(5)))
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UiKit.px(6)
	row.offset_right = -UiKit.px(6)
	var tag := UiKit.text_label("[%s]" % guild.tag, UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)
	tag.name = "Tag"
	tag.custom_minimum_size.x = UiKit.px(34)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tag)
	var texts := UiKit.vbox(0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UiKit.text_label(str(guild.name), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true)
	title.name = "Name"
	title.clip_text = true
	texts.add_child(title)
	var info := UiKit.text_label("%s · %s" % [tr(GuildDirectory.role_key(guild.role)), tr(&"GUILD_MEMBERS_SHORT") % [guild.memberCount, guild.maxMembers]], UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	info.name = "Info"
	texts.add_child(info)
	row.add_child(texts)
	var treasury := UiKit.icon_value(UiKit.GOLD_ICON, str(int(guild.get("treasury", 0))), UiKit.COLOR_GOLD, UiKit.SIZE_KEY_HINT, 8.0)
	treasury.name = "Treasury"
	row.add_child(treasury)
	card.add_child(row)
	return card


func _build_no_guild() -> void:
	var text := UiKit.wrapped_text(tr(&"GUILD_EMPTY"), menu_width, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	text.name = "NoGuild"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(text)
	var row := UiKit.hbox(int(UiKit.px(6)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var create := _button(&"GUILD_CREATE", func() -> void: _open_form(View.CREATE), true, BIG_BUTTON_WIDTH)
	create.name = "CreateGuildBig"
	create.custom_minimum_size.y = UiKit.px(BIG_BUTTON_HEIGHT)
	row.add_child(create)
	var join := _button(&"GUILD_JOIN", func() -> void: _open_form(View.JOIN), false, BIG_BUTTON_WIDTH)
	join.name = "JoinGuildBig"
	join.custom_minimum_size.y = UiKit.px(BIG_BUTTON_HEIGHT)
	row.add_child(join)
	_content.add_child(row)
	_focus_target = create


## Found a guild: name and tag (letters/digits, upper case).
func _build_create() -> void:
	_content.add_child(UiKit.text_label(&"GUILD_CREATE_TITLE", UiKit.SIZE_HEADING, UiKit.COLOR_GOLD, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(UiKit.px(6)))
	grid.add_theme_constant_override("v_separation", int(UiKit.px(3)))
	grid.add_child(_caption(&"GUILD_NAME"))
	var name_field := _line_edit("GuildName", &"GUILD_NAME_PLACEHOLDER", _form_name, GuildDirectory.NAME_MAX, 150.0)
	grid.add_child(name_field)
	_add_field_error(grid, "name")
	grid.add_child(_caption(&"GUILD_TAG"))
	var tag_field := _line_edit("GuildTag", &"GUILD_TAG_PLACEHOLDER", _form_tag, GuildDirectory.TAG_MAX, 50.0)
	tag_field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_child(tag_field)
	_add_field_error(grid, "tag")
	_content.add_child(grid)
	_content.add_child(UiKit.wrapped_text(tr(&"GUILD_CREATE_RULES"), menu_width, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED))
	_add_form_error("")
	var actions := UiKit.hbox(int(UiKit.px(4)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var confirm := _button(&"GUILD_CREATE_CONFIRM", _submit_create, true, BUTTON_WIDTH)
	confirm.name = "ConfirmCreate"
	actions.add_child(confirm)
	actions.add_child(_back_button())
	_content.add_child(actions)
	var update := func() -> void:
		confirm.disabled = directory.is_busy() or not GuildDirectory.is_valid_name(_form_name) or not GuildDirectory.is_valid_tag(_form_tag)
	name_field.text_changed.connect(func(text: String) -> void:
		_form_name = text
		update.call())
	tag_field.text_changed.connect(func(text: String) -> void:
		var normalized := GuildDirectory.normalize_tag(text)
		if normalized != text:
			tag_field.text = normalized
			tag_field.caret_column = normalized.length()
		_form_tag = normalized
		update.call())
	name_field.text_submitted.connect(func(_text: String) -> void: tag_field.grab_focus())
	tag_field.text_submitted.connect(func(_text: String) -> void:
		if not confirm.disabled:
			_submit_create())
	update.call()
	_focus_target = name_field


## Join a guild with its invite code.
func _build_join() -> void:
	_content.add_child(UiKit.text_label(&"GUILD_JOIN_TITLE", UiKit.SIZE_HEADING, UiKit.COLOR_GOLD, true))
	_content.add_child(UiKit.wrapped_text(tr(&"GUILD_JOIN_HINT"), menu_width, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	var code := _line_edit("InviteCode", &"GUILD_INVITE_PLACEHOLDER", _invite_input, GuildDirectory.INVITE_MAX, 110.0)
	code.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(code)
	_add_form_error("code")
	var actions := UiKit.hbox(int(UiKit.px(4)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var confirm := _button(&"GUILD_JOIN_CONFIRM", _submit_join, true, BUTTON_WIDTH)
	confirm.name = "ConfirmJoin"
	confirm.disabled = directory.is_busy() or not GuildDirectory.is_valid_invite_code(_invite_input)
	actions.add_child(confirm)
	actions.add_child(_back_button())
	_content.add_child(actions)
	code.text_changed.connect(func(text: String) -> void:
		var normalized := GuildDirectory.normalize_invite_code(text)
		if normalized != text:
			code.text = normalized
			code.caret_column = normalized.length()
		_invite_input = normalized
		confirm.disabled = directory.is_busy() or not GuildDirectory.is_valid_invite_code(normalized))
	code.text_submitted.connect(func(_text: String) -> void:
		if not confirm.disabled:
			_submit_join())
	_focus_target = code


## One guild: tag and name, own role, invite code, treasury, members, guild room, leave.
func _build_detail() -> void:
	var detail := directory.get_detail(detail_id)
	var summary := detail if not detail.is_empty() else directory.find_summary(detail_id)
	var role := directory.get_own_role(detail_id)
	var header := UiKit.hbox(int(UiKit.px(4)))
	var back := _back_button()
	back.custom_minimum_size.x = 0.0
	Modal.compact_buttons(back)
	header.add_child(back)
	var title := UiKit.text_label("[%s]  %s" % [summary.get("tag", ""), summary.get("name", "")], UiKit.SIZE_HEADING, UiKit.COLOR_GOLD, true)
	title.name = "GuildTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	header.add_child(title)
	if not role.is_empty():
		var role_label := UiKit.text_label(GuildDirectory.role_key(role), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
		role_label.name = "OwnRole"
		role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.add_child(role_label)
	_content.add_child(header)
	if detail.is_empty():
		_content.add_child(_centered(UiKit.text_label(&"GUILD_LOADING_ONE", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)))
		_focus_target = back
		return

	var info := UiKit.panel(&"dark")
	var info_box := UiKit.vbox(int(UiKit.px(2)))
	info.add_child(info_box)
	var code_row := UiKit.hbox(int(UiKit.px(4)))
	code_row.add_child(_caption(&"GUILD_INVITE_CODE"))
	var manage := GuildDirectory.can_manage(role)
	var invite := str(detail.get("inviteCode", ""))
	if manage and not invite.is_empty():
		var code_label := UiKit.text_label(invite, UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)
		code_label.name = "InviteCodeLabel"
		code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		code_row.add_child(code_label)
		var copy := _button(&"GUILD_COPY", func() -> void: _copy_invite(invite), false, 0.0)
		copy.name = "CopyInvite"
		code_row.add_child(copy)
		var renew := _button(&"GUILD_NEW_CODE", func() -> void: directory.rotate_invite_code(detail_id), false, 0.0)
		renew.name = "RenewInvite"
		renew.disabled = directory.is_busy()
		code_row.add_child(renew)
	else:
		var hidden := UiKit.text_label(&"GUILD_INVITE_HIDDEN", UiKit.SIZE_BODY, UiKit.COLOR_DISABLED)
		hidden.name = "InviteHidden"
		hidden.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		code_row.add_child(hidden)
	info_box.add_child(code_row)
	var treasury_row := UiKit.hbox(int(UiKit.px(4)))
	treasury_row.add_child(_caption(&"GUILD_TREASURY"))
	var treasury := UiKit.icon_value(UiKit.GOLD_ICON, str(int(detail.get("treasury", 0))), UiKit.COLOR_GOLD, UiKit.SIZE_KEY_HINT, 8.0)
	treasury.name = "Treasury"
	treasury.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	treasury_row.add_child(treasury)
	# Leaving sits here (asks first), the dialog stays short (R8, D-139).
	var leave := _button(&"GUILD_LEAVE", _ask_leave, false, 0.0)
	leave.name = "LeaveGuild"
	leave.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT)
	leave.disabled = directory.is_busy()
	treasury_row.add_child(leave)
	info_box.add_child(treasury_row)
	_content.add_child(info)

	# Guild room: create one (only members may join) or join one with its room code.
	var room_row := UiKit.hbox(int(UiKit.px(4)))
	room_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var room_blocked := is_in_room() or (lobby != null and lobby.is_busy())
	var room := _button(&"GUILD_ROOM_CREATE", _create_guild_room, true, BIG_BUTTON_WIDTH)
	room.name = "CreateGuildRoom"
	room.custom_minimum_size.y = UiKit.px(BIG_BUTTON_HEIGHT * 0.75)
	room.tooltip_text = tr(&"GUILD_ROOM_HINT")
	room.disabled = room_blocked
	if is_in_room():
		room.tooltip_text = tr(&"GUILD_ROOM_LEAVE_FIRST")
	room_row.add_child(room)
	var room_code := _line_edit("GuildRoomCode", &"LOBBY_CODE_PLACEHOLDER", _guild_room_code, RelayProtocol.ROOM_CODE_LENGTH, 62.0)
	room_code.editable = not room_blocked
	room_code.tooltip_text = tr(&"GUILD_ROOM_JOIN_HINT")
	room_row.add_child(room_code)
	var room_join := _button(&"GUILD_ROOM_JOIN", _join_guild_room, false, 0.0)
	room_join.name = "JoinGuildRoom"
	room_join.tooltip_text = tr(&"GUILD_ROOM_JOIN_HINT")
	room_join.disabled = room_blocked or not RelayProtocol.is_valid_code(_guild_room_code)
	room_row.add_child(room_join)
	room_code.text_changed.connect(func(text: String) -> void:
		var normalized := RelayProtocol.normalize_code(text)
		if normalized != text:
			room_code.text = normalized
			room_code.caret_column = normalized.length()
		_guild_room_code = normalized
		room_join.disabled = (is_in_room() or (lobby != null and lobby.is_busy())) or not RelayProtocol.is_valid_code(normalized))
	room_code.text_submitted.connect(func(_text: String) -> void:
		if not room_join.disabled:
			_join_guild_room())
	_content.add_child(room_row)

	var members: Array = detail.get("members", [])
	_content.add_child(UiKit.text_label(tr(&"GUILD_MEMBERS") % [members.size(), int(detail.get("maxMembers", GuildDirectory.MAX_GUILD_MEMBERS))], UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true))
	var list := UiKit.vbox(int(UiKit.px(1)))
	list.name = "Members"
	var own_id := directory.get_own_player_id()
	for member: Dictionary in members:
		list.add_child(_member_row(member, role, own_id))
	_content.add_child(_list_area(list, MEMBERS_HEIGHT))
	_focus_target = room if not room.disabled else back


## Two lines: name (and "du") on top, role and joined-on date small below; for founder/officer the
## actions (promote/demote, remove) on the right in a column of fixed width, so every row lines up.
func _member_row(member: Dictionary, own_role: String, own_id: String) -> Control:
	var row := UiKit.hbox(int(UiKit.px(4)))
	var player_id := str(member.get("playerId", ""))
	row.name = "Member_%s" % _safe_name(player_id)
	var is_self := not own_id.is_empty() and player_id == own_id
	var text := str(member.get("name", "?"))
	if is_self:
		text += " (%s)" % tr(&"LOBBY_YOU")
	var texts := UiKit.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := UiKit.text_label(text, UiKit.SIZE_BODY, UiKit.COLOR_GOLD if is_self else UiKit.COLOR_TEXT)
	name_label.name = "Name"
	name_label.clip_text = true
	texts.add_child(name_label)
	var meta := UiKit.hbox(int(UiKit.px(4)))
	var member_role := str(member.get("role", GuildDirectory.ROLE_MEMBER))
	var role_label := UiKit.text_label(GuildDirectory.role_key(member_role), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	role_label.name = "Role"
	meta.add_child(role_label)
	var joined := GuildDirectory.format_date(str(member.get("joinedAt", "")))
	if not joined.is_empty():
		var joined_label := UiKit.text_label(joined, UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
		joined_label.name = "Joined"
		joined_label.tooltip_text = tr(&"GUILD_JOINED_AT") % joined
		joined_label.mouse_filter = Control.MOUSE_FILTER_PASS
		meta.add_child(joined_label)
	texts.add_child(meta)
	row.add_child(texts)
	if not GuildDirectory.can_manage(own_role):
		return row
	var actions := UiKit.hbox(int(UiKit.px(3)))
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.custom_minimum_size.x = UiKit.px(MEMBER_ACTIONS_WIDTH)
	row.add_child(actions)
	if not is_self and GuildDirectory.can_change_role(own_role, member_role):
		var promote := member_role == GuildDirectory.ROLE_MEMBER
		var new_role := GuildDirectory.ROLE_OFFICER if promote else GuildDirectory.ROLE_MEMBER
		var role_button := _button(&"GUILD_PROMOTE" if promote else &"GUILD_DEMOTE", func() -> void: directory.set_member_role(detail_id, player_id, new_role), false, 0.0)
		role_button.name = "Role_%s" % _safe_name(player_id)
		role_button.tooltip_text = tr(&"GUILD_PROMOTE_HINT" if promote else &"GUILD_DEMOTE_HINT")
		role_button.disabled = directory.is_busy()
		Modal.compact_buttons(role_button)
		actions.add_child(role_button)
	if not is_self and GuildDirectory.can_remove(own_role, member_role):
		var remove := _button(&"GUILD_REMOVE", func() -> void: _ask_remove(player_id, str(member.get("name", "?"))), false, 0.0)
		remove.name = "Remove_%s" % _safe_name(player_id)
		remove.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT)
		remove.disabled = directory.is_busy()
		Modal.compact_buttons(remove)
		actions.add_child(remove)
	return row


func _build_confirm() -> void:
	var text := UiKit.wrapped_text(str(_confirm.get("text", "")), menu_width, UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT)
	text.name = "ConfirmText"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(text)
	var actions := UiKit.hbox(int(UiKit.px(4)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var yes := _button(str(_confirm.get("yes", "")), func() -> void:
		var action: Callable = _confirm.get("action", Callable())
		var back: View = _confirm.get("back", View.GUILDS)
		_confirm = {}
		view = back
		if action.is_valid():
			action.call()
		_rebuild(), false, BUTTON_WIDTH)
	yes.name = "ConfirmYes"
	yes.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT)
	actions.add_child(yes)
	var no := _button(&"COMMON_CANCEL", func() -> void: go_back(), true, BUTTON_WIDTH)
	no.name = "ConfirmNo"
	actions.add_child(no)
	_content.add_child(actions)
	# Safe default: "Abbrechen".
	_focus_target = no


func _update_status() -> void:
	var text := ""
	var color := UiKit.COLOR_MUTED
	if view == View.QUICK and lobby != null:
		match lobby.state:
			LobbyClient.State.LOGGING_IN:
				text = tr(&"LOBBY_STATUS_LOGGING_IN")
			LobbyClient.State.CONNECTING:
				text = tr(&"LOBBY_STATUS_CONNECTING")
			LobbyClient.State.LEAVING:
				text = tr(&"LOBBY_STATUS_LEAVING")
			_:
				if not lobby.last_error.is_empty():
					text = LobbyClient.error_text(lobby.last_error)
					color = UiKit.COLOR_DANGER_SOFT
	elif view != View.QUICK:
		if (view == View.CREATE or view == View.JOIN) and notice_is_error:
			# Shown at the field (_add_field_error, _add_form_error).
			text = ""
		elif not notice.is_empty():
			text = notice
			color = UiKit.COLOR_DANGER_SOFT if notice_is_error else UiKit.COLOR_SUCCESS
		elif directory.is_busy() and directory.loaded:
			text = tr(&"GUILD_WORKING")
	_status.text = text
	_status.visible = not text.is_empty()
	_status.add_theme_color_override("font_color", color)


# --- Actions ---

func _create_quick_room() -> void:
	if lobby == null:
		launch_requested.emit({"action": LobbyClient.LAUNCH_CREATE, "mode": LobbyClient.MODE_QUICK})
		return
	lobby.resume_dialog = true
	lobby.create_room()


func _join_room() -> void:
	if not RelayProtocol.is_valid_code(_room_code):
		return
	if lobby == null:
		launch_requested.emit({"action": LobbyClient.LAUNCH_JOIN, "code": _room_code})
		return
	lobby.resume_dialog = true
	lobby.join_room(_room_code)


## Guild room of the open guild: only its members may join (the relay asks the API).
func _create_guild_room() -> void:
	var summary := directory.find_summary(detail_id)
	var guild_name := str(directory.get_detail(detail_id).get("name", summary.get("name", "")))
	var guild_tag := str(directory.get_detail(detail_id).get("tag", summary.get("tag", "")))
	if lobby == null:
		launch_requested.emit({"action": LobbyClient.LAUNCH_CREATE, "mode": LobbyClient.MODE_GUILD, "guild_id": detail_id, "guild_name": guild_name, "guild_tag": guild_tag})
		return
	lobby.resume_dialog = true
	lobby.room_guild_name = guild_name
	lobby.room_guild_tag = guild_tag
	show_view(View.QUICK)
	lobby.create_room(LobbyClient.MODE_GUILD, detail_id)


## Join a guild room with its room code; the relay lets only members in (not_guild_member).
func _join_guild_room() -> void:
	if not RelayProtocol.is_valid_code(_guild_room_code):
		return
	var guild := directory.get_detail(detail_id)
	if lobby == null:
		launch_requested.emit({"action": LobbyClient.LAUNCH_JOIN, "code": _guild_room_code, "guild_name": str(guild.get("name", "")), "guild_tag": str(guild.get("tag", ""))})
		return
	lobby.resume_dialog = true
	show_view(View.QUICK)
	await lobby.join_room(_guild_room_code)
	if lobby != null and lobby.is_guild_room() and lobby.get_room_guild_id() == str(guild.get("id", "")):
		lobby.room_guild_name = str(guild.get("name", ""))
		lobby.room_guild_tag = str(guild.get("tag", ""))


func _open_form(form: View) -> void:
	_set_notice("")
	form_error_field = ""
	if form == View.JOIN:
		_invite_input = ""
	show_view(form)


func _submit_create() -> void:
	_set_notice("")
	form_error_field = ""
	directory.create_guild(_form_name, _form_tag)


func _submit_join() -> void:
	_set_notice("")
	form_error_field = ""
	directory.join_guild(_invite_input)


func _ask_leave() -> void:
	var guild_name := str(directory.find_summary(detail_id).get("name", ""))
	var id := detail_id
	var members: Array = directory.get_detail(id).get("members", [])
	_ask(leave_question(guild_name, directory.get_own_role(id), members.size()), tr(&"GUILD_LEAVE_YES"), func() -> void: directory.leave_guild(id), View.DETAIL)


## The question before leaving: the last member disbands the guild; a founder hands the lead to the
## longest-serving officer, else the longest-serving member (API P-102).
func leave_question(guild_name: String, role: String, member_count: int) -> String:
	var text := tr(&"GUILD_LEAVE_CONFIRM") % guild_name
	if member_count == 1:
		text += " " + tr(&"GUILD_LEAVE_LAST")
	elif role == GuildDirectory.ROLE_FOUNDER:
		text += " " + tr(&"GUILD_LEAVE_FOUNDER")
	return text


func _ask_remove(player_id: String, member_name: String) -> void:
	var id := detail_id
	_ask(tr(&"GUILD_REMOVE_CONFIRM") % member_name, tr(&"GUILD_REMOVE"), func() -> void: directory.remove_member(id, player_id), View.DETAIL)


func _ask(text: String, yes_text: String, action: Callable, back: View) -> void:
	_set_notice("")
	_confirm = {"text": text, "yes": yes_text, "action": action, "back": back}
	view = View.CONFIRM
	_rebuild()


func _copy_invite(code: String) -> void:
	DisplayServer.clipboard_set(code)
	_set_notice(tr(&"GUILD_COPIED"))
	_rebuild()


func _set_notice(text: String, is_error := false) -> void:
	notice = text
	notice_is_error = is_error


func _on_action_finished(action: StringName, result: ApiResult, info: Dictionary) -> void:
	var guild_name := str(info.get("name", ""))
	if not result.ok:
		if action == GuildDirectory.ACTION_LIST:
			return
		_set_notice(GuildDirectory.error_text(result.error), true)
		form_error_field = form_field_for(result.error)
		if action == GuildDirectory.ACTION_DETAIL and directory.find_summary(str(info.get("guild_id", ""))).is_empty() and view == View.DETAIL:
			view = View.GUILDS
		elif action == GuildDirectory.ACTION_LEAVE and directory.find_summary(str(info.get("guild_id", ""))).is_empty() and view == View.DETAIL:
			view = View.GUILDS
		_queue_rebuild()
		return
	match action:
		GuildDirectory.ACTION_CREATE:
			_form_name = ""
			_form_tag = ""
			_set_notice(tr(&"GUILD_CREATED") % guild_name)
			view = View.DETAIL
			detail_id = str(info.get("guild_id", ""))
		GuildDirectory.ACTION_JOIN:
			_invite_input = ""
			_set_notice(tr(&"GUILD_JOINED") % guild_name)
			view = View.DETAIL
			detail_id = str(info.get("guild_id", ""))
		GuildDirectory.ACTION_LEAVE:
			_set_notice(tr(&"GUILD_DISBANDED" if info.get("disbanded", false) == true else &"GUILD_LEFT") % guild_name)
			if view == View.DETAIL or view == View.CONFIRM:
				view = View.GUILDS
		GuildDirectory.ACTION_REMOVE:
			_set_notice(tr(&"GUILD_REMOVED") % str(info.get("name", "")))
		GuildDirectory.ACTION_ROTATE:
			_set_notice(tr(&"GUILD_CODE_RENEWED"))
		GuildDirectory.ACTION_ROLE:
			var promoted := str(info.get("role", "")) == GuildDirectory.ROLE_OFFICER
			_set_notice(tr(&"GUILD_PROMOTED" if promoted else &"GUILD_DEMOTED") % str(info.get("name", "")))
	_queue_rebuild()


## The form field an error code belongs to ("" = under the whole form).
static func form_field_for(code: String) -> String:
	match code:
		"guild_name_taken", GuildDirectory.ERROR_NAME_INVALID:
			return "name"
		"guild_tag_taken", GuildDirectory.ERROR_TAG_INVALID:
			return "tag"
		ApiResult.INVALID_INVITE_CODE, GuildDirectory.ERROR_CODE_INVALID:
			return "code"
	return ""


func _on_lobby_changed(_value: Variant = null) -> void:
	# A room was entered (or creating one started) from the guild tab: show it.
	if lobby != null and (lobby.is_in_room() or lobby.is_busy()) and view == View.GUILDS:
		view = View.QUICK
	_queue_rebuild()


# --- Widgets ---

## Framed button (dialog look) with a focus frame; text is a translation key or a ready text.
## width 0 = as wide as the text.
func _button(text: String, on_pressed: Callable, primary := false, width := BUTTON_WIDTH) -> Button:
	var button := UiKit.dialog_button(text, "", on_pressed, primary)
	button.custom_minimum_size.x = UiKit.px(width)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_make_focusable(button)
	return button


## Error of the last form call under its field (grid row: empty cell + text), else nothing.
func _add_field_error(grid: GridContainer, field: String) -> void:
	if not notice_is_error or notice.is_empty() or form_error_field != field:
		return
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(spacer)
	var error := UiKit.wrapped_text(notice, 150.0, UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
	error.name = "FieldError"
	grid.add_child(error)


## Error of the last form call under the form. field "": errors that belong to no field; "code":
## the join form has only that one field, so it shows every error there.
func _add_form_error(field: String) -> void:
	if not notice_is_error or notice.is_empty():
		return
	if field.is_empty() and not form_error_field.is_empty():
		return
	var error := UiKit.wrapped_text(notice, menu_width, UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
	error.name = "FieldError" if not field.is_empty() else "FormError"
	error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(error)


func _back_button() -> Button:
	var back := _button(&"COMMON_BACK", func() -> void: go_back(), false, BUTTON_WIDTH)
	back.name = "Back"
	return back


func _line_edit(node_name: String, placeholder: StringName, text: String, max_length: int, width: float) -> LineEdit:
	var field := LineEdit.new()
	field.name = node_name
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.text = text
	field.custom_minimum_size = Vector2(UiKit.px(width), 0)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_KEY_HINT))
	field.select_all_on_focus = false
	_make_focusable(field)
	return field


func _caption(key: StringName) -> Label:
	var label := UiKit.text_label(key, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _centered(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## A list in its own scroll area, or plain when the whole content scrolls already (village: no
## scroll area inside another one).
func _list_area(list: Control, max_height: float) -> Control:
	if max_content_height > 0.0:
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return list
	return _scroll(list, max_height)


## A vertical scroll area that is never taller than max_height mockup pixels.
func _scroll(child: Control, max_height: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Room for the scroll bar on the right, so it never covers the last column.
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", int(UiKit.px(5)))
	margin.add_child(child)
	scroll.add_child(margin)
	var limit := UiKit.px(max_height)
	scroll.custom_minimum_size.y = minf(limit, child.get_combined_minimum_size().y)
	child.minimum_size_changed.connect(func() -> void:
		if is_instance_valid(scroll):
			scroll.custom_minimum_size.y = minf(limit, child.get_combined_minimum_size().y))
	return scroll


## Focus for keyboard and controller, shown as a gold frame.
static func _make_focusable(control: Control) -> void:
	control.focus_mode = Control.FOCUS_ALL
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = UiKit.COLOR_GOLD
	frame.set_border_width_all(int(maxf(2.0, UiKit.px(FOCUS_BORDER))))
	# Drawn inside the control: scroll areas would cut off a frame outside it.
	control.add_theme_stylebox_override("focus", frame)


## The focused control if it belongs to this menu.
func _focus_owner() -> Control:
	var viewport := get_viewport()
	var focused := viewport.gui_get_focus_owner() if viewport != null else null
	return focused if focused != null and is_ancestor_of(focused) else null


static func _safe_name(id: String) -> String:
	return id.validate_node_name().replace("-", "_")
