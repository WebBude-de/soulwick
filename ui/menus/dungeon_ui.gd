class_name DungeonUI
extends CanvasLayer
## Dungeon dialogs: upgrade choice, shop, weapon slot replacement, confirmations, the campfire rest
## and the Tab overview. Every dialog pauses the simulation while open (D-043) and shows effective
## values from the same getters the attacks use (D-034).
## All dialogs share one menu kit (UX2, UiDialog): framed panel on the dimmed scene, eyebrow, title,
## subtitle, cards or option buttons with key caps, the key bar inside the panel and the same sounds.
## Cards never turn half transparent: a card that cannot be taken keeps its look and gets a badge
## (too little gold with a lock and a red price, sold, at the limit); a click answers with the error
## sound and a shake.
## Also non-blocking feedback: banners (queued, one at a time), room genre banners and first-time
## explanations (D-110, RoomGenre), the boss bar (name + tier, phase, badges, portrait),
## first-encounter hint cards for new enemy types, elite kinds and champions (EnemyHints) and the
## first-run controls card (ControlsHint, once per save, UX1). Only one teaching card is on screen at
## a time: the controls card steps aside while an enemy or room card shows.
## Room modes (R3, KONZEPT_RAEUME_V2 §1.3/§1.4): the intro of a room (RoomIntro: goal banner, 3-2-1,
## first-time card, sounds) and the task bar at the top centre (ObjectiveBar for the room's
## RoomObjective; the boss bar replaces it). Both are found through node_added, so a mode only adds
## its RoomObjective / RoomIntro under its room. The arena is started here (show_room_genre).
## Banners (07_ui.md): dark plaque with a stripe in the mode colour; banners and world captions
## (WorldCaption, only near a player) never share the screen; banners of a room left behind and
## banners that waited too long are dropped.
## Overlays and the fight (online test 16.10.2026: "Gegner sieht man oft schlecht, weil
## Texteinblendungen davor sind"): no message sits in the middle of the playfield. Everything lives
## in a top band below the HUD's top bars (task bar, boss bar, then the status line, then banners
## and the 3-2-1) or on the left edge below the hearts (teaching cards). While enemies are on screen
## a banner comes as a slim strip instead of the big plaque, and every overlay fades to
## OverlayDodge.DODGE_ALPHA while an enemy or a player stands under it. show_status_line() offers a
## small line at the top for state texts (coop: waiting, hurry up).
## Overlay hierarchy (same plate, stripe in the colour of the message): important news big and short
## (banner plaque, never over a running fight), info small at the top (strip, status line), teaching
## on the left edge, world texts small and short (damage numbers).
## Down and out (D-084, feedback 16.10.2026): the local player's fall gets a short banner with what
## took them down (RunRecap.describe_hit); a downed player in a group game gets the DownedPanel at the
## bottom (what happened, how to get up, revive progress), the others a strip and DownedMarkers
## (chevron over the mate, arrow at the screen edge). Players are watched by group, look only.
## Layout follows docs/design screens 02-06, 10 and 11; sizes are mockup pixels (UiKit.px).
## Modal dialogs run one after another (open_dialog): while a dialog is open (here or in GameUI),
## the next one waits in a queue (first requested, first shown) and appears DIALOG_GAP after the
## last one closed, under Modal's input guard, so a held key or a quick second click never picks
## in the second dialog (bug: chest and upgrade choice opened inside each other). Only a dialog
## opened from inside another (shop -> weapon slot) goes on top at once.

## A dialog of open_dialog is on screen now (at once or after waiting in the queue). NetDungeon
## tells the host when a client's timed upgrade choice really appeared.
signal dialog_shown(modal: Modal)

## Meta of a modal naming the dialog (dialog_shown listeners, e.g. a first-time hint on the upgrade
## choice): modal.get_meta(DIALOG_KIND, &"") == DIALOG_UPGRADE_CHOICE.
const DIALOG_KIND: StringName = &"dialog_kind"
const DIALOG_UPGRADE_CHOICE: StringName = &"upgrade_choice"

## Overlays fade while a body is under them, big banners shrink during a fight (no class_name: no
## global class cache entry needed).
const OverlayDodge := preload("res://ui/hints/overlay_dodge.gd")
## Downed panel and markers (preloaded, no class_name).
const DownedPanel := preload("res://ui/hints/downed_panel.gd")
const DownedMarkers := preload("res://ui/hints/downed_markers.gd")
## Colour of falls and downed players; seconds the fall banner stays (the run end follows after
## DungeonManager.DEATH_SCREEN_DELAY = 1.4 s), and the height of a mate's chevron over the body
## (world px, above NetDungeon's revive label at 78 px).
const DOWNED_COLOR := Color("#ff7366")
const FALL_BANNER_TIME := 1.4
const DOWNED_MARKER_LIFT := 96.0

## Seconds a plain banner stays (TESTWERT; was 2.2 before the online test of 16.10.2026).
const BANNER_TIME := 1.8
## A newer banner waits until the current one was readable this long (real seconds, TESTWERT).
const BANNER_MIN_TIME := 1.2
## A banner that waited longer than this in the queue is dropped (real seconds, TESTWERT).
const BANNER_STALE_TIME := 8.0
## Banner top in mockup pixels, below the task bar (it moves further down under a taller bar), and
## time of a genre banner on screen (TESTWERT).
const GENRE_BANNER_TOP := 24.0
const GENRE_BANNER_TIME := 2.4
const GENRE_ICON_SIZE := 16.0
## Intro banner (07_ui_intro_arena.png): bigger symbol; it stays while the intro runs and this long
## after "go" (TESTWERTE). An intro that never ends lets go of the banner after INTRO_HOLD_MAX.
const INTRO_ICON_SIZE := 24.0
const INTRO_BANNER_AFTER := 1.0
const INTRO_BANNER_AFTER_RUNNING := 3.0
const INTRO_HOLD_MAX := 15.0
## Colour stripe on the left of every banner (07_ui.md: 4-6 px of the mode colour).
const BANNER_STRIPE_WIDTH := 4.0
## Task bar and boss bar top (mockup pixels).
const TOP_BAR_Y := 4.0
## Banner strip (online test 16.10.2026): while enemies are on screen a banner is one slim line -
## thin stripe, small symbol, title and subtitle side by side on a see-through plaque - and stays
## STRIP_TIME (TESTWERTE, mockup pixels). The plaque itself is a little see-through too.
const STRIP_TIME := 1.5
const STRIP_STRIPE_WIDTH := 2.0
const STRIP_ICON_SIZE := 10.0
const STRIP_SUBTITLE_WIDTH := 200.0
const STRIP_ALPHA := 0.8
const PLAQUE_ALPHA := 0.92
## Gap between the pieces of the top band, and its top on a touch screen (below the touch buttons
## for the overview and the pause menu at the top centre, TouchOverlay; mockup pixels).
const TOP_BAND_GAP := 3.0
const TOUCH_TOP_CLEAR := 32.0
## Status line at the top (show_status_line): wraps at this width, fades in and out (seconds).
const STATUS_LINE_WIDTH := 220.0
const STATUS_LINE_FADE := 0.2
const STATUS_LINE_ALPHA := 0.85
## Banner subtitles wrap at this width (mockup pixels); the intro's rule line earlier, so the goal
## banner stays a compact plaque in the middle (07_ui_intro_arena.png).
const BANNER_SUBTITLE_WIDTH := 280.0
const INTRO_SUBTITLE_WIDTH := 190.0
## Boss bar (R8: compact, as high as the task bar it replaces, never over the room line): portrait,
## name and phase in one line, HP bar under it. Mockup pixels.
const BOSS_BAR_SIZE := Vector2(168, 4)
const BOSS_BAR_WIDTH := 168.0
const BOSS_PORTRAIT_SIZE := 16.0
const BOSS_BAR_COLOR := Color("#a66ef0")
const BOSS_BAR_ENRAGED_COLOR := Color("#e0463a")
const CHAMPION_BAR_COLOR := Color("#e0b84a")
## Boss-specific bar colours (HANDOUT palette); other bosses use their placeholder colour.
const BOSS_COLORS := {
	&"boss_slime_queen": Color("#f0648c"),
	&"boss_ember_golem": Color("#ff8a3c"),
	&"boss_shadow_lord": Color("#a66ef0"),
	&"boss_bone_king": Color("#b8b09a"),
}
## Enemy hint card: seconds on screen (TESTWERT; was 5 before the online test of 16.10.2026).
const HINT_TIME := 4.5
const HINT_WIDTH := 150.0
## Teaching cards that were on screen this long end when the players walk into the next room (QA
## 16.10.2026: "Abgrund" stood until room 4; real seconds), and they are a little see-through while
## a fight is on screen (TESTWERTE).
const HINT_ROOM_CHANGE_MIN := 2.0
const CARD_FIGHT_ALPHA := 0.8
## Enemy hint cards sit on the left edge like the room cards (they were at the bottom centre, under
## the player's feet, until the online test of 16.10.2026; mockup px).
const HINT_EDGE_MARGIN := 8.0
## Upgrade cards inside UiDialog.WIDTH_WIDE (R8: compact so the dialog stays under 60 % of the
## screen height; ui_spec had 124 × 158). Padding: vertical, horizontal (mockup pixels).
const CARD_SIZE := Vector2(136, 82)
const CARD_PADDING := Vector2(7, 6)
const CARD_NAME_WIDTH := 86.0
const CARD_GAP := 6.0
const CARD_LIFT := 3.0
const STACK_PIP_SIZE := 4.0
## Sound of an upgrade pick.
const PICK_SOUND: StringName = &"upgrade"
## Shop grid: 3 columns, gap 6 (ui_spec screens.shop.grid) inside UiDialog.WIDTH_WIDE. R8: compact
## cards (2 rows stay under 60 % of the screen): symbol tile with the key under it, kind and price
## on top, name, effect (2 lines) or the state badge.
const SHOP_COLUMNS := 3
const SHOP_GAP := 5.0
const SHOP_CARD_SIZE := Vector2(138, 40)
const SHOP_CARD_PADDING := Vector2(6, 6)
const SHOP_ICON_SIZE := 24.0
const SHOP_TEXT_WIDTH := 96.0
const SHOP_PRICE_WIDTH := 22.0
## Weapon comparison panel (ui_spec screens.weapon_room).
const WEAPON_PANEL_WIDTH := 310.0
const WEAPON_COLUMN_GAP := 6.0
const WEAPON_ICON_SIZE := 16.0
## Tab overview panel (ui_spec screens.tab_overview; R8 lower, max 60 % of the screen).
const OVERVIEW_SIZE := Vector2(452, 158)
const OVERVIEW_LIST_HEIGHT := 72.0
const DIALOG_WIDTH := UiDialog.WIDTH_NARROW
const CHOICE_DIALOG_WIDTH := 262.0
## Option cards of choose_option (mockup pixels).
const OPTION_CARD_WIDTH := 112.0
## Campfire dialog: width, heal column and heal button height in mockup pixels; above
## CAMPFIRE_LIST_ROWS upgrades the list scrolls.
const CAMPFIRE_DIALOG_WIDTH := 330.0
const CAMPFIRE_HEAL_WIDTH := 110.0
const CAMPFIRE_HEAL_HEIGHT := 34.0
const CAMPFIRE_LIST_ROWS := 4
const CAMPFIRE_LIST_HEIGHT := 70.0
const NUMBER_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
## A queued dialog appears this long after the dialog before it closed (real seconds, TESTWERT).
const DIALOG_GAP := 0.25
## Pause reason held while dialogs wait in the queue: the world stays held between two dialogs.
const PAUSE_DIALOG_QUEUE: StringName = &"dialog_queue"

var context: DungeonContext = null
## Show a hint card the first time an enemy type / elite kind / champion appears.
var auto_enemy_hints := true
## Overlays fade while an enemy or a player is under them (tests may switch it off).
var dodge_overlays := true
## Show the first-run controls card (once per save); tests and tools may switch it off.
var show_controls_hint := true

var _overview: Modal = null
var _banner_root: Control = null
var _banner_queue: Array[Dictionary] = []
var _banner_box: Control = null
var _banner_entry: Dictionary = {}
var _banner_since_ms := 0
## The banner on screen stays until its intro is over (intro banner).
var _banner_hold := false
## The banner on screen gives way at once (an intro banner came in).
var _banner_cut := false
var _objective_bar: ObjectiveBar = null
var _countdown: IntroCountdown = null
var _intro: RoomIntro = null
var _boss_bar_root: Control = null
var _boss_bar: ProgressBar = null
var _boss_fill: StyleBoxFlat = null
var _boss_name: Label = null
var _boss_sub: Label = null
var _boss_hp_text: Label = null
var _boss_phase: Label = null
var _boss_marker: ColorRect = null
var _boss_badges: HBoxContainer = null
var _boss_portrait: TextureRect = null
var _boss_color := BOSS_BAR_COLOR
var _boss: Enemy = null
var _hint_root: Control = null
## Status line at the top (show_status_line): root (dodge alpha), panel (fade), text, end time
## (real ms; 0 = until cleared) and its fade tween.
var _status_root: Control = null
var _status_panel: PanelContainer = null
var _status_label: Label = null
var _status_text := ""
var _status_until_ms := 0
var _status_tween: Tween = null
## Hook for the group game (NetDungeon): revive share 0..1 of a downed player,
## func(player: Player) -> float. Unset: the panel shows no progress bar.
var revive_share_provider: Callable = Callable()
## Watched players (instance id -> player; untyped: a player may be freed any time, a mate leaves or
## the world unloads) and what last hurt each one (cause text, RunRecap).
var _watched_players: Dictionary = {}
var _last_hit_by: Dictionary[int, String] = {}
var _downed_root: Control = null
var _downed_panel: DownedPanel = null
var _downed_markers: DownedMarkers = null
## Teaching cards waiting: {"kind": &"enemy", "title", "text", "badge"} or {"kind": &"room", "genre"}.
var _hint_queue: Array[Dictionary] = []
var _hint_card: Control = null
var _hint_entry: Dictionary = {}
var _controls_hint: ControlsHint = null
## Rooms whose genre was announced (instance id -> genre), so a room is named once.
var _announced_rooms: Dictionary[int, StringName] = {}
## Gap between two queued dialogs (DIALOG_GAP; tests may shorten it).
var dialog_gap := DIALOG_GAP
## Dialogs waiting for the one on screen, in request order (not in the tree yet).
var _dialog_queue: Array[Modal] = []
## Real time since when no dialog is open while the queue waits (-1 = a dialog is open).
var _dialog_free_since_ms := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_banner()
	_build_boss_bar()
	_build_objective_bar()
	_build_status_line()
	_build_hint_root()
	_build_downed()
	get_tree().node_added.connect(_on_node_added)
	EventBus.room_entered.connect(_on_room_entered_cards)
	# Deferred: the dungeon starts the run after its children are ready.
	start_controls_hint.call_deferred()


