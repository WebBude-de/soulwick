class_name Hud
extends CanvasLayer
## Compact edge HUD (D-042, docs/design screen 01 and 12). Displays values pushed via signals; it
## never computes gameplay state.
## Dungeon: hearts in quarter steps + shield + run gold (top left), room and cycle (top right), weapon
## slots with effective values, special and dash cooldown (bottom left).
## Village: village gold + soul crystals (top right) and chronicle values (bottom left).
## All measurements are mockup pixels (480×270) converted with UiKit.px / UiKit.art_px.
## R8: values that change hop once (hearts, shield, gold, crystals); the weapon block sits in one
## panel_dark with the slots, the active weapon's name and values, and its keys as key caps
## ([Q] Bogen · [RMB] Wirbelschlag · [Space] Dash) with the cooldown bars next to them.
## G3 (playtest note #12): the HUD is compact. Its pixel art (frames, hearts, icons, key caps) is
## drawn at HUD_PIXEL screen pixels per art pixel instead of UiKit.ART_SCALE, the weapon block has
## two short lines, and keys are KeyCaps with input symbols (mouse buttons, space, tab …) from the
## current binding. The hint line bottom right uses the same caps.

const HEART_TEXTURES: Array[Texture2D] = [
	preload("res://art/ui/heart_empty.png"),
	preload("res://art/ui/heart_1q.png"),
	preload("res://art/ui/heart_half.png"),
	preload("res://art/ui/heart_3q.png"),
	preload("res://art/ui/heart_full.png"),
]
const SHIELD_ICON: Texture2D = preload("res://art/ui/shield_icon.png")
const GOLD_ICON: Texture2D = preload("res://art/ui/gold_icon.png")
const CRYSTAL_ICON: Texture2D = preload("res://art/ui/crystal_icon.png")
const TROPHY_ICON: Texture2D = preload("res://art/ui/trophy_icon.png")
const SKULL_ICON: Texture2D = preload("res://art/ui/skull_icon.png")
const CLOCK_ICON: Texture2D = preload("res://art/ui/clock_icon.png")
const HP_PER_HEART := 2.0
## Hearts are shown in at most HEART_ROWS rows of HEARTS_PER_ROW. Beyond that (test players with
## huge max HP) one heart plus "×N" (hearts left) keeps the HUD readable and cheap.
const HEARTS_PER_ROW := 10
const HEART_ROWS := 2
## Screen pixels per art pixel in the HUD (dialogs: UiKit.ART_SCALE). TESTWERT (G3).
const HUD_PIXEL: int = KeyCap.HUD_PIXEL
## Heart size on screen: the 16 px art at HUD_PIXEL.
const HEART_SIZE := 16.0 * HUD_PIXEL
## Size of the 16 px icons (shield, gold, crystal, weapons) on screen.
const ICON_SIZE := 16.0 * HUD_PIXEL
## Translation keys (D-111): the hint label gets the key as text, Godot translates it live.
const CONTROLS_HINT: StringName = &"HUD_CONTROLS_HINT"
## After the first-run controls card (ControlsHint) the key line shrinks to this (UX1); all keys are
## in Esc → Optionen → Steuerung.
const CONTROLS_HINT_SHORT: StringName = &"HUD_CONTROLS_HINT_SHORT"
## Room type -> key HUD_ROOM_TYPE_<RoomSequence.RoomType name>; unknown types fall back to
## RoomSequence.get_type_name() (German).
const ROOM_TYPE_KEY_PREFIX := "HUD_ROOM_TYPE_"
## The HUD joins this group (DungeonUI: set_room_mode).
const GROUP: StringName = &"hud"
## Bars at the top centre (task bar, boss bar of DungeonUI): the room line moves below them when
## they would overlap (R3, 07_ui.md).
const TOP_CENTER_GROUP: StringName = &"hud_top_center"

