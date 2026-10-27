extends RefCounted
## Drawn pixel-art placeholders of the touch controls (Projektmitglied 17.10.2026: "so pixelig wie
## das Spiel"): every part of SPRITES_V10 §1 as an Image at 1 texel per art pixel in the briefing's
## sizes and palette, upscaled by the overlay with nearest filtering at whole screen pixels. No
## smooth circles, no gradients: discs are rasterised per pixel (hard edges), rings are shaded in
## steps (light top left, dark bottom right), icons are pixel grids with an outline added in code.
## TouchArt uses these only while art/ui/touch/<name>.png is missing. Preload, no class_name.

# Palette (SPRITES_V10 header, UiKit).
const OUTLINE := Color("#1c1a2b")
const FILL := Color(0.082, 0.075, 0.122, 0.5)
const FILL_STICK := Color(0.082, 0.075, 0.122, 0.42)
const FILL_PRESSED := Color(0.42, 0.35, 0.16, 0.62)
const RIM := Color("#5d577a")
const TEXT := Color("#e9e4d2")
const TEXT_SHADOW := Color("#b9b3c9")
const GOLD := Color("#f2cf4a")
const MAGIC := Color("#a66ef0")
const INNER_EDGE := Color(0.11, 0.1, 0.17, 0.6)
const SHADOW := Color(0.11, 0.1, 0.17, 0.4)
const COOLDOWN_DARK := Color(0.082, 0.075, 0.122, 0.62)
## Ring colours per look: [base, light (top left), dark (bottom right)].
const RING_WARM: Array[Color] = [Color("#d9b77e"), Color("#f0dcb0"), Color("#a8885a")]
const RING_EMBER: Array[Color] = [Color("#c8643c"), Color("#e8946a"), Color("#8e4228")]
const RING_PRESSED: Array[Color] = [Color("#f2cf4a"), Color("#fff0a8"), Color("#c9a227")]
const RING_DISABLED: Array[Color] = [Color("#7a7396"), Color("#8f88ad"), Color("#5d577a")]
## Ring alpha: crisp but the game stays visible through the controls.
const RING_ALPHA := 0.9
## Button "thickness" below the face (art pixels), like a key seen from slightly above.
const BUTTON_DEPTH := 2
const RING_WIDTH := 2
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

## Icon grids, 16 × 16: "#" light, "g" gold, "m" magic, "d" dark line. The outline is added around.
const ICON_GRIDS := {
	&"attack": [
		"................", ".............##.", "............###.", "...........###..",
		"..........###...", ".........###....", "........###.....", "....#..###......",
		".....####.......", "......##........", ".....#.#........", "....#...#.......",
		"...#............", "..##............", "................", "................",
	],
	&"special": [
		"................", ".............#..", "..#.........###.", ".......#.....#..",
		".......#........", "......###.......", "......#g#.......", "..###########...",
		"...####g####....", "....#######.....", ".....#####......", ".....##.##......",
		"....##...##.....", "....#.....#.....", "................", "................",
	],
	&"dash": [
		"................", "................", "................", ".........#......",
		"..#####..##.....", ".........###....", ".....########...", ".###.#########..",
		".###.#########..", ".....########...", ".........###....", "...####..##.....",
		".........#......", "................", "................", "................",
	],
	&"side_dash": [
		"................", ".........#......", "..#####..##.....", ".........###....",
		".....########...", ".###.#########..", ".###.#########..", ".....########...",
		".........###....", "...####..##.....", ".........#......", "................",
		"................", "..############..", "................", "................",
	],
	&"jump": [
		"................", ".......##.......", "......####......", ".....######.....",
		"....########....", "...##########...", "......####......", "......####......",
		"......####......", "......####......", "................", "................",
		".#............#.", "..############..", "................", "................",
	],
	&"interact": [
		"................", "......##........", "...##.##.##.....", "...##.##.##.##..",
		"...##.##.##.##..", "...##.##.##.##..", "...##.##.##.##..", ".#.###########..",
		".#############..", "..############..", "...###########..", "....#########...",
		".....#######....", "................", "................", "................",
	],
	&"switch": [
		"................", "................", "..........#.....", "..........##....",
		"..###########...", "..###########...", "..........##....", "..........#.....",
		".....#..........", "....##..........", "...###########..", "...###########..",
		"....##..........", ".....#..........", "................", "................",
	],
	&"pause": [
		"................", "................", "................", "....###..###....",
		"....###..###....", "....###..###....", "....###..###....", "....###..###....",
		"....###..###....", "....###..###....", "....###..###....", "....###..###....",
		"....###..###....", "................", "................", "................",
	],
	&"spell": [
		"................", ".......m........", "......mmm.......", "......mgm.......",
		".....mmgmm......", ".....mgggm......", "....mmgggmm.....", "....mgg#ggm.....",
		"....mg###gm.....", ".....mg#gm......", "......mmm.......", ".......#........",
		"......###.......", ".....#####......", "................", "................",
	],
	&"menu": [
		"................", "................", "..#####..#####..", ".######dd######.",
		".#dddd#dd#dddd#.", ".######dd######.", ".#dddd#dd#dddd#.", ".######dd######.",
		".#ddd##dd#ddd##.", ".######dd######.", ".######dd######.", "..#####dd#####..",
		"................", "................", "................", "................",
	],
}
const ICON_COLORS := {"#": TEXT, "g": GOLD, "m": MAGIC, "d": OUTLINE}


