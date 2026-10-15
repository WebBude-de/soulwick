class_name SpriteStrip
extends RefCounted
## Helpers for horizontal sprite strips from art/ (see docs/design/sprites/SPRITES.md).
## All character and tile art is drawn at PIXEL_SCALE in the world, so GDD pixel values
## (ranges, speeds) keep their meaning while 32 px sprites stay readable.

const PIXEL_SCALE := 2.0


## Adds one animation from a strip of equally sized frames to frames.
static func add_strip(frames: SpriteFrames, animation: StringName, texture: Texture2D, frame_size: Vector2i, fps: float, loop: bool) -> void:
	if not frames.has_animation(animation):
		frames.add_animation(animation)
	frames.set_animation_speed(animation, fps)
	frames.set_animation_loop(animation, loop)
	var count := maxi(1, texture.get_width() / frame_size.x)
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_size.x, 0, frame_size.x, frame_size.y)
		frames.add_frame(animation, atlas)


static func make_frames(texture: Texture2D, frame_size: Vector2i, fps: float, loop: bool, animation: StringName = &"default") -> SpriteFrames:
	var frames := SpriteFrames.new()
	if animation != &"default":
		frames.remove_animation(&"default")
	add_strip(frames, animation, texture, frame_size, fps, loop)
	return frames


## Offset that puts the given pivot (in frame pixels) onto the node origin of a centered sprite.
static func pivot_offset(frame_size: Vector2i, pivot: Vector2) -> Vector2:
	return Vector2(frame_size) * 0.5 - pivot


## Plays a strip once at global_pos and frees itself afterwards.
static func spawn_effect(parent: Node, global_pos: Vector2, texture: Texture2D, frame_size: Vector2i, fps: float, pivot: Vector2, effect_scale := Vector2.ONE, effect_rotation := 0.0) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = make_frames(texture, frame_size, fps, false)
	sprite.offset = pivot_offset(frame_size, pivot)
	sprite.scale = effect_scale
	sprite.rotation = effect_rotation
	sprite.z_index = 5
	parent.add_child(sprite)
	sprite.global_position = global_pos
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play(&"default")
	return sprite
