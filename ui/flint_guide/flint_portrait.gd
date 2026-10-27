class_name FlintPortrait
extends Control
## Flint big in the explanation corner (SPRITES_V13 §B2): his portrait strip for the step's mood,
## inside the round frame (guide_frame.png, else a ring drawn from code) on a dark disc in the panel
## colour (the delivered frame is open in the middle, V13c). Pixel art stays sharp
## (nearest, whole multiples of the art size). pulse() is the little bounce of a babbled syllable.
## Like the companion (D-217, FlintShine): a soft warm glow breathes behind him (under the ring, so
## it stays inside it) and sparks rise from his flame and fade before the ring; no sparks on
## "Lichteffekte: Niedrig". Optics only.

## Ring and portrait size in mockup pixels (§B2: 56 and 48).
const RING_SPEC := 56.0
const PORTRAIT_SPEC := 48.0
## Disc behind the portrait: the panel colour of the explanation corner.
const RING_FILL := Color("#2a2638")
const RING_EDGE := Color("#ffd166")
const RING_SHADE := Color("#1c1a2b")
const PULSE_SCALE := 1.06
## TESTWERTE (portrait art px, D-217): radius of the glow and how far below the flame its middle
## sits (so it stays inside the ring), how high sparks climb, and how far from the ring's middle
## (inner edge 24) they are gone.
const GLOW_RADIUS := 18.0
const GLOW_DROP := 3.0
const SPARK_RISE := 12.0
const SPARK_CLIP_RADIUS := 22.0

var frames: SpriteFrames = null
var animation: StringName = &"talk"
var frame := 0
var _frame_time := 0.0
var _ring: Texture2D = null
## Middle of the flame in the portrait art (glow and sparks) and the time they breathe and rise by.
var _flame := FlintPortraitArt.DEFAULT_FLAME
var _shine_time := 0.0


func _init() -> void:
	frames = FlintPortraitArt.get_frames()
	_ring = FlintPortraitArt.texture(FlintPortraitArt.FRAME_FILE)
	_flame = FlintPortraitArt.flame_point() if FlintPortraitArt.has_delivered_portraits() else _placeholder_flame()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var side := UiKit.art_px(RING_SPEC, RING_SPEC)
	custom_minimum_size = Vector2(side, side)
	size = custom_minimum_size


## Shows the strip of a mood (FlintGuideStep.Mood) from its first frame.
func set_mood(mood: int) -> void:
	var wanted := FlintGuideRules.portrait_animation(mood)
	if not frames.has_animation(wanted):
		wanted = &"talk"
	if wanted == animation:
		return
	animation = wanted
	frame = 0
	_frame_time = 0.0
	queue_redraw()


func pulse() -> void:
	pivot_offset = size * 0.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * PULSE_SCALE, 0.04)
	tween.tween_property(self, "scale", Vector2.ONE, 0.09)


func _process(delta: float) -> void:
	_shine_time += delta
	if is_visible_in_tree():
		# Glow and sparks move every frame.
		queue_redraw()
	var count := frames.get_frame_count(animation)
	if count <= 1:
		return
	_frame_time += delta
	var step := 1.0 / maxf(0.1, frames.get_animation_speed(animation))
	if _frame_time >= step:
		_frame_time = fmod(_frame_time, step)
		frame = (frame + 1) % count


## Where glow and sparks sit (portrait art px).
func get_flame_point() -> Vector2:
	return _flame


## The flame of the code figure in the placeholder portrait (FlintPlaceholder twice as large).
static func _placeholder_flame() -> Vector2:
	var anchor := FlintPlaceholder.flame_anchor(FlintPlaceholder.Pose.new()) - FlintPlaceholder.PIVOT
	return Vector2(FlintPortraitArt.PLACEHOLDER_FEET) + anchor * FlintPortraitArt.PLACEHOLDER_SCALE


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	var texture := frames.get_frame_texture(animation, frame) if frames.get_frame_count(animation) > 0 else null
	var side := UiKit.art_px(PORTRAIT_SPEC, float(texture.get_width()) if texture != null else PORTRAIT_SPEC)
	var portrait := Rect2(box.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	var pixel := side / FlintPortraitArt.FRAME_SIZE.x
	var flame := portrait.position + _flame * pixel
	if _ring != null:
		var art := UiKit.ART_SCALE
		draw_circle(box.get_center(), minf(box.size.x, box.size.y) * 0.5 - art, RING_FILL)
		# Under the ring: what spills over its inner edge is covered.
		FlintShine.draw_glow(self, flame + Vector2(0, GLOW_DROP * pixel), GLOW_RADIUS * pixel, _shine_time)
		draw_texture_rect(_ring, box, false)
	else:
		var center := box.get_center()
		var radius := minf(box.size.x, box.size.y) * 0.5
		var art := UiKit.ART_SCALE
		draw_circle(center, radius, RING_SHADE)
		draw_circle(center, radius - art, RING_EDGE)
		draw_circle(center, radius - art * 2, RING_FILL)
		var glow_center := flame + Vector2(0, GLOW_DROP * pixel)
		FlintShine.draw_glow(self, glow_center, minf(GLOW_RADIUS * pixel, radius - art * 2 - (glow_center - center).length()), _shine_time)
	if texture == null:
		return
	draw_texture_rect(texture, portrait, false)
	FlintShine.draw_sparks(self, flame, pixel, SPARK_RISE * pixel, _shine_time, box.get_center(), SPARK_CLIP_RADIUS * pixel)
