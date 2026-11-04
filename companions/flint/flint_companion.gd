class_name FlintCompanion
extends Node2D
## Flint (D-175, D-194; KONZEPT §7.1; the team member named the companion Flint on 22.10.2026,
## code ID flint): the small living candle that goes everywhere with his players. One Flint per
## world for the whole group (WK13, D-225): a child "Flint" of the world, every player of that world
## joins him (attach_to). Alone he keeps loosely near his player, falls in behind and beside him when
## he walks, never sits on the walking line or in the swing, stays on the player's side of walls
## (rays against PhysicsLayers.WORLD), roams a little around his spot (FlintRoam, optics) and fades
## while he would cover an enemy. In a group the same spot is built around the group point
## (FlintGroup: middle of the standing players pulled towards the one furthest behind, the bigger part
## when they split up) instead of around one player, with the lead player (the host's where he is in
## that part) for aim, light, side view and sorting; he keeps clear of every member's picture. Only
## the host (or a single machine) decides: a client draws him from the host's spot (net_driven,
## NetFlint), like enemies. The look (WK2: hat, flame colour) is the host's (get_look_owner).
## Each player's light circle sits at that player's figure
## (D-212, LightQuery); Flint's flame adds only a small warm glow (FlintGlow, a LightSource that never
## counts as light for rules) that fades out under the rock of a tunnel (feedback #118a38da: no glow
## through the tunnel), and his flame is where spells start (get_light_center).
## He looks like the website's Flint (D-217): art from tools/generate_flint.py, a soft breathing warm
## glow behind him (FlintAura, the FlintGlow light breathes along) and sparks rising from his flame
## (FlintSparks, none on "Lichteffekte: Niedrig"), both children of his sprite at the frame's flame
## anchor; optics only.
## Decisions are separate from looks (D-088): where Flint hovers follows only the players' state
## (position, velocity, aim, light radius) and the room's walls through FlintGroup and FlintFollow,
## without randomness; only the free roaming around it (FlintRoam) and the bob are local optics.
## FlintMood picks the animation from existing signals and state (EventBus.room_completed, the
## world's room_activated, the members' revived/blinded, downed, darkness, village rest); bobbing and
## blinking use randf() (optics only). No attack, no collision, never catches hits.
## He flies (feedback 22.10.2026 #6f0d0ebf "Flint ist dahinter", #704b64b1): his picture is a node of
## its own in the world (FlintPicture), sorted there as if it stood SORT_LIFT px in front of the
## group point (alone: his player's centre). So he is drawn over floor props, grave stones, figures
## and enemies around his players, while walls and rock that cover them (the passage rock of a gate
## on DoorView.LINTEL_Z, a house the player stands behind) cover him too. Over an enemy he turns
## see-through; his picture never overlaps a member's (FlintFollow).
## Usage: FlintCompanion.attach_to(player) once per spawned player (idempotent; the world's Flint is
## created on first use, WorldController creates it with the world), FlintCompanion.of(player).

const NODE_NAME := &"Flint"
## TESTWERTE
## Darker than this drawn light radius (extra-dark room 190, blinded 110) Flint is afraid and huddles.
const DARK_FEAR_RADIUS := 200.0
## Fear when a boss room opens (s).
const BOSS_FEAR_TIME := 3.0
## In the village Flint dozes off when his player rests this long (s).
const SLEEP_DELAY := 6.0
## Joy only for rooms that took a while (no cheering for rooms that open at once).
const JOY_MIN_ROOM_TIME := 2.0
## Secret niche closer than this makes Flint curious (px); he leans and drifts a little towards it.
const CURIOUS_RANGE := 160.0
const CURIOUS_DRIFT := 6.0
const CURIOUS_TILT := 0.18
## Moving faster than this plays the move animation (px/s).
const MOVE_ANIMATION_SPEED := 40.0
## Hover bob (optics): amplitude in px, period about 1.6 s with a little random spread.
const BOB_AMPLITUDE := 2.0
const BOB_SPEED := 3.9
## An enemy body this close to Flint's body (px) makes him see-through.
const ENEMY_CLEAR_RADIUS := 30.0
const COVERING_ALPHA := 0.35
const ALPHA_SPEED := 6.0
## Shadow on the floor under the hovering candle.
const SHADOW_RADIUS := 7.0
const ENEMY_GROUP := &"enemies"
## TESTWERT: Flint's picture sorts as if it stood this far below the player's centre (Player
## FEET_OFFSET 16 plus a tile and a half): grave stones, props and enemies near him are drawn under
## him, a building or rock mass the player stands behind still covers him.
const SORT_LIFT := 48.0
## On his flight into the explanation corner he is drawn over the world (under the room veils, z 20).
const EXCURSION_Z := 10
const PICTURE_NAME := "FlintPicture"
## TESTWERTE (D-212): the warm glow of his flame, optics only (counts_as_light stays off).
const GLOW_NAME := &"FlintGlow"
const GLOW_RADIUS := 56.0
const GLOW_INTENSITY := 0.55
const GLOW_FLICKER := 0.08
## TESTWERT (D-217): the glow's strength at the low point of its breath (share of GLOW_INTENSITY).
const GLOW_BREATH_LOW := 0.8
## TESTWERTE (#118a38da): the glow is fully out when his flame is under the rock of a tunnel and
## comes back over this distance (px) from the hidden passage; how fast it follows (1/s).
const GLOW_ROOF_FADE := 40.0
const GLOW_ROOF_SPEED := 6.0
## TESTWERTE (optics): how freely he roams walking at full speed, scared and beside a downed player
## (1 = as at rest); roaming slower than this (px/s) does not turn him round.
const ROAM_WALKING := 0.3
const ROAM_SCARED := 0.3
const ROAM_DOWNED := 0.25
const ROAM_FACE_SPEED := 8.0
## TESTWERT (D-225 §3): a client glides to the host's spot this fast (1/s, exponential; the host
## sends NetFlint.SEND_RATE times a second).
const NET_SHARPNESS := 12.0