func _process(delta: float) -> void:
	_pump_dialogs()
	_pump_banners()
	_update_status_line()
	_watch_players()
	_update_downed()
	WorldCaption.update_all(get_tree(), get_banner() != null, _player_positions(), delta)
	_update_dodge(delta)


func _exit_tree() -> void:
	# Dialogs still waiting never come: free them and let go of the queue's pause.
	for modal in _dialog_queue:
		if is_instance_valid(modal):
			modal.free()
	_dialog_queue.clear()
	GameManager.release_pause(PAUSE_DIALOG_QUEUE)


# --- Dialog queue ---

## Shows modal and returns its result. A dialog requested while another one is open (or others wait)
## joins the queue and appears after them; the wait does not count against modal.auto_finish_after.
## over_open_dialog: opened from inside the open dialog (shop -> weapon slot), shown on top at once.
func open_dialog(modal: Modal, over_open_dialog := false) -> Variant:
	if over_open_dialog or (_dialog_queue.is_empty() and Modal.open_count() == 0):
		modal.show_on(self)
		dialog_shown.emit(modal)
		return await modal.finished
	_dialog_queue.append(modal)
	_dialog_free_since_ms = -1
	GameManager.request_pause(PAUSE_DIALOG_QUEUE)
	# Closed while still waiting (e.g. Tab on a queued overview): out of the queue.
	modal.finished.connect(_drop_queued.bind(modal).unbind(1))
	return await modal.finished


## true while a dialog is open or waiting.
func is_dialog_busy() -> bool:
	return not _dialog_queue.is_empty() or Modal.open_count() > 0


func get_dialog_queue_size() -> int:
	return _dialog_queue.size()


func _pump_dialogs() -> void:
	if _dialog_queue.is_empty():
		return
	if Modal.open_count() > 0:
		_dialog_free_since_ms = -1
		return
	var now := Time.get_ticks_msec()
	if _dialog_free_since_ms < 0:
		_dialog_free_since_ms = now
	if now - _dialog_free_since_ms < int(dialog_gap * 1000.0):
		return
	var modal: Modal = _dialog_queue.pop_front()
	_dialog_free_since_ms = -1
	# Opened before the queue lets go of its pause: the world stays held from one dialog to the next.
	modal.show_on(self)
	if _dialog_queue.is_empty():
		GameManager.release_pause(PAUSE_DIALOG_QUEUE)
	dialog_shown.emit(modal)


## A queued dialog finished before it was shown (also called when a shown one finishes: no-op then).
func _drop_queued(modal: Modal) -> void:
	if not _dialog_queue.has(modal):
		return
	_dialog_queue.erase(modal)
	if _dialog_queue.is_empty():
		GameManager.release_pause(PAUSE_DIALOG_QUEUE)


## Living players' positions (coop: all of them, D-088).
func _player_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_alive():
			positions.append(player.global_position)
	return positions


## Shows the first-run controls card if this save has not seen it yet. Returns the card or null.
func start_controls_hint() -> ControlsHint:
	if not show_controls_hint or _controls_hint != null or not ControlsHint.should_show():
		return null
	_controls_hint = ControlsHint.new()
	_controls_hint.finished.connect(func() -> void: _controls_hint = null)
	_hint_root.add_child(_controls_hint)
	if _hint_card != null:
		# A teaching card is up already: the controls card waits behind it.
		_set_controls_hint_waiting(true)
	return _controls_hint


func get_controls_hint() -> ControlsHint:
	return _controls_hint if is_instance_valid(_controls_hint) else null


# --- Banners ---

## Non-blocking title card, e.g. "Raum geschafft!" or a boss name. Banners queue: a newer one waits
## until the current one was on screen for BANNER_MIN_TIME, so quick events never overwrite each
## other unread.
func show_banner(title: String, subtitle := "", color := UiKit.ACCENT_COLOR) -> void:
	_queue_banner({"title": title, "subtitle": subtitle, "color": color})


## Banner currently on screen (null if none), for tests and tools.
func get_banner() -> Control:
	return _banner_box if is_instance_valid(_banner_box) and not _banner_box.is_queued_for_deletion() else null


func get_banner_queue_size() -> int:
	return _banner_queue.size()


## Entry: title, subtitle, color; optional kind (&"plain", &"genre", &"intro", &"wave"), genre,
## eyebrow, icon (Texture2D), tint (colour the icon), time (seconds on screen), priority (goes first
## and cuts the banner on screen short), intro (RoomIntro: stays until it is over), keep (never
## dropped as stale). Stamped with the room it belongs to.
func _queue_banner(entry: Dictionary) -> void:
	entry["room"] = entry.get("room", _current_room())
	entry["queued_ms"] = Time.get_ticks_msec()
	if entry.has("genre"):
		# The old plain banner of the same room (e.g. "Lagerfeuer") gives way to the genre banner.
		for i in range(_banner_queue.size() - 1, -1, -1):
			if not _banner_queue[i].has("genre") and _banner_queue[i]["title"] == entry["title"]:
				_banner_queue.remove_at(i)
		if get_banner() != null and not _banner_entry.has("genre") and _banner_entry.get("title", "") == entry["title"]:
			_banner_cut = true
	elif entry.get("replace_same_title", false):
		# Plain banners with this title (e.g. NetDungeon's own "Du bist am Boden") give way to it.
		for i in range(_banner_queue.size() - 1, -1, -1):
			if not _banner_queue[i].has("kind") and _banner_queue[i]["title"] == entry["title"]:
				_banner_queue.remove_at(i)
		if get_banner() != null and not _banner_entry.has("kind") and _banner_entry.get("title", "") == entry["title"]:
			_banner_cut = true
	elif not entry.has("kind"):
		# Plain banners: the same title right behind or on screen is not shown twice (e.g. the old
		# wave banner of DungeonManager after the arena's own; the other way round the arena's
		# wave banner cuts the plain one short, it is a priority banner).
		if not _banner_queue.is_empty() and _banner_queue.back()["title"] == entry["title"]:
			return
		if get_banner() != null and _banner_entry.get("title", "") == entry["title"]:
			return
	if entry.get("priority", false):
		_banner_queue.push_front(entry)
		if get_banner() != null and not _banner_hold:
			_banner_cut = true
	else:
		_banner_queue.append(entry)
	_pump_banners()


func _pump_banners() -> void:
	if _banner_queue.is_empty():
		return
	_drop_stale_banners()
	if not _banner_queue.is_empty() and _banner_slot_free():
		_display_banner(_banner_queue.pop_front())


## Banners of a room the players already left, or that waited too long, are no news any more.
func _drop_stale_banners() -> void:
	var room := _current_room()
	var now := Time.get_ticks_msec()
	for i in range(_banner_queue.size() - 1, -1, -1):
		var entry := _banner_queue[i]
		if entry.get("keep", false) or entry.has("intro"):
			continue
		var old_room := int(entry.get("room", room)) < room
		if old_room or now - int(entry.get("queued_ms", now)) > int(BANNER_STALE_TIME * 1000.0):
			_banner_queue.remove_at(i)


func _banner_slot_free() -> bool:
	if get_banner() == null or _banner_cut:
		return true
	var shown := Time.get_ticks_msec() - _banner_since_ms
	if _banner_hold:
		return shown >= int(INTRO_HOLD_MAX * 1000.0)
	if int(_banner_entry.get("room", 0)) < _current_room():
		# A banner of the room behind gives way to the news of this one at once.
		return true
	return shown >= int(BANNER_MIN_TIME * 1000.0)


static func _current_room() -> int:
	return maxi(1, RunManager.get_current_room())


func _display_banner(entry: Dictionary) -> void:
	for child in _banner_root.get_children():
		child.queue_free()
	var intro := entry.get("intro") as RoomIntro if is_instance_valid(entry.get("intro")) else null
	var strip := _wants_strip(entry, intro)
	var box := _build_banner_strip(entry) if strip else _build_banner_plaque(entry)
	_banner_root.add_child(box)
	_banner_box = box
	_banner_entry = entry
	_banner_since_ms = Time.get_ticks_msec()
	_banner_cut = false
	_banner_hold = intro != null and not intro.is_released()
	var top := _banner_top()
	box.position.y = top - UiKit.px(8)
	box.modulate.a = 0.0
	var slide := box.create_tween().set_ignore_time_scale(true)
	slide.set_parallel(true)
	slide.tween_property(box, "modulate:a", 1.0, 0.25)
	slide.tween_property(box, "position:y", top, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# R8: the stripe grows down and the symbol pops a moment later.
	var stripe := box.find_child("Stripe", true, false) as Control
	if stripe != null:
		stripe.scale.y = 0.0
		UiKit.ui_tween(stripe).tween_property(stripe, "scale:y", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var symbol := box.find_child("Icon", true, false) as Control
	if symbol != null:
		UiKit.pop_in(symbol, 0.12, 0.5, 0.3)
	if _banner_hold:
		return
	var default_time := GENRE_BANNER_TIME if entry.has("genre") else BANNER_TIME
	if strip:
		default_time = STRIP_TIME
	if intro != null:
		default_time = INTRO_BANNER_AFTER_RUNNING if intro.fight_was_running else INTRO_BANNER_AFTER
	_fade_banner_later(box, float(entry.get("time", default_time)))


func _fade_banner_later(box: Control, seconds: float) -> void:
	var tween := box.create_tween().set_ignore_time_scale(true)
	tween.tween_interval(seconds)
	tween.tween_property(box, "modulate:a", 0.0, 0.5)
	tween.tween_callback(box.queue_free)


## The intro banner on screen lets go: it stays a moment after "go", then fades.
func _release_banner_hold(intro: RoomIntro) -> void:
	if not _banner_hold or _banner_entry.get("intro") != intro:
		return
	_banner_hold = false
	var box := get_banner()
	if box == null:
		return
	_banner_since_ms = Time.get_ticks_msec() - int(BANNER_MIN_TIME * 1000.0)
	var after := INTRO_BANNER_AFTER_RUNNING if intro.fight_was_running else INTRO_BANNER_AFTER
	_fade_banner_later(box, after)
	# The next banner may come once this one is gone.
	_banner_since_ms += int(after * 1000.0)


## Banner top: below every bar of the top centre that is up (task bar, boss bar, the status line,
## the coop wait line; Hud.TOP_CENTER_GROUP) and below the touch buttons on a touch screen.
func _banner_top() -> float:
	var top := UiKit.px(GENRE_BANNER_TOP)
	if InputGlyphs.is_touch():
		top = maxf(top, UiKit.px(TOUCH_TOP_CLEAR))
	if not is_inside_tree():
		return top
	for node in get_tree().get_nodes_in_group(Hud.TOP_CENTER_GROUP):
		var bar := node as Control
		if bar == null or not bar.is_visible_in_tree():
			continue
		top = maxf(top, bar.get_global_rect().end.y + UiKit.px(TOP_BAND_GAP))
	return top


## Bottom of the top band (viewport px): below the bars and the banner on screen, plus a gap. The
## intro's 3-2-1 sits here.
func get_top_band_bottom() -> float:
	var top := _banner_top()
	var box := get_banner()
	if box != null:
		top += box.get_combined_minimum_size().y
	return top + UiKit.px(TOP_BAND_GAP)


## Enemies of the fight are on this screen (living, not hidden in their spawn source).
func is_fight_on_screen() -> bool:
	return OverlayDodge.enemies_on_screen(get_tree(), get_viewport().get_visible_rect()) > 0


## Strip or plaque: an entry may ask with "compact"; the intro banner is a strip when it came over a
## running fight; every other banner is a strip while enemies are on screen.
func _wants_strip(entry: Dictionary, intro: RoomIntro) -> bool:
	if entry.has("compact"):
		return bool(entry["compact"])
	if intro != null:
		return intro.fight_was_running
	return is_fight_on_screen()


## The banner plaque of every kind (07_ui.md): panel_dark, a stripe in the colour on the left,
## optional symbol, eyebrow, title and one line. Names: "Banner", "GenreBanner", "IntroBanner",
## "WaveBanner"; children "Title" and "Subtitle".
func _build_banner_plaque(entry: Dictionary) -> Control:
	var kind: StringName = entry.get("kind", &"genre" if entry.has("genre") else &"plain")
	var color: Color = entry.get("color", UiKit.COLOR_GOLD)
	var plaque := UiKit.panel(&"dark")
	plaque.name = {&"genre": "GenreBanner", &"intro": "IntroBanner", &"wave": "WaveBanner"}.get(kind, "Banner")
	var style := UiKit.padded_style(&"dark", 4, 8).duplicate() as StyleBoxTexture
	style.content_margin_left = UiKit.px(3)
	plaque.add_theme_stylebox_override("panel", style)
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(int(UiKit.px(6)))
	plaque.add_child(row)
	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.color = color
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.custom_minimum_size.x = UiKit.px(BANNER_STRIPE_WIDTH)
	row.add_child(stripe)
	var icon_texture: Texture2D = entry.get("icon")
	if icon_texture == null and entry.has("genre"):
		icon_texture = RoomGenre.get_icon(entry["genre"])
		entry["tint"] = RoomGenre.is_icon_tinted(entry["genre"])
	if icon_texture != null:
		var icon := UiKit.pixel_icon(icon_texture, INTRO_ICON_SIZE if kind == &"intro" else GENRE_ICON_SIZE)
		icon.name = "Icon"
		if entry.get("tint", false):
			icon.modulate = color
		row.add_child(icon)
	var text := UiKit.vbox(0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var eyebrow: String = entry.get("eyebrow", "")
	if not eyebrow.is_empty():
		text.add_child(UiKit.eyebrow(eyebrow, color if kind == &"intro" else UiKit.COLOR_MUTED))
	var title_color := UiKit.COLOR_GOLD if kind == &"intro" else color
	# 07_ui.md: title 14 px Pixelify for every banner (R8).
	var title := UiKit.text_label(entry["title"], UiKit.SIZE_TITLE_LARGE, title_color, true)
	title.name = "Title"
	text.add_child(title)
	var subtitle: String = entry.get("subtitle", "")
	if not subtitle.is_empty():
		# Long subtitles (the run start summary, rule lines) wrap at a fixed width.
		var sub := UiKit.text_label(subtitle, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		sub.name = "Subtitle"
		var wrap_width := INTRO_SUBTITLE_WIDTH if kind == &"intro" else BANNER_SUBTITLE_WIDTH
		var single_line := UiKit.get_font().get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.font_px(UiKit.SIZE_BODY)).x
		if single_line > UiKit.px(wrap_width):
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sub.custom_minimum_size.x = UiKit.px(wrap_width)
		text.add_child(sub)
	if entry.get("skip_hint", false):
		var hint := UiKit.hbox(int(UiKit.px(3)))
		hint.name = "SkipHint"
		hint.add_child(KeyCap.for_name(String(InputGlyphs.TOUCH_INTERACT), UiKit.ART_SCALE) if InputGlyphs.is_touch()
				else KeyCap.for_action(&"interact", UiKit.ART_SCALE))
		hint.add_child(UiKit.text_label(_t(&"INTRO_SKIP"), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED))
		text.add_child(hint)
	plaque.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	plaque.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Only the dark plate is see-through, not the text on it.
	plaque.self_modulate.a = PLAQUE_ALPHA
	return plaque


## The banner as one slim line (online test 16.10.2026, while enemies are on screen): thin stripe,
## small symbol, title and subtitle side by side on a see-through plate. Same names as the plaque
## ("Banner" … "WaveBanner" with "Stripe", "Icon", "Title", "Subtitle") plus the meta "strip".
func _build_banner_strip(entry: Dictionary) -> Control:
	var kind: StringName = entry.get("kind", &"genre" if entry.has("genre") else &"plain")
	var color: Color = entry.get("color", UiKit.COLOR_GOLD)
	var plate := UiKit.panel(&"dark")
	plate.name = {&"genre": "GenreBanner", &"intro": "IntroBanner", &"wave": "WaveBanner"}.get(kind, "Banner")
	plate.set_meta(&"strip", true)
	var style := UiKit.padded_style(&"dark", 2, 5).duplicate() as StyleBoxTexture
	style.content_margin_left = UiKit.px(2)
	plate.add_theme_stylebox_override("panel", style)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.self_modulate.a = STRIP_ALPHA
	var row := UiKit.hbox(int(UiKit.px(4)))
	plate.add_child(row)
	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.color = color
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.custom_minimum_size.x = UiKit.px(STRIP_STRIPE_WIDTH)
	row.add_child(stripe)
	var icon_texture: Texture2D = entry.get("icon")
	var tint: bool = entry.get("tint", false)
	if icon_texture == null and entry.has("genre"):
		icon_texture = RoomGenre.get_icon(entry["genre"])
		tint = RoomGenre.is_icon_tinted(entry["genre"])
	if icon_texture != null:
		var icon := UiKit.pixel_icon(icon_texture, STRIP_ICON_SIZE)
		icon.name = "Icon"
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if tint:
			icon.modulate = color
		row.add_child(icon)
	var title_color := UiKit.COLOR_GOLD if kind == &"intro" else color
	var title := UiKit.text_label(entry["title"], UiKit.SIZE_CARD_NAME, title_color, true)
	title.name = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var subtitle: String = entry.get("subtitle", "")
	if not subtitle.is_empty():
		var sub := UiKit.text_label(subtitle, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		sub.name = "Subtitle"
		sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var single_line := UiKit.get_font().get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.font_px(UiKit.SIZE_BODY)).x
		if single_line > UiKit.px(STRIP_SUBTITLE_WIDTH):
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sub.custom_minimum_size.x = UiKit.px(STRIP_SUBTITLE_WIDTH)
		row.add_child(sub)
	plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return plate


# --- Status line (online test 16.10.2026) ---

## Small status line at the top centre, below the task bar or the boss bar (and above the banners):
## one short line on a see-through plate for states such as "Warte auf Anna …" or "Beeil dich!".
## duration > 0: it fades out after that many real seconds; 0: it stays until clear_status_line()
## or the next text. Showing the same text again only renews its time (safe to call every frame).
## Look only and local: every machine shows its own line.
func show_status_line(text: String, duration := 0.0, color := UiKit.COLOR_GOLD) -> void:
	if text.is_empty():
		clear_status_line()
		return
	_status_until_ms = Time.get_ticks_msec() + int(duration * 1000.0) if duration > 0.0 else 0
	_status_label.add_theme_color_override("font_color", color)
	if text == _status_text and _status_panel.visible:
		if _status_tween != null and _status_tween.is_valid():
			# A fade-out that was running is called off.
			_status_tween.kill()
			_status_panel.modulate.a = 1.0
		return
	_status_text = text
	_status_label.text = text
	var single_line := UiKit.get_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.font_px(UiKit.SIZE_BODY)).x
	var wraps := single_line > UiKit.px(STATUS_LINE_WIDTH)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wraps else TextServer.AUTOWRAP_OFF
	_status_label.custom_minimum_size.x = UiKit.px(STATUS_LINE_WIDTH) if wraps else 0.0
	var appearing := not _status_panel.visible
	_status_panel.visible = true
	_place_status_line()
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
	if appearing:
		_status_panel.modulate.a = 0.0
		_status_tween = UiKit.ui_tween(_status_panel)
		_status_tween.tween_property(_status_panel, "modulate:a", 1.0, STATUS_LINE_FADE)
	else:
		_status_panel.modulate.a = 1.0


## Takes the status line away (fades out).
func clear_status_line() -> void:
	_status_until_ms = 0
	if _status_text.is_empty():
		return
	_status_text = ""
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
	_status_tween = UiKit.ui_tween(_status_panel)
	_status_tween.tween_property(_status_panel, "modulate:a", 0.0, STATUS_LINE_FADE)
	_status_tween.tween_callback(_hide_status_panel)


## The text of the status line ("" when none or fading out).
func get_status_line_text() -> String:
	return _status_text


## The plate of the status line (tools and tests; visible while a text shows or fades).
func get_status_line() -> Control:
	return _status_panel


func _hide_status_panel() -> void:
	if _status_text.is_empty():
		_status_panel.visible = false


func _update_status_line() -> void:
	if _status_text.is_empty():
		return
	if _status_until_ms > 0 and Time.get_ticks_msec() >= _status_until_ms:
		clear_status_line()
		return
	_place_status_line()


## Top centre below the task bar / boss bar (and the touch buttons on a touch screen).
func _place_status_line() -> void:
	var top := UiKit.px(TOP_BAR_Y)
	if InputGlyphs.is_touch():
		top = maxf(top, UiKit.px(TOUCH_TOP_CLEAR))
	for bar: Control in [_objective_bar, _boss_bar_root]:
		if bar != null and bar.is_visible_in_tree():
			top = maxf(top, bar.get_global_rect().end.y + UiKit.px(TOP_BAND_GAP))
	var own := _status_panel.get_combined_minimum_size()
	_status_panel.size = own
	var view := get_viewport().get_visible_rect().size
	_status_panel.position = Vector2(roundf((view.x - own.x) * 0.5), top)


func _build_status_line() -> void:
	_status_root = Control.new()
	_status_root.name = "StatusLineRoot"
	_status_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_root.theme = UiKit.get_theme()
	add_child(_status_root)
	_status_panel = UiKit.panel(&"dark")
	_status_panel.name = "StatusLine"
	_status_panel.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 2, 5))
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.self_modulate.a = STATUS_LINE_ALPHA
	_status_panel.visible = false
	# The HUD's room line and other top lines (coop) move below it.
	_status_panel.add_to_group(Hud.TOP_CENTER_GROUP)
	_status_root.add_child(_status_panel)
	_status_label = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
	_status_label.name = "Text"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_child(_status_label)


