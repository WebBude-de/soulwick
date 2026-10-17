extends RefCounted
## Phones and touch screens in menus and dialogs (Projektmitglied 17.10.2026, web app on a phone: "no
## X in the pause menu, the menu could be much bigger on the small screen"). One place decides:
## - is_touch_screen(): the device has a touch screen (phone, tablet, touch laptop, or forced). Dialogs
##   that close with Esc/B get a tappable X there, menu buttons a minimum height of MIN_TOUCH_DP.
## - hides_key_hints(): keyboard hints ("Esc zurück", key caps) mean nothing right now (touch in use,
##   or a phone without a gamepad). Key bars, key lines and key caps hide.
## - menu_zoom(viewport): how much larger menus and dialogs are drawn. The layout stays in mockup
##   pixels; the dialog stage is scaled as a whole (Control.scale, text is rasterised at the final
##   size). Rule: body text (UiKit.SIZE_BODY) should be about TARGET_BODY_DP on the physical screen;
##   the zoom is snapped so one art pixel of the panels covers a whole number of device pixels (pixel
##   art stays even), never below 1 and at most MAX_ZOOM. Without a touch screen it stays 1 (AUTO).
##   fit_zoom() lowers it per dialog until the dialog fits; what is still too tall scrolls.
## - safe_rect(viewport): the visible area minus notch, camera hole and rounded corners in viewport
##   pixels (Android/iOS: DisplayServer safe area; browser: CSS env(safe-area-inset-*)).
## Usage (no class_name, new classes are preloaded): const MobileUi := preload("res://ui/menus/mobile_ui.gd")
## Desktop testing: "-- mobile_ui=1" simulates a phone (touch screen, short side SIMULATED_SHORT_DP dp),
## "-- safe_inset=90" a notch of 90 window pixels on the left and the right.
## Portrait (phone held upright, PortraitLayout): the visible rect is the game screen at the top, already
## placed below the notch, so safe_rect() is the visible rect; dialogs stay on that screen (as wide as
## the phone, so the text gets no smaller than over the whole screen; too tall dialogs scroll).
## fit_to_safe_area(control, true) additionally zooms an overlay by PortraitLayout.ui_zoom() (HUD).

## UI size option (hook for ui/options): AUTO = by screen, NORMAL = like the PC, LARGE = a step more.
enum SizeMode { AUTO, NORMAL, LARGE }

const FORCE_ARG := "mobile_ui=1"
const SAFE_INSET_ARG := "safe_inset="
## Wanted size of body text on a touch screen in dp (Android: 14 sp is the usual body size; TESTWERT).
const TARGET_BODY_DP := 14.0
## LARGE: this much more than AUTO (TESTWERT).
const LARGE_FACTOR := 1.25
## Largest menu zoom: above it the 1280×720 layouts no longer fit a phone in landscape (TESTWERT).
const MAX_ZOOM := 2.0
## Smallest height of a tappable button in dp (Material: 48 dp, about 9 mm).
const MIN_TOUCH_DP := 48.0
## Short side of the phone simulated by FORCE_ARG in dp (Pixel 7: 412, browser with bars: ~360).
const SIMULATED_SHORT_DP := 400.0
const PortraitLayout := preload("res://ui/touch/portrait_layout.gd")
## Body text and art pixel of the menus at zoom 1 in viewport pixels (UiKit.SIZE_BODY × UiKit.UI_SCALE
## and UiKit.ART_SCALE; no UiKit reference here, UiKit preloads this file).
const BODY_PX := 7.0 * 1280.0 / 480.0
const ART_PX := 3.0
## Room between a dialog and the safe area on a touch screen, share of the shorter side (TESTWERT).
const TOUCH_MARGIN := 0.025

## The UI size option (GameOptions hook: MobileUi.size_mode = ...; dialogs opened later follow).
static var size_mode: SizeMode = SizeMode.AUTO
## Tests: > 0 replaces menu_zoom().
static var zoom_override := 0.0
## Tests: 1/0 replace is_touch_screen() / is_phone() (-1 = by the device).
static var touch_override := -1
static var phone_override := -1
## Tests: >= 0 replaces the safe area insets (window pixels left and right).
static var safe_inset_override := -1.0

static var _web_insets := Vector4.ZERO
static var _web_insets_size := Vector2i(-1, -1)


## A phone or a phone-like browser (or simulated with -- mobile_ui=1).
static func is_phone() -> bool:
	if phone_override >= 0:
		return phone_override == 1
	return is_forced() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## The device has a touch screen: dialogs get a tappable X and taller buttons.
static func is_touch_screen() -> bool:
	if touch_override >= 0:
		return touch_override == 1
	return is_phone() or TouchState.is_touch_possible()


## Key hints ("Esc zurück", key caps, "1–3 wählen") mean nothing now: a touch screen that is in use
## (last input a finger, forced touch, or a phone) and no gamepad.
static func hides_key_hints() -> bool:
	if not is_touch_screen():
		return false
	var kind := InputDevice.shared().kind
	if kind == InputDevice.Kind.GAMEPAD:
		return false
	return kind == InputDevice.Kind.TOUCH or is_phone() or TouchState.shared().forced


