class_name TouchOverlay
extends CanvasLayer
## On-screen touch controls (CP2, two sticks): a floating stick on the left moves, the special button
## sits right next to it (the left thumb leaves the stick for it, the player stops briefly); the aim
## stick on the right turns the player and attacks on its own while it is deflected (TouchInput).
## Round buttons around the aim stick dash (in a side-view segment: jump plus a horizontal dash),
## interact and switch the weapon; small buttons at the top open the upgrade overview and the pause
## menu. Symbols only, no text.
## Looks: sprites from art/ui/touch/ via TouchArt (briefing SPRITES_V10 §1) with the drawing below
## as placeholder; the aim stick's knob shows the active weapon, dash and special their cooldown.
## Writes into a TouchState (the device's shared one); visible only while touch is in use and a local
## player that can act polls it, so menus, pauses and the main menu get every tap (emulated mouse).
## Lives under the root window (ensure()), across scene changes.

const LAYER := 25
## Stick reach in viewport pixels and the dead zone as a share of it.
const STICK_RADIUS := 90.0
const STICK_DEAD_ZONE := 0.18
## Dead zone of the aim stick: a resting thumb neither turns nor attacks (TESTWERT).
const AIM_DEAD_ZONE := 0.2
## Left share of the screen that starts the stick (below the top bar).
const STICK_ZONE_WIDTH := 0.45
## Right share of the screen that starts the aim stick (below the top bar, buttons first).
const AIM_ZONE_WIDTH := 0.45
const TOP_BAR_HEIGHT := 110.0
const MARGIN := 28.0
const BUTTON_RADIUS := 50.0
const SMALL_RADIUS := 34.0
## Event buttons: no PlayerInput action, an InputEventAction for the menus instead.
const PAUSE: StringName = &"pause_menu"
const OVERVIEW: StringName = &"upgrade_overview"
## Glyph per button kind.
enum Glyph { SWORD, STAR, DASH, JUMP, SIDE_DASH, HAND, SWAP, PAUSE, LIST }

const COLOR_FILL := Color(0.05, 0.04, 0.08, 0.42)
const COLOR_FILL_PRESSED := Color(0.95, 0.75, 0.35, 0.45)
const COLOR_RING := Color(1.0, 0.86, 0.62, 0.6)
const COLOR_GLYPH := Color(1.0, 0.93, 0.8, 0.9)
const COLOR_STICK := Color(1.0, 0.86, 0.62, 0.35)
const COLOR_RING_DISABLED := Color(0.6, 0.56, 0.68, 0.45)
const COLOR_COOLDOWN := Color(0.02, 0.02, 0.05, 0.55)
## Tints of the normal sprite while a pressed/disabled frame is missing.
const TINT_PRESSED := Color(1.25, 1.1, 0.8)
const TINT_DISABLED := Color(0.55, 0.53, 0.62, 0.8)
const KNOB_RADIUS := 34.0
## Special button relative to the resting move stick: up and to the right, one thumb move away.
const SPECIAL_OFFSET := Vector2(178, -82)

static var _instance: TouchOverlay = null

var state: TouchState
## {action, center, radius, glyph, icon, size, event} of the buttons shown right now (side view
## changes them): radius = touch area, glyph = drawn placeholder, icon/size = TouchArt sprite.
var buttons: Array[Dictionary] = []
var _view: Control
var _shown := false
var _side_view := false
var _layout_size := Vector2.ZERO
## Left stick (movement) and right stick (aim and auto-attack).
var _move_stick := TouchStick.new(STICK_RADIUS, STICK_DEAD_ZONE)
var _aim_stick := TouchStick.new(STICK_RADIUS, AIM_DEAD_ZONE)
var _finger_button: Dictionary[int, StringName] = {}
## Colour of the placeholder glyph being drawn (dimmed while cooling down).
var _ink := COLOR_GLYPH


## Adds the overlay under the root window once (deferred: called from physics frames).
static func ensure(tree: SceneTree) -> void:
	if tree == null or (is_instance_valid(_instance) and not _instance.is_queued_for_deletion()):
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


