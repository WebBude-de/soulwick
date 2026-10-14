class_name VillageUI
extends CanvasLayer
## Village building dialogs (D-078): Schmiede (permanent upgrades), Handelsposten (Proviant only,
## no crystal exchange since D-087), Chronik (statistics), Gilde (multiplayer lobby, in preparation)
## and Zuhause with the wardrobe (MM1: clothing colour of the save's character, live preview).
## Created by Village; every dialog is a Modal and pauses the village while open.
## D-087: on the first visit a building explains itself (show_intro, "Verstanden"), its role
## sentence stays as dialog subtitle and the info button next to the title shows the explanation again.
## Locked forge upgrades (MetaUnlocks) are not shown; one line with a lock says when more open.
## Short non-blocking notices (show_notice): "Neu freigeschaltet" and "Öffnet nach …" at locked doors.

const PAUSE_VILLAGE_DIALOG: StringName = &"village_dialog"
const PAUSE_VILLAGE_INTRO: StringName = &"village_intro"
const CARD_WIDTH := 240.0
const INTRO_TEXT_WIDTH := 440.0
const NPC_PORTRAIT_SCALE := 3.0
## Wardrobe preview scale (whole number, character frames are 32 px) and swatch size in px.
const WARDROBE_PREVIEW_SCALE := 5
const WARDROBE_SWATCH := 44.0
const GOLD_ICON: Texture2D = preload("res://art/ui/gold_icon.png")
const CRYSTAL_ICON: Texture2D = preload("res://art/ui/crystal_icon.png")
const INFO_ICON: Texture2D = preload("res://art/ui/icon_info.png")
const LOCK_ICON: Texture2D = preload("res://art/ui/icon_lock.png")
## Notice at the top of the screen: seconds visible (plus fade), fade time, top margin in px.
const NOTICE_TIME := 4.0
const NOTICE_FADE := 0.4
const NOTICE_TOP := 70.0
const NOTICE_TEXT_WIDTH := 520.0
const UPGRADE_ICONS := {
	MetaProgression.VITALITY: preload("res://art/ui/meta_vitality.png"),
	MetaProgression.START_SHIELD: preload("res://art/ui/meta_shield.png"),
	MetaProgression.SHARPNESS: preload("res://art/ui/meta_sharpness.png"),
	MetaProgression.GOLD_GREED: preload("res://art/ui/meta_greed.png"),
	MetaProgression.DASH_TRAINING: preload("res://art/ui/meta_dash.png"),
	MetaProgression.ARSENAL: preload("res://art/ui/meta_arsenal.png"),
}
const BOOST_ICONS := {
	MetaProgression.BOOST_POTION: preload("res://art/ui/upgrade_heal_on_kill.png"),
	MetaProgression.BOOST_UPGRADE: preload("res://art/ui/upgrade_magic_power.png"),
	MetaProgression.BOOST_GOLD: preload("res://art/ui/gold_icon.png"),
}
const WEAPON_NAMES := MetaProgression.WEAPON_NAMES
const STAT_ROWS := [
	[StatsTracker.RUNS, "Runs gestartet"],
	[StatsTracker.DEATHS, "Gefallen"],
	[StatsTracker.EXITS, "Dungeon verlassen"],
	[StatsTracker.DEEPEST_ROOM, "Tiefster Raum"],
	[StatsTracker.ROOMS_CLEARED, "Räume geschafft"],
	[StatsTracker.KILLS, "Besiegte Gegner"],
	[StatsTracker.CHAMPIONS, "Besiegte Champions"],
	[StatsTracker.BOSSES, "Besiegte Bosse"],
	[StatsTracker.GOLD_EARNED, "Gold gesammelt"],
	[StatsTracker.GOLD_BANKED, "Gold gesichert"],
	[StatsTracker.BEST_RUN_GOLD, "Meistes Gold in einem Run"],
	[StatsTracker.CRYSTALS_EARNED, "Seelenkristalle erhalten"],
]

var _open_modal: Modal = null
var _intro_modal: Modal = null
## True from the door until the building dialog is closed (covers the explanation in between).
var _busy := false
var _build: Callable
var _body: VBoxContainer = null
var _currencies: HBoxContainer = null
var _notice_root: Control = null
var _notice: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_notice_root = Control.new()
	_notice_root.name = "NoticeRoot"
	_notice_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_notice_root)


## Enter/Space confirms an open explanation like the "Verstanden" button (Esc does too, via Modal).
func _unhandled_input(event: InputEvent) -> void:
	if _intro_modal != null and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_intro_modal.finish()


func is_dialog_open() -> bool:
	return _busy or _open_modal != null or _intro_modal != null


