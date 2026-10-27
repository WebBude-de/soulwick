class_name VillagePlaceholders
extends RefCounted
## Drawn stand-ins for the R7 village art that is still open (docs/design/sprites/SPRITES_V13.md §2) and for the
## new ground tiles: the ruin of the dungeon entrance (built from the old entrance, the chains and
## broken stone walls), the soul flame bowl (the brazier with a violet soul flame), two ravens, the
## chronicle's board and an atlas with plaza cobbles, the ridge (cliff face), stairs and stone slabs.
## VillageArt hands these out only while art/environment/village/<name>.png does not exist, so a
## delivered file of the same name replaces them without a code change. Fixed seeds: the village
## looks the same on every start.

const SEED := 7707
## Ground atlas (TILES_V2): 8 tiles of 32×32 in one row, see VillageTiles.V2_*.
const TILE := 32
const TILES_V2_COUNT := 8
## Ruin of the dungeon entrance: size and the pieces it is built from.
const RUIN_SIZE := Vector2i(96, 80)
const OLD_ENTRANCE := "res://art/environment/props/dungeon_entrance.png"
const CHAINS := "res://art/environment/props/chains.png"
const BRAZIER := "res://art/environment/props/brazier_4f.png"
## Flame bowl: 6 frames of 32×32 from the 4 brazier frames.
const BOWL_FRAMES: Array[int] = [0, 1, 2, 3, 2, 1]
## Ravens: 4 frames of 32×16 (0, 1 sitting, 2, 3 flying).
const RAVEN_FRAME := Vector2i(32, 16)
## Chronicle board (empty slate on an easel).
const BOARD_SIZE := Vector2i(24, 30)
const BOARD_SLATE := Rect2i(3, 3, 18, 14)
## Most tally marks the board shows (three groups of five).
const BOARD_MAX_TALLY := 15

const MORTAR := Color("#3b3654")
const STONE_LIGHT := Color("#b5b0cc")
const MOSS := Color("#4f8a3a")
const RAVEN := Color("#262233")
const RAVEN_LIGHT := Color("#4a4566")
const RAVEN_EYE := Color("#e9e4d2")
const SLATE := Color("#2b2d3a")
const SLATE_LIGHT := Color("#3a3d4e")
const CHALK := Color("#e9e4d2")
## Cobbles of the village square: light, mid and dark grey with a touch of warmth.
const COBBLE: Array[Color] = [Color("#b8b2bf"), Color("#9c95a6"), Color("#7f7889")]
## Rock of the ridge: light, mid, dark, crevice.
const ROCK: Array[Color] = [Color("#9a8f8a"), Color("#7d7470"), Color("#5f5654"), Color("#3a3236")]
## Soul flame colours, darkest to brightest (the brazier's fire recoloured).
const SOUL: Array[Color] = [Color("#4a2a8a"), Color("#6a4fc4"), Color("#9a6cf0"), Color("#c9a8ff"), Color("#f0e6ff")]


## Ground atlas: cobble A/B, cliff A/B, stairs left/right, slabs A/B (VillageTiles.V2_*).
static func tiles_v2() -> Texture2D:
	var image := Image.create(TILE * TILES_V2_COUNT, TILE, false, Image.FORMAT_RGBA8)
	var grass := grass_color()
	for i in 2:
		_cobble(image, Vector2i(TILE * i, 0), _rng(10 + i))
		_cliff(image, Vector2i(TILE * (2 + i), 0), _rng(20 + i), grass)
		_stairs(image, Vector2i(TILE * (4 + i), 0), i == 0, _rng(30 + i))
		_slabs(image, Vector2i(TILE * (6 + i), 0), _rng(40 + i), grass)
	return ImageTexture.create_from_image(image)


