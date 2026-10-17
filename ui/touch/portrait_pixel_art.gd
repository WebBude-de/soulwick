extends RefCounted
## Drawn pixel-art placeholders of the portrait controller field (PortraitPad, briefing SPRITES_V10
## §10): casing, D-pad, round A/B buttons, small round buttons, flat Start/Select buttons and the 3×5
## letters printed on the casing. One texel per art pixel, hard edges, the UI palette (dark casing
## with a lilac tone, gold A, violet B); the pad draws them at whole window pixels per art pixel.
## art/ui/touch/<name>.png replaces a placeholder of the same name (sprite()). Preload, no class_name.

const DIR := "res://art/ui/touch/"

## File names (without .png) and sizes in art pixels (briefing SPRITES_V10 §10).
const PANEL := "portrait_panel"
const PANEL_SIZE := 24
## 9-slice margin of the casing (art pixels on every side).
const PANEL_MARGIN := 8
const DPAD := "dpad"
const DPAD_SIZE := 52
## Arm width and the length of one arm of the D-pad cross.
const DPAD_ARM := 16
const DPAD_LENGTH := 18
const BUTTON_A := "button_a"
const BUTTON_B := "button_b"
const BUTTON_BIG_SIZE := 28
const BUTTON_SMALL := "button_small"
const BUTTON_SMALL_SIZE := 20
const BUTTON_FLAT := "button_flat"
const BUTTON_FLAT_SIZE := Vector2i(20, 8)
const PRESSED := "_pressed"
## Thickness of a round button below its face (art pixels); pressed, the face sits on it.
const DEPTH := 2

# Palette (UiKit, SPRITES_V10 header): casing dark with a lilac tone.
const OUTLINE := Color("#15131f")
const CASING := Color("#2b2540")
const CASING_LIGHT := Color("#3b3356")
const CASING_SHINE := Color("#4a4170")
const CASING_DARK := Color("#211c33")
const GROOVE := Color("#1c1a2b")
const PRINT := Color("#7a7396")
const LED := Color("#a66ef0")
## Ring colours of the round buttons: [face, light (top left), dark (bottom right), thickness].
const COLORS_A: Array[Color] = [Color("#f2cf4a"), Color("#fff0a8"), Color("#c9a227"), Color("#7d6114")]
const COLORS_B: Array[Color] = [Color("#a66ef0"), Color("#cba6ff"), Color("#7a48c0"), Color("#45286f")]
const COLORS_SMALL: Array[Color] = [Color("#5d577a"), Color("#8f88ad"), Color("#3b3650"), Color("#211c33")]
const COLORS_FLAT: Array[Color] = [Color("#4a4466"), Color("#6c6590"), Color("#2f2a45"), Color("#1c1a2b")]
const DPAD_FACE := Color("#2f2a45")
const DPAD_LIGHT := Color("#4f4870")
const DPAD_DARK := Color("#1f1b30")
const DPAD_ARROW := Color("#7a7396")

