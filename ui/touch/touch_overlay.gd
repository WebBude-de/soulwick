class_name TouchOverlay
extends CanvasLayer
## On-screen touch controls (CP2, two sticks): a stick on the left moves, the special button sits
## right next to it (the left thumb leaves the stick for it, the player stops briefly); the aim
## stick on the right turns the player and attacks on its own while it is deflected (TouchInput).
## Round buttons around the aim stick dash (in a side-view segment: jump plus a horizontal dash),
## interact and switch the weapon, and above them cast the equipped spells (KE7, shown only with a
## spell, symbol of the spell); small buttons at the top open the upgrade overview and the pause
## menu, right of them the return stone (KE5, only while the local player's stone is ready). Symbols
## only, no text.
## Options (GameOptions, touch section, Projektmitglied 17.10.2026), read every frame so a change
## shows at once: swap sides (move right, aim left; the whole layout mirrors), fixed sticks
## (default; they stay at their place, TouchStick) or floating ones, size and opacity of the whole
## overlay.
## Size (D-219, playtest 26.10.2026: "viel zu klein"; default large): each step wants a normal
## button of TARGET_BUTTON_MM on the real screen (TouchMetrics: DPI of the phone, a typical phone
## elsewhere), as whole screen pixels per art pixel (never fewer than before D-219, MIN_PIXELS);
## every touch area is at least MIN_TOUCH_MM wide and never smaller than its picture. The layout is
## built from the sizes (rings of buttons around the sticks, GAP_ART apart); if it does not fit the
## screen without overlaps (top row, the HUD's weapon block bottom left), the size steps down.
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
## Dead zone of the move stick as a share of its reach.
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
## Kept free bottom left (the HUD's compact weapon block: about 414 × 79 viewport pixels with its
## margin, measured 26.10.2026); the stick on the left sits right above it.
const HUD_CLEAR := Vector2(420, 86)
## Size steps small, medium, large (D-219, TESTWERT): wanted width of a normal button's frame in
## mm, and the fewest screen pixels per art pixel (the sizes before D-219: 2, 3, 4).
const TARGET_BUTTON_MM: Array[float] = [9.0, 11.5, 14.0]
const MIN_PIXELS: Array[int] = [2, 3, 4]
const MIN_PIXEL := 2
## Every touch area is at least this wide (mm; D-219 "Daumenfläche mindestens 12 mm", TESTWERT).
const MIN_TOUCH_MM := 12.0
## Very small screens (a 4" phone held sideways): if nothing fits even at MIN_PIXEL, the touch areas
## shrink in these steps (mm; 0 = as big as the picture).
const FALLBACK_TOUCH_MM: Array[float] = [10.0, 8.0, 0.0]
## A touch this much beyond a touch area still counts (share of its radius).
const TOUCH_SLACK := 1.15
## Art pixels: stick reach (the drawn base is 60 wide), free space between neighbouring controls,
## the sticks' extra distance from the screen edges.
const STICK_REACH_ART := 30
const GAP_ART := 3
const STICK_INSET_ART := 6
## Controls never come closer than this (viewport pixels), whatever the size.
const MIN_GAP := 6.0
## Event buttons: no PlayerInput action, an InputEventAction for the menus instead.
const PAUSE: StringName = &"pause_menu"
const OVERVIEW: StringName = &"upgrade_overview"
## Directions in degrees (0 = right, 90 = down) for the stick on its usual side; swapped sides
## mirror them. Special: on the ring around the move stick, up and towards the screen centre.
const SPECIAL_ANGLE := -30.0
## Ring 1 around the aim stick, from low left over the top: dash (side view: jump), the cast
## buttons (KE7; shown only while the local player has a spell in that slot, the second one only
## with a second cast action), interact.
const DASH_ANGLE := 165.0
const SPELL_2_ANGLE := 207.0
const SPELL_ANGLE := 249.0
const INTERACT_ANGLE := 291.0
## Ring 2 (outside ring 1, in its gaps): switch weapon left of the stick; in a side view the side
## dash takes that place and switch moves up between the cast buttons.
const SWITCH_ANGLE := 186.0
const SWITCH_SIDE_VIEW_ANGLE := 228.0
## Smallest angle between neighbours on ring 1 (the angles above are this far apart); a ring too
## small for it grows.
const RING_STEP := 42.0
const SPELL_ACTIONS: Array[StringName] = [PlayerSpells.ACTION, PlayerSpells.ACTION_2]
## Return stone button (KE5): the Proviant's icon until a touch icon is delivered.
const RETURN_STONE_ICON_PATH := "res://art/ui/trading/boost_return_stone.png"

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
## 0 small, 1 medium, 2 large (default, D-219).
var size_step := 2
var opacity := 1.0
## Millimetres per viewport pixel; 0 = from the device (TouchMetrics). Tests and previews set it.
var mm_per_px := 0.0
## Smallest touch area of the last layout in mm (MIN_TOUCH_MM unless the screen is tiny).
var _touch_mm := MIN_TOUCH_MM
var _view: Control
var _shown := false
var _side_view := false
var _layout_size := Vector2.ZERO
## Screen pixels per art pixel of frames and sticks (size option, screen, fit; layout()).
var _pixel: int = TouchArt.PIXEL
## Left stick (movement) and right stick (aim and auto-attack); swapped sides swap their places.
var _move_stick := TouchStick.new(STICK_REACH_ART * TouchArt.PIXEL, STICK_DEAD_ZONE)
var _aim_stick := TouchStick.new(STICK_REACH_ART * TouchArt.PIXEL, AIM_DEAD_ZONE)
var _finger_button: Dictionary[int, StringName] = {}
## Spells of the local player per cast button (empty = button hidden), refreshed every frame.
var _spells: Array[StringName] = [&"", &""]
## The local player's return stone is ready (button shown), refreshed every frame.
var _stone_ready := false


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
	_read_spells()
	_read_return_stone()
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