## Image of a TouchArt name (without .png), or null for an unknown name. Cooldown frames are
## "touch_cooldown_<frame size>_<frame>" (one image per frame).
static func image(art_name: String) -> Image:
	if art_name.begins_with("icon_"):
		var id := StringName(art_name.trim_prefix("icon_"))
		return icon_image(id) if ICON_GRIDS.has(id) else null
	if art_name.begins_with("touch_cooldown_"):
		var parts := art_name.trim_prefix("touch_cooldown_").split("_")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			return cooldown_image(int(parts[0]), int(parts[1]), 8)
		return null
	match art_name:
		"touch_stick_base":
			return stick_base_image(60, false)
		"touch_stick_aim_base":
			return stick_base_image(60, true)
		"touch_stick_arrows":
			return stick_arrows_image(60)
		"touch_stick_knob":
			return knob_image(24, false)
		"touch_stick_knob_pressed":
			return knob_image(24, true)
	for prefix: String in ["touch_btn_large", "touch_btn_small", "touch_btn"]:
		if art_name.begins_with(prefix):
			var state := art_name.trim_prefix(prefix)
			if state not in ["", "_pressed", "_disabled"]:
				return null
			var size: int = {"touch_btn_large": 48, "touch_btn_small": 24, "touch_btn": 32}[prefix]
			return button_image(size, state)
	return null


# --- Buttons ---

## Round button of size × size art pixels: a face with outline, a 2 px ring shaded in steps, a dark
## inner edge and a translucent fill, and below it the button's thickness (missing when pressed:
## the face sits lower instead). state: "", "_pressed" or "_disabled".
static func button_image(size: int, state := "") -> Image:
	var pressed := state == "_pressed"
	var ring: Array[Color] = RING_PRESSED if pressed else (RING_DISABLED if state == "_disabled" else RING_WARM)
	var radius := (size - BUTTON_DEPTH) * 0.5
	var top := Vector2(size * 0.5, radius)
	var face := top + Vector2(0, BUTTON_DEPTH) if pressed else top
	var body := top + Vector2(0, BUTTON_DEPTH)
	var result := _blank(size, size)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var color := _face_pixel(p, face, radius, ring, FILL_PRESSED if pressed else FILL)
			if color.a <= 0.0 and not pressed:
				var distance := p.distance_to(body)
				if distance <= radius:
					color = OUTLINE if distance > radius - 1.0 else RIM
			result.set_pixel(x, y, color)
	return result


## Art-pixel offset of the face centre from the image centre (icons sit on the face).
static func face_offset(pressed: bool) -> float:
	return BUTTON_DEPTH * 0.5 if pressed else -BUTTON_DEPTH * 0.5


## Cooldown frame over a normal-state button face: the dark pie still cooling down, released
## clockwise from 12 o'clock, and a gold progress ring on the released part. frame 0 = just used.
static func cooldown_image(size: int, frame: int, frames: int) -> Image:
	var released := clampf(float(frame) / float(maxi(1, frames)), 0.0, 1.0)
	var radius := (size - BUTTON_DEPTH) * 0.5
	var center := Vector2(size * 0.5, radius)
	var result := _blank(size, size)
	for y in size:
		for x in size:
			var offset := Vector2(x + 0.5, y + 0.5) - center
			var distance := offset.length()
			if distance > radius - 1.0:
				continue
			var share := fposmod(atan2(offset.x, -offset.y), TAU) / TAU
			if share >= released:
				result.set_pixel(x, y, COOLDOWN_DARK)
			elif distance > radius - 1.0 - RING_WIDTH:
				result.set_pixel(x, y, GOLD)
	return result


# --- Sticks ---

## Stick base: a quiet disc with outline, shaded ring (warm gold, the aim stick ember red), dark
## inner edge, translucent fill and a 1 px shadow below. The aim base carries four short crosshair
## ticks inside the ring so both sticks read differently.
static func stick_base_image(size: int, aim: bool) -> Image:
	var ring: Array[Color] = RING_EMBER if aim else RING_WARM
	var radius := size * 0.5 - 1.0
	var center := Vector2(size * 0.5, radius)
	var shadow_center := center + Vector2(0, 1)
	var result := _blank(size, size)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var color := _face_pixel(p, center, radius, ring, FILL_STICK)
			if color.a <= 0.0 and p.distance_to(shadow_center) <= radius:
				color = SHADOW
			result.set_pixel(x, y, color)
	if aim:
		var tick := Color(ring[1], RING_ALPHA)
		var inner := int(radius) - 2 - RING_WIDTH - 1
		for direction in DIRECTIONS:
			for step in 4:
				for point in _ray_pixels(Vector2i(size / 2, int(radius)), direction, inner - step, 0):
					_put(result, point, tick)
	return result