## 3×5 letters (W is 5 wide) for the button letters and the brand line on the casing (art, not text).
const LETTERS := {
	"A": [".#.", "#.#", "###", "#.#", "#.#"],
	"B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": [".##", "#..", "#..", "#..", ".##"],
	"I": ["###", ".#.", ".#.", ".#.", "###"],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"],
	"L": ["#..", "#..", "#..", "#..", "###"],
	"O": [".#.", "#.#", "#.#", "#.#", ".#."],
	"S": [".##", "#..", ".#.", "..#", "##."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"W": ["#...#", "#...#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
}

static var _cache: Dictionary[String, Texture2D] = {}


## The file art/ui/touch/<art_name>.png, else the drawn placeholder (null for unknown names).
static func sprite(art_name: String) -> Texture2D:
	if _cache.has(art_name):
		return _cache[art_name]
	var result: Texture2D = null
	var path := DIR + art_name + ".png"
	if ResourceLoader.exists(path):
		result = load(path) as Texture2D
	if result == null:
		var drawn := image(art_name)
		if drawn != null:
			result = ImageTexture.create_from_image(drawn)
	_cache[art_name] = result
	return result


## A delivered file exists for art_name (no placeholder).
static func has_file(art_name: String) -> bool:
	return ResourceLoader.exists(DIR + art_name + ".png")


static func clear_cache() -> void:
	_cache.clear()


## Placeholder image of an art name, null for unknown names. "letters_<TEXT>" draws 3×5 letters.
static func image(art_name: String) -> Image:
	if art_name.begins_with("letters_"):
		return letters_image(art_name.trim_prefix("letters_"))
	var pressed := art_name.ends_with(PRESSED)
	var base := art_name.trim_suffix(PRESSED)
	match base:
		PANEL:
			return null if pressed else panel_image()
		DPAD:
			return dpad_image(pressed)
		BUTTON_A:
			return round_button_image(BUTTON_BIG_SIZE, COLORS_A, pressed)
		BUTTON_B:
			return round_button_image(BUTTON_BIG_SIZE, COLORS_B, pressed)
		BUTTON_SMALL:
			return round_button_image(BUTTON_SMALL_SIZE, COLORS_SMALL, pressed)
		BUTTON_FLAT:
			return flat_button_image(pressed)
	return null


# --- Casing ---

## 9-slice of the casing (PANEL_SIZE², margin PANEL_MARGIN): a dark lilac shell, a shine line at the
## top under the screen groove, a darker rim on the sides and rounded bottom corners.
static func panel_image() -> Image:
	var size := PANEL_SIZE
	var result := _blank(size, size)
	result.fill(CASING)
	for x in size:
		# Groove under the screen, then a shine line.
		result.set_pixel(x, 0, GROOVE)
		result.set_pixel(x, 1, GROOVE)
		result.set_pixel(x, 2, CASING_SHINE)
		result.set_pixel(x, 3, CASING_LIGHT)
	for y in range(2, size):
		result.set_pixel(0, y, CASING_LIGHT)
		result.set_pixel(size - 1, y, CASING_DARK)
	for x in size:
		result.set_pixel(x, size - 1, CASING_DARK)
		result.set_pixel(x, size - 2, CASING_DARK)
	# Rounded bottom corners (radius 5) with a dark edge.
	var radius := 5
	for y in range(size - radius, size):
		for x in size:
			var corner_x := -1.0
			if x < radius:
				corner_x = radius
			elif x >= size - radius:
				corner_x = size - radius
			else:
				continue
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(corner_x, size - radius))
			if distance > radius:
				result.set_pixel(x, y, Color(0, 0, 0, 0))
			elif distance > radius - 1.0:
				result.set_pixel(x, y, CASING_DARK)
	return result


# --- D-pad ---

## The D-pad cross (DPAD_SIZE², arms DPAD_ARM wide): raised face with a light top-left edge, a dark
## bottom-right edge, small arrows on the arms and a dimple in the middle. Pressed: every arm sunk
## (darker face, light edge gone); the pad only draws the region of the arm that is held.
static func dpad_image(pressed: bool) -> Image:
	var size := DPAD_SIZE
	var result := _blank(size, size)
	var low := DPAD_LENGTH
	var high := DPAD_LENGTH + DPAD_ARM
	var in_cross := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= size or y >= size:
			return false
		return (x >= low and x < high) or (y >= low and y < high)
	for y in size:
		for x in size:
			if not in_cross.call(x, y):
				continue
			var color := DPAD_DARK if pressed else DPAD_FACE
			var edge: bool = not in_cross.call(x - 1, y) or not in_cross.call(x + 1, y) \
					or not in_cross.call(x, y - 1) or not in_cross.call(x, y + 1)
			if edge:
				color = OUTLINE
			elif not pressed and (not in_cross.call(x - 2, y) or not in_cross.call(x, y - 2)):
				color = DPAD_LIGHT
			elif not in_cross.call(x + 2, y) or not in_cross.call(x, y + 2):
				color = GROOVE if pressed else DPAD_DARK
			elif pressed and (not in_cross.call(x - 2, y) or not in_cross.call(x, y - 2)):
				color = GROOVE
			result.set_pixel(x, y, color)
	# Arrows (5 wide, 3 tall) near the outer end of every arm.
	var mid := size / 2
	var arrow := DPAD_ARROW if not pressed else Color(DPAD_ARROW, 0.7)
	for row in 3:
		for w in range(-row - 1, row + 1):
			_put(result, Vector2i(mid + w, 4 + row), arrow)
			_put(result, Vector2i(mid + w, size - 5 - row), arrow)
			_put(result, Vector2i(4 + row, mid + w), arrow)
			_put(result, Vector2i(size - 5 - row, mid + w), arrow)
	# Dimple in the middle.
	for y in range(mid - 3, mid + 3):
		for x in range(mid - 3, mid + 3):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(mid, mid))
			if d <= 3.0:
				result.set_pixel(x, y, DPAD_DARK if d > 2.0 else GROOVE)
	return result