## Screen pixels per art pixel at the current size (layout(): option, screen size, fit).
func get_pixel() -> int:
	return _pixel


## Reach of both sticks in viewport pixels at the current size.
func get_stick_radius() -> float:
	return float(STICK_REACH_ART * _pixel)


## Millimetres per viewport pixel used by the last layout.
func get_mm_per_px() -> float:
	return _mm_for(Rect2(Vector2.ZERO, _layout_size))


## Smallest touch area of the last layout in mm (MIN_TOUCH_MM unless the screen is tiny).
func get_touch_mm() -> float:
	return _touch_mm


func _read_options() -> void:
	set_options(GameOptions.is_touch_swap_sides(), GameOptions.are_touch_sticks_floating(),
			GameOptions.get_touch_size(), GameOptions.get_touch_opacity())


func _apply_options() -> void:
	for stick in [_move_stick, _aim_stick]:
		stick.fixed = not floating_sticks
	_view.modulate = Color(1, 1, 1, opacity)


## Millimetres per viewport pixel for a layout in rect: the set value, else the device's.
func _mm_for(rect: Rect2) -> float:
	if mm_per_px > 0.0:
		return mm_per_px
	var window := Vector2(get_window().size) if is_inside_tree() else rect.size
	return TouchMetrics.mm_per_view_px(rect.size, window)


## Places sticks and buttons in rect (the visible area inside the safe area, viewport coordinates)
## at the biggest size up to the wanted one that fits (fitted_pixel). Move side: move stick above
## the HUD's weapon block, special next to it. Aim side: aim stick in the bottom corner, the other
## buttons on two rings above and towards the centre (thumb reach from the corner). Swapped sides
## swap the sticks and mirror their buttons.
func layout(rect: Rect2) -> void:
	_layout_size = rect.size
	_side_view = state.side_view
	var mm := _mm_for(rect)
	var size := fitted_size(rect, size_step, mm, swap_sides)
	_pixel = int(size.x)
	_touch_mm = size.y
	var plan := arrange(rect, _pixel, mm, swap_sides, _side_view, _touch_mm)
	for stick in [_move_stick, _aim_stick]:
		stick.radius = plan.reach
	_move_stick.set_rest(plan.move)
	_aim_stick.set_rest(plan.aim)
	buttons.assign(plan.buttons)


## Screen pixels per art pixel a size step wants at mm_per_view_px (D-219): a normal button frame of
## TARGET_BUTTON_MM, at least MIN_PIXELS.
static func wanted_pixel(step: int, mm_per_view_px: float) -> int:
	step = clampi(step, 0, TARGET_BUTTON_MM.size() - 1)
	var frame_mm := float(TouchArt.FRAME_ART_SIZES[TouchArt.Size.NORMAL]) * maxf(0.0001, mm_per_view_px)
	return maxi(MIN_PIXELS[step], roundi(TARGET_BUTTON_MM[step] / frame_mm))


