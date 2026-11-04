class_name HomeWindow
extends Node2D
## One window in the back wall of the home (KE8b, playtest 04.11.2026 "aus dem Fenster ist es immer
## Nacht"): the view outside follows the same clock as the village (VillageDaylight.night_amount):
## blue sky with a drifting cloud and green hills by day, an orange and violet sky with a low sun at
## dusk, a dark sky with stars (and the moon in one window) at night; a little house on the hills
## lights its window when it gets dark. Pixel art only (D-218): the sky is a few hard colour bands,
## every pixel on the art grid. Curtains and a rod frame the window.
## The frame comes from the delivered pictures home_window_day/night.png (V13d): the pixels that
## are equal in both are the frame, the others the glass, so the sky can change without new art.
## A delivered frame with see-through glass (home_window_frame.png, SPRITES_V13 Teil C) replaces
## that; without any picture a frame is drawn. Delivered views home_window_sky_<day|dusk|night>.png
## (the glass size, SPRITES_V13 Teil C) replace the drawn view of their phase. Art px; the parent
## (HomeRoom) scales to the world.
## The node origin is the window's foot point (middle of the sill, HomeLayout.window_foot).

enum Phase { DAY, DUSK, NIGHT }

## TESTWERT: night amount limits of the views (VillageDaylight: dusk 17:30–20:00, dawn 5:00–7:00).
const DUSK_FROM := 0.3
const NIGHT_FROM := 0.75
## Frame size and foot (pivot) of the delivered window pictures.
const SIZE := Vector2i(32, 32)
const PIVOT := Vector2i(16, 31)
const FRAME_FILE := "home_window_frame"
const SKY_FILES := {Phase.DAY: "home_window_sky_day", Phase.DUSK: "home_window_sky_dusk", Phase.NIGHT: "home_window_sky_night"}
## Sky bands top to bottom, hills (far, near), cloud or sun or moon, stars.
const SKY := {
	Phase.DAY: [Color("#5b9fd8"), Color("#79b6e6"), Color("#a3d2f0")],
	Phase.DUSK: [Color("#3a2e68"), Color("#b8557a"), Color("#f0975a")],
	Phase.NIGHT: [Color("#11132e"), Color("#181c40"), Color("#20264f")],
}
const HILLS := {
	Phase.DAY: [Color("#6fae52"), Color("#4f8a3c")],
	Phase.DUSK: [Color("#4a3b58"), Color("#33283f")],
	Phase.NIGHT: [Color("#1a1d33"), Color("#111326")],
}
const CLOUD := Color("#f4f8ff")
const SUN := Color("#ffe08a")
const DUSK_SUN := Color("#ffc05a")
const MOON := Color("#f3eccf")
const STAR := Color("#fff6d5")
const HOUSE := Color("#2b2233")
const HOUSE_LIT := Color("#ffd166")
const FRAME_WOOD := Color("#5c3a24")
const FRAME_LIGHT := Color("#8a5a34")
const CURTAIN := Color("#a83a3a")
const CURTAIN_LIGHT := Color("#c85252")
const CURTAIN_DARK := Color("#7a2a2e")
const ROD := Color("#3b2a22")
## TESTWERT: the cloud drifts one art px every CLOUD_STEP seconds; stars blink every STAR_STEP s.
const CLOUD_STEP := 1.5
const STAR_STEP := 0.9
const REDRAW_STEP := 0.25

static var _mask: Image = null
static var _frame: Image = null
## Delivered views by phase (null: drawn); loaded once.
static var _skies: Dictionary = {}

## Column of this window (varies hills, cloud and stars; the middle one shows the moon).
var col := 0
var night := 0.0
var show_moon := false
var _texture: ImageTexture = null
var _time := 0.0
var _redraw_left := 0.0


static func create(window_col: int, moon := false) -> HomeWindow:
	var window := HomeWindow.new()
	window.name = "Window%d" % window_col
	window.col = window_col
	window.show_moon = moon
	window.position = HomeLayout.window_foot(window_col)
	return window


## Column of the middle window (the one with the little house on the hill and the moon).
static func middle_col() -> int:
	return HomeLayout.WINDOW_COLS[floori(HomeLayout.WINDOW_COLS.size() * 0.5)]


static func phase_for(amount: float) -> Phase:
	if amount >= NIGHT_FROM:
		return Phase.NIGHT
	if amount >= DUSK_FROM:
		return Phase.DUSK
	return Phase.DAY


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture = ImageTexture.create_from_image(build_image(night, _time))