## The lead player Flint keeps to: alone his one player; in a group the host's player when he is in
## the part Flint follows, else the first member of that part (aim, light, side view, sorting).
## null while nobody is in the world.
var player: Player = null
## Whose look Flint wears and whose part wins a tie (D-225 §2, §6): the host's player. NetFlint sets
## it; by default the first member (the primary player of a local game, the host's on the host).
var host_player: Player = null
## A client of a networked world (D-225 §3): the host moves Flint (apply_net_follow), this machine
## only draws him and his optics.
var net_driven := false

## Every player of the world in join order (the primary player first).
var _members: Array[Player] = []
## The group point Flint's spot is built around (alone: the player's position) and whether it is set.
var _anchor := Vector2.ZERO
var _anchor_set := false
## The host's latest spot (net_driven), Vector2.INF until the first one came.
var _net_follow := Vector2.INF
## Excursion holders (FlintExcursion ids): with several local players each guide flies the one Flint;
## he lands when the last one let go.
var _excursion_holders: Dictionary[int, bool] = {}

var _art: FlintArt = null
## Holds the sprite in the player's world (the y-sort position, see SORT_LIFT).
var _picture: Node2D = null
var _sprite: AnimatedSprite2D = null
var _shadow: DropShadow = null
## The warm glow at his flame (optics only, D-212).
var _glow: LightSource = null
## Soft glow behind and sparks over his sprite (D-217, optics only).
var _aura: FlintAura = null
var _sparks: FlintSparks = null
## Flint's pivot in global coordinates (the decision; position is derived from it).
var _follow := Vector2.ZERO
var _velocity := Vector2.ZERO
var _side := 1.0
var _facing_left := false
var _mood := FlintMood.Mood.IDLE
var _one_shot := -1
var _one_shot_left := 0.0
var _fear_left := 0.0
var _rest_time := 0.0
var _room: Node = null
var _room_time := 0.0
var _bob_phase := 0.0
var _bob_speed := BOB_SPEED
var _alpha := 1.0
## Bob and curiosity lean of the picture (optics).
var _sprite_offset := Vector2.ZERO
## Optics of an excursion ("Flint erklärt", WK8): the picture leaves its spot, grows and fades while
## the decisions (follow spot, light centre) stay with the player.
var _excursion_offset := Vector2.ZERO
var _excursion_scale := 1.0
var _excursion_alpha := 1.0
var _on_excursion := false
## Free hovering around his spot (optics, FlintRoam) and its speed (facing).
var _roam := FlintRoam.new()
var _roam_velocity := Vector2.ZERO
## Which wall alternative the spot uses (0 = none; FlintFollow.wall_alternatives index + 1), kept
## while it stays free so he does not swap sides at every wall.
var _wall_pick := 0
## Share of the glow left under tunnel rock (1 = in the open).
var _glow_open := 1.0


## Joins target to the one Flint of its world (D-225), creating him on first use; idempotent. Call
## once per spawned player. A player without a world gets a Flint of his own as his child.
static func attach_to(target: Player) -> FlintCompanion:
	if target == null or not is_instance_valid(target):
		return null
	var existing := of(target)
	if existing != null:
		return existing
	var world := target.get_parent()
	var flint := for_world(world if world != null else target)
	if flint != null:
		flint.join(target)
	return flint