## The most common colour of the plain grass tile in the village tileset (so drawn tiles that show
## grass match the painted ground).
static func grass_color() -> Color:
	var image := _image_of(VillageArt.TILESET)
	if image == null:
		return VillageArt.GRASS_LIGHT
	var counts := {}
	for y in TILE:
		for x in TILE:
			var color := image.get_pixel(x, y)
			counts[color] = int(counts.get(color, 0)) + 1
	var best := VillageArt.GRASS_LIGHT
	var most := 0
	for color: Color in counts:
		if counts[color] > most:
			most = counts[color]
			best = color
	return best


## 96×80 ruin: broken stone walls left and right, a broken lintel, the old entrance arch with its
## stairs and torches in front, chains on the arch, moss and rubble.
static func entrance_ruin() -> Texture2D:
	var rng := _rng(50)
	var image := Image.create(RUIN_SIZE.x, RUIN_SIZE.y, false, Image.FORMAT_RGBA8)
	_broken_wall(image, Rect2i(2, 30, 22, 50), rng, 9)
	_broken_wall(image, Rect2i(72, 22, 22, 58), rng, 12)
	_broken_wall(image, Rect2i(26, 14, 44, 16), rng, 5)
	var old := _image_of(OLD_ENTRANCE)
	if old != null:
		image.blend_rect(old, Rect2i(Vector2i.ZERO, old.get_size()), Vector2i(16, 16))
	var chains := _image_of(CHAINS)
	if chains != null:
		# One chain on each side of the arch opening, hanging from the lintel.
		image.blend_rect(chains, Rect2i(0, 0, 12, 26), Vector2i(31, 30))
		image.blend_rect(chains, Rect2i(18, 0, 14, 26), Vector2i(53, 30))
	# Soul rune on the keystone.
	for spot: Vector2i in [Vector2i(47, 20), Vector2i(48, 20), Vector2i(47, 21), Vector2i(48, 21)]:
		image.set_pixelv(spot, SOUL[3])
	image.set_pixel(47, 19, SOUL[1])
	image.set_pixel(48, 22, SOUL[1])
	# Rubble at the foot of the walls.
	for spot: Vector2i in [Vector2i(4, 76), Vector2i(12, 77), Vector2i(20, 76), Vector2i(78, 76), Vector2i(86, 77), Vector2i(92, 75)]:
		_stone(image, Rect2i(spot.x, spot.y, rng.randi_range(3, 5), 3))
	VillageArt.add_outline(image)
	return ImageTexture.create_from_image(image)


## 6 frames of 32×32: the brazier bowl with its fire recoloured into a violet soul flame.
static func flame_bowl() -> Texture2D:
	var source := _image_of(BRAZIER)
	var image := Image.create(TILE * BOWL_FRAMES.size(), TILE, false, Image.FORMAT_RGBA8)
	if source == null:
		return ImageTexture.create_from_image(image)
	for frame in BOWL_FRAMES.size():
		var from := BOWL_FRAMES[frame] % maxi(1, int(source.get_width() / float(TILE)))
		for y in TILE:
			for x in TILE:
				var color := source.get_pixel(from * TILE + x, y)
				if color.a > 0.0 and _is_fire(color):
					color = _soul_tone(color)
				image.set_pixel(frame * TILE + x, y, color)
	return ImageTexture.create_from_image(image)


## 4 frames of 32×16: two ravens sitting (the second frame: one pecks), then flying (wings up, down).
static func ravens() -> Texture2D:
	var image := Image.create(RAVEN_FRAME.x * 4, RAVEN_FRAME.y, false, Image.FORMAT_RGBA8)
	var sitting := ["...##...", "..####>.", "..###...", ".#####..", "######..", "#.####..", "...#.#.."]
	var pecking := [".........", "..##.....", ".#####...", "#######..", "######>..", "#.####...", "...#.#..."]
	var wings_up := ["#.......#", "##.....##", ".##.#.##.", "..#####>.", "...###...", "....#...."]
	var wings_down := [".........", "....#....", "..######>", ".##.###.#", "##.......", "........."]
	_draw_map(image, Vector2i(5, 8), sitting)
	_draw_map(image, Vector2i(18, 7), sitting, true)
	_draw_map(image, Vector2i(RAVEN_FRAME.x + 5, 8), pecking)
	_draw_map(image, Vector2i(RAVEN_FRAME.x + 18, 7), sitting, true)
	_draw_map(image, Vector2i(RAVEN_FRAME.x * 2 + 3, 4), wings_up)
	_draw_map(image, Vector2i(RAVEN_FRAME.x * 2 + 18, 7), wings_down, true)
	_draw_map(image, Vector2i(RAVEN_FRAME.x * 3 + 3, 6), wings_down)
	_draw_map(image, Vector2i(RAVEN_FRAME.x * 3 + 18, 4), wings_up, true)
	return ImageTexture.create_from_image(image)


