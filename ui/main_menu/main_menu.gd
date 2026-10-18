class_name MainMenu
extends Control
## Main menu (MM1, docs/design screen 13, art/ui/menu/menu.json): night scene with the player's
## figure, logo and tagline, menu list on a darkened left edge, gold/crystals of the world
## "Weiterspielen" bottom left, record and version bottom right. Sub panels on the right: Welten
## (save slots, D-152: a slot is a world), Neue Welt (only its name), Figur (ProfilePanel: name and
## look of the player, the same in every world and online), Optionen (OptionsView: sound, display,
## keys) and "Online spielen" (OnlinePanel, D-147: quick game and guilds, the same menu as the
## village's guild building). "Online spielen" is always open (playtest 16.10.2026: needing a world
## first confused players); a room starts in the world of "Weiterspielen", without any world a fresh
## one is created in the first free slot ("Welt 1"). Name and look are the profile (D-152), not the
## world's, and can also be changed in the village (mirror, Zuhause) and in the lobby.
## First start (D-152): without a profile the menu opens "Wie heißt du?" (ProfilePanel, first_start)
## before anything else; the name of the save slots of older builds is suggested once.
## P1-1 "Ein Einstieg statt zwei": when that first "Los geht's" finds no world, a fresh "Welt 1" is
## created (create_default_world, the same as an online game without a world) and the game starts
## straight in the village; the world list stays under "Welten". Players who already have a world
## (older builds) land in the menu as before.
## Creating or joining a room from here loads the save like "Weiterspielen" (or creates the first
## world) and hands the wish to the village of the new game (LobbyClient.request_launch); the room
## starts there as before.
## Invite by link (MP2b, D-190): a start with a room code (InviteLink.take_arrival, from ?room= of
## the browser shell) skips the menu: without a profile the first start asks name and figure on one
## page (ProfilePanel with the invite), then the world of "Weiterspielen" (or a fresh "Welt 1") is
## loaded and the village joins the room at once; the guest login runs on the way (LobbyClient).
##
## Opening the menu copies the save of older builds into slot 1 once (SaveManager). When a slot is
## loaded or created, play_requested is emitted after a short fade; scenes/main.gd starts the game.
## Texts are translation keys (D-111, localization/translations.csv); composed texts (hints with
## numbers, record, key line) are rebuilt on NOTIFICATION_TRANSLATION_CHANGED.
##
## MP4: the footer shows version and build environment ("v0.9.0 dev"); on start an
## OnlineVersionCheck reads GET /public/config in the background. Too old for the API → online
## features locked with "please update" and the website; API unreachable → offline hint, single
## player as always. Command line "-- offline" or online_check = false (tests) skip the check.
##
## Gamepad (P0-2 step 2): D-pad/left stick move (MenuInput debounces the stick and repeats a held
## direction: _process pumps the repeats), A confirms, B goes back; the key line bottom right and
## the panels' footers show the gamepad's buttons while a gamepad is in use (KeyLine).
##
## Phones and touch screens (MobileUi, 17.10.2026): logo, list and corners sit on a stage in the
## safe area that is drawn MobileUi.menu_zoom() times larger. On a phone (zoom > 1) the layout is
## compact: smaller logo, list right under it with entries tall enough to tap, gold and crystals
## bottom right over the record; an open panel takes the middle of the screen alone (list hidden)
## on its own stage, zoomed until its width fits, scrolling when it is still too tall. Touch screens
## get an X on the panel
## (the same as Esc). Sub panels sit in the area right of the list up to the right screen edge (wide
## screens, aspect "expand").

signal play_requested
signal quit_requested

const LOGO_TEXTURE: Texture2D = preload("res://art/ui/logo.png")
const KeyLine := preload("res://ui/widgets/key_line.gd")
const PadNav := preload("res://ui/widgets/pad_nav.gd")
const MobileUi := preload("res://ui/menus/mobile_ui.gd")
const TROPHY_ICON: Texture2D = preload("res://art/ui/trophy_icon.png")
const TAGLINE: StringName = &"MENU_TAGLINE"
## Shown when project.godot has no application/config/version yet.
const FALLBACK_VERSION := "dev"