# Layout in mockup pixels (ui_spec.json "hud"; G3 values TESTWERT).
const STATUS_POSITION := Vector2(6, 6)
const HEART_GAP := 1.0
const EDGE_MARGIN := 8.0
## Room/cycle line top: the height of the task bar (07_ui.md).
const ROOM_LINE_TOP := 4.0
const ROOM_LINE_GAP := 3.0
const WEAPON_MARGIN := 6.0
## Padding inside the HUD frames (vertical, horizontal).
const FRAME_PADDING := Vector2(3, 4)
const SLOT_GAP := 2.0
## Free art pixels between a slot's rim and its icon.
const SLOT_PADDING := 1
const INACTIVE_SLOT_ALPHA := 0.8
## The frames are a little see-through, the scene shows under them.
const FRAME_ALPHA := 0.9
const HINT_MAX_WIDTH := 200.0
const KEY_PAIR_GAP := 2.0
const KEY_ROW_GAP := 5.0
const HINT_ENTRY_GAP := 5.0
const DASH_BAR_WIDTH := 12.0
const SPECIAL_BAR_WIDTH := 12.0
## Hint line entries: [ControlsInfo id, caption key suffix (HINT_KEY_PREFIX + suffix), English
## fallback, German fallback]. The keys are new in G3; until localization has them the fallbacks show.
## The full line shows until the first-run controls card was seen (UX1), then the short one.
const HINT_KEY_PREFIX := "HUD_HINT_"
const HINT_ENTRIES_FULL: Array[Array] = [
	[ControlsInfo.MOVE, "MOVE", "move", "bewegen"],
	[ControlsInfo.AIM, "AIM", "aim", "zielen"],
	[ControlsInfo.ATTACK, "ATTACK", "attack", "angreifen"],
	[ControlsInfo.DASH, "DASH", "dash", "Dash"],
	[ControlsInfo.SPECIAL, "SPECIAL", "special", "Spezial"],
	[ControlsInfo.SWITCH, "SWITCH", "weapon", "Waffe"],
	[ControlsInfo.INTERACT, "USE", "use", "benutzen"],
	[ControlsInfo.OVERVIEW, "UPGRADES", "upgrades", "Upgrades"],
	[ControlsInfo.PAUSE, "PAUSE", "pause", "Pause"],
]
const HINT_ENTRIES_SHORT: Array[Array] = [
	[ControlsInfo.OVERVIEW, "UPGRADES", "upgrades", "Upgrades"],
	[ControlsInfo.PAUSE, "PAUSE_OPTIONS", "pause and options", "Pause und Optionen"],
]
## Hop of a changed value (scale).
const BUMP_SCALE := 1.3
const CHRONICLE_REFRESH := 1.0

var _player: Player = null
var _dungeon_mode := false
## Rooms until the next regular heal; -1 = unknown (hidden). Set by the dungeon (set_heal_countdown).
var _heal_countdown := -1
## Campfire between two biomes (set by the dungeon via WorldController).
var _campfire_active := false
var _campfire_area := ""
## Name of the room mode ("Arena", "Flamme hüten") instead of the room type; "" = room type.
var _room_mode := ""

var _status_frame: PanelContainer
var _hearts: GridContainer
## Reused heart icons (never rebuilt per HP change) and the "×N" count of the compact display.
var _heart_icons: Array[TextureRect] = []
var _heart_count_label: Label
var _shield_label: Label
var _gold_label: Label
var _crystal_label: Label
var _crystal_icon: TextureRect
var _room_box: VBoxContainer
var _room_label: Label
var _room_detail: Label
var _weapon_root: Control
var _weapon_panels: Array[PanelContainer] = []
## Special cooldown bar per weapon slot (null for empty slots).
var _special_bars: Array[ProgressBar] = [null, null]
var _weapon_name: Label
var _weapon_stats: Label
## Key caps with captions under the weapon values (switch, special, dash).
var _weapon_keys: HBoxContainer
var _weapon_hint: Label
var _dash_bar: ProgressBar
## Special cooldown of the active weapon next to its key cap (null without a special).
var _special_key_bar: ProgressBar = null
## Last shown fill of every heart (quarter steps) and values, so only changes hop.
var _heart_fills: Array[int] = []
var _last_values := {}
## Plain text of the hint line (tools and tests read it; _hint_row shows it with key caps).
var _hint_label: Label
var _hint_row: HFlowContainer
var _hint_full := false
## Touch controls in use (TouchState): no keyboard hints, the weapon keys show the touch buttons.
var _touch := false
var _currency_frame: PanelContainer
var _village_gold: Label
var _village_crystals: Label
var _chronicle_frame: PanelContainer
var _chronicle_room: Label
var _chronicle_kills: Label
var _chronicle_time: Label
var _chronicle_timer := 0.0
var _root: Control