func set_night(amount: float) -> void:
	night = clampf(amount, 0.0, 1.0)
	_refresh()


func get_phase() -> Phase:
	return phase_for(night)


func get_texture() -> Texture2D:
	return _texture


func _process(delta: float) -> void:
	_time += delta
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = REDRAW_STEP
		_refresh()


func _refresh() -> void:
	if _texture == null:
		return
	_texture.update(build_image(night, _time))
	queue_redraw()


func _draw() -> void:
	_draw_curtains()
	if _texture != null:
		draw_texture(_texture, -Vector2(PIVOT))


## Rod over the window and a curtain on each side, gathered at two thirds (art px).
func _draw_curtains() -> void:
	var top := -PIVOT.y - 2
	draw_rect(Rect2(-PIVOT.x - 6, top, SIZE.x + 12, 2), ROD)
	for side: int in [-1, 1]:
		var inner := float(PIVOT.x - 1) * side
		var outer := float(PIVOT.x + 5) * side
		var left := minf(inner, outer)
		var width := absf(outer - inner)
		draw_rect(Rect2(left, top + 2, width, 20), CURTAIN)
		draw_rect(Rect2(left + (width - 2.0 if side < 0 else 0.0), top + 2, 2, 20), CURTAIN_LIGHT)
		draw_rect(Rect2(left, top + 22, width, 2), CURTAIN_DARK)
		draw_rect(Rect2(left + 1, top + 24, width - 2, 6), CURTAIN)
		draw_rect(Rect2(left + 1 + (width - 3.0 if side < 0 else 0.0), top + 24, 1, 6), CURTAIN_LIGHT)


## The window picture (frame and the view through the glass) for a night amount at time t (pure).
func build_image(amount: float, t: float) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var mask := glass_mask()
	var frame := frame_image()
	var glass := _glass_rect(mask)
	var phase := phase_for(amount)
	for y in SIZE.y:
		for x in SIZE.x:
			if mask.get_pixel(x, y).a > 0.5:
				image.set_pixel(x, y, view_color(phase, Vector2i(x, y) - glass.position, glass.size, t))
			elif frame.get_pixel(x, y).a > 0.0:
				image.set_pixel(x, y, frame.get_pixel(x, y))
	return image


## Colour of the view at p (px inside the glass rectangle of size) in a phase at time t.
func view_color(phase: Phase, p: Vector2i, size: Vector2i, t: float) -> Color:
	var delivered := sky_image(phase)
	if delivered != null:
		return delivered.get_pixel(clampi(p.x, 0, delivered.get_width() - 1), clampi(p.y, 0, delivered.get_height() - 1))
	var bands: Array = SKY[phase]
	var hills: Array = HILLS[phase]
	var horizon := int(size.y * 0.68)
	var far := horizon + _hill_bump(p.x, 3, 2)
	var near := horizon + 3 + _hill_bump(p.x + 5, 4, 2)
	if p.y >= near:
		return hills[1]
	# A little house on the far hill of the middle window: lit once it gets dark.
	if col == middle_col():
		var house := _house_color(p, horizon, phase)
		if house.a > 0.0:
			return house
	if p.y >= far:
		return hills[0]
	var sky: Color = bands[clampi(floori(float(p.y * bands.size()) / float(maxi(1, horizon))), 0, bands.size() - 1)]
	match phase:
		Phase.DAY:
			if _in_cloud(p, size, t):
				return CLOUD
			if col == HomeLayout.WINDOW_COLS[0] and _in_disc(p, Vector2i(3, 3), 2):
				return SUN
		Phase.DUSK:
			if _in_disc(p, Vector2i(size.x - 5 + (col % 2), horizon - 1), 2):
				return DUSK_SUN
		Phase.NIGHT:
			if show_moon and _in_moon(p, Vector2i(size.x - 5, 4)):
				return MOON
			if _is_star(p, t):
				return STAR
	return sky


## Height offset of a hill line (whole px, -amp..amp) for column x.
func _hill_bump(x: int, period: int, amp: int) -> int:
	return int(round(sin(float(x + col * 7) / float(period)) * amp)) - amp


func _house_color(p: Vector2i, horizon: int, phase: Phase) -> Color:
	var base := Vector2i(6, horizon - 1)
	var local := p - base
	if local.y > 0 or local.y < -5 or local.x < -1 or local.x > 5:
		return Color(0, 0, 0, 0)
	if local.y <= -3:
		var half := local.y + 5
		if local.x < 2 - half or local.x > 2 + half:
			return Color(0, 0, 0, 0)
		return HOUSE.darkened(0.2)
	if local.x < 0 or local.x > 4:
		return Color(0, 0, 0, 0)
	if local == Vector2i(2, -1) and phase != Phase.DAY:
		return HOUSE_LIT
	return HOUSE if phase != Phase.DAY else Color("#c8a07a")