## Layout in mockup pixels (menu.json "ui").
const LOGO_POSITION := Vector2(24, 16)
## D-152: six entries (Figur) must end above the bottom-left currency panel: list from y 88.
const MENU_POSITION := Vector2(24, 88)
const MENU_WIDTH := 140.0
## Darkened left edge: rgba(21,19,31, 0.88 -> 0.6 -> 0) over x 0..250.
const SHADE_WIDTH := 250.0
const CORNER_MARGIN := 8.0
## Sub panels live in this area right of the menu list (x from, x to).
const PANEL_AREA := Vector2(176, 472)
## Compact layout of phones (mockup pixels): logo at its art size × (ART_SCALE - 1), list right under it.
const LOGO_POSITION_COMPACT := Vector2(16, 8)
const MENU_POSITION_COMPACT := Vector2(16, 58)
const FADE_TIME := 0.35

const ENTRY_CONTINUE := &"continue"
const ENTRY_SLOTS := &"slots"
const ENTRY_PROFILE := &"profile"
const ENTRY_ONLINE := &"online"
const ENTRY_OPTIONS := &"options"
const ENTRY_QUIT := &"quit"

## Run the online version check when the menu opens (tests switch it off: no network).
static var online_check := true
## Open "Wie heißt du?" when the player has no profile yet (tests that do not care switch it off).
static var ask_profile_on_start := true

var _background: MenuBackground = null
var _list: MenuList = null
var _panel_area: Control = null
var _panel: MenuPanel = null
var _currency: PanelContainer = null
var _gold_value: Label = null
var _crystal_value: Label = null
var _profile_label: Label = null
var _status: PanelContainer = null
var _record_label: Label = null
var _keys_label: Label = null
var _keys_line: KeyLine = null
var _fade: ColorRect = null
var _starting := false
var _online_label: Label = null
var _update_link: LinkButton = null
var _online_config: OnlineConfig = null
var _version_check: OnlineVersionCheck = null
var _online_status := OnlineVersionCheck.Status.UNKNOWN
## Logo, tagline, list and corners (zoomed on phones) and the stage of the open panel.
var _stage: Control = null
var _logo: TextureRect = null
var _tagline: Label = null
var _close_button: Button = null
var _compact := false
var _layout_queued := false
var _fade_tween: Tween = null
## Room code of an invite link this start came with, until the game starts ("" = none).
var _invite_code := ""