static func is_forced() -> bool:
	return OS.get_cmdline_user_args().has(FORCE_ARG)


# --- Size ---

## How much larger menus are drawn on this screen (1 = like the PC). See the class comment.
static func menu_zoom(viewport: Viewport) -> float:
	if zoom_override > 0.0:
		return zoom_override
	if size_mode == SizeMode.NORMAL or viewport == null:
		return 1.0
	var wanted := 1.0
	if is_touch_screen():
		var body_dp := BODY_PX * dp_per_pixel(viewport)
		if body_dp > 0.0:
			wanted = TARGET_BODY_DP / body_dp
	if size_mode == SizeMode.LARGE:
		wanted = maxf(wanted, 1.0) * LARGE_FACTOR
	return snap_zoom(clampf(wanted, 1.0, MAX_ZOOM), device_scale(viewport))


## Nearest zoom at which one art pixel (ART_PX viewport pixels) covers whole device pixels; >= 1.
static func snap_zoom(zoom: float, device_px_per_pixel: float) -> float:
	var art := ART_PX * maxf(device_px_per_pixel, 0.01)
	var steps := roundi(art * zoom)
	return maxf(1.0, steps / art)


## The largest zoom <= zoom at which content (viewport pixels at zoom 1) fits into area, snapped down
## like snap_zoom; never below 1 (then the dialog scrolls or overflows as on the PC).
static func fit_zoom(zoom: float, content: Vector2, area: Vector2, device_px_per_pixel := 1.0) -> float:
	if zoom <= 1.0 or content.x <= 0.0 or content.y <= 0.0:
		return maxf(zoom, 1.0)
	var limit := minf(area.x / content.x, area.y / content.y)
	if zoom <= limit:
		return zoom
	var art := ART_PX * maxf(device_px_per_pixel, 0.01)
	return maxf(1.0, floori(art * limit + 0.001) / art)


## Device (window) pixels per viewport pixel (canvas_items stretch with aspect "expand").
static func device_scale(viewport: Viewport) -> float:
	var window := viewport as Window
	if window == null or DisplayServer.get_name() == "headless":
		return 1.0
	var visible := viewport.get_visible_rect().size
	if visible.x <= 0.0 or visible.y <= 0.0 or window.size.x <= 0 or window.size.y <= 0:
		return 1.0
	return minf(window.size.x / visible.x, window.size.y / visible.y)


## Physical size of one viewport pixel in dp (density-independent pixels, 160 per inch).
static func dp_per_pixel(viewport: Viewport) -> float:
	return device_scale(viewport) / density()


## Device pixels per dp: Android dpi / 160, browser devicePixelRatio (1 CSS pixel = 1 dp), desktop
## dpi / 96; the simulated phone fits SIMULATED_SHORT_DP into the short side of the window.
static func density() -> float:
	if is_forced() and not OS.has_feature("mobile") and not OS.has_feature("web"):
		var window := DisplayServer.window_get_size()
		return maxf(0.01, mini(window.x, window.y) / SIMULATED_SHORT_DP)
	if OS.has_feature("web"):
		return maxf(1.0, DisplayServer.screen_get_scale())
	var dpi := DisplayServer.screen_get_dpi()
	if OS.has_feature("mobile"):
		return dpi / 160.0 if dpi > 0 else maxf(1.0, DisplayServer.screen_get_scale())
	return maxf(1.0, dpi / 96.0)


## Smallest button height in layout pixels of a dialog drawn at zoom (0 without a touch screen).
static func min_touch_height(viewport: Viewport, zoom := 1.0) -> float:
	if not is_touch_screen() or viewport == null:
		return 0.0
	var per_dp := dp_per_pixel(viewport)
	if per_dp <= 0.0:
		return 0.0
	return ceilf(MIN_TOUCH_DP / per_dp / maxf(zoom, 1.0))


## Room between dialogs and the safe area edge in viewport pixels (0 on a desktop).
static func touch_margin(viewport: Viewport) -> float:
	if not is_touch_screen() or viewport == null:
		return 0.0
	var size := viewport.get_visible_rect().size
	return roundf(minf(size.x, size.y) * TOUCH_MARGIN)


# --- Safe area ---

## Visible area of viewport without notch, camera hole and rounded corners (viewport pixels).
static func safe_rect(viewport: Viewport) -> Rect2:
	var rect := viewport.get_visible_rect() if viewport != null else Rect2(0, 0, 1280, 720)
	if PortraitLayout.is_active():
		# The screen already sits below the notch; the bottom insets lie in the controller field.
		return rect
	var insets := safe_insets()
	if insets == Vector4.ZERO or viewport == null:
		return rect
	var scale := device_scale(viewport)
	var left := insets.x / scale
	var top := insets.y / scale
	var right := insets.z / scale
	var bottom := insets.w / scale
	return Rect2(rect.position + Vector2(left, top), (rect.size - Vector2(left + right, top + bottom)).max(Vector2.ONE))


