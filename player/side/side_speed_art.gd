class_name SideSpeedArt
extends RefCounted
## Body animations of momentum and stomping in side view (D-195, SV1): the sprint at full momentum
## and the stomp bounce. Like PlayerSideArt they are added at runtime to the player's SpriteFrames
## and the character's clothing masks, once and only in memory. Delivered strips (SPRITES_V13 B10)
## are taken by name; until then the sprint is the walk played faster and the stomp the jump's
## take-off frames (placeholders from code).

const SPRINT := &"side_sprint"
const STOMP := &"side_stomp"

const ART_DIR := "res://art/characters/player/"
const FRAME := Vector2i(32, 32)
const SPRINT_TEXTURE_PATH := ART_DIR + "player_sprint_6f.png"
const SPRINT_MASK_PATH := ART_DIR + "player_tint_mask_sprint_6f.png"
const STOMP_TEXTURE_PATH := ART_DIR + "player_stomp_3f.png"
const STOMP_MASK_PATH := ART_DIR + "player_tint_mask_stomp_3f.png"
const SPRINT_FPS := 14.0
const STOMP_FPS := 12.0
## The sprint shows from this momentum factor on (TESTWERT; near the top speed of 2.0×).
const SPRINT_FACTOR := 1.8
## The stomp frames show this long after a stomp (seconds).
const STOMP_ANIMATION_TIME := 0.25


## Makes sure the sprite's frames and character masks know the sprint and the stomp (after
## PlayerSideArt.ensure, whose jump frames are the stomp's placeholder).
static func ensure(sprite: AnimatedSprite2D) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var frames := sprite.sprite_frames
	var data := sprite.get_meta(CharacterData.META_DATA, null) as CharacterData
	var sprint := _texture(SPRINT_TEXTURE_PATH)
	if not frames.has_animation(SPRINT):
		if sprint != null:
			SpriteStrip.add_strip(frames, SPRINT, sprint, FRAME, SPRINT_FPS, true)
		elif frames.has_animation(&"walk"):
			_copy(frames, &"walk", SPRINT, SPRINT_FPS, true)
	var stomp := _texture(STOMP_TEXTURE_PATH)
	if not frames.has_animation(STOMP):
		if stomp != null:
			SpriteStrip.add_strip(frames, STOMP, stomp, FRAME, STOMP_FPS, false)
		elif frames.has_animation(PlayerSideArt.JUMP):
			_copy(frames, PlayerSideArt.JUMP, STOMP, STOMP_FPS, false)
	if data == null:
		return
	var sprint_mask := _texture(SPRINT_MASK_PATH) if sprint != null else data.get_mask(&"walk")
	var stomp_mask := _texture(STOMP_MASK_PATH) if stomp != null else data.get_mask(PlayerSideArt.JUMP)
	_add_mask(data, SPRINT, sprint_mask)
	_add_mask(data, STOMP, stomp_mask)
	CharacterData.refresh_tint(sprite)


static func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _copy(frames: SpriteFrames, from: StringName, to: StringName, fps: float, loop: bool) -> void:
	frames.add_animation(to)
	frames.set_animation_speed(to, fps)
	frames.set_animation_loop(to, loop)
	for i in frames.get_frame_count(from):
		frames.add_frame(to, frames.get_frame_texture(from, i))


static func _add_mask(data: CharacterData, animation: StringName, mask: Texture2D) -> void:
	if mask != null and not data.tint_masks.has(animation):
		data.tint_masks[animation] = mask