func _ready() -> void:
	theme = UiKit.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The player's language before the first text is built (also when apply_all did not run yet).
	GameOptions.apply_language()
	# Older builds had one save file: bring it into slot 1 before anything is shown.
	SaveManager.import_legacy_save_into_slot()

	_background = MenuBackground.new()
	add_child(_background)
	add_child(_build_shade())
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)
	_build_title()
	_build_list()
	_build_corners()
	_panel_area = Control.new()
	_panel_area.name = "PanelStage"
	_panel_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel_area)
	_fade = ColorRect.new()
	_fade.color = Color(UiKit.COLOR_BG, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_invite_code = InviteLink.take_arrival()
	# An invite skips the menu: the screen stays dark until the game starts (no flash of the menu).
	if _invite_code.is_empty() or (ask_profile_on_start and PlayerProfile.current().needs_setup()):
		_fade_tween = create_tween()
		_fade_tween.tween_property(_fade, "color:a", 0.0, 0.6)
	refresh()
	get_viewport().size_changed.connect(_queue_layout)
	resized.connect(_queue_layout)
	_status.minimum_size_changed.connect(_queue_layout)
	_layout()
	_start_online_check()
	if ask_profile_on_start and PlayerProfile.current().needs_setup():
		open_profile(true)
	elif not _invite_code.is_empty():
		join_invite.call_deferred()


## Re-reads slots: entry texts, currencies, record and the figure in the scene.
func refresh() -> void:
	var slot := SaveManager.get_continue_slot()
	var used := 0
	for i in range(1, SaveSlots.SLOT_COUNT + 1):
		if SaveManager.has_slot(i):
			used += 1
	if slot > 0:
		var summary := SaveManager.get_slot_summary(slot)
		_list.set_entry(ENTRY_CONTINUE, &"MENU_CONTINUE", summary.get("name", ""))
		_show_slot_info(summary)
	else:
		_list.set_entry(ENTRY_CONTINUE, &"MENU_NEW_GAME", &"MENU_NEW_GAME_HINT")
		_show_slot_info({})
	_list.set_entry(ENTRY_SLOTS, &"MENU_SLOTS", tr(&"MENU_SLOTS_HINT") % [used, SaveSlots.SLOT_COUNT])
	_list.set_entry(ENTRY_PROFILE, &"MENU_PROFILE", PlayerProfile.current().get_display_name())
	_refresh_online_entry()
	if _keys_line != null:
		var build := build_text(_environment_tag())
		_keys_line.set_texts(tr(&"MENU_KEYS") % build, PadNav.text(&"MENU_KEYS_PAD", [build], "%s · {dpad} select · {a} · {b}"))
		_keys_line.set_touch_text(build)
	_show_online_status()


## "Online spielen": always open (also without a world, see _on_online_launch), locked only while
## this build is too old for the API.
func _refresh_online_entry() -> void:
	if _online_status == OnlineVersionCheck.Status.OUTDATED:
		_list.set_entry(ENTRY_ONLINE, &"MENU_ONLINE", &"ONLINE_UPDATE_SHORT", false)
	else:
		_list.set_entry(ENTRY_ONLINE, &"MENU_ONLINE", &"MENU_ONLINE_HINT", true)


func get_list() -> MenuList:
	return _list


func get_open_panel() -> MenuPanel:
	return _panel


func get_background() -> MenuBackground:
	return _background


func is_starting() -> bool:
	return _starting


func get_online_status() -> OnlineVersionCheck.Status:
	return _online_status


func get_online_label() -> Label:
	return _online_label


## Room code of the invite link this start came with ("" if none or already on its way).
func get_invite_code() -> String:
	return _invite_code


func _notification(what: int) -> void:
	# Language changed in the options: composed texts (hints, record, key line) are rebuilt.
	# (is_node_ready() is already true inside _ready, so check the nodes themselves.)
	if what == NOTIFICATION_TRANSLATION_CHANGED and _list != null and _status != null:
		refresh()


## Held D-pad or stick: the next step as an arrow-key event (MenuInput).
func _process(_delta: float) -> void:
	if not _starting:
		MenuInput.pump_repeat()


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if _panel != null:
		if _panel.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if _list.handle_input(event):
		get_viewport().set_input_as_handled()


# --- Actions ---

func activate(id: StringName) -> void:
	if _starting:
		return
	match id:
		ENTRY_CONTINUE:
			var slot := SaveManager.get_continue_slot()
			if slot > 0:
				play_slot(slot)
			else:
				var free := SaveManager.get_free_slot()
				open_create(free if free > 0 else 1)
		ENTRY_SLOTS:
			open_slots()
		ENTRY_PROFILE:
			open_profile(false)
		ENTRY_ONLINE:
			open_online()
		ENTRY_OPTIONS:
			_open_panel(OptionsPanel.new())
		ENTRY_QUIT:
			quit_requested.emit()


func open_slots() -> SlotPanel:
	var panel := SlotPanel.new()
	panel.play_requested.connect(play_slot, CONNECT_DEFERRED)
	panel.create_requested.connect(open_create, CONNECT_DEFERRED)
	panel.slot_deleted.connect(func(_slot: int) -> void: refresh())
	_open_panel(panel)
	_list.select_id(ENTRY_SLOTS)
	return panel


func open_create(slot: int) -> CreateSlotPanel:
	var panel := CreateSlotPanel.create(slot)
	panel.confirmed.connect(_on_create_confirmed, CONNECT_DEFERRED)
	_open_panel(panel)
	# Back from the create panel returns to the slot list.
	panel.closed.disconnect(close_panel)
	panel.closed.connect(func() -> void: open_slots().select_slot(slot), CONNECT_DEFERRED)
	return panel


## "Figur" / first start "Wie heißt du?" (D-152): name and look of the player; the scene figure
## follows the editor live.
func open_profile(first_start := false) -> ProfilePanel:
	var panel := ProfilePanel.create(first_start, _invite_code if first_start else "")
	panel.look_changed.connect(_background.set_look)
	if first_start:
		# Deferred like close_panel (queued first, so the game is already starting when it runs).
		panel.saved.connect(_on_first_profile_saved, CONNECT_DEFERRED)
	_open_panel(panel)
	panel.closed.connect(func() -> void: _background.set_look(PlayerProfile.current().look), CONNECT_DEFERRED)
	if not first_start:
		_list.select_id(ENTRY_PROFILE)
	return panel


## "Los geht's" of the first start (P1-1): without any world, Welt 1 is created and the game starts
## in the village; with a world (older builds) the menu stays open as before.
func _on_first_profile_saved() -> void:
	if not _invite_code.is_empty():
		join_invite()
		return
	if _starting or SaveManager.get_continue_slot() > 0:
		return
	if create_default_world() <= 0:
		push_warning("MainMenu: could not create the first world.")
		return
	_start()


## "Online spielen": quick game and guilds (D-147).
func open_online() -> OnlinePanel:
	var panel := OnlinePanel.new()
	panel.launch_requested.connect(_on_online_launch, CONNECT_DEFERRED)
	_open_panel(panel)
	_list.select_id(ENTRY_ONLINE)
	return panel


## Invite by link (MP2b): straight into the room of the link, in the world of "Weiterspielen" or a
## fresh "Welt 1" (D-161); the village joins it (LobbyClient, via_link: failures with a way out).
func join_invite() -> void:
	if _starting or _invite_code.is_empty():
		return
	var code := _invite_code
	_invite_code = ""
	_on_online_launch({"action": LobbyClient.LAUNCH_JOIN, "code": code, "via_link": true})


## A room from the online menu: the world of "Weiterspielen" is loaded (without any world a fresh
## one is created first, online_world_slot) and the game starts; its village creates or joins the
## room (LobbyClient.take_launch in VillageUI).
func _on_online_launch(launch: Dictionary) -> void:
	if _starting:
		return
	var slot := SaveManager.get_continue_slot()
	var created := false
	if slot <= 0:
		slot = create_default_world()
		if slot <= 0:
			push_warning("MainMenu: could not create a world for the online game.")
			return
		created = true
	var via_link := bool(launch.get("via_link", false))
	LobbyClient.request_launch(str(launch.get("action", "")), str(launch.get("mode", LobbyClient.MODE_QUICK)),
			str(launch.get("guild_id", "")), str(launch.get("guild_name", "")), str(launch.get("code", "")),
			str(launch.get("guild_tag", "")), via_link)
	if not created:
		SaveManager.load_slot(slot)
	_start(via_link)


## A fresh world in the first free slot, like "Neue Welt" with an empty name ("Welt 1"): it explains
## the village (D-087). The first start and an online game without any world both start in it.
## Returns the slot (now the loaded save), 0 if no world could be created.
static func create_default_world() -> int:
	var slot := SaveManager.get_free_slot()
	if slot <= 0 or SaveManager.create_slot(slot) != OK:
		return 0
	return slot


## The world an online game starts in: the one of "Weiterspielen", else the free slot a fresh world
## would get (0 if neither, which cannot happen: no world means every slot is free).
static func online_world_slot() -> int:
	var slot := SaveManager.get_continue_slot()
	return slot if slot > 0 else SaveManager.get_free_slot()


func play_slot(slot: int) -> void:
	if _starting:
		return
	SaveManager.load_slot(slot)
	_start()


func close_panel() -> void:
	if _panel != null:
		_panel_area.remove_child(_panel)
		_panel.queue_free()
		_panel = null
	_remove_close_button()
	_stage.visible = true
	# The first start's "Los geht's" may already be fading into the game.
	_list.active = not _starting
	_status.visible = true
	refresh()


func _on_create_confirmed(slot: int, world_name: String) -> void:
	if _starting:
		return
	if SaveManager.create_slot(slot, world_name) != OK:
		push_warning("MainMenu: could not create slot %d." % slot)
		return
	_start()


func _open_panel(panel: MenuPanel) -> void:
	if _panel != null:
		_panel_area.remove_child(_panel)
		_panel.queue_free()
	_remove_close_button()
	_panel = panel
	_list.active = false
	_status.visible = false
	# Deferred: the panel may be removed by the handler while one of its buttons is still emitting.
	panel.closed.connect(close_panel, CONNECT_DEFERRED)
	_panel_area.add_child(panel)
	if MobileUi.is_touch_screen() and panel.can_close():
		_close_button = Modal.create_close_button(_on_close_pressed)
		_panel_area.add_child(_close_button)
	panel.minimum_size_changed.connect(func() -> void: _place_panel(panel))
	_place_panel(panel)
	Sfx.play_ui(self, &"ui_open")


## Centred in the area right of the menu list (to the right edge of the screen); on phones alone in
## the middle of the safe area at the zoom whose width fits, scrolling when too tall.
func _place_panel(panel: MenuPanel) -> void:
	if panel == null or panel != _panel or not is_inside_tree():
		return
	var viewport := get_viewport()
	var full := Rect2(Vector2.ZERO, size)
	var safe := MobileUi.safe_rect(viewport)
	var zoom := MobileUi.menu_zoom(viewport) if _compact else 1.0
	var close_size := 0.0
	if _close_button != null:
		close_size = maxf(UiKit.px(Modal.CLOSE_SIZE), MobileUi.min_touch_height(viewport, zoom))
	var area := safe
	if _compact:
		area = safe.grow(-maxf(MobileUi.touch_margin(viewport), ceilf(close_size * zoom * Modal.CLOSE_OUTSIDE + UiKit.px(2))))
		var need := panel.get_unlimited_minimum_size()
		zoom = MobileUi.fit_zoom(zoom, Vector2(need.x, 1.0), area.size, MobileUi.device_scale(viewport))
		panel.set_max_height(floorf(area.size.y / zoom))
		if _close_button != null:
			close_size = maxf(UiKit.px(Modal.CLOSE_SIZE), MobileUi.min_touch_height(viewport, zoom))
	MobileUi.place_stage(_panel_area, area, zoom, full)
	_stage.visible = not _compact
	var stage_size := _panel_area.size
	var panel_size := panel.get_combined_minimum_size()
	panel.size = panel_size
	var area_left := 0.0 if _compact else UiKit.px(PANEL_AREA.x)
	var area_right := stage_size.x if _compact else maxf(stage_size.x - UiKit.px(CORNER_MARGIN), area_left + panel_size.x)
	panel.position = Vector2(
		floorf(area_left + (area_right - area_left - panel_size.x) * 0.5),
		floorf((stage_size.y - panel_size.y) * 0.5))
	if not _compact:
		# A panel wider than the area keeps its right edge on screen (16:9: the world list was cut).
		panel.position.x = maxf(0.0, minf(panel.position.x, stage_size.x - UiKit.px(CORNER_MARGIN) - panel_size.x))
	if _close_button != null:
		_close_button.custom_minimum_size = Vector2.ONE * close_size
		_close_button.size = _close_button.custom_minimum_size
		_close_button.position = (panel.position + Vector2(panel_size.x - close_size * (1.0 - Modal.CLOSE_OUTSIDE),
				-close_size * Modal.CLOSE_OUTSIDE)).round()


## The X of a panel: the same as Esc (the panel may use it, e.g. leave the rename field), else close.
func _on_close_pressed() -> void:
	if _panel == null or _starting:
		return
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	if not _panel.handle_input(event):
		_panel.close()


func _remove_close_button() -> void:
	if _close_button != null:
		_close_button.queue_free()
		_close_button = null


# --- Layout (phones, wide screens) ---

func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_layout.call_deferred()


## Stage of logo, list and corners in the safe area; compact on phones (see the class comment).
func _layout() -> void:
	_layout_queued = false
	if not is_inside_tree() or _list == null:
		return
	var viewport := get_viewport()
	var full := Rect2(Vector2.ZERO, size)
	var safe := MobileUi.safe_rect(viewport)
	var zoom := MobileUi.menu_zoom(viewport)
	_compact = zoom > 1.0
	var entries := maxi(1, _list.get_entry_count())
	var item := UiKit.px(MenuList.ITEM_HEIGHT)
	if _compact:
		# The list has to fit under the logo: lower the zoom until it does.
		var need := UiKit.px(MENU_POSITION_COMPACT.y + entries * (MenuList.ITEM_HEIGHT + MenuList.GAP) + CORNER_MARGIN)
		zoom = MobileUi.fit_zoom(zoom, Vector2(1.0, need), safe.size, MobileUi.device_scale(viewport))
		var room := safe.size.y / zoom - UiKit.px(MENU_POSITION_COMPACT.y + CORNER_MARGIN)
		var tap := MobileUi.min_touch_height(viewport, zoom)
		item = clampf(tap, item, floorf(room / entries - UiKit.px(MenuList.GAP)))
	_list.set_item_height(item)
	MobileUi.place_stage(_stage, safe, zoom, full)
	var logo_scale := float(UiKit.ART_SCALE - 1 if _compact else UiKit.ART_SCALE)
	_logo.size = LOGO_TEXTURE.get_size() * logo_scale
	var logo_at := LOGO_POSITION_COMPACT if _compact else LOGO_POSITION
	_logo.position = UiKit.pxv(logo_at.x, logo_at.y)
	_tagline.position = Vector2(_logo.position.x + UiKit.px(4), _logo.position.y + _logo.size.y + UiKit.px(2))
	var list_at := MENU_POSITION_COMPACT if _compact else MENU_POSITION
	_list.position = UiKit.pxv(list_at.x, list_at.y)
	# Phones: gold and crystals bottom right over the record, the list needs the left edge down to
	# the bottom (top right is the moon and, in debug builds, the feedback button).
	if _compact:
		_anchor_corner(_currency, true)
		var lift := _status.get_combined_minimum_size().y + UiKit.px(4)
		_currency.offset_top -= lift
		_currency.offset_bottom -= lift
	else:
		_anchor_corner(_currency, false)
	if _panel != null:
		_place_panel(_panel)


## quick: an invite link (the menu was never shown, or only its first start page): no fade, no sound.
func _start(quick := false) -> void:
	_starting = true
	_list.active = false
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if quick and _fade.color.a >= 1.0:
		play_requested.emit.call_deferred()
		return
	Sfx.play_ui(self, &"ui_open")
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	tween.tween_callback(play_requested.emit)


## Bottom-left world name and currencies, bottom-right record of a slot summary ({} = none); the
## scene figure is the player's profile (D-152).
func _show_slot_info(summary: Dictionary) -> void:
	var exists: bool = summary.get("exists", false)
	_currency.visible = exists
	if exists:
		_gold_value.text = str(summary.get("gold", 0))
		_crystal_value.text = str(summary.get("crystals", 0))
		_profile_label.text = summary.get("name", "")
	var record: int = summary.get("deepest_room", 0)
	_record_label.text = (tr(&"MENU_RECORD") % record) if record > 0 else tr(&"MENU_NO_RECORD")
	if not _panel is ProfilePanel:
		_background.set_look(PlayerProfile.current().look)


# --- Building ---

func _build_shade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UiKit.COLOR_BG, 0.88))
	gradient.set_color(1, Color(UiKit.COLOR_BG, 0.0))
	gradient.add_point(0.6, Color(UiKit.COLOR_BG, 0.6))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	var shade := TextureRect.new()
	shade.texture = texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = UiKit.px(SHADE_WIDTH)
	return shade