## (pixel, smallest touch area in mm): the wanted pixel size, stepped down until both views
## (top-down and side view) fit into rect; on a tiny screen also smaller touch areas
## (FALLBACK_TOUCH_MM).
static func fitted_size(rect: Rect2, step: int, mm_per_view_px: float, swap: bool) -> Vector2:
	var touch_sizes: Array[float] = [MIN_TOUCH_MM]
	touch_sizes.append_array(FALLBACK_TOUCH_MM)
	for touch_mm in touch_sizes:
		var pixel := wanted_pixel(step, mm_per_view_px)
		while pixel > MIN_PIXEL and not fits(rect, pixel, mm_per_view_px, swap, touch_mm):
			pixel -= 1
		if fits(rect, pixel, mm_per_view_px, swap, touch_mm):
			return Vector2(pixel, touch_mm)
	return Vector2(MIN_PIXEL, 0.0)


## Screen pixels per art pixel of fitted_size().
static func fitted_pixel(rect: Rect2, step: int, mm_per_view_px: float, swap: bool) -> int:
	return int(fitted_size(rect, step, mm_per_view_px, swap).x)


## Every control of both views inside rect, none overlapping another, the HUD's weapon block (bottom
## left, HUD_CLEAR) free and the ring buttons below the top bar.
static func fits(rect: Rect2, pixel: int, mm_per_view_px: float, swap: bool, touch_mm := MIN_TOUCH_MM) -> bool:
	for side_view in [false, true]:
		var plan := arrange(rect, pixel, mm_per_view_px, swap, side_view, touch_mm)
		var circles: Array[Vector3] = [Vector3(plan.move.x, plan.move.y, plan.reach), Vector3(plan.aim.x, plan.aim.y, plan.reach)]
		for button: Dictionary in plan.buttons:
			circles.append(Vector3(button.center.x, button.center.y, button.radius))
		var inner := rect.grow(-2.0)
		var hud := Rect2(rect.position.x, rect.end.y - HUD_CLEAR.y, HUD_CLEAR.x, HUD_CLEAR.y)
		for i in circles.size():
			var circle := circles[i]
			var center := Vector2(circle.x, circle.y)
			var corner := Vector2(circle.z, circle.z)
			if not (inner.has_point(center - corner) and inner.has_point(center + corner)):
				return false
			var nearest := center.clamp(hud.position, hud.end)
			if nearest.distance_to(center) < circle.z:
				return false
			var is_top := false
			if i >= 2:
				var button: Dictionary = plan.buttons[i - 2]
				is_top = button.event or button.action == PlayerInput.USE_RETURN_STONE
			if not is_top and center.y - circle.z < rect.position.y + TOP_BAR_HEIGHT:
				return false
			for j in range(i + 1, circles.size()):
				var other := circles[j]
				if center.distance_to(Vector2(other.x, other.y)) - circle.z - other.z <= MIN_GAP:
					return false
	return true