## Region of one direction of the D-pad image (art pixels): the arm towards direction (one of the
## four unit directions).
static func dpad_arm_region(direction: Vector2i) -> Rect2i:
	var low := DPAD_LENGTH
	match direction:
		Vector2i.UP:
			return Rect2i(low, 0, DPAD_ARM, low)
		Vector2i.DOWN:
			return Rect2i(low, low + DPAD_ARM, DPAD_ARM, low)
		Vector2i.LEFT:
			return Rect2i(0, low, low, DPAD_ARM)
		Vector2i.RIGHT:
			return Rect2i(low + DPAD_ARM, low, low, DPAD_ARM)
	return Rect2i()


# --- Buttons ---

## Round button of size² art pixels, opaque: face with outline and a ring shaded in steps (light top
## left, dark bottom right), below it DEPTH pixels of thickness. Pressed: the face sits lower on the
## thickness and is shaded darker. colors: [face, light, dark, thickness].
static func round_button_image(size: int, colors: Array[Color], pressed: bool) -> Image:
	var result := _blank(size, size)
	var radius := (size - DEPTH) * 0.5
	var top := Vector2(size * 0.5, radius)
	var face := top + Vector2(0, DEPTH) if pressed else top
	var body := top + Vector2(0, DEPTH)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var offset := p - face
			var distance := offset.length()
			var color := Color(0, 0, 0, 0)
			if distance <= radius:
				if distance > radius - 1.0:
					color = OUTLINE
				else:
					var light := (offset / maxf(distance, 0.001)).dot(Vector2(-0.7071, -0.7071)) if distance > 0.0 else 0.0
					color = colors[0].darkened(0.18) if pressed else colors[0]
					if distance > radius - 2.5:
						if light > 0.4 and not pressed:
							color = colors[1]
						elif light < -0.4:
							color = colors[2]
					elif not pressed and (offset + Vector2(radius * 0.4, radius * 0.4)).length() < radius * 0.22:
						color = colors[1]
			elif not pressed and p.distance_to(body) <= radius:
				color = OUTLINE if p.distance_to(body) > radius - 1.0 else colors[3]
			result.set_pixel(x, y, color)
	return result


## Art-pixel offset of a round button's face centre from the image centre (icons sit on the face).
static func face_offset(pressed: bool) -> float:
	return DEPTH * 0.5 if pressed else -DEPTH * 0.5


## Flat pill (Start/Select, BUTTON_FLAT_SIZE): rounded ends, outline, light top edge; pressed darker
## and one pixel lower.
static func flat_button_image(pressed: bool) -> Image:
	var size := BUTTON_FLAT_SIZE
	var result := _blank(size.x, size.y)
	var shift := 1 if pressed else 0
	var height := size.y - 1
	for y in range(shift, height + shift):
		for x in size.x:
			var local_y := y - shift
			var cap := float(height) * 0.5
			var cx := clampf(x + 0.5, cap, size.x - cap)
			var distance := Vector2(x + 0.5, local_y + 0.5).distance_to(Vector2(cx, cap))
			if distance > cap:
				continue
			var color := COLORS_FLAT[2] if pressed else COLORS_FLAT[0]
			if distance > cap - 1.0:
				color = OUTLINE
			elif local_y <= 1 and not pressed:
				color = COLORS_FLAT[1]
			result.set_pixel(x, y, color)
	if not pressed:
		# Thickness: one dark row under the pill.
		for x in range(2, size.x - 2):
			if result.get_pixel(x, height).a <= 0.0:
				result.set_pixel(x, height, COLORS_FLAT[3])
	return result


# --- Letters ---

## Letters of text in the 3×5 font (one pixel apart), PRINT colour; unknown letters leave a gap.
static func letters_image(text: String) -> Image:
	var width := 0
	for letter in text:
		width += _letter_width(letter) + 1
	width = maxi(1, width - 1)
	var result := _blank(width, 5)
	var x := 0
	for letter in text:
		var rows: Array = LETTERS.get(letter, [])
		for y in rows.size():
			var row: String = rows[y]
			for i in row.length():
				if row[i] == "#":
					result.set_pixel(x + i, y, PRINT)
		x += _letter_width(letter) + 1
	return result


static func _letter_width(letter: String) -> int:
	var rows: Array = LETTERS.get(letter, [])
	return (rows[0] as String).length() if not rows.is_empty() else 3


static func _blank(width: int, height: int) -> Image:
	var result := Image.create(width, height, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	return result


static func _put(target: Image, point: Vector2i, color: Color) -> void:
	if point.x >= 0 and point.y >= 0 and point.x < target.get_width() and point.y < target.get_height():
		target.set_pixelv(point, color)
