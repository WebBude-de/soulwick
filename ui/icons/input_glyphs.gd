class_name InputGlyphs
extends RefCounted
## Shared input symbols of the UI (playtest note #12, 15.10.2026; briefing SPRITES_V10 §2): mouse
## buttons, wheel, space, shift, tab, enter, backspace, Esc, arrows, gamepad buttons, touch buttons
## and gestures as small pixel-art pictures instead of words like "Rechtsklick". Letters, digits and
## words without a picture (Q, E, Strg …) stay key names that KeyCap draws on a key cap. The symbol
## comes from the current binding (InputMap), so a later rebinding shows the right picture; the
## input actions themselves are never changed here. While a gamepad is the device in use
## (InputDevice, P0-2) actions and key names show the gamepad's buttons instead (first_event,
## pad_id_for_name, glyph_for_action, aim_id); rebuild on InputDevice.shared().changed.
##
## Art: res://art/ui/input/input_<id>.png replaces the drawn placeholder of the same id
## (SPRITES_V10 §2a/§2b); input_key_cap.png is the 9-slice background of text caps (KeyCap).
## Placeholders are drawn in code at 1 art pixel per texel; callers upscale them with nearest
## filtering (KeyCap, GlyphText).
##
## Key cap proportions (art pixels, shared with KeyCap's text caps): CAP_HEIGHT rows = 1 rim row,
## FACE_ROWS face rows, BOTTOM_ROWS rim rows for the key's front edge; 1 rim column on each side.

const ART_DIR := "res://art/ui/input/"
const ART_PREFIX := "input_"
## 9-slice background of text caps (SPRITES_V10 §2b) and its margins (left, top, right, bottom).
const KEY_CAP_ID: StringName = &"key_cap"
const KEY_CAP_MARGINS := Vector4i(2, 1, 2, 2)

const CAP_HEIGHT := 10
const FACE_ROWS := 7
const BOTTOM_ROWS := 2
## Free face pixels left and right of a symbol or a key name.
const CAP_PADDING := 2

# --- Glyph ids ---
const MOUSE_LEFT: StringName = &"mouse_left"
const MOUSE_RIGHT: StringName = &"mouse_right"
const MOUSE_MIDDLE: StringName = &"mouse_middle"
const MOUSE_WHEEL: StringName = &"mouse_wheel"
## The mouse itself (aiming, AIM has no action).
const MOUSE: StringName = &"mouse"
const SPACE: StringName = &"space"
const SHIFT: StringName = &"shift"
const TAB: StringName = &"tab"
const ENTER: StringName = &"enter"
const BACKSPACE: StringName = &"backspace"
const ESCAPE: StringName = &"escape"
const ARROW_UP: StringName = &"arrow_up"
const ARROW_DOWN: StringName = &"arrow_down"
const ARROW_LEFT: StringName = &"arrow_left"
const ARROW_RIGHT: StringName = &"arrow_right"
## Small touch buttons (same motifs as the TouchOverlay), shown instead of keys while touch is in use.
const TOUCH_SPECIAL: StringName = &"touch_special"
const TOUCH_DASH: StringName = &"touch_dash"
const TOUCH_SWITCH: StringName = &"touch_switch"
const TOUCH_ATTACK: StringName = &"touch_attack"
const TOUCH_INTERACT: StringName = &"touch_interact"
const TOUCH_JUMP: StringName = &"touch_jump"
const TOUCH_SIDE_DASH: StringName = &"touch_side_dash"
const TOUCH_PAUSE: StringName = &"touch_pause"
const TOUCH_MENU: StringName = &"touch_menu"
const TOUCH_STICK: StringName = &"touch_stick"
const GESTURE_TAP: StringName = &"gesture_tap"
const GESTURE_HOLD: StringName = &"gesture_hold"
const GESTURE_SWIPE: StringName = &"gesture_swipe"
const PAD_SOUTH: StringName = &"pad_south"
const PAD_EAST: StringName = &"pad_east"
const PAD_WEST: StringName = &"pad_west"
const PAD_NORTH: StringName = &"pad_north"
const PAD_A: StringName = &"pad_a"
const PAD_B: StringName = &"pad_b"
const PAD_X: StringName = &"pad_x"
const PAD_Y: StringName = &"pad_y"
const PAD_LB: StringName = &"pad_lb"
const PAD_RB: StringName = &"pad_rb"
const PAD_LT: StringName = &"pad_lt"
const PAD_RT: StringName = &"pad_rt"
const PAD_STICK_LEFT: StringName = &"pad_stick_left"
const PAD_STICK_RIGHT: StringName = &"pad_stick_right"
const PAD_DPAD: StringName = &"pad_dpad"
const PAD_START: StringName = &"pad_start"
const PAD_SELECT: StringName = &"pad_select"