## The Flint of world (child NODE_NAME), created on first use. WorldController creates it with the
## world, before the players come, so a networked world has it (and its NetFlint) on every machine.
static func for_world(world: Node) -> FlintCompanion:
	if world == null or not is_instance_valid(world):
		return null
	var existing := world.get_node_or_null(NodePath(NODE_NAME)) as FlintCompanion
	if existing != null and not existing.is_queued_for_deletion():
		return existing
	var flint := FlintCompanion.new()
	flint.name = NODE_NAME
	world.add_child(flint)
	return flint


## The Flint that goes with a player (the one of his world, if he joined it), or null (a player
## without Flint lights from his own position).
static func of(target: Node) -> FlintCompanion:
	if target == null or not is_instance_valid(target):
		return null
	var flint := target.get_node_or_null(NodePath(NODE_NAME)) as FlintCompanion
	if _usable(flint) and flint.has_member(target):
		return flint
	var world := target.get_parent()
	flint = world.get_node_or_null(NodePath(NODE_NAME)) as FlintCompanion if world != null else null
	return flint if _usable(flint) and flint.has_member(target) else null


static func _usable(flint: FlintCompanion) -> bool:
	return flint != null and is_instance_valid(flint) and not flint.is_queued_for_deletion()


func _init() -> void:
	_art = FlintArt.get_art()
	_bob_phase = randf() * TAU
	_bob_speed = BOB_SPEED * (0.85 + randf() * 0.3)


func _ready() -> void:
	_build_picture()
	_shadow = DropShadow.attach(self, SHADOW_RADIUS, FlintFollow.HOVER_HEIGHT)
	_build_glow()
	EventBus.room_completed.connect(_on_room_completed)
	var world := get_parent()
	if world != null and world.has_signal(&"room_activated"):
		world.connect(&"room_activated", _on_room_activated)
	snap()


## Takes target into the group (idempotent): his revive cheers Flint, his blinding scares him. The
## first member puts Flint at his spot at once.
func join(target: Player) -> void:
	if target == null or not is_instance_valid(target) or _members.has(target):
		return
	_prune_members()
	var first := _members.is_empty()
	_members.append(target)
	target.revived.connect(react.bind(FlintMood.Mood.JOY))
	target.blinded.connect(_on_blinded)
	if first:
		_anchor_set = false
		snap()


func has_member(target: Node) -> bool:
	return target is Player and _members.has(target)


## Every player of the group (freed ones dropped), in join order.
func get_members() -> Array[Player]:
	_prune_members()
	return _members.duplicate()


## More than one player shares this Flint.
func is_group() -> bool:
	return _members.size() > 1


## The player whose look Flint wears (WK2 hat and flame colour, D-225 §6): the host's.
func get_look_owner() -> Player:
	if host_player != null and is_instance_valid(host_player) and _members.has(host_player):
		return host_player
	_prune_members()
	return _members[0] if not _members.is_empty() else null


## The group point Flint's spot is built around (alone: his player's position).
func get_anchor() -> Vector2:
	return _anchor_now()


## Client side of a networked world (NetFlint): the host decides, this machine draws.
func set_net_driven(on: bool) -> void:
	net_driven = on
	if not on:
		_net_follow = Vector2.INF


## The host's spot of Flint (his pivot in global px, NetFlint). A jump farther than SNAP_DISTANCE puts
## him there at once, else he glides there (NET_SHARPNESS).
func apply_net_follow(spot: Vector2) -> void:
	_net_follow = spot
	if _follow.distance_to(spot) > FlintFollow.SNAP_DISTANCE:
		_follow = spot
		_roam.reset(true)


## Puts Flint at his spot at once (spawn, after a teleport).
func snap() -> void:
	if not _update_lead():
		return
	_anchor = _group_target()
	_anchor_set = true
	_velocity = Vector2.ZERO
	if net_driven and _net_follow != Vector2.INF:
		_follow = _net_follow
	else:
		_follow = _clear_of_members(_anchor + _wall_safe(_target_offset()))
	_roam.reset(true)
	_roam_velocity = Vector2.ZERO
	global_position = _follow
	_glow_open = _glow_open_target()
	_update_picture()


## The sprite showing Flint (it lives in the player's world, see SORT_LIFT).
func get_sprite() -> AnimatedSprite2D:
	_ensure_picture()
	return _sprite


## The warm glow at Flint's flame: a LightSource that never counts as light (D-212).
func get_glow() -> LightSource:
	return _glow


## The soft breathing glow behind his sprite (D-217).
func get_aura() -> FlintAura:
	_ensure_picture()
	return _aura


## The sparks rising from his flame (D-217).
func get_sparks() -> FlintSparks:
	_ensure_picture()
	return _sparks


## The node that places Flint's picture in the world's y-sort.
func get_picture() -> Node2D:
	_ensure_picture()
	return _picture


## Flint's flame at his (unbobbed) spot in global px: where his spells start (SpellEffects). Not the
## centre of the player's light circle any more (D-212: that is the player's figure).
func get_light_center() -> Vector2:
	return _current_follow() + _flame_offset()