func _ready() -> void:
	layer = 5
	add_to_group(GROUP)
	var root := Control.new()
	root.theme = UiKit.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root
	_build_status(root)
	_build_room(root)
	_build_weapons(root)
	_build_hint(root)
	_build_village(root)
	RunManager.run_gold_changed.connect(_on_gold_changed.unbind(1))
	RunManager.room_changed.connect(_on_room_changed)
	SaveManager.permanent_gold_changed.connect(_on_gold_changed.unbind(1))
	RunManager.run_crystals_changed.connect(_on_gold_changed.unbind(1))
	SaveManager.permanent_crystals_changed.connect(_on_gold_changed.unbind(1))
	EventBus.upgrade_acquired.connect(_on_weapons_changed.unbind(2))
	SaveManager.seen_changed.connect(_refresh_hint.unbind(1))
	SaveManager.slot_changed.connect(_refresh_hint.unbind(1))
	# The HUD stays visible in menus; their overlays (higher canvas layers) dim it with the scene.
	set_dungeon_mode(false)


func bind_player(player: Player) -> void:
	_player = player
	player.health.health_changed.connect(_on_health_changed)
	player.shield.shield_changed.connect(_on_shield_changed)
	player.weapon_controller.weapon_changed.connect(_on_weapons_changed.unbind(2))
	player.weapon_controller.active_slot_changed.connect(_on_weapons_changed.unbind(1))
	_on_health_changed(player.health.get_health(), player.health.get_max_health())
	_on_shield_changed(player.shield.get_shield())
	_on_weapons_changed()


## Dungeon: run gold and room number. Village: permanent gold and chronicle.
func set_dungeon_mode(enabled: bool) -> void:
	_dungeon_mode = enabled
	_room_box.visible = enabled
	_status_frame.visible = enabled
	_weapon_root.visible = enabled
	_currency_frame.visible = not enabled
	_chronicle_frame.visible = not enabled
	if not enabled:
		_heal_countdown = -1
	_on_gold_changed()
	_on_room_changed(RunManager.get_current_room())
	_refresh_chronicle()
	_refresh_hint()


## Full key line until the save has seen the first-run controls card, then the short one.
func _refresh_hint() -> void:
	var full := not SaveManager.has_seen(ControlsHint.SEEN_ID)
	_hint_label.text = CONTROLS_HINT if full else CONTROLS_HINT_SHORT
	if full == _hint_full and _hint_row.get_child_count() > 0:
		return
	_hint_full = full
	_build_hint_entries()


