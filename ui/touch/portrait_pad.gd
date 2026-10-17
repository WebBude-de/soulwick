extends CanvasLayer
## Controller field of the portrait mode (PortraitLayout; Projektmitglied 17.10.2026: "oben zocken
## und unten wie ein Gamepad. Voll retro."): a handheld casing under the game screen with a D-pad on
## the left, round face buttons on the right (A gold, B violet, X and Y smaller, Nintendo diamond),
## flat Select/Start in the middle and a small Benutzen button at the top of the field.
##
## Mapping (TESTWERT, D-180 proposal):
## - top-down: D-pad walks (8-way snap, full speed), A attacks in the walking direction (held: keeps
##   attacking), B dash, X special, Y switch weapon, Benutzen interact, Start pause, Select overview.
##   Aiming has no second stick: A feeds the walking direction (or the last one) as the aim stick of
##   TouchInput, so the touch aim assist for ranged weapons (D-155, like the gamepad D-163) applies.
## - side view: A jumps, B side dash, X special, Y attacks, a second small button next to Benutzen
##   switches the weapon (like the landscape touch layout there).
## - menus (and everywhere without a playing local player, e.g. the main menu): the D-pad sends
##   ui_up/down/left/right, A ui_accept, B ui_cancel (a gamepad in the hand), Start/Select their
##   actions; for NAV_GUARD_MSEC after a menu opened the buttons stay quiet (A is also the attack).
## Writes the device's TouchState like the landscape TouchOverlay (which hides in portrait), so
## TouchInput, cooldowns and the co-op input path stay the same (D-088: state per device, no player
## lookup). Options: "Seiten tauschen" puts the D-pad right and the buttons left, "Größe" picks the
## art pixel size; opacity is always 100 % (the casing is no overlay), "Joysticks" does not apply.
## Looks: pixel art at whole window pixels per art pixel; files from art/ui/touch/ (SPRITES_V10 §10)
## replace the drawn placeholders (PortraitPixelArt), icons are the touch icons (TouchArt).

const PortraitLayout := preload("res://ui/touch/portrait_layout.gd")
const PixelArt := preload("res://ui/touch/portrait_pixel_art.gd")

## Above every overlay of the game screen (side transit 90); below the dev feedback (119, 120).
const LAYER := 100
## Art pixel = floor(window width / columns) window pixels, per size option small/medium/large.
const ART_COLUMNS: Array[int] = [200, 176, 150]
const MIN_ART_PIXEL := 2
## Layout in art pixels (TESTWERTE): main row (D-pad, face buttons) at this share of the field
## height, the D-pad and the face buttons at these shares of the width.
const MAIN_ROW_SHARE := 0.46
const MIN_MAIN_ROW := 46
const DPAD_X_SHARE := 0.27
const FACE_X_SHARE := 0.73
## Diamond: centre of the face buttons to each button.
const FACE_SPREAD := 21
## Benutzen above the main row; Select/Start below it, off the centre.
const TOP_ROW_GAP := 32
const SELECT_ROW_GAP := 46
const SELECT_SPREAD := 17
## Side view: Waffe and Benutzen side by side, off the centre.
const SIDE_TOP_SPREAD := 12
## Brand line under the screen and the speaker grille at the bottom.
const BRAND := "SOULWICK"
const BRAND_TOP := 7
const GRILLE_SLOTS := 6
## D-pad: full deflection at this many art pixels from its centre, nothing inside the dead zone,
## directions within SNAP_DEGREES of the 8 main directions snap onto them (TESTWERTE).
const DPAD_REACH := 20.0
const DPAD_DEAD_ZONE := 0.22
const DPAD_SNAP_DEGREES := 15.0
## Touch areas: share of the drawn half size that takes a finger (D-pad, buttons).
const DPAD_GRAB := 1.45
const BUTTON_GRAB := 1.3
## A direction counts as pressed from this component (sin 22.5°).
const ARM_THRESHOLD := 0.38
## Menus: quiet time after a menu opened, then D-pad repeat (D-163 values).
const NAV_GUARD_MSEC := 600
const NAV_REPEAT_DELAY := 0.4
const NAV_REPEAT_EVERY := 0.12