## Flint's pivot (bottom of the candle) in global px, without the optical bob.
func get_follow_position() -> Vector2:
	return _follow


func get_mood() -> FlintMood.Mood:
	return _mood


func get_art() -> FlintArt:
	return _art


## Excursion (WK8, FlintExcursion drives it): Flint's picture is drawn offset px away from his spot,
## scale_factor times his size and with alpha, e.g. on his way into the explanation corner. Optics
## only: his follow spot and the light centre stay with the player (LightQuery), so nobody loses
## light while Flint explains. holder (a FlintExcursion id, 0 = none): with several local players
## every guide may fly the one Flint; clear_excursion lands him when the last holder let go.
func set_excursion(offset: Vector2, scale_factor: float, alpha: float, holder := 0) -> void:
	if holder != 0:
		_excursion_holders[holder] = true
	_on_excursion = true
	_excursion_offset = offset
	_excursion_scale = maxf(0.01, scale_factor)
	_excursion_alpha = clampf(alpha, 0.0, 1.0)
	_apply_excursion()


## Back to the normal picture at his spot (once no other holder still flies him).
func clear_excursion(holder := 0) -> void:
	_excursion_holders.erase(holder)
	if not _excursion_holders.is_empty():
		return
	_on_excursion = false
	_excursion_offset = Vector2.ZERO
	_excursion_scale = 1.0
	_excursion_alpha = 1.0
	_apply_excursion()


func is_on_excursion() -> bool:
	return _on_excursion


## Where Flint's picture is drawn right now (global px of his pivot, excursion and bob included).
func get_picture_position() -> Vector2:
	if _sprite == null or not is_instance_valid(_sprite) or not _sprite.is_inside_tree():
		return global_position + _excursion_offset
	return _sprite.global_position


## A one-shot reaction from outside (hooks: rank up -> JOY, spell -> CAST or PULSE). A weaker
## reaction does not cut off a stronger one that is still playing.
func react(mood: FlintMood.Mood) -> void:
	if not FlintMood.replaces(_one_shot if _one_shot_left > 0.0 else -1, mood):
		return
	_one_shot = mood
	_one_shot_left = _animation_length(FlintMood.animation_for(mood))
	if _sprite != null and is_instance_valid(_sprite) and _sprite.animation == FlintMood.animation_for(mood):
		# The same reaction again starts over.
		_sprite.stop()


## Shows animation (falls back to idle when the art has no such strip).
func play(animation: StringName) -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var name_to_play := animation if _art.has_animation(animation) else &"idle"
	if _sprite.animation != name_to_play or not _sprite.is_playing():
		_sprite.play(name_to_play)


func _process(delta: float) -> void:
	if not _update_lead():
		# Nobody in the world (yet): Flint waits out of sight.
		if _picture != null and is_instance_valid(_picture):
			_picture.visible = false
		return
	# The old world may have freed the picture (the player moved on): build it again.
	_ensure_picture()
	_track_anchor(delta)
	_tick(delta)
	_mood = FlintMood.decide(_gather_facts())
	if net_driven and _net_follow != Vector2.INF:
		# A client: the host decided the spot (D-225 §3), here he only glides there.
		_follow = _follow.lerp(_net_follow, 1.0 - exp(-NET_SHARPNESS * delta))
	else:
		var anchor := _anchor
		var stepped := FlintFollow.step_around(_follow - anchor, _wall_safe(_target_offset()), delta)
		# Trailing never takes the light away from the player (dash, blinded) nor puts Flint on him,
		# and never carries him through a wall.
		_follow = _clear_of_members(anchor + _short_of_walls(FlintFollow.settle(stepped, _flame_offset(), _lit_radius())))
	global_position = _follow + _roam_step(delta)
	_glow_open = move_toward(_glow_open, _glow_open_target(), GLOW_ROOF_SPEED * delta)
	_update_look(delta)


## Flint's spot for the light: _follow, or already the new spot when the player moved on since
## Flint's last frame (fall reset, teleport, a frame order where gameplay asks first), so the light
## never lags behind the player. A group's point glides, a client's spot is the host's: _follow.
func _current_follow() -> Vector2:
	if player == null or not is_instance_valid(player) or net_driven or is_group():
		return _follow
	var anchor := player.global_position
	if _follow.distance_to(anchor) > FlintFollow.SNAP_DISTANCE:
		return anchor + _wall_safe(_target_offset())
	return anchor + FlintFollow.settle(_follow - anchor, _flame_offset(), _lit_radius())


# --- The group (D-225) ---

## Drops freed members.
func _prune_members() -> void:
	for i in range(_members.size() - 1, -1, -1):
		if not is_instance_valid(_members[i]) or _members[i].is_queued_for_deletion():
			_members.remove_at(i)


