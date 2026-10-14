class_name VariantArt
extends RefCounted
## Art of the combat variants and the wager altar (docs/SPRITES_V5.md §3, delivered in
## art/environment/variants/, variants.json). Loads the file by name and draws a simple pixel
## placeholder with the same frame layout if it is missing. Placeholders use fixed shapes (pure
## optics, no dungeon RNG).

const DIR := "res://art/environment/variants/"
const SOUL_FLAME := "soul_flame_6f"
const SOUL_FLAME_DYING := "soul_flame_dying_6f"
const RIFT := "summoning_rift_6f"
const RIFT_BREAK := "summoning_rift_break_6f"
const BOUNTY_CROWN := "bounty_crown"
const ESCAPE_HOLE := "escape_hole_4f"
const BONE_HEAP_RISE := "bone_heap_rise_6f"
const WAGER_ALTAR := "wager_altar_4f"
const WAGER_ICONS := "wager_icons"

## name: [frame size, frames, fps, pivot] (variants.json).
const SPECS := {
	SOUL_FLAME: [Vector2i(32, 48), 6, 8.0, Vector2(16, 40)],
	SOUL_FLAME_DYING: [Vector2i(32, 48), 6, 6.0, Vector2(16, 40)],
	RIFT: [Vector2i(32, 48), 6, 8.0, Vector2(16, 46)],
	RIFT_BREAK: [Vector2i(32, 48), 6, 10.0, Vector2(16, 46)],
	BOUNTY_CROWN: [Vector2i(16, 16), 1, 0.0, Vector2(8, 12)],
	ESCAPE_HOLE: [Vector2i(32, 32), 4, 8.0, Vector2(16, 20)],
	BONE_HEAP_RISE: [Vector2i(32, 32), 6, 6.0, Vector2(16, 30)],
	WAGER_ALTAR: [Vector2i(32, 48), 4, 4.0, Vector2(16, 46)],
	WAGER_ICONS: [Vector2i(16, 16), 6, 0.0, Vector2(8, 8)],
}
const OUTLINE := Color("#1c1a2b")
const SOUL := Color("#a66ef0")
const SOUL_LIGHT := Color("#dcbcff")
const GOLD := Color("#f2cf4a")
const RIFT_COLOR := Color("#7ff0c8")
const BONE := Color("#d8d0b8")
const STONE := Color("#7d7799")
const HOLE := Color("#100c1a")

static var _cache: Dictionary[String, Texture2D] = {}


static func get_path(art_name: String) -> String:
	return DIR + art_name + ".png"


static func has_file(art_name: String) -> bool:
	return ResourceLoader.exists(get_path(art_name))


## Delivered file or placeholder (cached per name).
static func get_texture(art_name: String) -> Texture2D:
	if _cache.has(art_name):
		return _cache[art_name]
	var texture: Texture2D = null
	if has_file(art_name):
		texture = load(get_path(art_name)) as Texture2D
	if texture == null:
		texture = ImageTexture.create_from_image(_placeholder(art_name))
	_cache[art_name] = texture
	return texture


static func get_frame_size(art_name: String) -> Vector2i:
	return (SPECS[art_name] as Array)[0] if SPECS.has(art_name) else Vector2i(32, 32)


static func get_frame_count(art_name: String) -> int:
	return (SPECS[art_name] as Array)[1] if SPECS.has(art_name) else 1


static func get_fps(art_name: String) -> float:
	return (SPECS[art_name] as Array)[2] if SPECS.has(art_name) else 0.0


static func get_pivot(art_name: String) -> Vector2:
	return (SPECS[art_name] as Array)[3] if SPECS.has(art_name) else Vector2(16, 31)


## Adds a strip as one animation (fps from the delivery notes unless given).
static func add_animation(frames: SpriteFrames, animation: StringName, art_name: String, loop: bool, fps := -1.0) -> void:
	SpriteStrip.add_strip(frames, animation, get_texture(art_name), get_frame_size(art_name), get_fps(art_name) if fps < 0.0 else fps, loop)


## Animated sprite of one strip, world scale, pivot on the node origin plus lift (art px * 2).
static func make_animated(art_name: String, loop: bool, animation: StringName = &"default") -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	if animation != &"default":
		frames.remove_animation(&"default")
	add_animation(frames, animation, art_name, loop)
	sprite.sprite_frames = frames
	sprite.animation = animation
	sprite.offset = SpriteStrip.pivot_offset(get_frame_size(art_name), get_pivot(art_name))
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	return sprite


## Sprite of a single frame (crown, icons), world scale, pivot on the node origin.
static func make_sprite(art_name: String, frame := 0) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = get_texture(art_name)
	sprite.hframes = maxi(1, get_frame_count(art_name)) if art_name == WAGER_ICONS else 1
	sprite.frame = frame if art_name == WAGER_ICONS else 0
	sprite.offset = SpriteStrip.pivot_offset(get_frame_size(art_name), get_pivot(art_name))
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	return sprite