# --- Down and out (D-084, feedback 16.10.2026) ---

## The panel of the downed local player (null when standing), for tests and tools.
func get_downed_panel() -> DownedPanel:
	return _downed_panel if is_instance_valid(_downed_panel) and not _downed_panel.is_closing() else null


func get_downed_markers() -> DownedMarkers:
	return _downed_markers


## What last hurt player ("" = unknown), as the fall banner and the panel name it.
func get_last_hit_by(player: Player) -> String:
	return _last_hit_by.get(player.get_instance_id(), "") if player != null else ""


## Connects to every player in the group once (coop: remote ones arrive later).
func _watch_players() -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not is_instance_valid(player):
			continue
		var id := player.get_instance_id()
		if _watched_players.has(id) and is_instance_valid(_watched_players[id]):
			continue
		_watched_players[id] = player
		# Bound by id, not by the node: a deferred call may come after the player was freed.
		# Deferred: the hurtbox reports the fatal hit (its cause) only after the health died.
		player.died.connect(_on_watched_player_died.bind(id), CONNECT_DEFERRED)
		player.revived.connect(_on_watched_player_revived.bind(id))
		if player.hurtbox != null:
			player.hurtbox.hit_received.connect(_on_watched_player_hit.bind(id))
		if player.is_downed():
			_on_watched_player_died(id)


func _on_watched_player_hit(result: DamageResult, damage: DamageData, id: int) -> void:
	if result == null or result.health_damage <= 0.0:
		return
	var cause := RunRecap.describe_hit(damage)
	if not cause.is_empty():
		_last_hit_by[id] = cause


func _living_count() -> int:
	var count := 0
	for player in _watched():
		if player.is_alive():
			count += 1
	return count


## The watched player of an instance id (null when it was freed or left the tree).
func _watched_player(id: int) -> Player:
	var node: Variant = _watched_players.get(id)
	if not is_instance_valid(node):
		return null
	var player := node as Player
	return player if player != null and player.is_inside_tree() else null


## The watched players that still exist and are in the tree; freed ones drop out here (session end:
## the players go before this UI).
func _watched() -> Array[Player]:
	var result: Array[Player] = []
	for id: int in _watched_players.keys():
		var node: Variant = _watched_players[id]
		if not is_instance_valid(node):
			_watched_players.erase(id)
			_last_hit_by.erase(id)
			continue
		var player := node as Player
		if player != null and player.is_inside_tree():
			result.append(player)
	return result


## A player fell. Local and nobody left standing (single player, or the last of the group): short
## big banner with the cause (the run end follows). Local with mates standing: banner plus the
## DownedPanel. A mate: a strip with the name; the markers show where they lie.
func _on_watched_player_died(id: int) -> void:
	var player := _watched_player(id)
	if player == null or not is_inside_tree() or not player.is_downed():
		return
	var cause := get_last_hit_by(player)
	var cause_text := _t(&"DOWNED_CAUSE", [cause]) if not cause.is_empty() else ""
	var living := _living_count()
	if player.is_local:
		if living == 0:
			var title := _t(&"FALL_ALL_DOWN") if _watched().size() > 1 else _t(&"RUNEND_DEATH")
			_queue_banner({"kind": &"fall", "title": title, "subtitle": cause_text, "color": DOWNED_COLOR,
					"priority": true, "compact": false, "keep": true, "time": FALL_BANNER_TIME})
			return
		_queue_banner({"kind": &"fall", "title": Loc.t(&"NET_DOWNED_TITLE"), "subtitle": cause_text,
				"color": DOWNED_COLOR, "priority": true, "compact": false, "replace_same_title": true,
				"time": FALL_BANNER_TIME})
		_show_downed_panel(cause)
		return
	if living == 0:
		return
	var name_text := _player_name(player)
	var title := _t(&"MATE_DOWNED_TITLE", [name_text]) if not name_text.is_empty() else _t(&"MATE_DOWNED_NAMELESS")
	_queue_banner({"kind": &"fall", "title": title, "subtitle": _t(&"MATE_DOWNED_SUB", [DamageNumber.format_amount(CoopRules.REVIVE_TIME)]),
			"color": DOWNED_COLOR, "priority": true, "compact": true})


func _on_watched_player_revived(id: int) -> void:
	var player := _watched_player(id)
	if player == null or not is_inside_tree() or not player.is_local:
		return
	if _downed_panel != null and is_instance_valid(_downed_panel):
		_downed_panel.close()
	_downed_panel = null
	_queue_banner({"kind": &"fall", "title": _t(&"REVIVED_TITLE"), "color": UiKit.COLOR_SUCCESS, "compact": true, "priority": true})


func _show_downed_panel(cause: String) -> void:
	if _downed_panel != null and is_instance_valid(_downed_panel) and not _downed_panel.is_closing():
		_downed_panel.set_cause(cause)
		return
	_downed_panel = DownedPanel.new()
	_downed_root.add_child(_downed_panel)
	_downed_panel.set_cause(cause)


## Name tag of a player (NetPlayers puts one on every player of a group game; "" without one).
static func _player_name(player: Player) -> String:
	var tag := player.get_node_or_null(^"NameTag") as Label
	return tag.text if tag != null else ""


## Every frame: the panel's revive bar, the markers over downed mates (only while a local player
## stands; a downed local player sees the panel instead).
func _update_downed() -> void:
	var panel := get_downed_panel()
	var local_standing := false
	var players := _watched()
	for player in players:
		if player.is_local and player.is_alive():
			local_standing = true
		elif panel != null and player.is_local and player.is_downed():
			panel.set_revive_share(_revive_share(player))
	if panel != null and local_standing and _all_local_standing():
		panel.close()
		_downed_panel = null
	var targets: Array[Dictionary] = []
	if local_standing:
		for player in players:
			if player.is_local or not player.is_downed():
				continue
			var canvas := player.get_global_transform_with_canvas()
			targets.append({"point": canvas.origin, "share": _revive_share(player),
					"lift": DOWNED_MARKER_LIFT * maxf(0.01, canvas.get_scale().x)})
	_downed_markers.set_targets(targets)


func _all_local_standing() -> bool:
	for player in _watched():
		if player.is_local and player.is_downed():
			return false
	return true


func _revive_share(player: Player) -> float:
	if not revive_share_provider.is_valid():
		return 0.0
	return clampf(float(revive_share_provider.call(player)), 0.0, 1.0)


func _build_downed() -> void:
	_downed_markers = DownedMarkers.new()
	add_child(_downed_markers)
	_downed_root = Control.new()
	_downed_root.name = "DownedRoot"
	_downed_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_downed_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_root.theme = UiKit.get_theme()
	add_child(_downed_root)


# --- Overlay dodge (online test 16.10.2026) ---

## Banner, status line, teaching cards and the 3-2-1 fade while an enemy or a player is under them.
## Each overlay root has its own alpha; the overlays' own tweens use their own modulate.
func _update_dodge(delta: float) -> void:
	# The downed panel does not dodge: its player cannot fight, the panel is what matters then.
	var roots: Array[Control] = [_banner_root, _status_root, _hint_root, _countdown]
	var rects: Array[Rect2] = [
		_banner_box.get_global_rect() if get_banner() != null else Rect2(),
		_status_panel.get_global_rect() if _status_panel.visible else Rect2(),
		OverlayDodge.children_rect(_hint_root),
		_countdown.get_number_rect(),
	]
	var any := false
	for rect in rects:
		any = any or rect.size != Vector2.ZERO
	var bodies: Array[Rect2] = []
	if any and dodge_overlays:
		bodies = OverlayDodge.body_rects(get_tree())
	# Teaching cards step back a little while a fight is on screen.
	var card_rest := CARD_FIGHT_ALPHA if rects[2].size != Vector2.ZERO and is_fight_on_screen() else 1.0
	for i in roots.size():
		var root := roots[i]
		if root == null:
			continue
		var covered := OverlayDodge.is_covering(rects[i], bodies)
		root.modulate.a = OverlayDodge.step(root.modulate.a, covered, delta, card_rest if root == _hint_root else 1.0)


# --- Room genres (D-110) ---

