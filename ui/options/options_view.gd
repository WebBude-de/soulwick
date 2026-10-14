class_name OptionsView
extends VBoxContainer
## The options content shared by the main menu ("Optionen" panel) and the pause menu, so both look
## and behave the same (UX1, UX3). Three tabs under the eyebrow: "Allgemein" (Ton: Musik, Effekte,
## Gesamt · Sprache), "Bild" (Anzeige: Fenstermodus, VSync, Helligkeit (R8), Lichteffekte (L1) · Spielgefühl: Bildschirmwackeln,
## Trefferstopp, Schadenszahlen, Blitze reduzieren) and "Tasten" (key overview from ControlsInfo).
## "Zurücksetzen" (all options and volumes, after a confirmation) sits next to "Zurück".
## The view keeps one size whatever tab or row is shown (_fix_layout): every page gets the size of
## the largest one, captions the width of the longest "> caption", the key line the height of its
## longest text. Measured again after a language change.
##
## Keys: ↑/↓ row (the tab strip and the reset button are rows too), ←/→ change (on the tab row:
## switch tab), Enter toggles / next tab / reset, Q/E switch tabs anywhere. Esc is NOT used here
## except to cancel the reset question: the host closes (back_requested is emitted by the "Zurück"
## button only). Hosts forward keys with handle_input(); with listen_unhandled the view reads
## _unhandled_input itself (pause menu modal; children see keys before the modal).
## Music/SFX volumes are global (SaveManager.set_volume, saved on slider release and when the view
## closes); every other option is stored and applied at once (GameOptions).
##
## Texts are translation keys (D-111): Godot re-translates plain labels on a language change, the
## composed ones (captions with cursor, key chips, footer) are rebuilt in _notification.

signal back_requested

## Kept for hosts and tests: CONTROLS = the "Tasten" tab, SETTINGS = the other two.
enum Page { SETTINGS, CONTROLS }
enum Tab { GENERAL, DISPLAY, CONTROLS }
enum Row { TABS, MUSIC, SFX, MASTER, LANGUAGE, WINDOW, VSYNC, SHAKE, HIT_STOP, DAMAGE_NUMBERS, REDUCE_FLASHES, BRIGHTNESS, LIGHT_EFFECTS, RESET }

const STEP := 0.05
## Brightness slider step (GameOptions.BRIGHTNESS, -1 .. +1).
const BRIGHTNESS_STEP := 0.1
## Sizes in mockup pixels.
const CAPTION_WIDTH := 66.0
const SLIDER_SIZE := Vector2(90, 10)
const VALUE_WIDTH := 24.0
const CHOICE_WIDTH := 44.0
## Choice buttons: 12 mockup px high (sliders are 10), so six rows plus two sections fit the pause menu.
const CHOICE_HEIGHT := 12.0
const KEY_WIDTH := 50.0
const TAB_KEYS: Array[StringName] = [&"OPTIONS_TAB_GENERAL", &"OPTIONS_TAB_DISPLAY", &"OPTIONS_TAB_CONTROLS"]
## Rows per tab, in keyboard order.
const TAB_ROWS := {
	Tab.GENERAL: [Row.TABS, Row.MUSIC, Row.SFX, Row.MASTER, Row.LANGUAGE, Row.RESET],
	Tab.DISPLAY: [Row.TABS, Row.WINDOW, Row.VSYNC, Row.BRIGHTNESS, Row.LIGHT_EFFECTS, Row.SHAKE, Row.HIT_STOP, Row.DAMAGE_NUMBERS, Row.REDUCE_FLASHES, Row.RESET],
	Tab.CONTROLS: [Row.TABS, Row.RESET],
}
const SLIDER_BUSES := {Row.MUSIC: &"Music", Row.SFX: &"SFX", Row.MASTER: &"Master"}
const BUSES: Array[StringName] = [&"Music", &"SFX", &"Master"]
## Row -> option values of its choice buttons, left to right.
const CHOICE_VALUES := {
	Row.LANGUAGE: [&"auto", &"en", &"de"],
	Row.WINDOW: [&"windowed", &"fullscreen", &"borderless"],
	Row.SHAKE: [0.0, 0.5, 1.0],
	Row.VSYNC: [false, true],
	Row.HIT_STOP: [false, true],
	Row.DAMAGE_NUMBERS: [false, true],
	Row.REDUCE_FLASHES: [false, true],
	Row.LIGHT_EFFECTS: [&"low", &"high"],
}

