extends RefCounted
## Portrait mode ("Hochkant", Projektmitglied 17.10.2026: "oben zocken und unten wie ein Gamepad.
## Voll retro."): a phone held upright shows the game as a screen at the top over the full width and
## a handheld controller field below it (PortraitPad). Switches by itself when the window turns
## (PortraitMode), landscape stays exactly as before, the desktop never uses it.
##
## How the screen is cut out: the root window's visible rect IS the game screen. In portrait the root
## uses content scale aspect "ignore" with content_scale_size = VIEW_WIDTH × screen height, and its
## global canvas transform undoes the vertical stretch and moves the screen below the notch. So every
## camera (top-down rig, side view), every full-rect overlay (darkness, post-process, HUD, banners,
## dialogs) and every input event (Viewport.get_final_transform) works on the screen rect as on a
## landscape screen; the controller field lies below the visible rect in the same view coordinates
## and is drawn by a canvas layer above everything (the world drawn behind it is covered).
## Shaders that mix UV and SCREEN_UV assume the screen fills the window (see the report of D-180).
##
## Pure geometry and the shared state; no nodes. Preload (no class_name, D-044 style helpers):
## const PortraitLayout := preload("res://ui/touch/portrait_layout.gd")

## Width of the game screen in view pixels: every layout of the game (1280×720 mockups) keeps its
## width, so menus and the HUD lay out as in landscape.
const VIEW_WIDTH := 1280
## Share of the window height the game screen gets (TESTWERT; Game Boy: screen in the upper half).
const SCREEN_SHARE := 0.45
## Screen height in view pixels: at least 16:9, at most square (TESTWERT).
const MIN_SCREEN_HEIGHT := 720
const MAX_SCREEN_HEIGHT := 1280
## Camera zoom factor in portrait: the screen is about half as wide as in landscape, the world is
## drawn this much larger (TESTWERT; 1.0 would show the landscape width at half the size).
const WORLD_ZOOM := 1.25
## Zoom of the HUD (and other overlays that ask for it) in portrait (TESTWERT).
const UI_ZOOM := 1.5
## Command line (desktop tests): "-- portrait=1" forces the handheld check on, "portrait=0" off.
const FORCE_ARG := "portrait="

## Tests: 1/0 replace is_handheld() (-1 = by the device).
static var handheld_override := -1
## The frame applied right now (PortraitMode), null in landscape.
static var _frame: Frame = null


## Where everything sits in portrait, for one window size (window pixels unless named view).
class Frame:
	extends RefCounted
	## Window size in window (device) pixels.
	var window := Vector2.ZERO
	## Window pixels per view pixel (uniform).
	var scale := 1.0
	## Window pixels above the screen (notch, status bar) and kept free at the bottom (gesture bar).
	var top := 0.0
	var bottom := 0.0
	## Game screen in view pixels (the root's content_scale_size).
	var screen_size := Vector2i(VIEW_WIDTH, MIN_SCREEN_HEIGHT)

	## The game screen in view coordinates (= the root's visible rect).
	func screen_rect() -> Rect2:
		return Rect2(Vector2.ZERO, Vector2(screen_size))

	## Window y where the screen ends and the controller field starts.
	func pad_top() -> float:
		return top + float(screen_size.y) * scale

	## Window y where the controls end (above the gesture bar).
	func pad_bottom() -> float:
		return window.y - bottom

	## The controller field below the screen to the window's bottom edge, in view coordinates.
	func field_rect() -> Rect2:
		var start := float(screen_size.y)
		return Rect2(Vector2(0.0, start), Vector2(float(VIEW_WIDTH), (window.y - top) / scale - start))

	## Window pixel -> view coordinates (what input events and canvas layers use).
	func to_view(point: Vector2) -> Vector2:
		return Vector2(point.x, point.y - top) / scale

	## View coordinates -> window pixel.
	func to_window(point: Vector2) -> Vector2:
		return Vector2(point.x * scale, point.y * scale + top)

	## Root global canvas transform that turns the "ignore" stretch (VIEW_WIDTH × screen height onto
	## the whole window) into a uniform scale with the screen at the top below the notch.
	func global_transform() -> Transform2D:
		var stretch_y := window.y / float(screen_size.y)
		return Transform2D(Vector2(1.0, 0.0), Vector2(0.0, scale / stretch_y), Vector2(0.0, top / stretch_y))


## A phone or tablet build (Android/iOS app, browser on a phone or touch tablet) or forced for tests
## ("-- portrait=1", "-- mobile_ui=1", "-- touch=1"). Native desktops never turn portrait.
static func is_handheld() -> bool:
	if handheld_override >= 0:
		return handheld_override == 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(FORCE_ARG):
			return arg.trim_prefix(FORCE_ARG) == "1"
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if OS.has_feature("web") and DisplayServer.is_touchscreen_available():
		return true
	return OS.get_cmdline_user_args().has("mobile_ui=1") or TouchState.is_forced_by_command_line()


## The window is held upright.
static func is_upright(window: Vector2) -> bool:
	return window.x > 0.0 and window.y > window.x


## Frame for a window size and safe-area insets (window pixels: left, top, right, bottom).
static func compute(window: Vector2, insets := Vector4.ZERO) -> Frame:
	var frame := Frame.new()
	frame.window = window
	frame.scale = window.x / float(VIEW_WIDTH)
	frame.top = maxf(0.0, roundf(insets.y))
	frame.bottom = maxf(0.0, roundf(insets.w))
	var room := maxf(1.0, window.y - frame.top - frame.bottom)
	var height := floorf(room * SCREEN_SHARE / frame.scale)
	frame.screen_size = Vector2i(VIEW_WIDTH, int(clampf(height, MIN_SCREEN_HEIGHT, MAX_SCREEN_HEIGHT)))
	return frame


# --- Shared state (set by PortraitMode) ---

## Portrait mode is on right now.
static func is_active() -> bool:
	return _frame != null


## The applied frame (null in landscape).
static func get_frame() -> Frame:
	return _frame


## PortraitMode (and tests) switch the state; null = landscape.
static func set_frame(frame: Frame) -> void:
	_frame = frame


## Camera zoom factor: WORLD_ZOOM in portrait, 1 otherwise.
static func world_zoom() -> float:
	return WORLD_ZOOM if is_active() else 1.0


## Zoom of overlays that opt in (HUD): UI_ZOOM in portrait, 1 otherwise.
static func ui_zoom() -> float:
	return UI_ZOOM if is_active() else 1.0
