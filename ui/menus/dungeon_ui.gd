class_name DungeonUI
extends CanvasLayer
## Dungeon dialogs: upgrade choice, shop, weapon slot replacement, confirmations and the Tab
## upgrade overview. Every dialog pauses the simulation while open (D-043) and shows effective
## values from the same getters the attacks use (D-034).
## Also non-blocking feedback: banners, the boss bar (name + tier, phase, badges, portrait) and
## first-encounter hint cards for new enemy types, elite kinds and champions (EnemyHints), and the
## first-run controls card (ControlsHint, once per save, UX1).
## Layout follows docs/design screens 02-06, 10 and 11; sizes are mockup pixels (UiKit.px).

const BANNER_TIME := 2.2
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
## Upgrade cards (ui_spec screens.upgrade_pick.cards).
const CARD_SIZE := Vector2(124, 158)
const CARD_GAP := 8.0
const CARD_LIFT := 4.0
## Shop grid (ui_spec screens.shop.grid: 3 columns, gap 6, card height 64). Cards are 148 wide
## (side margin 12 instead of 24) so names like "Durchschlag" fit at 9 px without breaking.
const SHOP_COLUMNS := 3
const SHOP_GAP := 6.0
const SHOP_CARD_SIZE := Vector2(148, 64)
## Columns of a shop card: padding 12 + icon 24 + gaps 10 + text 66 + price 34 = 146.
const SHOP_TEXT_WIDTH := 66.0
const SHOP_PRICE_WIDTH := 34.0
## Weapon comparison panel (ui_spec screens.weapon_room).
const WEAPON_PANEL_WIDTH := 308.0
const WEAPON_COLUMN_GAP := 6.0
## Tab overview panel (ui_spec screens.tab_overview).
const OVERVIEW_SIZE := Vector2(440, 242)
const DIALOG_WIDTH := 220.0
const CHOICE_DIALOG_WIDTH := 250.0
const NUMBER_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]

var context: DungeonContext = null
## Show a hint card the first time an enemy type / elite kind / champion appears.
var auto_enemy_hints := true
## Show the first-run controls card (once per save); tests and tools may switch it off.
var show_controls_hint := true

var _overview: Modal = null
var _banner_root: Control = null
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
var _hint_queue: Array[Dictionary] = []
var _hint_card: Control = null
var _controls_hint: ControlsHint = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_banner()
	_build_boss_bar()
	_build_hint_root()
	get_tree().node_added.connect(_on_node_added)
	# Deferred: the dungeon starts the run after its children are ready.
	start_controls_hint.call_deferred()


## Shows the first-run controls card if this save has not seen it yet. Returns the card or null.
func start_controls_hint() -> ControlsHint:
	if not show_controls_hint or _controls_hint != null or not ControlsHint.should_show():
		return null
	_controls_hint = ControlsHint.new()
	_controls_hint.finished.connect(func() -> void: _controls_hint = null)
	_hint_root.add_child(_controls_hint)
	return _controls_hint


func get_controls_hint() -> ControlsHint:
	return _controls_hint if is_instance_valid(_controls_hint) else null