## Hook for DungeonManager._announce_room: banner with name and symbol for rooms with gameplay of
## their own; the first time per save also the explanation card. Normal combat rooms stay unnamed.
## An arena starts its intro here (R3: door shuts, camera on the gates, "Überlebe N Wellen", 3-2-1,
## task bar). Returns the genre (RoomGenre.NONE = nothing shown). A room is announced once.
## A special room builds its content (pact altar or not, kind of trial) only in activate(), right
## after the announcement: it is named one call later, so the hook may sit before or after activate.
## Room modes (RoomObjective.MODES) are named one frame later too, and only when the mode did not
## bring its own RoomIntro / RoomObjective (R4).
func show_room_genre(room: RoomController) -> StringName:
	if room == null or not is_instance_valid(room):
		return RoomGenre.NONE
	_watch_arena(room)
	if room.room_type == RoomSequence.RoomType.SPECIAL and room.state == RoomController.State.PREPARED:
		_announce_room_genre.call_deferred(room)
		return RoomGenre.of_room(room)
	var genre := RoomGenre.of_room(room)
	if genre == RoomGenre.ARENA and not _announced_rooms.has(room.get_instance_id()):
		start_arena_intro(room)
		return genre
	if RoomObjective.has_mode(genre):
		_announce_room_genre.call_deferred(room)
		return genre
	return _announce_room_genre(room)


func _announce_room_genre(room: RoomController) -> StringName:
	if room == null or not is_instance_valid(room):
		return RoomGenre.NONE
	var genre := RoomGenre.of_room(room)
	if genre == RoomGenre.NONE or _announced_rooms.has(room.get_instance_id()):
		return genre
	_announced_rooms[room.get_instance_id()] = genre
	if RoomIntro.get_intro(room) != null or RoomObjective.of_room(room) != null:
		# The mode introduces itself (goal banner, card, task bar).
		return genre
	show_genre(genre, room)
	return genre


## Banner (and, first time per save, the explanation) of a genre. room fills in the room number and
## details such as the next biome; without it the current room number is used.
func show_genre(genre: StringName, room: RoomController = null) -> void:
	if not RoomGenre.has_genre(genre):
		return
	var index := room.room_index if room != null and is_instance_valid(room) else maxi(1, RunManager.get_current_room())
	_queue_banner({
		"genre": genre,
		"title": RoomGenre.get_title(genre),
		"subtitle": RoomGenre.get_subtitle(genre, room),
		"eyebrow": RoomGenre.get_eyebrow(genre, index),
		"color": RoomGenre.get_color(genre),
	})
	if RoomGenre.should_explain(genre):
		_queue_room_intro(genre)


## The arena of room (R3): goal in the task bar and the intro (RoomIntro: door, camera on the
## gates, banner "Überlebe N Wellen", 3-2-1). The fight waits for the intro when RoomController
## asks RoomIntro.after_intro; without that hook the intro only names the goal.
func start_arena_intro(room: RoomController) -> RoomIntro:
	if room == null or not is_instance_valid(room):
		return null
	_announced_rooms[room.get_instance_id()] = RoomGenre.ARENA
	var objective := ArenaObjective.attach_to(room)
	return RoomIntro.start(room, objective, arena_focus(room))


## Where the arena intro's camera looks: halfway from the room centre to the gate farthest from the
## players (global; the room centre when the gates are not built yet). Gates come from the room's
## SpawnSources (R2) or, before that is wired, from the old ArenaWaves (looked up by name, it goes
## away with R2).
func arena_focus(room: RoomController) -> Vector2:
	var center := room.get_arena().get_center()
	var spots: Array[Vector2] = []
	var sources := SpawnSources.of(room)
	if sources != null:
		for source in sources.get_sources():
			if is_instance_valid(source):
				spots.append(source.global_position)
	elif room.has_method(&"get_arena_waves"):
		var waves: Object = room.call(&"get_arena_waves")
		if waves != null and waves.has_method(&"get_fixed_gates"):
			for gate: Object in waves.call(&"get_fixed_gates"):
				spots.append(room.to_global(gate.call(&"get_floor_position")))
	if spots.is_empty():
		return center
	var players := _player_positions()
	var from: Vector2 = players[0] if not players.is_empty() else center
	var best := center
	var best_distance := -1.0
	for spot in spots:
		var distance := spot.distance_to(from)
		if distance > best_distance:
			best_distance = distance
			best = spot
	return center.lerp(best, 0.5)


## RoomController.arena_started: an arena whose entry was not announced is named now (show_room_genre
## does that on entry) and gets the task bar. There is no ambush any more (D-120, R8 cleanup): the
## flag of the signal is ignored.
func on_arena_started(room: RoomController, _ambush := false) -> void:
	if room == null or not is_instance_valid(room):
		return
	ArenaObjective.attach_to(room)
	var id := room.get_instance_id()
	if _announced_rooms.get(id, RoomGenre.NONE) == RoomGenre.ARENA:
		return
	_announced_rooms[id] = RoomGenre.ARENA
	show_genre(RoomGenre.ARENA, room)


## The explanation card on screen (null if none), for tests and tools.
func get_room_intro_card() -> RoomIntroCard:
	return _hint_card as RoomIntroCard if is_instance_valid(_hint_card) else null


func _watch_arena(room: RoomController) -> void:
	if not room.arena_started.is_connected(on_arena_started):
		room.arena_started.connect(on_arena_started)


## urgent: the card of a starting intro; an enemy card on screen steps back and comes after it.
func _queue_room_intro(genre: StringName, urgent := false) -> void:
	for entry in _hint_queue:
		if entry.get("genre", RoomGenre.NONE) == genre:
			return
	if urgent and _hint_card != null and is_instance_valid(_hint_card) and not _hint_card is RoomIntroCard:
		var waiting := _hint_entry
		_hint_card.queue_free()
		_hint_card = null
		_hint_queue.push_front(waiting)
	# Explanations of the room go before enemy cards that are still waiting.
	_hint_queue.push_front({"kind": &"room", "genre": genre})
	if _hint_card == null:
		_show_next_hint()


# --- Room intro and task bar (R3) ---

## Task bar of the current room goal (hidden when none), for tests and tools.
func get_objective_bar() -> ObjectiveBar:
	return _objective_bar


func get_countdown() -> IntroCountdown:
	return _countdown


## The intro DungeonUI follows right now (null if none).
func get_intro() -> RoomIntro:
	return _intro if is_instance_valid(_intro) and not _intro.is_queued_for_deletion() else null


func _bind_objective(objective: RoomObjective) -> void:
	if objective == null or not is_instance_valid(objective) or objective.is_finished():
		return
	if _objective_bar.objective == objective:
		return
	_objective_bar.bind(objective)
	_objective_bar.visible = true
	if objective is ArenaObjective:
		var arena := objective as ArenaObjective
		if not arena.wave_cleared.is_connected(_on_wave_cleared):
			arena.wave_cleared.connect(_on_wave_cleared.bind(arena))
	get_tree().call_group(Hud.GROUP, &"set_room_mode", objective.get_title())
	_update_top_bars()


func _on_objective_bar_done() -> void:
	# Also called while the world unloads: then there is no tree any more.
	if not is_inside_tree():
		return
	get_tree().call_group(Hud.GROUP, &"set_room_mode", "")
	_update_top_bars()


## The boss bar replaces the task bar (07_ui.md).
func _update_top_bars() -> void:
	_objective_bar.visible = _objective_bar.is_active() and not _boss_bar_root.visible


func _bind_intro(intro: RoomIntro) -> void:
	if intro == null or not is_instance_valid(intro) or intro.is_released():
		return
	_intro = intro
	intro.phase_changed.connect(_on_intro_phase.bind(intro))
	intro.countdown_tick.connect(_on_intro_tick.bind(intro))
	intro.finished.connect(_on_intro_finished.bind(intro))
	var objective := intro.objective
	if objective != null and is_instance_valid(objective):
		_bind_objective(objective)
		if intro.full and RoomGenre.should_explain(objective.genre):
			# First time: the card from the start, it fades with "go".
			_queue_room_intro(objective.genre, true)
	_on_intro_phase(intro.phase, intro)


func _on_intro_phase(phase: RoomIntro.Phase, intro: RoomIntro) -> void:
	var objective := intro.objective
	match phase:
		RoomIntro.Phase.DOOR:
			Sfx.play_ui(self, &"intro_door")
		RoomIntro.Phase.BANNER:
			if objective == null or not is_instance_valid(objective):
				return
			var index := int(intro.room.get(&"room_index")) if is_instance_valid(intro.room) and intro.room.get(&"room_index") != null else _current_room()
			_queue_banner({
				"kind": &"intro",
				"title": objective.get_goal(),
				"subtitle": objective.get_rule(),
				"eyebrow": _t(&"INTRO_EYEBROW", [index, objective.get_title()]),
				"color": objective.get_ui_color(),
				"icon": objective.get_icon(),
				"tint": true,
				"priority": true,
				"intro": intro,
				"skip_hint": intro.full and not intro.is_released(),
			})
			Sfx.play_ui(self, &"intro_banner_calm" if RoomObjective.is_calm_mode(objective.mode_id) else &"intro_banner_combat")


func _on_intro_tick(number: int, intro: RoomIntro) -> void:
	var color := intro.objective.get_ui_color() if is_instance_valid(intro.objective) else UiKit.COLOR_DANGER
	# In the top band right under the goal banner, not in the middle of the playfield.
	_countdown.top_px = get_top_band_bottom()
	_countdown.show_number(number, color)
	Sfx.play_ui(self, &"countdown_go" if number <= 0 else &"countdown_tick")
	if number <= 0:
		# The explanation card of this intro fades with "go".
		var card := get_room_intro_card()
		if card != null and is_instance_valid(intro.objective) and card.genre == intro.objective.genre:
			card.finish()


func _on_intro_finished(_skipped: bool, intro: RoomIntro) -> void:
	_release_banner_hold(intro)
	if _intro == intro:
		_intro = null


## Arena: the running wave is down (2 s pause with "Welle 2/3" and a gong, 07_ui.md).
func _on_wave_cleared(next_wave: int, total: int, arena: ArenaObjective) -> void:
	_queue_banner({
		"kind": &"wave",
		"title": _t(&"WAVE_BANNER_TITLE", [next_wave, total]),
		"subtitle": _t(&"WAVE_BANNER_SUB"),
		"color": arena.get_ui_color(),
		"icon": arena.get_icon(),
		"tint": true,
		"time": ArenaObjective.WAVE_PAUSE,
		"priority": true,
	})
	Sfx.play_ui(self, &"wave_gong")


# --- Teaching cards (enemy hints, room explanations) ---

