class_name TouchOverlay
extends CanvasLayer
## On-screen touch controls (CP2, two sticks): a stick on the left moves, the special button sits
## right next to it (the left thumb leaves the stick for it, the player stops briefly); the aim
## stick on the right turns the player and attacks on its own while it is deflected (TouchInput).
## Round buttons around the aim stick dash (in a side-view segment: jump plus a horizontal dash),
## interact and switch the weapon; small buttons at the top open the upgrade overview and the pause
## menu. Symbols only, no text.
## Options (GameOptions, touch section, Projektmitglied 17.10.2026), read every frame so a change
## shows at once: swap sides (move right, aim left; the whole layout mirrors), fixed sticks
## (default; they stay at their place, TouchStick) or floating ones, size (2, 3 or 4 screen pixels
## per art pixel; touch areas and distances scale along) and opacity of the whole overlay.
## Looks: pixel art only (hard edges, whole screen pixels per art pixel, nearest filtering):
## sprites from art/ui/touch/ via TouchArt (briefing SPRITES_V10 §1), else the drawn pixel-art
## placeholders of TouchPixelArt; the aim stick's knob shows the active weapon, dash and special
## their cooldown.
## Writes into a TouchState (the device's shared one); visible only while touch is in use and a local
## player that can act polls it, so menus, pauses and the main menu get every tap (emulated mouse).
## Lives under the root window (ensure()), across scene changes. Places everything inside the
## visible viewport (aspect "expand": any phone format) shrunk to the display's safe area.
## Portrait (phone held upright, PortraitLayout): this overlay hides, the handheld controller field
## below the game screen (PortraitPad) writes the same TouchState instead.

const LAYER := 25
const PortraitLayout := preload("res://ui/touch/portrait_layout.gd")
const PortraitMode := preload("res://ui/touch/portrait_mode.gd")
## Stick reach in viewport pixels at the medium size and the dead zone as a share of it.
const STICK_RADIUS := 90.0
const STICK_DEAD_ZONE := 0.18
## Dead zone of the aim stick: a resting thumb neither turns nor attacks (TESTWERT).
const AIM_DEAD_ZONE := 0.2
## Share of the screen on the move side that starts a floating move stick (below the top bar).
const STICK_ZONE_WIDTH := 0.45
## Share of the screen on the aim side that starts a floating aim stick (below the top bar,
## buttons first).
const AIM_ZONE_WIDTH := 0.45
const TOP_BAR_HEIGHT := 110.0
## A safe area smaller than this share of the screen on either side is ignored (safe_rect).
const MIN_SAFE_SHARE := 0.6
## Web build: how often the page's safe-area insets are read again.
const WEB_SAFE_AREA_MSEC := 1000
## Web build: CSS insets left, top, right, bottom and the page size, comma separated.
const WEB_SAFE_AREA_JS := "(function(){var d=document.createElement('div');d.style.cssText='position:fixed;left:0;top:0;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';document.body.appendChild(d);var s=getComputedStyle(d);var r=[s.paddingLeft,s.paddingTop,s.paddingRight,s.paddingBottom].map(function(v){return parseFloat(v)||0;});d.remove();return r.concat([window.innerWidth,window.innerHeight]).join(',');})()"
const MARGIN := 28.0
## Room kept free under the stick on the left (the HUD's weapon panel), viewport pixels.
const BOTTOM_CLEAR := 150.0
## Touch areas at the medium size.
const BUTTON_RADIUS := 50.0
const SMALL_RADIUS := 34.0
## Event buttons: no PlayerInput action, an InputEventAction for the menus instead.
const PAUSE: StringName = &"pause_menu"
const OVERVIEW: StringName = &"upgrade_overview"
## Special button relative to the resting move stick (medium size, move stick on the left): up and
## towards the screen centre, one thumb move away. Mirrored with swapped sides.
const SPECIAL_OFFSET := Vector2(178, -82)
## Buttons around the aim stick (medium size, aim stick on the right); mirrored with swapped sides.
const DASH_OFFSET := Vector2(-195, 45)
const SIDE_DASH_OFFSET := Vector2(-170, -125)
const SWITCH_OFFSET := Vector2(-170, -120)
## Side view: low and left of the jump button (free of the special also with swapped sides at the
## large size).
const SWITCH_SIDE_VIEW_OFFSET := Vector2(-310, 90)
const INTERACT_OFFSET := Vector2(-30, -190)

static var _instance: TouchOverlay = null
## Web build: last safe area asked from the page and when (-1 = never).
static var _web_safe := Rect2()
static var _web_safe_msec := -1

