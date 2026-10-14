class_name OptionsView
extends VBoxContainer
## The options content shared by the main menu ("Optionen" panel) and the pause menu, so both look
## and behave the same (UX1). Page "Einstellungen": Musik, Effekte (volume sliders), Anzeige
## (Fenster / Vollbild), Bildschirmwackeln (Aus / An), Steuerung (opens page "Steuerung", the key
## overview from ControlsInfo).
##
## Keys: ↑/↓ row, ←/→ change, Enter toggles or opens, Esc on the controls page goes back to the
## settings. Esc on the settings page is NOT used here: the host closes (back_requested is emitted by
## the "Zurück" button only). Hosts forward keys with handle_input(); with listen_unhandled the view
## reads _unhandled_input itself (pause menu modal; children see keys before the modal).
## Volumes are global (SaveManager.set_volume, saved on slider release and when the view closes);
## the other options are stored at once (GameOptions).

signal back_requested

enum Page { SETTINGS, CONTROLS }
enum Row { MUSIC, SFX, WINDOW, SHAKE, CONTROLS }

const STEP := 0.05
## Sizes in mockup pixels.
const CAPTION_WIDTH := 66.0
const SLIDER_SIZE := Vector2(90, 10)
const VALUE_WIDTH := 24.0
const CHOICE_WIDTH := 44.0
const KEY_WIDTH := 50.0
const FOOTER_SETTINGS := "↑↓ wählen · ←→ ändern · Enter · Esc zurück"
const FOOTER_CONTROLS := "Esc oder Enter zurück · F11 Vollbild"
const BUSES: Array[StringName] = [&"Music", &"SFX"]

## true: the view reads keys in _unhandled_input (pause menu); false: the host calls handle_input.
var listen_unhandled := false

var _page := Page.SETTINGS
var _row := Row.MUSIC
var _title: Label = null
var _settings: VBoxContainer = null
var _controls: VBoxContainer = null
var _footer: Label = null
var _back_button: Button = null
var _captions: Array[Label] = []
var _sliders: Array[HSlider] = []
## Row -> [left button, right button] of the two-way choices.
var _choices: Dictionary = {}
var _controls_button: Button = null
var _volume_dirty := false