## Queues the hint cards for everything new about this enemy (type, elite kind, champion).
func notice_enemy(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or enemy.data == null or enemy.is_dead():
		return
	# The first-encounter hint card waits for the boss intro, it would cover the dialog line.
	if enemy.is_in_intro():
		enemy.intro_ended.connect(notice_enemy, CONNECT_ONE_SHOT)
		return
	for entry in EnemyHints.get_entries(enemy.data, enemy.elite, enemy.is_champion()):
		_queue_hint_once(entry)


## Short card in the upper left (where the room cards sit): badge, name and one sentence.
## Auto-hides, never pauses the game.
func show_hint(title: String, text: String, badge := &"") -> void:
	_hint_queue.append({"kind": &"enemy", "title": title, "text": text, "badge": badge})
	if _hint_card == null:
		_show_next_hint()


func _queue_hint_once(entry: Dictionary) -> void:
	var id: StringName = entry["id"]
	if SaveManager.is_unlocked(id):
		return
	SaveManager.unlock_content(id)
	show_hint(entry["title"], entry["text"], entry["badge"])


func _on_node_added(node: Node) -> void:
	if node is Enemy:
		if auto_enemy_hints:
			# Deferred: elite, champion data and scaling are applied by then.
			notice_enemy.call_deferred(node)
	elif node is RoomObjective:
		# Deferred: the mode fills in its goal right after adding it.
		_bind_objective.call_deferred(node)
	elif node is RoomIntro:
		_bind_intro.call_deferred(node)
	else:
		WorldCaption.adopt(node)


## Next teaching card, one at a time. The controls card waits hidden while it shows.
func _show_next_hint() -> void:
	_hint_card = null
	_hint_entry = {}
	if _hint_queue.is_empty():
		_set_controls_hint_waiting(false)
		return
	var hint: Dictionary = _hint_queue.pop_front()
	if hint.get("kind", &"enemy") == &"room":
		var genre: StringName = hint["genre"]
		if not RoomGenre.should_explain(genre):
			_show_next_hint()
			return
		RoomGenre.mark_explained(genre)
		_set_controls_hint_waiting(true)
		var intro := RoomIntroCard.create(genre)
		intro.finished.connect(_show_next_hint)
		intro.set_meta(&"shown_ms", Time.get_ticks_msec())
		_hint_root.add_child(intro)
		_hint_card = intro
		_hint_entry = hint
		return
	_set_controls_hint_waiting(true)
	var badge: StringName = hint["badge"]
	var color: Color = EnemyBadges.COLORS.get(badge, UiKit.ACCENT_COLOR)
	var card := UiKit.panel(&"dark")
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pauses with the game, so a hint is not missed behind a dialog.
	card.process_mode = Node.PROCESS_MODE_PAUSABLE
	var row := UiKit.hbox(int(UiKit.px(5)))
	card.add_child(row)
	if badge != &"":
		row.add_child(UiKit.pixel_icon(EnemyBadges.get_texture(badge), 12.0))
	var text := UiKit.vbox(0)
	text.add_child(UiKit.text_label(hint["title"], UiKit.SIZE_CARD_NAME, color, true))
	text.add_child(GlyphText.wrapped(hint["text"], HINT_WIDTH, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	row.add_child(text)
	card.name = "EnemyHint"
	_hint_root.add_child(card)
	var own := card.get_combined_minimum_size()
	card.size = own
	card.position = Vector2(UiKit.px(HINT_EDGE_MARGIN), ControlsHint.card_top(card, own.y))
	card.modulate.a = 0.0
	_hint_card = card
	_hint_entry = hint
	card.set_meta(&"shown_ms", Time.get_ticks_msec())
	var tween := card.create_tween()
	card.set_meta(&"tween", tween)
	tween.tween_property(card, "modulate:a", 1.0, 0.25)
	tween.tween_interval(HINT_TIME)
	tween.tween_property(card, "modulate:a", 0.0, 0.4)
	tween.tween_callback(card.queue_free)
	tween.tween_callback(_show_next_hint)


## Next room: a teaching card that was readable for HINT_ROOM_CHANGE_MIN goes. The controls card is
## not one of them: it runs on through rooms 2-3 until its keys were used and ends by room 4 at the
## latest (ControlsHint, P1-4).
func _on_room_entered_cards(_room_index: int) -> void:
	var card := _hint_card as Control
	if card == null or not is_instance_valid(card) or card.is_queued_for_deletion():
		return
	if Time.get_ticks_msec() - int(card.get_meta(&"shown_ms", 0)) < int(HINT_ROOM_CHANGE_MIN * 1000.0):
		return
	if card is RoomIntroCard:
		(card as RoomIntroCard).finish()
		return
	var running := card.get_meta(&"tween", null) as Tween
	if running != null and running.is_valid():
		running.kill()
	var fade := card.create_tween()
	fade.tween_property(card, "modulate:a", 0.0, 0.3)
	fade.tween_callback(card.queue_free)
	fade.tween_callback(_show_next_hint)


## The controls card steps aside (hidden, its timer and key tracking frozen) while another teaching
## card shows, and comes back where it was afterwards.
func _set_controls_hint_waiting(waiting: bool) -> void:
	var controls := get_controls_hint()
	if controls == null:
		return
	controls.visible = not waiting
	controls.process_mode = Node.PROCESS_MODE_DISABLED if waiting else Node.PROCESS_MODE_PAUSABLE


# --- Boss bar ---

## Boss or champion bar (R8, compact; replaces the task bar): portrait, name (+ tier "II", "III"),
## badges and phase in one line, the HP bar in the boss colour with the phase-two mark under it,
## HP as a small number on the right. The phase change flashes the bar and shakes it once.
func show_boss_bar(enemy: Enemy) -> void:
	if _boss != null and is_instance_valid(_boss):
		_disconnect_boss(_boss)
	_boss = enemy
	var champion := enemy.is_champion()
	if champion:
		_boss_name.text = _t(&"BOSS_BAR_CHAMPION", [enemy.get_display_name()])
	else:
		_boss_name.text = BossRules.boss_title(enemy.get_display_name(), enemy.get_boss_tier())
	_boss_name.add_theme_color_override("font_color", UiKit.COLOR_GOLD)
	_boss_sub.text = _t(&"BOSS_BAR_ROOM", [maxi(1, RunManager.get_current_room()), _t(&"BOSS_BAR_KIND_CHAMPION" if champion else &"BOSS_BAR_KIND_BOSS")])
	_boss_color = _boss_color_for(enemy, champion)
	_set_boss_health(enemy.health.get_health(), enemy.health.get_max_health())
	_set_boss_phase(enemy.phase, champion)
	for child in _boss_badges.get_children():
		child.queue_free()
	for badge in enemy.get_ability_badges():
		_boss_badges.add_child(UiKit.pixel_icon(EnemyBadges.get_texture(badge), 8.0))
	var portrait := EnemyArt.get_portrait(enemy.data)
	_boss_portrait.texture = portrait
	_boss_portrait.visible = portrait != null
	enemy.health.health_changed.connect(_on_boss_health_changed)
	enemy.phase_changed.connect(_on_boss_phase_changed)
	enemy.died.connect(_on_boss_died)
	var appearing := not _boss_bar_root.visible
	_boss_bar_root.visible = true
	_update_top_bars()
	if appearing:
		UiKit.pop_in(_boss_bar_root, 0.0, 0.85, 0.3)


func hide_boss_bar() -> void:
	_boss_bar_root.visible = false
	if _boss != null and is_instance_valid(_boss):
		_disconnect_boss(_boss)
	_boss = null
	_update_top_bars()


func _boss_color_for(enemy: Enemy, champion: bool) -> Color:
	if champion:
		return CHAMPION_BAR_COLOR
	if enemy.data != null and BOSS_COLORS.has(enemy.data.id):
		return BOSS_COLORS[enemy.data.id]
	if enemy.data != null and enemy.data.placeholder_color != Color.WHITE:
		return enemy.data.placeholder_color
	return BOSS_BAR_COLOR


func _set_boss_phase(phase: int, champion: bool) -> void:
	var enraged := phase >= 2
	if champion:
		_boss_phase.text = _t(&"BOSS_BAR_ENRAGED") if enraged else ""
	else:
		_boss_phase.text = _t(&"BOSS_BAR_PHASE_TWO") if enraged else _t(&"BOSS_BAR_PHASE_ONE")
	_boss_phase.visible = not _boss_phase.text.is_empty()
	_boss_phase.add_theme_color_override("font_color", BOSS_BAR_ENRAGED_COLOR if enraged else UiKit.COLOR_MUTED)
	_boss_marker.visible = not enraged
	_boss_fill.bg_color = BOSS_BAR_ENRAGED_COLOR if enraged else _boss_color


func _set_boss_health(current: float, maximum: float) -> void:
	_boss_bar.max_value = maximum
	_boss_bar.value = current
	_boss_hp_text.text = DamageNumber.format_amount(ceilf(maxf(0.0, current) * 2.0) * 0.5)


func _on_boss_health_changed(current: float, maximum: float) -> void:
	_set_boss_health(current, maximum)


func _on_boss_phase_changed(enemy: Enemy, phase: int) -> void:
	var champion := enemy.is_champion()
	_set_boss_phase(phase, champion)
	_boss_bar_root.modulate = Color(2.0, 1.2, 1.2)
	_boss_bar_root.create_tween().tween_property(_boss_bar_root, "modulate", Color.WHITE, 0.5)
	UiKit.bump(_boss_bar_root, 1.08, 0.3)
	if champion:
		show_banner(_t(&"BOSS_BANNER_CHAMPION_ENRAGED", [enemy.get_display_name()]), _t(&"BOSS_BANNER_CHAMPION_ENRAGED_SUB"), BOSS_BAR_ENRAGED_COLOR)
		return
	# enrage_text is a translation key now (i18n round 3; Loc.t gives German text back unchanged).
	var subtitle := Loc.t(StringName(enemy.data.enrage_text)) if not enemy.data.enrage_text.is_empty() else _t(&"BOSS_BANNER_PHASE_TWO_SUB")
	show_banner(_t(&"BOSS_BANNER_PHASE_TWO", [enemy.get_display_name()]), subtitle, BOSS_BAR_ENRAGED_COLOR)
	_queue_hint_once(EnemyHints.phase_two_entry())


func _on_boss_died(_enemy: Enemy) -> void:
	hide_boss_bar()


func _disconnect_boss(enemy: Enemy) -> void:
	if enemy.health.health_changed.is_connected(_on_boss_health_changed):
		enemy.health.health_changed.disconnect(_on_boss_health_changed)
	if enemy.phase_changed.is_connected(_on_boss_phase_changed):
		enemy.phase_changed.disconnect(_on_boss_phase_changed)
	if enemy.died.is_connected(_on_boss_died):
		enemy.died.disconnect(_on_boss_died)


func _build_banner() -> void:
	_banner_root = Control.new()
	_banner_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_root.theme = UiKit.get_theme()
	add_child(_banner_root)


func _build_hint_root() -> void:
	_hint_root = Control.new()
	_hint_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_root.theme = UiKit.get_theme()
	add_child(_hint_root)


## Task bar at the top centre and the intro countdown (R3).
func _build_objective_bar() -> void:
	var root := Control.new()
	root.name = "ObjectiveRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.get_theme()
	add_child(root)
	_countdown = IntroCountdown.new()
	root.add_child(_countdown)
	_objective_bar = ObjectiveBar.new()
	_objective_bar.add_to_group(Hud.TOP_CENTER_GROUP)
	_objective_bar.visible = false
	root.add_child(_objective_bar)
	_objective_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_objective_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_objective_bar.position.y = UiKit.px(TOP_BAR_Y)
	_objective_bar.done.connect(_on_objective_bar_done)


func _build_boss_bar() -> void:
	var frame := UiKit.panel(&"dark")
	frame.name = "BossBar"
	frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 3, 6))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme = UiKit.get_theme()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.position.y = UiKit.px(TOP_BAR_Y)
	frame.add_to_group(Hud.TOP_CENTER_GROUP)
	add_child(frame)
	var row := UiKit.hbox(int(UiKit.px(5)))
	frame.add_child(row)
	_boss_portrait = UiKit.pixel_icon(null, BOSS_PORTRAIT_SIZE)
	_boss_portrait.name = "Portrait"
	_boss_portrait.custom_minimum_size = Vector2.ONE * UiKit.art_px(BOSS_PORTRAIT_SIZE, 48.0)
	_boss_portrait.visible = false
	row.add_child(_boss_portrait)
	var box := UiKit.vbox(int(UiKit.px(2)))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(box)
	var header := UiKit.hbox(int(UiKit.px(3)))
	box.add_child(header)
	_boss_name = UiKit.text_label("", UiKit.SIZE_CARD_NAME, UiKit.COLOR_GOLD, true)
	_boss_name.name = "Name"
	header.add_child(_boss_name)
	_boss_badges = UiKit.hbox(int(UiKit.px(1)))
	_boss_badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_boss_badges)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_boss_phase = UiKit.text_label("", UiKit.SIZE_EYEBROW + 1, UiKit.COLOR_MUTED)
	_boss_phase.name = "Phase"
	_boss_phase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_boss_phase)
	# Room and kind ("Raum 15 · Boss") are on the room line of the HUD already; kept for tools.
	_boss_sub = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_boss_sub.visible = false
	header.add_child(_boss_sub)
	var bar_row := UiKit.hbox(int(UiKit.px(4)))
	box.add_child(bar_row)
	_boss_bar = ProgressBar.new()
	_boss_bar.name = "Health"
	_boss_bar.show_percentage = false
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.custom_minimum_size = UiKit.pxv(BOSS_BAR_SIZE.x, BOSS_BAR_SIZE.y)
	_boss_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_boss_fill = UiKit.bar_style(BOSS_BAR_COLOR)
	_boss_bar.add_theme_stylebox_override("fill", _boss_fill)
	_boss_bar.add_theme_stylebox_override("background", UiKit.bar_style(UiKit.COLOR_SHADOW))
	bar_row.add_child(_boss_bar)
	# Marks the phase-two threshold until it is reached.
	_boss_marker = ColorRect.new()
	_boss_marker.color = Color(UiKit.COLOR_TEXT, 0.85)
	_boss_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var marker_width := maxf(2.0, UiKit.px(1))
	_boss_marker.position = Vector2(UiKit.px(BOSS_BAR_SIZE.x) * BossRules.PHASE_TWO_THRESHOLD - marker_width * 0.5, -UiKit.px(1))
	_boss_marker.size = Vector2(marker_width, UiKit.px(BOSS_BAR_SIZE.y + 2))
	_boss_bar.add_child(_boss_marker)
	_boss_hp_text = UiKit.text_label("", UiKit.SIZE_EYEBROW + 1, UiKit.COLOR_TEXT_SOFT, true)
	_boss_hp_text.name = "HealthText"
	_boss_hp_text.custom_minimum_size.x = UiKit.px(16)
	_boss_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_row.add_child(_boss_hp_text)
	_boss_bar_root = frame
	frame.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"upgrade_overview"):
		return
	get_viewport().set_input_as_handled()
	if _overview != null:
		UiSound.back(self)
		_overview.finish()
	elif not GameManager.is_game_paused():
		show_upgrade_overview()


# --- Shared pieces of the menu kit ---

## No line break between a number and its unit sign ("80 %", "+2 HP" stays "80" / "% des …" otherwise).
static func keep_together(text: String) -> String:
	var regex := RegEx.create_from_string("(\\d) (%|HP|px)")
	return regex.sub(text, "$1\u00a0$2", true)


## Key cap text of number keys 1..count: "1", "1–3".
static func number_range(count: int) -> String:
	return "1" if count <= 1 else "1–%d" % mini(count, NUMBER_KEYS.size())


static func _t(key: StringName, args: Array = []) -> String:
	return DungeonTexts.t(key, args)


## Fixed-size slot so the focused card can rise by CARD_LIFT (into the gap above) without moving its
## neighbours.
func _lift_holder(card: UiCard) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = card.custom_minimum_size
	holder.add_child(card)
	card.position = Vector2.ZERO
	card.set_meta(&"lift_holder", true)
	# The card may grow with long texts: the slot follows.
	card.minimum_size_changed.connect(func() -> void:
		if is_instance_valid(card) and is_instance_valid(holder):
			holder.custom_minimum_size = card.get_combined_minimum_size())
	return holder


func _focus_card(cards: Array[UiCard], target: UiCard) -> void:
	for card in cards:
		if not is_instance_valid(card):
			continue
		card.focused = card == target
		if card.has_meta(&"lift_holder"):
			card.position.y = -UiKit.px(CARD_LIFT) if card.focused else 0.0


## Enter on a card row: the focused card.
func _activate_focused(cards: Array[UiCard]) -> void:
	for card in cards:
		if is_instance_valid(card) and card.focused:
			card.activate()
			return


## ←/→ (and ↑/↓) move the focus through a card row; returns true when handled (Modal.input_handler).
## Gamepad: D-pad and left stick the same way (MenuInput debounces the stick), A picks (Modal).
func _arrow_focus(event: InputEvent, cards: Array[UiCard]) -> bool:
	var direction := MenuInput.direction(event, false)
	var step := 0
	if direction == Vector2i.LEFT or direction == Vector2i.UP:
		step = -1
	elif direction == Vector2i.RIGHT or direction == Vector2i.DOWN:
		step = 1
	if step == 0 or cards.is_empty():
		return false
	var current := -1
	for i in cards.size():
		if is_instance_valid(cards[i]) and cards[i].focused:
			current = i
	var next := 0 if current < 0 and step > 0 else posmod(current + step, cards.size())
	if current < 0 and step < 0:
		next = cards.size() - 1
	UiSound.hover(self)
	_focus_card(cards, cards[next])
	return true


## D-pad / stick / arrows through a card grid of columns (shop): ←/→ one card, ↑/↓ one row; the
## first step focuses the first card. Returns true when handled (Modal.input_handler).
func _grid_focus(event: InputEvent, cards: Array[UiCard], columns: int) -> bool:
	var direction := MenuInput.direction(event, false)
	if direction == Vector2i.ZERO or cards.is_empty():
		return false
	var current := -1
	for i in cards.size():
		if is_instance_valid(cards[i]) and cards[i].focused:
			current = i
	var next := 0
	if current >= 0:
		if direction.x != 0:
			next = posmod(current + direction.x, cards.size())
		else:
			next = current + direction.y * columns
			if next < 0 or next >= cards.size():
				next = current
	if next != current:
		UiSound.hover(self)
	_focus_card(cards, cards[next])
	return true


## Text-only button (hint style), e.g. "Wählen" under an upgrade card.
func _link_button(text: String, on_pressed: Callable) -> Button:
	var link := UiKit.button(text, on_pressed)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		link.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	link.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_KEY_HINT))
	link.add_theme_color_override("font_color", UiKit.COLOR_MUTED)
	link.add_theme_color_override("font_hover_color", UiKit.COLOR_GOLD)
	link.add_theme_color_override("font_pressed_color", UiKit.COLOR_GOLD)
	return link


