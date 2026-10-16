class_name VillageUI
extends CanvasLayer
## Village building dialogs (D-078): Schmiede (permanent upgrades), Handelsposten (Proviant only,
## no crystal exchange since D-087), Chronik (statistics), Gilde (the online menu of D-147, OnlineMenu:
## quick game with a room code on the relay and the player's guilds with guild rooms; the same menu
## as "Online spielen" in the main menu) and Zuhause with the profile editor (D-152: name, figure and
## colours of the player, the same editor as the mirror next to it, the first start and the lobby).
## Created by Village; every dialog is a Modal and pauses the village while open (single player
## only: in a room the world runs on, GameMode.pauses_for_menus).
## D-087: on the first visit a building explains itself (show_intro, "Verstanden"), its role
## sentence stays as dialog subtitle and the info button next to the title shows the explanation again.
## Locked forge upgrades (MetaUnlocks) are not shown; one line with a lock says when more open.
## Short non-blocking notices (show_notice): "Neu freigeschaltet" and "Öffnet nach …" at locked doors.
## Texts come from localization/translations.csv (D-111) and are resolved when a dialog is built.

const PAUSE_VILLAGE_DIALOG: StringName = &"village_dialog"
const PAUSE_VILLAGE_INTRO: StringName = &"village_intro"
const CARD_WIDTH := 240.0
const INTRO_TEXT_WIDTH := 440.0
const NPC_PORTRAIT_SCALE := 3.0
## Width of the profile editor in the village dialogs (mockup px).
const PROFILE_EDITOR_WIDTH := 262.0
const GOLD_ICON: Texture2D = preload("res://art/ui/gold_icon.png")
const CRYSTAL_ICON: Texture2D = preload("res://art/ui/crystal_icon.png")
const INFO_ICON: Texture2D = preload("res://art/ui/icon_info.png")
const LOCK_ICON: Texture2D = preload("res://art/ui/icon_lock.png")
## Notice at the top of the screen: seconds visible (plus fade), fade time, top margin in px
## (R7, 07_ui.md: below the HUD row, whose gold panel ends at about 90 px).
const NOTICE_TIME := 4.0
const NOTICE_FADE := 0.4
const NOTICE_TOP := 104.0
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
## Chronicle rows: stat id -> translation key of its caption (D-111).
const STAT_ROWS := [
	[StatsTracker.RUNS, &"VILLAGE_UI_STAT_RUNS"],
	[StatsTracker.DEATHS, &"VILLAGE_UI_STAT_DEATHS"],
	[StatsTracker.EXITS, &"VILLAGE_UI_STAT_EXITS"],
	[StatsTracker.DEEPEST_ROOM, &"VILLAGE_UI_STAT_DEEPEST_ROOM"],
	[StatsTracker.ROOMS_CLEARED, &"VILLAGE_UI_STAT_ROOMS_CLEARED"],
	[StatsTracker.KILLS, &"VILLAGE_UI_STAT_KILLS"],
	[StatsTracker.CHAMPIONS, &"VILLAGE_UI_STAT_CHAMPIONS"],
	[StatsTracker.BOSSES, &"VILLAGE_UI_STAT_BOSSES"],
	[StatsTracker.GOLD_EARNED, &"VILLAGE_UI_STAT_GOLD_EARNED"],
	[StatsTracker.GOLD_BANKED, &"VILLAGE_UI_STAT_GOLD_BANKED"],
	[StatsTracker.BEST_RUN_GOLD, &"VILLAGE_UI_STAT_BEST_RUN_GOLD"],
	[StatsTracker.CRYSTALS_EARNED, &"VILLAGE_UI_STAT_CRYSTALS_EARNED"],
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
## The online menu of the open guild dialog (null otherwise).
var _online_menu: OnlineMenu = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_notice_root = Control.new()
	_notice_root.name = "NoticeRoot"
	_notice_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_notice_root)
	_resume_lobby.call_deferred()


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
		row.add_child(UiKit.label(MetaProgression.get_upgrade_stat(MetaProgression.ARSENAL), 16))
		var chosen := MetaProgression.get_second_weapon()
		for weapon_id in weapons:
			var pick := UiKit.button(MetaProgression.get_weapon_name(weapon_id), func() -> void:
				MetaProgression.set_second_weapon(weapon_id)
				refresh.call())
			pick.disabled = weapon_id == chosen
			row.add_child(pick)
		body.add_child(row)


