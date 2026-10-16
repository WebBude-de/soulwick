class_name TurretArt
extends RefCounted
## Look of the turrets (D-151) until real art exists. Real art follows the EnemyArt naming convention
## (art/characters/enemies/<id>/<id>_<anim>_<n>f.png with idle, walk = idle, attack, death) and wins
## automatically; until then this draws a small tower per biome palette in code: plinth, column and
## a head whose eye charges up (attack) and crumbles away (death).
## The shot uses art/projectiles/<id>_shot_4f.png (16 x 16 frames) when present, else the magic orb.

const FRAME := Vector2i(32, 32)
const SHOT_ART_PATH := "res://art/projectiles/%s_shot_4f.png"
const SHOT_FALLBACK: Texture2D = preload("res://art/projectiles/magic_orb_4f.png")
const SHOT_FRAME := Vector2i(16, 16)
const SHOT_PIVOT := Vector2(8, 8)
## Frame of the attack strip on which the shot leaves (the brightest eye).
const STRIKE_FRAME := 4
const IDLE_FPS := 3.0
const ATTACK_FPS := 8.0
const DEATH_FPS := 8.0

## Palette per turret id: body, dark (outline, shade), light (rim), eye (charge colour).
const PALETTES := {
	&"bone_turret": [Color("#d9cfb4"), Color("#3b3430"), Color("#f4ecd8"), Color("#8fd8ff")],
	&"slime_spitter": [Color("#5aa84a"), Color("#1f3d1c"), Color("#9fe07a"), Color("#c8ffd9")],
	&"shadow_eye": [Color("#4a3868"), Color("#160f22"), Color("#7c62a8"), Color("#a9a2ff")],
	&"ember_cauldron": [Color("#4a4242"), Color("#161212"), Color("#7a6a64"), Color("#ffa040")],
}

static var _frames_cache: Dictionary[StringName, SpriteFrames] = {}


## Placeholder animations for a turret type (cached per id): idle, walk (= idle), attack, death.
static func placeholder_frames(data: EnemyData) -> SpriteFrames:
	var id: StringName = data.id if data != null else &""
	if _frames_cache.has(id):
		return _frames_cache[id]
	var palette := get_palette(data)
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var idle := _strip([_draw_tower(palette, 0.25, 1.0, 0), _draw_tower(palette, 0.4, 1.0, 0)])
	SpriteStrip.add_strip(frames, &"idle", idle, FRAME, IDLE_FPS, true)
	SpriteStrip.add_strip(frames, &"walk", idle, FRAME, IDLE_FPS, true)
	var attack: Array[Image] = []
	for i in 5:
		attack.append(_draw_tower(palette, 0.45 + 0.18 * i, 1.0, 0))
	SpriteStrip.add_strip(frames, &"attack", _strip(attack), FRAME, ATTACK_FPS, false)
	var death: Array[Image] = []
	for i in 4:
		death.append(_draw_tower(palette, 0.0, 1.0 - 0.22 * i, i * 3))
	SpriteStrip.add_strip(frames, &"death", _strip(death), FRAME, DEATH_FPS, false)
	_frames_cache[id] = frames
	return frames


## [body, dark, light, eye] of the type; unknown ids get one from placeholder_color.
static func get_palette(data: EnemyData) -> Array:
	if data != null and PALETTES.has(data.id):
		return PALETTES[data.id]
	var base := data.placeholder_color if data != null else Color(0.7, 0.7, 0.75)
	return [base, base.darkened(0.7), base.lightened(0.35), Color(0.6, 0.85, 1.0)]


## Colour of the charge glow, the shot and its impact.
static func get_eye_color(data: EnemyData) -> Color:
	return get_palette(data)[3]


## Shot texture: own art by name, else the magic orb.
static func get_shot_texture(data: EnemyData) -> Texture2D:
	if data != null and data.projectile_texture != null:
		return data.projectile_texture
	if data != null:
		var path := SHOT_ART_PATH % String(data.id)
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return SHOT_FALLBACK


static func _strip(images: Array[Image]) -> ImageTexture:
	var strip := Image.create(FRAME.x * images.size(), FRAME.y, false, Image.FORMAT_RGBA8)
	for i in images.size():
		strip.blit_rect(images[i], Rect2i(Vector2i.ZERO, FRAME), Vector2i(FRAME.x * i, 0))
	return ImageTexture.create_from_image(strip)


## One 32 x 32 frame: feet at y 30, body centre at (16, 22) like every placeholder enemy.
## glow 0..1 = eye size and brightness, alpha fades the whole tower, sink lowers it (crumbling).
static func _draw_tower(palette: Array, glow: float, alpha: float, sink: int) -> Image:
	var image := Image.create(FRAME.x, FRAME.y, false, Image.FORMAT_RGBA8)
	var body: Color = palette[0]
	var dark: Color = palette[1]
	var light: Color = palette[2]
	var eye: Color = palette[3]
	var top := 6 + sink
	# Plinth, column, head: outline first, then the fill one pixel smaller.
	_rect(image, Rect2i(7, 24, 18, 7), dark, alpha)
	_rect(image, Rect2i(8, 25, 16, 5), body.darkened(0.25), alpha)
	_rect(image, Rect2i(8, 25, 16, 1), light, alpha)
	if top < 22:
		_rect(image, Rect2i(10, top + 5, 12, 25 - top - 5), dark, alpha)
		_rect(image, Rect2i(11, top + 6, 10, 25 - top - 6), body, alpha)
		_rect(image, Rect2i(11, top + 6, 2, 25 - top - 6), light, alpha)
		_rect(image, Rect2i(19, top + 6, 2, 25 - top - 6), body.darkened(0.3), alpha)
		_rect(image, Rect2i(8, top, 16, 7), dark, alpha)
		_rect(image, Rect2i(9, top + 1, 14, 5), body, alpha)
		_rect(image, Rect2i(9, top + 1, 14, 1), light, alpha)
		# The eye: a dark socket, the charge glow growing in it.
		_disc(image, Vector2(16, top + 3.5), 2.6, dark, alpha)
		if glow > 0.0:
			_disc(image, Vector2(16, top + 3.5), 0.8 + 1.8 * clampf(glow, 0.0, 1.0), eye.lightened(0.5 * maxf(0.0, glow - 0.6)), alpha)
			if glow > 0.95:
				_disc(image, Vector2(16, top + 3.5), 1.0, Color.WHITE, alpha)
	if sink > 0:
		# Rubble at the foot while it crumbles.
		for i in sink:
			_rect(image, Rect2i(6 + (i * 7) % 20, 27 + i % 3, 2, 2), body.darkened(0.1 * i), alpha)
	return image


static func _rect(image: Image, rect: Rect2i, color: Color, alpha: float) -> void:
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, FRAME))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	image.fill_rect(clipped, Color(color, color.a * alpha))


static func _disc(image: Image, center: Vector2, radius: float, color: Color, alpha: float) -> void:
	for y in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for x in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			if x < 0 or y < 0 or x >= FRAME.x or y >= FRAME.y:
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				image.set_pixel(x, y, Color(color, color.a * alpha))