var state: TouchState
## {action, center, radius, icon, size, event} of the buttons shown right now (side view changes
## them): radius = touch area, icon/size = TouchArt sprite.
var buttons: Array[Dictionary] = []
## Options (see the header). follow_options: read them from GameOptions every frame; tests switch
## it off and call set_options().
var follow_options := true
var swap_sides := false
var floating_sticks := false
## 0 small, 1 medium, 2 large.
var size_step := 1
var opacity := 1.0
var _view: Control
var _shown := false
var _side_view := false
var _layout_size := Vector2.ZERO
## Screen pixels per art pixel of frames and sticks (size option).
var _pixel: int = TouchArt.PIXEL
## Left stick (movement) and right stick (aim and auto-attack); swapped sides swap their places.
var _move_stick := TouchStick.new(STICK_RADIUS, STICK_DEAD_ZONE)
var _aim_stick := TouchStick.new(STICK_RADIUS, AIM_DEAD_ZONE)
var _finger_button: Dictionary[int, StringName] = {}


## Adds the overlay under the root window once (deferred: called from physics frames).
static func ensure(tree: SceneTree) -> void:
	if tree == null:
		return
	# The portrait switch comes along (also when game.tscn is started directly).
	PortraitMode.ensure(tree)
	if is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return
	_instance = TouchOverlay.new()
	_instance.name = "TouchOverlay"
	tree.root.add_child.call_deferred(_instance)


func _init(touch_state: TouchState = null) -> void:
	state = touch_state if touch_state != null else TouchState.shared()
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_view = Control.new()
	_view.name = "View"
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.draw.connect(_draw_controls)
	add_child(_view)
	_apply_options()


func _ready() -> void:
	if state.forced and state == TouchState.shared():
		# Forced on a desktop: the mouse acts as one finger, so the controls can be tried out.
		Input.emulate_touch_from_mouse = true
	if follow_options:
		_read_options()
	layout(_screen_rect())


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _process(_delta: float) -> void:
	if follow_options:
		_read_options()
	var rect := _screen_rect()
	if rect.size != _layout_size or state.side_view != _side_view:
		layout(rect)
	set_shown(state.wants_overlay() and not _menu_open() and not PortraitLayout.is_active())
	if _shown:
		_view.queue_redraw()


func is_shown() -> bool:
	return _shown


func set_shown(value: bool) -> void:
	if value == _shown:
		return
	_shown = value
	visible = value
	if not value:
		_release_everything()


## Sets the options (see the header) and lays the controls out again if they changed.
func set_options(swap: bool, floating: bool, step: int, alpha: float) -> void:
	step = clampi(step, 0, 2)
	alpha = clampf(alpha, 0.0, 1.0)
	if swap == swap_sides and floating == floating_sticks and step == size_step and is_equal_approx(alpha, opacity):
		return
	var relayout := swap != swap_sides or step != size_step
	swap_sides = swap
	floating_sticks = floating
	size_step = step
	opacity = alpha
	_apply_options()
	if relayout:
		# Fingers on the old places would point at the wrong controls.
		_release_everything()
		layout(_screen_rect())


## Screen pixels per art pixel at the current size (2, 3 or 4).
func get_pixel() -> int:
	return _pixel


## Size factor against the medium size (touch areas, distances).
func get_size_factor() -> float:
	return float(_pixel) / float(TouchArt.PIXEL)


## Reach of both sticks in viewport pixels at the current size.
func get_stick_radius() -> float:
	return STICK_RADIUS * get_size_factor()


func _read_options() -> void:
	set_options(GameOptions.is_touch_swap_sides(), GameOptions.are_touch_sticks_floating(),
			GameOptions.get_touch_size(), GameOptions.get_touch_opacity())


func _apply_options() -> void:
	_pixel = TouchArt.PIXEL + size_step - 1
	for stick in [_move_stick, _aim_stick]:
		stick.radius = get_stick_radius()
		stick.fixed = not floating_sticks
	_view.modulate = Color(1, 1, 1, opacity)