func _forge_card(id: StringName, refresh: Callable) -> Control:
	var level := MetaProgression.get_level(id)
	var max_level := MetaProgression.get_max_level(id)
	var box := _card(UPGRADE_ICONS.get(id), MetaProgression.get_upgrade_name(id), MetaProgression.get_upgrade_summary(id))
	# Real values instead of "+1 je Stufe" (D-087): "Max-HP 6 → 7".
	var step := UiKit.wrapped_label(MetaProgression.describe_level_step(id, level), CARD_WIDTH - 40.0, 16, UiKit.ACCENT_COLOR)
	step.name = "StepLabel"
	box.add_child(step)
	var level_text := Loc.t(&"VILLAGE_UI_LEVEL", [level, max_level])
	if id == MetaProgression.ARSENAL and level > 0:
		level_text += " · %s" % MetaProgression.get_weapon_name(MetaProgression.get_second_weapon())
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
	body.add_child(_section_title(Loc.t(&"VILLAGE_UI_PROVISIONS")))
	var grid := _grid(3)
	body.add_child(grid)
	for id in MetaProgression.BOOST_ORDER:
		var box := _card(BOOST_ICONS.get(id), MetaProgression.get_boost_name(id), MetaProgression.get_boost_effect(id))
		var pending := SaveManager.has_pending_boost(id)
		var price := MetaProgression.get_boost_price(id)
		var price_text := Loc.t(&"VILLAGE_UI_PRICE_CRYSTAL" if price == 1 else &"VILLAGE_UI_PRICE_CRYSTALS", [price])
		var button := UiKit.button(Loc.t(&"VILLAGE_UI_PACKED") if pending else price_text, func() -> void:
			if MetaProgression.try_buy_boost(id):
				Sfx.play_ui(self, &"coin")
			refresh.call())
		button.disabled = not MetaProgression.can_buy_boost(id)
		box.add_child(button)
		grid.add_child(box.get_parent())
	body.add_child(UiKit.label(Loc.t(&"VILLAGE_TRADER_HINT_2"), 14, UiKit.MUTED_COLOR))


# --- Chronik ---

func open_chronicle() -> void:
	await _open(VillageBuildings.CHRONICLE, _build_chronicle)


func _build_chronicle(body: VBoxContainer, _refresh: Callable) -> void:
	var grid := _grid(2)
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for row in STAT_ROWS:
		grid.add_child(UiKit.label(Loc.t(row[1]), 17))
		var value := UiKit.label(str(int(SaveManager.get_stat(row[0]))), 17, UiKit.ACCENT_COLOR)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
	grid.add_child(UiKit.label(Loc.t(&"VILLAGE_UI_STAT_PLAY_TIME"), 17))
	var time := UiKit.label(StatsTracker.format_play_time(float(SaveManager.get_stat(StatsTracker.PLAY_TIME))), 17, UiKit.ACCENT_COLOR)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(time)
	var frame := UiKit.panel(&"dark")
	frame.add_child(grid)
	body.add_child(frame)


# --- Gilde ---

## skip_intro: opened by a room wish of the main menu (the explanation waits for the next visit).
func open_guild(skip_intro := false) -> void:
	await _open(VillageBuildings.GUILD, _build_guild, skip_intro)
	_online_menu = null


## The online menu (D-147). It rebuilds itself on lobby and guild changes, so the dialog body is
## built only once; Esc goes back inside the menu first (Modal.input_handler).
func _build_guild(body: VBoxContainer, _refresh: Callable) -> void:
	var lobby := LobbyClient.of(self)
	if lobby == null:
		return
	_online_menu = OnlineMenu.create(lobby, null, OnlineMenu.DEFAULT_WIDTH, OnlineMenu.VILLAGE_CONTENT_HEIGHT)
	body.add_child(_online_menu)
	if _open_modal != null:
		_open_modal.input_handler = _online_menu.handle_input


## The online menu of the open guild dialog (null if none), for tests and tools.
func get_online_menu() -> OnlineMenu:
	return _online_menu if _online_menu != null and is_instance_valid(_online_menu) else null


## After a room was entered or ended the village is reloaded: reopen the room dialog for the
## player who opened it, or explain why the room closed.
func _resume_lobby() -> void:
	# "Online spielen" in the main menu: create or join the room now and show it.
	if LobbyClient.has_pending_launch():
		var launch := LobbyClient.take_launch()
		var client := LobbyClient.of(self)
		if client != null:
			client.run_launch(launch)
			open_guild(true)
		return
	var lobby := LobbyClient.find(self)
	if lobby == null:
		return
	# Guild runs: "+21 Gold für [DOCHT]" once the report was answered (now or later, D-147).
	if lobby.net_run != null:
		if not lobby.net_run.guild_payout_noticed.is_connected(_on_guild_payout):
			lobby.net_run.guild_payout_noticed.connect(_on_guild_payout)
		var payout := lobby.net_run.take_payout_notice()
		if not payout.is_empty():
			_on_guild_payout(payout)
	var notice := lobby.take_notice()
	if not notice.is_empty():
		var lines: Array[String] = [Loc.t(StringName(notice))]
		show_notice(Loc.t(&"LOBBY_SESSION_ENDED"), lines)
	elif lobby.is_in_room() and lobby.resume_dialog:
		lobby.resume_dialog = false
		# Reopened by itself: the explanation waits for a visit of the player's own.
		open_guild(true)


