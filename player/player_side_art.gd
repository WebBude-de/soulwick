class_name PlayerSideArt
extends RefCounted
## Body animations of the side-view segments (M5): jump (take-off, flight, apex), landing, falling
## (player_fall frame 1) and climbing. They are added at runtime to the player's SpriteFrames and the
## character's clothing masks (CharacterData.tint_masks), once and only in memory, so the character
## colours keep working without touching art/ or characters/. Hook for the art round: put the same
## animations into art/characters/player/player_frames.tres and characters/hero.tres, then ensure()
## finds them and does nothing.

const JUMP := &"side_jump"
const LAND := &"side_land"
const FALL := &"side_fall"
const CLIMB := &"side_climb"

const FRAME := Vector2i(32, 32)
const JUMP_TEXTURE: Texture2D = preload("res://art/characters/player/player_jump_3f.png")
const JUMP_MASK: Texture2D = preload("res://art/characters/player/player_tint_mask_jump_3f.png")
const LAND_TEXTURE: Texture2D = preload("res://art/characters/player/player_land_2f.png")
## Not delivered yet (SPRITES_V9): without it the landing uses the take-off frame of the jump.
const LAND_MASK_PATH := "res://art/characters/player/player_tint_mask_land_2f.png"
const FALL_TEXTURE: Texture2D = preload("res://art/characters/player/player_fall_4f.png")
const FALL_MASK: Texture2D = preload("res://art/characters/player/player_tint_mask_fall_4f.png")
## Not delivered yet (SPRITES_V9): until then climbing reuses the walk frames.
const CLIMB_TEXTURE_PATH := "res://art/characters/player/player_climb_4f.png"
const CLIMB_MASK_PATH := "res://art/characters/player/player_tint_mask_climb_4f.png"
const JUMP_FPS := 10.0
const LAND_FPS := 14.0
const CLIMB_FPS := 8.0


## Makes sure the sprite's frames and character masks know the side-view animations.
static func ensure(sprite: AnimatedSprite2D) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var frames := sprite.sprite_frames
	var data := sprite.get_meta(CharacterData.META_DATA, null) as CharacterData
	if not frames.has_animation(JUMP):
		SpriteStrip.add_strip(frames, JUMP, JUMP_TEXTURE, FRAME, JUMP_FPS, false)
	var land_mask: Texture2D = load(LAND_MASK_PATH) as Texture2D if ResourceLoader.exists(LAND_MASK_PATH) else null
	if not frames.has_animation(LAND):
		if land_mask != null:
			SpriteStrip.add_strip(frames, LAND, LAND_TEXTURE, FRAME, LAND_FPS, false)
		else:
			_add_single(frames, LAND, JUMP_TEXTURE, 0, LAND_FPS)
	if not frames.has_animation(FALL):
		_add_single(frames, FALL, FALL_TEXTURE, 0, 1.0)
	if not frames.has_animation(CLIMB):
		if ResourceLoader.exists(CLIMB_TEXTURE_PATH):
			SpriteStrip.add_strip(frames, CLIMB, load(CLIMB_TEXTURE_PATH) as Texture2D, FRAME, CLIMB_FPS, true)
		elif frames.has_animation(&"walk"):
			_copy(frames, &"walk", CLIMB, CLIMB_FPS)
	if data == null:
		return
	_add_mask(data, JUMP, JUMP_MASK)
	_add_mask(data, LAND, land_mask if land_mask != null else JUMP_MASK)
	_add_mask(data, FALL, FALL_MASK)
	var climb_mask: Texture2D = load(CLIMB_MASK_PATH) as Texture2D if ResourceLoader.exists(CLIMB_MASK_PATH) else data.get_mask(&"walk")
	_add_mask(data, CLIMB, climb_mask)
	CharacterData.refresh_tint(sprite)


static func _add_single(frames: SpriteFrames, animation: StringName, texture: Texture2D, index: int, fps: float) -> void:
	frames.add_animation(animation)
	frames.set_animation_speed(animation, fps)
	frames.set_animation_loop(animation, false)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(index * FRAME.x, 0, FRAME.x, FRAME.y)
	frames.add_frame(animation, atlas)


static func _copy(frames: SpriteFrames, from: StringName, to: StringName, fps: float) -> void:
	frames.add_animation(to)
	frames.set_animation_speed(to, fps)
	frames.set_animation_loop(to, true)
	for i in frames.get_frame_count(from):
		frames.add_frame(to, frames.get_frame_texture(from, i))


static func _add_mask(data: CharacterData, animation: StringName, mask: Texture2D) -> void:
	if mask != null and not data.tint_masks.has(animation):
		data.tint_masks[animation] = mask