## Places sticks and buttons in rect (the visible area inside the safe area, viewport coordinates).
## Move side: move stick, special right next to it. Aim side: aim stick, the other buttons in an
## arc above and towards the centre (thumb reach from the bottom corner). The left stick sits
## above the HUD's weapon panel, the right one in the bottom corner; swapped sides swap the sticks
## and mirror their buttons.
func layout(rect: Rect2) -> void:
	_layout_size = rect.size
	_side_view = state.side_view
	buttons.clear()
	var normal := TouchArt.Size.NORMAL
	var small := TouchArt.Size.SMALL
	var factor := get_size_factor()
	var left := _left_stick_center(rect)
	var right := _right_stick_center(rect)
	var move_center := right if swap_sides else left
	var aim := left if swap_sides else right
	var mirror := Vector2(-1.0 if swap_sides else 1.0, 1.0) * factor
	_move_stick.set_rest(move_center)
	_aim_stick.set_rest(aim)
	var button_radius := BUTTON_RADIUS * factor
	var small_radius := SMALL_RADIUS * factor
	_add(PlayerInput.SPECIAL, move_center + SPECIAL_OFFSET * mirror, button_radius, TouchArt.ICON_SPECIAL, normal)
	if _side_view:
		_add(PlayerInput.DASH, aim + DASH_OFFSET * mirror, button_radius, TouchArt.ICON_JUMP, normal)
		_add(PlayerInput.SIDE_DASH, aim + SIDE_DASH_OFFSET * mirror, button_radius, TouchArt.ICON_SIDE_DASH, normal)
		_add(PlayerInput.SWITCH_WEAPON, aim + SWITCH_SIDE_VIEW_OFFSET * mirror, small_radius + 6.0 * factor, TouchArt.ICON_SWITCH, small)
	else:
		_add(PlayerInput.DASH, aim + DASH_OFFSET * mirror, button_radius, TouchArt.ICON_DASH, normal)
		_add(PlayerInput.SWITCH_WEAPON, aim + SWITCH_OFFSET * mirror, small_radius + 6.0 * factor, TouchArt.ICON_SWITCH, small)
	_add(PlayerInput.INTERACT, aim + INTERACT_OFFSET * mirror, button_radius, TouchArt.ICON_INTERACT, normal)
	# Top centre: the HUD uses the corners (hearts left, room and gold right).
	var top := Vector2(rect.get_center().x, rect.position.y + MARGIN * 0.5 + small_radius)
	_add(OVERVIEW, top + Vector2(-small_radius * 1.4, 0), small_radius, TouchArt.ICON_MENU, small, true)
	_add(PAUSE, top + Vector2(small_radius * 1.4, 0), small_radius, TouchArt.ICON_PAUSE, small, true)