## Chalk tally marks for the chronicle board (same size as the board, transparent elsewhere).
static func tally_overlay(count: int) -> Texture2D:
	var image := Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
	_tally(image, mini(count, BOARD_MAX_TALLY))
	return ImageTexture.create_from_image(image)


## Board of the chronicle on an easel: empty slate (first run) or chalk tally marks, one per run.
static func chronicle_board(tally := 0) -> Texture2D:
	var image := Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
	# Easel legs.
	for y in range(10, BOARD_SIZE.y):
		var spread := int((y - 10) / 4.0)
		image.set_pixel(6 - spread, y, VillageArt.WOOD_DARK)
		image.set_pixel(17 + spread, y, VillageArt.WOOD_DARK)
	for y in range(1, 26):
		image.set_pixel(11, y, VillageArt.WOOD_MID)
	# Frame and slate.
	var frame := BOARD_SLATE.grow(1)
	for y in range(frame.position.y, frame.end.y):
		for x in range(frame.position.x, frame.end.x):
			image.set_pixel(x, y, VillageArt.WOOD if y == frame.position.y else VillageArt.WOOD_MID)
	for y in range(BOARD_SLATE.position.y, BOARD_SLATE.end.y):
		for x in range(BOARD_SLATE.position.x, BOARD_SLATE.end.x):
			image.set_pixel(x, y, SLATE_LIGHT if y == BOARD_SLATE.position.y else SLATE)
	_tally(image, mini(tally, BOARD_MAX_TALLY))
	VillageArt.add_outline(image)
	return ImageTexture.create_from_image(image)


# --- Window glow ---

## Glass pixels of a building sprite as a warm "lit window" image of the same size, plus the art-px
## centres of the window panes: {"texture": Texture2D or null, "centres": Array[Vector2]}.
static func window_glow(texture: Texture2D) -> Dictionary:
	var result := {"texture": null, "centres": [] as Array[Vector2]}
	if texture == null:
		return result
	var image := texture.get_image()
	if image == null:
		return result
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var size := image.get_size()
	var glow := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var glass := {}
	for y in size.y:
		for x in size.x:
			var color := image.get_pixel(x, y)
			if is_glass(color):
				glass[Vector2i(x, y)] = true
				glow.set_pixel(x, y, Color("#fff0b8") if color.get_luminance() > 0.8 else Color("#ffc65a"))
	if glass.is_empty():
		return result
	var centres: Array[Vector2] = []
	var seen := {}
	for start: Vector2i in glass:
		if seen.has(start):
			continue
		var open: Array[Vector2i] = [start]
		var box := Rect2i(start, Vector2i.ONE)
		var count := 0
		seen[start] = true
		while not open.is_empty():
			var cell: Vector2i = open.pop_back()
			count += 1
			box = box.expand(cell).expand(cell + Vector2i.ONE)
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := cell + step
				if glass.has(next) and not seen.has(next):
					seen[next] = true
					open.append(next)
		if count >= 3:
			centres.append(Vector2(box.get_center()))
	result["texture"] = ImageTexture.create_from_image(glow)
	result["centres"] = centres
	return result


## Window glass in the village_v2 buildings: light, clearly blue (roofs are darker, walls warmer).
static func is_glass(color: Color) -> bool:
	return color.a > 0.5 and color.b > color.r + 0.12 and color.b >= color.g and color.get_luminance() > 0.55


