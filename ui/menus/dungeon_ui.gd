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
## Layout follows docs/design screens 02-06, 10 and 11; sizes are mockup pixels (UiKit.px).

const BANNER_TIME := 2.2
## A newer banner waits until the current one was readable this long (real seconds, TESTWERT).
const BANNER_MIN_TIME := 1.2
## Room genre banner: top in mockup pixels and time on screen (TESTWERT).
const GENRE_BANNER_TOP := 38.0
const GENRE_BANNER_TIME := 2.8
const GENRE_ICON_SIZE := 16.0
## Banner subtitles wrap at this width (mockup pixels).
const BANNER_SUBTITLE_WIDTH := 280.0
## Boss HP bar (ui_spec hud.boss_bar.bar), mockup pixels.
const BOSS_BAR_SIZE := Vector2(180, 7)
const BOSS_BAR_WIDTH := 180.0
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
const HINT_TIME := 5.0
const HINT_WIDTH := 150.0
## Enemy hint cards end this far above the bottom edge: clear of the HUD weapon block (mockup px).
const HINT_BOTTOM := 36.0
## Upgrade cards (ui_spec screens.upgrade_pick.cards), inside UiDialog.WIDTH_WIDE.
const CARD_SIZE := Vector2(132, 150)
const CARD_GAP := 8.0
const CARD_LIFT := 4.0
## Shop grid: 3 columns, gap 6 (ui_spec screens.shop.grid) inside UiDialog.WIDTH_WIDE.
const SHOP_COLUMNS := 3
const SHOP_GAP := 6.0
const SHOP_CARD_SIZE := Vector2(138, 66)
## Columns of a shop card: padding 10 + icon 24 + gap 5 + text 99 = 138. The bottom line holds the
## key cap, the state (badge or action) and the price.
const SHOP_ICON_SIZE := 24.0
const SHOP_TEXT_WIDTH := 96.0
const SHOP_PRICE_WIDTH := 24.0
## Weapon comparison panel (ui_spec screens.weapon_room).
const WEAPON_PANEL_WIDTH := 310.0
const WEAPON_COLUMN_GAP := 6.0
## Tab overview panel (ui_spec screens.tab_overview).
const OVERVIEW_SIZE := Vector2(452, 236)
const OVERVIEW_LIST_HEIGHT := 150.0
const DIALOG_WIDTH := UiDialog.WIDTH_NARROW
const CHOICE_DIALOG_WIDTH := 250.0
## Campfire dialog: width in mockup pixels; above CAMPFIRE_LIST_ROWS rows of upgrades it scrolls.
const CAMPFIRE_DIALOG_WIDTH := UiDialog.WIDTH_MEDIUM
const CAMPFIRE_LIST_ROWS := 4
const CAMPFIRE_LIST_HEIGHT := 112.0
const NUMBER_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]

var context: DungeonContext = null
## Show a hint card the first time an enemy type / elite kind / champion appears.
var auto_enemy_hints := true
## Show the first-run controls card (once per save); tests and tools may switch it off.
var show_controls_hint := true

var _overview: Modal = null
var _banner_root: Control = null
var _banner_queue: Array[Dictionary] = []
var _banner_box: Control = null
var _banner_entry: Dictionary = {}
var _banner_since_ms := 0
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
## Teaching cards waiting: {"kind": &"enemy", "title", "text", "badge"} or {"kind": &"room", "genre"}.
var _hint_queue: Array[Dictionary] = []
var _hint_card: Control = null
var _hint_entry: Dictionary = {}
var _controls_hint: ControlsHint = null
## Rooms whose genre was announced (instance id -> genre), so a room is named once.
var _announced_rooms: Dictionary[int, StringName] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_banner()
	_build_boss_bar()
	_build_hint_root()
	get_tree().node_added.connect(_on_node_added)
	# Deferred: the dungeon starts the run after its children are ready.
	start_controls_hint.call_deferred()


func _process(_delta: float) -> void:
	if not _banner_queue.is_empty() and _banner_slot_free():
		_display_banner(_banner_queue.pop_front())


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


func _queue_banner(entry: Dictionary) -> void:
	var genre := entry.has("genre")
	if genre:
		# The old plain banner of the same room (e.g. "Lagerfeuer") gives way to the genre banner.
		for i in range(_banner_queue.size() - 1, -1, -1):
			if not _banner_queue[i].has("genre") and _banner_queue[i]["title"] == entry["title"]:
				_banner_queue.remove_at(i)
		if get_banner() != null and not _banner_entry.has("genre") and _banner_entry.get("title", "") == entry["title"]:
			_banner_since_ms = 0
	elif not _banner_queue.is_empty() and _banner_queue.back()["title"] == entry["title"]:
		return
	_banner_queue.append(entry)
	if _banner_slot_free():
		_display_banner(_banner_queue.pop_front())


func _banner_slot_free() -> bool:
	if get_banner() == null:
		return true
	return Time.get_ticks_msec() - _banner_since_ms >= int(BANNER_MIN_TIME * 1000.0)