func _add(action: StringName, center: Vector2, radius: float, icon: StringName, size: TouchArt.Size,
		is_event := false) -> void:
	buttons.append({
		"action": action, "center": center, "radius": radius, "icon": icon, "size": size,
		"event": is_event,
	})


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not state.touched:
			state.touched = true
			# The first touch also counts when the player is already waiting for it.
			set_shown(state.wants_overlay() and not _menu_open() and not PortraitLayout.is_active())
		if _shown and handle_touch(event.index, event.position, event.pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if _shown and handle_drag(event.index, event.position):
			get_viewport().set_input_as_handled()
	elif not state.forced and _is_desktop_input(event):
		# Keyboard or a real mouse: back to the desktop controls until the next touch.
		state.touched = false


## A finger went down or up; true if the overlay used it.
func handle_touch(index: int, position: Vector2, pressed: bool) -> bool:
	if pressed:
		var button := button_at(position)
		if not button.is_empty():
			_finger_button[index] = button.action
			_press_button(button)
			return true
		if not _move_stick.is_held() and _can_start(_move_stick, position, swap_sides, STICK_ZONE_WIDTH):
			state.move = _move_stick.begin(index, position)
			return true
		if not _aim_stick.is_held() and _can_start(_aim_stick, position, not swap_sides, AIM_ZONE_WIDTH):
			state.aim = _aim_stick.begin(index, position, _aim_stick.is_on_ring(position))
			return true
		return false
	if _finger_button.has(index):
		_release_button(_finger_button[index])
		_finger_button.erase(index)
		return true
	if index == _move_stick.finger:
		_move_stick.end()
		state.move = Vector2.ZERO
		return true
	if index == _aim_stick.finger:
		_aim_stick.end()
		state.aim = Vector2.ZERO
		return true
	return false


## A finger moved; true if the overlay used it.
func handle_drag(index: int, position: Vector2) -> bool:
	# Floating sticks follow a thumb that leaves their ring; fixed ones stay (TouchStick).
	if index == _move_stick.finger:
		state.move = _move_stick.drag(position)
		return true
	if index == _aim_stick.finger:
		state.aim = _aim_stick.drag(position)
		return true
	return _finger_button.has(index)


## Move stick offset (viewport pixels, medium size) → movement of length 0..1 with dead zone.
static func stick_vector(offset: Vector2) -> Vector2:
	return TouchStick.vector(offset, STICK_RADIUS, STICK_DEAD_ZONE)


## Aim stick offset (viewport pixels, medium size) → aim of length 0..1 with its dead zone.
static func aim_vector(offset: Vector2) -> Vector2:
	return TouchStick.vector(offset, STICK_RADIUS, AIM_DEAD_ZONE)


## The button under position (slightly generous), or {}.
func button_at(position: Vector2) -> Dictionary:
	for button in buttons:
		if position.distance_to(button.center) <= float(button.radius) * 1.15:
			return button
	return {}


func is_stick_held() -> bool:
	return _move_stick.is_held()


func is_aim_held() -> bool:
	return _aim_stick.is_held()


## Resting centre of the aim stick (layout; tests, screenshots).
func get_aim_rest() -> Vector2:
	return _aim_stick.rest


## Resting centre of the move stick (layout; tests, screenshots).
func get_stick_rest() -> Vector2:
	return _move_stick.rest


## Where the knobs are drawn right now (tests: a fixed stick never moves).
func get_stick_origin() -> Vector2:
	return _move_stick.origin


func get_aim_origin() -> Vector2:
	return _aim_stick.origin


func _press_button(button: Dictionary) -> void:
	if not button.event:
		state.press(button.action)
	# Menus and intros listen to the actions as events: mirror the button.
	if InputMap.has_action(button.action):
		_send_action(button.action, true)


func _release_button(action: StringName) -> void:
	state.release(action)
	if InputMap.has_action(action):
		_send_action(action, false)


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	# Deferred: no nested dispatch from inside _input.
	Input.parse_input_event.call_deferred(event)


func _release_everything() -> void:
	for index in _finger_button.keys():
		_release_button(_finger_button[index])
	_finger_button.clear()
	_move_stick.end()
	_aim_stick.end()
	state.release_all()


## A free finger at position may take stick: a fixed stick near its ring (TouchStick.can_grab), a
## floating one in its zone (share of the screen on the right or left, below the top bar).
func _can_start(stick: TouchStick, position: Vector2, right_side: bool, zone_width: float) -> bool:
	var rect := _screen_rect()
	if position.y <= rect.position.y + TOP_BAR_HEIGHT:
		return false
	if stick.fixed:
		return stick.can_grab(position)
	if right_side:
		return position.x > rect.end.x - rect.size.x * zone_width
	return position.x < rect.position.x + rect.size.x * zone_width


func _left_stick_center(rect: Rect2) -> Vector2:
	# Above the weapon panel of the HUD (bottom left).
	var radius := get_stick_radius()
	return Vector2(rect.position.x + MARGIN + radius + 90.0 * get_size_factor(), rect.end.y - BOTTOM_CLEAR - radius)


func _right_stick_center(rect: Rect2) -> Vector2:
	# Bottom right corner: free in touch mode (the HUD hides its keyboard hint line there).
	var inset := MARGIN + get_stick_radius() + 50.0 * get_size_factor()
	return rect.end - Vector2(inset, inset)


## A modal is open (pause menu, shop, upgrade choice; in a group game too, where nothing pauses).
func _menu_open() -> bool:
	return get_tree().paused or GameManager.is_game_paused()


static func _is_desktop_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		# Phones send keys for system buttons (back); only a desktop keyboard switches back.
		return event.pressed and not OS.has_feature("mobile")
	# Only mouse buttons: in the browser every finger drag also arrives as a mouse motion with
	# device 32 instead of DEVICE_ID_EMULATION, which would hide the touch controls mid-move.
	if event is InputEventMouseButton:
		return event.device != InputEvent.DEVICE_ID_EMULATION
	return false


## Visible viewport area, shrunk to the display's safe area on phones (notches, rounded corners,
## camera holes left or right in landscape). 1280×720 only as a fallback outside the tree.
func _screen_rect() -> Rect2:
	var viewport := get_viewport() if is_inside_tree() else null
	if viewport == null:
		return Rect2(Vector2.ZERO, Vector2(1280, 720))
	return safe_rect(viewport.get_visible_rect(), viewport.get_final_transform(), _display_safe_area())


## visible (viewport coordinates) shrunk to safe (window pixels, empty = none) mapped through the
## viewport's final transform. A safe area that would leave less than MIN_SAFE_SHARE of either side
## counts as wrong (other units, a stale value) and is ignored. Separate from the display for tests.
static func safe_rect(visible: Rect2, final_transform: Transform2D, safe: Rect2) -> Rect2:
	if not safe.has_area():
		return visible
	var local := final_transform.affine_inverse() * safe
	var inner := visible.intersection(local)
	if inner.size.x < visible.size.x * MIN_SAFE_SHARE or inner.size.y < visible.size.y * MIN_SAFE_SHARE:
		return visible
	return inner


## The display's safe area in window pixels: Android and iOS exports ask the display; the web
## build asks the page (its canvas covers the notch, viewport-fit=cover in deploy/web/shell.html)
## for the CSS insets env(safe-area-inset-*). Empty elsewhere.
static func _display_safe_area() -> Rect2:
	if OS.has_feature("web"):
		return _web_safe_area()
	if not OS.has_feature("mobile"):
		return Rect2()
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var window := DisplayServer.window_get_position()
	safe.position -= Vector2(window)
	return safe


## Web: the page's safe-area insets as shares of the page size, applied to the window size (units
## stay right whatever the device pixel ratio). Asked at most once per WEB_SAFE_AREA_MSEC (turning
## the phone changes them).
static func _web_safe_area() -> Rect2:
	var now := Time.get_ticks_msec()
	if _web_safe_msec >= 0 and now - _web_safe_msec < WEB_SAFE_AREA_MSEC:
		return _web_safe
	_web_safe_msec = now
	_web_safe = Rect2()
	var answer: Variant = JavaScriptBridge.eval(WEB_SAFE_AREA_JS, true)
	if typeof(answer) != TYPE_STRING:
		return _web_safe
	var parts := (answer as String).split(",")
	if parts.size() != 6:
		return _web_safe
	var values: Array[float] = []
	for part in parts:
		values.append(float(part))
	var page := Vector2(values[4], values[5])
	if page.x <= 0.0 or page.y <= 0.0:
		return _web_safe
	var window := Vector2(DisplayServer.window_get_size())
	var page_scale := window / page
	var top_left := Vector2(values[0], values[1]) * page_scale
	var bottom_right := Vector2(values[2], values[3]) * page_scale
	_web_safe = Rect2(top_left, window - top_left - bottom_right)
	return _web_safe


# --- Drawing ---
# Pixel art only: TouchArt hands out the file from art/ui/touch/ (SPRITES_V10) or the drawn
# placeholder of TouchPixelArt; everything is drawn at whole screen pixels per art pixel.

func _draw_controls() -> void:
	_draw_stick(_move_stick, false)
	_draw_stick(_aim_stick, true)
	_draw_aim_icon()
	for button in buttons:
		_draw_button(button)


func _draw_stick(stick: TouchStick, aim: bool) -> void:
	_draw_centered(TouchArt.stick_base_sprite(aim), stick.origin, _pixel)
	if not aim:
		var arrows := TouchArt.arrows_sprite()
		if arrows != null:
			_draw_centered(arrows, stick.origin, _pixel)
	var knob := TouchArt.knob_sprite(stick.is_held())
	_draw_centered(knob.texture, stick.knob(), _pixel, knob.tint)


## The aim stick attacks: its knob carries the icon of the active weapon.
func _draw_aim_icon() -> void:
	var icon := TouchArt.attack_sprite(state.weapon_type)
	_draw_centered(icon, _aim_stick.knob(), TouchArt.icon_pixel(TouchArt.Size.NORMAL, _pixel))


func _draw_button(button: Dictionary) -> void:
	var action: StringName = button.action
	var pressed: bool = _finger_button.values().has(action)
	var share := state.cooldown_share(action)
	var disabled := share > 0.0 and not pressed
	var size: TouchArt.Size = button.size
	var center: Vector2 = button.center
	var state_name := TouchArt.PRESSED if pressed else (TouchArt.DISABLED if disabled else "")
	var frame := TouchArt.frame_sprite(size, state_name)
	_draw_centered(frame.texture, center, _pixel, frame.tint)
	var face := center + Vector2(0.0, TouchArt.face_offset(size, pressed) * _pixel)
	var icon := TouchArt.icon_sprite(button.icon)
	_draw_centered(icon, face, TouchArt.icon_pixel(size, _pixel), TouchArt.TINT_DISABLED if disabled else Color.WHITE)
	if disabled:
		var cooldown := TouchArt.cooldown_sprite(size, share)
		var region: Rect2 = cooldown.region
		var screen_size := region.size * _pixel
		_view.draw_texture_rect_region(cooldown.texture, Rect2((center - screen_size * 0.5).round(), screen_size), region)


## Texture centred on center at pixel screen pixels per art pixel (whole pixels, crisp).
func _draw_centered(texture: Texture2D, center: Vector2, pixel: int, tint := Color.WHITE) -> void:
	if texture == null:
		return
	var screen_size := Vector2(texture.get_width(), texture.get_height()) * pixel
	_view.draw_texture_rect(texture, Rect2((center - screen_size * 0.5).round(), screen_size), false, tint)