## Members in the tree (a player leaving the world does not count).
func _present() -> Array[Player]:
	var result: Array[Player] = []
	# Untyped loop: a member freed this frame must not be assigned to a typed variable.
	for node: Variant in _members:
		if is_instance_valid(node) and (node as Player).is_inside_tree():
			result.append(node as Player)
	return result


## The members the group point is built from: the standing ones (alive, not downed), all present
## ones when nobody stands.
func _standing() -> Array[Player]:
	var present := _present()
	var result: Array[Player] = []
	for member in present:
		if member.is_alive() and not member.is_downed():
			result.append(member)
	return result if not result.is_empty() else present


## Picks the lead player (see player). False when nobody is there.
func _update_lead() -> bool:
	_prune_members()
	var present := _present()
	if present.is_empty():
		player = null
		return false
	if present.size() == 1:
		player = present[0]
		return true
	var standing := _standing()
	var part := FlintGroup.main_part(_positions(standing), _host_index(standing))
	var host := get_look_owner()
	player = standing[part[0]]
	for index in part:
		if standing[index] == host:
			player = host
	return true


## Where the group point wants to be (FlintGroup.target): alone the player's position.
func _group_target() -> Vector2:
	if not is_group():
		return player.global_position
	var standing := _standing()
	var velocities := PackedVector2Array()
	for member in standing:
		velocities.append(member.velocity)
	var goal := FlintGroup.target(_positions(standing), velocities, _host_index(standing))
	return goal if goal != Vector2.INF else player.global_position


## The group point now: alone the player's position, in a group the gliding point.
func _anchor_now() -> Vector2:
	if player == null or not is_instance_valid(player):
		return _anchor
	if not is_group() or not _anchor_set:
		return player.global_position
	return _anchor


static func _positions(players: Array[Player]) -> PackedVector2Array:
	var result := PackedVector2Array()
	for member in players:
		result.append(member.global_position)
	return result


func _host_index(players: Array[Player]) -> int:
	return maxi(0, players.find(get_look_owner()))


## spot (global) pushed out of every member's picture (a group's point has no figure of its own).
func _clear_of_members(spot: Vector2) -> Vector2:
	if not is_group():
		return spot
	for member in _present():
		var offset := spot - member.global_position
		if FlintFollow.overlaps_player(offset):
			spot = member.global_position + FlintFollow.push_out(offset)
	return spot


## True if Flint's picture at the global spot would come too close to a member's picture.
func _overlaps_member(spot: Vector2) -> bool:
	for member in _present():
		if FlintFollow.overlaps_player(spot - member.global_position):
			return true
	return false


## Moves the group point (alone: onto the player) and estimates how the group walks.
func _track_anchor(delta: float) -> void:
	var previous := _anchor
	var goal := _group_target()
	if not _anchor_set:
		previous = goal
		_anchor = goal
	elif is_group():
		_anchor = FlintGroup.glide(_anchor, goal, delta)
	else:
		_anchor = goal
	_anchor_set = true
	var moved := _anchor - previous
	if moved.length() > FlintFollow.SNAP_DISTANCE:
		# Fall reset, room change, teleport: he arrives at his spot, not out on a trip.
		_roam.reset(true)
	_velocity = FlintFollow.estimate_velocity(_velocity, moved, delta)
	_rest_time = _rest_time + delta if moved.length() < 0.5 else 0.0
	_side = FlintFollow.pick_side(_side, player.get_aim_direction())


func _tick(delta: float) -> void:
	_fear_left = maxf(0.0, _fear_left - delta)
	_one_shot_left = maxf(0.0, _one_shot_left - delta)
	_room_time += delta


func _gather_facts() -> FlintMood.Facts:
	var facts := FlintMood.Facts.new()
	# In a group a member down makes him sad; he stays with the standing ones (D-225).
	facts.downed = _any_member_downed()
	facts.moving = _velocity.length() > MOVE_ANIMATION_SPEED
	facts.afraid = _is_afraid()
	facts.sleepy = GameManager.get_phase() == GameManager.Phase.VILLAGE and _rest_time >= SLEEP_DELAY
	facts.curious = _secret_direction() != Vector2.ZERO
	facts.one_shot = _one_shot if _one_shot_left > 0.0 else -1
	return facts


## Boss room just opened, blinded or a dark room: decided from shared game state only.
func _is_afraid() -> bool:
	if _fear_left > 0.0:
		return true
	return GameManager.get_phase() == GameManager.Phase.DUNGEON and LightQuery.get_player_radius(player) < DARK_FEAR_RADIUS


func _target_offset() -> Vector2:
	var huddle := _is_afraid() or player.is_downed()
	return FlintFollow.target_offset(_velocity, _side, _lit_radius(), _flame_offset(), huddle, player.is_side_view(), player.get_aim_direction())