func _ready() -> void:
	if state.forced and state == TouchState.shared():
		# Forced on a desktop: the mouse acts as one finger, so the controls can be tried out.
		Input.emulate_touch_from_mouse = true
	layout(_screen_rect())


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _process(_delta: float) -> void:
	var rect := _screen_rect()
	if rect.size != _layout_size or state.side_view != _side_view:
		layout(rect)
	set_shown(state.wants_overlay() and not _menu_open())
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


## Places sticks and buttons in rect (the visible area inside the safe area, viewport coordinates).
## Left: move stick, special right next to it. Right: aim stick, the other buttons in an arc above
## and left of it (thumb reach from the bottom right corner).
func layout(rect: Rect2) -> void:
	_layout_size = rect.size
	_side_view = state.side_view
	buttons.clear()
	var normal := TouchArt.Size.NORMAL
	var small := TouchArt.Size.SMALL
	var move_center := _default_stick_center(rect)
	var aim := _default_aim_center(rect)
	_move_stick.set_rest(move_center)
	_aim_stick.set_rest(aim)
	_add(PlayerInput.SPECIAL, move_center + SPECIAL_OFFSET, BUTTON_RADIUS, Glyph.STAR, TouchArt.ICON_SPECIAL, normal)
	if _side_view:
		_add(PlayerInput.DASH, aim + Vector2(-195, 45), BUTTON_RADIUS, Glyph.JUMP, TouchArt.ICON_JUMP, normal)
		_add(PlayerInput.SIDE_DASH, aim + Vector2(-170, -125), BUTTON_RADIUS, Glyph.SIDE_DASH, TouchArt.ICON_SIDE_DASH, normal)
		_add(PlayerInput.SWITCH_WEAPON, aim + Vector2(-345, -30), SMALL_RADIUS + 6.0, Glyph.SWAP, TouchArt.ICON_SWITCH, small)
	else:
		_add(PlayerInput.DASH, aim + Vector2(-195, 45), BUTTON_RADIUS, Glyph.DASH, TouchArt.ICON_DASH, normal)
		_add(PlayerInput.SWITCH_WEAPON, aim + Vector2(-170, -120), SMALL_RADIUS + 6.0, Glyph.SWAP, TouchArt.ICON_SWITCH, small)
	_add(PlayerInput.INTERACT, aim + Vector2(-30, -190), BUTTON_RADIUS, Glyph.HAND, TouchArt.ICON_INTERACT, normal)
	# Top centre: the HUD uses the corners (hearts left, room and gold right).
	var top := Vector2(rect.get_center().x, rect.position.y + MARGIN * 0.5 + SMALL_RADIUS)
	_add(OVERVIEW, top + Vector2(-SMALL_RADIUS * 1.4, 0), SMALL_RADIUS, Glyph.LIST, TouchArt.ICON_MENU, small, true)
	_add(PAUSE, top + Vector2(SMALL_RADIUS * 1.4, 0), SMALL_RADIUS, Glyph.PAUSE, TouchArt.ICON_PAUSE, small, true)


func _add(action: StringName, center: Vector2, radius: float, glyph: Glyph, icon: StringName,
		size: TouchArt.Size, is_event := false) -> void:
	buttons.append({
		"action": action, "center": center, "radius": radius, "glyph": glyph, "icon": icon,
		"size": size, "event": is_event,
	})


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not state.touched:
			state.touched = true
			# The first touch also counts when the player is already waiting for it.
			set_shown(state.wants_overlay() and not _menu_open())
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
		if not _move_stick.is_held() and _in_stick_zone(position):
			state.move = _move_stick.begin(index, position)
			return true
		if not _aim_stick.is_held() and _in_aim_zone(position):
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
	# Both sticks follow a thumb that leaves their ring (floating sticks).
	if index == _move_stick.finger:
		state.move = _move_stick.drag(position)
		return true
	if index == _aim_stick.finger:
		state.aim = _aim_stick.drag(position)
		return true
	return _finger_button.has(index)