## Key cap + caption row at the bottom of a card ("[1] Wählen").
func _key_row(key: String, action: Control) -> HBoxContainer:
	var row := UiKit.hbox(int(UiKit.px(3)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiChip.key(key))
	row.add_child(action)
	return row


func _filler() -> Control:
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return filler


# --- Upgrade choice (screen 02) ---

## Lets the player pick exactly one upgrade. Returns null only if offer is empty.
## Click a card (or its "Wählen") or press 1–3 to pick it at once; ←/→ move the focus, Enter
## picks the focused card.
## stack_gain: stacks the pick will gain (pact altar: more than one); the cards show the result.
## R8: compact cards in the category colour, dealt in one after another; a pick leaves a burst.
## time_limit > 0 (group games, CoopRules.UPGRADE_TIMEOUT): the first card is taken when the time
## is up; the clock starts when the dialog appears, not while it waits in the dialog queue.
## Only upgrades of this offer are accepted as a result (a pick meant for another dialog is ignored).
func choose_upgrade(offer: Array[UpgradeData], title: String, stack_gain := 1, time_limit := 0.0) -> UpgradeData:
	if offer.is_empty():
		return null
	var subtitle := _t(&"UPGRADE_SUBTITLE") if stack_gain <= 1 else _t(&"UPGRADE_SUBTITLE_STACKS", [stack_gain])
	var accent := UiKit.COLOR_MAGIC if stack_gain > 1 else UiKit.COLOR_GOLD
	var modal := UiDialog.create_menu(GameManager.PAUSE_UPGRADE_CHOICE, UiDialog.WIDTH_WIDE, title, subtitle, _t(&"UPGRADE_EYEBROW"), accent)
	modal.cancel_allowed = false
	modal.result_filter = func(result: Variant) -> bool: return result is UpgradeData and offer.has(result)
	if time_limit > 0.0:
		modal.auto_finish_after = time_limit
		modal.auto_finish_result = offer[0]
	var row := UiKit.hbox(int(UiKit.px(CARD_GAP)))
	row.name = "Cards"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	modal.content.add_child(row)
	var cards: Array[UiCard] = []
	for i in offer.size():
		var upgrade := offer[i]
		var card := _upgrade_card(upgrade, i, modal.finish.bind(upgrade), stack_gain)
		var holder := _lift_holder(card)
		row.add_child(holder)
		cards.append(card)
		card.pressed.connect(modal.finish.bind(upgrade))
		card.focus_requested.connect(_focus_card.bind(cards, card))
		if i < NUMBER_KEYS.size():
			modal.hotkeys[NUMBER_KEYS[i]] = card.activate
	modal.deal(cards)
	modal.accept_action = _activate_focused.bind(cards)
	modal.input_handler = _arrow_focus.bind(cards)
	# Gamepad: the first card starts focused, so A picks it (Modal ignores A in its first moments).
	if InputGlyphs.is_gamepad() and not cards.is_empty():
		_focus_card(cards, cards[0])
	var keys: Array = [
		[number_range(offer.size()), _t(&"MENU_HINT_PICK")],
		[_t(&"MENU_KEY_ARROWS"), _t(&"MENU_HINT_MOVE")],
		[_t(&"MENU_KEY_ENTER"), _t(&"MENU_HINT_CONFIRM")],
	]
	# P1-4: the first upgrade choice of a save names the overview key (Tab; gamepad: Back).
	var overview_tip := ControlsHint.take_overview_key_hint()
	if not overview_tip.is_empty():
		keys.append(overview_tip)
	modal.set_key_hints(keys)
	# Hook (P1-4, ui/hints): dialog_shown carries this modal; the meta tells it is the upgrade choice.
	modal.set_meta(DIALOG_KIND, DIALOG_UPGRADE_CHOICE)
	return await open_dialog(modal)


## One upgrade card (R8, chosen from two variants by screenshot): category band along the top
## edge, the 32 px symbol on a tile in the category colour next to the category and the name, the
## short effect below, then the stack line (pips for limited upgrades) and "[1] Wählen". The
## "Wählen" button carries the pick (tools press it, balance_sim reads the upgrade from its bound
## arguments).
func _upgrade_card(upgrade: UpgradeData, index: int, on_pick: Callable, stack_gain := 1) -> UiCard:
	var color := UiKit.category_color(upgrade.category)
	var card := UiCard.new()
	card.name = "Upgrade%d" % (index + 1)
	card.accent = color
	card.pick_sound = PICK_SOUND
	card.padding = CARD_PADDING
	card.custom_minimum_size = UiKit.pxv(CARD_SIZE.x, CARD_SIZE.y)
	var box := UiKit.vbox(int(UiKit.px(3)))
	card.add_child(box)
	var head := UiKit.hbox(int(UiKit.px(4)))
	box.add_child(head)
	var tile := _symbol_tile(upgrade.icon, color)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(tile)
	card.symbol = tile.get_child(0) as Control
	var names := UiKit.vbox(0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(UiKit.eyebrow(UiKit.category_name(upgrade.category), color))
	var name_label := UiKit.text_label(DataTexts.upgrade_name(upgrade), UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	name_label.name = "Name"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = UiKit.px(CARD_NAME_WIDTH)
	names.add_child(name_label)
	var description := UiKit.wrapped_text(keep_together(DataTexts.upgrade_description(upgrade)), CARD_SIZE.x - CARD_PADDING.y * 2.0)
	description.name = "Description"
	box.add_child(description)
	box.add_child(_filler())
	var bottom := UiKit.hbox(int(UiKit.px(3)))
	box.add_child(bottom)
	var stacks := _stack_line(upgrade, stack_gain, color)
	stacks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(stacks)
	bottom.add_child(_key_row(str(index + 1), _link_button(_t(&"MENU_CHOOSE"), on_pick)))
	return card


## The card symbol on a dark tile framed in the category colour (32 px symbol, 07_ui.md).
func _symbol_tile(texture: Texture2D, color: Color, spec_size := 32.0) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.name = "SymbolTile"
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.82), 0.95)
	style.border_color = color.darkened(0.25)
	style.set_border_width_all(UiKit.ART_SCALE)
	style.anti_aliasing = false
	var inset := UiKit.px(2)
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	tile.add_theme_stylebox_override("panel", style)
	var picture := UiKit.pixel_icon(texture, spec_size)
	picture.name = "Symbol"
	tile.add_child(picture)
	return tile


## Stack line of a card: pips for limited upgrades (owned muted, gained in the category colour,
## free as outlines), else "Stufe 1 → 2 · unbegrenzt".
func _stack_line(upgrade: UpgradeData, stack_gain: int, color: Color) -> HBoxContainer:
	var row := UiKit.hbox(int(UiKit.px(1)))
	row.name = "Stacks"
	var stacks := context.upgrade_manager.get_stacks(upgrade.id) if context != null else 0
	if not upgrade.is_limited():
		var text := UiKit.text_label(_t(&"UPGRADE_STACKS_UNLIMITED", [stacks, stacks + stack_gain]), UiKit.SIZE_EYEBROW + 1, UiKit.COLOR_MUTED)
		text.name = "StackText"
		row.add_child(text)
		return row
	var after := mini(stacks + stack_gain, upgrade.max_stacks)
	for i in upgrade.max_stacks:
		var pip := Panel.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.custom_minimum_size = Vector2.ONE * UiKit.px(STACK_PIP_SIZE)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := StyleBoxFlat.new()
		style.anti_aliasing = false
		style.set_border_width_all(UiKit.ART_SCALE)
		if i < stacks:
			style.bg_color = UiKit.COLOR_MUTED
			style.border_color = UiKit.COLOR_SHADOW
		elif i < after:
			style.bg_color = color
			style.border_color = color.lightened(0.4)
		else:
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = UiKit.COLOR_EMPTY_SLOT
		pip.add_theme_stylebox_override("panel", style)
		row.add_child(pip)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size.x = UiKit.px(2)
	row.add_child(gap)
	var label := UiKit.text_label(_t(&"UPGRADE_STACKS_LIMITED", [stacks, upgrade.max_stacks, after, upgrade.max_stacks]), UiKit.SIZE_EYEBROW + 1, UiKit.COLOR_SUCCESS)
	label.name = "StackText"
	row.add_child(label)
	return row


# --- Shop (screen 04) ---

## The merchant's offers in a 3-column grid. 1–6 or a click buys; offers that cannot be bought keep
## their look and show why (badge); clicking them plays the error sound. Esc closes.
func open_shop(offers: Array[ShopOffer], player: Player) -> void:
	var modal := UiDialog.create_menu(GameManager.PAUSE_SHOP, UiDialog.WIDTH_WIDE, _t(&"SHOP_TITLE"), "", _t(&"SHOP_EYEBROW"),
			UiKit.COLOR_GOLD, UiKit.COLOR_GOLD, RoomGenre.get_icon(RoomGenre.SHOP), true)
	var gold_badge := UiKit.panel(&"dark")
	gold_badge.name = "GoldBadge"
	gold_badge.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 2, 5))
	var gold_row := UiKit.icon_value(UiKit.GOLD_ICON, "", UiKit.COLOR_GOLD, UiKit.SIZE_VALUE, 12.0)
	var gold_label := gold_row.get_child(1) as Label
	gold_badge.add_child(gold_row)
	gold_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiDialog.add_header_badge(modal, gold_badge)
	var grid := GridContainer.new()
	grid.name = "Offers"
	grid.columns = SHOP_COLUMNS
	grid.add_theme_constant_override("h_separation", int(UiKit.px(SHOP_GAP)))
	grid.add_theme_constant_override("v_separation", int(UiKit.px(SHOP_GAP)))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	modal.content.add_child(grid)
	var close := UiDialog.option_button(_t(&"MENU_CLOSE"), "", _t(&"MENU_KEY_ESC"), modal.finish)
	modal.set_key_hints([[number_range(offers.size()), _t(&"MENU_HINT_BUY")]], true, close)
	var cards: Array[UiCard] = []
	var refresh := func() -> void:
		gold_label.text = str(RunManager.get_run_gold())
		# The gamepad focus stays on the same offer after a purchase rebuilt the cards.
		var focused := -1
		for i in cards.size():
			if is_instance_valid(cards[i]) and cards[i].focused:
				focused = i
		for child in grid.get_children():
			# Out of the grid at once: the new cards keep their names ("Offer1"..).
			grid.remove_child(child)
			child.queue_free()
		cards.clear()
		for i in offers.size():
			var card := _shop_card(offers[i], i, player, modal)
			grid.add_child(card)
			cards.append(card)
		var cells := ceili(float(maxi(offers.size(), 1)) / SHOP_COLUMNS) * SHOP_COLUMNS
		for i in range(offers.size(), cells):
			var empty := DashedBox.new()
			empty.caption = _t(&"SHOP_EMPTY_SLOT", [i + 1])
			empty.custom_minimum_size = UiKit.pxv(SHOP_CARD_SIZE.x, SHOP_CARD_SIZE.y)
			grid.add_child(empty)
		if focused >= 0 and focused < cards.size():
			_focus_card(cards, cards[focused])
	# Gamepad: D-pad / stick move through the grid, A buys the focused offer, B closes.
	modal.input_handler = func(event: InputEvent) -> bool: return _grid_focus(event, cards, SHOP_COLUMNS)
	modal.accept_action = _activate_focused.bind(cards)
	for i in mini(offers.size(), NUMBER_KEYS.size()):
		modal.hotkeys[NUMBER_KEYS[i]] = func() -> void:
			if i < cards.size() and is_instance_valid(cards[i]):
				cards[i].activate()
	modal.set_meta(&"refresh", refresh)
	refresh.call()
	if InputGlyphs.is_gamepad() and not cards.is_empty():
		_focus_card(cards, cards[0])
	modal.deal(cards)
	await open_dialog(modal)


## State of a shop offer for this player: &"sold", &"unavailable" (limit, HP full, owned),
## &"too_expensive", &"replace" (weapon, both slots taken) or &"buy".
func get_offer_state(offer: ShopOffer, player: Player) -> StringName:
	if offer.sold:
		return &"sold"
	var slot := _preview_slot(offer, player)
	if context != null and not context.economy.can_deliver(offer, player, context.upgrade_manager, slot):
		return &"unavailable"
	if RunManager.get_run_gold() < offer.price:
		return &"too_expensive"
	if offer.kind == ShopOffer.Kind.WEAPON and player.weapon_controller.find_free_slot() < 0:
		return &"replace"
	return &"buy"


func _shop_card(offer: ShopOffer, index: int, player: Player, modal: Modal) -> UiCard:
	var state := get_offer_state(offer, player)
	var eyebrow := _shop_eyebrow(offer)
	var color: Color = eyebrow[1]
	var card := UiCard.new()
	card.name = "Offer%d" % (index + 1)
	card.set_meta(&"offer_state", state)
	card.accent = color if state != &"sold" else UiKit.COLOR_DISABLED
	card.pick_sound = &"coin"
	card.padding = SHOP_CARD_PADDING
	card.custom_minimum_size = UiKit.pxv(SHOP_CARD_SIZE.x, SHOP_CARD_SIZE.y)
	var row := UiKit.hbox(int(UiKit.px(4)))
	card.add_child(row)
	var tile := _symbol_tile(offer.get_icon(), color, SHOP_ICON_SIZE)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var offer_icon := tile.get_child(0) as Control
	card.symbol = offer_icon
	if offer.kind == ShopOffer.Kind.WEAPON:
		offer_icon.modulate = offer.weapon.tint
	if state == &"sold":
		offer_icon.modulate = Color(0.42, 0.4, 0.5)
	row.add_child(_with_key(tile, str(index + 1) if index < NUMBER_KEYS.size() else ""))
	var text := UiKit.vbox(int(UiKit.px(1)))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var top := UiKit.hbox(int(UiKit.px(2)))
	text.add_child(top)
	var title_color := UiKit.COLOR_MUTED if state == &"sold" else UiKit.COLOR_TEXT
	var title := _fitted_label(offer.get_title(), SHOP_TEXT_WIDTH - SHOP_PRICE_WIDTH, UiKit.SIZE_CARD_NAME, title_color)
	title.name = "Name"
	title.tooltip_text = eyebrow[0]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	if state != &"sold":
		top.add_child(_shop_price(offer, state))
	var footer := UiKit.hbox(int(UiKit.px(3)))
	footer.name = "State"
	text.add_child(footer)
	var status := _shop_state(offer, state, player)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)
	card.disabled = state in [&"sold", &"unavailable", &"too_expensive"]
	card.pressed.connect(_on_buy_pressed.bind(offer, player, modal))
	card.focus_requested.connect(func() -> void: card.focused = true)
	card.mouse_exited.connect(func() -> void: card.focused = false)
	return card