## true: the view reads keys in _unhandled_input (pause menu); false: the host calls handle_input.
var listen_unhandled := false

var _tab := Tab.GENERAL
var _row := Row.MUSIC
var _confirming_reset := false
var _tab_buttons: Array[Button] = []
var _pages_host: MarginContainer = null
var _pages: Array[VBoxContainer] = []
var _controls_rows: VBoxContainer = null
var _actions: HBoxContainer = null
var _reset_button: Button = null
var _back_button: Button = null
var _footer: Label = null
## Row -> caption label (meta "caption" holds the key).
var _captions: Dictionary = {}
## Row -> HSlider, Row -> value label.
var _sliders: Dictionary = {}
var _values: Dictionary = {}
## Row -> Array[Button] of the choice rows.
var _choices: Dictionary = {}
var _volume_dirty := false


func _init() -> void:
	add_theme_constant_override("separation", int(UiKit.px(5)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Loc.install()


func _ready() -> void:
	var header := UiKit.vbox(int(UiKit.px(2)))
	var eyebrow := UiKit.eyebrow(&"MENU_OPTIONS", UiKit.COLOR_MUTED)
	eyebrow.uppercase = true
	header.add_child(eyebrow)
	header.add_child(_build_tabs())
	add_child(header)
	_pages_host = MarginContainer.new()
	_pages_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		_pages_host.add_theme_constant_override("margin_" + side, 0)
	add_child(_pages_host)
	_pages = [_build_general(), _build_display(), _build_controls()]
	for page in _pages:
		page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_pages_host.add_child(page)
	_actions = UiKit.hbox(int(UiKit.px(6)))
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_actions)
	_footer = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_footer)
	_rebuild_actions()
	_refresh_choices()
	_show_tab(Tab.GENERAL)
	_set_row(Row.MUSIC)
	_fix_layout()


func _exit_tree() -> void:
	save_volumes()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _footer != null:
		_retranslate()


func _unhandled_input(event: InputEvent) -> void:
	if listen_unhandled and is_visible_in_tree() and handle_input(event):
		get_viewport().set_input_as_handled()


## Returns true if the event was used. Esc is left to the host unless the reset question is open.
func handle_input(event: InputEvent) -> bool:
	if _confirming_reset:
		if MenuInput.is_accept(event):
			confirm_reset()
			return true
		if MenuInput.is_back(event):
			cancel_reset()
			return true
		return MenuInput.is_up(event) or MenuInput.is_down(event) or MenuInput.is_left(event) or MenuInput.is_right(event)
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_Q or key.keycode == KEY_E):
		show_tab(_next_tab(-1 if key.keycode == KEY_Q else 1))
		return true
	if MenuInput.is_up(event) or MenuInput.is_down(event):
		var rows: Array = TAB_ROWS[_tab]
		var index := rows.find(_row)
		_set_row(rows[posmod(index + (-1 if MenuInput.is_up(event) else 1), rows.size())] as Row)
		UiSound.hover(self)
		return true
	if MenuInput.is_left(event) or MenuInput.is_right(event):
		change(-1 if MenuInput.is_left(event) else 1)
		return true
	if MenuInput.is_accept(event):
		if _row == Row.TABS:
			show_tab(_next_tab(1))
			return true
		if _row == Row.RESET:
			request_reset()
			return true
		if CHOICE_VALUES.has(_row):
			change(1)
			return true
	return false


## ←/→ on the current row: volume step, next choice (wrapping) or next tab.
func change(direction: int) -> void:
	if _row == Row.TABS:
		show_tab(_next_tab(direction))
	elif SLIDER_BUSES.has(_row):
		var slider := _sliders[_row] as HSlider
		slider.value = clampf(slider.value + STEP * direction, 0.0, 1.0)
	elif _row == Row.BRIGHTNESS:
		var slider := _sliders[_row] as HSlider
		slider.value = clampf(slider.value + BRIGHTNESS_STEP * direction, GameOptions.BRIGHTNESS_MIN, GameOptions.BRIGHTNESS_MAX)
	elif CHOICE_VALUES.has(_row):
		var values: Array = CHOICE_VALUES[_row]
		_pick(_row, posmod(_choice_index(_row) + direction, values.size()))


