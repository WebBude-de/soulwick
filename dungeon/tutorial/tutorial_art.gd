class_name TutorialArt
extends RefCounted
## Pictures of the practice run (WK10, SPRITES_V13), delivered in art/environment/tutorial/ with the
## frame data of tutorial.json: straw dummy (idle, hit, break), dummy with a wooden shield (idle,
## block), station sign, flag (frame 0 limp, frame 1 flying) and the gate "Dungeon". Drawn at
## SpriteStrip.PIXEL_SCALE like every 32 px art. A missing file gets a small placeholder drawn here,
## so the practice run never breaks on art (AGENTS.md §8); a file of the same name replaces it.

const DIR := "res://art/environment/tutorial/"
## name -> [file, frame size, frames, fps, loop, pivot] (tutorial.json).
const STRIPS := {
	&"dummy_idle": ["training_dummy_idle_2f.png", Vector2i(32, 32), 2, 2.0, true, Vector2(16, 30)],
	&"dummy_hit": ["training_dummy_hit_4f.png", Vector2i(32, 32), 4, 10.0, false, Vector2(16, 30)],
	&"dummy_break": ["training_dummy_break_6f.png", Vector2i(32, 32), 6, 8.0, false, Vector2(16, 30)],
	&"shield_idle": ["training_dummy_shield_idle_2f.png", Vector2i(32, 32), 2, 2.0, true, Vector2(16, 30)],
	&"shield_block": ["training_dummy_shield_block_4f.png", Vector2i(32, 32), 4, 10.0, false, Vector2(16, 30)],
	&"shield_break": ["training_dummy_shield_break_6f.png", Vector2i(32, 32), 6, 8.0, false, Vector2(16, 30)],
	&"sign": ["station_sign.png", Vector2i(24, 32), 1, 0.0, false, Vector2(12, 31)],
	&"flag": ["station_flag_2f.png", Vector2i(16, 24), 2, 0.0, false, Vector2(4, 23)],
	&"gate": ["tutorial_gate.png", Vector2i(64, 48), 1, 0.0, false, Vector2(32, 47)],
}
## Free board of the sign for the key symbol (art px, tutorial.json: x 4-20, y 4-16).
const SIGN_BOARD := Rect2(4, 4, 16, 12)
## Placeholder colours: straw, wood, shield, flag cloth.
const STRAW := Color("#e8c47c")
const WOOD := Color("#8a5a30")
const CLOTH := Color("#4fd06a")

static var _textures: Dictionary = {}


## Texture of a strip (the delivered file or a drawn placeholder of the same size).
static func texture(strip: StringName) -> Texture2D:
	if _textures.has(strip):
		return _textures[strip]
	var spec: Array = STRIPS[strip]
	var path: String = DIR + String(spec[0])
	var result: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if result == null:
		result = placeholder(strip)
	_textures[strip] = result
	return result


## True when the strip comes from art/ (not a placeholder).
static func is_delivered(strip: StringName) -> bool:
	return ResourceLoader.exists(DIR + String(STRIPS[strip][0]))


static func frame_size(strip: StringName) -> Vector2i:
	return STRIPS[strip][1]


static func pivot(strip: StringName) -> Vector2:
	return STRIPS[strip][5]


## Frames of a dummy: idle, hit and break (straw) or idle, block and break (shield).
static func dummy_frames(shielded: bool) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var names: Array[StringName] = [&"dummy_idle", &"dummy_hit", &"dummy_break"]
	if shielded:
		# Until its own break is delivered (SPRITES_V13 part C) the straw dummy's fall stands in.
		names = [&"shield_idle", &"shield_block", &"shield_break" if is_delivered(&"shield_break") else &"dummy_break"]
	var animations: Array[StringName] = [&"idle", &"hit", &"break"]
	for i in names.size():
		var spec: Array = STRIPS[names[i]]
		SpriteStrip.add_strip(frames, animations[i], texture(names[i]), spec[1], spec[3], spec[4])
	return frames


## A Sprite2D of a still strip (sign, flag, gate) at the art scale, its pivot on the node origin;
## frame picks the picture of a strip with several.
static func sprite(strip: StringName) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = texture(strip)
	var spec: Array = STRIPS[strip]
	node.hframes = maxi(1, int(spec[2]))
	node.centered = false
	node.offset = -Vector2(spec[5])
	node.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return node


## Drawn stand-in with the strip's size and frame count (AGENTS.md §8).
static func placeholder(strip: StringName) -> Texture2D:
	var spec: Array = STRIPS[strip]
	var size: Vector2i = spec[1]
	var frames: int = maxi(1, int(spec[2]))
	var image := Image.create(size.x * frames, size.y, false, Image.FORMAT_RGBA8)
	for frame in frames:
		var origin := Vector2i(size.x * frame, 0)
		match strip:
			&"sign":
				image.fill_rect(Rect2i(origin + Vector2i(10, 16), Vector2i(4, 16)), WOOD)
				image.fill_rect(Rect2i(origin + Vector2i(2, 2), Vector2i(20, 16)), WOOD)
				image.fill_rect(Rect2i(origin + Vector2i(4, 4), Vector2i(16, 12)), Color("#2a2335"))
			&"flag":
				image.fill_rect(Rect2i(origin + Vector2i(3, 2), Vector2i(2, 22)), WOOD)
				var cloth := Vector2i(8, 6) if frame == 1 else Vector2i(4, 8)
				image.fill_rect(Rect2i(origin + Vector2i(5, 2), cloth), CLOTH if frame == 1 else CLOTH.darkened(0.4))
			&"gate":
				image.fill_rect(Rect2i(origin + Vector2i(4, 0), Vector2i(56, 48)), Color("#8a84a8"))
				image.fill_rect(Rect2i(origin + Vector2i(14, 10), Vector2i(36, 38)), Color("#2a2335"))
			_:
				# A dummy: pole, straw head, a plank shield on the shield strips; the break frames tip over.
				var tipped := strip in [&"dummy_break", &"shield_break"] and frame >= frames / 2
				if tipped:
					image.fill_rect(Rect2i(origin + Vector2i(6, 26), Vector2i(20, 3)), WOOD)
					image.fill_rect(Rect2i(origin + Vector2i(20, 23), Vector2i(9, 8)), STRAW)
				else:
					image.fill_rect(Rect2i(origin + Vector2i(15, 14), Vector2i(2, 16)), WOOD)
					image.fill_rect(Rect2i(origin + Vector2i(11, 4), Vector2i(10, 10)), STRAW)
					if strip in [&"shield_idle", &"shield_block"]:
						image.fill_rect(Rect2i(origin + Vector2i(20, 10), Vector2i(6, 11)), WOOD)
	return ImageTexture.create_from_image(image)