func _in_cloud(p: Vector2i, size: Vector2i, t: float) -> bool:
	var span := size.x + 10
	var x0 := posmod(int(t / CLOUD_STEP) + col * 9, span) - 6
	var y0 := 3 + (col % 3)
	var local := p - Vector2i(x0, y0)
	if local.y == 0:
		return local.x >= 1 and local.x <= 3
	if local.y == 1:
		return local.x >= 0 and local.x <= 5
	return false


static func _in_disc(p: Vector2i, centre: Vector2i, radius: int) -> bool:
	var d := p - centre
	return d.x * d.x + d.y * d.y <= radius * radius


static func _in_moon(p: Vector2i, centre: Vector2i) -> bool:
	return _in_disc(p, centre, 2) and not _in_disc(p, centre + Vector2i(1, -1), 2)


func _is_star(p: Vector2i, t: float) -> bool:
	if posmod(p.x * 73 + p.y * 151 + col * 37, 61) != 0:
		return false
	# Every star blinks off now and then (one step in four, not all at once).
	return posmod(int(t / STAR_STEP) + p.x + p.y, 4) != 0


## The delivered view of a phase (null while it is drawn).
static func sky_image(phase: Phase) -> Image:
	if not _skies.has(phase):
		_skies[phase] = _load_image(String(SKY_FILES[phase]))
	return _skies[phase]


## Glass pixels (white) of the window picture.
static func glass_mask() -> Image:
	if _mask == null:
		_build_masks()
	return _mask


## Frame pixels (the rest transparent).
static func frame_image() -> Image:
	if _frame == null:
		_build_masks()
	return _frame


static func _glass_rect(mask: Image) -> Rect2i:
	var used := mask.get_used_rect()
	return used if used.has_area() else Rect2i(3, 3, SIZE.x - 6, SIZE.y - 8)


## Frame and glass from a see-through frame picture, from the day and night pictures (equal pixels
## = frame), or drawn.
static func _build_masks() -> void:
	_mask = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_mask.fill(Color(0, 0, 0, 0))
	_frame = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_frame.fill(Color(0, 0, 0, 0))
	var frame_art := _load_image(FRAME_FILE)
	var day := _load_image(HomeArt.WINDOW_DAY)
	var night_art := _load_image(HomeArt.WINDOW_NIGHT)
	if frame_art != null and frame_art.get_size() == SIZE:
		_frame.copy_from(frame_art)
		_fill_enclosed_glass()
		return
	if day != null and night_art != null and day.get_size() == SIZE and night_art.get_size() == SIZE:
		for y in SIZE.y:
			for x in SIZE.x:
				var a := day.get_pixel(x, y)
				var b := night_art.get_pixel(x, y)
				if a.a > 0.0 and a.is_equal_approx(b):
					_frame.set_pixel(x, y, a)
				elif a.a > 0.0:
					_mask.set_pixel(x, y, Color.WHITE)
		return
	_draw_frame()


## Glass of a see-through frame: transparent pixels inside the frame's outer box (not the edge).
static func _fill_enclosed_glass() -> void:
	var used := _frame.get_used_rect()
	for y in range(used.position.y + 1, used.end.y - 3):
		for x in range(used.position.x + 1, used.end.x - 1):
			if _frame.get_pixel(x, y).a == 0.0:
				_mask.set_pixel(x, y, Color.WHITE)


## A drawn window: wooden frame with a cross bar and a sill, four panes.
static func _draw_frame() -> void:
	for y in range(2, 30):
		for x in range(3, 29):
			var edge := x < 5 or x > 26 or y < 4 or y > 27 or x == 15 or x == 16 or y == 15
			if edge:
				_frame.set_pixel(x, y, FRAME_WOOD if x != 3 and y != 2 else FRAME_LIGHT)
			else:
				_mask.set_pixel(x, y, Color.WHITE)
	for x in range(1, 31):
		_frame.set_pixel(x, 30, FRAME_LIGHT)
		_frame.set_pixel(x, 31, FRAME_WOOD)


static func _load_image(file: String) -> Image:
	var path := HomeArt.DIR + file + ".png"
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


## Forgets the frame and glass (tests, new art).
static func clear_cache() -> void:
	_mask = null
	_frame = null
	_skies.clear()