func show_tab(tab: Tab) -> void:
	if tab == _tab:
		return
	UiSound.play(self, UiSound.OPEN, -4.0)
	_show_tab(tab)


## Kept for hosts: the key overview is the "Tasten" tab.
func show_controls() -> void:
	show_tab(Tab.CONTROLS)


func show_settings() -> void:
	if _tab == Tab.CONTROLS:
		UiSound.back(self)
		_show_tab(Tab.GENERAL)


func get_tab() -> Tab:
	return _tab


func get_page() -> Page:
	return Page.CONTROLS if _tab == Tab.CONTROLS else Page.SETTINGS


func get_row() -> Row:
	return _row


## Selects a row and switches to its tab.
func select_row(row: Row) -> void:
	for tab in TAB_ROWS:
		if (TAB_ROWS[tab] as Array).has(row):
			if tab != _tab:
				_show_tab(tab)
			break
	_set_row(row)


func get_volume_slider(bus: StringName) -> HSlider:
	for row in SLIDER_BUSES:
		if SLIDER_BUSES[row] == bus:
			return _sliders.get(row, null)
	return null


## Choice buttons of a row (left to right), for tests and screenshots.
func get_choice_buttons(row: Row) -> Array:
	return _choices.get(row, [])


func get_tab_buttons() -> Array[Button]:
	return _tab_buttons


## The key line as shown (translated), for tests.
func get_footer_text() -> String:
	return tr(_footer.text) if _footer != null else ""


## Caption of a row as shown ("> Musik" when selected), for tests.
func get_caption_text(row: Row) -> String:
	var caption := _captions.get(row, null) as Label
	return caption.text if caption != null else ""


func is_confirming_reset() -> bool:
	return _confirming_reset


func save_volumes() -> void:
	if _volume_dirty:
		_volume_dirty = false
		SaveManager.save_settings()


# --- Reset ---

func request_reset() -> void:
	if _confirming_reset:
		return
	Sfx.play_ui(self, &"ui_open")
	_confirming_reset = true
	_set_row(Row.RESET)
	_rebuild_actions()
	_update_footer()


func confirm_reset() -> void:
	if not _confirming_reset:
		return
	_confirming_reset = false
	GameOptions.reset_to_defaults()
	_volume_dirty = false
	UiSound.play(self, UiSound.CONFIRM)
	_refresh_sliders()
	_refresh_choices()
	_rebuild_actions()
	_update_footer()


func cancel_reset() -> void:
	if not _confirming_reset:
		return
	_confirming_reset = false
	UiSound.back(self)
	_rebuild_actions()
	_update_footer()


func _on_back_pressed() -> void:
	if _confirming_reset:
		cancel_reset()
	else:
		back_requested.emit()


# --- Tabs and rows ---

func _next_tab(direction: int) -> Tab:
	return posmod(int(_tab) + direction, Tab.size()) as Tab


func _show_tab(tab: Tab) -> void:
	_tab = tab
	for i in _pages.size():
		_pages[i].visible = i == int(tab)
	if not (TAB_ROWS[tab] as Array).has(_row):
		var rows: Array = TAB_ROWS[tab]
		_set_row(rows[1] if rows.size() > 2 else rows[0])
	else:
		_set_row(_row)
	_update_footer()


func _set_row(row: Row) -> void:
	_row = row
	for key in _captions:
		var caption := _captions[key] as Label
		var selected: bool = key == int(row)
		caption.add_theme_color_override("font_color", UiKit.COLOR_GOLD if selected else UiKit.COLOR_TEXT_SOFT)
		caption.text = ("> " if selected else "") + tr(caption.get_meta(&"caption") as StringName)
	for i in _tab_buttons.size():
		_style_tab(i)
	if _reset_button != null:
		_reset_button.add_theme_color_override("font_color", UiKit.COLOR_GOLD if row == Row.RESET else UiKit.COLOR_TEXT)