func _display_banner(entry: Dictionary) -> void:
	for child in _banner_root.get_children():
		child.queue_free()
	var box := _build_genre_banner(entry) if entry.has("genre") else _build_plain_banner(entry)
	_banner_root.add_child(box)
	_banner_box = box
	_banner_entry = entry
	_banner_since_ms = Time.get_ticks_msec()
	if entry.has("genre"):
		var top := box.position.y
		box.position.y = top - UiKit.px(8)
		box.modulate.a = 0.0
		var slide := box.create_tween().set_ignore_time_scale(true)
		slide.set_parallel(true)
		slide.tween_property(box, "modulate:a", 1.0, 0.25)
		slide.tween_property(box, "position:y", top, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		slide.chain().tween_interval(GENRE_BANNER_TIME)
		slide.chain().tween_property(box, "modulate:a", 0.0, 0.5)
		slide.chain().tween_callback(box.queue_free)
		return
	box.pivot_offset = Vector2(box.size.x * 0.5, UiKit.px(11))
	box.modulate.a = 0.0
	box.scale = Vector2(1.4, 1.4)
	var tween := box.create_tween().set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.tween_property(box, "modulate:a", 1.0, 0.25)
	tween.tween_property(box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(BANNER_TIME)
	tween.chain().tween_property(box, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(box.queue_free)


func _build_plain_banner(entry: Dictionary) -> Control:
	var title: String = entry["title"]
	var subtitle: String = entry.get("subtitle", "")
	var box := UiKit.vbox(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.position.y = UiKit.px(45)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.add_child(UiKit.title(title, 16, entry.get("color", UiKit.ACCENT_COLOR)))
	if not subtitle.is_empty():
		# Long subtitles (e.g. the run start summary) wrap at a fixed width instead of running off screen.
		var sub := UiKit.text_label(subtitle, UiKit.SIZE_KEY_HINT, UiKit.COLOR_MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var single_line := UiKit.get_font().get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.font_px(UiKit.SIZE_KEY_HINT)).x
		if single_line > UiKit.px(BANNER_SUBTITLE_WIDTH):
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sub.custom_minimum_size.x = UiKit.px(BANNER_SUBTITLE_WIDTH)
		box.add_child(sub)
	return box


## Room genre banner (D-110): a dark plaque with symbol, eyebrow ("RAUM 7 · KAMPFRAUM"), name and
## one line. The plaque keeps it readable over world captions such as "Lagerfeuer".
func _build_genre_banner(entry: Dictionary) -> Control:
	var genre: StringName = entry["genre"]
	var color: Color = entry.get("color", UiKit.COLOR_GOLD)
	var plaque := UiKit.panel(&"dark")
	plaque.name = "GenreBanner"
	plaque.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 4, 10))
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(int(UiKit.px(6)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	plaque.add_child(row)
	var icon_texture := RoomGenre.get_icon(genre)
	if icon_texture != null:
		var icon := UiKit.pixel_icon(icon_texture, GENRE_ICON_SIZE)
		if RoomGenre.is_icon_tinted(genre):
			icon.modulate = color
		row.add_child(icon)
	var text := UiKit.vbox(0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var eyebrow: String = entry.get("eyebrow", "")
	if not eyebrow.is_empty():
		text.add_child(UiKit.eyebrow(eyebrow, UiKit.COLOR_MUTED))
	var title := UiKit.text_label(entry["title"], UiKit.SIZE_TITLE, color, true)
	title.name = "Title"
	text.add_child(title)
	var subtitle: String = entry.get("subtitle", "")
	if not subtitle.is_empty():
		text.add_child(UiKit.text_label(subtitle, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	plaque.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	plaque.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plaque.position.y = UiKit.px(GENRE_BANNER_TOP)
	return plaque


# --- Room genres (D-110) ---

## Hook for DungeonManager._announce_room: banner with name and symbol for rooms with gameplay of
## their own; the first time per save also the explanation card. Normal combat rooms stay unnamed.
## An ambush arena is named when it springs (on_arena_started, connected here). Returns the genre
## (RoomGenre.NONE = nothing shown). A room is announced once.
## A special room builds its content (pact altar or not, kind of trial) only in activate(), right
## after the announcement: it is named one call later, so the hook may sit before or after activate.
func show_room_genre(room: RoomController) -> StringName:
	if room == null or not is_instance_valid(room):
		return RoomGenre.NONE
	_watch_arena(room)
	if room.room_type == RoomSequence.RoomType.SPECIAL and room.state == RoomController.State.PREPARED:
		_announce_room_genre.call_deferred(room)
		return RoomGenre.of_room(room)
	return _announce_room_genre(room)


func _announce_room_genre(room: RoomController) -> StringName:
	if room == null or not is_instance_valid(room):
		return RoomGenre.NONE
	var genre := RoomGenre.of_room(room)
	if genre == RoomGenre.NONE or _announced_rooms.has(room.get_instance_id()):
		return genre
	_announced_rooms[room.get_instance_id()] = genre
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


## RoomController.arena_started: an ambush is named now ("Hinterhalt!"); a plain arena only if its
## entry was not announced (show_room_genre does that on entry).
func on_arena_started(room: RoomController, ambush: bool) -> void:
	if room == null or not is_instance_valid(room):
		return
	var id := room.get_instance_id()
	var genre := RoomGenre.AMBUSH if ambush else RoomGenre.ARENA
	if _announced_rooms.get(id, RoomGenre.NONE) == genre:
		return
	_announced_rooms[id] = genre
	show_genre(genre, room)


## The explanation card on screen (null if none), for tests and tools.
func get_room_intro_card() -> RoomIntroCard:
	return _hint_card as RoomIntroCard if is_instance_valid(_hint_card) else null


func _watch_arena(room: RoomController) -> void:
	if not room.arena_started.is_connected(on_arena_started):
		room.arena_started.connect(on_arena_started)


func _queue_room_intro(genre: StringName) -> void:
	for entry in _hint_queue:
		if entry.get("genre", RoomGenre.NONE) == genre:
			return
	# Explanations of the room go before enemy cards that are still waiting.
	_hint_queue.push_front({"kind": &"room", "genre": genre})
	if _hint_card == null:
		_show_next_hint()


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


## Short card at the bottom: badge, name and one sentence. Auto-hides, never pauses the game.
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
	if auto_enemy_hints and node is Enemy:
		# Deferred: elite, champion data and scaling are applied by then.
		notice_enemy.call_deferred(node)


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
	text.add_child(UiKit.wrapped_text(hint["text"], HINT_WIDTH, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	row.add_child(text)
	_hint_root.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.position.y -= UiKit.px(HINT_BOTTOM)
	card.modulate.a = 0.0
	_hint_card = card
	_hint_entry = hint
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.25)
	tween.tween_interval(HINT_TIME)
	tween.tween_property(card, "modulate:a", 0.0, 0.4)
	tween.tween_callback(card.queue_free)
	tween.tween_callback(_show_next_hint)


## The controls card steps aside (hidden, its timer and key tracking frozen) while another teaching
## card shows, and comes back where it was afterwards.
func _set_controls_hint_waiting(waiting: bool) -> void:
	var controls := get_controls_hint()
	if controls == null:
		return
	controls.visible = not waiting
	controls.process_mode = Node.PROCESS_MODE_DISABLED if waiting else Node.PROCESS_MODE_PAUSABLE


# --- Boss bar ---

## Boss or champion bar: portrait, name (+ tier "II", "III"), room, HP bar in the boss colour,
## HP text, phase indicator and badges (docs/design screen 11).
func show_boss_bar(enemy: Enemy) -> void:
	if _boss != null and is_instance_valid(_boss):
		_disconnect_boss(_boss)
	_boss = enemy
	var champion := enemy.is_champion()
	if champion:
		_boss_name.text = "Champion: " + enemy.get_display_name()
	else:
		_boss_name.text = BossRules.boss_title(enemy.get_display_name(), enemy.get_boss_tier())
	_boss_name.add_theme_color_override("font_color", UiKit.COLOR_GOLD)
	_boss_sub.text = "Raum %d · %s" % [maxi(1, RunManager.get_current_room()), "Champion" if champion else "Boss"]
	_boss_color = _boss_color_for(enemy, champion)
	_set_boss_health(enemy.health.get_health(), enemy.health.get_max_health())
	_set_boss_phase(enemy.phase, champion)
	for child in _boss_badges.get_children():
		child.queue_free()
	for badge in enemy.get_ability_badges():
		_boss_badges.add_child(UiKit.pixel_icon(EnemyBadges.get_texture(badge), 12.0))
	var portrait := EnemyArt.get_portrait(enemy.data)
	_boss_portrait.texture = portrait
	_boss_portrait.visible = portrait != null
	enemy.health.health_changed.connect(_on_boss_health_changed)
	enemy.phase_changed.connect(_on_boss_phase_changed)
	enemy.died.connect(_on_boss_died)
	_boss_bar_root.visible = true


func hide_boss_bar() -> void:
	_boss_bar_root.visible = false
	if _boss != null and is_instance_valid(_boss):
		_disconnect_boss(_boss)
	_boss = null


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
		_boss_phase.text = "Wütend!" if enraged else ""
	else:
		_boss_phase.text = "Phase 2 – Raserei!" if enraged else "Phase 1"
	_boss_phase.visible = not _boss_phase.text.is_empty()
	_boss_phase.add_theme_color_override("font_color", BOSS_BAR_ENRAGED_COLOR if enraged else UiKit.COLOR_MUTED)
	_boss_marker.visible = not enraged
	_boss_fill.bg_color = BOSS_BAR_ENRAGED_COLOR if enraged else _boss_color


func _set_boss_health(current: float, maximum: float) -> void:
	_boss_bar.max_value = maximum
	_boss_bar.value = current
	_boss_hp_text.text = "%s / %s" % [DamageNumber.format_amount(ceilf(current * 2.0) * 0.5), DamageNumber.format_amount(maximum)]


func _on_boss_health_changed(current: float, maximum: float) -> void:
	_set_boss_health(current, maximum)


func _on_boss_phase_changed(enemy: Enemy, phase: int) -> void:
	var champion := enemy.is_champion()
	_set_boss_phase(phase, champion)
	_boss_bar_root.modulate = Color(2.0, 1.2, 1.2)
	_boss_bar_root.create_tween().tween_property(_boss_bar_root, "modulate", Color.WHITE, 0.5)
	if champion:
		show_banner("%s wird wütend!" % enemy.data.display_name, "Er ruft Verstärkung", BOSS_BAR_ENRAGED_COLOR)
		return
	var subtitle := enemy.data.enrage_text if not enemy.data.enrage_text.is_empty() else "Phase 2"
	show_banner("%s rast!" % enemy.data.display_name, subtitle, BOSS_BAR_ENRAGED_COLOR)
	_queue_hint_once({"id": EnemyHints.PHASE_TWO_HINT_ID, "title": EnemyHints.PHASE_TWO_TITLE, "text": EnemyHints.PHASE_TWO_TEXT, "badge": &""})


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


func _build_boss_bar() -> void:
	var frame := UiKit.panel(&"dark")
	frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 4, 6))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme = UiKit.get_theme()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.position.y = UiKit.px(4)
	add_child(frame)
	var row := UiKit.hbox(int(UiKit.px(8)))
	frame.add_child(row)
	_boss_portrait = UiKit.pixel_icon(null, 48.0)
	_boss_portrait.custom_minimum_size = Vector2.ONE * UiKit.art_px(48.0)
	_boss_portrait.visible = false
	row.add_child(_boss_portrait)
	var box := UiKit.vbox(int(UiKit.px(3)))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(box)
	var header := UiKit.hbox(int(UiKit.px(4)))
	box.add_child(header)
	_boss_name = UiKit.text_label("", UiKit.SIZE_VALUE, UiKit.COLOR_GOLD, true)
	_boss_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_boss_name)
	_boss_badges = UiKit.hbox(int(UiKit.px(2)))
	header.add_child(_boss_badges)
	_boss_sub = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	_boss_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_boss_sub)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.custom_minimum_size = UiKit.pxv(BOSS_BAR_SIZE.x, BOSS_BAR_SIZE.y)
	_boss_fill = UiKit.bar_style(BOSS_BAR_COLOR)
	_boss_bar.add_theme_stylebox_override("fill", _boss_fill)
	_boss_bar.add_theme_stylebox_override("background", UiKit.bar_style(UiKit.COLOR_BG))
	box.add_child(_boss_bar)
	# Marks the phase-two threshold until it is reached.
	_boss_marker = ColorRect.new()
	_boss_marker.color = Color(UiKit.COLOR_TEXT, 0.85)
	_boss_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var marker_width := maxf(2.0, UiKit.px(1))
	_boss_marker.position = Vector2(UiKit.px(BOSS_BAR_SIZE.x) * BossRules.PHASE_TWO_THRESHOLD - marker_width * 0.5, -UiKit.px(1))
	_boss_marker.size = Vector2(marker_width, UiKit.px(BOSS_BAR_SIZE.y + 2))
	_boss_bar.add_child(_boss_marker)
	var footer := UiKit.hbox(int(UiKit.px(6)))
	box.add_child(footer)
	_boss_hp_text = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_TEXT)
	_boss_hp_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_boss_hp_text)
	_boss_phase = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	_boss_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_boss_phase)
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

## Key cap text of number keys 1..count: "1", "1–3".
static func number_range(count: int) -> String:
	return "1" if count <= 1 else "1–%d" % mini(count, NUMBER_KEYS.size())


static func _t(key: StringName, args: Array = []) -> String:
	return DungeonTexts.t(key, args)


## Fixed-size slot so the focused card can rise by CARD_LIFT without moving its neighbours.
func _lift_holder(card: UiCard) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = card.custom_minimum_size + Vector2(0, UiKit.px(CARD_LIFT))
	holder.add_child(card)
	card.position = Vector2(0, UiKit.px(CARD_LIFT))
	card.set_meta(&"lift_holder", true)
	return holder


func _focus_card(cards: Array[UiCard], target: UiCard) -> void:
	for card in cards:
		if not is_instance_valid(card):
			continue
		card.focused = card == target
		if card.has_meta(&"lift_holder"):
			card.position.y = 0.0 if card.focused else UiKit.px(CARD_LIFT)


## Enter on a card row: the focused card.
func _activate_focused(cards: Array[UiCard]) -> void:
	for card in cards:
		if is_instance_valid(card) and card.focused:
			card.activate()
			return


## ←/→ (and ↑/↓) move the focus through a card row; returns true when handled (Modal.input_handler).
func _arrow_focus(event: InputEvent, cards: Array[UiCard]) -> bool:
	var step := 0
	if event.is_action_pressed(&"ui_left", false, true) or event.is_action_pressed(&"ui_up", false, true):
		step = -1
	elif event.is_action_pressed(&"ui_right", false, true) or event.is_action_pressed(&"ui_down", false, true):
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
func choose_upgrade(offer: Array[UpgradeData], title: String, stack_gain := 1) -> UpgradeData:
	if offer.is_empty():
		return null
	var subtitle := _t(&"UPGRADE_SUBTITLE") if stack_gain <= 1 else _t(&"UPGRADE_SUBTITLE_STACKS", [stack_gain])
	var modal := UiDialog.create_menu(GameManager.PAUSE_UPGRADE_CHOICE, UiDialog.WIDTH_WIDE, title, subtitle, _t(&"UPGRADE_EYEBROW"))
	modal.cancel_allowed = false
	var row := UiKit.hbox(int(UiKit.px(CARD_GAP)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	modal.content.add_child(row)
	var cards: Array[UiCard] = []
	for i in offer.size():
		var upgrade := offer[i]
		var card := _upgrade_card(upgrade, i, modal.finish.bind(upgrade), stack_gain)
		row.add_child(_lift_holder(card))
		cards.append(card)
		card.pressed.connect(modal.finish.bind(upgrade))
		card.focus_requested.connect(_focus_card.bind(cards, card))
		if i < NUMBER_KEYS.size():
			modal.hotkeys[NUMBER_KEYS[i]] = card.activate
	modal.accept_action = _activate_focused.bind(cards)
	modal.input_handler = _arrow_focus.bind(cards)
	modal.set_key_hints([
		[number_range(offer.size()), _t(&"MENU_HINT_PICK")],
		[_t(&"MENU_KEY_ARROWS"), _t(&"MENU_HINT_MOVE")],
		[_t(&"MENU_KEY_ENTER"), _t(&"MENU_HINT_CONFIRM")],
	])
	return await modal.open(self)


func _upgrade_card(upgrade: UpgradeData, index: int, on_pick: Callable, stack_gain := 1) -> UiCard:
	var card := UiCard.new()
	card.padding = Vector2(7, 6)
	card.custom_minimum_size = UiKit.pxv(CARD_SIZE.x, CARD_SIZE.y)
	var box := UiKit.vbox(int(UiKit.px(4)))
	card.add_child(box)
	var eyebrow := UiKit.eyebrow(UiKit.category_name(upgrade.category), UiKit.category_color(upgrade.category))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	box.add_child(UiKit.pixel_icon(upgrade.icon, 32.0))
	var name_label := UiKit.title(upgrade.display_name, UiKit.SIZE_VALUE, UiKit.COLOR_TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = UiKit.px(CARD_SIZE.x - 16.0)
	box.add_child(name_label)
	var description := UiKit.wrapped_text(upgrade.description, CARD_SIZE.x - 16.0)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(description)
	box.add_child(_filler())
	var stacks := context.upgrade_manager.get_stacks(upgrade.id) if context != null else 0
	var stack_label: Label
	if upgrade.is_limited():
		var after := mini(stacks + stack_gain, upgrade.max_stacks)
		stack_label = UiKit.text_label(_t(&"UPGRADE_STACKS_LIMITED", [stacks, upgrade.max_stacks, after, upgrade.max_stacks]), UiKit.SIZE_BODY, UiKit.COLOR_SUCCESS)
	else:
		stack_label = UiKit.text_label(_t(&"UPGRADE_STACKS_UNLIMITED", [stacks, stacks + stack_gain]), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stack_label)
	box.add_child(_key_row(str(index + 1), _link_button(_t(&"MENU_CHOOSE"), on_pick)))
	return card


# --- Shop (screen 04) ---

## The merchant's offers in a 3-column grid. 1–6 or a click buys; offers that cannot be bought keep
## their look and show why (badge); clicking them plays the error sound. Esc closes.
func open_shop(offers: Array[ShopOffer], player: Player) -> void:
	var modal := UiDialog.create_menu(GameManager.PAUSE_SHOP, UiDialog.WIDTH_WIDE, _t(&"SHOP_TITLE"), _t(&"SHOP_SUBTITLE"), _t(&"SHOP_EYEBROW"))
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
	for i in mini(offers.size(), NUMBER_KEYS.size()):
		modal.hotkeys[NUMBER_KEYS[i]] = func() -> void:
			if i < cards.size() and is_instance_valid(cards[i]):
				cards[i].activate()
	modal.set_meta(&"refresh", refresh)
	refresh.call()
	await modal.open(self)


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
	var card := UiCard.new()
	card.name = "Offer%d" % (index + 1)
	card.set_meta(&"offer_state", state)
	card.padding = Vector2(5, 5)
	card.custom_minimum_size = UiKit.pxv(SHOP_CARD_SIZE.x, SHOP_CARD_SIZE.y)
	var box := UiKit.vbox(int(UiKit.px(3)))
	card.add_child(box)
	var row := UiKit.hbox(int(UiKit.px(5)))
	box.add_child(row)
	var offer_icon := UiKit.pixel_icon(offer.get_icon(), SHOP_ICON_SIZE)
	offer_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if offer.kind == ShopOffer.Kind.WEAPON:
		offer_icon.modulate = offer.weapon.tint
	if state == &"sold":
		offer_icon.modulate = Color(0.42, 0.4, 0.5)
	row.add_child(offer_icon)
	var text := UiKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var eyebrow := _shop_eyebrow(offer)
	var eyebrow_label := UiKit.eyebrow(eyebrow[0], eyebrow[1])
	eyebrow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eyebrow_label.custom_minimum_size.x = UiKit.px(SHOP_TEXT_WIDTH)
	text.add_child(eyebrow_label)
	var title_color := UiKit.COLOR_MUTED if state == &"sold" else UiKit.COLOR_TEXT
	text.add_child(_fitted_label(offer.get_title(), SHOP_TEXT_WIDTH, UiKit.SIZE_CARD_NAME, title_color))
	var description := offer.get_description()
	if offer.kind == ShopOffer.Kind.WEAPON:
		description = UiKit.weapon_stats_text(player.weapon_controller, offer.weapon)
	text.add_child(UiKit.wrapped_text(description, SHOP_TEXT_WIDTH, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	box.add_child(_filler())
	var footer := UiKit.hbox(int(UiKit.px(4)))
	footer.name = "State"
	box.add_child(footer)
	if index < NUMBER_KEYS.size():
		footer.add_child(UiChip.key(str(index + 1)))
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.add_child(_shop_state(offer, state))
	if state != &"sold":
		footer.add_child(_shop_price(offer, state))
	card.disabled = state in [&"sold", &"unavailable", &"too_expensive"]
	card.pressed.connect(_on_buy_pressed.bind(offer, player, modal))
	card.focus_requested.connect(func() -> void: card.focused = true)
	card.mouse_exited.connect(func() -> void: card.focused = false)
	return card


## Price: gold, red when there is too little gold, muted when the offer cannot be bought anyway.
func _shop_price(offer: ShopOffer, state: StringName) -> Control:
	var price_color := UiKit.COLOR_GOLD
	match state:
		&"too_expensive":
			price_color = UiKit.COLOR_DANGER
		&"unavailable":
			price_color = UiKit.COLOR_DISABLED
	var price := UiKit.icon_value(UiKit.GOLD_ICON, str(offer.price), price_color, UiKit.SIZE_VALUE, 12.0)
	price.name = "Price"
	price.alignment = BoxContainer.ALIGNMENT_END
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.custom_minimum_size.x = UiKit.px(SHOP_PRICE_WIDTH)
	return price


## The line under an offer: a badge for every state that blocks the purchase (UX2), else the action.
func _shop_state(offer: ShopOffer, state: StringName) -> Control:
	match state:
		&"sold":
			return UiChip.badge(_t(&"STATE_SOLD"), UiKit.COLOR_MUTED)
		&"unavailable":
			return UiChip.badge(_unavailable_text(offer), UiKit.COLOR_SHIELD)
		&"too_expensive":
			return UiChip.badge(_t(&"STATE_TOO_LITTLE_GOLD"), UiKit.COLOR_DANGER_SOFT, UiKit.LOCK_ICON)
		&"replace":
			return _centered_label(_t(&"STATE_REPLACE_SLOT"), UiKit.COLOR_GOLD)
	return _centered_label(_t(&"MENU_HINT_BUY"), UiKit.COLOR_MUTED)


func _centered_label(text: String, color: Color) -> Label:
	var label := UiKit.text_label(text, UiKit.SIZE_BODY, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


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
			slot = await choose_weapon_slot(offer.weapon, player)
			if slot < 0:
				return
	context.economy.try_purchase(offer, player, context.upgrade_manager, slot)
	if is_instance_valid(modal):
		(modal.get_meta(&"refresh") as Callable).call()


# --- Weapon slot choice (screen 03) ---

## Returns the slot to replace, or -1 when cancelled. Shows effective stats of all three weapons.
func choose_weapon_slot(new_weapon: WeaponData, player: Player) -> int:
	var controller := player.weapon_controller
	var modal := UiDialog.create_menu(GameManager.PAUSE_WEAPON_CHOICE, WEAPON_PANEL_WIDTH, _t(&"WEAPON_TITLE"), _t(&"WEAPON_SUBTITLE"), _t(&"WEAPON_EYEBROW"), UiKit.COLOR_WEAPON)
	modal.cancel_result = -1
	var columns := UiKit.hbox(int(UiKit.px(WEAPON_COLUMN_GAP)))
	modal.content.add_child(columns)
	var offer := UiKit.panel(&"gold")
	offer.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold", 6, 6))
	offer.add_child(_weapon_column(new_weapon, controller, _t(&"WEAPON_OFFER"), UiKit.COLOR_GOLD, ""))
	offer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(offer)
	var cards: Array[UiCard] = []
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var weapon := controller.get_weapon(slot)
		var role := _t(&"WEAPON_SLOT_ACTIVE" if slot == controller.get_active_slot() else &"WEAPON_SLOT", [slot + 1])
		var card := UiCard.new()
		card.padding = Vector2(6, 6)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(_weapon_column(weapon, controller, role, UiKit.COLOR_SHIELD, str(slot + 1)))
		card.pressed.connect(modal.finish.bind(slot))
		card.focus_requested.connect(_focus_card.bind(cards, card))
		card.mouse_exited.connect(func() -> void: card.focused = false)
		cards.append(card)
		columns.add_child(card)
		modal.hotkeys[NUMBER_KEYS[slot]] = card.activate
	modal.input_handler = _arrow_focus.bind(cards)
	modal.accept_action = _activate_focused.bind(cards)
	UiDialog.add_footnote(modal, _t(&"WEAPON_VALUES_NOTE"))
	var cancel := UiDialog.option_button(_t(&"MENU_CANCEL"), "", _t(&"MENU_KEY_ESC"), modal.finish.bind(-1))
	modal.set_key_hints([[number_range(WeaponController.MAX_WEAPON_SLOTS), _t(&"MENU_HINT_REPLACE")]], true, cancel)
	return await modal.open(self)


## One comparison column: icon + name, role eyebrow, effective values and, for a slot, its key.
func _weapon_column(weapon: WeaponData, controller: WeaponController, role: String, role_color: Color, key: String) -> Control:
	var box := UiKit.vbox(int(UiKit.px(2)))
	if weapon == null:
		box.add_child(UiKit.eyebrow(role, role_color))
		box.add_child(UiKit.text_label(_t(&"WEAPON_EMPTY"), UiKit.SIZE_CARD_NAME, UiKit.COLOR_DISABLED))
		return box
	var head := UiKit.hbox(int(UiKit.px(4)))
	var weapon_icon := UiKit.pixel_icon(weapon.icon, 16.0)
	weapon_icon.modulate = weapon.tint
	head.add_child(weapon_icon)
	var name_label := UiKit.text_label(weapon.display_name, UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_label)
	box.add_child(head)
	box.add_child(UiKit.eyebrow(role, role_color))
	for row in UiKit.weapon_stat_rows(controller, weapon):
		var line := UiKit.hbox(int(UiKit.px(3)))
		line.add_child(UiKit.text_label(row[0], UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
		line.add_child(UiKit.text_label(row[1], UiKit.SIZE_BODY, UiKit.COLOR_TEXT, true))
		box.add_child(line)
	box.add_child(_filler())
	if key.is_empty():
		var badge := UiChip.badge(_t(&"STATE_NEW"), UiKit.COLOR_GOLD)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(badge)
	else:
		var action := UiKit.text_label(_t(&"MENU_HINT_REPLACE"), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
		action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var row := _key_row(key, action)
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		box.add_child(row)
	return box


# --- Dialogs (screens 06 and 10) ---

## Yes/no dialog (e.g. the exit portal). details: optional [[caption, value, color], ...] rows such
## as "Run-Gold" / "Gutschrift (100 %)". Enter = yes, Esc = no.
func confirm(title: String, text: String, yes_text := "", no_text := "", details: Array = []) -> bool:
	yes_text = yes_text if not yes_text.is_empty() else _t(&"MENU_YES")
	no_text = no_text if not no_text.is_empty() else _t(&"MENU_NO")
	var modal := UiDialog.create_menu(GameManager.PAUSE_CONFIRM, DIALOG_WIDTH, title, text, _t(&"CHOICE_EYEBROW"))
	modal.cancel_result = false
	UiDialog.add_rows(modal, details)
	UiDialog.add_buttons(modal, [
		{"text": yes_text, "key": _t(&"MENU_KEY_ENTER"), "result": true, "default": true},
		{"text": no_text, "key": _t(&"MENU_KEY_ESC"), "result": false},
	], false)
	modal.set_key_hints([[_t(&"MENU_KEY_ENTER"), yes_text], [_t(&"MENU_KEY_ESC"), no_text]])
	return await modal.open(self)


## Decision with equal options side by side (pact altar: "Extra-Upgrade" vs "Pakt schließen").
## options: [{"text": String, "sub": String}, ...]; returns the chosen index, or -1 on Esc when
## allow_cancel. 1–n pick directly; the first option is the Enter default.
func choose_option(title: String, text: String, details: Array, options: Array, allow_cancel := false, footnote := "") -> int:
	var modal := UiDialog.create_menu(GameManager.PAUSE_CONFIRM, CHOICE_DIALOG_WIDTH, title, text, _t(&"CHOICE_EYEBROW"))
	modal.cancel_allowed = allow_cancel
	modal.cancel_result = -1
	UiDialog.add_rows(modal, details)
	var entries: Array = []
	for i in options.size():
		var option: Dictionary = options[i]
		var key := str(i + 1) if i < NUMBER_KEYS.size() else ""
		entries.append({"text": option.get("text", ""), "sub": option.get("sub", ""), "key": key, "result": i, "default": i == 0})
		if i < NUMBER_KEYS.size():
			modal.hotkeys[NUMBER_KEYS[i]] = modal.finish.bind(i)
	UiDialog.add_buttons(modal, entries, false)
	if not footnote.is_empty():
		UiDialog.add_footnote(modal, footnote)
	var keys: Array = [[number_range(options.size()), _t(&"MENU_HINT_PICK")], [_t(&"MENU_KEY_ENTER"), _t(&"MENU_HINT_CONFIRM")]]
	if allow_cancel:
		keys.append([_t(&"MENU_KEY_ESC"), _t(&"MENU_HINT_LATER")])
	modal.set_key_hints(keys)
	return await modal.open(self)


# --- Campfire (A6, D-103) ---

## The one choice at the campfire: heal (index 0) or strengthen one of upgrades by a stack
## (index 1 + position in upgrades). -1 = Esc, the player may come back. Pauses like the other
## choice dialogs. 1 heals, 2–6 pick the first upgrades; Enter takes the highlighted default.
func choose_campfire_rest(heal_amount: float, heal_possible: bool, upgrades: Array[UpgradeData], player: Player = null) -> int:
	var modal := UiDialog.create_menu(GameManager.PAUSE_UPGRADE_CHOICE, CAMPFIRE_DIALOG_WIDTH, _t(&"CAMPFIRE_TITLE"),
			_t(&"CAMPFIRE_SUBTITLE"), _t(&"CAMPFIRE_EYEBROW"), UiKit.COLOR_EFFECT)
	modal.cancel_result = -1
	if player != null:
		var hp := "%s / %s" % [DamageNumber.format_amount(player.health.get_health()), DamageNumber.format_amount(player.health.get_max_health())]
		UiDialog.add_rows(modal, [[_t(&"CAMPFIRE_LIFE"), hp, UiKit.COLOR_DANGER_SOFT]])
	var heal_sub := _t(&"CAMPFIRE_HEAL_AMOUNT", [DamageNumber.format_amount(heal_amount)]) if heal_possible else _t(&"CAMPFIRE_HEAL_FULL")
	var heal := UiDialog.option_button(_t(&"CAMPFIRE_HEAL"), heal_sub, "1", modal.finish.bind(0), heal_possible)
	heal.name = "Heal"
	UiDialog.set_option_icon(heal, UiKit.HEART_ICON)
	heal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiDialog.set_option_enabled(heal, heal_possible)
	modal.content.add_child(heal)
	if heal_possible:
		modal.accept_allowed = true
		modal.accept_result = 0
	modal.hotkeys[NUMBER_KEYS[0]] = func() -> void:
		if heal_possible:
			modal.finish(0)
		else:
			UiSound.error(modal)
	if upgrades.is_empty():
		UiDialog.add_footnote(modal, _t(&"CAMPFIRE_NO_UPGRADE"))
	else:
		UiDialog.add_section(modal, _t(&"CAMPFIRE_OR_UPGRADE"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", int(UiKit.px(4)))
		grid.add_theme_constant_override("v_separation", int(UiKit.px(4)))
		for i in upgrades.size():
			var upgrade := upgrades[i]
			var key := str(i + 2) if i + 1 < NUMBER_KEYS.size() else ""
			var button := UiDialog.option_button(upgrade.display_name, _campfire_stack_text(upgrade), key, modal.finish.bind(i + 1))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UiDialog.set_option_icon(button, upgrade.icon)
			grid.add_child(button)
			if i + 1 < NUMBER_KEYS.size():
				modal.hotkeys[NUMBER_KEYS[i + 1]] = modal.finish.bind(i + 1)
		if upgrades.size() > CAMPFIRE_LIST_ROWS * 2:
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.custom_minimum_size.y = UiKit.px(CAMPFIRE_LIST_HEIGHT)
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(grid)
			modal.content.add_child(scroll)
		else:
			modal.content.add_child(grid)
	var keys: Array = [[number_range(upgrades.size() + 1), _t(&"MENU_HINT_PICK")]]
	if heal_possible:
		keys.append([_t(&"MENU_KEY_ENTER"), _t(&"CAMPFIRE_HEAL")])
	keys.append([_t(&"MENU_KEY_ESC"), _t(&"MENU_HINT_LATER")])
	modal.set_key_hints(keys)
	return await modal.open(self)


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
	modal.frame.custom_minimum_size.y = UiKit.px(OVERVIEW_SIZE.y)
	var columns := UiKit.hbox(int(UiKit.px(12)))
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal.content.add_child(columns)
	columns.add_child(_overview_upgrades())
	columns.add_child(_overview_values())
	modal.set_key_hints([[_t(&"MENU_KEY_TAB"), ""], [_t(&"MENU_KEY_ESC"), _t(&"MENU_HINT_CLOSE")]])
	await modal.open(self)
	_overview = null


func _overview_upgrades() -> Control:
	var column := UiKit.vbox(int(UiKit.px(4)))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.0
	var active := context.upgrade_manager.get_active_upgrades() if context != null else ([] as Array[UpgradeData])
	var total := 0
	for upgrade in active:
		total += context.upgrade_manager.get_stacks(upgrade.id)
	column.add_child(UiKit.text_label(_t(&"OVERVIEW_UPGRADES", [total]), UiKit.SIZE_HEADING, UiKit.COLOR_GOLD, true))
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
		var row := UiKit.hbox(int(UiKit.px(6)))
		row.add_child(UiKit.pixel_icon(upgrade.icon, 16.0))
		var names := UiKit.vbox(0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_child(UiKit.text_label(upgrade.display_name, UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true))
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
	column.add_child(UiKit.text_label(_t(&"OVERVIEW_VALUES"), UiKit.SIZE_HEADING, UiKit.COLOR_GOLD, true))
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
		card.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold" if active else &"normal", 5, 6))
		var box := UiKit.vbox(int(UiKit.px(1)))
		card.add_child(box)
		var head := UiKit.hbox(int(UiKit.px(4)))
		var weapon_icon := UiKit.pixel_icon(weapon.icon, 16.0)
		weapon_icon.modulate = weapon.tint
		head.add_child(weapon_icon)
		head.add_child(UiKit.text_label(weapon.display_name, UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true))
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
	column.add_child(UiKit.wrapped_text(stats, OVERVIEW_SIZE.x * 0.5 - 18.0, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
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
	var first := "%s Schaden%s · %.2f/s%s" % [
		DamageNumber.format_amount(DamageProcessor.round_damage(damage)), _factor_text(weapon.base_damage, damage),
		rate, _factor_text(weapon.attack_rate, rate)]
	var extras: PackedStringArray = []
	var rows := UiKit.weapon_stat_rows(controller, weapon)
	for i in range(2, rows.size()):
		extras.append("%s %s" % [rows[i][0], rows[i][1]])
	var projectiles := controller.get_projectile_count(weapon)
	if projectiles > 1:
		extras.append("%d Geschosse" % projectiles)
	var pierce := controller.get_pierce_count(weapon)
	if pierce > 0:
		extras.append("Durchschlag %d" % pierce)
	var bounce := controller.get_bounce_count(weapon)
	if bounce > 0:
		extras.append("Abpraller %d" % bounce)
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