## One wager symbol (WagerRules.icon_index) as its own texture (banner, cards).
static func get_wager_icon(index: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = get_texture(WAGER_ICONS)
	atlas.region = Rect2(clampi(index, 0, 5) * 16, 0, 16, 16)
	return atlas


## Frames of the bone heap for EnemyData.sprite_frames: "idle" = the heap (first frame), "rise" =
## the whole strip (the skeleton grows back together).
static func make_bone_heap_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var texture := get_texture(BONE_HEAP_RISE)
	var size := get_frame_size(BONE_HEAP_RISE)
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", 1.0)
	frames.set_animation_loop(&"idle", true)
	var first := AtlasTexture.new()
	first.atlas = texture
	first.region = Rect2(Vector2.ZERO, size)
	frames.add_frame(&"idle", first)
	add_animation(frames, &"rise", BONE_HEAP_RISE, false, float(get_frame_count(BONE_HEAP_RISE)) / VariantRules.RISE_ANIMATION_TIME)
	return frames


## Frames of a summoning rift: "idle" pulses, "death" closes it (Enemy plays "death" on dying).
static func make_rift_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	add_animation(frames, &"idle", RIFT, true)
	add_animation(frames, &"death", RIFT_BREAK, false)
	return frames


# --- Placeholders ---

static func _placeholder(art_name: String) -> Image:
	var size := get_frame_size(art_name)
	var count := get_frame_count(art_name)
	var image := Image.create(size.x * count, size.y, false, Image.FORMAT_RGBA8)
	for frame in count:
		var origin := Vector2(frame * size.x, 0)
		var t := float(frame) / maxf(1.0, count - 1.0)
		match art_name:
			SOUL_FLAME, SOUL_FLAME_DYING:
				var shrink := t if art_name == SOUL_FLAME_DYING else 0.1 * sin(TAU * t)
				_box(image, origin, Vector2(12, 38), Vector2(8, 8), STONE)
				_ellipse(image, origin + Vector2(16, 26), Vector2(8, 14) * (1.0 - shrink), SOUL)
				_ellipse(image, origin + Vector2(16, 30), Vector2(4, 7) * (1.0 - shrink), SOUL_LIGHT)
			RIFT, RIFT_BREAK:
				var open := (1.0 - t) if art_name == RIFT_BREAK else 1.0 - 0.15 * sin(TAU * t)
				_ellipse(image, origin + Vector2(16, 26), Vector2(6, 18) * open, RIFT_COLOR)
				_ellipse(image, origin + Vector2(16, 26), Vector2(2, 12) * open, Color.WHITE)
			BOUNTY_CROWN:
				_box(image, origin, Vector2(3, 7), Vector2(10, 5), GOLD)
				for x in [3, 7, 11]:
					_box(image, origin, Vector2(x, 4), Vector2(2, 3), GOLD)
			ESCAPE_HOLE:
				_ellipse(image, origin + Vector2(16, 18), Vector2(4 + 10 * t, 2 + 5 * t), HOLE)
			BONE_HEAP_RISE:
				var height := 4.0 + 18.0 * t
				_ellipse(image, origin + Vector2(16, 28), Vector2(10, 3), BONE.darkened(0.3))
				_box(image, origin, Vector2(12, 30 - height), Vector2(8, height), BONE)
			WAGER_ALTAR:
				_box(image, origin, Vector2(6, 26), Vector2(20, 20), STONE)
				_ellipse(image, origin + Vector2(16, 20), Vector2(5, 5), SOUL_LIGHT.darkened(0.3 * t))
			WAGER_ICONS:
				var colors := [Color("#e0463a"), GOLD, Color("#6cb2ec"), SOUL, Color("#ff8a3c"), Color("#7ff0c8")]
				_ellipse(image, origin + Vector2(8, 8), Vector2(5, 5), colors[frame % colors.size()])
	_outline(image)
	return image


static func _box(image: Image, origin: Vector2, position: Vector2, size: Vector2, color: Color) -> void:
	var rect := Rect2i(Vector2i(origin + position), Vector2i(size))
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if clipped.size.x > 0 and clipped.size.y > 0:
		image.fill_rect(clipped, color)


static func _ellipse(image: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	if radius.x <= 0.0 or radius.y <= 0.0:
		return
	for y in range(floori(center.y - radius.y), ceili(center.y + radius.y) + 1):
		for x in range(floori(center.x - radius.x), ceili(center.x + radius.x) + 1):
			var d := Vector2((x - center.x) / radius.x, (y - center.y) / radius.y)
			if d.length_squared() <= 1.0 and x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


## Dark outline around every opaque pixel (house style of the placeholders).
static func _outline(image: Image) -> void:
	var copy := image.duplicate() as Image
	for y in image.get_height():
		for x in image.get_width():
			if copy.get_pixel(x, y).a > 0.0:
				continue
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p := Vector2i(x, y) + offset
				if p.x >= 0 and p.y >= 0 and p.x < image.get_width() and p.y < image.get_height() and copy.get_pixel(p.x, p.y).a > 0.0:
					image.set_pixel(x, y, OUTLINE)
					break