## Non-blocking title card, e.g. "Raum geschafft!" or a boss name.
func show_banner(title: String, subtitle := "", color := UiKit.ACCENT_COLOR) -> void:
	for child in _banner_root.get_children():
		child.queue_free()
	var box := UiKit.vbox(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.position.y = UiKit.px(45)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var title_label := UiKit.title(title, 16, color)
	box.add_child(title_label)
	if not subtitle.is_empty():
		# Long subtitles (e.g. the run start summary) wrap at a fixed width instead of running off screen.
		var sub := UiKit.text_label(subtitle, UiKit.SIZE_KEY_HINT, UiKit.COLOR_MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var single_line := UiKit.get_font().get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.font_px(UiKit.SIZE_KEY_HINT)).x
		if single_line > UiKit.px(BANNER_SUBTITLE_WIDTH):
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sub.custom_minimum_size.x = UiKit.px(BANNER_SUBTITLE_WIDTH)
		box.add_child(sub)
	_banner_root.add_child(box)
	box.pivot_offset = Vector2(box.size.x * 0.5, UiKit.px(11))
	box.modulate.a = 0.0
	box.scale = Vector2(1.4, 1.4)
	var tween := box.create_tween()
	tween.set_parallel(true)
	tween.tween_property(box, "modulate:a", 1.0, 0.25)
	tween.tween_property(box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(BANNER_TIME)
	tween.chain().tween_property(box, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(box.queue_free)


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
	_hint_queue.append({"title": title, "text": text, "badge": badge})
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


func _show_next_hint() -> void:
	_hint_card = null
	if _hint_queue.is_empty():
		return
	var hint: Dictionary = _hint_queue.pop_front()
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
	card.position.y -= UiKit.px(26)
	card.modulate.a = 0.0
	_hint_card = card
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.25)
	tween.tween_interval(HINT_TIME)
	tween.tween_property(card, "modulate:a", 0.0, 0.4)
	tween.tween_callback(card.queue_free)
	tween.tween_callback(_show_next_hint)


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


# --- Upgrade choice (screen 02) ---

## Lets the player pick exactly one upgrade. Returns null only if offer is empty.
## Click a card (or its "Wählen") or press 1–3 to pick it at once; Enter picks the focused card.
func choose_upgrade(offer: Array[UpgradeData], title: String) -> UpgradeData:
	if offer.is_empty():
		return null
	var modal := Modal.create(GameManager.PAUSE_UPGRADE_CHOICE, &"none")
	modal.cancel_allowed = false
	modal.content.add_theme_constant_override("separation", int(UiKit.px(4)))
	modal.content.add_child(UiKit.title(title, UiKit.SIZE_TITLE_LARGE))
	var subtitle := UiKit.text_label("Wähle ein Upgrade – es gilt für den ganzen Run.", UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal.content.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = UiKit.px(6)
	modal.content.add_child(spacer)
	var row := UiKit.hbox(int(UiKit.px(CARD_GAP)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	modal.content.add_child(row)
	var cards: Array[UiCard] = []
	for i in offer.size():
		var upgrade := offer[i]
		var card := _upgrade_card(upgrade, i, modal.finish.bind(upgrade))
		row.add_child(_lift_holder(card))
		cards.append(card)
		card.pressed.connect(modal.finish.bind(upgrade))
		card.focus_requested.connect(_focus_card.bind(cards, card))
		if i < NUMBER_KEYS.size():
			modal.hotkeys[NUMBER_KEYS[i]] = card.activate
	modal.accept_action = func() -> void:
		for card in cards:
			if card.focused:
				card.activate()
				return
	modal.set_footer("Klicken oder 1–%d wählt sofort · Spiel pausiert" % offer.size())
	return await modal.open(self)


func _upgrade_card(upgrade: UpgradeData, index: int, on_pick: Callable) -> UiCard:
	var card := UiCard.new()
	card.padding = Vector2(8, 6)
	card.custom_minimum_size = UiKit.pxv(CARD_SIZE.x, CARD_SIZE.y)
	var box := UiKit.vbox(int(UiKit.px(4)))
	card.add_child(box)
	var eyebrow := UiKit.eyebrow(UiKit.category_name(upgrade.category), UiKit.category_color(upgrade.category))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	var icon := UiKit.pixel_icon(upgrade.icon, 32.0)
	box.add_child(icon)
	var name_label := UiKit.title(upgrade.display_name, UiKit.SIZE_VALUE, UiKit.COLOR_TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = UiKit.px(CARD_SIZE.x - 16.0)
	box.add_child(name_label)
	var description := UiKit.wrapped_text(upgrade.description, CARD_SIZE.x - 16.0)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(description)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(filler)
	var stacks := context.upgrade_manager.get_stacks(upgrade.id) if context != null else 0
	var stack_label: Label
	if upgrade.is_limited():
		stack_label = UiKit.text_label("%d / %d → %d / %d" % [stacks, upgrade.max_stacks, stacks + 1, upgrade.max_stacks], UiKit.SIZE_BODY, UiKit.COLOR_SUCCESS)
	else:
		stack_label = UiKit.text_label("Stufe %d → %d · unbegrenzt" % [stacks, stacks + 1], UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stack_label)
	var hint := UiKit.hbox(int(UiKit.px(3)))
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_child(UiKit.text_label("[%d]" % (index + 1), UiKit.SIZE_KEY_HINT, UiKit.COLOR_DISABLED))
	hint.add_child(_link_button("Wählen", on_pick))
	box.add_child(hint)
	return card


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


## Text-only button (hint style), e.g. "Wählen" under an upgrade card.
func _link_button(text: String, on_pressed: Callable) -> Button:
	var link := UiKit.button(text, on_pressed)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		link.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	link.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_KEY_HINT))
	link.add_theme_color_override("font_color", UiKit.COLOR_DISABLED)
	link.add_theme_color_override("font_hover_color", UiKit.COLOR_GOLD)
	link.add_theme_color_override("font_pressed_color", UiKit.COLOR_GOLD)
	return link


# --- Shop (screen 04) ---

func open_shop(offers: Array[ShopOffer], player: Player) -> void:
	var modal := Modal.create(GameManager.PAUSE_SHOP, &"none")
	modal.content.add_theme_constant_override("separation", int(UiKit.px(6)))
	modal.content.add_child(UiKit.title("Händler"))
	var gold_badge := UiKit.panel(&"dark")
	gold_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gold_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	gold_badge.offset_right = -UiKit.px(10)
	gold_badge.offset_top = UiKit.px(10)
	modal.add_child(gold_badge)
	var gold_row := UiKit.icon_value(UiKit.GOLD_ICON, "", UiKit.COLOR_GOLD, UiKit.SIZE_VALUE, 16.0)
	var gold_label := gold_row.get_child(1) as Label
	gold_badge.add_child(gold_row)
	var grid := GridContainer.new()
	grid.columns = SHOP_COLUMNS
	grid.add_theme_constant_override("h_separation", int(UiKit.px(SHOP_GAP)))
	grid.add_theme_constant_override("v_separation", int(UiKit.px(SHOP_GAP)))
	modal.content.add_child(grid)
	var close_row := UiKit.hbox(0)
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	close_row.add_child(UiKit.dialog_button("Schließen", "Esc", modal.finish))
	modal.content.add_child(close_row)
	modal.set_footer("Kauf ist atomar: Gold und Ware zusammen · Esc schließt · Spiel pausiert")

	var refresh := func() -> void:
		gold_label.text = str(RunManager.get_run_gold())
		for child in grid.get_children():
			child.queue_free()
		for offer in offers:
			grid.add_child(_shop_card(offer, player, modal))
		var cells := ceili(float(maxi(offers.size(), 1)) / SHOP_COLUMNS) * SHOP_COLUMNS
		for i in range(offers.size(), cells):
			var empty := DashedBox.new()
			empty.caption = "kein %d. Angebot" % (i + 1)
			empty.custom_minimum_size = UiKit.pxv(SHOP_CARD_SIZE.x, SHOP_CARD_SIZE.y)
			grid.add_child(empty)
	modal.set_meta(&"refresh", refresh)
	refresh.call()
	await modal.open(self)


func _shop_card(offer: ShopOffer, player: Player, modal: Modal) -> Control:
	var card := UiCard.new()
	card.padding = Vector2(5, 6)
	card.custom_minimum_size = UiKit.pxv(SHOP_CARD_SIZE.x, SHOP_CARD_SIZE.y)
	var row := UiKit.hbox(int(UiKit.px(5)))
	card.add_child(row)
	var offer_icon := UiKit.pixel_icon(offer.get_icon(), 24.0)
	if offer.kind == ShopOffer.Kind.WEAPON:
		offer_icon.modulate = offer.weapon.tint
	row.add_child(offer_icon)
	var text := UiKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var eyebrow := _shop_eyebrow(offer)
	var eyebrow_label := UiKit.eyebrow(eyebrow[0], eyebrow[1])
	eyebrow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eyebrow_label.custom_minimum_size.x = UiKit.px(SHOP_TEXT_WIDTH)
	text.add_child(eyebrow_label)
	var title := UiKit.text_label(offer.get_title(), UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = UiKit.px(SHOP_TEXT_WIDTH)
	text.add_child(title)
	var description := offer.get_description()
	if offer.kind == ShopOffer.Kind.WEAPON:
		description = UiKit.weapon_stats_text(player.weapon_controller, offer.weapon)
	text.add_child(UiKit.wrapped_text(description, SHOP_TEXT_WIDTH, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))

	var preview_slot := _preview_slot(offer, player)
	var affordable := RunManager.get_run_gold() >= offer.price
	var can_buy := not offer.sold and context.economy.can_purchase(offer, player, context.upgrade_manager, preview_slot)
	var status := "kaufen"
	var status_color := UiKit.COLOR_MUTED
	if offer.sold:
		status = "Verkauft"
	elif not affordable:
		status = "zu wenig Gold"
		status_color = UiKit.COLOR_DANGER
	elif not can_buy:
		status = _unavailable_text(offer)
	elif offer.kind == ShopOffer.Kind.WEAPON and player.weapon_controller.find_free_slot() < 0:
		status = "Slot ersetzen"
		status_color = UiKit.COLOR_GOLD
	var price_box := UiKit.vbox(int(UiKit.px(1)))
	price_box.alignment = BoxContainer.ALIGNMENT_CENTER
	price_box.custom_minimum_size.x = UiKit.px(SHOP_PRICE_WIDTH)
	var price := UiKit.icon_value(UiKit.GOLD_ICON, str(offer.price), UiKit.COLOR_DANGER if not affordable and not offer.sold else UiKit.COLOR_GOLD, UiKit.SIZE_VALUE, 12.0)
	price.alignment = BoxContainer.ALIGNMENT_END
	price_box.add_child(price)
	var status_label := UiKit.text_label(status, UiKit.SIZE_EYEBROW, status_color)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = UiKit.px(SHOP_PRICE_WIDTH)
	price_box.add_child(status_label)
	row.add_child(price_box)

	card.disabled = not can_buy
	card.pressed.connect(_on_buy_pressed.bind(offer, player, modal))
	card.focus_requested.connect(func() -> void: card.focused = true)
	card.mouse_exited.connect(func() -> void: card.focused = false)
	return card


## Short reason why an affordable offer cannot be bought right now.
func _unavailable_text(offer: ShopOffer) -> String:
	match offer.kind:
		ShopOffer.Kind.HEAL:
			return "HP voll"
		ShopOffer.Kind.UPGRADE:
			return "am Limit"
	return "nicht möglich"


## Eyebrow text and colour for a shop offer: "Upgrade · Attribut", "Waffe", "Heilung", "Schild".
func _shop_eyebrow(offer: ShopOffer) -> Array:
	match offer.kind:
		ShopOffer.Kind.UPGRADE:
			return ["Upgrade · %s" % UiKit.category_name(offer.upgrade.category), UiKit.category_color(offer.upgrade.category)]
		ShopOffer.Kind.WEAPON:
			return ["Waffe", UiKit.COLOR_WEAPON]
		ShopOffer.Kind.HEAL:
			return ["Heilung", UiKit.COLOR_DANGER]
	return ["Schild", UiKit.COLOR_SHIELD]


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
	var modal := Modal.create(GameManager.PAUSE_WEAPON_CHOICE)
	modal.cancel_result = -1
	modal.frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", 8, 10))
	modal.set_width(WEAPON_PANEL_WIDTH)
	var header := UiKit.hbox(int(UiKit.px(8)))
	var title := UiKit.text_label("Waffe ersetzen?", 12, UiKit.COLOR_GOLD, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var hint := UiKit.wrapped_text("Beide Slots sind belegt. Welche Waffe soll weg?", 110.0, UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(hint)
	modal.content.add_child(header)
	var columns := UiKit.hbox(int(UiKit.px(WEAPON_COLUMN_GAP)))
	modal.content.add_child(columns)
	var offer := UiKit.panel(&"gold")
	offer.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold", 6, 6))
	offer.add_child(_weapon_column(new_weapon, controller, "Angebot", UiKit.COLOR_GOLD, "Neu"))
	offer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(offer)
	var cards: Array[UiCard] = []
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var weapon := controller.get_weapon(slot)
		var role := "Slot %d" % (slot + 1)
		if slot == controller.get_active_slot():
			role += " · aktiv"
		var card := UiCard.new()
		card.padding = Vector2(6, 6)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(_weapon_column(weapon, controller, role, UiKit.COLOR_SHIELD, "[%d] ersetzen" % (slot + 1)))
		card.pressed.connect(modal.finish.bind(slot))
		card.focus_requested.connect(_focus_card.bind(cards, card))
		card.mouse_exited.connect(func() -> void: card.focused = false)
		cards.append(card)
		columns.add_child(card)
		modal.hotkeys[NUMBER_KEYS[slot]] = card.activate
	modal.content.add_child(UiKit.wrapped_text("Werte inkl. aktiver Upgrades.", WEAPON_PANEL_WIDTH - 20.0, UiKit.SIZE_BODY, UiKit.COLOR_MUTED))
	var buttons := UiKit.hbox(int(UiKit.px(6)))
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UiKit.dialog_button("Abbrechen", "Esc", modal.finish.bind(-1)))
	modal.content.add_child(buttons)
	return await modal.open(self)


## One comparison column: icon + name, role eyebrow, effective values, key hint.
func _weapon_column(weapon: WeaponData, controller: WeaponController, role: String, role_color: Color, hint: String) -> Control:
	var box := UiKit.vbox(int(UiKit.px(2)))
	if weapon == null:
		box.add_child(UiKit.eyebrow(role, role_color))
		box.add_child(UiKit.text_label("leer", UiKit.SIZE_CARD_NAME, UiKit.COLOR_DISABLED))
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
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(filler)
	box.add_child(UiKit.text_label(hint, UiKit.SIZE_BODY, UiKit.COLOR_DISABLED))
	return box


# --- Dialogs (screens 06 and 10) ---

## Yes/no dialog (portal style: world stays visible). details: optional [[caption, value, color], ...]
## rows such as "Run-Gold" / "Gutschrift (100 %)". Enter = yes, Esc = no.
func confirm(title: String, text: String, yes_text := "Ja", no_text := "Nein", details: Array = []) -> bool:
	var modal := UiDialog.create(GameManager.PAUSE_CONFIRM, DIALOG_WIDTH, title, text)
	modal.cancel_result = false
	modal.set_dimmed(false)
	UiDialog.add_rows(modal, details)
	UiDialog.add_buttons(modal, [
		{"text": yes_text, "sub": "Enter", "result": true, "default": true},
		{"text": no_text, "sub": "Esc", "result": false},
	])
	return await modal.open(self)


## Decision with equal options side by side (room 45: "Aussteigen" vs "Weiter (Endlos)").
## options: [{"text": String, "sub": String}, ...]; returns the chosen index, or -1 on Esc when
## allow_cancel. 1–n pick directly; the first option is the Enter default.
func choose_option(title: String, text: String, details: Array, options: Array, allow_cancel := false, footnote := "") -> int:
	var modal := UiDialog.create(GameManager.PAUSE_CONFIRM, CHOICE_DIALOG_WIDTH, title, text)
	modal.cancel_allowed = allow_cancel
	modal.cancel_result = -1
	UiDialog.add_rows(modal, details)
	var entries: Array = []
	for i in options.size():
		var option: Dictionary = options[i]
		entries.append({"text": option.get("text", ""), "sub": option.get("sub", ""), "result": i, "default": i == 0})
		if i < NUMBER_KEYS.size():
			modal.hotkeys[NUMBER_KEYS[i]] = modal.finish.bind(i)
	UiDialog.add_buttons(modal, entries, false)
	if not footnote.is_empty():
		UiDialog.add_footnote(modal, footnote)
	return await modal.open(self)


# --- Tab overview (screen 05) ---

func show_upgrade_overview() -> void:
	var modal := Modal.create(GameManager.PAUSE_UPGRADE_OVERVIEW)
	_overview = modal
	modal.frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", 10, 12))
	modal.frame.custom_minimum_size = UiKit.pxv(OVERVIEW_SIZE.x, OVERVIEW_SIZE.y)
	var columns := UiKit.hbox(int(UiKit.px(12)))
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal.content.add_child(columns)
	columns.add_child(_overview_upgrades())
	columns.add_child(_overview_values())
	var footer := UiKit.text_label("[Tab] schließen · Spiel pausiert", UiKit.SIZE_BODY, UiKit.COLOR_DISABLED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	modal.content.add_child(footer)
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
	var heading := UiKit.text_label("Upgrades dieses Runs · %d Stacks" % total, UiKit.SIZE_HEADING, UiKit.COLOR_GOLD, true)
	column.add_child(heading)
	if active.is_empty():
		column.add_child(UiKit.text_label("Noch keine Upgrades.", UiKit.SIZE_KEY_HINT, UiKit.COLOR_MUTED))
		return column
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = UiKit.px(OVERVIEW_SIZE.y - 50.0)
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
	column.add_child(UiKit.text_label("Effektive Werte", UiKit.SIZE_HEADING, UiKit.COLOR_GOLD, true))
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
		head.add_child(UiKit.text_label("Slot %d%s" % [slot + 1, " · aktiv" if active else ""], UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED))
		box.add_child(head)
		for line in _weapon_breakdown(controller, weapon):
			box.add_child(UiKit.text_label(line, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
		column.add_child(card)
	var stats := "HP %s / %s · Schild %s (Softcap %s) · Dash %s s" % [
		DamageNumber.format_amount(player.health.get_health()),
		DamageNumber.format_amount(player.health.get_max_health()),
		DamageNumber.format_amount(player.shield.get_shield()),
		DamageNumber.format_amount(ShieldComponent.SOFTCAP_THRESHOLD),
		DamageNumber.format_amount(snappedf(player.dash_cooldown, 0.1))]
	column.add_child(UiKit.wrapped_text(stats, OVERVIEW_SIZE.x * 0.5 - 18.0, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	return column


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