## Every glyph with a picture, in briefing order (SPRITES_V10 §2a, §2b).
const IDS: Array[StringName] = [
	MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE, MOUSE_WHEEL, MOUSE,
	SPACE, SHIFT, TAB, ENTER, BACKSPACE, ESCAPE, ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT,
	TOUCH_SPECIAL, TOUCH_DASH, TOUCH_SWITCH, TOUCH_ATTACK, TOUCH_INTERACT, TOUCH_JUMP, TOUCH_SIDE_DASH,
	TOUCH_PAUSE, TOUCH_MENU, TOUCH_STICK,
	GESTURE_TAP, GESTURE_HOLD, GESTURE_SWIPE,
	PAD_SOUTH, PAD_EAST, PAD_WEST, PAD_NORTH, PAD_A, PAD_B, PAD_X, PAD_Y, PAD_LB, PAD_RB, PAD_LT, PAD_RT,
	PAD_STICK_LEFT, PAD_STICK_RIGHT, PAD_DPAD, PAD_START, PAD_SELECT,
]
const MOUSE_IDS: Array[StringName] = [MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE, MOUSE_WHEEL, MOUSE]
const TOUCH_IDS: Array[StringName] = [
	TOUCH_SPECIAL, TOUCH_DASH, TOUCH_SWITCH, TOUCH_ATTACK, TOUCH_INTERACT, TOUCH_JUMP, TOUCH_SIDE_DASH,
	TOUCH_PAUSE, TOUCH_MENU, TOUCH_STICK,
]
## ControlsInfo id -> touch button glyph (controls without a touch button, e.g. aiming, have none).
const TOUCH_GLYPHS := {
	ControlsInfo.MOVE: TOUCH_STICK, ControlsInfo.ATTACK: TOUCH_ATTACK, ControlsInfo.DASH: TOUCH_DASH,
	ControlsInfo.SPECIAL: TOUCH_SPECIAL, ControlsInfo.SWITCH: TOUCH_SWITCH, ControlsInfo.INTERACT: TOUCH_INTERACT,
	ControlsInfo.OVERVIEW: TOUCH_MENU, ControlsInfo.PAUSE: TOUCH_PAUSE,
}
## Input action -> touch button glyph; in a side-view segment dash is the jump (PlayerSideMotion).
const TOUCH_ACTION_GLYPHS := {
	&"attack": TOUCH_ATTACK, &"special_attack": TOUCH_SPECIAL, &"dash": TOUCH_DASH, &"switch_weapon": TOUCH_SWITCH,
	&"interact": TOUCH_INTERACT, &"side_dash": TOUCH_SIDE_DASH, &"pause_menu": TOUCH_PAUSE,
	&"upgrade_overview": TOUCH_MENU, &"move_up": TOUCH_STICK, &"move_down": TOUCH_STICK,
	&"move_left": TOUCH_STICK, &"move_right": TOUCH_STICK,
}
const TOUCH_SIDE_VIEW_GLYPHS := {&"dash": TOUCH_JUMP}

## Actions whose key names pad_id_for_name maps to gamepad glyphs, in priority order: the menu keys
## first (a menu's "Esc" means back, not pause), then the game actions like GlyphText.ACTIONS.
const NAME_ACTIONS: Array[StringName] = [
	&"ui_accept", &"ui_cancel", &"dash", &"attack", &"special_attack", &"switch_weapon", &"interact",
	&"upgrade_overview", &"pause_menu", &"side_dash", &"move_up", &"move_left", &"move_down", &"move_right",
]

