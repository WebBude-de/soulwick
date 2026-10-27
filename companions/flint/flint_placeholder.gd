class_name FlintPlaceholder
extends RefCounted
## Flint from code for when his art folder is missing (tests, a broken checkout): the same figure as
## the generated art (D-217), only fewer poses. The rasters below are copies of GAME_FLAMES and
## GAME_BODY in tools/generate_flint.py (the website figure at companion size, D-205), painted the
## same way, so idle frame 0 here is pixel for pixel the generated one (test_flint_art pins it): there
## is only one Flint look. 32x32 frames, pivot (16, 30), facing left. No light is painted in (D-174).

const FRAME_SIZE := Vector2i(32, 32)
const PIVOT := Vector2(16, 30)
## Website colours (wick-figure.tsx COLORS).
const OUTLINE := Color("#1c1a2b")
const COLORS := {
	"k": Color("#1c1a2b"),
	"t": Color("#3b3650"),
	"o": Color("#ff8a3c"),
	"y": Color("#ffb54a"),
	"w": Color("#fff3c4"),
	"c": Color("#efe6cf"),
	"h": Color("#ffffff"),
	"s": Color("#b9b3c9"),
	"p": Color("#f0648c"),
}
const FLAME_CHARS := "oyw"
## The raster column that lands on the pivot.
const CENTER_COLUMN := 8
## Eyes (1x2, body rows 4-5) and the mouth of the open-mouthed talk pose.
const EYE_COLUMNS: Array[int] = [6, 9]
const EYE_ROW := 4
const MOUTH := Vector2i(7, 8)

const FLAMES := {
	&"a": [
		"........o.......",
		".......ooo......",
		"......oyyyo.....",
		"......oywyo.....",
		".....oywwwyo....",
		".....oywwwyo....",
		"......oyyyo.....",
	],
	&"b": [
		".......o........",
		".......oo.......",
		".......oyo......",
		"......oyyyo.....",
		"......oywyo.....",
		".....oywwwyo....",
		"......oyyyo.....",
	],
	&"c": [
		"................",
		".........o......",
		"........ooo.....",
		"......ooyyyo....",
		".....oyywwyo....",
		".....oywwwyo....",
		"......oyyyo.....",
	],
}
## Wick row first; cheeks and the small mouth are part of the website body.
const BODY: Array[String] = [
	"........t.......",
	".....kkkkkk.....",
	"....khccccsk....",
	"....khccccsk....",
	"....kcccccsk....",
	"....kcccccsk....",
	"....kccccssk....",
	"....kpccccpk....",
	"....kcckcssk....",
	"....khcccssk....",
	"....kccccssk....",
	"....kssssssk....",
	".....kkkkkk.....",
	".....kk..kk.....",
]

## name -> [frames, fps, loop]: the flame flickers (a, b, a, c), a blink in the last frame.
const ANIMATIONS := {
	&"idle": [4, 4.0, true],
}


## One frame: flame variant, eyes open or blinking, mouth closed or open (talk).
class Pose:
	extends RefCounted
	var flame: StringName = &"a"
	var blink := false
	var open_mouth := false


	func _init(flame_variant: StringName = &"a", blinking := false, mouth_open := false) -> void:
		flame = flame_variant
		blink = blinking
		open_mouth = mouth_open


## All animations: {frames: SpriteFrames, anchors: {anchor: {animation: PackedVector2Array}}}.
static func build() -> Dictionary:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var flame_anchors := {}
	var head_anchors := {}
	for animation: StringName in ANIMATIONS:
		var spec: Array = ANIMATIONS[animation]
		frames.add_animation(animation)
		frames.set_animation_speed(animation, spec[1])
		frames.set_animation_loop(animation, spec[2])
		var flames := PackedVector2Array()
		var heads := PackedVector2Array()
		for i in int(spec[0]):
			var pose := idle_pose(i)
			frames.add_frame(animation, ImageTexture.create_from_image(paint(pose)))
			flames.append(flame_anchor(pose))
			heads.append(head_anchor())
		flame_anchors[animation] = flames
		head_anchors[animation] = heads
	return {"frames": frames, "anchors": {&"flame": flame_anchors, &"head": head_anchors}}


static func idle_pose(i: int) -> Pose:
	return Pose.new([&"a", &"b", &"a", &"c"][i % 4], i % 4 == 3)


## One 32x32 frame of the companion.
static func paint(pose: Pose) -> Image:
	var image := Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	paint_into(image, pose, Vector2i(PIVOT), 1)
	return image


## Paints the figure into image with its feet row at feet (image px) and raster column 8 at feet.x,
## each raster pixel scale x scale.
static func paint_into(image: Image, pose: Pose, feet: Vector2i, scale: int) -> void:
	var pixels := figure_pixels(pose)
	var bottom := BODY.size() - 1
	for cell: Vector2i in pixels:
		var corner := feet + (cell - Vector2i(CENTER_COLUMN, bottom)) * scale
		image.fill_rect(Rect2i(corner, Vector2i(scale, scale)), COLORS[pixels[cell]])


## {Vector2i(x, y): char} of the figure: y 0 is the wick row, the flame has negative rows.
static func figure_pixels(pose: Pose) -> Dictionary:
	var pixels := {}
	for y in BODY.size():
		for x in BODY[y].length():
			if BODY[y][x] != ".":
				pixels[Vector2i(x, y)] = BODY[y][x]
	for eye_x in EYE_COLUMNS:
		if not pose.blink:
			pixels[Vector2i(eye_x, EYE_ROW)] = "k"
		pixels[Vector2i(eye_x, EYE_ROW + 1)] = "k"
	if pose.open_mouth:
		pixels[MOUTH] = "k"
		pixels[MOUTH + Vector2i(1, 0)] = "k"
		pixels[MOUTH + Vector2i(0, 1)] = "p"
		pixels[MOUTH + Vector2i(1, 1)] = "k"
	var flame: Array = FLAMES.get(pose.flame, FLAMES[&"a"])
	for i in flame.size():
		var row: String = flame[flame.size() - 1 - i]
		for x in row.length():
			if row[x] != ".":
				pixels[Vector2i(x, -1 - i)] = row[x]
	return pixels


## Middle of the flame pixels in frame px (light, spell origin).
static func flame_anchor(pose: Pose) -> Vector2:
	var pixels := figure_pixels(pose)
	var sum := Vector2.ZERO
	var count := 0
	for cell: Vector2i in pixels:
		if FLAME_CHARS.contains(pixels[cell]):
			sum += Vector2(cell) + Vector2(0.5, 0.5)
			count += 1
	var middle := sum / maxf(1.0, count)
	return PIVOT + middle - Vector2(CENTER_COLUMN, BODY.size() - 1)


## Top edge of the wax outline in frame px (hats).
static func head_anchor() -> Vector2:
	return PIVOT + Vector2(0, 1 - (BODY.size() - 1))
