class_name TrialArt
extends RefCounted
## Art of the trial rooms and the pact altar (docs/SPRITES_V5.md §1, §3, §4). Loads the delivered
## file by name and draws a pixel placeholder with the same size and frame layout until then.
## Placeholders are drawn once per name with fixed shapes (pure optics, no dungeon RNG).

const PENDULUM := "pendulum_blade_8f"
const FLAME_JET := "flame_jet_6f"
const PLATE := "trial_pressure_plate"
const PACT_ALTAR := "pact_altar_4f"
const CHEST_CLOSED := "chest_closed"
const CHEST_OPEN := "chest_open_4f"
const TORCH_STAND := "torch_stand_4f"
const TORCH_UNLIT := "torch_stand_unlit"
## Spike plates of the biomes (delivered with SPRITES_V2): retracted / warning / extended.
const SPIKES := "spike_trap_3f"

## Where the delivered files go (SPRITES_V5 section per group).
const PATHS := {
	PENDULUM: "res://art/environment/trials/pendulum_blade_8f.png",
	FLAME_JET: "res://art/environment/trials/flame_jet_6f.png",
	PLATE: "res://art/environment/trials/trial_pressure_plate.png",
	PACT_ALTAR: "res://art/environment/trials/pact_altar_4f.png",
	CHEST_CLOSED: "res://art/environment/rooms/chest_closed.png",
	CHEST_OPEN: "res://art/environment/rooms/chest_open_4f.png",
	TORCH_STAND: "res://art/environment/rooms/torch_stand_4f.png",
	TORCH_UNLIT: "res://art/environment/variants/torch_stand_unlit.png",
	SPIKES: "res://art/environment/props/spike_trap_3f.png",
}
## Frame size and count per name (art pixels).
const FRAME_SIZES := {
	PENDULUM: Vector2i(32, 64),
	FLAME_JET: Vector2i(32, 48),
	PLATE: Vector2i(32, 32),
	PACT_ALTAR: Vector2i(32, 48),
	CHEST_CLOSED: Vector2i(32, 32),
	CHEST_OPEN: Vector2i(32, 32),
	TORCH_STAND: Vector2i(16, 40),
	TORCH_UNLIT: Vector2i(16, 40),
	SPIKES: Vector2i(32, 32),
}
## Pivots of the delivered art (trials.json, rooms.json, variants.json); others: bottom centre.
## The pendulum hangs from (16, 2); the code places it by its bottom on the lane's south edge, so
## the chain reaches the lane's north edge.
const PIVOTS := {
	FLAME_JET: Vector2(16, 46),
	PACT_ALTAR: Vector2(16, 46),
	CHEST_CLOSED: Vector2(16, 30),
	CHEST_OPEN: Vector2(16, 30),
	TORCH_STAND: Vector2(8, 39),
	TORCH_UNLIT: Vector2(8, 39),
}
const FRAME_COUNTS := {
	PENDULUM: 8, FLAME_JET: 6, PLATE: 1, PACT_ALTAR: 4, CHEST_CLOSED: 1, CHEST_OPEN: 4,
	TORCH_STAND: 4, TORCH_UNLIT: 1, SPIKES: 3,
}

const OUTLINE := Color("#1c1a2b")
const STONE_LIGHT := Color("#9a94b5")
const STONE := Color("#7d7799")
const STONE_DARK := Color("#59547a")
const OBSIDIAN := Color("#2a2540")
const OBSIDIAN_LIGHT := Color("#3b3650")
const METAL := Color("#b8b6c8")
const METAL_DARK := Color("#6e6a85")
const WOOD_LIGHT := Color("#a8703f")
const WOOD := Color("#8a5a34")
const WOOD_DARK := Color("#5c3a24")
const GOLD := Color("#f2cf4a")
const GOLD_DARK := Color("#c99a2e")
const FLAME_CORE := Color("#fff1a8")
const FLAME_MID := Color("#f2cf4a")
const FLAME_OUTER := Color("#ff8a3c")
const FLAME_EDGE := Color("#e0463a")
const PACT := Color("#a66ef0")
const PACT_LIGHT := Color("#dcbcff")
const RUNE := Color("#6cb2ec")