## Engine key names (OS.get_keycode_string) with a picture.
const KEY_GLYPHS := {
	"Space": SPACE, "Shift": SHIFT, "Tab": TAB, "Enter": ENTER, "Kp Enter": ENTER, "Escape": ESCAPE,
	"Backspace": BACKSPACE, "Up": ARROW_UP, "Down": ARROW_DOWN, "Left": ARROW_LEFT, "Right": ARROW_RIGHT,
}
const MOUSE_GLYPHS := {
	MOUSE_BUTTON_LEFT: MOUSE_LEFT,
	MOUSE_BUTTON_RIGHT: MOUSE_RIGHT,
	MOUSE_BUTTON_MIDDLE: MOUSE_MIDDLE,
	MOUSE_BUTTON_WHEEL_UP: MOUSE_WHEEL,
	MOUSE_BUTTON_WHEEL_DOWN: MOUSE_WHEEL,
}
## Gamepad buttons: neutral positions (fits Xbox, PlayStation and Switch).
const PAD_BUTTON_GLYPHS := {
	JOY_BUTTON_A: PAD_SOUTH, JOY_BUTTON_B: PAD_EAST, JOY_BUTTON_X: PAD_WEST, JOY_BUTTON_Y: PAD_NORTH,
	JOY_BUTTON_LEFT_SHOULDER: PAD_LB, JOY_BUTTON_RIGHT_SHOULDER: PAD_RB,
	JOY_BUTTON_LEFT_STICK: PAD_STICK_LEFT, JOY_BUTTON_RIGHT_STICK: PAD_STICK_RIGHT,
	JOY_BUTTON_DPAD_UP: PAD_DPAD, JOY_BUTTON_DPAD_DOWN: PAD_DPAD, JOY_BUTTON_DPAD_LEFT: PAD_DPAD,
	JOY_BUTTON_DPAD_RIGHT: PAD_DPAD, JOY_BUTTON_START: PAD_START, JOY_BUTTON_BACK: PAD_SELECT,
}
const PAD_AXIS_GLYPHS := {
	JOY_AXIS_LEFT_X: PAD_STICK_LEFT, JOY_AXIS_LEFT_Y: PAD_STICK_LEFT,
	JOY_AXIS_RIGHT_X: PAD_STICK_RIGHT, JOY_AXIS_RIGHT_Y: PAD_STICK_RIGHT,
	JOY_AXIS_TRIGGER_LEFT: PAD_LT, JOY_AXIS_TRIGGER_RIGHT: PAD_RT,
}
## Translation keys of key names (ControlsInfo) -> glyph, so a shown name maps back to its picture.
const NAME_KEYS := {
	&"KEY_MOUSE_LEFT": MOUSE_LEFT, &"KEY_MOUSE_RIGHT": MOUSE_RIGHT, &"KEY_MOUSE_MIDDLE": MOUSE_MIDDLE,
	&"KEY_MOUSE": MOUSE, &"KEY_SPACE": SPACE, &"KEY_SHIFT": SHIFT, &"KEY_BACKSPACE": BACKSPACE,
}
## Short names on text caps (engine name -> translation key or plain text), like ControlsInfo.
const CAP_NAMES := {
	"Escape": "Esc", "Ctrl": &"KEY_CTRL", "Delete": &"KEY_DELETE", "Kp Enter": "Enter",
}

# Placeholder colours (UiKit palette).
const COLOR_RIM := UiKit.COLOR_EMPTY_SLOT
const COLOR_FACE := UiKit.COLOR_BG
const COLOR_SYMBOL := UiKit.COLOR_TEXT
const COLOR_MOUSE := UiKit.COLOR_TEXT_SOFT
const COLOR_MOUSE_BODY := UiKit.COLOR_BG
const COLOR_PRESSED := UiKit.COLOR_GOLD
## Ring of a touch button (the overlay's warm ring colour, opaque).
const COLOR_TOUCH_RING := Color("#d9b77e")
## Pixel grids: "#" light line, "o" gold, "+" rim, "f" face, "." transparent.
const GRID_COLORS := {"#": COLOR_MOUSE, "o": COLOR_PRESSED, "+": COLOR_RIM, "f": COLOR_FACE}