## A guild run paid into the guild treasury: a short notice at the top (the host's run report).
func _on_guild_payout(payout: Dictionary) -> void:
	var lobby := LobbyClient.find(self)
	if lobby != null and lobby.net_run != null:
		# Shown now: not again on the next village load.
		lobby.net_run.take_payout_notice()
	var lines: Array[String] = [NetRun.payout_text(payout)]
	if int(payout.get("treasury", -1)) >= 0:
		lines.append(Loc.t(&"GUILD_RUN_TREASURY_NOW", [int(payout.treasury)]))
	show_notice(Loc.t(&"GUILD_TREASURY"), lines, UiKit.GOLD_ICON)


# --- Zuhause and the mirror: the profile editor (D-152) ---

func open_home() -> void:
	await _open(VillageBuildings.HOME, _build_home)


## Name, figure and colours of the player (ProfileEditor). Saving closes the dialog; the player in
## the village follows via SaveManager.profile_changed (in a room the others see it too, NetPlayers).
func _build_home(body: VBoxContainer, _refresh: Callable) -> void:
	var editor := _profile_editor()
	editor.show_cancel = false
	body.add_child(editor)
	var modal := _open_modal
	if modal != null:
		modal.input_handler = editor.handle_input
		editor.saved.connect(modal.finish)
		editor.cancelled.connect(modal.finish)


## The mirror next to Zuhause (VillageMirror): the same editor without the building around it.
func open_mirror() -> void:
	if is_dialog_open():
		return
	_busy = true
	var modal := Modal.create(PAUSE_VILLAGE_DIALOG)
	modal.name = "MirrorModal"
	_open_modal = modal
	modal.content.add_child(_title(Loc.t(&"MIRROR_TITLE")))
	var subtitle := _centered(UiKit.label(Loc.t(&"MIRROR_SUBTITLE"), 16, UiKit.MUTED_COLOR))
	subtitle.name = "Subtitle"
	modal.content.add_child(subtitle)
	var editor := _profile_editor()
	modal.content.add_child(editor)
	modal.input_handler = editor.handle_input
	# Esc goes through the editor (cancel), so a running save is never cut off.
	modal.cancel_allowed = false
	editor.saved.connect(modal.finish)
	editor.cancelled.connect(modal.finish)
	await modal.open(self)
	_open_modal = null
	_busy = false


func _profile_editor() -> ProfileEditor:
	var profile := PlayerProfile.current()
	var editor := ProfileEditor.create(profile.player_name, profile.look, false, PROFILE_EDITOR_WIDTH)
	return editor


## Puts on outfit colour index (PlayerLook palette) and saves the profile; false if it was already
## worn or the index is invalid. Kept for tools (screenshots) from the MM1 wardrobe.
func put_on_color(index: int) -> bool:
	var profile := PlayerProfile.current()
	if index < 0 or index >= PlayerLook.COLOR_COUNT or PlayerLook.get_index(profile.look, PlayerLook.OUTFIT) == index:
		return false
	profile.set_color(PlayerLook.OUTFIT, index)
	profile.save()
	return true


## The editor of the open mirror or Zuhause dialog (null if none), for tests and tools.
func get_profile_editor() -> ProfileEditor:
	if _open_modal == null or not is_instance_valid(_open_modal):
		return null
	return _open_modal.find_child("ProfileEditor", true, false) as ProfileEditor


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
	var confirm := UiKit.button(Loc.t(&"VILLAGE_UI_UNDERSTOOD"), modal.finish)
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
		own.set_look(PlayerProfile.current().look)
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
	show_notice(MetaUnlocks.get_announce_title(), lines)


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
func _open(building_id: StringName, build: Callable, skip_intro := false) -> void:
	if is_dialog_open():
		return
	_busy = true
	if VillageBuildings.needs_intro(building_id) and not skip_intro:
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
	var close := UiKit.button(Loc.t(&"MENU_CLOSE"), modal.finish)
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
	info.tooltip_text = Loc.t(&"VILLAGE_UI_SHOW_INTRO")
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
	# Gold and crystals do not count online (D-081): the guild dialog shows none.
	_currencies.visible = _build != _build_guild
	_build.call(_body, _request_refresh)


func _fill_currencies(row: HBoxContainer) -> void:
	row.add_child(UiKit.icon(GOLD_ICON, 24.0))
	row.add_child(UiKit.label("%d Gold" % SaveManager.get_permanent_gold(), 20, UiKit.ACCENT_COLOR))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	row.add_child(spacer)
	row.add_child(UiKit.icon(CRYSTAL_ICON, 24.0))
	row.add_child(UiKit.label(Loc.t(&"VILLAGE_UI_CRYSTALS", [SaveManager.get_permanent_crystals()]), 20, Color(0.7, 0.85, 1.0)))


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