func _update_footer() -> void:
	if _confirming_reset:
		_footer.text = &"OPTIONS_RESET_QUESTION"
		_footer.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT)
	else:
		_footer.text = &"OPTIONS_FOOTER_CONTROLS" if _tab == Tab.CONTROLS else &"OPTIONS_FOOTER"
		_footer.add_theme_color_override("font_color", UiKit.COLOR_DISABLED)


## Language change: captions carry the cursor, the key page has composed texts.
func _retranslate() -> void:
	_set_row(_row)
	_update_footer()
	_fill_controls_rows()
	_fix_layout()


## One size for every tab and row (the window must not jump): captions as wide as the longest
## selected caption, all pages as large as the largest page, the key line as high as its longest
## text at that width. Hidden pages do not count in a container, so the size is set explicitly.
func _fix_layout() -> void:
	if _pages_host == null:
		return
	var caption_width := UiKit.px(CAPTION_WIDTH)
	for key in _captions:
		var caption := _captions[key] as Label
		var text := "> " + tr(caption.get_meta(&"caption") as StringName)
		caption_width = maxf(caption_width, _text_width(caption, text))
	for key in _captions:
		(_captions[key] as Label).custom_minimum_size.x = ceilf(caption_width)
	_pages_host.custom_minimum_size = Vector2.ZERO
	var page_size := Vector2.ZERO
	for page in _pages:
		page_size = page_size.max(page.get_combined_minimum_size())
	_pages_host.custom_minimum_size = page_size.ceil()
	if _footer != null:
		var width := maxf(page_size.x, get_combined_minimum_size().x)
		var height := 0.0
		for key in [&"OPTIONS_FOOTER", &"OPTIONS_FOOTER_CONTROLS", &"OPTIONS_RESET_QUESTION"]:
			height = maxf(height, _text_height(_footer, tr(key), width))
		_footer.custom_minimum_size.y = ceilf(height)


static func _text_width(label: Label, text: String) -> float:
	var font := label.get_theme_font(&"font")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x


static func _text_height(label: Label, text: String, width: float) -> float:
	var font := label.get_theme_font(&"font")
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, label.get_theme_font_size(&"font_size")).y


func _hover_row(row: Row) -> void:
	if row != _row and not _confirming_reset:
		_set_row(row)


# --- Choices ---

func _choice_index(row: Row) -> int:
	var values: Array = CHOICE_VALUES[row]
	var current: Variant
	match row:
		Row.LANGUAGE:
			current = GameOptions.get_language()
		Row.WINDOW:
			current = GameOptions.get_window_mode()
		Row.SHAKE:
			current = GameOptions.get_screen_shake_strength()
		Row.VSYNC:
			current = GameOptions.is_vsync_enabled()
		Row.HIT_STOP:
			current = GameOptions.is_hit_stop_enabled()
		Row.DAMAGE_NUMBERS:
			current = GameOptions.are_damage_numbers_enabled()
		Row.REDUCE_FLASHES:
			current = GameOptions.is_reduce_flashes_enabled()
		Row.LIGHT_EFFECTS:
			current = GameOptions.get_light_effects()
	var index := values.find(current)
	if index < 0 and row == Row.SHAKE:
		# Any other strength (hand-edited file) shows as the nearest step.
		index = 2 if float(current) > 0.75 else (1 if float(current) > 0.0 else 0)
	return maxi(index, 0)


## Applies the choice at index of a row (click, ←/→, Enter) and stores it at once.
func _pick(row: Row, index: int) -> void:
	if index == _choice_index(row):
		return
	var value: Variant = (CHOICE_VALUES[row] as Array)[index]
	UiSound.toggle(self)
	match row:
		Row.LANGUAGE:
			GameOptions.set_language(value)
		Row.WINDOW:
			GameOptions.set_window_mode(value)
		Row.SHAKE:
			GameOptions.set_screen_shake_strength(value)
			if value > 0.0:
				# A small jolt shows what was switched on (no-op without a game camera, e.g. main menu).
				CameraShake.shake(self, 4.0 * float(value))
		Row.VSYNC:
			GameOptions.set_vsync(value)
		Row.HIT_STOP:
			GameOptions.set_hit_stop(value)
		Row.DAMAGE_NUMBERS:
			GameOptions.set_damage_numbers(value)
		Row.REDUCE_FLASHES:
			GameOptions.set_reduce_flashes(value)
		Row.LIGHT_EFFECTS:
			GameOptions.set_light_effects(value)
	_refresh_choices()