func _lit_radius() -> float:
	return LightQuery.player_lit_radius(LightQuery.get_player_radius(player))


func _flame_offset() -> Vector2:
	return _art.anchor_offset(FlintArt.ANCHOR_FLAME, &"idle", 0, _facing_left)


## Looks only: animation, facing, bob, curiosity lean, see-through over enemies.
func _update_look(delta: float) -> void:
	play(FlintMood.animation_for(_mood))
	var secret := _secret_direction() if _mood == FlintMood.Mood.CURIOUS else Vector2.ZERO
	if secret != Vector2.ZERO:
		_facing_left = secret.x < 0.0
	elif absf(_velocity.x) > MOVE_ANIMATION_SPEED:
		_facing_left = _velocity.x < 0.0
	elif absf(_roam_velocity.x) > ROAM_FACE_SPEED:
		# Roaming at rest he looks where he drifts.
		_facing_left = _roam_velocity.x < 0.0
	else:
		_facing_left = player.get_aim_direction().x < 0.0
	_sprite.flip_h = _art.needs_flip(_facing_left)
	_bob_phase = fmod(_bob_phase + _bob_speed * delta, TAU)
	var bob := sin(_bob_phase) * BOB_AMPLITUDE if _mood != FlintMood.Mood.SLEEP else sin(_bob_phase * 0.5) * BOB_AMPLITUDE * 0.5
	var drift := secret * CURIOUS_DRIFT
	if FlintFollow.overlaps_player(global_position - _anchor_now() + drift) or (is_group() and _overlaps_member(global_position + drift)):
		# Leaning towards a secret never puts him on his player.
		drift = Vector2.ZERO
	_sprite_offset = Vector2(0.0, bob) + drift
	# The lean stands in for the missing curious strip (SPRITES_V13 part C).
	_sprite.rotation = 0.0 if _art.has_animation(&"curious") else secret.x * CURIOUS_TILT
	var target_alpha := COVERING_ALPHA if _covers_enemy() else 1.0
	_alpha = move_toward(_alpha, target_alpha, ALPHA_SPEED * delta)
	if _shadow != null and is_instance_valid(_shadow):
		# His floor shadow belongs to the top-down view (feedback #e0486234): none in the side view.
		_shadow.self_modulate.a = 0.0 if player.is_side_view() else 1.0
	_apply_excursion()


## Size, alpha and shadow of the picture (the excursion on top of the see-through over enemies).
func _apply_excursion() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE * _excursion_scale
	_sprite.modulate.a = _alpha * _excursion_alpha
	_sprite.z_index = EXCURSION_Z if _on_excursion else 0
	if _shadow != null:
		# The shadow stays on the floor: it hides while Flint is off on his excursion.
		_shadow.visible = not _on_excursion
	_update_picture()


# --- The picture in the world (SORT_LIFT) ---

## Builds the picture node and its sprite (again, when the old world freed them).
func _build_picture() -> void:
	_picture = Node2D.new()
	_picture.name = PICTURE_NAME
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = _art.frames
	_sprite.offset = SpriteStrip.pivot_offset(_art.frame_size, _art.pivot)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.add_child(_sprite)
	_sprite.animation_finished.connect(_on_animation_finished)
	_aura = FlintAura.new()
	_sprite.add_child(_aura)
	_sparks = FlintSparks.new()
	_sprite.add_child(_sparks)
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE * _excursion_scale
	_sprite.modulate.a = _alpha * _excursion_alpha
	play(&"idle")


func _ensure_picture() -> void:
	if _picture == null or not is_instance_valid(_picture) or _sprite == null or not is_instance_valid(_sprite):
		_build_picture()


## Puts the picture into the player's world right after the player (the y-sort decides; in a
## world without y-sort the tree order draws it over the player like a child) and moves it to
## Flint's spot. Optics only.
func _update_picture() -> void:
	if player == null or not is_instance_valid(player):
		return
	_ensure_picture()
	if not is_inside_tree():
		return
	var world := player.get_parent()
	# A world still setting up its children takes the picture on Flint's next frame.
	if world != null and _picture.get_parent() != world and world.is_node_ready():
		if _picture.get_parent() != null:
			_picture.get_parent().remove_child(_picture)
		world.add_child(_picture)
		world.move_child(_picture, player.get_index() + 1)
	_picture.visible = is_visible_in_tree()
	_picture.z_index = player.z_index
	var sort_at := Vector2(global_position.x, _anchor_now().y + SORT_LIFT)
	if _picture.is_inside_tree():
		_picture.global_position = sort_at
	else:
		_picture.position = sort_at
	_sprite.position = global_position - sort_at + _sprite_offset + _excursion_offset
	_place_shine()
	_update_glow()