## Safe area insets in window pixels: left, top, right, bottom.
static func safe_insets() -> Vector4:
	var forced := safe_inset_override
	if forced < 0.0:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with(SAFE_INSET_ARG):
				forced = maxf(0.0, arg.trim_prefix(SAFE_INSET_ARG).to_float())
	if forced >= 0.0:
		return Vector4(forced, 0.0, forced, 0.0)
	if OS.has_feature("web"):
		return _web_safe_insets()
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if safe.size.x <= 0 or safe.size.y <= 0 or screen.x <= 0:
		return Vector4.ZERO
	return Vector4(maxi(0, safe.position.x), maxi(0, safe.position.y),
			maxi(0, screen.x - safe.end.x), maxi(0, screen.y - safe.end.y))


## Browser: CSS env(safe-area-inset-*) (the shell uses viewport-fit=cover) × devicePixelRatio, read
## once per window size (turning the phone changes the sides).
static func _web_safe_insets() -> Vector4:
	var window := DisplayServer.window_get_size()
	if window == _web_insets_size:
		return _web_insets
	_web_insets_size = window
	_web_insets = Vector4.ZERO
	if not Engine.has_singleton(&"JavaScriptBridge"):
		return _web_insets
	var code := "(function(){var d=document.createElement('div');" \
			+ "d.style.cssText='position:fixed;visibility:hidden;pointer-events:none;left:0;top:0;" \
			+ "padding-left:env(safe-area-inset-left);padding-top:env(safe-area-inset-top);" \
			+ "padding-right:env(safe-area-inset-right);padding-bottom:env(safe-area-inset-bottom)';" \
			+ "document.body.appendChild(d);var s=getComputedStyle(d);" \
			+ "var r=[s.paddingLeft,s.paddingTop,s.paddingRight,s.paddingBottom].map(function(v){return parseFloat(v)||0;}).join(',');" \
			+ "d.remove();return r;})()"
	var result: Variant = JavaScriptBridge.eval(code, true)
	var parts := str(result).split(",")
	if parts.size() == 4:
		var ratio := maxf(1.0, DisplayServer.screen_get_scale())
		_web_insets = Vector4(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float()) * ratio
	return _web_insets


## Keeps a full-rect Control (HUD root, card layers) inside the safe area: its offsets follow the
## insets, also after the window turns. Call once the control is in the tree. Desktop: offsets 0.
## zoomed: in portrait the control is drawn PortraitLayout.ui_zoom() times larger (its layout size
## shrinks by that, so anchored children keep their places on the screen); 1 elsewhere.
static func fit_to_safe_area(control: Control, zoomed := false) -> void:
	if not control.is_inside_tree():
		return
	apply_safe_offsets(control, zoomed)
	var viewport := control.get_viewport()
	var follow := func() -> void:
		if is_instance_valid(control) and control.is_inside_tree():
			apply_safe_offsets(control, zoomed)
	viewport.size_changed.connect(follow)
	# Connected only while the control is in the tree: a freed control would otherwise stay
	# connected (turning the phone later logged a freed lambda capture).
	control.tree_exiting.connect(func() -> void:
		var leaving := control.get_viewport()
		if leaving != null and leaving.size_changed.is_connected(follow):
			leaving.size_changed.disconnect(follow))
	control.tree_entered.connect(func() -> void:
		var entering := control.get_viewport()
		if entering != null and not entering.size_changed.is_connected(follow):
			entering.size_changed.connect(follow)
		follow.call())


static func apply_safe_offsets(control: Control, zoomed := false) -> void:
	var viewport := control.get_viewport()
	var visible := viewport.get_visible_rect()
	var safe := safe_rect(viewport)
	var zoom := 1.0
	if zoomed:
		zoom = PortraitLayout.ui_zoom()
		control.pivot_offset = Vector2.ZERO
		control.scale = Vector2.ONE * zoom
	control.offset_left = safe.position.x - visible.position.x
	control.offset_top = safe.position.y - visible.position.y
	control.offset_right = safe.position.x + safe.size.x / zoom - visible.end.x
	control.offset_bottom = safe.position.y + safe.size.y / zoom - visible.end.y


# --- Stage ---

## Places stage (a plain Control without anchors) in area of its parent and draws it zoom times
## larger: its layout size is area.size / zoom, so anchored children lay out in mockup pixels as
## on the PC. zoom 1 over the whole viewport restores the full-rect anchors.
static func place_stage(stage: Control, area: Rect2, zoom: float, full: Rect2) -> void:
	if is_equal_approx(zoom, 1.0) and area.is_equal_approx(full):
		stage.scale = Vector2.ONE
		stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	stage.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stage.scale = Vector2(zoom, zoom)
	stage.position = area.position.round()
	stage.size = (area.size / zoom).floor()