func _refresh_choices() -> void:
	for row in _choices:
		_style_choice(row, _choice_index(row))


func _refresh_sliders() -> void:
	for row in _sliders:
		var slider := _sliders[row] as HSlider
		if row == Row.BRIGHTNESS:
			slider.set_value_no_signal(GameOptions.get_brightness())
			(_values[row] as Label).text = brightness_text(GameOptions.get_brightness())
			continue
		var value := GameOptions.get_master_volume() if row == Row.MASTER else SaveManager.get_volume(SLIDER_BUSES[row])
		slider.set_value_no_signal(value)
		(_values[row] as Label).text = "%d %%" % roundi(value * 100.0)


# --- Building: header ---

func _build_tabs() -> HBoxContainer:
	var strip := UiKit.hbox(int(UiKit.px(4)))
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in TAB_KEYS.size():
		var button := Button.new()
		button.text = TAB_KEYS[i]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.y = UiKit.px(14)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_CARD_NAME))
		button.add_theme_font_override("font", UiKit.bold_font())
		button.pressed.connect(func() -> void:
			if _confirming_reset:
				return
			_set_row(Row.TABS)
			show_tab(i as Tab))
		button.mouse_entered.connect(func() -> void:
			if not _confirming_reset:
				UiSound.hover(button))
		strip.add_child(button)
		_tab_buttons.append(button)
	return strip


