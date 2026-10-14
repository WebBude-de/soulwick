class_name Villager
extends Node2D
## Villager or small animal that walks slowly along a route of points and stands for a moment at
## each one (B3). No collision: it never blocks the player's way. The origin sits FEET_OFFSET above
## the feet like the player's, so Y-sorting against player and props needs no SortLift.
## Art: art/characters/npcs/<art_name>_idle_4f.png (+ _walk_6f.png) via VillageArt; until then the
## fallback NPC frames with a tint (villagers) or nothing (optional animals free themselves).
## Waiting times are random (randf, optics only); the route itself is fixed.

## Route points (feet, village coordinates). Two or more points.
@export var route := PackedVector2Array()
## true: last point leads back to the first; false: walk the route back and forth.
@export var loop := false
## TESTWERT: walking speed (world px/s) and waiting time per point (s).
@export var speed := 30.0
@export var pause_min := 1.2
@export var pause_max := 3.6
@export var art_name := ""
@export var fallback_frames: SpriteFrames = null
@export var tint := Color.WHITE
## Free the node when neither art nor fallback exists (chickens, cat).
@export var optional := false
## Art pixels are drawn at this scale; small animals use the same.
@export var art_scale := 2.0

const FEET_OFFSET := Player.FEET_OFFSET
## Walk bob (world px) while there is no walk animation.
const BOB := 2.0
const BOB_SPEED := 14.0
const ARRIVE := 1.0

var _sprite: AnimatedSprite2D = null
var _target := 0
var _forward := true
var _wait := 0.0
var _has_walk := false
var _bob_time := 0.0


## Next route index after index (count points): loop or back and forth. Returns [index, forward].
static func next_index(index: int, count: int, looping: bool, forward: bool) -> Array:
	if count < 2:
		return [0, forward]
	if looping:
		return [(index + 1) % count, true]
	if forward and index + 1 >= count:
		forward = false
	elif not forward and index - 1 < 0:
		forward = true
	return [index + (1 if forward else -1), forward]


func _ready() -> void:
	var frames := VillageArt.get_character_frames(art_name)
	if frames == null:
		if optional or fallback_frames == null:
			queue_free()
			return
		frames = fallback_frames
		modulate = tint
	_has_walk = frames.has_animation(&"walk")
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = frames
	_sprite.scale = Vector2.ONE * art_scale
	var frame := frames.get_frame_texture(&"idle", 0)
	var frame_size := frame.get_size() if frame != null else Vector2(32, 32)
	# Feet on the frame's bottom line (pivot (16, 30) in 32 px frames) at FEET_OFFSET.
	_sprite.offset = Vector2(0, -frame_size.y * 0.5 + frame_size.y / 16.0)
	_sprite.position = FEET_OFFSET
	add_child(_sprite)
	_sprite.play(&"idle")
	DropShadow.attach(self, 7.0 * art_scale * frame_size.x / 32.0, FEET_OFFSET.y)
	if route.size() > 0:
		position = route[0] - FEET_OFFSET
	_target = 1 if route.size() > 1 else 0
	_wait = randf_range(0.0, pause_max)


## Feet position in village coordinates.
func get_feet() -> Vector2:
	return position + FEET_OFFSET


func _process(delta: float) -> void:
	if _sprite == null or route.size() < 2:
		return
	if _wait > 0.0:
		_wait -= delta
		_set_walking(false)
		return
	var goal := route[_target] - FEET_OFFSET
	var to_goal := goal - position
	if to_goal.length() <= ARRIVE:
		position = goal
		var next := next_index(_target, route.size(), loop, _forward)
		_target = next[0]
		_forward = next[1]
		_wait = randf_range(pause_min, pause_max)
		_set_walking(false)
		return
	position += to_goal.limit_length(speed * delta)
	if absf(to_goal.x) > 0.5:
		_sprite.flip_h = to_goal.x < 0.0
	_set_walking(true)
	if not _has_walk:
		_bob_time += delta
		_sprite.position.y = FEET_OFFSET.y - absf(sin(_bob_time * BOB_SPEED)) * BOB


func _set_walking(walking: bool) -> void:
	var animation := &"walk" if walking and _has_walk else &"idle"
	if _sprite.animation != animation:
		_sprite.play(animation)
	if not walking:
		_sprite.position.y = FEET_OFFSET.y