func is_intro_open() -> bool:
	return _intro_modal != null


## The open explanation or building dialog (null if none), e.g. for tests and tools.
func get_intro_modal() -> Modal:
	return _intro_modal


func get_building_modal() -> Modal:
	return _open_modal


# --- Schmiede ---

func open_forge() -> void:
	await _open(VillageBuildings.FORGE, _build_forge)


func _build_forge(body: VBoxContainer, refresh: Callable) -> void:
	var grid := _grid(3)
	body.add_child(grid)
	# Locked upgrades stay hidden until they open (D-087); one line says when more come.
	for id in MetaUnlocks.get_open_upgrades():
		grid.add_child(_forge_card(id, refresh))
	for event in MetaUnlocks.get_locked_upgrade_events():
		var hint := _lock_row(MetaUnlocks.get_forge_lock_text(event))
		hint.name = "LockedUpgradesHint"
		body.add_child(hint)
	var weapons := MetaProgression.get_available_second_weapons()
	if weapons.size() > 1:
		var row := UiKit.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(UiKit.label("Zweite Startwaffe:", 16))
		var chosen := MetaProgression.get_second_weapon()
		for weapon_id in weapons:
			var pick := UiKit.button(WEAPON_NAMES.get(weapon_id, String(weapon_id)), func() -> void:
				MetaProgression.set_second_weapon(weapon_id)
				refresh.call())
			pick.disabled = weapon_id == chosen
			row.add_child(pick)
		body.add_child(row)


func _forge_card(id: StringName, refresh: Callable) -> Control:
	var info: Dictionary = MetaProgression.UPGRADES[id]
	var level := MetaProgression.get_level(id)
	var max_level := MetaProgression.get_max_level(id)
	var box := _card(UPGRADE_ICONS.get(id), info["name"], info["summary"])
	# Real values instead of "+1 je Stufe" (D-087): "Max-HP 6 → 7".
	var step := UiKit.wrapped_label(MetaProgression.describe_level_step(id, level), CARD_WIDTH - 40.0, 16, UiKit.ACCENT_COLOR)
	step.name = "StepLabel"
	box.add_child(step)
	var level_text := "Stufe %d/%d" % [level, max_level]
	if id == MetaProgression.ARSENAL and level > 0:
		level_text += " · %s" % WEAPON_NAMES.get(MetaProgression.get_second_weapon(), "")
	box.add_child(UiKit.label(level_text, 14, UiKit.MUTED_COLOR))
	var cost := MetaProgression.get_next_cost(id)
	var buy := UiKit.button("Max." if cost < 0 else "%d Gold" % cost, func() -> void:
		if MetaProgression.try_buy(id):
			Sfx.play_ui(self, &"coin")
		refresh.call())
	buy.disabled = not MetaProgression.can_buy(id)
	box.add_child(buy)
	return box.get_parent()


# --- Handelsposten ---

func open_trader() -> void:
	await _open(VillageBuildings.TRADER, _build_trader)


## Proviant only: the crystal exchange was removed (D-087), crystals are spent here and nowhere else.
func _build_trader(body: VBoxContainer, refresh: Callable) -> void:
	body.add_child(_section_title("Proviant (nur für den nächsten Run)"))
	var grid := _grid(3)
	body.add_child(grid)
	for id in MetaProgression.BOOST_ORDER:
		var info: Dictionary = MetaProgression.BOOSTS[id]
		var box := _card(BOOST_ICONS.get(id), info["name"], info["effect"])
		var pending := SaveManager.has_pending_boost(id)
		var price: int = info["price"]
		var button := UiKit.button("Eingepackt" if pending else "%d Kristall%s" % [price, "" if price == 1 else "e"], func() -> void:
			if MetaProgression.try_buy_boost(id):
				Sfx.play_ui(self, &"coin")
			refresh.call())
		button.disabled = not MetaProgression.can_buy_boost(id)
		box.add_child(button)
		grid.add_child(box.get_parent())
	body.add_child(UiKit.label("Seelenkristalle erhältst du von Champions und Bossen.", 14, UiKit.MUTED_COLOR))


# --- Chronik ---

func open_chronicle() -> void:
	await _open(VillageBuildings.CHRONICLE, _build_chronicle)


func _build_chronicle(body: VBoxContainer, _refresh: Callable) -> void:
	var grid := _grid(2)
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for row in STAT_ROWS:
		grid.add_child(UiKit.label(row[1], 17))
		var value := UiKit.label(str(int(SaveManager.get_stat(row[0]))), 17, UiKit.ACCENT_COLOR)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
	grid.add_child(UiKit.label("Spielzeit", 17))
	var time := UiKit.label(StatsTracker.format_play_time(float(SaveManager.get_stat(StatsTracker.PLAY_TIME))), 17, UiKit.ACCENT_COLOR)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(time)
	var frame := UiKit.panel(&"dark")
	frame.add_child(grid)
	body.add_child(frame)