func _build_title() -> void:
	var logo := TextureRect.new()
	logo.texture = LOGO_TEXTURE
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo_scale := float(UiKit.ART_SCALE)
	logo.size = LOGO_TEXTURE.get_size() * logo_scale
	logo.position = UiKit.pxv(LOGO_POSITION.x, LOGO_POSITION.y)
	_stage.add_child(logo)
	_logo = logo
	var tagline := UiKit.text_label(TAGLINE, UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	tagline.position = Vector2(logo.position.x + UiKit.px(4), logo.position.y + logo.size.y + UiKit.px(2))
	_stage.add_child(tagline)
	_tagline = tagline


func _build_list() -> void:
	_list = MenuList.new()
	_list.position = UiKit.pxv(MENU_POSITION.x, MENU_POSITION.y)
	_list.custom_minimum_size.x = UiKit.px(MENU_WIDTH)
	_list.size.x = UiKit.px(MENU_WIDTH)
	_stage.add_child(_list)
	_list.add_entry(ENTRY_CONTINUE, &"MENU_CONTINUE")
	_list.add_entry(ENTRY_SLOTS, &"MENU_SLOTS")
	_list.add_entry(ENTRY_PROFILE, &"MENU_PROFILE")
	_list.add_entry(ENTRY_ONLINE, &"MENU_ONLINE", &"MENU_ONLINE_HINT")
	_list.add_entry(ENTRY_OPTIONS, &"MENU_OPTIONS", &"MENU_OPTIONS_HINT")
	# A browser tab cannot close itself; the player closes the tab.
	if not OS.has_feature("web"):
		_list.add_entry(ENTRY_QUIT, &"MENU_QUIT")
	_list.activated.connect(activate)


func _build_corners() -> void:
	_currency = UiKit.panel(&"dark")
	_currency.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var currency_box := UiKit.vbox(int(UiKit.px(1)))
	_profile_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	currency_box.add_child(_profile_label)
	var values := UiKit.hbox(int(UiKit.px(8)))
	var gold := UiKit.icon_value(UiKit.GOLD_ICON, "0", UiKit.COLOR_GOLD, UiKit.SIZE_VALUE)
	_gold_value = gold.get_child(1) as Label
	values.add_child(gold)
	var crystals := UiKit.icon_value(UiKit.CRYSTAL_ICON, "0", UiKit.COLOR_CRYSTAL, UiKit.SIZE_VALUE)
	_crystal_value = crystals.get_child(1) as Label
	values.add_child(crystals)
	currency_box.add_child(values)
	_currency.add_child(currency_box)
	_anchor_corner(_currency, false)
	_stage.add_child(_currency)

	_status = UiKit.panel(&"dark")
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var status_box := UiKit.vbox(int(UiKit.px(1)))
	var record_row := UiKit.hbox(int(UiKit.px(4)))
	record_row.alignment = BoxContainer.ALIGNMENT_END
	record_row.add_child(UiKit.pixel_icon(TROPHY_ICON, 12.0))
	_record_label = UiKit.text_label("", UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true)
	_record_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	record_row.add_child(_record_label)
	status_box.add_child(record_row)
	_keys_line = KeyLine.new()
	_keys_line.name = "Keys"
	_keys_line.setup(UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED, HORIZONTAL_ALIGNMENT_RIGHT)
	_keys_label = _keys_line.label
	_keys_label.text = tr(&"MENU_KEYS") % build_text(_environment_tag())
	status_box.add_child(_keys_line)
	_online_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	_online_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_online_label.visible = false
	status_box.add_child(_online_label)
	_update_link = LinkButton.new()
	_update_link.focus_mode = Control.FOCUS_NONE
	_update_link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	_update_link.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_EYEBROW))
	_update_link.add_theme_color_override("font_color", UiKit.COLOR_GOLD)
	_update_link.size_flags_horizontal = Control.SIZE_SHRINK_END
	_update_link.visible = false
	status_box.add_child(_update_link)
	_status.add_child(status_box)
	_anchor_corner(_status, true)
	_stage.add_child(_status)