## Symbols on key caps, 5 rows each ("#" = symbol pixel).
const SYMBOLS := {
	SPACE: ["", "", "#.........#", "#.........#", "###########"],
	SHIFT: ["..#..", ".#.#.", "##.##", ".#.#.", ".###."],
	TAB: ["....#.#", ".....##", "#######", ".....##", "....#.#"],
	ENTER: ["....#", "....#", ".#..#", "#####", ".#..."],
	BACKSPACE: ["..#....", ".#.....", "#######", ".#.....", "..#...."],
	ESCAPE: ["###....", "##.....", "#.#.###", "...#..#", "...####"],
	ARROW_UP: ["..#..", ".###.", "#.#.#", "..#..", "..#.."],
	ARROW_DOWN: ["..#..", "..#..", "#.#.#", ".###.", "..#.."],
	ARROW_LEFT: ["..#..", ".#...", "#####", ".#...", "..#.."],
	ARROW_RIGHT: ["..#..", "...#.", "#####", "...#.", "..#.."],
	PAD_LB: ["#..##.", "#..#.#", "#..##.", "#..#.#", "##.##."],
	PAD_RB: ["##.##.", "#.##.#", "##.##.", "#.##.#", "#.###."],
	PAD_LT: ["#..###", "#...#.", "#...#.", "#...#.", "##..#."],
	PAD_RT: ["##.###", "#.#.#.", "##..#.", "#.#.#.", "#.#.#."],
}
## Symbols inside a round button, 5 × 5 (touch buttons, gamepad letters and menu buttons).
const ROUND_SYMBOLS := {
	TOUCH_SPECIAL: ["..#..", "#####", ".###.", ".#.#.", "#...#"],
	# Dash: arrow to the right with motion streaks behind it (no ">>", SPRITES_V10).
	TOUCH_DASH: ["..#..", "#..#.", ".####", "#..#.", "..#.."],
	TOUCH_SWITCH: ["...#.", "#####", ".....", "#####", ".#..."],
	TOUCH_ATTACK: ["....#", "...#.", "#.#..", ".#...", "#.#.."],
	TOUCH_INTERACT: ["#.#.#", "#.#.#", "#####", "#####", ".###."],
	TOUCH_JUMP: ["..#..", ".###.", "..#..", ".....", "#####"],
	TOUCH_SIDE_DASH: ["#..#.", ".####", "#..#.", ".....", "#####"],
	TOUCH_PAUSE: [".#.#.", ".#.#.", ".#.#.", ".#.#.", ".#.#."],
	TOUCH_MENU: ["##.##", "#.#.#", "##.##", "#.#.#", "##.##"],
	TOUCH_STICK: [".###.", "#...#", "#.#.#", "#...#", ".###."],
	PAD_A: [".#.", "#.#", "###", "#.#", "#.#"],
	PAD_B: ["##.", "#.#", "##.", "#.#", "##."],
	PAD_X: ["#.#", "#.#", ".#.", "#.#", "#.#"],
	PAD_Y: ["#.#", "#.#", ".#.", ".#.", ".#."],
	PAD_START: ["#####", ".....", "#####", ".....", "#####"],
	PAD_SELECT: ["###..", "#.###", "###.#", "..#.#", "..###"],
}
## Ring colour of the round gamepad letters (A green, B red, X blue, Y gold).
const PAD_LETTER_COLORS := {
	PAD_A: UiKit.COLOR_SUCCESS, PAD_B: UiKit.COLOR_DANGER, PAD_X: UiKit.COLOR_SHIELD, PAD_Y: UiKit.COLOR_GOLD,
}
## Round button, 9 × 10: "#" ring, "f" face, "+" shadow under it (like a key's front edge).
const ROUND_SHAPE: Array[String] = [
	"..#####..",
	".#fffff#.",
	"#fffffff#",
	"#fffffff#",
	"#fffffff#",
	"#fffffff#",
	"#fffffff#",
	".#fffff#.",
	"..#####..",
	"..+++++..",
]
## Mouse, 9 × 10: "#" outline, "." body, "L"/"R" left/right button, "W" wheel.
const MOUSE_SHAPE: Array[String] = [
	".#######.",
	"#LLL#RRR#",
	"#LLLWRRR#",
	"#LLLWRRR#",
	"#########",
	"#.......#",
	"#.......#",
	"#.......#",
	".#.....#.",
	"..#####..",
]
## Full 10 × 10 grids (GRID_COLORS).
const GRIDS := {
	GESTURE_TAP: [
		"..ooo.....", ".o...o....", ".o.#.o....", "..o#o.....", "...#......",
		"...#.#.#..", "...######.", "..#######.", "..#######.", "...#####..",
	],
	GESTURE_HOLD: [
		".ooooo....", "oo...oo...", "o..#..o...", "oo.#.oo...", ".oo#oo....",
		"...#.#.#..", "...######.", "..#######.", "..#######.", "...#####..",
	],
	GESTURE_SWIPE: [
		"..........", "...#...o..", "o..#...oo.", "...#.ooooo", "o..#...oo.",
		"...#.#.o..", "...######.", "..#######.", "..#######.", "...#####..",
	],
	PAD_STICK_LEFT: [
		"..####....", ".#ffff#...", "#ff##ff#..", "#f####f#..", "#f####f#..",
		"#ff##ff#..", ".#ffff#...", "..####....", "..........", "o.........",
	],
	PAD_STICK_RIGHT: [
		"..####....", ".#ffff#...", "#ff##ff#..", "#f####f#..", "#f####f#..",
		"#ff##ff#..", ".#ffff#...", "..####....", "..........", ".......o..",
	],
	PAD_DPAD: [
		"...###....", "...#f#....", "...#f#....", "####f####.", "#fffffff#.",
		"####f####.", "...#f#....", "...#f#....", "...###....", "..........",
	],
}
## Gamepad face buttons: diamond of four 3 × 3 dots; the meant one is gold.
const PAD_DOTS := {PAD_NORTH: Vector2i(3, 0), PAD_WEST: Vector2i(0, 3), PAD_EAST: Vector2i(6, 3), PAD_SOUTH: Vector2i(3, 6)}