## Price: gold, red with a lock when there is too little gold, muted when the offer cannot be bought
## anyway.
func _shop_price(offer: ShopOffer, state: StringName) -> Control:
	var price_color := UiKit.COLOR_GOLD
	match state:
		&"too_expensive":
			price_color = UiKit.COLOR_DANGER
		&"unavailable":
			price_color = UiKit.COLOR_DISABLED
	var holder := UiKit.hbox(int(UiKit.px(1)))
	holder.name = "PriceRow"
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if state == &"too_expensive":
		holder.tooltip_text = _t(&"STATE_TOO_LITTLE_GOLD")
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		var lock := UiKit.pixel_icon(UiKit.LOCK_ICON, UiChip.BADGE_ICON_SIZE)
		lock.name = "Lock"
		lock.modulate = UiKit.COLOR_DANGER_SOFT
		holder.add_child(lock)
	var price := UiKit.icon_value(UiKit.GOLD_ICON, str(offer.price), price_color, UiKit.SIZE_KEY_HINT, 8.0)
	price.name = "Price"
	price.alignment = BoxContainer.ALIGNMENT_END
	holder.add_child(price)
	return holder


## The line under the name: the effect, or a badge for every state that blocks the purchase (UX2:
## sold, at the limit, HP full); too little gold keeps the effect and shows a badge-less red price
## with a lock (R8: no wall of red badges).
func _shop_state(offer: ShopOffer, state: StringName, player: Player) -> Control:
	match state:
		&"sold":
			return _shrunk(UiChip.badge(_t(&"STATE_SOLD"), UiKit.COLOR_MUTED))
		&"unavailable":
			return _shrunk(UiChip.badge(_unavailable_text(offer), UiKit.COLOR_SHIELD))
	var description := offer.get_description()
	if offer.kind == ShopOffer.Kind.WEAPON:
		description = DataTexts.weapon_stats_text(player.weapon_controller, offer.weapon)
	var color := UiKit.COLOR_TEXT_SOFT
	if state == &"replace":
		description = _t(&"STATE_REPLACE_SLOT") + " · " + description
	var label := UiKit.wrapped_text(keep_together(description), SHOP_TEXT_WIDTH, UiKit.SIZE_BODY, color)
	label.name = "Effect"
	label.max_lines_visible = 2
	return label


## The symbol tile with its number key on the lower left corner (shop cards: saves a row).
func _with_key(tile: Control, key: String) -> Control:
	if key.is_empty():
		return tile
	var holder := Control.new()
	holder.name = "TileWithKey"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	holder.add_child(tile)
	var chip := UiChip.key(key)
	holder.add_child(chip)
	var place := func() -> void:
		if not is_instance_valid(tile) or not is_instance_valid(chip):
			return
		tile.size = tile.get_combined_minimum_size()
		holder.custom_minimum_size = tile.size + Vector2(0, UiKit.px(3))
		chip.size = chip.get_combined_minimum_size()
		chip.position = Vector2(-UiKit.px(2), tile.size.y - chip.size.y + UiKit.px(3))
	tile.minimum_size_changed.connect(place)
	chip.minimum_size_changed.connect(place)
	holder.ready.connect(place)
	place.call()
	return holder


func _shrunk(control: Control) -> Control:
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return control


## Bold label that steps down in font size until the text fits on one line (long names such as
## "Schildverstärkung" in a shop card) and only wraps if it still does not fit.
func _fitted_label(text: String, width: float, size: int, color: Color) -> Label:
	var font := UiKit.bold_font()
	var fitted := size
	while fitted > UiKit.SIZE_BODY and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.font_px(fitted)).x > UiKit.px(width):
		fitted -= 1
	var label := UiKit.text_label(text, fitted, color, true)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = UiKit.px(width)
	return label


## Short reason why an offer cannot be delivered right now.
func _unavailable_text(offer: ShopOffer) -> String:
	match offer.kind:
		ShopOffer.Kind.HEAL:
			return _t(&"STATE_HP_FULL")
		ShopOffer.Kind.UPGRADE:
			return _t(&"STATE_AT_LIMIT")
		ShopOffer.Kind.WEAPON:
			return _t(&"STATE_OWNED")
		ShopOffer.Kind.SHIELD:
			return _t(&"STATE_SHIELD_FULL")
	return _t(&"STATE_NOT_POSSIBLE")


## Eyebrow text and colour for a shop offer: "Upgrade · Attribut", "Waffe", "Heilung", "Schild".
func _shop_eyebrow(offer: ShopOffer) -> Array:
	match offer.kind:
		ShopOffer.Kind.UPGRADE:
			return [_t(&"SHOP_KIND_UPGRADE", [UiKit.category_name(offer.upgrade.category)]), UiKit.category_color(offer.upgrade.category)]
		ShopOffer.Kind.WEAPON:
			return [_t(&"SHOP_KIND_WEAPON"), UiKit.COLOR_WEAPON]
		ShopOffer.Kind.HEAL:
			return [_t(&"SHOP_KIND_HEAL"), UiKit.COLOR_DANGER]
	return [_t(&"SHOP_KIND_SHIELD"), UiKit.COLOR_SHIELD]


func _preview_slot(offer: ShopOffer, player: Player) -> int:
	if offer.kind != ShopOffer.Kind.WEAPON:
		return -1
	var free_slot := player.weapon_controller.find_free_slot()
	return free_slot if free_slot >= 0 else 0


func _on_buy_pressed(offer: ShopOffer, player: Player, modal: Modal) -> void:
	var slot := -1
	if offer.kind == ShopOffer.Kind.WEAPON:
		slot = player.weapon_controller.find_free_slot()
		if slot < 0:
			# Choose the slot first; cancelling leaves gold and weapons untouched (atomic purchase).
			slot = await choose_weapon_slot(offer.weapon, player, true)
			if slot < 0:
				return
	context.economy.try_purchase(offer, player, context.upgrade_manager, slot)
	if is_instance_valid(modal):
		(modal.get_meta(&"refresh") as Callable).call()


# --- Weapon slot choice (screen 03) ---

## Returns the slot to replace, or -1 when cancelled. Shows effective stats of all three weapons.
## R8: the offer on a gold card, the two slots as cards in the weapon colour with their symbol tiles.
## over_shop: asked from inside the open shop, so it goes on top instead of into the dialog queue.
func choose_weapon_slot(new_weapon: WeaponData, player: Player, over_shop := false) -> int:
	var controller := player.weapon_controller
	var modal := UiDialog.create_menu(GameManager.PAUSE_WEAPON_CHOICE, WEAPON_PANEL_WIDTH, _t(&"WEAPON_TITLE"), _t(&"WEAPON_SUBTITLE"), _t(&"WEAPON_EYEBROW"),
			UiKit.COLOR_WEAPON, UiKit.COLOR_GOLD, RoomGenre.get_icon(RoomGenre.WEAPON), true)
	modal.cancel_result = -1
	var columns := UiKit.hbox(int(UiKit.px(WEAPON_COLUMN_GAP)))
	modal.content.add_child(columns)
	var offer := UiKit.panel(&"gold")
	offer.name = "Offer"
	offer.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold", 7, 6))
	offer.add_child(_weapon_column(new_weapon, controller, _t(&"WEAPON_OFFER"), UiKit.COLOR_GOLD, ""))
	offer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(offer)
	var cards: Array[UiCard] = []
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var weapon := controller.get_weapon(slot)
		var role := _t(&"WEAPON_SLOT_ACTIVE" if slot == controller.get_active_slot() else &"WEAPON_SLOT", [slot + 1])
		var card := UiCard.new()
		card.name = "Slot%d" % (slot + 1)
		card.padding = Vector2(7, 6)
		card.accent = UiKit.COLOR_WEAPON
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column := _weapon_column(weapon, controller, role, UiKit.COLOR_SHIELD, str(slot + 1))
		card.add_child(column)
		card.symbol = column.find_child("Symbol", true, false) as Control
		card.pressed.connect(modal.finish.bind(slot))
		card.focus_requested.connect(_focus_card.bind(cards, card))
		card.mouse_exited.connect(func() -> void: card.focused = false)
		cards.append(card)
		columns.add_child(card)
		modal.hotkeys[NUMBER_KEYS[slot]] = card.activate
	var dealt: Array = [offer]
	dealt.append_array(cards)
	modal.deal(dealt)
	modal.input_handler = _arrow_focus.bind(cards)
	modal.accept_action = _activate_focused.bind(cards)
	var cancel := UiDialog.option_button(_t(&"MENU_CANCEL"), "", _t(&"MENU_KEY_ESC"), modal.finish.bind(-1))
	modal.set_key_hints([[number_range(WeaponController.MAX_WEAPON_SLOTS), _t(&"MENU_HINT_REPLACE")]], true, cancel)
	return await open_dialog(modal, over_shop)


## One comparison column: symbol tile + name, role eyebrow, effective values and, for a slot, its key.
func _weapon_column(weapon: WeaponData, controller: WeaponController, role: String, role_color: Color, key: String) -> Control:
	var box := UiKit.vbox(int(UiKit.px(1)))
	if weapon == null:
		box.add_child(UiKit.eyebrow(role, role_color))
		box.add_child(UiKit.text_label(_t(&"WEAPON_EMPTY"), UiKit.SIZE_CARD_NAME, UiKit.COLOR_DISABLED))
		return box
	var head := UiKit.hbox(int(UiKit.px(4)))
	var tile := _symbol_tile(weapon.icon, UiKit.COLOR_WEAPON, WEAPON_ICON_SIZE)
	(tile.get_child(0) as Control).modulate = weapon.tint
	head.add_child(tile)
	var names := UiKit.vbox(0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UiKit.eyebrow(role, role_color))
	var name_label := UiKit.text_label(DataTexts.weapon_name(weapon), UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	names.add_child(name_label)
	head.add_child(names)
	# The slot key (or "Neu" on the offer) sits on the right of the head (R8: one row less).
	var tag: Control = UiChip.badge(_t(&"STATE_NEW"), UiKit.COLOR_GOLD) if key.is_empty() else UiChip.key(key)
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(tag)
	box.add_child(head)
	for row in UiKit.weapon_stat_rows(controller, weapon):
		var line := UiKit.hbox(int(UiKit.px(3)))
		var caption := UiKit.text_label(row[0], UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(caption)
		line.add_child(UiKit.text_label(row[1], UiKit.SIZE_BODY, UiKit.COLOR_TEXT, true))
		box.add_child(line)
	return box


# --- Dialogs (screens 06 and 10) ---

## Yes/no dialog (e.g. the exit portal). details: optional [[caption, value, color], ...] rows such
## as "Run-Gold" / "Gutschrift (100 %)". Enter = yes, Esc = no.
func confirm(title: String, text: String, yes_text := "", no_text := "", details: Array = []) -> bool:
	yes_text = yes_text if not yes_text.is_empty() else _t(&"MENU_YES")
	no_text = no_text if not no_text.is_empty() else _t(&"MENU_NO")
	var modal := UiDialog.create_menu(GameManager.PAUSE_CONFIRM, DIALOG_WIDTH, title, text, _t(&"CHOICE_EYEBROW"), UiKit.COLOR_SHIELD)
	modal.cancel_result = false
	UiDialog.add_rows(modal, details)
	var buttons := UiDialog.add_buttons(modal, [
		{"text": yes_text, "key": _t(&"MENU_KEY_ENTER"), "result": true, "default": true},
		{"text": no_text, "key": _t(&"MENU_KEY_ESC"), "result": false},
	], false)
	modal.deal(buttons)
	modal.set_key_hints([[_t(&"MENU_KEY_ENTER"), yes_text], [_t(&"MENU_KEY_ESC"), no_text]])
	return await open_dialog(modal)


## Decision with equal options side by side (pact altar: "Extra-Upgrade" vs "Pakt schließen").
## options: [{"text": String, "sub": String, "color": Color (optional accent), "icon": Texture2D
## (optional)}, ...]; returns the chosen index, or -1 on Esc when allow_cancel. 1–n pick directly;
## the first option is the Enter default. R8: every option is a card with its accent band; an
## option whose sub line names a curse ("Fluch: …") is drawn in the curse colour.
func choose_option(title: String, text: String, details: Array, options: Array, allow_cancel := false, footnote := "") -> int:
	var accent := UiKit.COLOR_MAGIC
	var modal := UiDialog.create_menu(GameManager.PAUSE_CONFIRM, CHOICE_DIALOG_WIDTH, title, text, _t(&"CHOICE_EYEBROW"), accent)
	modal.cancel_allowed = allow_cancel
	modal.cancel_result = -1
	UiDialog.add_rows(modal, details)
	var row := UiKit.hbox(int(UiKit.px(CARD_GAP)))
	row.name = "Options"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	modal.content.add_child(row)
	var cards: Array[UiCard] = []
	for i in options.size():
		var option: Dictionary = options[i]
		var card := _option_card(option, i, modal.finish.bind(i))
		card.pressed.connect(modal.finish.bind(i))
		card.focus_requested.connect(_focus_card.bind(cards, card))
		row.add_child(card)
		cards.append(card)
		if i < NUMBER_KEYS.size():
			modal.hotkeys[NUMBER_KEYS[i]] = card.activate
	if not cards.is_empty():
		_focus_card(cards, cards[0])
	modal.deal(cards)
	modal.accept_action = _activate_focused.bind(cards)
	modal.input_handler = _arrow_focus.bind(cards)
	if not footnote.is_empty():
		UiDialog.add_footnote(modal, footnote)
	var keys: Array = [[number_range(options.size()), _t(&"MENU_HINT_PICK")], [_t(&"MENU_KEY_ENTER"), _t(&"MENU_HINT_CONFIRM")]]
	if allow_cancel:
		keys.append([_t(&"MENU_KEY_ESC"), _t(&"MENU_HINT_LATER")])
	modal.set_key_hints(keys)
	return await open_dialog(modal)


## One option of choose_option as a card: key cap, title, sub line; the button inside carries the
## title (tools press dialog buttons by their text).
func _option_card(option: Dictionary, index: int, on_pick: Callable) -> UiCard:
	var sub: String = option.get("sub", "")
	var color: Color = option.get("color", UiKit.COLOR_GOLD)
	if not option.has("color") and index > 0 and sub.begins_with(_t(&"CHOICE_CURSE_PREFIX")):
		color = UiKit.COLOR_DANGER_SOFT
	var card := UiCard.new()
	card.name = "Option%d" % (index + 1)
	card.accent = color
	card.padding = Vector2(7, 6)
	card.custom_minimum_size.x = UiKit.px(OPTION_CARD_WIDTH)
	var box := UiKit.vbox(int(UiKit.px(2)))
	card.add_child(box)
	var head := UiKit.hbox(int(UiKit.px(4)))
	box.add_child(head)
	if index < NUMBER_KEYS.size():
		head.add_child(UiChip.key(str(index + 1)))
	var icon_texture: Texture2D = option.get("icon")
	if icon_texture != null:
		var tile := _symbol_tile(icon_texture, color, 16.0)
		head.add_child(tile)
		card.symbol = tile.get_child(0) as Control
	var title_button := _link_button(String(option.get("text", "")), on_pick)
	title_button.name = "Title"
	title_button.add_theme_font_override("font", UiKit.bold_font())
	title_button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_CARD_NAME))
	title_button.add_theme_color_override("font_color", UiKit.COLOR_TEXT)
	title_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(title_button)
	if not sub.is_empty():
		var sub_label := UiKit.wrapped_text(sub, OPTION_CARD_WIDTH - 14.0, UiKit.SIZE_BODY, color.lightened(0.15))
		sub_label.name = "Sub"
		box.add_child(sub_label)
	return card