## Four small direction triangles inside the move stick's ring (5 × 3 art pixels each).
static func stick_arrows_image(size: int) -> Image:
	var result := _blank(size, size)
	var color := Color(TEXT, 0.6)
	var radius := size * 0.5 - 1.0
	var tip_distance := int(radius) - 2 - RING_WIDTH - 2
	for direction in DIRECTIONS:
		for row in 3:
			for point in _ray_pixels(Vector2i(size / 2, int(radius)), direction, tip_distance - row, row):
				_put(result, point, color)
	return result


## Stick knob: a domed disc, warm and translucent (gold and fuller while held), a light rim top
## left, a darker one bottom right, outline and a 1 px shadow.
static func knob_image(size: int, pressed: bool) -> Image:
	var ring: Array[Color] = RING_PRESSED if pressed else RING_WARM
	var fill := Color(ring[0], 0.74 if pressed else 0.62)
	var radius := size * 0.5 - 1.0
	var center := Vector2(size * 0.5, radius)
	var result := _blank(size, size)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var offset := p - center
			var distance := offset.length()
			var color := Color(0, 0, 0, 0)
			if distance <= radius:
				if distance > radius - 1.0:
					color = OUTLINE
				elif distance > radius - 2.5:
					var light := _light(offset, distance)
					color = fill
					if light > 0.35:
						color = Color(ring[1], minf(1.0, fill.a + 0.25))
					elif light < -0.35:
						color = Color(ring[2], fill.a)
				else:
					color = fill
					# A small highlight spot top left inside the dome.
					if (offset + Vector2(radius * 0.35, radius * 0.35)).length() < radius * 0.22:
						color = Color(ring[1], minf(1.0, fill.a + 0.2))
			elif (p - center - Vector2(0, 1)).length() <= radius:
				color = SHADOW
			result.set_pixel(x, y, color)
	return result


# --- Icons ---

## 16 × 16 icon from its grid with a 1 px outline around every motif pixel (8 neighbours) and a
## shadow edge under light strokes thicker than one pixel.
static func icon_image(id: StringName) -> Image:
	var rows: Array = ICON_GRIDS[id]
	var height := rows.size()
	var width := (rows[0] as String).length()
	var result := _blank(width, height)
	var solid := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= width or y >= height:
			return false
		return ICON_COLORS.has((rows[y] as String)[x])
	for y in height:
		for x in width:
			var cell := (rows[y] as String)[x]
			if ICON_COLORS.has(cell):
				var color: Color = ICON_COLORS[cell]
				if cell == "#" and not solid.call(x, y + 1) and solid.call(x, y - 1):
					color = TEXT_SHADOW
				result.set_pixel(x, y, color)
				continue
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if solid.call(x + dx, y + dy):
						result.set_pixel(x, y, OUTLINE)
	return result


# --- Helpers ---

## Pixel of a ringed disc at p (outline, shaded ring, dark inner edge, fill) or transparent.
static func _face_pixel(p: Vector2, center: Vector2, radius: float, ring: Array[Color], fill: Color) -> Color:
	var offset := p - center
	var distance := offset.length()
	if distance > radius:
		return Color(0, 0, 0, 0)
	if distance > radius - 1.0:
		return OUTLINE
	if distance > radius - 1.0 - RING_WIDTH:
		var light := _light(offset, distance)
		var color := ring[0]
		if light > 0.45:
			color = ring[1]
		elif light < -0.45:
			color = ring[2]
		return Color(color, RING_ALPHA)
	if distance > radius - 2.0 - RING_WIDTH:
		return INNER_EDGE
	return fill


## -1 (bottom right) .. 1 (top left): light from the top left.
static func _light(offset: Vector2, distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	return (offset / distance).dot(Vector2(-0.7071, -0.7071))


## Pixels at distance k (whole pixels) from the pixel corner centre along direction, half_width
## extra pixels to each side. The centre of an even disc lies between pixels, so a ray covers two
## pixel columns (or rows) and the four directions stay symmetric.
static func _ray_pixels(centre: Vector2i, direction: Vector2i, k: int, half_width: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var along := Vector2i(
		centre.x + direction.x * k - (1 if direction.x < 0 else 0),
		centre.y + direction.y * k - (1 if direction.y < 0 else 0))
	var side := Vector2i(1, 0) if direction.x == 0 else Vector2i(0, 1)
	for w in range(-half_width - 1, half_width + 1):
		var point := along + side * w
		if direction.x == 0:
			point.x = centre.x + w
		else:
			point.y = centre.y + w
		points.append(point)
	return points


static func _blank(width: int, height: int) -> Image:
	var result := Image.create(width, height, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	return result


static func _put(target: Image, point: Vector2i, color: Color) -> void:
	if point.x >= 0 and point.y >= 0 and point.x < target.get_width() and point.y < target.get_height():
		target.set_pixelv(point, color)
