class_name OnlineMenu
extends VBoxContainer
## The online menu (D-147): the same menu in the main menu ("Online spielen", OnlinePanel) and in
## the village's guild building (VillageUI). Two tabs:
## - Schnelles Spiel: create a room or join one by room code (LobbyClient); inside a room the code
##   and one designed place per player (LobbySlot, D-152: figure in its look, name, host crown,
##   status, ping; free places "Wartet auf Spieler …", the first with "Code teilen"), Start/Leave.
##   The own place has "Aussehen ändern": the profile editor (ProfileEditor) replaces the room view
##   until it is saved or left; the new look reaches everybody in the room (NetPlayers) and the
##   account (PATCH /me).
## - Gilden: the player's guilds (GuildDirectory). Without a guild a short "Was bringt eine Gilde?"
##   (only what exists: guild rooms, treasury, guild leaderboard) and two big buttons "Gilde
##   erstellen" / "Gilde beitreten"; with guilds a list and both buttons small at the top right.
##   A guild shows tag, name, own role, the invite code (founder/officer: copy, renew), the
##   treasury with one line on what guild runs bring, the members with their role (founder:
##   promote/demote officers; founder/officer: remove) and "Gilde verlassen" with a confirmation.
##   Guild rooms live on the guild's page (playtest 16.10.2026): the open rooms of the guild
##   (GET /guilds/:id/rooms, polled every ROOMS_REFRESH_SECONDS while the page is open; hidden on an
##   API without the route) with "Beitreten" and "Gilden-Raum erstellen" (relay mode guild, only
##   members may join). Guild rooms show no room code (report b47bee4a): the guild joins from that
##   list; the code (field, "Kopieren", "Code teilen") is only the fallback for an API without the
##   list. The own guild room (places, Start/Leave) is shown on that page, not in the quick tab; the
##   quick tab only points to it.
## The village dialog and the main menu panel give the content one fixed height (report 60711d3b:
## switching tabs never resizes the dialog); it scrolls with a pixel scroll bar, an even wheel step
## (report e0ca0a4f) and keeps its place when the page is rebuilt (report b5657bff).
## Invite by link (MP2b, D-190): the code row has "Link kopieren" (on phones in the browser "Teilen",
## the share sheet of the Web Share API), the code stays readable next to it; the first free place
## shares the link too. A player who arrived by a link sees the invite on the quick tab instead of
## create/join: which room, and if the join failed one sentence with a way out ("Erneut versuchen"
## where another try can help, "Neu laden" for another version in the browser, always "Selbst
## spielen", which drops the invite and closes the dialog).
## Without a lobby (main menu) the room buttons emit launch_requested; the main menu loads the world
## (or creates the first one) and the village runs the wish (LobbyClient.request_launch). The menu
## never pauses anything itself;
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
## button it stays on a 270 px high screen; taller views scroll. Every view gets this height (report
## 60711d3b: the dialog no longer jumps between tabs); a room with four places just fits.
const VILLAGE_CONTENT_HEIGHT := 140.0
## Gap between the content and the scroll bar (mockup pixels). The bar's own width
## (Modal.SCROLL_BAR_WIDTH) is always kept free next to it, also while nothing scrolls.
const SCROLL_GAP := 2.0
## TESTWERT: one mouse wheel step in the scroll areas (mockup pixels, about one line and a half;
## Godot's own step is an eighth of the visible height, report e0ca0a4f "scrolls much too far").
const WHEEL_STEP := 14.0
## TESTWERT: the browser makes every wheel event a full step, also the many small ones of a touchpad
## swipe. There a step moves WHEEL_STEP only after this pause, quicker ones a share of it: a swipe
## scrolls at most WHEEL_STEP per this many milliseconds.
const WEB_WHEEL_WINDOW_MSEC := 40.0
## Focus frame around the focused control (keyboard / controller).
const FOCUS_BORDER := 1.0
## Gap between the player places of a room (mockup pixels).
const SLOT_GAP := 3.0
## TESTWERT: seconds between two loads of a guild's open rooms while its page is open (the API asks
## for at most one every ~5 s).
const ROOMS_REFRESH_SECONDS := 6.0
## Scroll height of the open rooms of a guild (mockup pixels, about two rows).
const ROOMS_HEIGHT := 36.0
## What a guild brings today (playtest 16.10.2026: "Was bringt eine Gilde?"): guild rooms only for
## members, the treasury that guild runs fill (D-081: all leftover gold at the portal, else half),
## the guild leaderboard (D-082, guild runs). No guild forge yet (MP8): not promised here.
const PERK_KEYS: Array[StringName] = [&"GUILD_PERK_ROOMS", &"GUILD_PERK_TREASURY", &"GUILD_PERK_RANKING"]

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
## The scroll area around the content (fixed height), null without max_content_height.
var _scroll_area: ScrollContainer = null
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
## Where the last room action started: QUICK, or DETAIL with the guild (_room_origin_guild). Room
## errors are shown there only.
var _room_origin := View.QUICK
var _room_origin_guild := ""
## Seconds until the open rooms of the shown guild are loaded again.
var _rooms_left := ROOMS_REFRESH_SECONDS
## Back from the confirmation: {focus, scroll} of the page that asked (the next build keeps them).
var _return_to: Dictionary = {}
## Scroll position the content area keeps while a rebuilt page is laid out (-1 = none) and the
## frames it is still applied (every sort of the scroll area in between sets it again).
var _pending_scroll := -1
var _pending_scroll_frames := 0


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
		_scroll_area = _scroll(_content, max_content_height, true)
		_scroll_area.name = "ScrollArea"
		_scroll_area.sort_children.connect(_apply_pending_scroll)
		add_child(_scroll_area)
	else:
		add_child(_content)
	_status = UiKit.wrapped_text("", menu_width, UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	if _scroll_area != null:
		# One line is always kept for it: "Einen Moment …" coming and going never resizes the dialog.
		_status.custom_minimum_size.y = _status.get_line_height()
	var start_view := remembered_view if remembered_view == View.GUILDS else View.QUICK
	var room_guild := get_room_guild()
	if not room_guild.is_empty():
		# A guild room (or one being created/joined from its page) is shown on the guild's page.
		start_view = View.DETAIL
		detail_id = room_guild
		_room_origin = View.DETAIL
		_room_origin_guild = room_guild
	elif is_in_room() or (lobby != null and lobby.is_busy()):
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


## A failed or waiting invite ends with the dialog (like "Selbst spielen"): no join behind the
## player's back, no old invite on the next visit. A first join on its way goes on (as with a typed
## code); a retry while waiting for a run is cancelled.
func _exit_tree() -> void:
	if lobby != null and is_instance_valid(lobby) and lobby.has_invite() \
			and (lobby.state == LobbyClient.State.IDLE or lobby.invite_waiting):
		lobby.give_up_invite()


func _process(delta: float) -> void:
	if _pending_scroll >= 0:
		_apply_pending_scroll()
		_pending_scroll_frames -= 1
		if _pending_scroll_frames <= 0:
			_pending_scroll = -1
	_rooms_left -= delta
	if _rooms_left <= 0.0:
		_rooms_left = ROOMS_REFRESH_SECONDS
		if wants_rooms():
			directory.load_rooms(detail_id)
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


## The guild whose page shows this machine's room: inside a guild room its guild, while a guild room
## is being created or joined from a guild's page that guild, else "" (LobbyClient).
func get_room_guild() -> String:
	return lobby.get_guild_room_target() if lobby != null else ""


## In a room or about to be: create and join are blocked.
func _room_blocked() -> bool:
	return is_in_room() or (lobby != null and lobby.is_busy())


## The tab the view belongs to: QUICK or GUILDS. The profile editor of a guild room belongs to the
## guild's page.
func get_tab() -> View:
	if view == View.PROFILE:
		return View.GUILDS if not get_room_guild().is_empty() else View.QUICK
	return View.QUICK if view == View.QUICK else View.GUILDS


## The open rooms of the shown guild are worth loading: its page is open and visible, the API knows
## the route and no load is running. Not while this machine is in that guild's room.
func wants_rooms() -> bool:
	return view == View.DETAIL and not detail_id.is_empty() and directory.rooms_supported \
			and directory.rooms_running == 0 and is_visible_in_tree() and get_room_guild() != detail_id \
			and not directory.get_detail(detail_id).is_empty()


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
		_load_guild_page(detail_id)
	_rebuild()


## The guild, then its open rooms (one after the other: the first call may have to log in).
func _load_guild_page(guild_id: String) -> void:
	_rooms_left = ROOMS_REFRESH_SECONDS
	var result: ApiResult = await directory.load_guild(guild_id)
	if result.ok and view == View.DETAIL and detail_id == guild_id and directory.rooms_supported \
			and directory.rooms_running == 0 and get_room_guild() != guild_id:
		_rooms_left = ROOMS_REFRESH_SECONDS
		directory.load_rooms(guild_id)


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
			_return_from_confirm()
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
	var scroll_before := _scroll_area.scroll_vertical if _scroll_area != null else 0
	if _pending_scroll >= 0:
		# The last page is not laid out yet (its place is still on the way).
		scroll_before = _pending_scroll
	var back_from_confirm := _return_to
	_return_to = {}
	for row: Control in [_tabs, _content]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	_focus_target = null
	_build_tabs()
	match view:
		View.QUICK:
			if not get_room_guild().is_empty():
				_build_guild_room_pointer()
			elif is_in_room():
				_build_room(_content)
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
	# While the view shows the same thing (a guild call started or ended, the open rooms changed) or
	# after the confirmation, focus and scroll stay where they were (report b5657bff: every click
	# jumped back to "Zurück" at the top). A button greyed out only while the call runs keeps the
	# focus; one that is gone takes it along (the next key gives it back, handle_input). A new view
	# gives the focus to its main control (e.g. a guild that finished loading: "Gilden-Raum erstellen").
	var key := "%d|%s|%s|%s" % [view, detail_id, directory.get_detail(detail_id).is_empty(), is_in_room()]
	var same_view := key == _built_key
	_built_key = key
	if same_view or not back_from_confirm.is_empty():
		var keep_name := focused_name if same_view else str(back_from_confirm.get("focus", ""))
		var again := find_child(keep_name, true, false) as Control if not keep_name.is_empty() else null
		if again != null and again.focus_mode != Control.FOCUS_NONE and again.is_visible_in_tree():
			again.grab_focus()
		_keep_scroll(scroll_before if same_view else int(back_from_confirm.get("scroll", 0)))
	elif had_focus or _wants_initial_focus():
		focus_default()


## The scroll area stays at value: now (a newly built control that takes the focus scrolls it before
## the containers placed it) and again whenever the scroll area sorts the new content during the
## next frames (a short page before, e.g. the confirmation, still limits the scroll range).
func _keep_scroll(value: int) -> void:
	if _scroll_area == null or value <= 0:
		return
	_pending_scroll = value
	_pending_scroll_frames = 3
	_apply_pending_scroll()


func _apply_pending_scroll() -> void:
	if _pending_scroll >= 0 and _scroll_area != null and is_instance_valid(_scroll_area):
		_scroll_area.scroll_vertical = _pending_scroll


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
	if lobby != null and lobby.has_invite():
		_build_invite()
		return
	var hint := tr(&"LOBBY_QUICK_HINT")
	if lobby == null:
		hint += " " + tr(&"ONLINE_MENU_VILLAGE_HINT")
	_content.add_child(UiKit.wrapped_text(hint, _content_width(), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	_add_new_world_hint()
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


## Arrival by an invite link (MP2b, D-190): the room of the link; while it connects the status line
## says so; a failure is one sentence with a way out; a run in progress is waited for.
func _build_invite() -> void:
	var title := UiKit.text_label(_format(&"INVITE_TITLE", [lobby.invite_code]), UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)
	title.name = "InviteTitle"
	_content.add_child(_centered(title))
	var code := lobby.last_error if lobby.state == LobbyClient.State.IDLE else ""
	var text := ""
	if lobby.invite_waiting:
		text = tr(&"INVITE_WAIT_RUN")
	elif not code.is_empty():
		text = InviteLink.error_text(code)
	if not text.is_empty():
		var line := UiKit.wrapped_text(text, _content_width(), UiKit.SIZE_BODY,
				UiKit.COLOR_TEXT_SOFT if lobby.invite_waiting else UiKit.COLOR_DANGER_SOFT)
		line.name = "InviteText"
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(line)
	var actions := UiKit.hbox(int(UiKit.px(4)))
	actions.name = "InviteActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	if not code.is_empty() and not lobby.invite_waiting:
		if InviteLink.can_retry(code):
			var retry := _button(&"GUILD_RETRY", lobby.retry_invite, true, BUTTON_WIDTH + 10.0)
			retry.name = "InviteRetry"
			actions.add_child(retry)
			_focus_target = retry
		elif code in ["version_mismatch", LobbyClient.ERROR_UPDATE_REQUIRED] and OS.has_feature("web"):
			var reload := _button(&"INVITE_RELOAD", _reload_page, true, BUTTON_WIDTH + 10.0)
			reload.name = "InviteReload"
			actions.add_child(reload)
			_focus_target = reload
	var solo := _button(&"INVITE_PLAY_SOLO", play_solo, _focus_target == null, BUTTON_WIDTH + 10.0)
	solo.name = "InviteSolo"
	actions.add_child(solo)
	if _focus_target == null:
		_focus_target = solo
	_content.add_child(actions)


## "Selbst spielen" of an invite: the invite is dropped, the dialog closes (the village is solo).
func play_solo() -> void:
	if lobby != null:
		lobby.give_up_invite()
	var node := get_parent()
	while node != null and not node is Modal:
		node = node.get_parent()
	if node is Modal:
		(node as Modal).finish()
	else:
		_queue_rebuild()


## Browser: a new version is fetched by reloading the page (the shell installs it on its start screen).
func _reload_page() -> void:
	if OS.has_feature("web") and Engine.has_singleton(&"JavaScriptBridge"):
		JavaScriptBridge.eval("window.location.reload()", true)


## Main menu without any world: starting a room creates one ("Welt 1"), said once so it is no
## surprise (playtest 16.10.2026: online must not need a world first).
func _add_new_world_hint() -> void:
	if lobby != null or SaveManager.get_continue_slot() > 0:
		return
	var slot := SaveManager.get_free_slot()
	if slot <= 0:
		return
	var line := UiKit.wrapped_text(_format(&"ONLINE_MENU_NEW_WORLD_HINT", [SaveSlots.default_name(slot)]), _content_width(), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	line.name = "NewWorldHint"
	_content.add_child(line)


## Quick tab while this machine is in a guild room (or joining one): the room lives on the guild's
## page; one line and a button there.
func _build_guild_room_pointer() -> void:
	var guild_id := get_room_guild()
	var summary := directory.find_summary(guild_id)
	var tag := str(summary.get("tag", lobby.room_guild_tag if lobby != null else ""))
	var guild_name := str(summary.get("name", lobby.room_guild_name if lobby != null else ""))
	var text := _format(&"GUILD_ROOM_ACTIVE", ["[%s] %s" % [tag, guild_name] if not tag.is_empty() else guild_name])
	if tag.is_empty() and guild_name.is_empty():
		text = tr(&"GUILD_ROOM_ACTIVE_PLAIN")
	var line := UiKit.wrapped_text(text, _content_width(), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	line.name = "GuildRoomActive"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(line)
	var go := _button(&"GUILD_ROOM_SHOW", func() -> void:
		_set_notice("")
		show_view(View.DETAIL, guild_id), true, BIG_BUTTON_WIDTH)
	go.name = "ShowGuildRoom"
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(go)
	_focus_target = go


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
## (LobbySlot) and Start (host) / Leave. on_guild_page: the guild room on its guild's page (the
## page header names the guild; members find the room in their guild).
func _build_room(parent: Container, on_guild_page := false) -> void:
	var peers := lobby.get_room_peers()
	var net := _watch_net_players()
	if on_guild_page:
		var own := UiKit.text_label(&"GUILD_ROOM_OWN", UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)
		own.name = "GuildRoomTitle"
		parent.add_child(_centered(own))
	elif lobby.is_guild_room():
		var title := tr(&"GUILD_ROOM_TITLE") % lobby.room_guild_name if not lobby.room_guild_name.is_empty() else tr(&"GUILD_ROOM_TITLE_PLAIN")
		parent.add_child(_centered(UiKit.text_label(title, UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)))
	# A guild room needs no code: the guild finds it in the open rooms of its page (report b47bee4a).
	# Only an API without that list leaves the code as the way in.
	var show_code := not (on_guild_page or lobby.is_guild_room()) or not directory.rooms_supported
	if show_code:
		parent.add_child(_room_code_row())
	var host_name := str(peers[0].get("name", "")) if not peers.is_empty() and peers[0] is Dictionary else ""
	if net != null and not peers.is_empty() and peers[0] is Dictionary and not net.get_player_name_of(RelayProtocol.HOST_PEER_ID).is_empty():
		host_name = net.get_player_name_of(RelayProtocol.HOST_PEER_ID)
	if lobby.is_host():
		_room_hint_text = tr(&"LOBBY_SHARE_HINT") if show_code else tr(&"GUILD_ROOM_SHARE_HINT")
	else:
		_room_hint_text = tr(&"LOBBY_JOINED_HINT") % host_name
	_room_hint = _centered(UiKit.text_label(_room_hint_line(), UiKit.SIZE_BODY, UiKit.COLOR_MUTED))
	_room_hint.name = "RoomHint"
	parent.add_child(_room_hint)
	# The host's last guild run paid into the treasury (POST /runs guildPayout, D-081).
	var run := lobby.net_run
	if lobby.is_guild_room() and run != null and run.last_guild_treasury >= 0:
		var paid := UiKit.text_label(tr(&"GUILD_RUN_PAYOUT") % [run.last_guild_payout, run.last_guild_treasury], UiKit.SIZE_BODY, UiKit.COLOR_GOLD)
		paid.name = "GuildPayout"
		parent.add_child(_centered(paid))
	var max_players := int(lobby.room.get("maxPlayers", RelayProtocol.MAX_ROOM_PLAYERS))
	parent.add_child(_build_slots(peers, max_players, net, show_code))
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
	parent.add_child(actions)


## "RAUMCODE ABCD23 [Kopieren] [Link kopieren]" of a room; on phones in the browser "Teilen" instead
## of "Link kopieren" (MP2b).
func _room_code_row() -> HBoxContainer:
	var code_row := UiKit.hbox(int(UiKit.px(6)))
	code_row.name = "RoomCodeRow"
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
	var sharing := InviteLink.can_share()
	var link := _button(&"INVITE_SHARE" if sharing else &"INVITE_COPY_LINK", func() -> void: pass, false, 0.0)
	link.name = "ShareLink" if sharing else "CopyLink"
	link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	link.pressed.connect(func() -> void:
		if share_link() and not sharing:
			link.text = tr(&"LOBBY_CODE_COPIED"))
	code_row.add_child(link)
	return code_row


## One LobbySlot per place: players in room order (host first), then the free places; the first free
## place offers the code ("Code teilen") when the room is joined by code (offer_code).
func _build_slots(peers: Array, max_players: int, net: NetPlayers, offer_code := true) -> Control:
	var row := UiKit.hbox(int(UiKit.px(SLOT_GAP)))
	row.name = "LobbyPlayers"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var places := maxi(1, max_players)
	# The village dialog scrolls: leave room for its scroll bar.
	var usable := _content_width() - (1.0 if max_content_height > 0.0 else 0.0)
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
			if offer_code and not share_offered:
				share = share_link
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


## The invite link of the room (MP2b): the share sheet on phones in the browser, else the clipboard
## with a notice. false without a room.
func share_link() -> bool:
	var url := get_invite_url()
	if url.is_empty():
		return false
	UiSound.click(self)
	if InviteLink.share(url, _format(&"INVITE_SHARE_TEXT", [lobby.get_room_code()])):
		return true
	_set_notice(tr(&"INVITE_LINK_COPIED"))
	_update_status()
	return true


## Link to the room of this machine ("" outside a room).
func get_invite_url() -> String:
	if lobby == null or lobby.get_room_code().is_empty():
		return ""
	return InviteLink.for_room(lobby.get_room_code())


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


## Back to the room view (also after saving): the quick tab, or the guild's page of a guild room.
func close_profile_editor() -> void:
	_profile_editor = null
	var room_guild := get_room_guild()
	if not room_guild.is_empty():
		show_view(View.DETAIL, room_guild)
	else:
		show_view(View.QUICK)


func get_profile_editor() -> ProfileEditor:
	return _profile_editor if _has_profile_editor() else null


## The scroll area of the content (null without max_content_height), for tests and tools.
func get_scroll_area() -> ScrollContainer:
	return _scroll_area


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
	var usable := _content_width() - (1.0 if max_content_height > 0.0 else 0.0)
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
		var error := UiKit.wrapped_text(GuildDirectory.error_text(directory.list_error), _content_width(), UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
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
	var text := UiKit.wrapped_text(tr(&"GUILD_EMPTY"), _content_width(), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	text.name = "NoGuild"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(text)
	_content.add_child(_build_perks())
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


## "Was bringt eine Gilde?": only what the game really has (PERK_KEYS: guild rooms only for members,
## the treasury filled by guild runs, the guild leaderboard). Nothing about the guild forge until it
## exists (MP8).
func _build_perks() -> PanelContainer:
	var panel := UiKit.panel(&"dark")
	panel.name = "GuildPerks"
	var box := UiKit.vbox(int(UiKit.px(2)))
	box.add_child(UiKit.text_label(&"GUILD_PERKS_TITLE", UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true))
	for key: StringName in PERK_KEYS:
		var line := UiKit.wrapped_text("•  " + tr(key), _content_width() - 16.0, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		line.name = "Perk_%s" % String(key).trim_prefix("GUILD_PERK_")
		box.add_child(line)
	panel.add_child(box)
	return panel


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
	_content.add_child(UiKit.wrapped_text(tr(&"GUILD_CREATE_RULES"), _content_width(), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED))
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
	_content.add_child(UiKit.wrapped_text(tr(&"GUILD_JOIN_HINT"), _content_width(), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
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


## One guild: tag and name, own role; the own guild room right below the header (when in one);
## invite code, treasury with what guild runs bring, leave; the open rooms of the guild with
## "Beitreten", "Gilden-Raum erstellen" and joining by code; the members.
func _build_detail() -> void:
	var detail := directory.get_detail(detail_id)
	var summary := detail if not detail.is_empty() else directory.find_summary(detail_id)
	var role := directory.get_own_role(detail_id)
	var room_here := not detail_id.is_empty() and get_room_guild() == detail_id
	var header := UiKit.hbox(int(UiKit.px(4)))
	var back := _back_button()
	back.custom_minimum_size.x = 0.0
	Modal.compact_buttons(back)
	header.add_child(back)
	var tag := str(summary.get("tag", ""))
	var guild_name := str(summary.get("name", ""))
	if summary.is_empty() and room_here and lobby != null:
		# The room is there before the guild finished loading (e.g. right after entering it).
		tag = lobby.room_guild_tag
		guild_name = lobby.room_guild_name
	var title := UiKit.text_label("[%s]  %s" % [tag, guild_name] if not tag.is_empty() else guild_name, UiKit.SIZE_HEADING, UiKit.COLOR_GOLD, true)
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
	# The own guild room first: that is what the player came for (code, places, Start/Leave).
	if room_here and is_in_room():
		var room_box := UiKit.vbox(int(UiKit.px(4)))
		room_box.name = "GuildRoom"
		_build_room(room_box, true)
		_content.add_child(room_box)
		_content.add_child(UiKit.separator())
	if detail.is_empty():
		_content.add_child(_centered(UiKit.text_label(&"GUILD_LOADING_ONE", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)))
		if _focus_target == null:
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
	treasury.tooltip_text = tr(&"GUILD_PERK_TREASURY")
	treasury.mouse_filter = Control.MOUSE_FILTER_PASS
	treasury_row.add_child(treasury)
	# Leaving sits here (asks first), the dialog stays short (R8, D-139).
	var leave := _button(&"GUILD_LEAVE", _ask_leave, false, 0.0)
	leave.name = "LeaveGuild"
	leave.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT)
	leave.disabled = directory.is_busy()
	treasury_row.add_child(leave)
	info_box.add_child(treasury_row)
	# What guild runs bring, in one line (the long version is the empty guild tab).
	var perks := UiKit.wrapped_text(tr(&"GUILD_DETAIL_PERKS"), _content_width() - 12.0, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	perks.name = "GuildPerksShort"
	info_box.add_child(perks)
	_content.add_child(info)

	if not (room_here and is_in_room()):
		_build_guild_rooms()

	var members: Array = detail.get("members", [])
	_content.add_child(UiKit.text_label(tr(&"GUILD_MEMBERS") % [members.size(), int(detail.get("maxMembers", GuildDirectory.MAX_GUILD_MEMBERS))], UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true))
	var list := UiKit.vbox(int(UiKit.px(1)))
	list.name = "Members"
	var own_id := directory.get_own_player_id()
	for member: Dictionary in members:
		list.add_child(_member_row(member, role, own_id))
	_content.add_child(_list_area(list, MEMBERS_HEIGHT))
	if _focus_target == null:
		_focus_target = back


## Guild rooms on the guild's page: the open rooms of the guild (GET /guilds/:id/rooms; hidden on an
## API without the route or while the relay is away) with "Beitreten", then "Gilden-Raum erstellen".
## Joining by room code only on an API without the list (report b47bee4a: guild rooms need no code).
## Everything is blocked while this machine is in a room or entering one.
func _build_guild_rooms() -> void:
	var blocked := _room_blocked()
	var section := UiKit.vbox(int(UiKit.px(2)))
	section.name = "GuildRooms"
	if directory.rooms_supported and directory.has_rooms(detail_id):
		section.add_child(UiKit.text_label(&"GUILD_ROOMS_OPEN", UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true))
		var own_code := lobby.get_room_code() if lobby != null and is_in_room() else ""
		var rows := UiKit.vbox(int(UiKit.px(1)))
		rows.name = "OpenRooms"
		for room in directory.get_rooms(detail_id):
			if str(room.code) == own_code:
				continue
			rows.add_child(_open_room_row(room, blocked))
		if rows.get_child_count() == 0:
			rows.free()
			var none := UiKit.text_label(&"GUILD_ROOMS_NONE", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
			none.name = "NoOpenRooms"
			section.add_child(none)
		else:
			section.add_child(_list_area(rows, ROOMS_HEIGHT))
	var room_row := UiKit.hbox(int(UiKit.px(4)))
	room_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var room := _button(&"GUILD_ROOM_CREATE", _create_guild_room, true, BIG_BUTTON_WIDTH)
	room.name = "CreateGuildRoom"
	room.custom_minimum_size.y = UiKit.px(BIG_BUTTON_HEIGHT * 0.75)
	room.tooltip_text = tr(&"GUILD_ROOM_HINT")
	room.disabled = blocked
	if is_in_room():
		room.tooltip_text = tr(&"GUILD_ROOM_LEAVE_FIRST")
	room_row.add_child(room)
	if not directory.rooms_supported:
		_add_guild_room_code(room_row, blocked)
	section.add_child(room_row)
	_content.add_child(section)
	if not room.disabled:
		_focus_target = room


## Fallback for an API without the open rooms: join a guild room of this guild by its room code.
func _add_guild_room_code(room_row: HBoxContainer, blocked: bool) -> void:
	var room_code := _line_edit("GuildRoomCode", &"LOBBY_CODE_PLACEHOLDER", _guild_room_code, RelayProtocol.ROOM_CODE_LENGTH, 62.0)
	room_code.editable = not blocked
	room_code.tooltip_text = tr(&"GUILD_ROOM_JOIN_HINT")
	room_row.add_child(room_code)
	var room_join := _button(&"GUILD_ROOM_JOIN", func() -> void: _join_guild_room(), false, 0.0)
	room_join.name = "JoinGuildRoom"
	room_join.tooltip_text = tr(&"GUILD_ROOM_JOIN_HINT")
	room_join.disabled = blocked or not RelayProtocol.is_valid_code(_guild_room_code)
	room_row.add_child(room_join)
	room_code.text_changed.connect(func(text: String) -> void:
		var normalized := RelayProtocol.normalize_code(text)
		if normalized != text:
			room_code.text = normalized
			room_code.caret_column = normalized.length()
		_guild_room_code = normalized
		room_join.disabled = _room_blocked() or not RelayProtocol.is_valid_code(normalized))
	room_code.text_submitted.connect(func(_text: String) -> void:
		if not room_join.disabled:
			_join_guild_room())


## One open room of the guild: "Raum von <host>", players, and "Beitreten" (greyed out while its run
## is on, for another game version, when full or while this machine is in a room).
func _open_room_row(room: Dictionary, blocked: bool) -> Control:
	var code := str(room.code)
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.name = "OpenRoom_%s" % code
	var host := str(room.get("hostName", ""))
	var label := UiKit.text_label(_format(&"GUILD_ROOM_OF", [host if not host.is_empty() else "?"]), UiKit.SIZE_BODY, UiKit.COLOR_TEXT)
	label.name = "Host"
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var state := ""
	var hint := ""
	var version := str(room.get("gameVersion", ""))
	if bool(room.get("started", false)):
		state = tr(&"GUILD_ROOM_RUNNING")
		hint = tr(&"GUILD_ROOM_RUNNING_HINT")
	elif not version.is_empty() and version != OnlineConfig.get_game_version():
		state = tr(&"GUILD_ROOM_OTHER_VERSION")
		hint = _format(&"GUILD_ROOM_OTHER_VERSION_HINT", [version])
	if not state.is_empty():
		var state_label := UiKit.text_label(state, UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
		state_label.name = "State"
		state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		state_label.tooltip_text = hint
		state_label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(state_label)
	var players := UiKit.text_label(tr(&"GUILD_MEMBERS_SHORT") % [int(room.get("players", 0)), int(room.get("maxPlayers", RelayProtocol.MAX_ROOM_PLAYERS))], UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	players.name = "Players"
	players.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(players)
	var join := _button(&"GUILD_ROOM_JOIN", func() -> void: _join_guild_room(code), false, 0.0)
	join.name = "JoinListed_%s" % code
	join.disabled = blocked or not state.is_empty() or int(room.get("players", 0)) >= int(room.get("maxPlayers", RelayProtocol.MAX_ROOM_PLAYERS))
	join.tooltip_text = hint if not hint.is_empty() else (tr(&"GUILD_ROOM_LEAVE_FIRST") if is_in_room() else "")
	Modal.compact_buttons(join)
	row.add_child(join)
	return row


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
	var text := UiKit.wrapped_text(str(_confirm.get("text", "")), _content_width(), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT)
	text.name = "ConfirmText"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(text)
	var actions := UiKit.hbox(int(UiKit.px(4)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var yes := _button(str(_confirm.get("yes", "")), func() -> void:
		var action: Callable = _confirm.get("action", Callable())
		var back: View = _confirm.get("back", View.GUILDS)
		_return_from_confirm()
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
	# Room state on the page that shows the room (quick tab, or the guild's page of a guild room);
	# room errors only where the room action started.
	var room_page := view == View.QUICK or (view == View.DETAIL and not detail_id.is_empty() and get_room_guild() == detail_id)
	var room_errors := (_room_origin == View.QUICK and view == View.QUICK) \
			or (_room_origin == View.DETAIL and view == View.DETAIL and _room_origin_guild == detail_id)
	var room_error := ""
	if lobby != null and (room_page or room_errors):
		match lobby.state:
			LobbyClient.State.LOGGING_IN:
				text = tr(&"LOBBY_STATUS_LOGGING_IN")
			LobbyClient.State.CONNECTING:
				text = tr(&"LOBBY_STATUS_CONNECTING")
			LobbyClient.State.LEAVING:
				text = tr(&"LOBBY_STATUS_LEAVING")
			_:
				if room_errors and not lobby.last_error.is_empty():
					room_error = LobbyClient.error_text(lobby.last_error)
	if not text.is_empty():
		pass
	elif view == View.QUICK:
		# An invite shows its failure in its own card (_build_invite); a copied link is a notice.
		var invite_card := lobby != null and lobby.has_invite() and not is_in_room()
		text = "" if invite_card else room_error
		color = UiKit.COLOR_DANGER_SOFT
		if text.is_empty() and not notice.is_empty() and not notice_is_error:
			text = notice
			color = UiKit.COLOR_SUCCESS
	else:
		if (view == View.CREATE or view == View.JOIN) and notice_is_error:
			# Shown at the field (_add_field_error, _add_form_error).
			text = ""
		elif not notice.is_empty():
			text = notice
			color = UiKit.COLOR_DANGER_SOFT if notice_is_error else UiKit.COLOR_SUCCESS
		elif not room_error.is_empty():
			text = room_error
			color = UiKit.COLOR_DANGER_SOFT
		elif directory.is_busy() and directory.loaded:
			text = tr(&"GUILD_WORKING")
	_status.text = text
	_status.visible = not text.is_empty() or _scroll_area != null
	_status.add_theme_color_override("font_color", color)


# --- Actions ---

func _create_quick_room() -> void:
	_set_room_origin(View.QUICK)
	if lobby == null:
		launch_requested.emit({"action": LobbyClient.LAUNCH_CREATE, "mode": LobbyClient.MODE_QUICK})
		return
	lobby.resume_dialog = true
	lobby.create_room()


func _join_room() -> void:
	if not RelayProtocol.is_valid_code(_room_code):
		return
	_set_room_origin(View.QUICK)
	if lobby == null:
		launch_requested.emit({"action": LobbyClient.LAUNCH_JOIN, "code": _room_code})
		return
	lobby.resume_dialog = true
	lobby.join_room(_room_code)


## Guild room of the open guild: only its members may join (the relay asks the API). The room is
## shown right here on the guild's page (not in the quick tab).
func _create_guild_room() -> void:
	var summary := directory.find_summary(detail_id)
	var guild_name := str(directory.get_detail(detail_id).get("name", summary.get("name", "")))
	var guild_tag := str(directory.get_detail(detail_id).get("tag", summary.get("tag", "")))
	_set_room_origin(View.DETAIL, detail_id)
	if lobby == null:
		launch_requested.emit({"action": LobbyClient.LAUNCH_CREATE, "mode": LobbyClient.MODE_GUILD, "guild_id": detail_id, "guild_name": guild_name, "guild_tag": guild_tag})
		return
	lobby.resume_dialog = true
	lobby.room_guild_name = guild_name
	lobby.room_guild_tag = guild_tag
	lobby.create_room(LobbyClient.MODE_GUILD, detail_id)


## Join a guild room of the open guild: from its list of open rooms (code) or by the typed room code;
## the relay lets only members in (not_guild_member). The room is shown on the guild's page.
func _join_guild_room(code := "") -> void:
	var room_code := code if not code.is_empty() else _guild_room_code
	if not RelayProtocol.is_valid_code(room_code):
		return
	var guild_id := detail_id
	var summary := directory.find_summary(guild_id)
	var guild := directory.get_detail(guild_id)
	var guild_name := str(guild.get("name", summary.get("name", "")))
	var guild_tag := str(guild.get("tag", summary.get("tag", "")))
	_set_room_origin(View.DETAIL, guild_id)
	if lobby == null:
		launch_requested.emit({"action": LobbyClient.LAUNCH_JOIN, "code": room_code, "guild_id": guild_id, "guild_name": guild_name, "guild_tag": guild_tag})
		return
	lobby.resume_dialog = true
	await lobby.join_room(room_code, guild_id, guild_name, guild_tag)


## Room errors are shown where the room action started (the quick tab or that guild's page).
func _set_room_origin(origin: View, guild_id := "") -> void:
	_room_origin = origin
	_room_origin_guild = guild_id


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
	var focused := _focus_owner()
	_confirm = {"text": text, "yes": yes_text, "action": action, "back": back,
		"focus": String(focused.name) if focused != null else "",
		"scroll": _scroll_area.scroll_vertical if _scroll_area != null else 0}
	view = View.CONFIRM
	_rebuild()


## Leaving the confirmation: the page that asked gets its focus and scroll back (next build).
func _return_from_confirm() -> void:
	_return_to = {"focus": str(_confirm.get("focus", "")), "scroll": int(_confirm.get("scroll", 0))}
	_confirm = {}


func _copy_invite(code: String) -> void:
	DisplayServer.clipboard_set(code)
	_set_notice(tr(&"GUILD_COPIED"))
	_rebuild()


func _set_notice(text: String, is_error := false) -> void:
	notice = text
	notice_is_error = is_error


func _on_action_finished(action: StringName, result: ApiResult, info: Dictionary) -> void:
	var guild_name := str(info.get("name", ""))
	# Open rooms are polled quietly: no notice, the list just shows or hides (GuildDirectory.changed).
	if action == GuildDirectory.ACTION_ROOMS:
		return
	if not result.ok:
		if action == GuildDirectory.ACTION_LIST:
			return
		var failed_id := str(info.get("guild_id", ""))
		var room_guild := get_room_guild()
		# The guild's page stays while this machine's room of that guild is on it (server away: the
		# room on the relay still works).
		if action == GuildDirectory.ACTION_DETAIL and failed_id == room_guild and not failed_id.is_empty() \
				and (result.error == ApiResult.UNREACHABLE or result.error == ApiResult.TIMEOUT):
			_queue_rebuild()
			return
		_set_notice(GuildDirectory.error_text(result.error), true)
		form_error_field = form_field_for(result.error)
		if action == GuildDirectory.ACTION_DETAIL and directory.find_summary(failed_id).is_empty() and view == View.DETAIL and failed_id != room_guild:
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
	if not is_inside_tree():
		return
	if lobby != null and (lobby.is_in_room() or lobby.is_busy()):
		var room_guild := get_room_guild()
		if not room_guild.is_empty():
			# A guild room is shown on its guild's page.
			if view == View.GUILDS or (view == View.DETAIL and detail_id != room_guild):
				show_view(View.DETAIL, room_guild)
				return
		elif view == View.GUILDS:
			# A quick room entered (or creating one started) from the guild tab: show it.
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
	var error := UiKit.wrapped_text(notice, _content_width(), UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
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


## tr(key) % args, safe while a text is missing or has no placeholder (a new key before the
## translations have it shows the key instead of failing).
func _format(key: StringName, args: Array) -> String:
	var text := tr(key)
	if not text.contains("%"):
		return text
	return text % args


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


## A vertical scroll area that is never taller than max_height mockup pixels; fixed: always exactly
## that high (the content area of the menu: views of every length keep the dialog's size).
func _scroll(child: Control, max_height: float, fixed := false) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The bar shows only when needed, but its room is always kept: the width never jumps (60711d3b).
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.follow_focus = true
	# The pixel bar of the dialogs instead of Godot's grey one (report e0ca0a4f).
	Modal._style_scroll_bar(scroll.get_v_scroll_bar())
	scroll.gui_input.connect(func(event: InputEvent) -> void:
		if wheel_scroll(scroll, event, Time.get_ticks_msec(), OS.has_feature("web")):
			scroll.accept_event())
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A small gap before the scroll bar, so it never touches the last column.
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", int(UiKit.px(SCROLL_GAP)))
	margin.add_child(child)
	scroll.add_child(margin)
	var limit := UiKit.px(max_height)
	if fixed:
		scroll.custom_minimum_size.y = limit
		return scroll
	scroll.custom_minimum_size.y = minf(limit, child.get_combined_minimum_size().y)
	child.minimum_size_changed.connect(func() -> void:
		if is_instance_valid(scroll):
			scroll.custom_minimum_size.y = minf(limit, child.get_combined_minimum_size().y))
	return scroll


## Width in mockup pixels a line of the content may take: the menu minus the room of the scroll bar
## (gap and bar), so every view is exactly as wide as the menu (report 60711d3b).
func _content_width() -> float:
	return menu_width - (SCROLL_GAP + Modal.SCROLL_BAR_WIDTH if max_content_height > 0.0 else 0.0)


## Mouse wheel in a scroll area (gui_input runs before the ScrollContainer's own handling): WHEEL_STEP
## per step, times the step's share on the desktop (smooth wheels and touchpads send small ones). In
## the browser (web) every event counts as a full step, so quick ones only move by the time since the
## last one (WEB_WHEEL_WINDOW_MSEC). true = used, the ScrollContainer's own step is skipped; false at
## the end of the area, so a scroll area around it may move.
static func wheel_scroll(scroll: ScrollContainer, event: InputEvent, now_msec: int, web := false) -> bool:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.shift_pressed:
		return false
	var direction := 0.0
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1.0
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1.0
	if direction == 0.0:
		return false
	var bar := scroll.get_v_scroll_bar()
	var end := bar.max_value - bar.page
	if end <= 0.0 or (direction < 0.0 and bar.value <= 0.0) or (direction > 0.0 and bar.value >= end):
		return false
	var share := button.factor if button.factor > 0.0 else 1.0
	if web:
		var last := int(scroll.get_meta(&"wheel_msec", -1_000_000))
		scroll.set_meta(&"wheel_msec", now_msec)
		share = clampf(float(now_msec - last) / WEB_WHEEL_WINDOW_MSEC, 0.0, 1.0)
	bar.value = clampf(bar.value + direction * UiKit.px(WHEEL_STEP) * share, 0.0, end)
	return true


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