## Key caps + short captions of the hint line ([Tab] Upgrades · [Esc] Pause und Optionen).
func _build_hint_entries() -> void:
	for child in _hint_row.get_children():
		_hint_row.remove_child(child)
		child.queue_free()
	for entry: Array in (HINT_ENTRIES_FULL if _hint_full else HINT_ENTRIES_SHORT):
		var pair := UiKit.hbox(int(UiKit.px(KEY_PAIR_GAP)))
		pair.add_child(KeyCap.row_for_control(entry[0], HUD_PIXEL))
		var caption := UiKit.text_label(hud_text(StringName(HINT_KEY_PREFIX + String(entry[1])), entry[2], entry[3]), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pair.add_child(caption)
		_hint_row.add_child(pair)


## Text of a new translation key with a fallback per language until localization has the key (G3).
static func hud_text(key: StringName, english: String, german: String) -> String:
	return DataTexts.text_or(key, german if Loc.current_language() == &"de" else english)


## Touch controls switched on or off (TouchState, read only): the hint line is for keyboards and
## hides, the weapon keys show the touch buttons. The touch buttons sit bottom right, the compact
## weapon block bottom left stays clear of them.
func _check_touch() -> void:
	var touch := TouchState.shared().is_active()
	if touch == _touch:
		return
	set_touch_mode(touch)


func set_touch_mode(enabled: bool) -> void:
	_touch = enabled
	_hint_row.visible = not enabled
	if _player != null and is_instance_valid(_player):
		_refresh_weapon_text(_player.weapon_controller, _player.weapon_controller.get_active_slot())


func is_touch_mode() -> bool:
	return _touch


## Hook for the dungeon: rooms until the next regular heal (-1 hides the hint).
func set_heal_countdown(rooms_left: int) -> void:
	_heal_countdown = rooms_left
	_on_room_changed(RunManager.get_current_room())


## Hook for DungeonUI: the detail line names the room mode ("Zyklus 3 · Arena"); "" = room type.
func set_room_mode(mode_name: String) -> void:
	if _room_mode == mode_name:
		return
	_room_mode = mode_name
	_on_room_changed(RunManager.get_current_room())


func _process(delta: float) -> void:
	_check_touch()
	if not _dungeon_mode:
		_chronicle_timer -= delta
		if _chronicle_timer <= 0.0:
			_refresh_chronicle()
	else:
		_dodge_top_center()
	if _player == null or not is_instance_valid(_player):
		return
	_dash_bar.value = 1.0 - _player.get_dash_cooldown_left() / maxf(0.01, _player.dash_cooldown)
	_update_special_bars()


# --- Builders ---

func _build_status(root: Control) -> void:
	var frame := hud_frame()
	frame.position = UiKit.pxv(STATUS_POSITION.x, STATUS_POSITION.y)
	root.add_child(frame)
	_status_frame = frame
	var box := UiKit.vbox(int(UiKit.px(2)))
	frame.add_child(box)
	var heart_row := UiKit.hbox(int(UiKit.px(3)))
	box.add_child(heart_row)
	_hearts = GridContainer.new()
	_hearts.columns = HEARTS_PER_ROW
	_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hearts.add_theme_constant_override("h_separation", int(UiKit.px(HEART_GAP)))
	_hearts.add_theme_constant_override("v_separation", int(UiKit.px(HEART_GAP)))
	heart_row.add_child(_hearts)
	_heart_count_label = _value_label(UiKit.COLOR_DANGER_SOFT)
	_heart_count_label.visible = false
	heart_row.add_child(_heart_count_label)
	var row := UiKit.hbox(int(UiKit.px(2)))
	row.add_child(UiKit.icon(SHIELD_ICON, ICON_SIZE))
	_shield_label = _value_label(UiKit.COLOR_TEXT)
	_shield_label.custom_minimum_size.x = UiKit.px(9)
	row.add_child(_shield_label)
	row.add_child(UiKit.icon(GOLD_ICON, ICON_SIZE))
	_gold_label = _value_label(UiKit.COLOR_GOLD)
	_gold_label.custom_minimum_size.x = UiKit.px(9)
	row.add_child(_gold_label)
	_crystal_icon = UiKit.icon(CRYSTAL_ICON, ICON_SIZE)
	row.add_child(_crystal_icon)
	_crystal_label = _value_label(UiKit.COLOR_CRYSTAL)
	row.add_child(_crystal_label)
	box.add_child(row)


func _build_room(root: Control) -> void:
	var box := UiKit.vbox(0)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -UiKit.px(EDGE_MARGIN)
	box.offset_top = UiKit.px(ROOM_LINE_TOP)
	root.add_child(box)
	_room_label = UiKit.text_label(Loc.t(&"HUD_ROOM", [1]), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_room_label)
	_room_detail = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_room_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_room_detail)
	_room_box = box


## Weapon block (G3): two small slots, then two short lines: name + values, and the keys as caps
## with captions and cooldown bars ([Q] Bogen · [RMB] Wirbelschlag ▬ · [Space] Dash ▬).
func _build_weapons(root: Control) -> void:
	var frame := hud_frame()
	frame.name = "WeaponBlock"
	frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	frame.offset_left = UiKit.px(WEAPON_MARGIN)
	frame.offset_bottom = -UiKit.px(WEAPON_MARGIN)
	root.add_child(frame)
	_weapon_root = frame
	var row := UiKit.hbox(int(UiKit.px(SLOT_GAP)))
	frame.add_child(row)
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var slot_frame := PanelContainer.new()
		slot_frame.name = "Slot%d" % (slot + 1)
		slot_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_frame.custom_minimum_size = Vector2.ONE * slot_size()
		slot_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slot_frame)
		_weapon_panels.append(slot_frame)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.x = UiKit.px(2)
	row.add_child(spacer)
	var text := UiKit.vbox(int(UiKit.px(1)))
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var head := UiKit.hbox(int(UiKit.px(4)))
	text.add_child(head)
	_weapon_name = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_TEXT, true)
	_weapon_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_weapon_name)
	_weapon_stats = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_weapon_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_weapon_stats)
	_weapon_keys = UiKit.hbox(int(UiKit.px(KEY_ROW_GAP)))
	_weapon_keys.name = "Keys"
	text.add_child(_weapon_keys)
	# Plain text of the key line (tools and tests read it; the key caps show it).
	_weapon_hint = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_DISABLED)
	_weapon_hint.visible = false
	text.add_child(_weapon_hint)
	_dash_bar = _cooldown_bar(UiKit.COLOR_SHIELD, DASH_BAR_WIDTH)
	_add_key(ControlsInfo.DASH, Loc.t(&"HUD_DASH")).add_child(_dash_bar)