## Button ids (positions); what they do depends on the mode (action_of, nav_action_of).
const A: StringName = &"a"
const B: StringName = &"b"
const X: StringName = &"x"
const Y: StringName = &"y"
const USE: StringName = &"use"
const WEAPON: StringName = &"weapon"
const START: StringName = &"start"
const SELECT: StringName = &"select"
const FACE_BUTTONS: Array[StringName] = [A, B, X, Y]
const PAUSE: StringName = &"pause_menu"
const OVERVIEW: StringName = &"upgrade_overview"
## Button looks.
enum Kind { BIG, SMALL, FLAT }
## Labels under Select and Start (translation keys).
const KEY_START: StringName = &"TOUCH_PAD_START"
const KEY_SELECT: StringName = &"TOUCH_PAD_SELECT"

var state: TouchState
## Options (see the header). follow_options: read them from GameOptions every frame; tests switch it
## off and call set_options().
var follow_options := true
var swap_sides := false
var size_step := 1
## {id, center (window px), size (art px), kind, art} of the buttons shown right now.
var buttons: Array[Dictionary] = []
## The local player plays (else menu navigation).
var playing := false

var _frame: PortraitLayout.Frame = null
var _pixel := 6
var _side_view := false
var _layout_key := ""
var _view: Control
var _dpad_center := Vector2.ZERO
var _dpad_finger := -1
var _dpad_dir := Vector2.ZERO
var _finger_button: Dictionary[int, StringName] = {}
## Last walking direction: A aims there while the D-pad rests.
var _facing := Vector2.RIGHT
var _nav_quiet_until := 0
## Menu direction the D-pad sends right now and when it repeats.
var _nav_dir := Vector2i.ZERO
var _nav_sent := false
var _nav_repeat_left := 0.0
## Menu actions sent as pressed (released again on lift).
var _nav_held: Dictionary[int, StringName] = {}


func _init(touch_state: TouchState = null) -> void:
	state = touch_state if touch_state != null else TouchState.shared()
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_view = Control.new()
	_view.name = "View"
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.draw.connect(_draw_pad)
	add_child(_view)


func _process(delta: float) -> void:
	var frame := PortraitLayout.get_frame()
	if frame == null:
		if visible:
			visible = false
			_release_everything()
		return
	visible = true
	if follow_options:
		set_options(GameOptions.is_touch_swap_sides(), GameOptions.get_touch_size())
	set_frame(frame)
	refresh_mode()
	_repeat_nav(delta)
	_view.queue_redraw()


## Options: swapped sides (D-pad right), size step 0..2.
func set_options(swap: bool, step: int) -> void:
	step = clampi(step, 0, ART_COLUMNS.size() - 1)
	if swap == swap_sides and step == size_step:
		return
	swap_sides = swap
	size_step = step
	_layout_key = ""


## Lays the field out for frame (again only when something changed).
func set_frame(frame: PortraitLayout.Frame) -> void:
	_frame = frame
	if frame == null:
		return
	var key := "%s|%s|%s|%d|%d|%s" % [frame.window, frame.top, frame.bottom, frame.screen_size.y, size_step, swap_sides]
	key += "|side" if state.side_view else ""
	if key == _layout_key:
		return
	if not _layout_key.is_empty():
		# Fingers on the old places would point at the wrong controls; only the buttons change
		# when the side view starts or ends (the D-pad keeps walking).
		if key.trim_suffix("|side") == _layout_key.trim_suffix("|side"):
			_release_buttons()
		else:
			_release_everything()
	_layout_key = key
	_side_view = state.side_view
	_pixel = art_pixel(frame.window.x, size_step)
	var layout := layout_controls(frame, _pixel, swap_sides, _side_view)
	_dpad_center = layout.dpad
	buttons.assign(layout.buttons)