## Move stick offset (viewport pixels) → movement of length 0..1 with dead zone.
static func stick_vector(offset: Vector2) -> Vector2:
	return TouchStick.vector(offset, STICK_RADIUS, STICK_DEAD_ZONE)


## Aim stick offset (viewport pixels) → aim of length 0..1 with its dead zone.
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


func _in_stick_zone(position: Vector2) -> bool:
	var rect := _screen_rect()
	return position.x < rect.position.x + rect.size.x * STICK_ZONE_WIDTH and position.y > rect.position.y + TOP_BAR_HEIGHT


func _in_aim_zone(position: Vector2) -> bool:
	var rect := _screen_rect()
	return position.x > rect.end.x - rect.size.x * AIM_ZONE_WIDTH and position.y > rect.position.y + TOP_BAR_HEIGHT


func _default_stick_center(rect: Rect2) -> Vector2:
	# Above the weapon panel of the HUD (bottom left).
	return Vector2(rect.position.x + MARGIN + STICK_RADIUS + 90.0, rect.end.y - 240.0)


func _default_aim_center(rect: Rect2) -> Vector2:
	# Bottom right corner: free in touch mode (the HUD hides its keyboard hint line there).
	return rect.end - Vector2(MARGIN + STICK_RADIUS + 50.0, MARGIN + STICK_RADIUS + 50.0)


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


## Visible viewport area, shrunk to the display's safe area on phones (notches, rounded corners).
func _screen_rect() -> Rect2:
	var viewport := get_viewport() if is_inside_tree() else null
	if viewport == null:
		return Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rect := viewport.get_visible_rect()
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var local := viewport.get_final_transform().affine_inverse() * safe
		if local.has_area():
			rect = rect.intersection(local)
	return rect


# --- Drawing ---
# Sprites from TouchArt (art/ui/touch/, SPRITES_V10) where the file exists, else the drawn
# placeholder below. Missing state frames (pressed, disabled) tint the normal frame.

func _draw_controls() -> void:
	_draw_stick(_move_stick, TouchArt.texture(TouchArt.STICK_BASE), true)
	_draw_stick(_aim_stick, TouchArt.aim_base(), false)
	_draw_aim_icon()
	for button in buttons:
		_draw_button(button)


func _draw_stick(stick: TouchStick, base: Texture2D, with_arrows: bool) -> void:
	var held := stick.is_held()
	if base != null:
		_draw_centered(base, stick.origin, TouchArt.PIXEL)
	else:
		_view.draw_circle(stick.origin, STICK_RADIUS, COLOR_FILL)
		_view.draw_arc(stick.origin, STICK_RADIUS, 0.0, TAU, 48, COLOR_STICK, 3.0, true)
	var arrows := TouchArt.texture(TouchArt.STICK_ARROWS) if with_arrows else null
	if arrows != null:
		_draw_centered(arrows, stick.origin, TouchArt.PIXEL)
	var knob := stick.knob()
	var knob_texture := TouchArt.texture(TouchArt.STICK_KNOB + TouchArt.PRESSED) if held else null
	var knob_tint := Color.WHITE
	if knob_texture == null:
		knob_texture = TouchArt.texture(TouchArt.STICK_KNOB)
		knob_tint = TINT_PRESSED if held else Color.WHITE
	if knob_texture != null:
		_draw_centered(knob_texture, knob, TouchArt.PIXEL, knob_tint)
	else:
		_view.draw_circle(knob, KNOB_RADIUS, COLOR_RING if held else COLOR_STICK)


## The aim stick attacks: its knob carries the icon of the active weapon (sword glyph as placeholder).
func _draw_aim_icon() -> void:
	var knob := _aim_stick.knob()
	var icon := TouchArt.attack_icon(state.weapon_type)
	if icon != null:
		_draw_centered(icon, knob, TouchArt.ICON_PIXELS[TouchArt.Size.NORMAL])
	else:
		_ink = COLOR_GLYPH
		_draw_glyph(Glyph.SWORD, knob, KNOB_RADIUS * 0.6)


