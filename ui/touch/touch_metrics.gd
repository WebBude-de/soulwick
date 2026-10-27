class_name TouchMetrics
extends RefCounted
## Physical size of the screen for the touch controls (D-219, playtest 26.10.2026: "viel zu klein"):
## how many millimetres one pixel spans, so sticks and buttons get a thumb-sized area on every phone
## instead of a fixed pixel count. Phones and tablets (app) ask the display for its DPI; the browser
## on a phone or tablet counts CSS pixels (about 1/160 inch there, like Android dp). Everything else
## (desktop with "-- touch=1", tests, previews) counts as a typical phone (REFERENCE_DPI with a
## REFERENCE_SHORT_PX short side, about 65 mm). Pure helpers, no state but the web page cache.

## Typical phone (Pixel 7: 416 dpi, Galaxy A54: 403, iPhone 15: 460) with a 1080 px short side.
const REFERENCE_DPI := 420.0
const REFERENCE_SHORT_PX := 1080.0
## Browser on a phone: CSS pixels per inch (devicePixelRatio already counted in by the browser).
const CSS_PX_PER_INCH := 160.0
const MM_PER_INCH := 25.4
## A screen whose short side measures outside this range (mm) counts as a wrong reading.
const MIN_SHORT_MM := 40.0
const MAX_SHORT_MM := 300.0
## Web build: how often the page size is read again (turning the phone changes it).
const WEB_PAGE_MSEC := 1000
const WEB_PAGE_JS := "window.innerWidth+','+window.innerHeight"

static var _web_page := Vector2.ZERO
static var _web_page_msec := -1


## Short side of the reference phone in mm (about 65).
static func reference_short_mm() -> float:
	return REFERENCE_SHORT_PX / REFERENCE_DPI * MM_PER_INCH


## Millimetres per pixel of a view that fills the screen (landscape overlay: the visible viewport
## stretched uniformly onto the window). window: window size in device pixels (only the device
## reading uses it).
static func mm_per_view_px(view: Vector2, window: Vector2) -> float:
	var short_mm := device_short_mm(window)
	if short_mm <= 0.0:
		short_mm = reference_short_mm()
	return short_mm / maxf(1.0, minf(view.x, view.y))


## Millimetres per window (device) pixel (portrait controller field, which lays out in window pixels).
static func mm_per_window_px(window: Vector2) -> float:
	var short_mm := device_short_mm(window)
	if short_mm <= 0.0:
		return MM_PER_INCH / REFERENCE_DPI
	return short_mm / maxf(1.0, minf(window.x, window.y))


## Pixels for a length in mm at mm_per_px.
static func px(mm: float, mm_per_px: float) -> float:
	return mm / maxf(0.0001, mm_per_px)


## Short side of this device's screen in mm for a window of that size (device pixels); 0 = unknown
## (desktop) or a reading outside MIN_SHORT_MM..MAX_SHORT_MM.
static func device_short_mm(window: Vector2) -> float:
	var short_px := minf(window.x, window.y)
	if short_px <= 0.0:
		return 0.0
	var mm := 0.0
	if OS.has_feature("mobile"):
		var dpi := float(DisplayServer.screen_get_dpi())
		if dpi > 0.0:
			mm = short_px / dpi * MM_PER_INCH
	elif OS.has_feature("web") and _is_handheld_web():
		var page := _web_page_size()
		var css_short := minf(page.x, page.y)
		if css_short > 0.0:
			mm = css_short / CSS_PX_PER_INCH * MM_PER_INCH
	return short_mm_or_zero(mm)


## mm if it is a plausible short side of a screen, else 0.
static func short_mm_or_zero(mm: float) -> float:
	return mm if mm >= MIN_SHORT_MM and mm <= MAX_SHORT_MM else 0.0


static func _is_handheld_web() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()


## The page's inner size in CSS pixels, asked at most once per WEB_PAGE_MSEC.
static func _web_page_size() -> Vector2:
	var now := Time.get_ticks_msec()
	if _web_page_msec >= 0 and now - _web_page_msec < WEB_PAGE_MSEC:
		return _web_page
	_web_page_msec = now
	var answer: Variant = JavaScriptBridge.eval(WEB_PAGE_JS, true)
	if typeof(answer) != TYPE_STRING:
		return _web_page
	var parts := (answer as String).split(",")
	if parts.size() == 2:
		_web_page = Vector2(float(parts[0]), float(parts[1]))
	return _web_page