## Glow and sparks sit on the flame of the frame shown (hops, flicker), in the sprite's art pixels.
func _place_shine() -> void:
	if _aura == null or not is_instance_valid(_aura):
		return
	var flame := _art.get_anchor(FlintArt.ANCHOR_FLAME, _sprite.animation, _sprite.frame) - _art.pivot
	if _sprite.flip_h:
		flame.x = -flame.x
	_aura.position = flame
	_sparks.position = flame


## Builds the glow at the flame (optics only: counts_as_light off, so no rule ever reads it).
func _build_glow() -> void:
	if _glow != null and is_instance_valid(_glow):
		return
	_glow = LightSource.new()
	_glow.name = GLOW_NAME
	_glow.radius = GLOW_RADIUS
	_glow.intensity = GLOW_INTENSITY
	_glow.flicker = GLOW_FLICKER
	_glow.color = LightPalette.WARM
	_glow.counts_as_light = false
	add_child(_glow)
	_update_glow()


## The glow follows the drawn flame (bob and excursion included) and fades with the picture.
func _update_glow() -> void:
	if _glow == null or not is_instance_valid(_glow):
		return
	_glow.position = _flame_offset() + _sprite_offset + _excursion_offset
	# It breathes with the aura (D-217).
	var breath := FlintShine.breath(_aura.time) if _aura != null and is_instance_valid(_aura) else 1.0
	_glow.intensity = GLOW_INTENSITY * _excursion_alpha * _glow_open * lerpf(GLOW_BREATH_LOW, 1.0, breath)
	_glow.radius = GLOW_RADIUS * lerpf(FlintShine.GLOW_SCALE_MIN, FlintShine.GLOW_SCALE_MAX, breath)


## Share of the glow wanted where his flame is drawn: 0 under tunnel rock, back to 1 over
## GLOW_ROOF_FADE px from the hidden passage. On his flight to the corner he is drawn over the world.
func _glow_open_target() -> float:
	if _on_excursion or _glow == null or not is_instance_valid(_glow) or not _glow.is_inside_tree():
		return 1.0
	return clampf(roof_distance(get_tree(), _glow.global_position) / GLOW_ROOF_FADE, 0.0, 1.0)


## Distance (px) from point to the nearest stretch of a tunnel passage where the rock hides a
## player (DoorView.get_hidden_rects; 0 inside), INF without a tunnel. Optics only.
static func roof_distance(tree: SceneTree, point: Vector2) -> float:
	var best := INF
	if tree == null:
		return best
	# Rock drawn over the figures (boss gate roof, lintels, #876edf4a): the glow is out there too.
	if DoorView.is_under_rock(tree, point):
		return 0.0
	for node in tree.get_nodes_in_group(DoorView.TUNNEL_GROUP):
		var view := node as DoorView
		if view == null or not view.is_inside_tree():
			continue
		var local := view.to_local(point)
		for rect: Rect2 in view.get_hidden_rects():
			var nearest := local.clamp(rect.position, rect.end)
			best = minf(best, nearest.distance_to(local))
	return best


# --- Roaming (optics) and walls (decision) ---

## One roaming step: how freely he roams now, the drawn picture kept off the player and out of
## walls. Returns the roam offset from his spot.
func _roam_step(delta: float) -> Vector2:
	var before := _roam.offset
	var hurry := _one_shot_left > 0.0 and (_one_shot == FlintMood.Mood.CAST or _one_shot == FlintMood.Mood.PULSE)
	_roam.update(delta, _roam_calm(), _accepts_roam_goal, hurry, player.is_side_view())
	var home := _follow - _anchor_now()
	var drawn := home + _roam.offset
	if FlintFollow.overlaps_player(drawn):
		_roam.offset = FlintFollow.push_out(drawn) - home
	if _roam.offset.length() > 1.0 and _wall_hit(home + _roam.offset) != Vector2.INF:
		# The player moved and a wall came between: drift home.
		_roam.reset()
	elif is_group() and _overlaps_member(_follow + _roam.offset):
		# A member walked into his trip: home again (never on anybody's picture).
		_roam.reset()
	_roam_velocity = (_roam.offset - before) / delta if delta > 0.0 else Vector2.ZERO
	return _roam.offset


## 1 at rest, less walking fast, scared or beside a downed player, 0 asleep or on an excursion.
func _roam_calm() -> float:
	if _on_excursion or _mood == FlintMood.Mood.SLEEP:
		return 0.0
	if player.is_downed():
		return ROAM_DOWNED
	if _is_afraid():
		return ROAM_SCARED
	var walking := clampf(_velocity.length() / FlintFollow.TRAIL_FULL_SPEED, 0.0, 1.0)
	return lerpf(1.0, ROAM_WALKING, walking)


## A roam goal (relative to his spot) is fine if there he stays off the player, on the leash, with
## his flame in the light and no wall between him and the player.
func _accepts_roam_goal(goal: Vector2) -> bool:
	var spot := _follow - _anchor_now() + goal
	if FlintFollow.overlaps_player(spot) or (is_group() and _overlaps_member(_follow + goal)):
		return false
	if (spot + FlintFollow.BODY_CENTER).length() > FlintFollow.LEASH_DISTANCE:
		return false
	if (spot + _flame_offset()).length() > FlintFollow.light_reach(_lit_radius()):
		return false
	return _wall_hit(spot) == Vector2.INF


## offset (relative to the player) if no wall stands between it and the player, else the first free
## alternative (the other side, behind his head, in front of his feet), else cut short of the wall.
func _wall_safe(offset: Vector2) -> Vector2:
	var hit := _wall_hit(offset)
	if hit == Vector2.INF:
		_wall_pick = 0
		return offset
	var options := FlintFollow.wall_alternatives(offset)
	var order: Array[int] = [0, 1, 2]
	if _wall_pick > 0:
		order.erase(_wall_pick - 1)
		order.push_front(_wall_pick - 1)
	for index in order:
		var option := FlintFollow.settle(options[index], _flame_offset(), _lit_radius())
		if _wall_hit(option) == Vector2.INF:
			_wall_pick = index + 1
			return option
	_wall_pick = 0
	return FlintFollow.short_of_wall(offset, hit - _anchor_now(), player.is_side_view())


## offset cut short of a wall between it and the player (his trailing never goes through one).
func _short_of_walls(offset: Vector2) -> Vector2:
	var hit := _wall_hit(offset)
	if hit == Vector2.INF:
		return offset
	return FlintFollow.short_of_wall(offset, hit - _anchor_now(), player.is_side_view())


## Global point where a wall (PhysicsLayers.WORLD) cuts the ray from the player to Flint at offset
## (FlintFollow.wall_ray), Vector2.INF when the way is free or there is no physics world.
func _wall_hit(offset: Vector2) -> Vector2:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return Vector2.INF
	var world := player.get_world_2d()
	if world == null:
		return Vector2.INF
	var ray := FlintFollow.wall_ray(offset, player.is_side_view())
	var anchor := _anchor_now()
	var query := PhysicsRayQueryParameters2D.create(anchor + ray[0], anchor + ray[1], PhysicsLayers.WORLD)
	query.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector2.INF


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_TREE:
			# Flint leaves his world (or is freed with it): the picture waits hidden until
			# _update_picture shows it again.
			if _picture != null and is_instance_valid(_picture):
				_picture.visible = false
		NOTIFICATION_PREDELETE:
			if _picture != null and is_instance_valid(_picture):
				_picture.queue_free()


## Unit direction to a closed secret niche of the current room within CURIOUS_RANGE, else zero.
func _secret_direction() -> Vector2:
	if _room == null or not is_instance_valid(_room):
		return Vector2.ZERO
	var niche := SecretNiche.of(_room)
	if niche == null or niche.is_open:
		return Vector2.ZERO
	var to_niche := niche.get_crack_position() - _anchor_now()
	if to_niche.length() > CURIOUS_RANGE or to_niche == Vector2.ZERO:
		return Vector2.ZERO
	return to_niche.normalized()


func _covers_enemy() -> bool:
	var body := global_position + FlintFollow.BODY_CENTER
	for node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var enemy := node as Node2D
		if enemy != null and is_instance_valid(enemy) and enemy.global_position.distance_to(body) < ENEMY_CLEAR_RADIUS:
			return true
	return false


func _animation_length(animation: StringName) -> float:
	var name_to_check := animation if _art.has_animation(animation) else &"idle"
	var frames := _art.frames
	var speed := frames.get_animation_speed(name_to_check)
	return frames.get_frame_count(name_to_check) / maxf(0.1, speed)


func _on_animation_finished() -> void:
	# A one-shot strip ended: let the held mood take over at once.
	if FlintMood.is_one_shot(_mood):
		_one_shot_left = 0.0


func _on_room_completed(_room_index: int) -> void:
	if _room == null or _room_time >= JOY_MIN_ROOM_TIME:
		react(FlintMood.Mood.JOY)


func _on_room_activated(room: Node) -> void:
	_room = room
	_room_time = 0.0
	var room_type: Variant = room.get(&"room_type")
	if room_type == RoomSequence.RoomType.BOSS:
		_fear_left = maxf(_fear_left, BOSS_FEAR_TIME)
	if room.has_method(&"is_campfire") and room.is_campfire():
		react(FlintMood.Mood.PULSE)


## A member is down (alone: his player).
func _any_member_downed() -> bool:
	for member in _present():
		if member.is_downed():
			return true
	return player != null and is_instance_valid(player) and player.is_downed()


func _on_blinded(duration: float) -> void:
	_fear_left = maxf(_fear_left, duration)