# --- Campfire (A6, D-103) ---

## The one choice at the campfire: heal (index 0) or strengthen one of upgrades by a stack
## (index 1 + position in upgrades). -1 = Esc, the player may come back. Pauses like the other
## choice dialogs. 1 heals, 2–6 pick the first upgrades; Enter takes the highlighted default.
## R8: two columns - the heal button with the life bar on the left, the upgrades as a list on the
## right (scrolls above CAMPFIRE_LIST_ROWS), accent in the fire colour.
func choose_campfire_rest(heal_amount: float, heal_possible: bool, upgrades: Array[UpgradeData], player: Player = null) -> int:
	var modal := UiDialog.create_menu(GameManager.PAUSE_UPGRADE_CHOICE, CAMPFIRE_DIALOG_WIDTH, _t(&"CAMPFIRE_TITLE"),
			"", _t(&"CAMPFIRE_EYEBROW"), UiKit.COLOR_EFFECT, UiKit.COLOR_GOLD,
			RoomGenre.get_icon(RoomGenre.CAMPFIRE), true)
	modal.cancel_result = -1
	var columns := UiKit.hbox(int(UiKit.px(8)))
	columns.name = "Columns"
	modal.content.add_child(columns)
	var left := UiKit.vbox(int(UiKit.px(4)))
	left.custom_minimum_size.x = UiKit.px(CAMPFIRE_HEAL_WIDTH)
	columns.add_child(left)
	var heal_sub := _t(&"CAMPFIRE_HEAL_AMOUNT", [DamageNumber.format_amount(heal_amount)]) if heal_possible else _t(&"CAMPFIRE_HEAL_FULL")
	var heal := UiDialog.option_button(_t(&"CAMPFIRE_HEAL"), heal_sub, "1", modal.finish.bind(0), heal_possible)
	heal.name = "Heal"
	UiDialog.set_option_icon(heal, UiKit.HEART_ICON)
	heal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal.custom_minimum_size.y = UiKit.px(CAMPFIRE_HEAL_HEIGHT)
	UiDialog.set_option_enabled(heal, heal_possible)
	left.add_child(heal)
	if player != null:
		left.add_child(_life_bar(player, heal_possible, heal_amount))
	if heal_possible:
		modal.accept_allowed = true
		modal.accept_result = 0
	modal.hotkeys[NUMBER_KEYS[0]] = func() -> void:
		if heal_possible:
			modal.finish(0)
		else:
			UiSound.error(modal)
	var right := UiKit.vbox(int(UiKit.px(3)))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var dealt: Array = [heal]
	if upgrades.is_empty():
		var none := UiKit.wrapped_text(_t(&"CAMPFIRE_NO_UPGRADE"), CAMPFIRE_DIALOG_WIDTH - CAMPFIRE_HEAL_WIDTH - 40.0, UiKit.SIZE_BODY, UiKit.COLOR_DISABLED)
		right.add_child(none)
	else:
		var section := UiKit.eyebrow(_t(&"CAMPFIRE_OR_UPGRADE"), UiKit.COLOR_GOLD)
		section.name = "Section"
		right.add_child(section)
		var list := UiKit.vbox(int(UiKit.px(3)))
		list.name = "Upgrades"
		for i in upgrades.size():
			var upgrade := upgrades[i]
			var key := str(i + 2) if i + 1 < NUMBER_KEYS.size() else ""
			var button := UiDialog.option_button(DataTexts.upgrade_name(upgrade), "", key, modal.finish.bind(i + 1))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			UiDialog.set_option_icon(button, upgrade.icon)
			UiDialog.set_option_hint(button, _campfire_stack_text(upgrade), UiKit.category_color(upgrade.category))
			Modal.compact_buttons(button)
			list.add_child(button)
			dealt.append(button)
			if i + 1 < NUMBER_KEYS.size():
				modal.hotkeys[NUMBER_KEYS[i + 1]] = modal.finish.bind(i + 1)
		if upgrades.size() > CAMPFIRE_LIST_ROWS:
			var scroll := ScrollContainer.new()
			scroll.name = "Scroll"
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.custom_minimum_size.y = UiKit.px(CAMPFIRE_LIST_HEIGHT)
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(list)
			right.add_child(scroll)
		else:
			right.add_child(list)
	modal.deal(dealt)
	var keys: Array = [[number_range(upgrades.size() + 1), _t(&"MENU_HINT_PICK")]]
	if heal_possible:
		keys.append([_t(&"MENU_KEY_ENTER"), _t(&"CAMPFIRE_HEAL")])
	keys.append([_t(&"MENU_KEY_ESC"), _t(&"MENU_HINT_LATER")])
	modal.set_key_hints(keys)
	return await open_dialog(modal)


## Life bar under the heal button: current HP in red, what healing adds as a lighter part, "4.5 / 6".
func _life_bar(player: Player, heal_possible: bool, heal_amount: float) -> Control:
	var box := UiKit.vbox(int(UiKit.px(1)))
	box.name = "Life"
	var current := player.health.get_health()
	var maximum := maxf(player.health.get_max_health(), 0.01)
	var hp := "%s / %s" % [DamageNumber.format_amount(current), DamageNumber.format_amount(maximum)]
	box.add_child(UiKit.value_row(_t(&"CAMPFIRE_LIFE"), hp, UiKit.COLOR_DANGER_SOFT, UiKit.SIZE_BODY))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.max_value = maximum
	bar.value = minf(maximum, current + (heal_amount if heal_possible else 0.0))
	bar.custom_minimum_size.y = UiKit.px(4)
	bar.add_theme_stylebox_override("background", UiKit.bar_style(UiKit.COLOR_SHADOW))
	bar.add_theme_stylebox_override("fill", UiKit.bar_style(UiKit.COLOR_DANGER_SOFT.darkened(0.35)))
	var now := ProgressBar.new()
	now.show_percentage = false
	now.mouse_filter = Control.MOUSE_FILTER_IGNORE
	now.max_value = maximum
	now.value = current
	now.set_anchors_preset(Control.PRESET_FULL_RECT)
	now.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	now.add_theme_stylebox_override("fill", UiKit.bar_style(UiKit.COLOR_DANGER))
	bar.add_child(now)
	box.add_child(bar)
	return box


func _campfire_stack_text(upgrade: UpgradeData) -> String:
	var stacks := context.upgrade_manager.get_stacks(upgrade.id) if context != null else 0
	if upgrade.is_limited():
		return _t(&"CAMPFIRE_STACK_LIMITED", [stacks, upgrade.max_stacks, stacks + 1, upgrade.max_stacks])
	return _t(&"CAMPFIRE_STACK_UNLIMITED", [stacks, stacks + 1])


# --- Tab overview (screen 05) ---

func show_upgrade_overview() -> void:
	var modal := UiDialog.create_menu(GameManager.PAUSE_UPGRADE_OVERVIEW, OVERVIEW_SIZE.x, _t(&"OVERVIEW_TITLE"), "",
			_t(&"OVERVIEW_EYEBROW", [maxi(1, RunManager.get_current_room())]))
	_overview = modal
	var columns := UiKit.hbox(int(UiKit.px(12)))
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal.content.add_child(columns)
	var left := _overview_upgrades()
	columns.add_child(left)
	var right := _overview_values()
	columns.add_child(right)
	# The HP/shield/dash line goes under the upgrade list (R8: the values column was the tall one).
	var stats := right.get_node_or_null(^"Stats")
	if stats != null:
		right.remove_child(stats)
		left.add_child(stats)
	modal.set_key_hints([[_t(&"MENU_KEY_TAB"), ""], [_t(&"MENU_KEY_ESC"), _t(&"MENU_HINT_CLOSE")]])
	await open_dialog(modal)
	_overview = null


func _overview_upgrades() -> Control:
	var column := UiKit.vbox(int(UiKit.px(4)))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.0
	var active := context.upgrade_manager.get_active_upgrades() if context != null else ([] as Array[UpgradeData])
	var total := 0
	for upgrade in active:
		total += context.upgrade_manager.get_stacks(upgrade.id)
	column.add_child(UiKit.eyebrow(_t(&"OVERVIEW_UPGRADES", [total]), UiKit.COLOR_GOLD))
	if active.is_empty():
		column.add_child(UiKit.text_label(_t(&"OVERVIEW_NO_UPGRADES"), UiKit.SIZE_KEY_HINT, UiKit.COLOR_MUTED))
		return column
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = UiKit.px(OVERVIEW_LIST_HEIGHT)
	column.add_child(scroll)
	var list := UiKit.vbox(int(UiKit.px(2)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for upgrade in active:
		var row := UiKit.hbox(int(UiKit.px(5)))
		row.add_child(_symbol_tile(upgrade.icon, UiKit.category_color(upgrade.category), 12.0))
		var names := UiKit.vbox(0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_child(UiKit.text_label(DataTexts.upgrade_name(upgrade), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true))
		names.add_child(UiKit.eyebrow(UiKit.category_name(upgrade.category), UiKit.category_color(upgrade.category)))
		row.add_child(names)
		if upgrade.is_limited() and context.upgrade_manager.get_stacks(upgrade.id) >= upgrade.max_stacks:
			row.add_child(UiChip.badge(_t(&"STATE_MAX"), UiKit.COLOR_SUCCESS))
		var stack := UiKit.text_label(_stack_text(upgrade), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT_SOFT)
		stack.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(stack)
		list.add_child(row)
		list.add_child(UiKit.separator())
	return column


func _overview_values() -> Control:
	var column := UiKit.vbox(int(UiKit.px(5)))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UiKit.eyebrow(_t(&"OVERVIEW_VALUES"), UiKit.COLOR_GOLD))
	if context == null or context.player == null:
		return column
	var player := context.player
	var controller := player.weapon_controller
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var weapon := controller.get_weapon(slot)
		if weapon == null:
			continue
		var active := slot == controller.get_active_slot()
		var card := UiKit.panel(&"gold" if active else &"normal")
		card.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold" if active else &"normal", 4, 6))
		var box := UiKit.vbox(0)
		card.add_child(box)
		var head := UiKit.hbox(int(UiKit.px(4)))
		var weapon_icon := UiKit.pixel_icon(weapon.icon, 12.0)
		weapon_icon.modulate = weapon.tint
		head.add_child(weapon_icon)
		head.add_child(UiKit.text_label(DataTexts.weapon_name(weapon), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true))
		head.add_child(UiKit.text_label(_t(&"OVERVIEW_SLOT_ACTIVE" if active else &"OVERVIEW_SLOT", [slot + 1]), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED))
		box.add_child(head)
		for line in _weapon_breakdown(controller, weapon):
			box.add_child(UiKit.text_label(line, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
		column.add_child(card)
	var stats := _t(&"OVERVIEW_STATS", [
		DamageNumber.format_amount(player.health.get_health()),
		DamageNumber.format_amount(player.health.get_max_health()),
		DamageNumber.format_amount(player.shield.get_shield()),
		DamageNumber.format_amount(ShieldComponent.SOFTCAP_THRESHOLD),
		DamageNumber.format_amount(snappedf(player.dash_cooldown, 0.1))])
	var stats_label := UiKit.wrapped_text(stats, OVERVIEW_SIZE.x * 0.5 - 18.0, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	stats_label.name = "Stats"
	column.add_child(stats_label)
	var curses := _overview_curses()
	if curses != null:
		column.add_child(curses)
	return column


## Curses of the player's pacts (PlayerCurses, pact altar A8): icon, name and effect per row
## under the effective values; null without curses.
func _overview_curses() -> Control:
	if context == null or context.player == null:
		return null
	var curses := PlayerCurses.get_curses_of(context.player)
	if curses.is_empty():
		return null
	var box := UiKit.vbox(int(UiKit.px(2)))
	box.name = "Curses"
	box.add_child(UiKit.separator())
	box.add_child(UiKit.text_label(_t(&"OVERVIEW_CURSES"), UiKit.SIZE_HEADING, UiKit.COLOR_DANGER_SOFT, true))
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", int(UiKit.px(8)))
	row.add_theme_constant_override("v_separation", int(UiKit.px(2)))
	box.add_child(row)
	for curse in curses:
		var entry := UiKit.hbox(int(UiKit.px(4)))
		entry.add_child(UiKit.pixel_icon(CurseArt.get_icon(curse), 16.0))
		var names := UiKit.vbox(0)
		names.add_child(UiKit.text_label(PlayerCurses.get_curse_name(curse), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true))
		names.add_child(UiKit.text_label(PlayerCurses.get_curse_effect(curse), UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT))
		entry.add_child(names)
		row.add_child(entry)
	return box


## Effective values with the calculation shown: "14.5 Schaden (12 × 1.2) · 1.73/s (1.5 × 1.15)".
func _weapon_breakdown(controller: WeaponController, weapon: WeaponData) -> PackedStringArray:
	var damage := controller.get_effective_damage(weapon)
	var rate := controller.get_effective_attack_rate(weapon)
	var first := _t(&"OVERVIEW_WEAPON_LINE", [
		DamageNumber.format_amount(DamageProcessor.round_damage(damage)), _factor_text(weapon.base_damage, damage),
		rate, _factor_text(weapon.attack_rate, rate)])
	var extras: PackedStringArray = []
	var rows := UiKit.weapon_stat_rows(controller, weapon)
	for i in range(2, rows.size()):
		extras.append("%s %s" % [rows[i][0], rows[i][1]])
	var projectiles := controller.get_projectile_count(weapon)
	if projectiles > 1:
		extras.append(_t(&"OVERVIEW_PROJECTILES", [projectiles]))
	var pierce := controller.get_pierce_count(weapon)
	if pierce > 0:
		extras.append(_t(&"OVERVIEW_PIERCE", [pierce]))
	var bounce := controller.get_bounce_count(weapon)
	if bounce > 0:
		extras.append(_t(&"OVERVIEW_BOUNCE", [bounce]))
	return PackedStringArray([first, " · ".join(extras)])


## " (base × factor)" when upgrades change the value, else "".
func _factor_text(base: float, effective: float) -> String:
	if base <= 0.0 or is_equal_approx(base, effective):
		return ""
	return " (%s × %s)" % [_short_number(base), _short_number(effective / base)]


func _short_number(value: float) -> String:
	var text := "%.2f" % value
	text = text.rstrip("0").rstrip(".")
	return text


func _stack_text(upgrade: UpgradeData) -> String:
	var stacks := context.upgrade_manager.get_stacks(upgrade.id) if context != null else 0
	if upgrade.is_limited():
		return "%d / %d" % [stacks, upgrade.max_stacks]
	return "×%d" % stacks if stacks > 0 else ""
