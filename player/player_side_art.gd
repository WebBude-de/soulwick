class_name PlayerSideArt
extends RefCounted
## Body animations of the side-view segments (M5): jump (take-off, flight, apex), landing, falling
## (player_fall frame 1), climbing, double jump and wall slide. They are added at runtime to the
## player's SpriteFrames and the character's clothing masks (CharacterData.tint_masks), once and only
## in memory, so the character colours keep working without touching art/ or characters/. Delivered
## strips are taken by name; missing ones fall back to frames that exist (placeholders). Hook for the
## art round: put the same animations into art/characters/player/player_frames.tres and the
## characters (characters/wick.tres, ember.tres, moss.tres, frost.tres), then ensure() finds them
## and does nothing.
## Squash, stretch and the salto turn of the double jump are not frames: SidePlayerFx scales and
## turns the sprite.

const JUMP := &"side_jump"
const LAND := &"side_land"
const FALL := &"side_fall"
const CLIMB := &"side_climb"
const DOUBLE_JUMP := &"side_double_jump"
const WALL_SLIDE := &"side_wall_slide"

const ART_DIR := "res://art/characters/player/"
const FRAME := Vector2i(32, 32)
const JUMP_TEXTURE: Texture2D = preload("res://art/characters/player/player_jump_3f.png")
const JUMP_MASK: Texture2D = preload("res://art/characters/player/player_tint_mask_jump_3f.png")
const LAND_TEXTURE: Texture2D = preload("res://art/characters/player/player_land_2f.png")
const FALL_TEXTURE: Texture2D = preload("res://art/characters/player/player_fall_4f.png")
const FALL_MASK: Texture2D = preload("res://art/characters/player/player_tint_mask_fall_4f.png")
## Delivered with SPRITES_V9 (15.10.2026); without them the fallbacks below.
const LAND_MASK_PATH := ART_DIR + "player_tint_mask_land_2f.png"
const CLIMB_TEXTURE_PATH := ART_DIR + "player_climb_4f.png"
const CLIMB_MASK_PATH := ART_DIR + "player_tint_mask_climb_4f.png"
## Not delivered yet (round 2 report): the salto of the double jump and the wall slide. Until then
## the double jump plays the jump frames (turned by SidePlayerFx), the wall slide the fall frame.
const DOUBLE_JUMP_TEXTURE_PATH := ART_DIR + "player_double_jump_4f.png"
const DOUBLE_JUMP_MASK_PATH := ART_DIR + "player_tint_mask_double_jump_4f.png"
const WALL_SLIDE_TEXTURE_PATH := ART_DIR + "player_wall_slide_2f.png"
const WALL_SLIDE_MASK_PATH := ART_DIR + "player_tint_mask_wall_slide_2f.png"
const JUMP_FPS := 10.0
const LAND_FPS := 14.0
const CLIMB_FPS := 8.0
const DOUBLE_JUMP_FPS := 14.0
const WALL_SLIDE_FPS := 6.0


## Makes sure the sprite's frames and character masks know the side-view animations.
static func ensure(sprite: AnimatedSprite2D) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var frames := sprite.sprite_frames
	var data := sprite.get_meta(CharacterData.META_DATA, null) as CharacterData
	if not frames.has_animation(JUMP):
		SpriteStrip.add_strip(frames, JUMP, JUMP_TEXTURE, FRAME, JUMP_FPS, false)
	var land_mask := _texture(LAND_MASK_PATH)
	if not frames.has_animation(LAND):
		if land_mask != null:
			SpriteStrip.add_strip(frames, LAND, LAND_TEXTURE, FRAME, LAND_FPS, false)
		else:
			_add_single(frames, LAND, JUMP_TEXTURE, 0, LAND_FPS)
	if not frames.has_animation(FALL):
		_add_single(frames, FALL, FALL_TEXTURE, 0, 1.0)
	var climb := _texture(CLIMB_TEXTURE_PATH)
	if not frames.has_animation(CLIMB):
		if climb != null:
			SpriteStrip.add_strip(frames, CLIMB, climb, FRAME, CLIMB_FPS, true)
		elif frames.has_animation(&"walk"):
			_copy(frames, &"walk", CLIMB, CLIMB_FPS)
	var double_jump := _texture(DOUBLE_JUMP_TEXTURE_PATH)
	if not frames.has_animation(DOUBLE_JUMP):
		SpriteStrip.add_strip(frames, DOUBLE_JUMP, double_jump if double_jump != null else JUMP_TEXTURE, FRAME, DOUBLE_JUMP_FPS, false)
	var wall_slide := _texture(WALL_SLIDE_TEXTURE_PATH)
	if not frames.has_animation(WALL_SLIDE):
		if wall_slide != null:
			SpriteStrip.add_strip(frames, WALL_SLIDE, wall_slide, FRAME, WALL_SLIDE_FPS, true)
		else:
			_add_single(frames, WALL_SLIDE, FALL_TEXTURE, 0, 1.0)
	if data == null:
		return
	_add_mask(data, JUMP, JUMP_MASK)
	_add_mask(data, LAND, land_mask if land_mask != null else JUMP_MASK)
	_add_mask(data, FALL, FALL_MASK)
	var climb_mask := _texture(CLIMB_MASK_PATH)
	_add_mask(data, CLIMB, climb_mask if climb != null and climb_mask != null else data.get_mask(&"walk"))
	_add_mask(data, DOUBLE_JUMP, _texture(DOUBLE_JUMP_MASK_PATH) if double_jump != null else JUMP_MASK)
	_add_mask(data, WALL_SLIDE, _texture(WALL_SLIDE_MASK_PATH) if wall_slide != null else FALL_MASK)
	CharacterData.refresh_tint(sprite)


static func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


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