func _style_tab(index: int) -> void:
	var button := _tab_buttons[index]
	var active: bool = index == int(_tab)
	var selected: bool = _row == Row.TABS
	var style: StyleBox = StyleBoxEmpty.new()
	if active:
		style = UiKit.padded_style(&"button_hover" if selected else &"button", 1, 6)
	for state in ["normal", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("hover", UiKit.padded_style(&"button_hover" if active else &"button", 1, 6))
	var color := UiKit.COLOR_DISABLED
	if active:
		color = UiKit.COLOR_GOLD if selected else UiKit.COLOR_TEXT
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", UiKit.COLOR_GOLD if active else UiKit.COLOR_TEXT)


# --- Building: pages ---

func _build_general() -> VBoxContainer:
	var box := UiKit.vbox(int(UiKit.px(4)))
	box.add_child(_section(&"OPTIONS_SECTION_AUDIO"))
	box.add_child(_slider_row(Row.MUSIC, &"OPTIONS_MUSIC"))
	box.add_child(_slider_row(Row.SFX, &"OPTIONS_SFX"))
	box.add_child(_slider_row(Row.MASTER, &"OPTIONS_MASTER"))
	box.add_child(_section(&"OPTIONS_SECTION_LANGUAGE"))
	# Language names stay in their own language on purpose.
	box.add_child(_choice_row(Row.LANGUAGE, &"OPTIONS_LANGUAGE", [&"OPTIONS_LANG_AUTO", "English", "Deutsch"]))
	return box


func _build_display() -> VBoxContainer:
	var box := UiKit.vbox(int(UiKit.px(4)))
	box.add_child(_section(&"OPTIONS_SECTION_DISPLAY"))
	box.add_child(_choice_row(Row.WINDOW, &"OPTIONS_WINDOW_MODE", [&"OPTIONS_WINDOWED", &"OPTIONS_FULLSCREEN", &"OPTIONS_BORDERLESS"]))
	box.add_child(_choice_row(Row.VSYNC, &"OPTIONS_VSYNC", [&"COMMON_OFF", &"COMMON_ON"]))
	box.add_child(_brightness_row())
	box.add_child(_choice_row(Row.LIGHT_EFFECTS, &"OPTIONS_LIGHT_EFFECTS", [&"OPTIONS_LIGHT_LOW", &"OPTIONS_LIGHT_HIGH"]))
	box.add_child(_section(&"OPTIONS_SECTION_FEEL"))
	box.add_child(_choice_row(Row.SHAKE, &"OPTIONS_SHAKE", [&"COMMON_OFF", &"OPTIONS_SHAKE_LIGHT", &"OPTIONS_SHAKE_NORMAL"]))
	box.add_child(_choice_row(Row.HIT_STOP, &"OPTIONS_HIT_STOP", [&"COMMON_OFF", &"COMMON_ON"]))
	box.add_child(_choice_row(Row.DAMAGE_NUMBERS, &"OPTIONS_DAMAGE_NUMBERS", [&"COMMON_OFF", &"COMMON_ON"]))
	box.add_child(_choice_row(Row.REDUCE_FLASHES, &"OPTIONS_REDUCE_FLASHES", [&"COMMON_OFF", &"COMMON_ON"]))
	return box


func _build_controls() -> VBoxContainer:
	var box := UiKit.vbox(int(UiKit.px(3)))
	box.add_child(_section(&"OPTIONS_SECTION_CONTROLS"))
	_controls_rows = UiKit.vbox(int(UiKit.px(2)))
	box.add_child(_controls_rows)
	_fill_controls_rows()
	var later := UiKit.text_label(&"CONTROLS_REBIND_LATER", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	later.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(later)
	return box


## (Re)builds the key rows: key names and captions are composed in the current language.
func _fill_controls_rows() -> void:
	if _controls_rows == null:
		return
	for child in _controls_rows.get_children():
		_controls_rows.remove_child(child)
		child.queue_free()
	for id in ControlsInfo.get_ids():
		_controls_rows.add_child(_control_row(id))


func _section(key: StringName) -> Label:
	var label := UiKit.eyebrow(key, UiKit.COLOR_DISABLED)
	label.uppercase = true
	return label


## Row with its caption (a translation key); caption hover selects the row.
func _row_box(row: Row, caption_key: StringName) -> HBoxContainer:
	var box := UiKit.hbox(int(UiKit.px(6)))
	var caption := UiKit.text_label(tr(caption_key), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT_SOFT, true)
	caption.set_meta(&"caption", caption_key)
	caption.custom_minimum_size.x = UiKit.px(CAPTION_WIDTH)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_STOP
	caption.mouse_entered.connect(_hover_row.bind(row))
	box.add_child(caption)
	_captions[row] = caption
	return box


func _slider_row(row: Row, caption_key: StringName) -> Control:
	var bus: StringName = SLIDER_BUSES[row]
	var box := _row_box(row, caption_key)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = STEP
	slider.value = GameOptions.get_master_volume() if row == Row.MASTER else SaveManager.get_volume(bus)
	slider.custom_minimum_size = UiKit.pxv(SLIDER_SIZE.x, SLIDER_SIZE.y)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.mouse_entered.connect(_hover_row.bind(row))
	box.add_child(slider)
	var value := UiKit.text_label("%d %%" % roundi(slider.value * 100.0), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	value.custom_minimum_size.x = UiKit.px(VALUE_WIDTH)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value)
	slider.value_changed.connect(func(new_value: float) -> void:
		if row == Row.MASTER:
			# Master is an option: stored at once (SaveManager's volumes only know Music and SFX).
			GameOptions.set_master_volume(new_value)
		else:
			SaveManager.set_volume(bus, new_value)
			_volume_dirty = true
		value.text = "%d %%" % roundi(new_value * 100.0)
		_set_row(row)
		# The effects slider ticks at full level so the new loudness can be heard.
		if bus == &"SFX":
			UiSound.click(slider)
		else:
			UiSound.step(slider))
	slider.drag_ended.connect(func(_changed: bool) -> void: save_volumes())
	_sliders[row] = slider
	_values[row] = value
	return box


## Brightness slider (R8): -1 .. +1, stored and applied at once (GameOptions.set_brightness), value
## as "+20 %" / "0 %".
func _brightness_row() -> Control:
	var row := Row.BRIGHTNESS
	var box := _row_box(row, &"OPTIONS_BRIGHTNESS")
	var slider := HSlider.new()
	slider.name = "Brightness"
	slider.min_value = GameOptions.BRIGHTNESS_MIN
	slider.max_value = GameOptions.BRIGHTNESS_MAX
	slider.step = BRIGHTNESS_STEP
	slider.value = GameOptions.get_brightness()
	slider.custom_minimum_size = UiKit.pxv(SLIDER_SIZE.x, SLIDER_SIZE.y)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.mouse_entered.connect(_hover_row.bind(row))
	box.add_child(slider)
	var value := UiKit.text_label(brightness_text(slider.value), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	value.custom_minimum_size.x = UiKit.px(VALUE_WIDTH)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value)
	slider.value_changed.connect(func(new_value: float) -> void:
		GameOptions.set_brightness(new_value)
		value.text = brightness_text(new_value)
		_set_row(row)
		UiSound.step(slider))
	_sliders[row] = slider
	_values[row] = value
	return box


## "+20 %", "-50 %", "0 %".
static func brightness_text(value: float) -> String:
	var percent := roundi(value * 100.0)
	return ("+%d %%" % percent) if percent > 0 else ("%d %%" % percent)


## Choice row ("Fenster | Vollbild | Randlos"): the active option is framed gold. labels are
## translation keys or plain names; their order matches CHOICE_VALUES[row].
func _choice_row(row: Row, caption_key: StringName, labels: Array) -> Control:
	var box := _row_box(row, caption_key)
	var buttons: Array[Button] = []
	for i in labels.size():
		var button := Button.new()
		button.text = labels[i]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(UiKit.px(CHOICE_WIDTH), UiKit.px(CHOICE_HEIGHT))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_BODY))
		button.add_theme_font_override("font", UiKit.bold_font())
		button.pressed.connect(func() -> void:
			if _confirming_reset:
				return
			_set_row(row)
			_pick(row, i))
		button.mouse_entered.connect(_hover_row.bind(row))
		box.add_child(button)
		buttons.append(button)
	_choices[row] = buttons
	return box