# --- Drawing helpers ---

static func _rng(offset: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + offset
	return rng


static func _image_of(path: String) -> Image:
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


static func _fill(image: Image, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			image.set_pixel(x, y, color)


## One stone: mid fill, light top row, dark bottom row, mortar-coloured cut corners.
static func _stone(image: Image, rect: Rect2i, base := VillageArt.STONE_MID) -> void:
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not bounds.has_point(Vector2i(x, y)):
				continue
			var corner := (x == rect.position.x or x == rect.end.x - 1) and (y == rect.position.y or y == rect.end.y - 1)
			if corner and rect.size.x > 2 and rect.size.y > 2:
				continue
			var color := base
			if y == rect.position.y:
				color = VillageArt.STONE if base == VillageArt.STONE_MID else STONE_LIGHT
			elif y == rect.end.y - 1:
				color = VillageArt.STONE_DARK
			image.set_pixel(x, y, color)


## Rows of stones over rect with a mortar background (rows of the given heights, random widths).
static func _stone_rows(image: Image, rect: Rect2i, rng: RandomNumberGenerator, heights: Array[int], width_min: int, width_max: int, base := VillageArt.STONE_MID) -> void:
	_fill(image, rect, MORTAR)
	var y := rect.position.y
	for height in heights:
		var x := rect.position.x - rng.randi_range(0, width_min)
		while x < rect.end.x:
			var width := rng.randi_range(width_min, width_max)
			_stone(image, Rect2i(x + 1, y + 1, width - 1, height - 1).intersection(rect), base)
			x += width
		y += height
		if y >= rect.end.y:
			break


## Round cobbles set in earth (the joints have the colour of the village paths).
static func _cobble(image: Image, origin: Vector2i, rng: RandomNumberGenerator) -> void:
	var joint := path_color().darkened(0.3)
	_fill(image, Rect2i(origin, Vector2i(TILE, TILE)), joint)
	var y := 0
	var row := 0
	while y < TILE:
		var height := 5 if row % 2 == 0 else 6
		var x := -(row % 2) * 3
		while x < TILE:
			var width := rng.randi_range(4, 7)
			var tone := rng.randf()
			var base: Color = COBBLE[1] if tone < 0.6 else (COBBLE[2] if tone < 0.85 else COBBLE[0])
			_cobble_stone(image, Rect2i(origin.x + x + 1, origin.y + y + 1, width - 1, height - 1), base, origin)
			x += width
		y += height
		row += 1


## One cobble; wraps around the tile's left/right edge so the tiles join without a seam.
static func _cobble_stone(image: Image, rect: Rect2i, base: Color, tile_origin: Vector2i) -> void:
	var tile := Rect2i(tile_origin, Vector2i(TILE, TILE))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var corner := (x == rect.position.x or x == rect.end.x - 1) and (y == rect.position.y or y == rect.end.y - 1)
			if corner:
				continue
			var color := base
			if y == rect.position.y or x == rect.position.x:
				color = base.lightened(0.18)
			elif y == rect.end.y - 1:
				color = base.darkened(0.22)
			var point := Vector2i(posmod(x - tile.position.x, TILE) + tile.position.x, y)
			if point.y < tile.end.y and point.y >= tile.position.y:
				image.set_pixelv(point, color)


## The most common colour of the plain path tile in the village tileset.
static func path_color() -> Color:
	var image := _image_of(VillageArt.TILESET)
	if image == null:
		return VillageArt.SOIL_LIGHT
	var counts := {}
	for y in TILE:
		for x in range(4 * TILE, 5 * TILE):
			var color := image.get_pixel(x, y)
			counts[color] = int(counts.get(color, 0)) + 1
	var best := VillageArt.SOIL_LIGHT
	var most := 0
	for color: Color in counts:
		if counts[color] > most:
			most = counts[color]
			best = color
	return best


static func _cliff(image: Image, origin: Vector2i, rng: RandomNumberGenerator, grass: Color) -> void:
	_fill(image, Rect2i(origin, Vector2i(TILE, TILE)), grass)
	# Rock face: big irregular boulders with dark crevices, lighter at the top (catching the light).
	_fill(image, Rect2i(origin + Vector2i(0, 5), Vector2i(TILE, 23)), ROCK[3])
	var top := 5
	while top < 28:
		var height := mini(rng.randi_range(6, 9), 28 - top)
		var left := -rng.randi_range(0, 6)
		while left < TILE:
			var width := rng.randi_range(7, 13)
			var shade := ROCK[0] if top < 11 else (ROCK[1] if top < 20 else ROCK[2])
			_boulder(image, Rect2i(origin.x + left + 1, origin.y + top + 1, width - 1, height - 1), shade, origin)
			left += width
		top += height
	# Grass lip hanging over the edge, dark rock foot and shadow on the grass below.
	for x in TILE:
		var lip := 4 + rng.randi_range(0, 2)
		for y in range(0, lip):
			image.set_pixel(origin.x + x, origin.y + y, grass if y < lip - 1 else MOSS)
		image.set_pixel(origin.x + x, origin.y + lip, VillageArt.OUTLINE)
		image.set_pixel(origin.x + x, origin.y + 28, MORTAR)
		image.set_pixel(origin.x + x, origin.y + 29, VillageArt.OUTLINE)
		image.set_pixel(origin.x + x, origin.y + 30, grass.darkened(0.35))
		image.set_pixel(origin.x + x, origin.y + 31, grass.darkened(0.18))
	for i in 4:
		image.set_pixel(origin.x + rng.randi_range(0, 31), origin.y + rng.randi_range(6, 12), MOSS)


static func _stairs(image: Image, origin: Vector2i, left: bool, rng: RandomNumberGenerator) -> void:
	_fill(image, Rect2i(origin, Vector2i(TILE, TILE)), MORTAR)
	for step in 4:
		var top := origin.y + step * 8
		for x in TILE:
			for row in 8:
				var color := VillageArt.STONE_MID
				if row < 2:
					color = STONE_LIGHT if row == 0 else VillageArt.STONE
				elif row >= 6:
					color = VillageArt.STONE_DARK if row == 6 else VillageArt.OUTLINE
				image.set_pixel(origin.x + x, top + row, color)
		# Worn spots on the treads.
		image.set_pixel(origin.x + rng.randi_range(6, 26), top + 1, VillageArt.STONE_MID)
	# Side wall (cheek) on the outer side of the flight.
	var cheek := Rect2i(origin + Vector2i(0 if left else TILE - 5, 0), Vector2i(5, TILE))
	var heights: Array[int] = [8, 8, 8, 8]
	_stone_rows(image, cheek, rng, heights, 4, 6)
	for y in TILE:
		image.set_pixel(cheek.end.x - 1 if left else cheek.position.x, origin.y + y, VillageArt.OUTLINE)


static func _slabs(image: Image, origin: Vector2i, rng: RandomNumberGenerator, grass: Color) -> void:
	_fill(image, Rect2i(origin, Vector2i(TILE, TILE)), grass)
	var plates: Array[Rect2i] = [Rect2i(1, 1, 14, 13), Rect2i(17, 2, 14, 12), Rect2i(2, 16, 13, 14), Rect2i(17, 17, 13, 13)]
	for plate in plates:
		var jitter := Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		var rect := Rect2i(origin + plate.position + jitter, plate.size)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var corner := (x == rect.position.x or x == rect.end.x - 1) and (y == rect.position.y or y == rect.end.y - 1)
				if corner:
					continue
				var edge := x == rect.position.x or x == rect.end.x - 1 or y == rect.position.y or y == rect.end.y - 1
				var color := VillageArt.OUTLINE if edge else VillageArt.STONE
				if not edge and (y == rect.end.y - 2 or x == rect.end.x - 2):
					color = VillageArt.STONE_MID
				elif not edge and y == rect.position.y + 1:
					color = STONE_LIGHT
				image.set_pixel(x, y, color)
		# A crack in some plates.
		if rng.randf() < 0.5:
			var cx := rect.position.x + rng.randi_range(4, rect.size.x - 5)
			for y in range(rect.position.y + 3, rect.position.y + 7):
				image.set_pixel(cx + (y % 2), y, VillageArt.STONE_DARK)


## One boulder of the ridge, clipped to its tile: rounded corners, light top-left edge, dark bottom.
static func _boulder(image: Image, rect: Rect2i, base: Color, tile_origin: Vector2i) -> void:
	var tile := Rect2i(tile_origin, Vector2i(TILE, TILE))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not tile.has_point(Vector2i(x, y)):
				continue
			var corner := (x == rect.position.x or x == rect.end.x - 1) and (y == rect.position.y or y == rect.end.y - 1)
			if corner:
				continue
			var color := base
			if y == rect.position.y:
				color = base.lightened(0.15)
			elif y >= rect.end.y - 2:
				color = base.darkened(0.2)
			image.set_pixel(x, y, color)


## Masonry with a broken (stepped) top edge and moss on it.
static func _broken_wall(image: Image, rect: Rect2i, rng: RandomNumberGenerator, roughness: int) -> void:
	var tops: Array[int] = []
	var x := 0
	while x < rect.size.x:
		var top := rect.position.y + rng.randi_range(0, roughness)
		var run := rng.randi_range(3, 6)
		for i in run:
			tops.append(top)
		x += run
	var wall := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	var heights: Array[int] = []
	for i in int(rect.size.y / 6.0) + 1:
		heights.append(6)
	_stone_rows(wall, rect, rng, heights, 6, 10)
	for column in rect.size.x:
		var px := rect.position.x + column
		for y in range(rect.position.y, rect.end.y):
			if y < tops[column]:
				wall.set_pixel(px, y, Color(0, 0, 0, 0))
		var top_y := tops[column]
		if top_y < rect.end.y and rng.randf() < 0.6:
			wall.set_pixel(px, top_y, MOSS)
	image.blend_rect(wall, rect, rect.position)


static func _draw_map(image: Image, origin: Vector2i, rows: Array, mirrored := false) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var tx := origin.x + (row.length() - 1 - x if mirrored else x)
			var cell := row[x]
			if cell == "#":
				image.set_pixel(tx, origin.y + y, RAVEN if y > 1 else RAVEN_LIGHT)
			elif cell == ">":
				image.set_pixel(tx, origin.y + y, VillageArt.STONE_DARK)
	# Eye: the second-highest row's last body pixel facing the beak.
	for y in rows.size():
		var row: String = rows[y]
		var beak := row.find(">")
		if beak > 0:
			var eye_x := beak - 1
			var tx := origin.x + (row.length() - 1 - eye_x if mirrored else eye_x)
			image.set_pixel(tx, origin.y + y - 1, RAVEN_EYE)
			break


static func _tally(image: Image, count: int) -> void:
	var x := BOARD_SLATE.position.x + 2
	var top := BOARD_SLATE.position.y + 3
	for i in count:
		var in_group := i % 5
		if in_group == 4:
			# The fifth mark crosses the four before it.
			for step in 8:
				image.set_pixel(x - 8 + step, top + 6 - int(step * 6 / 8.0), CHALK)
			x += 2
			continue
		for y in range(top, top + 7):
			image.set_pixel(x, y, CHALK)
		x += 2
		if x >= BOARD_SLATE.end.x - 1:
			break


static func _is_fire(color: Color) -> bool:
	return color.s > 0.45 and color.v > 0.45 and (color.h < 0.17 or color.h > 0.95)


static func _soul_tone(color: Color) -> Color:
	var value := color.v
	if value > 0.95 and color.s < 0.6:
		return SOUL[4]
	if value > 0.9:
		return SOUL[3]
	if value > 0.75:
		return SOUL[2]
	if value > 0.6:
		return SOUL[1]
	return SOUL[0]