func _draw_button(button: Dictionary) -> void:
	var action: StringName = button.action
	var pressed: bool = _finger_button.values().has(action)
	var share := state.cooldown_share(action)
	var disabled := share > 0.0 and not pressed
	var size: TouchArt.Size = button.size
	var center: Vector2 = button.center
	var radius: float = button.radius
	var state_name := TouchArt.PRESSED if pressed else (TouchArt.DISABLED if disabled else "")
	var frame := TouchArt.frame(size, state_name)
	var tint := Color.WHITE
	if frame == null and not state_name.is_empty():
		frame = TouchArt.frame(size)
		tint = TINT_PRESSED if pressed else TINT_DISABLED
	if frame != null:
		_draw_centered(frame, center, TouchArt.PIXEL, tint)
	else:
		var fill := COLOR_FILL_PRESSED if pressed else COLOR_FILL
		_view.draw_circle(center, radius, fill)
		_view.draw_arc(center, radius, 0.0, TAU, 40, COLOR_RING_DISABLED if disabled else COLOR_RING, 3.0, true)
	var icon_tint := TINT_DISABLED if disabled else Color.WHITE
	var icon := _icon_texture(button)
	if icon != null:
		_draw_centered(icon, center, TouchArt.ICON_PIXELS[size], icon_tint)
	else:
		_ink = COLOR_GLYPH * icon_tint
		_draw_glyph(button.glyph, center, radius * 0.5)
	if disabled:
		_draw_cooldown(center, radius, size, share)


func _icon_texture(button: Dictionary) -> Texture2D:
	return TouchArt.icon(button.icon)


## Cooldown on top of a button: frame of touch_cooldown_8f (normal buttons), else a dark pie for the
## part still cooling down and a ring for the part that is done.
func _draw_cooldown(center: Vector2, radius: float, size: TouchArt.Size, share: float) -> void:
	var strip := TouchArt.texture(TouchArt.COOLDOWN)
	if strip != null and size == TouchArt.Size.NORMAL:
		var frame_width := float(strip.get_width()) / TouchArt.COOLDOWN_FRAMES
		var region := Rect2(frame_width * TouchArt.cooldown_frame(share), 0.0, frame_width, strip.get_height())
		var screen_size := region.size * TouchArt.PIXEL
		_view.draw_texture_rect_region(strip, Rect2((center - screen_size * 0.5).round(), screen_size), region)
		return
	var start := -PI / 2.0
	var points := PackedVector2Array([center])
	var steps := maxi(2, ceili(40.0 * share))
	for i in steps + 1:
		points.append(center + Vector2.from_angle(start + TAU * share * i / steps) * (radius - 2.0))
	_view.draw_colored_polygon(points, COLOR_COOLDOWN)
	if share < 1.0:
		_view.draw_arc(center, radius - 1.5, start + TAU * share, start + TAU, 40, COLOR_RING, 4.0, true)


## Texture centred on center at pixel screen pixels per art pixel (whole pixels, crisp).
func _draw_centered(texture: Texture2D, center: Vector2, pixel: int, tint := Color.WHITE) -> void:
	var screen_size := Vector2(texture.get_width(), texture.get_height()) * pixel
	_view.draw_texture_rect(texture, Rect2((center - screen_size * 0.5).round(), screen_size), false, tint)