## {move, aim: resting stick centres, reach: stick reach, buttons: [{action, center, radius, icon,
## size, event}]} for rect at pixel screen pixels per art pixel (radius = touch area: the frame, at
## least touch_mm wide).
static func arrange(rect: Rect2, pixel: int, mm_per_view_px: float, swap: bool, side_view: bool,
		touch_mm := MIN_TOUCH_MM) -> Dictionary:
	var p := float(pixel)
	var reach := STICK_REACH_ART * p
	var gap := GAP_ART * p
	var min_radius := TouchMetrics.px(touch_mm, mm_per_view_px) * 0.5
	var normal := maxf(TouchArt.frame_screen_size(TouchArt.Size.NORMAL, pixel) * 0.5, min_radius)
	var small := maxf(TouchArt.frame_screen_size(TouchArt.Size.SMALL, pixel) * 0.5, min_radius)
	# Ring 1 touches the stick and leaves room between its neighbours (RING_STEP apart); ring 2 lies
	# a whole button further out.
	var ring_1_normal := maxf(reach + gap + normal, (2.0 * normal + gap) / (2.0 * sin(deg_to_rad(RING_STEP) * 0.5)))
	var ring_1 := func(radius: float) -> float: return ring_1_normal - normal + radius
	var ring_2 := func(radius: float) -> float: return ring_1_normal + normal + gap + radius
	# Sticks MARGIN plus a little from the edges; the aim stick further in where ring 1 reaches past
	# it (interact towards the outer edge, dash towards the bottom).
	var inset := MARGIN + reach + STICK_INSET_ART * p
	var ring_out := Vector2(ring_1_normal * maxf(0.0, cos(deg_to_rad(INTERACT_ANGLE))),
			ring_1_normal * maxf(0.0, sin(deg_to_rad(DASH_ANGLE)))) + Vector2(normal, normal)
	var aim_inset := Vector2(maxf(inset, MARGIN * 0.5 + ring_out.x), maxf(inset, MARGIN * 0.5 + ring_out.y))
	var move_inset := Vector2(inset, inset)
	# The left place sits above the HUD's weapon block (with swapped sides the dash below the aim
	# stick too), the right one in the corner.
	var left_inset := aim_inset if swap else move_inset
	var right_inset := move_inset if swap else aim_inset
	# Whole pixels, one more for the rounded button centres.
	var above_hud := maxf(reach, ceilf(ring_out.y) + 1.0 if swap else 0.0)
	var left := Vector2(rect.position.x + left_inset.x, rect.end.y - HUD_CLEAR.y - above_hud).round()
	var right := (rect.end - right_inset).round()
	var move := right if swap else left
	var aim := left if swap else right
	var at := func(center: Vector2, angle: float, distance: float) -> Vector2:
		var direction := Vector2.from_angle(deg_to_rad(angle))
		if swap:
			direction.x = -direction.x
		return (center + direction * distance).round()
	var result: Array[Dictionary] = []
	result.append(_entry(PlayerInput.SPECIAL, at.call(move, SPECIAL_ANGLE, ring_1.call(normal)), normal, TouchArt.ICON_SPECIAL, TouchArt.Size.NORMAL))
	if side_view:
		result.append(_entry(PlayerInput.DASH, at.call(aim, DASH_ANGLE, ring_1.call(normal)), normal, TouchArt.ICON_JUMP, TouchArt.Size.NORMAL))
		result.append(_entry(PlayerInput.SIDE_DASH, at.call(aim, SWITCH_ANGLE, ring_2.call(normal)), normal, TouchArt.ICON_SIDE_DASH, TouchArt.Size.NORMAL))
		result.append(_entry(PlayerInput.SWITCH_WEAPON, at.call(aim, SWITCH_SIDE_VIEW_ANGLE, ring_2.call(small)), small, TouchArt.ICON_SWITCH, TouchArt.Size.SMALL))
	else:
		result.append(_entry(PlayerInput.DASH, at.call(aim, DASH_ANGLE, ring_1.call(normal)), normal, TouchArt.ICON_DASH, TouchArt.Size.NORMAL))
		result.append(_entry(PlayerInput.SWITCH_WEAPON, at.call(aim, SWITCH_ANGLE, ring_2.call(small)), small, TouchArt.ICON_SWITCH, TouchArt.Size.SMALL))
	result.append(_entry(PlayerInput.INTERACT, at.call(aim, INTERACT_ANGLE, ring_1.call(normal)), normal, TouchArt.ICON_INTERACT, TouchArt.Size.NORMAL))
	result.append(_entry(PlayerSpells.ACTION, at.call(aim, SPELL_ANGLE, ring_1.call(normal)), normal, TouchArt.ICON_SPELL, TouchArt.Size.NORMAL))
	result.append(_entry(PlayerSpells.ACTION_2, at.call(aim, SPELL_2_ANGLE, ring_1.call(normal)), normal, TouchArt.ICON_SPELL, TouchArt.Size.NORMAL))
	# Top centre (the HUD uses the corners: hearts left, room and gold right): overview and pause,
	# the return stone on the move side, away from the buttons around the aim stick.
	var top := Vector2(rect.get_center().x, rect.position.y + MARGIN * 0.5 + small).round()
	var outwards := 1.0 if swap else -1.0
	result.append(_entry(OVERVIEW, top + Vector2(small * 1.4 * outwards, 0), small, TouchArt.ICON_MENU, TouchArt.Size.SMALL, true))
	result.append(_entry(PAUSE, top - Vector2(small * 1.4 * outwards, 0), small, TouchArt.ICON_PAUSE, TouchArt.Size.SMALL, true))
	# The Proviant's icon is drawn over it (RETURN_STONE_ICON_PATH); interact is the fallback.
	result.append(_entry(PlayerInput.USE_RETURN_STONE, top + Vector2(small * 4.2 * outwards, 0), small, TouchArt.ICON_INTERACT, TouchArt.Size.SMALL))
	return {"move": move, "aim": aim, "reach": reach, "buttons": result}