func _init() -> void:
	add_theme_constant_override("separation", int(UiKit.px(5)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var header := UiKit.vbox(int(UiKit.px(1)))
	header.add_child(UiKit.eyebrow("Optionen", UiKit.COLOR_MUTED))
	_title = UiKit.text_label("Einstellungen", UiKit.SIZE_TITLE, UiKit.COLOR_GOLD, true)
	header.add_child(_title)
	add_child(header)
	_settings = _build_settings()
	add_child(_settings)
	_controls = _build_controls()
	_controls.visible = false
	add_child(_controls)
	var actions := UiKit.hbox(int(UiKit.px(6)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_back_button = MenuPanel.action_button("Zurück", "Esc", _on_back_pressed, true)
	actions.add_child(_back_button)
	add_child(actions)
	_footer = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_footer)
	_show_page(Page.SETTINGS)
	_set_row(Row.MUSIC)


func _exit_tree() -> void:
	save_volumes()


func _unhandled_input(event: InputEvent) -> void:
	if listen_unhandled and is_visible_in_tree() and handle_input(event):
		get_viewport().set_input_as_handled()


## Returns true if the event was used. Esc on the settings page is left to the host.
func handle_input(event: InputEvent) -> bool:
	if _page == Page.CONTROLS:
		if MenuInput.is_back(event) or MenuInput.is_accept(event):
			show_settings()
			return true
		return MenuInput.is_up(event) or MenuInput.is_down(event) or MenuInput.is_left(event) or MenuInput.is_right(event)
	if MenuInput.is_up(event) or MenuInput.is_down(event):
		_set_row(posmod(_row + (-1 if MenuInput.is_up(event) else 1), Row.size()) as Row)
		UiSound.hover(self)
		return true
	if MenuInput.is_left(event) or MenuInput.is_right(event):
		change(-1 if MenuInput.is_left(event) else 1)
		return true
	if MenuInput.is_accept(event):
		match _row:
			Row.WINDOW, Row.SHAKE:
				change(1)
				return true
			Row.CONTROLS:
				show_controls()
				return true
	return false


## ←/→ on the current row: volume step, or switch the two-way choice.
func change(direction: int) -> void:
	match _row:
		Row.MUSIC, Row.SFX:
			var slider := _sliders[_row]
			slider.value = clampf(slider.value + STEP * direction, 0.0, 1.0)
		Row.WINDOW:
			_set_fullscreen(not GameOptions.is_fullscreen())
		Row.SHAKE:
			_set_shake(not GameOptions.is_screen_shake_enabled())
		Row.CONTROLS:
			pass


func show_controls() -> void:
	UiSound.play(self, UiSound.OPEN, -4.0)
	_show_page(Page.CONTROLS)


func show_settings() -> void:
	UiSound.back(self)
	_show_page(Page.SETTINGS)


func get_page() -> Page:
	return _page


func get_row() -> Row:
	return _row


func select_row(row: Row) -> void:
	_set_row(row)


func get_volume_slider(bus: StringName) -> HSlider:
	var index := BUSES.find(bus)
	return _sliders[index] if index >= 0 else null


## Choice buttons of a two-way row ([left, right]), for tests and screenshots.
func get_choice_buttons(row: Row) -> Array:
	return _choices.get(row, [])


func save_volumes() -> void:
	if _volume_dirty:
		_volume_dirty = false
		SaveManager.save_settings()


func _on_back_pressed() -> void:
	if _page == Page.CONTROLS:
		show_settings()
	else:
		back_requested.emit()


func _show_page(page: Page) -> void:
	_page = page
	_settings.visible = page == Page.SETTINGS
	_controls.visible = page == Page.CONTROLS
	_title.text = "Steuerung" if page == Page.CONTROLS else "Einstellungen"
	_footer.text = FOOTER_CONTROLS if page == Page.CONTROLS else FOOTER_SETTINGS


func _set_row(row: Row) -> void:
	_row = row
	for i in _captions.size():
		var selected := i == int(row)
		_captions[i].add_theme_color_override("font_color", UiKit.COLOR_GOLD if selected else UiKit.COLOR_TEXT_SOFT)
		_captions[i].text = ("> " if selected else "") + String(_captions[i].get_meta(&"caption"))
	if _controls_button != null:
		_controls_button.add_theme_color_override("font_color", UiKit.COLOR_GOLD if row == Row.CONTROLS else UiKit.COLOR_TEXT)


func _set_fullscreen(on: bool) -> void:
	if on == GameOptions.is_fullscreen():
		return
	UiSound.toggle(self)
	GameOptions.set_fullscreen(on)
	_refresh_choices()


func _set_shake(on: bool) -> void:
	if on == GameOptions.is_screen_shake_enabled():
		return
	UiSound.toggle(self)
	GameOptions.set_screen_shake(on)
	_refresh_choices()
	if on:
		# A small jolt shows what was switched on (no-op without a game camera, e.g. main menu).
		CameraShake.shake(self, 4.0)


# --- Settings page ---

func _build_settings() -> VBoxContainer:
	var box := UiKit.vbox(int(UiKit.px(4)))
	box.add_child(_section("Ton"))
	for i in BUSES.size():
		box.add_child(_slider_row(i))
	box.add_child(_section("Anzeige"))
	box.add_child(_choice_row(Row.WINDOW, "Darstellung", ["Fenster", "Vollbild"],
		func(right: bool) -> void: _set_fullscreen(right)))
	box.add_child(_choice_row(Row.SHAKE, "Bildschirmwackeln", ["Aus", "An"],
		func(right: bool) -> void: _set_shake(right)))
	box.add_child(_section("Hilfe"))
	var row := _row_box(Row.CONTROLS, "Steuerung")
	_controls_button = UiKit.button("Tasten anzeigen", show_controls)
	_controls_button.custom_minimum_size.y = UiKit.px(14)
	_controls_button.custom_minimum_size.x = UiKit.px(CHOICE_WIDTH * 2.0) + UiKit.px(6)
	_controls_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_controls_button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_BODY))
	_controls_button.add_theme_font_override("font", UiKit.bold_font())
	_controls_button.add_theme_stylebox_override("normal", UiKit.padded_style(&"button", 2, 6))
	_controls_button.add_theme_stylebox_override("hover", UiKit.padded_style(&"button_hover", 2, 6))
	_controls_button.add_theme_stylebox_override("pressed", UiKit.padded_style(&"button_hover", 2, 6))
	_controls_button.mouse_entered.connect(_hover_row.bind(Row.CONTROLS))
	row.add_child(_controls_button)
	box.add_child(row)
	_refresh_choices()
	return box


func _section(text: String) -> Label:
	var label := UiKit.eyebrow(text, UiKit.COLOR_DISABLED)
	return label


## Row with its caption; caption hover selects the row.
func _row_box(row: Row, caption_text: String) -> HBoxContainer:
	var box := UiKit.hbox(int(UiKit.px(6)))
	var caption := UiKit.text_label(caption_text, UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT_SOFT, true)
	caption.set_meta(&"caption", caption_text)
	caption.custom_minimum_size.x = UiKit.px(CAPTION_WIDTH)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_STOP
	caption.mouse_entered.connect(_hover_row.bind(row))
	box.add_child(caption)
	_captions.append(caption)
	return box


func _hover_row(row: Row) -> void:
	if row != _row:
		_set_row(row)


func _slider_row(index: int) -> Control:
	var bus := BUSES[index]
	var row := _row_box(index as Row, "Musik" if bus == &"Music" else "Effekte")
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = STEP
	slider.value = SaveManager.get_volume(bus)
	slider.custom_minimum_size = UiKit.pxv(SLIDER_SIZE.x, SLIDER_SIZE.y)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.mouse_entered.connect(_hover_row.bind(index as Row))
	row.add_child(slider)
	var value := UiKit.text_label("%d %%" % roundi(slider.value * 100.0), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	value.custom_minimum_size.x = UiKit.px(VALUE_WIDTH)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	slider.value_changed.connect(func(new_value: float) -> void:
		SaveManager.set_volume(bus, new_value)
		value.text = "%d %%" % roundi(new_value * 100.0)
		_volume_dirty = true
		_set_row(index as Row)
		# The effects slider ticks at full level so the new loudness can be heard.
		if bus == &"SFX":
			UiSound.click(slider)
		else:
			UiSound.step(slider))
	slider.drag_ended.connect(func(_changed: bool) -> void: save_volumes())
	_sliders.append(slider)
	return row


## Two-way choice ("Fenster | Vollbild"): the active side is framed gold. on_pick(true) = right side.
func _choice_row(row: Row, caption_text: String, labels: Array, on_pick: Callable) -> Control:
	var box := _row_box(row, caption_text)
	var buttons: Array[Button] = []
	for i in 2:
		var button := Button.new()
		button.text = labels[i]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(UiKit.px(CHOICE_WIDTH), UiKit.px(14))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_BODY))
		button.add_theme_font_override("font", UiKit.bold_font())
		var right := i == 1
		button.pressed.connect(func() -> void:
			_set_row(row)
			on_pick.call(right))
		button.mouse_entered.connect(_hover_row.bind(row))
		box.add_child(button)
		buttons.append(button)
	_choices[row] = buttons
	return box


func _refresh_choices() -> void:
	_style_choice(Row.WINDOW, GameOptions.is_fullscreen())
	_style_choice(Row.SHAKE, GameOptions.is_screen_shake_enabled())


func _style_choice(row: Row, right_active: bool) -> void:
	var buttons: Array = _choices.get(row, [])
	for i in buttons.size():
		var button := buttons[i] as Button
		var active := (i == 1) == right_active
		var kind := &"button_hover" if active else &"dark"
		for state in ["normal", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, UiKit.padded_style(kind, 2, 4))
		button.add_theme_stylebox_override("hover", UiKit.padded_style(&"button_hover" if active else &"button", 2, 4))
		button.add_theme_color_override("font_color", UiKit.COLOR_GOLD if active else UiKit.COLOR_DISABLED)
		button.add_theme_color_override("font_hover_color", UiKit.COLOR_GOLD if active else UiKit.COLOR_TEXT)


# --- Controls page ---

func _build_controls() -> VBoxContainer:
	var box := UiKit.vbox(int(UiKit.px(2)))
	for id in ControlsInfo.get_ids():
		box.add_child(_control_row(id))
	return box


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