## Hint line bottom right: key caps with short captions, wrapping right-aligned (G3).
func _build_hint(root: Control) -> void:
	_hint_label = UiKit.text_label(CONTROLS_HINT, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_hint_label.visible = false
	root.add_child(_hint_label)
	_hint_row = HFlowContainer.new()
	_hint_row.name = "HintLine"
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.alignment = FlowContainer.ALIGNMENT_END
	_hint_row.last_wrap_alignment = FlowContainer.LAST_WRAP_ALIGNMENT_END
	_hint_row.add_theme_constant_override("h_separation", int(UiKit.px(HINT_ENTRY_GAP)))
	_hint_row.add_theme_constant_override("v_separation", int(UiKit.px(2)))
	_hint_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_row.offset_left = -UiKit.px(WEAPON_MARGIN + HINT_MAX_WIDTH)
	_hint_row.offset_right = -UiKit.px(WEAPON_MARGIN)
	_hint_row.offset_bottom = -UiKit.px(WEAPON_MARGIN)
	_hint_row.offset_top = _hint_row.offset_bottom
	root.add_child(_hint_row)


## Compact HUD frame: panel_dark at HUD_PIXEL (thin rim), slightly see-through.
static func hud_frame() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", hud_frame_style())
	frame.self_modulate.a = FRAME_ALPHA
	return frame


static var _frame_style: StyleBoxTexture = null


static func hud_frame_style() -> StyleBoxTexture:
	if _frame_style == null:
		_frame_style = StyleBoxTexture.new()
		_frame_style.texture = UiKit.upscale(UiKit.PANEL_DARK_TEXTURE, HUD_PIXEL)
		_frame_style.set_texture_margin_all(UiKit.PANEL_BORDER * HUD_PIXEL)
		_frame_style.content_margin_left = UiKit.px(FRAME_PADDING.y)
		_frame_style.content_margin_right = UiKit.px(FRAME_PADDING.y)
		_frame_style.content_margin_top = UiKit.px(FRAME_PADDING.x)
		_frame_style.content_margin_bottom = UiKit.px(FRAME_PADDING.x)
	return _frame_style


## Weapon slot: icon plus padding and a one-art-pixel rim, in screen pixels.
static func slot_size() -> float:
	return ICON_SIZE + float((SLOT_PADDING + 1) * 2 * HUD_PIXEL)


## Slot rim: gold for the active weapon, grey otherwise (no nine-patch, it would be too thick).
static func slot_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiKit.COLOR_BG
	style.border_color = UiKit.COLOR_GOLD if active else UiKit.COLOR_EMPTY_SLOT
	style.anti_aliasing = false
	style.set_border_width_all(HUD_PIXEL)
	style.set_content_margin_all((SLOT_PADDING + 1) * HUD_PIXEL)
	return style


func _build_village(root: Control) -> void:
	_currency_frame = UiKit.panel(&"dark")
	_currency_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_currency_frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_currency_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_currency_frame.offset_right = -UiKit.px(EDGE_MARGIN)
	_currency_frame.offset_top = UiKit.px(EDGE_MARGIN)
	root.add_child(_currency_frame)
	var currencies := UiKit.hbox(int(UiKit.px(8)))
	_currency_frame.add_child(currencies)
	var gold := UiKit.icon_value(GOLD_ICON, "0", UiKit.COLOR_GOLD, UiKit.SIZE_VALUE, 16.0)
	_village_gold = gold.get_child(1) as Label
	currencies.add_child(gold)
	var crystals := UiKit.icon_value(CRYSTAL_ICON, "0", UiKit.COLOR_TEXT, UiKit.SIZE_VALUE, 16.0)
	_village_crystals = crystals.get_child(1) as Label
	currencies.add_child(crystals)

	_chronicle_frame = UiKit.panel(&"dark")
	_chronicle_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chronicle_frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_chronicle_frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chronicle_frame.offset_left = UiKit.px(EDGE_MARGIN)
	_chronicle_frame.offset_bottom = -UiKit.px(EDGE_MARGIN)
	root.add_child(_chronicle_frame)
	var stats := UiKit.hbox(int(UiKit.px(10)))
	_chronicle_frame.add_child(stats)
	_chronicle_room = _chronicle_entry(stats, TROPHY_ICON)
	_chronicle_kills = _chronicle_entry(stats, SKULL_ICON)
	_chronicle_time = _chronicle_entry(stats, CLOCK_ICON)


func _chronicle_entry(parent: Control, texture: Texture2D) -> Label:
	var entry := UiKit.icon_value(texture, "", UiKit.COLOR_TEXT_SOFT, UiKit.SIZE_KEY_HINT, 12.0)
	parent.add_child(entry)
	return entry.get_child(1) as Label


func _value_label(color: Color) -> Label:
	var result := UiKit.text_label("0", UiKit.SIZE_KEY_HINT, color, true)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return result


## Thin cooldown bar: width in mockup pixels, one HUD art pixel high (0 width = stretch).
func _cooldown_bar(color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(UiKit.px(width), HUD_PIXEL)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", UiKit.bar_style(color))
	bar.add_theme_stylebox_override("background", UiKit.bar_style(UiKit.COLOR_SHADOW))
	return bar


# --- Signal handlers ---

## Hearts in quarter steps; the icons are reused, only their textures change.
func _on_health_changed(current: float, maximum: float) -> void:
	var heart_count := ceili(maximum / HP_PER_HEART)
	var compact := is_compact_hearts(heart_count)
	var shown := 1 if compact else heart_count
	while _heart_icons.size() < shown:
		var icon := UiKit.icon(HEART_TEXTURES[0], HEART_SIZE)
		_hearts.add_child(icon)
		_heart_icons.append(icon)
	while _heart_fills.size() < _heart_icons.size():
		_heart_fills.append(-1)
	for i in _heart_icons.size():
		var icon := _heart_icons[i]
		icon.visible = i < shown
		if not icon.visible:
			continue
		var fill := clampf(current - i * HP_PER_HEART, 0.0, HP_PER_HEART)
		var quarters := roundi(fill / HP_PER_HEART * 4.0)
		icon.texture = HEART_TEXTURES[quarters]
		if _heart_fills[i] >= 0 and _heart_fills[i] != quarters:
			UiKit.bump(icon, BUMP_SCALE)
		_heart_fills[i] = quarters
	_heart_count_label.visible = compact
	if compact:
		_heart_count_label.text = "×%d" % ceili(maxf(0.0, current) / HP_PER_HEART)


## More hearts than HEART_ROWS rows hold: one heart and "×N" instead.
static func is_compact_hearts(heart_count: int) -> bool:
	return heart_count > HEARTS_PER_ROW * HEART_ROWS


func get_visible_heart_count() -> int:
	var count := 0
	for icon in _heart_icons:
		if icon.visible:
			count += 1
	return count


func _on_shield_changed(current: float) -> void:
	_set_value(_shield_label, DamageNumber.format_amount(current))


## Sets a value label; a changed value hops once (R8).
func _set_value(label: Label, text: String) -> void:
	if label.text == text:
		return
	var known := _last_values.has(label)
	label.text = text
	_last_values[label] = text
	if known and _dungeon_mode:
		UiKit.bump(label, BUMP_SCALE)


func _on_gold_changed() -> void:
	_set_value(_gold_label, str(RunManager.get_run_gold() if _dungeon_mode else SaveManager.get_permanent_gold()))
	var crystals := RunManager.get_run_crystals() if _dungeon_mode else SaveManager.get_permanent_crystals()
	_set_value(_crystal_label, str(crystals))
	# Run crystals only matter once there are some (bosses and champions drop them).
	_crystal_label.visible = crystals > 0
	_crystal_icon.visible = crystals > 0
	_village_gold.text = str(SaveManager.get_permanent_gold())
	_village_crystals.text = str(SaveManager.get_permanent_crystals())


## The campfire after a boss is not a room (A6): the detail line names it and the next area.
func set_campfire(active: bool, next_area := "") -> void:
	_campfire_area = next_area if active else ""
	_campfire_active = active
	_on_room_changed(RunManager.get_current_room())


func _on_room_changed(room_index: int) -> void:
	var room := maxi(1, room_index)
	var cycle := floori(float(room - 1) / RoomSequence.CYCLE_LENGTH) + 1
	var type_name := room_type_name(RoomSequence.get_room_type(room))
	if not _room_mode.is_empty():
		type_name = _room_mode
	if _campfire_active:
		type_name = Loc.t(&"HUD_CAMPFIRE_NEXT", [_campfire_area]) if not _campfire_area.is_empty() else Loc.t(&"HUD_CAMPFIRE")
	_room_label.text = Loc.t(&"HUD_ROOM", [room])
	var detail := Loc.t(&"HUD_ROOM_DETAIL", [cycle, type_name])
	if _heal_countdown >= 0:
		# Own line (R8): the room line stays narrow next to the task bar and the boss bar.
		detail += "\n" + Loc.t(&"HUD_NEXT_HEAL", [_heal_countdown])
	_room_detail.text = detail


## The room line sits at the height of the task bar and moves below a bar at the top centre that
## would cover it (wide boss bar, narrow windows).
func _dodge_top_center() -> void:
	var top := UiKit.px(ROOM_LINE_TOP)
	var line := Rect2(_room_box.global_position.x, top, _room_box.size.x, _room_box.size.y)
	for node in get_tree().get_nodes_in_group(TOP_CENTER_GROUP):
		var bar := node as Control
		if bar == null or not bar.is_visible_in_tree():
			continue
		var rect := bar.get_global_rect()
		if rect.intersects(line.grow(UiKit.px(ROOM_LINE_GAP))):
			top = maxf(top, rect.end.y + UiKit.px(ROOM_LINE_GAP))
	if not is_equal_approx(_room_box.position.y, top):
		_room_box.position.y = top


## Translated room type ("Combat", "Special room" ...); RoomSequence's German name if there is no key.
static func room_type_name(room_type: RoomSequence.RoomType) -> String:
	var type_key := String(RoomSequence.RoomType.find_key(room_type)) if RoomSequence.RoomType.values().has(room_type) else ""
	return DataTexts.text_or(StringName(ROOM_TYPE_KEY_PREFIX + type_key), RoomSequence.get_type_name(room_type))


## Composed texts (room, record, weapon line) are rebuilt when the language changes (D-111 §5).
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _room_label != null:
		_on_room_changed(RunManager.get_current_room())
		_refresh_chronicle()
		_build_hint_entries()
		if _player != null and is_instance_valid(_player):
			_refresh_weapon_text(_player.weapon_controller, _player.weapon_controller.get_active_slot())


func _refresh_chronicle() -> void:
	_chronicle_timer = CHRONICLE_REFRESH
	_chronicle_room.text = Loc.t(&"HUD_RECORD", [int(SaveManager.get_stat(StatsTracker.DEEPEST_ROOM))])
	_chronicle_kills.text = str(int(SaveManager.get_stat(StatsTracker.KILLS)))
	_chronicle_time.text = StatsTracker.format_play_time(float(SaveManager.get_stat(StatsTracker.PLAY_TIME)))


func _on_weapons_changed() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var controller := _player.weapon_controller
	var active_slot := controller.get_active_slot()
	for slot in _weapon_panels.size():
		var frame := _weapon_panels[slot]
		for child in frame.get_children():
			child.queue_free()
		_special_bars[slot] = null
		var active := slot == active_slot
		frame.add_theme_stylebox_override("panel", slot_style(active))
		frame.modulate.a = 1.0 if active else INACTIVE_SLOT_ALPHA
		var weapon := controller.get_weapon(slot)
		if weapon == null:
			var empty := UiKit.text_label("%d" % (slot + 1), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			frame.add_child(empty)
			continue
		var icon := UiKit.icon(weapon.icon, ICON_SIZE)
		icon.modulate = weapon.tint
		frame.add_child(icon)
		if weapon.special_name != "":
			frame.add_child(_build_special_bar(slot))
	_refresh_weapon_text(controller, active_slot)
	_update_special_bars()


## Name, effective values and key caps of the active weapon ([Q] Bogen · [RMB] Wirbelschlag ·
## [Space] Dash, R8), names translated through DataTexts (D-111). The plain line stays in _weapon_hint.
func _refresh_weapon_text(controller: WeaponController, active_slot: int) -> void:
	var weapon := controller.get_weapon(active_slot)
	_weapon_name.text = DataTexts.weapon_name(weapon) if weapon != null else "–"
	_weapon_stats.text = DataTexts.weapon_stats_text(controller, weapon) if weapon != null else ""
	var hints: PackedStringArray = []
	if _dash_bar.get_parent() != null:
		_dash_bar.get_parent().remove_child(_dash_bar)
	for child in _weapon_keys.get_children():
		_weapon_keys.remove_child(child)
		child.queue_free()
	_special_key_bar = null
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var other := controller.get_weapon(slot)
		if slot != active_slot and other != null:
			hints.append(Loc.t(&"HUD_KEY_SWITCH", [DataTexts.weapon_name(other)]))
			_add_key(ControlsInfo.SWITCH, DataTexts.weapon_name(other))
	if weapon != null and weapon.special_name != "":
		hints.append(Loc.t(&"HUD_KEY_SPECIAL", [DataTexts.weapon_special_name(weapon)]))
		var special := _add_key(ControlsInfo.SPECIAL, DataTexts.weapon_special_name(weapon))
		_special_key_bar = _cooldown_bar(UiKit.COLOR_GOLD, SPECIAL_BAR_WIDTH)
		special.add_child(_special_key_bar)
	hints.append(Loc.t(&"HUD_KEY_DASH"))
	var dash := _add_key(ControlsInfo.DASH, Loc.t(&"HUD_DASH"))
	dash.add_child(_dash_bar)
	_weapon_hint.text = " · ".join(hints)


## Key cap (symbol of the bound key) + caption in the key line; returns the pair (cooldown bars go
## behind the caption).
func _add_key(control_id: StringName, caption: String) -> HBoxContainer:
	var pair := UiKit.hbox(int(UiKit.px(KEY_PAIR_GAP)))
	var actions := ControlsInfo.actions(control_id)
	if _touch:
		# Touch: the symbol of the on-screen button (same as on the TouchOverlay), no keys.
		var touch_glyph := InputGlyphs.touch_id(control_id)
		if touch_glyph != &"":
			pair.add_child(KeyCap.for_name(String(touch_glyph), HUD_PIXEL))
	elif not actions.is_empty():
		pair.add_child(KeyCap.for_action(actions[0], HUD_PIXEL))
	var label := UiKit.text_label(caption, UiKit.SIZE_EYEBROW, UiKit.COLOR_TEXT_SOFT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pair.add_child(label)
	_weapon_keys.add_child(pair)
	return pair


## Thin cooldown bar along the bottom edge of a slot; full when the special is ready again.
func _build_special_bar(slot: int) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := _cooldown_bar(UiKit.COLOR_GOLD, 0.0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# On the free pixel row between icon and rim.
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_bottom = SLOT_PADDING * HUD_PIXEL
	bar.offset_top = bar.offset_bottom - HUD_PIXEL
	holder.add_child(bar)
	_special_bars[slot] = bar
	return holder


func _update_special_bars() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var controller := _player.weapon_controller
	if _special_key_bar != null and is_instance_valid(_special_key_bar):
		var active_charge := controller.get_special_charge(controller.get_active_slot())
		_special_key_bar.value = active_charge
		_special_key_bar.modulate = Color.WHITE if active_charge >= 1.0 else Color(0.6, 0.6, 0.6)
	for slot in _special_bars.size():
		var bar := _special_bars[slot]
		if bar == null or not is_instance_valid(bar):
			continue
		var charge := controller.get_special_charge(slot)
		bar.value = charge
		# Dimmed while recharging, full brightness when ready.
		bar.modulate = Color.WHITE if charge >= 1.0 else Color(0.6, 0.6, 0.6)