## Play or menu navigation, by the touch state (a local player that can act polled it) and menus.
func refresh_mode() -> void:
	var now_playing := state.wants_overlay() and not _menu_open()
	if now_playing == playing:
		return
	# Let go of what the old mode pressed (gameplay actions or menu events), then switch.
	_release_buttons()
	_end_nav_direction()
	playing = now_playing
	if not playing:
		_nav_quiet_until = Time.get_ticks_msec() + NAV_GUARD_MSEC
		# A thumb still on the D-pad does not step through the menu that just opened.
		_nav_dir = nav_direction(_dpad_dir)
		_nav_sent = false
	_sync_state()


# --- Layout (window pixels) ---

## Window pixels per art pixel for a window width and size step.
static func art_pixel(window_width: float, step: int) -> int:
	return maxi(MIN_ART_PIXEL, floori(window_width / float(ART_COLUMNS[clampi(step, 0, ART_COLUMNS.size() - 1)])))


## {dpad: centre, main_y, buttons: [{id, center, size, kind, art}]} in window pixels for a frame.
static func layout_controls(frame: PortraitLayout.Frame, pixel: int, swap: bool, side_view: bool) -> Dictionary:
	var p := float(pixel)
	var width := frame.window.x
	var top := frame.pad_top()
	var bottom := frame.pad_bottom()
	var field := bottom - top
	var main_y := top + maxf(MIN_MAIN_ROW * p, field * MAIN_ROW_SHARE)
	# Select/Start (and their labels) must stay above the bottom edge.
	main_y = maxf(top + (TOP_ROW_GAP + 12) * p, minf(main_y, bottom - (SELECT_ROW_GAP + 12) * p))
	var dpad := Vector2(width * (1.0 - DPAD_X_SHARE if swap else DPAD_X_SHARE), main_y).round()
	var face := Vector2(width * (1.0 - FACE_X_SHARE if swap else FACE_X_SHARE), main_y).round()
	var spread := FACE_SPREAD * p
	var result: Array[Dictionary] = []
	result.append(_button(A, face + Vector2(spread, 0), Kind.BIG, PixelArt.BUTTON_A))
	result.append(_button(B, face + Vector2(0, spread), Kind.BIG, PixelArt.BUTTON_B))
	result.append(_button(X, face + Vector2(0, -spread), Kind.SMALL, PixelArt.BUTTON_SMALL))
	result.append(_button(Y, face + Vector2(-spread, 0), Kind.SMALL, PixelArt.BUTTON_SMALL))
	var top_row := Vector2(width * 0.5, main_y - TOP_ROW_GAP * p).round()
	if side_view:
		result.append(_button(WEAPON, top_row - Vector2(SIDE_TOP_SPREAD * p, 0), Kind.SMALL, PixelArt.BUTTON_SMALL))
		result.append(_button(USE, top_row + Vector2(SIDE_TOP_SPREAD * p, 0), Kind.SMALL, PixelArt.BUTTON_SMALL))
	else:
		result.append(_button(USE, top_row, Kind.SMALL, PixelArt.BUTTON_SMALL))
	var select_row := Vector2(width * 0.5, main_y + SELECT_ROW_GAP * p).round()
	result.append(_button(SELECT, select_row - Vector2(SELECT_SPREAD * p, 0), Kind.FLAT, PixelArt.BUTTON_FLAT))
	result.append(_button(START, select_row + Vector2(SELECT_SPREAD * p, 0), Kind.FLAT, PixelArt.BUTTON_FLAT))
	return {"dpad": dpad, "main_y": main_y, "buttons": result}