func _style_choice(row: Row, active_index: int) -> void:
	var buttons: Array = _choices.get(row, [])
	for i in buttons.size():
		var button := buttons[i] as Button
		var active := i == active_index
		var kind := &"button_hover" if active else &"dark"
		for state in ["normal", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, UiKit.padded_style(kind, 2, 3))
		button.add_theme_stylebox_override("hover", UiKit.padded_style(&"button_hover" if active else &"button", 2, 3))
		button.add_theme_color_override("font_color", UiKit.COLOR_GOLD if active else UiKit.COLOR_DISABLED)
		button.add_theme_color_override("font_hover_color", UiKit.COLOR_GOLD if active else UiKit.COLOR_TEXT)


# --- Building: actions ---

## "Zurücksetzen" and "Zurück"; while the reset question is open: "Alles zurücksetzen" and
## "Abbrechen". Deferred: the button that triggered this may still be inside its pressed signal.
func _rebuild_actions() -> void:
	_rebuild_actions_now.call_deferred()


func _rebuild_actions_now() -> void:
	if _actions == null:
		return
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	if _confirming_reset:
		_reset_button = MenuPanel.action_button(&"OPTIONS_RESET_CONFIRM", "Enter", confirm_reset, true)
		_reset_button.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT)
		_reset_button.add_theme_color_override("font_hover_color", UiKit.COLOR_DANGER_SOFT.lightened(0.2))
		_actions.add_child(_reset_button)
		_back_button = MenuPanel.action_button(&"COMMON_CANCEL", "Esc", cancel_reset)
		_actions.add_child(_back_button)
		return
	_reset_button = MenuPanel.action_button(&"OPTIONS_RESET", "Enter", request_reset)
	_reset_button.mouse_entered.connect(_hover_row.bind(Row.RESET))
	_actions.add_child(_reset_button)
	_back_button = MenuPanel.action_button(&"COMMON_BACK", "Esc", _on_back_pressed, true)
	_actions.add_child(_back_button)
	_set_row(_row)


# --- Controls page ---

## One line per entry (key chip, caption, muted note on the right) so the page fits the screen.
func _control_row(id: StringName) -> Control:
	var row := UiKit.hbox(int(UiKit.px(6)))
	row.add_child(key_chip(ControlsInfo.key_text(id), KEY_WIDTH))
	var caption := UiKit.text_label(ControlsInfo.caption(id), UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	var note := UiKit.text_label(ControlsInfo.note(id), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(note)
	return row


## Dark frame with a gold key name, e.g. "Leertaste" (also used by the first-run hint).
static func key_chip(key: String, min_width := 0.0) -> PanelContainer:
	var chip := UiKit.panel(&"dark")
	chip.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 1, 4))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if min_width > 0.0:
		chip.custom_minimum_size.x = UiKit.px(min_width)
	var label := UiKit.text_label(key, UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip
