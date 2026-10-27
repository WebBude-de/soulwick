class_name Villager
extends Node2D
## Villager or small animal that walks slowly along a route of points and stands for a moment at
## each one (B3). No collision: it never blocks the player's way. The origin sits FEET_OFFSET above
## the feet like the player's, so Y-sorting against player and props needs no SortLift.
## Art: art/characters/npcs/<art_name>_idle_4f.png (+ _walk_6f.png) via VillageArt; until then the
## fallback NPC frames with a tint (villagers) or nothing (optional animals free themselves).
## Waiting times are random (randf, optics only); the route itself is fixed.
## Report #ec4f0b9f (17.10.2026, "um mich herumlaufen und beim Anrennen beiseite huschen, mit einem
## kleinen verwirrten Laut"): still without collision, a walking villager steps around a player in its
## way, and one a player runs into hops aside, looks at the player with a "?" above its head, stands
## for a moment (dodge_sound, animals have none yet) and then walks back onto its route. Every player
## of the world counts (group &"player": local and remote players, Koop); each client moves its own
## villagers, nothing is shared or saved and no dungeon RNG is used (optics, D-088). A spot inside
## something solid (house, fence, prop, bush) is never taken.
## WK12 (D-196): an animal (animal = &"chicken", &"cat", …) gets a VillageAnimal: spoken to, it
## stands and looks at the player (hold), hops in place (hop_in_place) and plays its "react" strip
## while one is delivered (VillageArt.get_character_frames).

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
## Sound when a player runs into it (audio/sfx/<name>.wav, silent while the file is missing); empty
## for animals until they have their own.
@export var dodge_sound: StringName = &"villager_huh"
## WK12: animal kind for VillageAnimal (VillageAnimal.KINDS); empty for villagers.
@export var animal: StringName = &""

const FEET_OFFSET := Player.FEET_OFFSET
## Walk bob (world px) while there is no walk animation.
const BOB := 2.0
const BOB_SPEED := 14.0
const ARRIVE := 1.0
## TESTWERTE (#ec4f0b9f): a player closer than AVOID_RADIUS ahead of a walking villager and less than
## AVOID_SIDE beside its way makes it pass AVOID_SIDE px beside the player (sideways at AVOID_SPEED);
## once the player is AVOID_BEHIND behind it or gone, it returns at RETURN_SPEED.
const AVOID_RADIUS := 44.0
const AVOID_SIDE := 30.0
const AVOID_BEHIND := 12.0
const AVOID_SPEED := 70.0
const RETURN_SPEED := 40.0
## TESTWERTE: a player faster than DODGE_MIN_SPEED (px/s) moving towards the feet and closer than
## DODGE_RADIUS makes it hop DODGE_DISTANCE px aside in DODGE_TIME s (DODGE_HOP px high), then it
## stands for DODGE_PAUSE s; the "?" shows HUH_TIME s, the sound at most every SOUND_COOLDOWN s.
const DODGE_RADIUS := 26.0
const DODGE_MIN_SPEED := 60.0
const DODGE_DISTANCE := 36.0
const DODGE_TIME := 0.25
const DODGE_HOP := 6.0
const DODGE_PAUSE := 0.8
const HUH_TIME := 1.0
const HUH_RISE := 6.0
const HUH_GLYPH_GAP := 8.0
const SOUND_COOLDOWN := 2.5
const SOUND_VOLUME_DB := -8.0
## Feet circle checked against solids before a villager steps or hops somewhere (world px).
const SPOT_RADIUS := 7.0
const HUH_COLOR := Color(1.0, 0.94, 0.7)
const HUH_OUTLINE := Color(0.1, 0.08, 0.15)
## WK12 (preloaded: works before the class cache knows it).
const AnimalScript := preload("res://world/village/village_animal.gd")

var _sprite: AnimatedSprite2D = null
var _target := 0
var _forward := true
var _wait := 0.0
var _has_walk := false
var _bob_time := 0.0
var _cloak := Color.WHITE
## Top of the visible art (head) in local px, for the "?".
var _head_y := -32.0
## Origin on the route; the node stands _side away from it (stepping around or after a hop).
var _route_position := Vector2.ZERO
var _side := Vector2.ZERO
var _side_target := Vector2.ZERO
## Side (+1 / -1 along the way's normal) chosen for the player in the way, 0 = nobody in the way.
var _avoid_sign := 0
var _dodge_left := 0.0
var _dodge_from := Vector2.ZERO
var _dodge_to := Vector2.ZERO
var _stand_left := 0.0
var _sound_cooldown := 0.0
var _huh: Label = null
var _huh_left := 0.0
## Players seen last frame: instance id -> feet (global), for their speed (remote players too).
var _seen: Dictionary = {}
## WK12: hop height of the current hop (DODGE_HOP for a dodge), standing time after it, time left
## of a reaction (the "react" strip plays) and the animal's reaction node.
var _hop_height := DODGE_HOP
var _stand_after_hop := DODGE_PAUSE
var _reaction_left := 0.0
var _animal: AnimalScript = null


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
	# Feet (lowest opaque row of the art) at FEET_OFFSET.
	_sprite.offset = Vector2(0, VillageArt.feet_offset_y(frames))
	var image := frame.get_image() if frame != null else null
	var top := float(image.get_used_rect().position.y) if image != null else 0.0
	_head_y = FEET_OFFSET.y + (_sprite.offset.y - frame_size.y * 0.5 + top) * art_scale
	_sprite.position = FEET_OFFSET
	_sprite.self_modulate = _cloak
	add_child(_sprite)
	_sprite.play(&"idle")
	DropShadow.attach(self, 7.0 * art_scale * frame_size.x / 32.0, FEET_OFFSET.y)
	if route.size() > 0:
		position = route[0] - FEET_OFFSET
	_route_position = position
	_target = 1 if route.size() > 1 else 0
	_wait = randf_range(0.0, pause_max)
	if animal != &"":
		_animal = AnimalScript.attach(self, animal)


## Cloak colour of a rescued villager (R7: LostVillager.CLOAK_TINTS, like in the escort room).
func set_cloak(tint: Color) -> void:
	_cloak = tint
	if _sprite != null:
		_sprite.self_modulate = tint


func get_cloak() -> Color:
	return _cloak


## Feet position in village coordinates.
func get_feet() -> Vector2:
	return position + FEET_OFFSET


## True while it hops aside or stands after a hop (for tests and tools).
func is_dodging() -> bool:
	return _dodge_left > 0.0 or _stand_left > 0.0


## WK12: the reaction of an animal (null for villagers and animals without a kind).
func get_animal() -> AnimalScript:
	return _animal


## Feet position in world coordinates.
func get_feet_global() -> Vector2:
	return _global_feet(_route_position + _side)


## Top of the visible art (local px), for things shown above the head.
func get_head_y() -> float:
	return _head_y


func get_sprite() -> AnimatedSprite2D:
	return _sprite


## WK12: stands for seconds and looks towards face (global point); its "react" strip plays meanwhile.
## A player running into it still makes it hop aside.
func hold(face: Vector2, seconds: float) -> void:
	if _sprite == null:
		return
	_stand_left = maxf(_stand_left, seconds)
	_stand_after_hop = maxf(DODGE_PAUSE, seconds)
	_reaction_left = seconds
	_avoid_sign = 0
	var feet := get_feet_global()
	if absf(face.x - feet.x) > 0.5:
		_sprite.flip_h = face.x < feet.x
	_set_walking(false)


## True while it stands for a reaction (hold).
func is_holding() -> bool:
	return _reaction_left > 0.0


## WK12: a hop on the spot (height world px), then it stands like after a dodge (or as long as hold).
func hop_in_place(height: float) -> void:
	if _sprite == null:
		return
	_dodge_from = _side
	_dodge_to = _side
	_dodge_left = DODGE_TIME
	_hop_height = height


## How far it stands beside its route right now (world px).
func get_side_offset() -> Vector2:
	return _side


## The "?" above the head while it shows (null otherwise).
func get_huh() -> Label:
	return _huh if _huh != null and _huh.visible else null


func _process(delta: float) -> void:
	if _sprite == null:
		return
	_sound_cooldown = maxf(0.0, _sound_cooldown - delta)
	_reaction_left = maxf(0.0, _reaction_left - delta)
	_update_huh(delta)
	# Every frame, so the players' speeds stay true through a hop.
	var players := _players(delta)
	if _dodge_left > 0.0:
		_hop(delta)
	elif _stand_left > 0.0:
		# Standing after a hop (or until a player in the way moves on): only another bump counts.
		_stand_left = maxf(0.0, _stand_left - delta)
		_set_walking(false)
		_react(players, delta, Vector2.ZERO, false)
	else:
		var walk_direction := _walk(delta) if route.size() >= 2 else Vector2.ZERO
		var drifting := _react(players, delta, walk_direction)
		if walk_direction == Vector2.ZERO:
			_set_walking(drifting)
	position = _route_position + _side


## Follows the route on _route_position; returns the walking direction (zero while waiting, then the
## caller sets the animation).
func _walk(delta: float) -> Vector2:
	if _wait > 0.0:
		_wait -= delta
		return Vector2.ZERO
	var goal := route[_target] - FEET_OFFSET
	var to_goal := goal - _route_position
	if to_goal.length() <= ARRIVE:
		_route_position = goal
		var next := next_index(_target, route.size(), loop, _forward)
		_target = next[0]
		_forward = next[1]
		_wait = randf_range(pause_min, pause_max)
		return Vector2.ZERO
	_route_position += to_goal.limit_length(speed * delta)
	if absf(to_goal.x) > 0.5:
		_sprite.flip_h = to_goal.x < 0.0
	_set_walking(true)
	if not _has_walk:
		_bob_time += delta
		_sprite.position.y = FEET_OFFSET.y - absf(sin(_bob_time * BOB_SPEED)) * BOB
	return to_goal.normalized()


## Players around: hop aside when one runs into the feet, step around one in the way while walking,
## else drift back onto the route (not while a player still stands on it). move = false: only hops.
## Returns true while it drifts sideways without walking its route (then it walks, not slides).
func _react(players: Array[Dictionary], delta: float, walk_direction: Vector2, move := true) -> bool:
	var feet := _global_feet(_route_position + _side)
	var route_feet := _global_feet(_route_position)
	var nearest: Dictionary = {}
	for seen: Dictionary in players:
		if nearest.is_empty() or feet.distance_to(seen["feet"]) < feet.distance_to(nearest["feet"]):
			nearest = seen
	if not nearest.is_empty() and _runs_into(nearest, feet):
		_start_dodge(nearest, feet)
		return false
	if not move:
		return false
	_side_target = _avoid_offset(players, route_feet, walk_direction)
	if _side_target == Vector2.ZERO and _side != Vector2.ZERO and _player_near(players, route_feet, AVOID_SIDE):
		_side_target = _side
	var side_speed := AVOID_SPEED if _side_target != Vector2.ZERO else RETURN_SPEED
	var before := _side
	_side = _side.move_toward(_side_target, side_speed * delta)
	# Drifting back while waiting at a route point: walk there instead of sliding.
	var drift := _side - before
	if walk_direction != Vector2.ZERO or drift.length() <= 0.001 or _stand_left > 0.0:
		return false
	if absf(drift.x) > 0.001:
		_sprite.flip_h = drift.x < 0.0
	return true


## Every player of the world with its feet and speed (px/s, from the last frame's feet).
func _players(delta: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_inside_tree():
		return result
	var seen := {}
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node2D
		if player == null or not player.is_inside_tree():
			continue
		var player_feet := player.global_position + FEET_OFFSET
		var id := player.get_instance_id()
		var velocity := Vector2.ZERO
		if _seen.has(id) and delta > 0.0:
			velocity = (player_feet - (_seen[id] as Vector2)) / delta
		seen[id] = player_feet
		result.append({"feet": player_feet, "velocity": velocity})
	_seen = seen
	return result


## A player moving fast towards the feet and already close.
static func _runs_into(player: Dictionary, feet: Vector2) -> bool:
	var velocity: Vector2 = player["velocity"]
	var to_feet: Vector2 = feet - (player["feet"] as Vector2)
	return to_feet.length() < DODGE_RADIUS and velocity.length() > DODGE_MIN_SPEED and velocity.dot(to_feet) > 0.0


## Hop aside across the player's way (the side it already stands on, else the other one, else a
## shorter hop), look at the player, "?" and the sound. Stays in place if every spot is blocked.
func _start_dodge(player: Dictionary, feet: Vector2) -> void:
	var velocity: Vector2 = player["velocity"]
	var player_feet: Vector2 = player["feet"]
	var across := velocity.normalized().orthogonal()
	var side := 1.0 if across.dot(feet - player_feet) >= 0.0 else -1.0
	var hop := Vector2.ZERO
	for step: Vector2 in [across * side * DODGE_DISTANCE, -across * side * DODGE_DISTANCE, across * side * DODGE_DISTANCE * 0.5]:
		if is_spot_free(feet + step):
			hop = step
			break
	_dodge_from = _side
	_dodge_to = _side + hop
	_dodge_left = DODGE_TIME
	_hop_height = DODGE_HOP
	_stand_after_hop = DODGE_PAUSE
	_reaction_left = 0.0
	_avoid_sign = 0
	_side_target = _dodge_to
	_sprite.flip_h = player_feet.x < feet.x
	_set_walking(false)
	_show_huh()
	if dodge_sound != &"" and _sound_cooldown <= 0.0:
		_sound_cooldown = SOUND_COOLDOWN
		Sfx.play_at(self, dodge_sound, feet, SOUND_VOLUME_DB)


## The hop: across in DODGE_TIME with a small jump, then DODGE_PAUSE standing.
func _hop(delta: float) -> void:
	_dodge_left = maxf(0.0, _dodge_left - delta)
	var t := 1.0 - _dodge_left / DODGE_TIME
	_side = _dodge_from.lerp(_dodge_to, 1.0 - (1.0 - t) * (1.0 - t))
	_sprite.position.y = FEET_OFFSET.y - sin(t * PI) * _hop_height
	if _dodge_left <= 0.0:
		_sprite.position.y = FEET_OFFSET.y
		_stand_left = maxf(_stand_left, _stand_after_hop)


## Offset from the route that passes the nearest player in the way AVOID_SIDE px beside it (zero if
## nobody is in the way or the villager is not walking). Keeps the side once chosen.
func _avoid_offset(players: Array[Dictionary], route_feet: Vector2, walk_direction: Vector2) -> Vector2:
	if walk_direction == Vector2.ZERO:
		_avoid_sign = 0
		return Vector2.ZERO
	var across := walk_direction.orthogonal()
	var blocker: Dictionary = {}
	var best := INF
	for seen: Dictionary in players:
		var relative: Vector2 = (seen["feet"] as Vector2) - route_feet
		var ahead := relative.dot(walk_direction)
		if ahead > -AVOID_BEHIND and ahead < AVOID_RADIUS and absf(relative.dot(across)) < AVOID_SIDE and ahead < best:
			best = ahead
			blocker = seen
	if blocker.is_empty():
		_avoid_sign = 0
		return Vector2.ZERO
	var lateral := ((blocker["feet"] as Vector2) - route_feet).dot(across)
	if _avoid_sign == 0:
		var first := -1 if lateral > 0.0 else 1
		var ahead_spot := route_feet + walk_direction * AVOID_RADIUS * 0.5
		for sign_try: int in [first, -first]:
			if is_spot_free(ahead_spot + across * (lateral + sign_try * AVOID_SIDE)):
				_avoid_sign = sign_try
				break
		if _avoid_sign == 0:
			# No way around: wait a moment until the player moves on.
			_stand_left = DODGE_PAUSE * 0.5
			return _side
	return across * (lateral + _avoid_sign * AVOID_SIDE)


## Some player's feet closer than distance to point.
static func _player_near(players: Array[Dictionary], point: Vector2, distance: float) -> bool:
	for seen: Dictionary in players:
		if point.distance_to(seen["feet"]) < distance:
			return true
	return false


## No solid body (house, fence, prop, bush tile) at a feet position (global, world layer).
func is_spot_free(spot: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = SPOT_RADIUS
	query.shape = shape
	query.transform = Transform2D(0.0, spot)
	query.collision_mask = PhysicsLayers.WORLD
	query.collide_with_areas = false
	return space.intersect_shape(query, 1).is_empty()


func _global_feet(local_origin: Vector2) -> Vector2:
	var parent := get_parent() as Node2D
	var origin := parent.to_global(local_origin) if parent != null else local_origin
	return origin + FEET_OFFSET


## "?" above the head: rises a little and fades out.
func _show_huh() -> void:
	if _huh == null:
		_huh = Label.new()
		_huh.name = "Huh"
		_huh.text = "?"
		_huh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_huh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_huh.add_theme_font_override("font", UiKit.bold_font())
		_huh.add_theme_font_size_override("font_size", 18)
		_huh.add_theme_color_override("font_color", HUH_COLOR)
		_huh.add_theme_color_override("font_outline_color", HUH_OUTLINE)
		_huh.add_theme_constant_override("outline_size", 5)
		_huh.size = Vector2(24, 26)
		# Above roofs and props in front of it (the y-sort would hide it behind them).
		_huh.z_index = 10
		add_child(_huh)
	_huh_left = HUH_TIME
	_huh.visible = true
	_place_huh()


func _update_huh(delta: float) -> void:
	if _huh == null or not _huh.visible:
		return
	_huh_left -= delta
	if _huh_left <= 0.0:
		_huh.visible = false
		return
	_place_huh()


func _place_huh() -> void:
	var head := _head_y
	var t := 1.0 - _huh_left / HUH_TIME
	# The glyph sits a few px above the bottom of its label: overlap them, so it floats just above the head.
	_huh.position = Vector2(-_huh.size.x * 0.5, head - _huh.size.y + HUH_GLYPH_GAP - t * HUH_RISE)
	_huh.modulate.a = clampf(_huh_left / 0.25, 0.0, 1.0)


func _set_walking(walking: bool) -> void:
	var animation := &"walk" if walking and _has_walk else &"idle"
	if not walking and _reaction_left > 0.0 and _sprite.sprite_frames.has_animation(&"react"):
		animation = &"react"
	if _sprite.animation != animation:
		_sprite.play(animation)
	if not walking:
		_sprite.position.y = FEET_OFFSET.y