func _draw_glyph(glyph: Glyph, c: Vector2, s: float) -> void:
	var w := maxf(3.0, s * 0.16)
	match glyph:
		Glyph.SWORD:
			_view.draw_line(c + Vector2(-0.8, 0.8) * s, c + Vector2(0.9, -0.9) * s, _ink, w * 1.3)
			_view.draw_line(c + Vector2(-0.75, 0.15) * s, c + Vector2(-0.15, 0.75) * s, _ink, w)
			_view.draw_line(c + Vector2(-0.8, 0.8) * s, c + Vector2(-1.05, 1.05) * s, _ink, w * 1.6)
		Glyph.STAR:
			var points := PackedVector2Array()
			for i in 10:
				var angle := -PI / 2.0 + i * PI / 5.0
				points.append(c + Vector2.from_angle(angle) * s * (1.0 if i % 2 == 0 else 0.45))
			_view.draw_colored_polygon(points, _ink)
		Glyph.DASH, Glyph.SIDE_DASH:
			_dash_arrow(c + (Vector2(0.0, -0.15) * s if glyph == Glyph.SIDE_DASH else Vector2.ZERO), s, w)
			if glyph == Glyph.SIDE_DASH:
				_view.draw_line(c + Vector2(-0.9, 0.75) * s, c + Vector2(0.9, 0.75) * s, _ink, w * 0.7)
		Glyph.JUMP:
			_chevron(c + Vector2(0.0, -0.1) * s, s * 0.8, -PI / 2.0, w * 1.2)
			_view.draw_line(c + Vector2(-0.7, 0.8) * s, c + Vector2(0.7, 0.8) * s, _ink, w)
		Glyph.HAND:
			_view.draw_arc(c, s * 0.85, 0.0, TAU, 32, _ink, w, true)
			_view.draw_circle(c, s * 0.28, _ink)
		Glyph.SWAP:
			_view.draw_arc(c, s * 0.75, PI * 0.15, PI * 0.95, 16, _ink, w, true)
			_view.draw_arc(c, s * 0.75, PI * 1.15, PI * 1.95, 16, _ink, w, true)
			_arrow_head(c + Vector2.from_angle(PI * 0.95) * s * 0.75, PI * 1.45, s * 0.35)
			_arrow_head(c + Vector2.from_angle(PI * 1.95) * s * 0.75, PI * 0.45, s * 0.35)
		Glyph.PAUSE:
			_view.draw_rect(Rect2(c + Vector2(-0.6, -0.7) * s, Vector2(0.4, 1.4) * s), _ink)
			_view.draw_rect(Rect2(c + Vector2(0.2, -0.7) * s, Vector2(0.4, 1.4) * s), _ink)
		Glyph.LIST:
			for dy in [-0.55, 0.0, 0.55]:
				_view.draw_line(c + Vector2(-0.7, dy) * s, c + Vector2(0.7, dy) * s, _ink, w)


## Dash placeholder: a solid arrow rushing to the right with three speed streaks behind it (reads
## as "quick burst forward", unlike a ">>" that looks like fast-forward).
func _dash_arrow(c: Vector2, s: float, w: float) -> void:
	_view.draw_colored_polygon(PackedVector2Array([
		c + Vector2(1.0, 0.0) * s, c + Vector2(0.3, -0.62) * s, c + Vector2(0.3, -0.24) * s,
		c + Vector2(-0.2, -0.24) * s, c + Vector2(-0.2, 0.24) * s, c + Vector2(0.3, 0.24) * s,
		c + Vector2(0.3, 0.62) * s,
	]), _ink)
	_view.draw_line(c + Vector2(-1.05, 0.0) * s, c + Vector2(-0.4, 0.0) * s, _ink, w)
	for dy in [-0.5, 0.5]:
		_view.draw_line(c + Vector2(-0.9, dy) * s, c + Vector2(-0.35, dy) * s, _ink, w * 0.8)


## A ">" shape pointing at angle (0 = right).
func _chevron(tip_center: Vector2, size: float, angle: float, width: float) -> void:
	var tip := tip_center + Vector2.from_angle(angle) * size * 0.5
	var back := Vector2.from_angle(angle + PI) * size
	_view.draw_polyline(PackedVector2Array([tip + back.rotated(0.7), tip, tip + back.rotated(-0.7)]), _ink, width, true)


func _arrow_head(point: Vector2, angle: float, size: float) -> void:
	var dir := Vector2.from_angle(angle)
	_view.draw_colored_polygon(PackedVector2Array([point + dir * size, point + dir.rotated(2.3) * size * 0.8, point + dir.rotated(-2.3) * size * 0.8]), _ink)
