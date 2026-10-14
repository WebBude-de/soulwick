class_name Hud
extends CanvasLayer
## Compact edge HUD (D-042, docs/design screen 01 and 12). Displays values pushed via signals; it
## never computes gameplay state.
## Dungeon: hearts in quarter steps + shield + run gold (top left), room and cycle (top right), weapon
## slots with effective values, special and dash cooldown (bottom left).
## Village: village gold + soul crystals (top right) and chronicle values (bottom left).
## All measurements are mockup pixels (480×270) converted with UiKit.px / UiKit.art_px.

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
## Heart size on screen (16 mockup px, whole multiple of the 16 px art).
const HEART_SIZE := 16.0 * UiKit.ART_SCALE
const CONTROLS_HINT := "WASD bewegen · Maus zielen · LMB angreifen · Space Dash · RMB Spezial · Q Waffe · E benutzen · Tab Upgrades · Esc Pause"
## After the first-run controls card (ControlsHint) the key line shrinks to this (UX1); all keys are
## in Esc → Optionen → Steuerung.
const CONTROLS_HINT_SHORT := "Tab Upgrades · Esc Pause und Optionen"

# Layout in mockup pixels (ui_spec.json "hud").
const STATUS_POSITION := Vector2(6, 6)
const HEART_GAP := 2.0
const EDGE_MARGIN := 8.0
const WEAPON_MARGIN := 6.0
const SLOT_SIZE := 28.0
const SLOT_GAP := 4.0
const SLOT_ICON_SIZE := 16.0
const INACTIVE_SLOT_ALPHA := 0.8
const SMALL_ICON_SIZE := 12.0
const HINT_MAX_WIDTH := 200.0
const DASH_BAR_SIZE := Vector2(24, 2)
const CHRONICLE_REFRESH := 1.0

var _player: Player = null
var _dungeon_mode := false
## Rooms until the next regular heal; -1 = unknown (hidden). Set by the dungeon (set_heal_countdown).
var _heal_countdown := -1
## Campfire between two biomes (set by the dungeon via WorldController).
var _campfire_active := false
var _campfire_area := ""

var _status_frame: PanelContainer
var _hearts: HBoxContainer
var _shield_label: Label
var _gold_label: Label
var _crystal_label: Label
var _crystal_icon: TextureRect
var _room_box: VBoxContainer
var _room_label: Label
var _room_detail: Label
var _weapon_root: HBoxContainer
var _weapon_panels: Array[PanelContainer] = []
## Special cooldown bar per weapon slot (null for empty slots).
var _special_bars: Array[ProgressBar] = [null, null]
var _weapon_name: Label
var _weapon_stats: Label
var _weapon_hint: Label
var _dash_bar: ProgressBar
var _hint_label: Label
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
	_hint_label.text = CONTROLS_HINT_SHORT if SaveManager.has_seen(ControlsHint.SEEN_ID) else CONTROLS_HINT


## Hook for the dungeon: rooms until the next regular heal (-1 hides the hint).
func set_heal_countdown(rooms_left: int) -> void:
	_heal_countdown = rooms_left
	_on_room_changed(RunManager.get_current_room())


func _process(delta: float) -> void:
	if not _dungeon_mode:
		_chronicle_timer -= delta
		if _chronicle_timer <= 0.0:
			_refresh_chronicle()
	if _player == null or not is_instance_valid(_player):
		return
	_dash_bar.value = 1.0 - _player.get_dash_cooldown_left() / maxf(0.01, _player.dash_cooldown)
	_update_special_bars()


# --- Builders ---

func _build_status(root: Control) -> void:
	var frame := UiKit.panel(&"dark")
	frame.position = UiKit.pxv(STATUS_POSITION.x, STATUS_POSITION.y)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	_status_frame = frame
	var box := UiKit.vbox(int(UiKit.px(3)))
	frame.add_child(box)
	_hearts = UiKit.hbox(int(UiKit.px(HEART_GAP)))
	box.add_child(_hearts)
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.add_child(UiKit.pixel_icon(SHIELD_ICON, SMALL_ICON_SIZE))
	_shield_label = _value_label(UiKit.COLOR_TEXT)
	_shield_label.custom_minimum_size.x = UiKit.px(14)
	row.add_child(_shield_label)
	row.add_child(UiKit.pixel_icon(GOLD_ICON, SMALL_ICON_SIZE))
	_gold_label = _value_label(UiKit.COLOR_GOLD)
	_gold_label.custom_minimum_size.x = UiKit.px(14)
	row.add_child(_gold_label)
	_crystal_icon = UiKit.pixel_icon(CRYSTAL_ICON, SMALL_ICON_SIZE)
	row.add_child(_crystal_icon)
	_crystal_label = _value_label(UiKit.COLOR_CRYSTAL)
	row.add_child(_crystal_label)
	box.add_child(row)


func _build_room(root: Control) -> void:
	var box := UiKit.vbox(0)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -UiKit.px(EDGE_MARGIN)
	box.offset_top = UiKit.px(EDGE_MARGIN - 2)
	root.add_child(box)
	_room_label = UiKit.text_label("Raum 1", UiKit.SIZE_VALUE, UiKit.COLOR_TEXT, true)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_room_label)
	_room_detail = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	_room_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_room_detail)
	_room_box = box


