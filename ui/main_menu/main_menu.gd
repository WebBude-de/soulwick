class_name MainMenu
extends Control
## Main menu (MM1, docs/design screen 13, art/ui/menu/menu.json): night scene with the save's
## character, logo and tagline, menu list on a darkened left edge, gold/crystals bottom left, record
## and version bottom right. Sub panels on the right: Spielstände (slots), Neuer Spielstand
## (name, character, clothing colour), Optionen (OptionsView: sound, display, keys). "Online /
## Gilde" is a greyed-out placeholder. The colour can be changed later in the village (Zuhause,
## "Umkleiden").
##
## Opening the menu copies the save of older builds into slot 1 once (SaveManager). When a slot is
## loaded or created, play_requested is emitted after a short fade; scenes/main.gd starts the game.
## Texts are translation keys (D-111, localization/translations.csv); composed texts (hints with
## numbers, record, key line) are rebuilt on NOTIFICATION_TRANSLATION_CHANGED.

signal play_requested
signal quit_requested

const LOGO_TEXTURE: Texture2D = preload("res://art/ui/logo.png")
const TROPHY_ICON: Texture2D = preload("res://art/ui/trophy_icon.png")
const TAGLINE: StringName = &"MENU_TAGLINE"
## Shown when project.godot has no application/config/version yet.
const FALLBACK_VERSION := "dev"

## Layout in mockup pixels (menu.json "ui").
const LOGO_POSITION := Vector2(24, 16)
const MENU_POSITION := Vector2(24, 100)
const MENU_WIDTH := 140.0
## Darkened left edge: rgba(21,19,31, 0.88 -> 0.6 -> 0) over x 0..250.
const SHADE_WIDTH := 250.0
const CORNER_MARGIN := 8.0
## Sub panels live in this area right of the menu list (x from, x to).
const PANEL_AREA := Vector2(176, 472)
const FADE_TIME := 0.35

const ENTRY_CONTINUE := &"continue"
const ENTRY_SLOTS := &"slots"
const ENTRY_ONLINE := &"online"
const ENTRY_OPTIONS := &"options"
const ENTRY_QUIT := &"quit"

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
var _fade: ColorRect = null
var _starting := false


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
	_build_title()
	_build_list()
	_build_corners()
	_panel_area = Control.new()
	_panel_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel_area)
	_fade = ColorRect.new()
	_fade.color = Color(UiKit.COLOR_BG, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)
	refresh()


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
	if _keys_label != null:
		_keys_label.text = tr(&"MENU_KEYS") % version_text()


func get_list() -> MenuList:
	return _list


func get_open_panel() -> MenuPanel:
	return _panel


func get_background() -> MenuBackground:
	return _background


func is_starting() -> bool:
	return _starting


func _notification(what: int) -> void:
	# Language changed in the options: composed texts (hints, record, key line) are rebuilt.
	# (is_node_ready() is already true inside _ready, so check the nodes themselves.)
	if what == NOTIFICATION_TRANSLATION_CHANGED and _list != null and _status != null:
		refresh()


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
	panel.character_changed.connect(func(data: CharacterData) -> void: _background.set_character(data, Color(0, 0, 0, 0)))
	panel.color_changed.connect(_background.set_character_color)
	_open_panel(panel)
	# Back from the create panel returns to the slot list.
	panel.closed.disconnect(close_panel)
	panel.closed.connect(func() -> void:
		_show_active_look()
		open_slots().select_slot(slot), CONNECT_DEFERRED)
	return panel


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
	_list.active = true
	_status.visible = true
	refresh()


func _on_create_confirmed(slot: int, profile_name: String, character_id: StringName, color: Color) -> void:
	if _starting:
		return
	# Transparent colour = the character's default; it can be changed later at home (village).
	if SaveManager.create_slot(slot, profile_name, character_id, color) != OK:
		push_warning("MainMenu: could not create slot %d." % slot)
		return
	_start()


func _open_panel(panel: MenuPanel) -> void:
	if _panel != null:
		_panel_area.remove_child(_panel)
		_panel.queue_free()
	_panel = panel
	_list.active = false
	_status.visible = false
	# Deferred: the panel may be removed by the handler while one of its buttons is still emitting.
	panel.closed.connect(close_panel, CONNECT_DEFERRED)
	_panel_area.add_child(panel)
	panel.minimum_size_changed.connect(func() -> void: _place_panel(panel))
	_place_panel(panel)
	Sfx.play_ui(self, &"ui_open")


## Centred in the area right of the menu list.
func _place_panel(panel: Control) -> void:
	var area_left := UiKit.px(PANEL_AREA.x)
	var area_right := UiKit.px(PANEL_AREA.y)
	var panel_size := panel.get_combined_minimum_size()
	panel.size = panel_size
	panel.position = Vector2(
		floorf(area_left + (area_right - area_left - panel_size.x) * 0.5),
		floorf((size.y - panel_size.y) * 0.5))


func _start() -> void:
	_starting = true
	_list.active = false
	Sfx.play_ui(self, &"ui_open")
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	tween.tween_callback(play_requested.emit)


func _show_active_look() -> void:
	var slot := SaveManager.get_continue_slot()
	_show_slot_info(SaveManager.get_slot_summary(slot) if slot > 0 else {})


## Bottom-left currencies, bottom-right record and the scene figure of a slot summary ({} = none).
func _show_slot_info(summary: Dictionary) -> void:
	var exists: bool = summary.get("exists", false)
	_currency.visible = exists
	if exists:
		_gold_value.text = str(summary.get("gold", 0))
		_crystal_value.text = str(summary.get("crystals", 0))
		_profile_label.text = summary.get("name", "")
	var record: int = summary.get("deepest_room", 0)
	_record_label.text = (tr(&"MENU_RECORD") % record) if record > 0 else tr(&"MENU_NO_RECORD")
	var data := CharacterCatalog.get_character(summary.get("character", CharacterCatalog.DEFAULT_ID))
	_background.set_character(data, summary.get("color", Color(0, 0, 0, 0)))


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
	add_child(logo)
	var tagline := UiKit.text_label(TAGLINE, UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	tagline.position = Vector2(logo.position.x + UiKit.px(4), logo.position.y + logo.size.y + UiKit.px(2))
	add_child(tagline)


func _build_list() -> void:
	_list = MenuList.new()
	_list.position = UiKit.pxv(MENU_POSITION.x, MENU_POSITION.y)
	_list.custom_minimum_size.x = UiKit.px(MENU_WIDTH)
	_list.size.x = UiKit.px(MENU_WIDTH)
	add_child(_list)
	_list.add_entry(ENTRY_CONTINUE, &"MENU_CONTINUE")
	_list.add_entry(ENTRY_SLOTS, &"MENU_SLOTS")
	_list.add_entry(ENTRY_ONLINE, &"MENU_ONLINE", &"COMMON_SOON", false)
	_list.add_entry(ENTRY_OPTIONS, &"MENU_OPTIONS", &"MENU_OPTIONS_HINT")
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
	add_child(_currency)

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
	_keys_label = UiKit.text_label(tr(&"MENU_KEYS") % version_text(), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	_keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_box.add_child(_keys_label)
	_status.add_child(status_box)
	_anchor_corner(_status, true)
	add_child(_status)


## "v0.4.0" from project.godot (application/config/version) or the fallback.
static func version_text() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return "v" + version if not version.is_empty() else FALLBACK_VERSION


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