# --- Gilde ---

func open_guild() -> void:
	await _open(VillageBuildings.GUILD, _build_guild)


func _build_guild(body: VBoxContainer, _refresh: Callable) -> void:
	var badge := UiKit.label("IN VORBEREITUNG", 18, Color(1.0, 0.55, 0.35))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(badge)
	var actions := UiKit.hbox(10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var create := UiKit.button("Lobby erstellen", func() -> void: pass)
	create.disabled = true
	create.tooltip_text = "In Vorbereitung"
	actions.add_child(create)
	var address := LineEdit.new()
	address.placeholder_text = "IP-Adresse, z. B. 192.168.0.10"
	address.custom_minimum_size = Vector2(260, 0)
	address.editable = false
	actions.add_child(address)
	var join := UiKit.button("Lobby beitreten (IP)", func() -> void: pass)
	join.disabled = true
	join.tooltip_text = "In Vorbereitung"
	actions.add_child(join)
	body.add_child(actions)

	body.add_child(_section_title("Spieler in der Lobby"))
	var list := UiKit.vbox(4)
	list.add_child(UiKit.label("1.  Du (Host)", 16))
	for i in range(2, 5):
		list.add_child(UiKit.label("%d.  – freier Platz –" % i, 16, UiKit.MUTED_COLOR))
	var frame := UiKit.panel(&"dark")
	frame.add_child(list)
	body.add_child(frame)
	body.add_child(UiKit.wrapped_label("Geplant: bis zu 4 Spieler im lokalen Netzwerk, ein Spieler ist Host. "
		+ "Diese Funktionen sind noch nicht aktiv.", 560.0, 14, UiKit.MUTED_COLOR))


# --- Zuhause: wardrobe (MM1) ---

func open_home() -> void:
	await _open(VillageBuildings.HOME, _build_home)


## Clothing colour of the loaded save: big live preview, one swatch per colour (also keys 1-9).
## A click puts it on and saves; the player in the village follows via SaveManager.profile_changed.
func _build_home(body: VBoxContainer, refresh: Callable) -> void:
	var data := CharacterCatalog.get_active()
	if data == null:
		return
	var current := data.get_color_index(SaveManager.get_character_color())
	var row := UiKit.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	var stage := UiKit.panel(&"dark")
	stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var preview := CharacterPreview.create(WARDROBE_PREVIEW_SCALE)
	preview.name = "WardrobePreview"
	stage.add_child(preview)
	preview.set_character(data, SaveManager.get_character_color())
	row.add_child(stage)

	var side := UiKit.vbox(10)
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(side)
	side.add_child(UiKit.label("Kleiderschrank", 22, UiKit.ACCENT_COLOR))
	side.add_child(UiKit.label("%s · %s" % [data.display_name, data.get_color_name(current)], 16, UiKit.MUTED_COLOR))
	var swatches := _grid(3)
	swatches.name = "Swatches"
	side.add_child(swatches)
	var modal := _open_modal
	for i in data.color_choices.size():
		var choose := func() -> void:
			# Same sounds as the colour choice when creating a save slot (UX1, UiSound).
			if put_on_color(i):
				UiSound.toggle(self)
			else:
				UiSound.error(self)
			refresh.call()
		var swatch := Button.new()
		swatch.name = "Swatch%d" % (i + 1)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2.ONE * WARDROBE_SWATCH
		swatch.tooltip_text = "%s [%d]" % [data.get_color_name(i), i + 1]
		swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var style := StyleBoxFlat.new()
		style.bg_color = data.color_choices[i]
		style.border_color = UiKit.COLOR_GOLD if i == current else UiKit.COLOR_SHADOW
		style.set_border_width_all(5 if i == current else 2)
		for state in ["normal", "hover", "pressed"]:
			swatch.add_theme_stylebox_override(state, style)
		# Hovering previews the colour, leaving shows the worn one again.
		swatch.mouse_entered.connect(func() -> void:
			UiSound.hover(swatch)
			preview.set_color(data.color_choices[i]))
		swatch.mouse_exited.connect(func() -> void: preview.set_color(SaveManager.get_character_color()))
		swatch.pressed.connect(choose)
		swatches.add_child(swatch)
		if modal != null and i < 9:
			modal.hotkeys[KEY_1 + i] = choose
	side.add_child(UiKit.label("Gilt für diesen Spielstand · Tasten 1–%d" % mini(9, data.color_choices.size()), 14, UiKit.MUTED_COLOR))


## Puts on colour index of the active character and saves. Returns false if it was already worn.
func put_on_color(index: int) -> bool:
	var data := CharacterCatalog.get_active()
	if data == null or index < 0 or index >= data.color_choices.size():
		return false
	var color := data.color_choices[index]
	if SaveManager.has_character_color() and SaveManager.get_character_color() == color:
		return false
	SaveManager.set_character_color(color)
	SaveManager.save_game()
	return true


# --- Explanation (D-087) ---

## Shows the building's explanation: NPC, name, the role sentence from D-087 and short hints, closed
## with "Verstanden" (or Esc). Marks it as seen when closed. Also reachable via the info button.
func show_intro(building_id: StringName) -> void:
	if _intro_modal != null or not VillageBuildings.has_building(building_id):
		return
	var modal := Modal.create(PAUSE_VILLAGE_INTRO, &"gold")
	modal.name = "IntroModal"
	_intro_modal = modal
	var row := UiKit.hbox(18)
	row.add_child(_npc_portrait(building_id))
	var text := UiKit.vbox(8)
	var header := UiKit.hbox(8)
	header.add_child(UiKit.icon(INFO_ICON, 28.0))
	header.add_child(UiKit.label(VillageBuildings.get_display_name(building_id), 28, UiKit.ACCENT_COLOR))
	text.add_child(header)
	var role := UiKit.wrapped_label(VillageBuildings.get_role(building_id), INTRO_TEXT_WIDTH, 20)
	role.name = "RoleLabel"
	text.add_child(role)
	for hint in VillageBuildings.get_hints(building_id):
		text.add_child(UiKit.wrapped_label("• " + hint, INTRO_TEXT_WIDTH, 15, UiKit.MUTED_COLOR))
	row.add_child(text)
	modal.content.add_child(row)
	var confirm := UiKit.button("Verstanden", modal.finish)
	confirm.name = "ConfirmButton"
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	modal.content.add_child(confirm)
	await modal.open(self)
	_intro_modal = null
	VillageBuildings.mark_intro_seen(building_id)


## The building's NPC, animated, in a dark frame (empty frame if the sprite is missing). Zuhause has
## no NPC: it shows the player's own character.
func _npc_portrait(building_id: StringName) -> Control:
	var frame := UiKit.panel(&"dark")
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if building_id == VillageBuildings.HOME:
		var own := CharacterPreview.create(int(NPC_PORTRAIT_SCALE))
		own.name = "OwnPortrait"
		frame.add_child(own)
		own.set_character(CharacterCatalog.get_active(), SaveManager.get_character_color())
		return frame
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(32, 32) * NPC_PORTRAIT_SCALE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(holder)
	var frames := VillageBuildings.get_npc_frames(building_id)
	if frames != null and frames.has_animation(&"idle"):
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.scale = Vector2.ONE * NPC_PORTRAIT_SCALE
		sprite.position = holder.custom_minimum_size * 0.5
		holder.add_child(sprite)
		sprite.play(&"idle")
	return frame


# --- Notices (D-087: unlocks, locked doors) ---

## "Neu freigeschaltet" with one line per opened thing (MetaUnlocks.take_announcements()).
func show_unlocks(lines: Array[String]) -> void:
	if lines.is_empty():
		return
	Sfx.play_ui(self, &"upgrade")
	show_notice(MetaUnlocks.ANNOUNCE_TITLE, lines)


## A locked building's door: name with a lock and "Öffnet nach …".
func show_locked(building_id: StringName) -> void:
	var text := MetaUnlocks.get_building_lock_text(building_id)
	if text.is_empty():
		return
	Sfx.play_ui(self, &"ui_click")
	show_notice(VillageBuildings.get_display_name(building_id), [text + "."], LOCK_ICON)


## Short card at the top that fades out by itself; never blocks or pauses. A new one replaces it.
func show_notice(title: String, lines: Array[String], icon: Texture2D = null) -> void:
	if _notice != null and is_instance_valid(_notice):
		_notice.queue_free()
	var card := UiKit.panel(&"gold")
	card.name = "Notice"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiKit.vbox(4)
	var header := UiKit.hbox(8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	if icon != null:
		header.add_child(UiKit.icon(icon, 28.0))
	var title_label := UiKit.label(title, 22, UiKit.ACCENT_COLOR)
	title_label.name = "NoticeTitle"
	header.add_child(title_label)
	box.add_child(header)
	for line in lines:
		var label := UiKit.wrapped_label(line, NOTICE_TEXT_WIDTH, 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_to_group(&"village_notice_line")
		box.add_child(label)
	card.add_child(box)
	_notice_root.add_child(card)
	_notice = card
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.position.y = NOTICE_TOP
	card.modulate.a = 0.0
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, NOTICE_FADE)
	tween.tween_interval(NOTICE_TIME)
	tween.tween_property(card, "modulate:a", 0.0, NOTICE_FADE)
	tween.tween_callback(card.queue_free)


## The visible notice (null if none), for tests and tools.
func get_notice() -> Control:
	return _notice if _notice != null and is_instance_valid(_notice) and not _notice.is_queued_for_deletion() else null


## Lock icon and a muted line, centred.
func _lock_row(text: String) -> Control:
	var row := UiKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.icon(LOCK_ICON, 24.0))
	row.add_child(UiKit.label(text, 15, UiKit.MUTED_COLOR))
	return row


# --- Shared widgets ---

## Opens one building: on the first visit its explanation, then the dialog with title (+ info
## button), the role sentence as subtitle, currency bar, a body built by build(body, refresh) and
## rebuilt whenever refresh is called (after purchases), and a close button. One at a time.
func _open(building_id: StringName, build: Callable) -> void:
	if is_dialog_open():
		return
	_busy = true
	if VillageBuildings.needs_intro(building_id):
		await show_intro(building_id)
	var modal := Modal.create(PAUSE_VILLAGE_DIALOG)
	modal.name = "BuildingModal"
	_open_modal = modal
	_build = build
	modal.content.add_child(_title_row(building_id))
	var subtitle := _centered(UiKit.label(VillageBuildings.get_role(building_id), 16, UiKit.MUTED_COLOR))
	subtitle.name = "Subtitle"
	modal.content.add_child(subtitle)
	_currencies = UiKit.hbox(8)
	_currencies.alignment = BoxContainer.ALIGNMENT_CENTER
	modal.content.add_child(_currencies)
	_body = UiKit.vbox(10)
	modal.content.add_child(_body)
	var close := UiKit.button("Schließen", modal.finish)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	modal.content.add_child(close)
	_rebuild()
	await modal.open(self)
	_open_modal = null
	_body = null
	_currencies = null
	_busy = false


## Building name with an info button that shows the explanation again.
func _title_row(building_id: StringName) -> Control:
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_title(VillageBuildings.get_display_name(building_id)))
	var info := Button.new()
	info.name = "InfoButton"
	info.icon = UiKit.upscale(INFO_ICON, 2)
	info.flat = true
	info.focus_mode = Control.FOCUS_NONE
	info.tooltip_text = "Erklärung zeigen"
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.pressed.connect(func() -> void:
		Sfx.play_ui(info, &"ui_click")
		show_intro(building_id))
	row.add_child(info)
	return row