static var _textures: Dictionary = {}
static var _key_cap_styles: Dictionary = {}


# --- Ids ---

## Glyph id of an input event ("" = no picture, the key shows its name).
static func id_for_event(event: InputEvent) -> StringName:
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return MOUSE_GLYPHS.get(mouse.button_index, &"")
	var pad := event as InputEventJoypadButton
	if pad != null:
		return PAD_BUTTON_GLYPHS.get(pad.button_index, &"")
	var axis := event as InputEventJoypadMotion
	if axis != null:
		return PAD_AXIS_GLYPHS.get(axis.axis, &"")
	var key := event as InputEventKey
	if key == null:
		return &""
	return KEY_GLYPHS.get(engine_key_name(key), &"")


## Glyph id of the first bound event of an action ("" = none or no picture).
static func id_for_action(action: StringName) -> StringName:
	var event := first_event(action)
	return id_for_event(event) if event != null else &""


## Glyph id of a key name as ControlsInfo shows it ("Rechtsklick", "Right click", "Space", "Tab");
## while the gamepad is in use the gamepad button of the action behind the name (pad_id_for_name).
static func id_for_name(key_name: String) -> StringName:
	var text := key_name.strip_edges()
	if text.is_empty():
		return &""
	var pad := pad_id_for_name(text)
	if pad != &"":
		return pad
	if KEY_GLYPHS.has(text):
		return KEY_GLYPHS[text]
	if text == "Esc":
		return ESCAPE
	for key: StringName in NAME_KEYS:
		if text == Loc.t(key):
			return NAME_KEYS[key]
	return &""


## First bound event of an action for the device in use (null when unbound): keyboard and mouse
## first, a gamepad binding only when there is nothing else; while the gamepad is in use
## (is_gamepad, P0-2) the other way round.
static func first_event(action: StringName, pad_first := is_gamepad()) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var pad: InputEvent = null
	var desk: InputEvent = null
	for event in InputMap.action_get_events(action):
		if desk == null and (event is InputEventMouseButton or event is InputEventKey):
			desk = event
		if pad == null and is_pad_event(event):
			pad = event
	if pad_first:
		return pad if pad != null else desk
	return desk if desk != null else pad


static func is_pad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## Glyph of the first gamepad binding of an action ("" = none).
static func pad_id_for_action(action: StringName) -> StringName:
	if not InputMap.has_action(action):
		return &""
	for event in InputMap.action_get_events(action):
		if is_pad_event(event):
			return id_for_event(event)
	return &""


## Glyph of an action for the device in use: the touch button, the gamepad button or the bound key
## or mouse button ("" = a key without a picture, e.g. Q). side_view: dash is the jump there.
## Hook for GlyphText.name_glyphs and other hint builders (P0-2).
static func glyph_for_action(action: StringName, side_view := false) -> StringName:
	if is_touch():
		return touch_id_for_action(action, side_view)
	if is_gamepad():
		return pad_id_for_action(action)
	var event := first_event(action, false)
	return id_for_event(event) if event != null else &""


## Glyph of aiming (ControlsInfo.AIM has no action): the right stick on a gamepad, else the mouse.
static func aim_id() -> StringName:
	return PAD_STICK_RIGHT if is_gamepad() else MOUSE