static func _entry(action: StringName, center: Vector2, radius: float, icon: StringName, size: TouchArt.Size,
		is_event := false) -> Dictionary:
	return {
		"action": action, "center": center, "radius": radius, "icon": icon, "size": size,
		"event": is_event,
	}


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


## The button under position (slightly generous, TOUCH_SLACK; the nearest wins), or {}. Hidden
## cast buttons take no finger.
func button_at(position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for button in buttons:
		var distance := position.distance_to(button.center)
		if is_button_active(button) and distance <= float(button.radius) * TOUCH_SLACK and distance < best_distance:
			best = button
			best_distance = distance
	return best


## Every button but a cast button without a spell (KE7) and the return stone while it is not ready.
func is_button_active(button: Dictionary) -> bool:
	if button.action == PlayerInput.USE_RETURN_STONE:
		return _stone_ready
	var slot := SPELL_ACTIONS.find(button.action)
	return slot < 0 or _spells[slot] != &""


## Spell shown on the cast button of slot (0 or 1), &"" = hidden.
func get_spell_on_button(slot: int) -> StringName:
	return _spells[slot] if slot >= 0 and slot < _spells.size() else &""


## Spells and their cooldowns of the local player for the cast buttons (display only, the press
## goes through the TouchState like every button). Without a second cast action the one button
## casts both slots (PlayerSpells.slot_for_button), so only the first button shows.
func set_spells(spells: PlayerSpells) -> void:
	var loadout: Array[StringName] = []
	if spells != null:
		loadout = spells.get_loadout()
	var second := PlayerSpells.has_second_button()
	for slot in SPELL_ACTIONS.size():
		var shown := slot < loadout.size() and (slot == 0 or second)
		_spells[slot] = loadout[slot] if shown else &""
		var share := spells.get_cooldown_share(slot) if shown else 0.0
		if slot == 0 and not second and spells != null:
			# One button for both slots: it waits only while every spell waits.
			for other in loadout.size():
				share = minf(share, spells.get_cooldown_share(other))
		state.cooldowns[SPELL_ACTIONS[slot]] = share


## Shows or hides the return stone button (tests call it with a player).
func set_return_stone_ready(ready: bool) -> void:
	_stone_ready = ready


func _read_return_stone() -> void:
	var player := Hud.local_player(get_tree()) if is_inside_tree() else null
	set_return_stone_ready(player != null and GameManager.get_phase() == GameManager.Phase.DUNGEON \
			and MetaProgression.can_use_return_stone(player))


func _read_spells() -> void:
	var player := Hud.local_player(get_tree()) if is_inside_tree() else null
	set_spells(PlayerSpells.of(player) if player != null else null)


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


## A modal is open (pause menu, shop, upgrade choice; in a group game too, where nothing pauses).
func _menu_open() -> bool:
	return get_tree().paused or GameManager.is_game_paused() or _guide_running()


## WK8: a running "Flint erklärt" tour holds the controls like a menu (a plain hint does not lock
## the player, so the controls stay).
func _guide_running() -> bool:
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_local:
			var guide := FlintGuide.of(player)
			if guide != null and guide.is_running() and player.is_input_locked():
				return true
	return false


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
		if is_button_active(button):
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
	var spell_slot := SPELL_ACTIONS.find(action)
	if spell_slot >= 0:
		# The cast button shows the spell it casts (SpellArt symbol).
		icon = SpellArt.icon(_spells[spell_slot])
	elif action == PlayerInput.USE_RETURN_STONE and ResourceLoader.exists(RETURN_STONE_ICON_PATH):
		icon = load(RETURN_STONE_ICON_PATH) as Texture2D
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