func _build_weapons(root: Control) -> void:
	var row := UiKit.hbox(int(UiKit.px(SLOT_GAP)))
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = UiKit.px(WEAPON_MARGIN)
	row.offset_bottom = -UiKit.px(WEAPON_MARGIN)
	root.add_child(row)
	_weapon_root = row
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.custom_minimum_size = Vector2.ONE * UiKit.px(SLOT_SIZE)
		row.add_child(frame)
		_weapon_panels.append(frame)
	var text := UiKit.vbox(0)
	text.alignment = BoxContainer.ALIGNMENT_END
	var spacer := Control.new()
	spacer.custom_minimum_size.x = UiKit.px(SLOT_GAP)
	row.add_child(spacer)
	row.add_child(text)
	_weapon_name = UiKit.text_label("", UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	text.add_child(_weapon_name)
	_weapon_stats = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	text.add_child(_weapon_stats)
	var hint_row := UiKit.hbox(int(UiKit.px(4)))
	text.add_child(hint_row)
	_weapon_hint = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_DISABLED)
	hint_row.add_child(_weapon_hint)
	_dash_bar = _cooldown_bar(UiKit.COLOR_SHIELD, DASH_BAR_SIZE)
	hint_row.add_child(_dash_bar)


func _build_hint(root: Control) -> void:
	_hint_label = UiKit.text_label(CONTROLS_HINT, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.offset_left = -UiKit.px(WEAPON_MARGIN + HINT_MAX_WIDTH)
	_hint_label.offset_right = -UiKit.px(WEAPON_MARGIN)
	_hint_label.offset_bottom = -UiKit.px(WEAPON_MARGIN)
	_hint_label.offset_top = _hint_label.offset_bottom - UiKit.px(20)
	root.add_child(_hint_label)


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
	var result := UiKit.text_label("0", UiKit.SIZE_VALUE, color, true)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return result


func _cooldown_bar(color: Color, spec_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = UiKit.pxv(spec_size.x, spec_size.y)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", UiKit.bar_style(color))
	bar.add_theme_stylebox_override("background", UiKit.bar_style(UiKit.COLOR_SHADOW))
	return bar


# --- Signal handlers ---

func _on_health_changed(current: float, maximum: float) -> void:
	for child in _hearts.get_children():
		child.queue_free()
	var heart_count := ceili(maximum / HP_PER_HEART)
	for i in heart_count:
		var fill := clampf(current - i * HP_PER_HEART, 0.0, HP_PER_HEART)
		var quarters := roundi(fill / HP_PER_HEART * 4.0)
		_hearts.add_child(UiKit.icon(HEART_TEXTURES[quarters], HEART_SIZE))


func _on_shield_changed(current: float) -> void:
	_shield_label.text = DamageNumber.format_amount(current)


func _on_gold_changed() -> void:
	_gold_label.text = str(RunManager.get_run_gold() if _dungeon_mode else SaveManager.get_permanent_gold())
	var crystals := RunManager.get_run_crystals() if _dungeon_mode else SaveManager.get_permanent_crystals()
	_crystal_label.text = str(crystals)
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
	var type_name := RoomSequence.get_type_name(RoomSequence.get_room_type(room))
	if _campfire_active:
		type_name = "Lagerfeuer" + (" · weiter: %s" % _campfire_area if not _campfire_area.is_empty() else "")
	_room_label.text = "Raum %d" % room
	var detail := "Zyklus %d · %s" % [cycle, type_name]
	if _heal_countdown >= 0:
		detail += " · nächste Heilung in %d" % _heal_countdown
	_room_detail.text = detail


func _refresh_chronicle() -> void:
	_chronicle_timer = CHRONICLE_REFRESH
	_chronicle_room.text = "Rekord Raum %d" % int(SaveManager.get_stat(StatsTracker.DEEPEST_ROOM))
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
		frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold" if active else &"normal", 0, 0))
		frame.modulate.a = 1.0 if active else INACTIVE_SLOT_ALPHA
		var weapon := controller.get_weapon(slot)
		if weapon == null:
			var empty := UiKit.text_label("[%d]" % (slot + 1), UiKit.SIZE_BODY, UiKit.COLOR_DISABLED)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			frame.add_child(empty)
			continue
		var icon := UiKit.pixel_icon(weapon.icon, SLOT_ICON_SIZE)
		icon.modulate = weapon.tint
		frame.add_child(icon)
		if weapon.special_name != "":
			frame.add_child(_build_special_bar(slot))
	_refresh_weapon_text(controller, active_slot)
	_update_special_bars()


## Name, effective values and key hints of the active weapon ("Q Bogen · RMB Wirbelschlag · Space Dash").
func _refresh_weapon_text(controller: WeaponController, active_slot: int) -> void:
	var weapon := controller.get_weapon(active_slot)
	_weapon_name.text = weapon.display_name if weapon != null else "–"
	_weapon_stats.text = UiKit.weapon_stats_text(controller, weapon) if weapon != null else ""
	var hints: PackedStringArray = []
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var other := controller.get_weapon(slot)
		if slot != active_slot and other != null:
			hints.append("Q %s" % other.display_name)
	if weapon != null and weapon.special_name != "":
		hints.append("RMB %s" % weapon.special_name)
	hints.append("Space Dash")
	_weapon_hint.text = " · ".join(hints)


## Thin cooldown bar along the bottom edge of a slot; full when the special is ready again.
func _build_special_bar(slot: int) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := _cooldown_bar(UiKit.COLOR_GOLD, Vector2(0, 2))
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = UiKit.px(5)
	bar.offset_right = -UiKit.px(5)
	bar.offset_bottom = -UiKit.px(4)
	bar.offset_top = bar.offset_bottom - UiKit.px(2)
	holder.add_child(bar)
	_special_bars[slot] = bar
	return holder


func _update_special_bars() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var controller := _player.weapon_controller
	for slot in _special_bars.size():
		var bar := _special_bars[slot]
		if bar == null or not is_instance_valid(bar):
			continue
		var charge := controller.get_special_charge(slot)
		bar.value = charge
		# Dimmed while recharging, full brightness when ready.
		bar.modulate = Color.WHITE if charge >= 1.0 else Color(0.6, 0.6, 0.6)