## Rebuilds the open dialog at the end of the frame (safe to call from a button inside it).
func _request_refresh() -> void:
	_rebuild.call_deferred()


func _rebuild() -> void:
	if not is_instance_valid(_body) or not is_instance_valid(_currencies):
		return
	for row: Control in [_currencies, _body]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	_fill_currencies(_currencies)
	_build.call(_body, _request_refresh)


func _fill_currencies(row: HBoxContainer) -> void:
	row.add_child(UiKit.icon(GOLD_ICON, 24.0))
	row.add_child(UiKit.label("%d Gold" % SaveManager.get_permanent_gold(), 20, UiKit.ACCENT_COLOR))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	row.add_child(spacer)
	row.add_child(UiKit.icon(CRYSTAL_ICON, 24.0))
	row.add_child(UiKit.label("%d Seelenkristalle" % SaveManager.get_permanent_crystals(), 20, Color(0.7, 0.85, 1.0)))


## A dark card with icon, name and effect text; returns the inner VBox (card = get_parent()).
func _card(icon: Texture2D, title: String, effect: String) -> VBoxContainer:
	var card := UiKit.panel(&"dark")
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var box := UiKit.vbox(6)
	card.add_child(box)
	var header := UiKit.hbox(10)
	if icon != null:
		header.add_child(UiKit.icon(icon, 32.0))
	header.add_child(UiKit.label(title, 18, UiKit.ACCENT_COLOR))
	box.add_child(header)
	var text := UiKit.wrapped_label(effect, CARD_WIDTH - 40.0, 14)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	return box


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


func _title(text: String) -> Label:
	var title := UiKit.label(text, 28, UiKit.ACCENT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _section_title(text: String) -> Label:
	var title := UiKit.label(text, 20, UiKit.ACCENT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _centered(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