static func _button(id: StringName, center: Vector2, kind: Kind, art: String) -> Dictionary:
	var size := Vector2(PixelArt.BUTTON_FLAT_SIZE) if kind == Kind.FLAT else \
			Vector2.ONE * float(PixelArt.BUTTON_BIG_SIZE if kind == Kind.BIG else PixelArt.BUTTON_SMALL_SIZE)
	return {"id": id, "center": center, "size": size, "kind": kind, "art": art}


# --- Mapping ---

## Player action (or menu event action for Start/Select) of a button while playing.
static func action_of(id: StringName, side_view: bool) -> StringName:
	match id:
		A:
			return PlayerInput.DASH if side_view else PlayerInput.ATTACK
		B:
			return PlayerInput.SIDE_DASH if side_view else PlayerInput.DASH
		X:
			return PlayerInput.SPECIAL
		Y:
			return PlayerInput.ATTACK if side_view else PlayerInput.SWITCH_WEAPON
		USE:
			return PlayerInput.INTERACT
		WEAPON:
			return PlayerInput.SWITCH_WEAPON
		START:
			return PAUSE
		SELECT:
			return OVERVIEW
	return &""


## Menu action of a button outside play (D-pad: nav_action_of_direction).
static func nav_action_of(id: StringName) -> StringName:
	match id:
		A:
			return &"ui_accept"
		B:
			return &"ui_cancel"
		START:
			return PAUSE
		SELECT:
			return OVERVIEW
	return &""


## Icon (TouchArt id) of an action; the attack shows the active weapon instead.
static func icon_of(action: StringName, side_view: bool) -> StringName:
	match action:
		PlayerInput.ATTACK:
			return TouchArt.ICON_ATTACK
		PlayerInput.DASH:
			return TouchArt.ICON_JUMP if side_view else TouchArt.ICON_DASH
		PlayerInput.SIDE_DASH:
			return TouchArt.ICON_SIDE_DASH
		PlayerInput.SPECIAL:
			return TouchArt.ICON_SPECIAL
		PlayerInput.SWITCH_WEAPON:
			return TouchArt.ICON_SWITCH
		PlayerInput.INTERACT:
			return TouchArt.ICON_INTERACT
	return &""


## D-pad offset (window pixels) -> walking direction: zero in the dead zone, else a unit vector,
## snapped onto the 8 main directions when within snap_degrees of one.
static func dpad_vector(offset: Vector2, reach: float, dead_zone := DPAD_DEAD_ZONE, snap_degrees := DPAD_SNAP_DEGREES) -> Vector2:
	if reach <= 0.0 or offset.length() < reach * dead_zone:
		return Vector2.ZERO
	var angle := offset.angle()
	var step := PI / 4.0
	var nearest := roundf(angle / step) * step
	if absf(angle_difference(angle, nearest)) <= deg_to_rad(snap_degrees):
		angle = nearest
	return Vector2.from_angle(angle)


## The menu direction of a D-pad vector (the stronger axis), zero when resting.
static func nav_direction(direction: Vector2) -> Vector2i:
	if direction.length() < 0.5:
		return Vector2i.ZERO
	if absf(direction.x) >= absf(direction.y):
		return Vector2i(int(signf(direction.x)), 0)
	return Vector2i(0, int(signf(direction.y)))


static func nav_action_of_direction(direction: Vector2i) -> StringName:
	match direction:
		Vector2i.UP:
			return &"ui_up"
		Vector2i.DOWN:
			return &"ui_down"
		Vector2i.LEFT:
			return &"ui_left"
		Vector2i.RIGHT:
			return &"ui_right"
	return &""


# --- Input ---