## "v0.4.0" from project.godot (application/config/version) or the fallback.
static func version_text() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return "v" + version if not version.is_empty() else FALLBACK_VERSION


## Version plus build environment for the footer: "v0.9.0 dev", "v0.9.0 local", "v1.0.0" (production).
static func build_text(environment_tag: String) -> String:
	return version_text() if environment_tag.is_empty() else "%s %s" % [version_text(), environment_tag]


func _environment_tag() -> String:
	if _online_config != null:
		return _online_config.get_environment_tag()
	return OnlineConfig.environment_tag(OnlineConfig.build_environment())


# --- Online version check (MP4) ---

func _start_online_check() -> void:
	if not online_check or OS.get_cmdline_user_args().has("offline") or OS.get_cmdline_user_args().has("--offline"):
		return
	_online_config = OnlineConfig.load_default()
	_version_check = OnlineVersionCheck.new()
	_version_check.name = "OnlineVersionCheck"
	_version_check.config = _online_config
	add_child(_version_check)
	_version_check.finished.connect(_on_online_checked)
	_online_status = OnlineVersionCheck.Status.CHECKING
	refresh()
	_version_check.run()


func _on_online_checked(status: OnlineVersionCheck.Status) -> void:
	_online_status = status
	refresh()


## Footer line under the version: checking, ready, offline or "please update" with the website.
func _show_online_status() -> void:
	if _online_label == null:
		return
	var key := &""
	var color := UiKit.COLOR_DISABLED
	match _online_status:
		OnlineVersionCheck.Status.CHECKING:
			key = &"ONLINE_CHECKING"
		OnlineVersionCheck.Status.ONLINE:
			key = &"ONLINE_READY"
		OnlineVersionCheck.Status.OFFLINE:
			key = &"ONLINE_OFFLINE"
			color = UiKit.COLOR_MUTED
		OnlineVersionCheck.Status.OUTDATED:
			key = &"ONLINE_UPDATE"
			color = UiKit.COLOR_GOLD
	_online_label.visible = key != &""
	_online_label.add_theme_color_override("font_color", color)
	if key == &"ONLINE_UPDATE":
		var minimum := OnlineVersionCheck.min_game_version
		_online_label.text = tr(key) % (minimum if not minimum.is_empty() else "?")
	elif key != &"":
		_online_label.text = tr(key)
	var outdated := _online_status == OnlineVersionCheck.Status.OUTDATED
	_update_link.visible = outdated
	if outdated:
		var url := _online_config.get_web_url() if _online_config != null else OnlineConfig.DEFAULT_WEB_URL
		_update_link.uri = url
		_update_link.text = tr(&"ONLINE_UPDATE_LINK") % url.trim_prefix("https://")


func _anchor_corner(control: Control, right: bool) -> void:
	var margin := UiKit.px(CORNER_MARGIN)
	if right:
		control.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		control.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		control.offset_right = -margin
		control.offset_left = -margin
	else:
		control.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		control.grow_horizontal = Control.GROW_DIRECTION_END
		control.offset_left = margin
		control.offset_right = margin
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN
	control.offset_bottom = -margin
	control.offset_top = -margin