## Engine name of a key ("Q", "Space", "Escape"); physical bindings show the letter of the
## player's keyboard layout like ControlsInfo.event_text.
static func engine_key_name(key: InputEventKey) -> String:
	var code := key.keycode
	if code == KEY_NONE and key.physical_keycode != KEY_NONE:
		code = key.physical_keycode
		if DisplayServer.get_name() not in ["headless", "Web"]:
			var local := DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			if local != KEY_NONE:
				code = local
	return OS.get_keycode_string(code)


## Short name on a text cap ("Q", "Esc", "Strg"), in the current language.
static func cap_text(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var name := engine_key_name(key)
		var value: Variant = CAP_NAMES.get(name, name)
		return Loc.t(value) if value is StringName else String(value)
	return ControlsInfo.event_text(event) if event != null else ""


static func is_mouse(glyph_id: StringName) -> bool:
	return MOUSE_IDS.has(glyph_id)


## Touch button glyph of a control ("" = it has no touch button, e.g. aiming).
static func touch_id(control_id: StringName) -> StringName:
	return TOUCH_GLYPHS.get(control_id, &"")


## Touch button glyph of an input action; side_view: dash is the jump there.
static func touch_id_for_action(action: StringName, side_view := false) -> StringName:
	if side_view and TOUCH_SIDE_VIEW_GLYPHS.has(action):
		return TOUCH_SIDE_VIEW_GLYPHS[action]
	return TOUCH_ACTION_GLYPHS.get(action, &"")


## Touch controls in use on this device (TouchState, read only).
static func is_touch() -> bool:
	return TouchState.shared().is_active()


## Gamepad in use on this machine (InputDevice, read only); the touch controls win.
static func is_gamepad() -> bool:
	return InputDevice.is_gamepad() and not is_touch()


## While the gamepad is in use: the gamepad glyph of the action a shown key name belongs to
## ("Enter" -> A, "Esc" -> B, "Leertaste" -> A), searched in NAME_ACTIONS order; "" otherwise.
static func pad_id_for_name(key_name: String) -> StringName:
	if not is_gamepad():
		return &""
	for action in NAME_ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if not (event is InputEventKey or event is InputEventMouseButton):
				continue
			var names := [ControlsInfo.event_text(event)]
			if event is InputEventKey:
				names.append(engine_key_name(event))
			if names.has(key_name):
				var pad := pad_id_for_action(action)
				if pad != &"":
					return pad
	return &""


# --- Textures ---

## Picture of a glyph at 1 texel per art pixel: art/ui/input/input_<id>.png if it exists, else the
## drawn placeholder. null for unknown ids.
static func texture(glyph_id: StringName) -> Texture2D:
	if glyph_id == &"" or not IDS.has(glyph_id):
		return null
	if _textures.has(glyph_id):
		return _textures[glyph_id]
	var result := _art(glyph_id)
	if result == null:
		result = ImageTexture.create_from_image(placeholder_image(glyph_id))
	_textures[glyph_id] = result
	return result


static func art_path(glyph_id: StringName) -> String:
	return ART_DIR + ART_PREFIX + String(glyph_id) + ".png"


## 9-slice background for text caps at pixel screen pixels per art pixel, or null while
## art/ui/input/input_key_cap.png is missing (KeyCap then draws its rectangles).
static func key_cap_style(pixel: int) -> StyleBoxTexture:
	if _key_cap_styles.has(pixel):
		return _key_cap_styles[pixel]
	var art := _art(KEY_CAP_ID)
	var style: StyleBoxTexture = null
	if art != null:
		style = StyleBoxTexture.new()
		style.texture = UiKit.upscale(art, pixel)
		style.texture_margin_left = KEY_CAP_MARGINS.x * pixel
		style.texture_margin_top = KEY_CAP_MARGINS.y * pixel
		style.texture_margin_right = KEY_CAP_MARGINS.z * pixel
		style.texture_margin_bottom = KEY_CAP_MARGINS.w * pixel
	_key_cap_styles[pixel] = style
	return style


static func _art(glyph_id: StringName) -> Texture2D:
	var path := art_path(glyph_id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Drawn placeholder; every one is CAP_HEIGHT rows high.
static func placeholder_image(glyph_id: StringName) -> Image:
	if is_mouse(glyph_id):
		return _mouse_image(glyph_id)
	if ROUND_SYMBOLS.has(glyph_id):
		return _round_image(glyph_id)
	if GRIDS.has(glyph_id):
		return grid_image(GRIDS[glyph_id])
	if PAD_DOTS.has(glyph_id):
		return _pad_face_image(glyph_id)
	var rows: Array = SYMBOLS.get(glyph_id, [])
	var symbol_width := 0
	for row: String in rows:
		symbol_width = maxi(symbol_width, row.length())
	var image := cap_image(symbol_width + CAP_PADDING * 2 + 2)
	# Symbol rows sit on face rows 2..6 (one free face row above and below).
	_stamp(image, rows, Vector2i(1 + CAP_PADDING, 2), COLOR_SYMBOL)
	return image


## Empty key cap of the given width in art pixels (rim, face, thicker front edge).
static func cap_image(width: int) -> Image:
	var image := Image.create(width, CAP_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(COLOR_RIM)
	image.fill_rect(Rect2i(1, 1, width - 2, FACE_ROWS), COLOR_FACE)
	# Rounded look: the four corner pixels stay transparent.
	for corner in [Vector2i(0, 0), Vector2i(width - 1, 0), Vector2i(0, CAP_HEIGHT - 1), Vector2i(width - 1, CAP_HEIGHT - 1)]:
		image.set_pixelv(corner, Color(0, 0, 0, 0))
	return image


## Image of a pixel grid (GRID_COLORS; unknown characters stay transparent).
static func grid_image(rows: Array, colors: Dictionary = GRID_COLORS) -> Image:
	var width := 0
	for row: String in rows:
		width = maxi(width, row.length())
	var image := Image.create(width, rows.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if colors.has(row[x]):
				image.set_pixel(x, y, colors[row[x]])
	return image


static func _stamp(image: Image, rows: Array, offset: Vector2i, color: Color) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				image.set_pixel(offset.x + x, offset.y + y, color)


static func _round_image(glyph_id: StringName) -> Image:
	var ring: Color = PAD_LETTER_COLORS.get(glyph_id, COLOR_TOUCH_RING if TOUCH_IDS.has(glyph_id) else COLOR_MOUSE)
	var image := grid_image(ROUND_SHAPE, {"#": ring, "f": COLOR_FACE, "+": COLOR_RIM})
	var rows: Array = ROUND_SYMBOLS[glyph_id]
	var width := (rows[0] as String).length()
	# 5-wide symbols fill face columns 2..6, 3-wide letters sit in the middle.
	_stamp(image, rows, Vector2i(2 + (5 - width) / 2, 2), COLOR_SYMBOL)
	return image


static func _pad_face_image(glyph_id: StringName) -> Image:
	var image := Image.create(9, CAP_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for dot: StringName in PAD_DOTS:
		var origin: Vector2i = PAD_DOTS[dot]
		image.fill_rect(Rect2i(origin, Vector2i(3, 3)), COLOR_MOUSE)
		image.set_pixelv(origin + Vector2i.ONE, COLOR_PRESSED if dot == glyph_id else COLOR_FACE)
		if dot == glyph_id:
			image.fill_rect(Rect2i(origin, Vector2i(3, 3)), COLOR_PRESSED)
	return image


static func _mouse_image(glyph_id: StringName) -> Image:
	var height := MOUSE_SHAPE.size()
	var width := MOUSE_SHAPE[0].length()
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var pressed: String = {MOUSE_LEFT: "L", MOUSE_RIGHT: "R", MOUSE_MIDDLE: "W", MOUSE_WHEEL: "W"}.get(glyph_id, "")
	for y in height:
		var row := MOUSE_SHAPE[y]
		var first := row.find("#")
		var last := row.rfind("#")
		for x in width:
			var cell := row[x]
			if cell != "#" and (x < first or x > last):
				continue
			var color := COLOR_MOUSE_BODY
			match cell:
				"#":
					color = COLOR_MOUSE
				"L", "R":
					color = COLOR_PRESSED if cell == pressed else COLOR_MOUSE_BODY
				"W":
					# The wheel is a light stripe on the divider; gold when it is the key.
					color = COLOR_PRESSED if cell == pressed else COLOR_MOUSE
			image.set_pixel(x, y, color)
	if glyph_id == MOUSE_WHEEL:
		image.set_pixel(4, 1, COLOR_PRESSED)
	return image