func _input(event: InputEvent) -> void:
	if not visible or _frame == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and not state.touched:
			# The first touch after keyboard use already plays (not a menu step).
			state.touched = true
			refresh_mode()
		if handle_touch(event.index, event.position, event.pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if handle_drag(event.index, event.position):
			get_viewport().set_input_as_handled()


## A finger went down or up at position (view coordinates); true if the field used it. Touches on
## the game screen pass on (menus and dialogs are tapped there).
func handle_touch(index: int, position: Vector2, pressed: bool) -> bool:
	if _frame == null:
		return false
	var at := _frame.to_window(position)
	var on_field := at.y >= _frame.pad_top() or at.y < _frame.top
	if pressed:
		if not on_field:
			return false
		var button := button_at(at)
		if not button.is_empty():
			_finger_button[index] = button.id
			_press(button.id, index)
			return true
		if _dpad_finger < 0 and at.distance_to(_dpad_center) <= dpad_half() * DPAD_GRAB:
			_dpad_finger = index
			_set_dpad(at)
			return true
		return true
	if _finger_button.has(index):
		var id: StringName = _finger_button[index]
		_finger_button.erase(index)
		_release(id, index)
		return true
	if index == _dpad_finger:
		_dpad_finger = -1
		_dpad_dir = Vector2.ZERO
		_end_nav_direction()
		_sync_state()
		return true
	return on_field


## A finger moved (view coordinates); true if the field used it. A thumb may slide from one face
## button onto the next (B to A like on a handheld).
func handle_drag(index: int, position: Vector2) -> bool:
	if _frame == null:
		return false
	var at := _frame.to_window(position)
	if index == _dpad_finger:
		_set_dpad(at)
		return true
	if _finger_button.has(index):
		var current: StringName = _finger_button[index]
		var over := button_at(at)
		if not over.is_empty() and over.id != current and FACE_BUTTONS.has(over.id) and FACE_BUTTONS.has(current):
			_finger_button[index] = over.id
			_release(current, index)
			_press(over.id, index)
		return true
	return at.y >= _frame.pad_top()


## The button under a window position (touch area BUTTON_GRAB × its half size; the nearest wins).
func button_at(at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for button in buttons:
		var size: Vector2 = button.size * float(_pixel)
		var center: Vector2 = button.center
		var hit := false
		if button.kind == Kind.FLAT:
			hit = Rect2(center - size * 0.5, size).grow(size.y * (BUTTON_GRAB - 1.0) + float(_pixel) * 2.0).has_point(at)
		else:
			hit = at.distance_to(center) <= size.x * 0.5 * BUTTON_GRAB
		var distance := at.distance_to(center)
		if hit and distance < best_distance:
			best = button
			best_distance = distance
	return best


## Half the drawn size of the D-pad in window pixels.
func dpad_half() -> float:
	return PixelArt.DPAD_SIZE * 0.5 * float(_pixel)


func get_dpad_center() -> Vector2:
	return _dpad_center


func get_dpad_direction() -> Vector2:
	return _dpad_dir


func get_pixel() -> int:
	return _pixel


func is_button_held(id: StringName) -> bool:
	return _finger_button.values().has(id)


## Window position of a button (tests, screenshots); Vector2.INF if not shown.
func button_center(id: StringName) -> Vector2:
	for button in buttons:
		if button.id == id:
			return button.center
	return Vector2.INF


func _set_dpad(at: Vector2) -> void:
	_dpad_dir = dpad_vector(at - _dpad_center, DPAD_REACH * float(_pixel))
	if _dpad_dir != Vector2.ZERO:
		_facing = _dpad_dir
	if not playing:
		_update_nav_direction(nav_direction(_dpad_dir))
	_sync_state()


func _press(id: StringName, finger: int) -> void:
	if playing:
		var action := action_of(id, _side_view)
		if action != PlayerInput.ATTACK and action != PAUSE and action != OVERVIEW:
			state.press(action)
		# Menus and intros listen to the actions as events (like the landscape overlay).
		if action != PlayerInput.ATTACK and InputMap.has_action(action):
			_send_action(action, true)
		_sync_state()
		return
	var nav := nav_action_of(id)
	if nav.is_empty():
		return
	if Time.get_ticks_msec() < _nav_quiet_until and nav != PAUSE and nav != OVERVIEW:
		return
	_nav_held[finger] = nav
	if InputMap.has_action(nav):
		_send_action(nav, true)


## finger let go of id (already removed from the held buttons).
func _release(id: StringName, finger: int) -> void:
	if playing:
		var action := action_of(id, _side_view)
		if action != PlayerInput.ATTACK and not is_button_held(id):
			state.release(action)
			if InputMap.has_action(action):
				_send_action(action, false)
		_sync_state()
		return
	if _nav_held.has(finger):
		var nav: StringName = _nav_held[finger]
		_nav_held.erase(finger)
		if InputMap.has_action(nav):
			_send_action(nav, false)


## Writes sticks and the attack into the touch state: the D-pad is the move stick; while an attack
## button is held its direction (walking, else the last one) is the aim stick, so TouchInput attacks
## that way and applies its aim assist.
func _sync_state() -> void:
	if not playing:
		state.move = Vector2.ZERO
		state.aim = Vector2.ZERO
		return
	state.move = _dpad_dir
	state.aim = _facing if is_attack_held() else Vector2.ZERO


## An attack button is held (A top-down, Y side view).
func is_attack_held() -> bool:
	for id in _finger_button.values():
		if action_of(id, _side_view) == PlayerInput.ATTACK:
			return true
	return false


func _update_nav_direction(direction: Vector2i) -> void:
	if direction == _nav_dir:
		return
	_end_nav_direction()
	_nav_dir = direction
	if direction == Vector2i.ZERO or Time.get_ticks_msec() < _nav_quiet_until:
		return
	_send_nav_step()


func _send_nav_step() -> void:
	var action := nav_action_of_direction(_nav_dir)
	if action.is_empty() or not InputMap.has_action(action):
		return
	_send_action(action, true)
	_nav_sent = true
	_nav_repeat_left = NAV_REPEAT_DELAY


func _end_nav_direction() -> void:
	if _nav_sent:
		var action := nav_action_of_direction(_nav_dir)
		if not action.is_empty() and InputMap.has_action(action):
			_send_action(action, false)
	_nav_sent = false
	_nav_dir = Vector2i.ZERO
	_nav_repeat_left = 0.0


func _repeat_nav(delta: float) -> void:
	if playing or not _nav_sent or _nav_dir == Vector2i.ZERO:
		return
	_nav_repeat_left -= delta
	if _nav_repeat_left <= 0.0:
		_send_action(nav_action_of_direction(_nav_dir), true)
		_nav_repeat_left = NAV_REPEAT_EVERY


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	# Deferred: no nested dispatch from inside _input.
	Input.parse_input_event.call_deferred(event)


## Lets go of the buttons (fingers stay down but count no more); the D-pad keeps its finger.
func _release_buttons() -> void:
	for finger in _finger_button.keys():
		var id: StringName = _finger_button[finger]
		if playing:
			var action := action_of(id, _side_view)
			if action != PlayerInput.ATTACK and InputMap.has_action(action):
				_send_action(action, false)
	_finger_button.clear()
	for finger in _nav_held.keys():
		var nav: StringName = _nav_held[finger]
		if InputMap.has_action(nav):
			_send_action(nav, false)
	_nav_held.clear()
	state.release_all()


func _release_everything() -> void:
	_release_buttons()
	_end_nav_direction()
	_dpad_finger = -1
	_dpad_dir = Vector2.ZERO
	_sync_state()


## A modal is open (pause menu, shop, upgrade choice; in a group game too, where nothing pauses).
func _menu_open() -> bool:
	if not is_inside_tree():
		return false
	return get_tree().paused or GameManager.is_game_paused()


# --- Drawing (window pixels mapped to view coordinates) ---

func _draw_pad() -> void:
	if _frame == null:
		return
	_draw_casing()
	_draw_print()
	_draw_dpad()
	for button in buttons:
		_draw_button(button)


func _to_view_rect(rect: Rect2) -> Rect2:
	return Rect2(_frame.to_view(rect.position), rect.size / _frame.scale)


## The casing: everything outside the game screen, solid (the world drawn there is covered), the
## 9-slice panel on the field below the screen.
func _draw_casing() -> void:
	var window := _frame.window
	var field := Rect2(0.0, _frame.pad_top(), window.x, window.y - _frame.pad_top())
	# Solid backdrop first (rounded corners of the panel, sub-pixel edges), never over the screen.
	_view.draw_rect(_to_view_rect(field).grow_individual(4.0, 0.0, 4.0, 4.0), PixelArt.OUTLINE)
	if _frame.top > 0.0:
		_view.draw_rect(_to_view_rect(Rect2(0, 0, window.x, _frame.top)).grow_individual(4.0, 4.0, 4.0, 0.0), PixelArt.CASING)
	_draw_nine_slice(PixelArt.sprite(PixelArt.PANEL), field, PixelArt.PANEL_MARGIN)


func _draw_nine_slice(texture: Texture2D, rect: Rect2, margin: int) -> void:
	if texture == null:
		return
	var tex := texture.get_size()
	var p := float(_pixel)
	var m := minf(float(margin) * p, minf(rect.size.x, rect.size.y) * 0.5)
	var xs := [rect.position.x, rect.position.x + m, rect.end.x - m, rect.end.x]
	var ys := [rect.position.y, rect.position.y + m, rect.end.y - m, rect.end.y]
	var us := [0.0, float(margin), tex.x - margin, tex.x]
	var vs := [0.0, float(margin), tex.y - margin, tex.y]
	for row in 3:
		for column in 3:
			var target := Rect2(xs[column], ys[row], xs[column + 1] - xs[column], ys[row + 1] - ys[row])
			var source := Rect2(us[column], vs[row], us[column + 1] - us[column], vs[row + 1] - vs[row])
			if target.size.x <= 0.0 or target.size.y <= 0.0:
				continue
			_view.draw_texture_rect_region(texture, _to_view_rect(target), source)


## Brand line with a power light under the screen, letters next to the face buttons, labels under
## Select/Start and the speaker grille bottom right (decoration, pixel art).
func _draw_print() -> void:
	var p := float(_pixel)
	var brand := PixelArt.sprite("letters_" + BRAND)
	var brand_center := Vector2(_frame.window.x * 0.5, _frame.pad_top() + (BRAND_TOP + 2.5) * p)
	_draw_sprite(brand, brand_center, _pixel)
	if brand != null:
		var led := Rect2((brand_center - Vector2(brand.get_width() * 0.5 + 6.0, 1.5) * p).round(), Vector2(3, 3) * p)
		_view.draw_rect(_to_view_rect(led), PixelArt.LED)
	for button in buttons:
		var id: StringName = button.id
		if FACE_BUTTONS.has(id):
			var letter := PixelArt.sprite("letters_" + String(id).to_upper())
			var size: Vector2 = button.size
			_draw_sprite(letter, button.center + Vector2(0.0, size.y * 0.5 + 4.0) * p, _pixel)
		elif id == START or id == SELECT:
			_draw_label(label_text(id), button.center + Vector2(0.0, 6.0 * p))
	_draw_grille()


## Label under Select/Start: the translation, English/German fallback until the key is in the table.
static func label_text(id: StringName) -> String:
	if id == START:
		return DataTexts.text_or(KEY_START, "START")
	return DataTexts.text_or(KEY_SELECT, "SELECT" if Loc.current_language() != &"de" else "ÜBERSICHT")


func _draw_label(text: String, top_center: Vector2) -> void:
	var font := UiKit.get_font()
	var p := float(_pixel)
	var size := maxi(8, roundi(5.0 * p / _frame.scale))
	var width := 34.0 * p / _frame.scale
	var at := _frame.to_view(top_center) + Vector2(-width * 0.5, float(size))
	_view.draw_string(font, at.round(), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, PixelArt.PRINT)


## Diagonal slots bottom right, only where the field has room below Select/Start.
func _draw_grille() -> void:
	var p := float(_pixel)
	var base := Vector2(_frame.window.x - 44.0 * p, _frame.pad_bottom() - 10.0 * p)
	var select_bottom := button_center(START).y + 18.0 * p
	if base.y - 12.0 * p <= select_bottom:
		return
	for slot in GRILLE_SLOTS:
		for k in 12:
			var cell := Rect2(base + Vector2(slot * 5.0 + k, -k) * p, Vector2(2.0, 1.0) * p)
			_view.draw_rect(_to_view_rect(cell), PixelArt.GROOVE)
			_view.draw_rect(_to_view_rect(Rect2(cell.position + Vector2(0.0, p), Vector2(2.0, 1.0) * p)), PixelArt.CASING_LIGHT)


func _draw_dpad() -> void:
	var base := PixelArt.sprite(PixelArt.DPAD)
	_draw_sprite(base, _dpad_center, _pixel)
	if _dpad_dir == Vector2.ZERO or base == null:
		return
	var pressed := PixelArt.sprite(PixelArt.DPAD + PixelArt.PRESSED)
	if pressed == null:
		return
	var origin := (_dpad_center - base.get_size() * 0.5 * float(_pixel)).round()
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if Vector2(direction).dot(_dpad_dir) < ARM_THRESHOLD:
			continue
		var region := Rect2(PixelArt.dpad_arm_region(direction))
		var target := Rect2(origin + region.position * float(_pixel), region.size * float(_pixel))
		_view.draw_texture_rect_region(pressed, _to_view_rect(target), region)


func _draw_button(button: Dictionary) -> void:
	var id: StringName = button.id
	var held := is_button_held(id)
	var art: String = button.art
	var tint := Color.WHITE
	var texture := PixelArt.sprite(art + PixelArt.PRESSED) if held else PixelArt.sprite(art)
	if held and PixelArt.has_file(art) and not PixelArt.has_file(art + PixelArt.PRESSED):
		texture = PixelArt.sprite(art)
		tint = TouchArt.TINT_PRESSED
	var center: Vector2 = button.center
	_draw_sprite(texture, center, _pixel, tint)
	var kind: Kind = button.kind
	if kind == Kind.FLAT:
		return
	var action := action_of(id, _side_view)
	var face := center
	if not PixelArt.has_file(art):
		face.y += PixelArt.face_offset(held) * float(_pixel)
	var share := state.cooldown_share(action) if playing else 0.0
	var cooling := share > 0.0 and not held
	var icon := TouchArt.attack_sprite(state.weapon_type) if action == PlayerInput.ATTACK else TouchArt.icon_sprite(icon_of(action, _side_view))
	var icon_pixel := _pixel if kind == Kind.BIG else maxi(1, roundi(_pixel * 0.75))
	_draw_sprite(icon, face, icon_pixel, TouchArt.TINT_DISABLED if cooling else Color.WHITE)
	if cooling:
		var size := int((button.size as Vector2).x)
		var pie := TouchArt.placeholder("touch_cooldown_%d_%d" % [size, TouchArt.cooldown_frame(share)])
		_draw_sprite(pie, center, _pixel)


## texture centred on center (window pixels) at pixel window pixels per texel, snapped to whole
## window pixels.
func _draw_sprite(texture: Texture2D, center: Vector2, pixel: int, tint := Color.WHITE) -> void:
	if texture == null:
		return
	var size := texture.get_size() * float(pixel)
	var rect := Rect2((center - size * 0.5).round(), size)
	_view.draw_texture_rect(texture, _to_view_rect(rect), false, tint)