static var _cache: Dictionary[String, Texture2D] = {}


## Delivered file or placeholder.
static func get_texture(art_name: String) -> Texture2D:
	if _cache.has(art_name):
		return _cache[art_name]
	var texture: Texture2D = null
	var path: String = PATHS.get(art_name, "")
	if not path.is_empty() and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null:
		texture = ImageTexture.create_from_image(_placeholder(art_name))
	_cache[art_name] = texture
	return texture


static func has_file(art_name: String) -> bool:
	var path: String = PATHS.get(art_name, "")
	return not path.is_empty() and ResourceLoader.exists(path)


static func get_frame_size(art_name: String) -> Vector2i:
	return FRAME_SIZES.get(art_name, Vector2i(32, 32))


static func get_frame_count(art_name: String) -> int:
	return FRAME_COUNTS.get(art_name, 1)


## Pivot of a frame: from the delivery notes, else the bottom centre (SPRITES_V5 style rule).
static func get_pivot(art_name: String) -> Vector2:
	if PIVOTS.has(art_name):
		return PIVOTS[art_name]
	var size := get_frame_size(art_name)
	return Vector2(size.x * 0.5, size.y - 1)


## Sprite2D showing one frame of a strip (hframes), scaled to the world, pivot at the bottom centre.
static func make_sprite(art_name: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = get_texture(art_name)
	sprite.hframes = get_frame_count(art_name)
	sprite.offset = SpriteStrip.pivot_offset(get_frame_size(art_name), get_pivot(art_name))
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	return sprite


static func _placeholder(art_name: String) -> Image:
	match art_name:
		PENDULUM:
			return _draw_pendulum()
		FLAME_JET:
			return _draw_flame_jet()
		PLATE:
			return _draw_plate()
		PACT_ALTAR:
			return _draw_pact_altar()
		CHEST_CLOSED:
			return _draw_chest_strip(1)
		CHEST_OPEN:
			return _draw_chest_strip(4)
		TORCH_STAND:
			return _draw_torch_stand(4)
		TORCH_UNLIT:
			return _draw_torch_stand(0)
		SPIKES:
			return _draw_spikes()
	return Image.create(16, 16, false, Image.FORMAT_RGBA8)


# --- Placeholders (pixel art, outline #1c1a2b, pivot bottom centre) ---

## Chain from the top centre, crescent blade at its end; frames 0 and 4 are the outer positions.
static func _draw_pendulum() -> Image:
	var image := _strip(PENDULUM)
	for frame in 8:
		var ox := frame * 32
		var swing := cos(TAU * frame / 8.0)
		var anchor := Vector2(ox + 16, 2)
		var blade := Vector2(ox + 16 + swing * 11.0, 46 - absf(swing) * 6.0)
		_rect(image, Rect2i(ox + 12, 0, 8, 3), STONE_DARK)
		var links := 9
		for i in links:
			var point := anchor.lerp(blade, float(i) / links)
			_disc(image, point, 1.4, METAL_DARK if i % 2 else METAL)
		# Crescent blade, edge pointing down.
		for y in range(-6, 9):
			for x in range(-10, 11):
				var p := Vector2(x, y)
				var outer := p.length() < 10.0 and y > -2
				var inner := (p - Vector2(0, -6)).length() < 9.0
				if outer and not inner:
					var color := METAL if y > 4 else METAL_DARK
					_px(image, Vector2i(blade + p.rotated(swing * 0.5)), color)
		_disc(image, blade, 2.0, STONE_DARK)
	_outline_all(image)
	return image


## Nozzle in the floor: idle, sparks (warning), three flame frames, dying puff.
static func _draw_flame_jet() -> Image:
	var image := _strip(FLAME_JET)
	for frame in 6:
		var ox := frame * 32
		_rect(image, Rect2i(ox + 8, 40, 16, 7), STONE_DARK)
		_rect(image, Rect2i(ox + 10, 41, 12, 4), OBSIDIAN)
		_rect(image, Rect2i(ox + 12, 42, 8, 2), FLAME_EDGE.darkened(0.4) if frame == 0 else FLAME_OUTER)
		if frame == 1:
			for spark in [Vector2i(13, 36), Vector2i(18, 33), Vector2i(15, 30), Vector2i(20, 37)]:
				_px(image, Vector2i(ox, 0) + spark, FLAME_MID)
		elif frame >= 2 and frame <= 4:
			var height := 34.0 + (frame - 2) * 3.0
			for step in int(height):
				var y := 41 - step
				var k := float(step) / height
				var half := 6.5 * (1.0 - k * 0.7) + (1.0 if (step + frame) % 4 == 0 else 0.0)
				for x in range(int(16 - half), int(16 + half) + 1):
					var d := absf(x - 16.0) / maxf(half, 0.5)
					var color := FLAME_EDGE if d > 0.8 else (FLAME_OUTER if d > 0.5 or k > 0.75 else (FLAME_MID if d > 0.2 or k > 0.45 else FLAME_CORE))
					_px(image, Vector2i(ox + x, y), color)
		elif frame == 5:
			_disc(image, Vector2(ox + 16, 30), 4.0, Color(0.45, 0.42, 0.5, 0.7))
			_disc(image, Vector2(ox + 14, 24), 3.0, Color(0.45, 0.42, 0.5, 0.5))
	_outline_all(image)
	return image


static func _draw_plate() -> Image:
	var image := _strip(PLATE)
	_rect(image, Rect2i(3, 6, 26, 22), STONE_DARK)
	_rect(image, Rect2i(4, 7, 24, 19), STONE)
	_rect(image, Rect2i(4, 7, 24, 2), STONE_LIGHT)
	# Rune: a ring with a cross.
	for angle in 24:
		var a := TAU * angle / 24.0
		_px(image, Vector2i(Vector2(16, 16) + Vector2(cos(a), sin(a)) * 6.0), RUNE)
	for i in range(-3, 4):
		_px(image, Vector2i(16 + i, 16), RUNE)
		_px(image, Vector2i(16, 16 + i), RUNE)
	_outline_all(image)
	return image


## Dark obsidian altar with a hovering violet flame.
static func _draw_pact_altar() -> Image:
	var image := _strip(PACT_ALTAR)
	for frame in 4:
		var ox := frame * 32
		_rect(image, Rect2i(ox + 5, 40, 22, 7), OBSIDIAN)
		_rect(image, Rect2i(ox + 8, 26, 16, 14), OBSIDIAN_LIGHT)
		_rect(image, Rect2i(ox + 6, 23, 20, 4), OBSIDIAN)
		_rect(image, Rect2i(ox + 6, 23, 20, 1), PACT.darkened(0.3))
		# Carved sigil.
		_px(image, Vector2i(ox + 16, 30), PACT)
		_px(image, Vector2i(ox + 15, 32), PACT)
		_px(image, Vector2i(ox + 17, 32), PACT)
		_px(image, Vector2i(ox + 16, 34), PACT)
		# Hovering flame, bobbing with the frame.
		var bob: int = [0, -1, -2, -1][frame]
		var center := Vector2(ox + 16, 14 + bob)
		for y in range(-8, 6):
			for x in range(-5, 6):
				var p := Vector2(x, y)
				var half := 4.5 * (1.0 - clampf((-float(y)) / 9.0, 0.0, 1.0)) if y < 0 else sqrt(maxf(0.0, 20.0 - y * y * 0.9))
				if absf(p.x) <= half:
					var color := PACT_LIGHT if absf(p.x) < half * 0.4 and y > -4 else PACT
					_px(image, Vector2i(center + p), color)
	_outline_all(image)
	return image


## Wooden chest with iron bands; frames > 0 open the lid with a golden glow.
static func _draw_chest_strip(frames: int) -> Image:
	var image := Image.create(32 * frames, 32, false, Image.FORMAT_RGBA8)
	for frame in frames:
		var ox := frame * 32
		var open_k := float(frame) / 3.0 if frames > 1 else 0.0
		_rect(image, Rect2i(ox + 5, 17, 22, 13), WOOD)
		_rect(image, Rect2i(ox + 5, 17, 22, 2), WOOD_LIGHT)
		_rect(image, Rect2i(ox + 5, 27, 22, 3), WOOD_DARK)
		_rect(image, Rect2i(ox + 9, 17, 2, 13), METAL_DARK)
		_rect(image, Rect2i(ox + 21, 17, 2, 13), METAL_DARK)
		if open_k <= 0.0:
			_rect(image, Rect2i(ox + 5, 10, 22, 8), WOOD_LIGHT)
			_rect(image, Rect2i(ox + 5, 10, 22, 2), WOOD_LIGHT.lightened(0.15))
			_rect(image, Rect2i(ox + 9, 10, 2, 8), METAL)
			_rect(image, Rect2i(ox + 21, 10, 2, 8), METAL)
			_rect(image, Rect2i(ox + 14, 16, 4, 4), GOLD)
		else:
			var lid_height := int(roundf(8.0 * (1.0 - open_k * 0.6)))
			_rect(image, Rect2i(ox + 5, 17 - lid_height - 3, 22, lid_height), WOOD_DARK)
			_rect(image, Rect2i(ox + 6, 15, 20, 3), GOLD_DARK)
			for i in int(3 + open_k * 6):
				_px(image, Vector2i(ox + 8 + (i * 5) % 17, 13 - (i * 3) % 7), GOLD if i % 2 else FLAME_CORE)
	_outline_all(image)
	return image


## Free-standing iron torch stand; flames (lit) or a cold, charred head (frames == 0).
static func _draw_torch_stand(frames: int) -> Image:
	var count := maxi(frames, 1)
	var image := Image.create(16 * count, 40, false, Image.FORMAT_RGBA8)
	for frame in count:
		var ox := frame * 16
		_rect(image, Rect2i(ox + 4, 37, 8, 2), METAL_DARK)
		_rect(image, Rect2i(ox + 7, 14, 2, 24), METAL_DARK)
		_rect(image, Rect2i(ox + 5, 12, 6, 3), METAL)
		if frames == 0:
			_rect(image, Rect2i(ox + 6, 9, 4, 3), Color("#2b2730"))
			continue
		var height: int = 8 + [0, 2, 1, 3][frame % 4]
		for step in height:
			var y := 11 - step
			var half := 3.0 * (1.0 - float(step) / height) + 0.5
			for x in range(int(8 - half), int(8 + half) + 1):
				var d := absf(x - 8.0) / maxf(half, 0.5)
				_px(image, Vector2i(ox + x, y), FLAME_OUTER if d > 0.5 else (FLAME_MID if step > 2 else FLAME_CORE))
	_outline_all(image)
	return image


static func _draw_spikes() -> Image:
	var image := _strip(SPIKES)
	for frame in 3:
		var ox := frame * 32
		_rect(image, Rect2i(ox + 3, 3, 26, 26), Color("#2e2a3a"))
		for gx in 3:
			for gy in 3:
				var center := Vector2i(ox + 8 + gx * 8, 8 + gy * 8)
				_px(image, center, Color("#121018"))
				var height: int = [0, 2, 6][frame]
				for h in height:
					_px(image, center + Vector2i(0, -h), METAL if h < height - 1 else Color.WHITE)
	return image


# --- Pixel helpers ---

static func _strip(art_name: String) -> Image:
	var size := get_frame_size(art_name)
	return Image.create(size.x * get_frame_count(art_name), size.y, false, Image.FORMAT_RGBA8)


static func _px(image: Image, pixel: Vector2i, color: Color) -> void:
	if pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height():
		image.set_pixelv(pixel, color)


static func _rect(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())), color)


static func _disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for x in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				_px(image, Vector2i(x, y), color)


## 1 px outline around all opaque pixels (frames never touch, so one pass over the strip is fine).
static func _outline_all(image: Image) -> void:
	var border: Array[Vector2i] = []
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				continue
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := Vector2i(x, y) + offset
				if n.x >= 0 and n.y >= 0 and n.x < image.get_width() and n.y < image.get_height() and image.get_pixelv(n).a > 0.5:
					border.append(Vector2i(x, y))
					break
	for pixel in border:
		image.set_pixelv(pixel, OUTLINE)
