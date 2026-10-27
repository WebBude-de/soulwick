class_name BountyFlight
extends Node
## The crowned one of "Jagd" (RAEUME §3.8; before "Kopfgeld", D-114). A child
## node of that enemy: it wears a gold crown; once it sees a player (range and free line) it stops
## fighting and flees. The escape hole opens over HuntRules.CATCH_TIME seconds; until its last seconds
## he zigzags away from the players between the pillars (evade_points), then he runs for the hole and
## jumps in once it is open. Killed before that = caught.
## While fleeing this node drives the enemy (its own AI is paused): path over the room navigation
## (EnemyNavigation), walk animation, no attacks of its own AI. Decisions (spot, escape) emit
## signals; the mode places the hole and removes the escaped enemy.
## Cornered (no spot leads away) with a player right next to him, he strikes back once (D-206): a
## red circle and his attack animation announce it for DEFENSE_WIND_UP seconds, then one attack
## instance (own Hitbox, own hit ID, D-020) deals little damage with knockback; I-frames and the dash
## protect as always (D-017). Then DEFENSE_COOLDOWN. Only the host runs this node (clients get the
## enemy as a puppet; the telegraph circle travels with the enemy snapshot).

signal spotted(flight: BountyFlight)
signal escaped(flight: BountyFlight)

enum State { WATCHING, FLEEING, JUMPING, ESCAPED, CAUGHT }
## His strike back in the corner: wind-up (telegraph), strike (hitbox active), none.
enum Defense { NONE, WIND_UP, STRIKE }

const NODE_NAME := &"BountyFlight"
const CROWN_HEIGHT := 6.0
const CROWN_BOB := 2.0
const BLINK_SPEED := 8.0
## A zigzag spot must lie at least this much farther from the nearest player than he stands now.
const EVADE_GAIN := 16.0  # TESTWERT
## The straight way to a spot keeps this far from every player (or as far as he is now when a player
## is closer), minus the slack.
const EVADE_PASS_DISTANCE := 64.0  # TESTWERT
const EVADE_PASS_SLACK := 4.0
## Strike back (D-206): a player whose feet are this close while he cowers cornered ...
const DEFENSE_RANGE := 64.0  # TESTWERT (1 tile)
## ... sees this long announced ...
const DEFENSE_WIND_UP := 0.5  # TESTWERT (at least 0.4 s)
## ... and takes this damage (1.0 HP = half a heart) with this knockback (px/s, DamageData) ...
const DEFENSE_DAMAGE := 1.0  # TESTWERT
const DEFENSE_KNOCKBACK := 240.0  # TESTWERT
## ... the strike circle in front of him (towards the player at wind-up start) ...
const DEFENSE_REACH := 24.0
const DEFENSE_RADIUS := 40.0
## ... stays active this long, then he waits this long before he may strike again.
const DEFENSE_ACTIVE_TIME := 0.15
const DEFENSE_COOLDOWN := 2.0  # TESTWERT
## Fallback slide for bodies without Player.apply_knockback (D-208): this far over this time
## (only the local player; see _shove).
const SHOVE_DISTANCE := 40.0  # TESTWERT
const SHOVE_TIME := 0.15
const DEFENSE_HITBOX_NAME := &"DefenseHitbox"

var enemy: Enemy = null
## Global position of the escape hole (set by the mode; with hole_fixed it is known before he flees).
var hole_position := Vector2.ZERO
var hole_fixed := false
## Global floor points he may run to while he zigzags (empty = straight to the hole).
var evade_points: Array[Vector2] = []
## false: he does not look for players yet (the fight has not started).
var watching := true
var state := State.WATCHING
var time_fleeing := 0.0

var _crown: Sprite2D = null
var _jump_left := 0.0
var _clock := 0.0
var _evade_target := Vector2.INF
var _repick_left := 0.0
## No spot leads away from the players (set by _choose_evade_target).
var _cornered := false
var _defense := Defense.NONE
var _defense_left := 0.0
var _defense_cooldown := 0.0
var _defense_direction := Vector2.RIGHT
var _defense_hitbox: Hitbox = null
var _shove_body: CharacterBody2D = null
var _shove_velocity := Vector2.ZERO
var _shove_left := 0.0


## Puts the crown on enemy and makes it the crowned one. Before or after the enemy entered the tree.
static func attach(target: Enemy) -> BountyFlight:
	var flight := BountyFlight.new()
	flight.name = NODE_NAME
	flight.enemy = target
	target.add_child(flight)
	flight._build_crown()
	target.died.connect(flight._on_enemy_died)
	return flight


static func of(target: Node) -> BountyFlight:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NodePath(NODE_NAME)) as BountyFlight


func _physics_process(delta: float) -> void:
	step(delta)
	_tick_shove(delta)


## One step (public for tests and tools).
func step(delta: float) -> void:
	_clock += delta
	if state == State.ESCAPED or state == State.CAUGHT or not is_instance_valid(enemy):
		return
	if enemy.is_dead():
		_on_enemy_died(enemy)
		return
	match state:
		State.WATCHING:
			if watching and sees_player():
				spot()
		State.FLEEING:
			time_fleeing += delta
			_defense_cooldown = maxf(0.0, _defense_cooldown - delta)
			var at_hole := false
			if _defense != Defense.NONE:
				_tick_defense(delta)
				at_hole = enemy.global_position.distance_to(hole_position) <= HuntRules.ARRIVE_RADIUS
			else:
				at_hole = _run(delta)
				var near := _nearest_player()
				if near != null and wants_defense(_cornered, _feet_distance(near), _defense_cooldown):
					_begin_defense(near)
			if (HuntRules.hole_open(time_fleeing) and at_hole) or HuntRules.forced_escape(time_fleeing):
				_begin_jump()
		State.JUMPING:
			_jump_left -= delta
			if _jump_left <= 0.0:
				escape()
	_update_crown()


## Does the enemy see a living player (within HuntRules.SIGHT_RANGE, free line)?
func sees_player() -> bool:
	if not enemy.is_inside_tree() or enemy.is_in_intro():
		return false
	var navigation := enemy.get_navigation()
	for node in EnemyTargeting.living_players(enemy.get_tree()):
		var distance := enemy.global_position.distance_to(node.global_position)
		var free_line := navigation == null or navigation.has_free_shot(enemy.global_position, node.global_position)
		if HuntRules.sees(distance, free_line):
			return true
	return false


## Decision: the enemy saw a player and flees from now on.
func spot() -> bool:
	if state != State.WATCHING or enemy.is_dead():
		return false
	state = State.FLEEING
	time_fleeing = 0.0
	if not hole_fixed:
		hole_position = enemy.global_position
	# Its own AI pauses: no attack, no chase; a running attack ends here.
	enemy.set_physics_process(false)
	var hitbox := enemy.get_node_or_null("AttackHitbox") as Hitbox
	if hitbox != null:
		hitbox.end_attack()
	for telegraph_name in ["TelegraphCircle", "TelegraphLine"]:
		var telegraph := enemy.get_node_or_null(NodePath(telegraph_name)) as CanvasItem
		if telegraph != null:
			telegraph.visible = false
	spotted.emit(self)
	return true


## Decision: the hole is open, the enemy is gone.
func escape() -> bool:
	if state == State.ESCAPED or state == State.CAUGHT:
		return false
	_end_defense()
	state = State.ESCAPED
	escaped.emit(self)
	return true


func is_fleeing() -> bool:
	return state == State.FLEEING or state == State.JUMPING


func is_caught() -> bool:
	return state == State.CAUGHT


func is_escaped() -> bool:
	return state == State.ESCAPED


## Cornered: no spot to run to leads away from the players (he cowers).
func is_cornered() -> bool:
	return _cornered


## Winding up or striking back (D-206).
func is_defending() -> bool:
	return _defense != Defense.NONE


func get_defense_cooldown() -> float:
	return _defense_cooldown


## Rule (D-206): he strikes back only cornered, with a player within DEFENSE_RANGE and no cooldown.
static func wants_defense(cornered: bool, player_distance: float, cooldown_left: float) -> bool:
	return cornered and player_distance <= DEFENSE_RANGE and cooldown_left <= 0.0


## Opening of the hole 0..1.
func get_hole_progress() -> float:
	return HuntRules.hole_progress(time_fleeing) if state != State.WATCHING else 0.0


## Where he runs right now (global): a zigzag spot or the hole.
func get_run_target() -> Vector2:
	if HuntRules.runs_to_hole(time_fleeing) or evade_points.is_empty() or _evade_target == Vector2.INF:
		return hole_position
	return _evade_target


## Runs one step; true when he stands at the hole.
func _run(delta: float) -> bool:
	_choose_evade_target(delta)
	var target := get_run_target()
	var body := enemy.get_node_or_null("CollisionShape2D") as Node2D
	var from := body.global_position if body != null else enemy.global_position
	var to_target := target - enemy.global_position
	var sprite := enemy.get_node_or_null("Sprite") as AnimatedSprite2D
	var at_hole := enemy.global_position.distance_to(hole_position) <= HuntRules.ARRIVE_RADIUS
	if to_target.length() <= HuntRules.ARRIVE_RADIUS:
		# At the hole (or at his spot): he cowers there.
		enemy.velocity = Vector2.ZERO
		_play(sprite, &"idle")
		if target != hole_position:
			_repick_left = 0.0
		return at_hole
	var navigation := enemy.get_navigation()
	var direction := Vector2.ZERO
	if navigation != null:
		navigation.tick(delta)
		direction = navigation.direction_to(from, target)
	if direction == Vector2.ZERO:
		direction = to_target.normalized()
	enemy.velocity = direction * enemy.get_move_speed() * HuntRules.FLEE_SPEED_FACTOR
	enemy.move_and_slide()
	_play(sprite, &"walk")
	if sprite != null and absf(direction.x) > 0.1:
		sprite.flip_h = direction.x < 0.0
	return at_hole


## Zigzag: every EVADE_REPICK seconds the spot that keeps him farthest from the players without
## running far (HuntRules.evade_score). Only spots that lead away (is_evade_spot): farther from the
## nearest player than he stands now and a way that does not pass a player. Without such a spot he
## cowers where he is (cornered = catchable) instead of running past the player to a "best of the
## bad" spot and back again (report #eff1c81c: he ran to and fro next to the player).
func _choose_evade_target(delta: float) -> void:
	if evade_points.is_empty() or HuntRules.runs_to_hole(time_fleeing) or not enemy.is_inside_tree():
		_cornered = false
		return
	var players := _player_points()
	if players.is_empty():
		_cornered = false
		return
	var here := enemy.global_position
	_repick_left -= delta
	# On the way: a player who steps into it or onto the spot makes him choose again at once.
	var target_safe := _evade_target != Vector2.INF and (_evade_target.distance_to(here) <= HuntRules.ARRIVE_RADIUS
		or is_evade_spot(here, _evade_target, players, -EVADE_PASS_SLACK))
	if _repick_left > 0.0 and target_safe:
		return
	_repick_left = HuntRules.EVADE_REPICK
	var best := Vector2.INF
	var best_score := -INF
	var reach := HuntRules.EVADE_RANGE_TILES * RoomTiles.TILE_WORLD + HuntRules.ARRIVE_RADIUS
	for point in evade_points:
		var to_self := point.distance_to(here)
		if to_self > reach or to_self < RoomTiles.TILE_WORLD or not is_evade_spot(here, point, players):
			continue
		var score := HuntRules.evade_score(WaveRules.distance_to_nearest(point, players), to_self)
		if score > best_score:
			best_score = score
			best = point
	# Cornered: he stays (target = where he stands) and looks again next frame.
	_cornered = best == Vector2.INF
	_evade_target = best if not _cornered else here


## Does running from `from` to `point` take him away from the players: the spot lies at least `gain`
## farther from the nearest player than `from`, and the straight way never comes closer to any player
## than `from` is now (at most EVADE_PASS_DISTANCE, minus EVADE_PASS_SLACK)? Public for tests.
static func is_evade_spot(from: Vector2, point: Vector2, players: Array[Vector2], gain := EVADE_GAIN) -> bool:
	var here_distance := WaveRules.distance_to_nearest(from, players)
	if WaveRules.distance_to_nearest(point, players) < here_distance + gain:
		return false
	for player in players:
		var closest := Geometry2D.get_closest_point_to_segment(player, from, point)
		if closest.distance_to(player) < minf(here_distance, EVADE_PASS_DISTANCE) - EVADE_PASS_SLACK:
			return false
	return true


## Feet of the living players (global), where the hunt measures distances.
func _player_points() -> Array[Vector2]:
	var players: Array[Vector2] = []
	for node in EnemyTargeting.living_players(enemy.get_tree()):
		var player := node as Player
		players.append(player.get_feet_position() if player != null else node.global_position)
	return players


## The living player nearest to his feet measure (feet of players), or null.
func _nearest_player() -> Node2D:
	return EnemyTargeting.nearest_living(EnemyTargeting.living_players(enemy.get_tree()), enemy.global_position)


func _feet_distance(node: Node2D) -> float:
	var player := node as Player
	var feet := player.get_feet_position() if player != null else node.global_position
	return enemy.global_position.distance_to(feet)


## Wind-up: he stops, the red circle shows where the strike lands (direction fixed now, so stepping
## out or dashing avoids it) and the attack animation reaches its strike frame at the end.
func _begin_defense(target: Node2D) -> void:
	_defense = Defense.WIND_UP
	_defense_left = DEFENSE_WIND_UP
	var to_target := target.global_position - enemy.global_position
	_defense_direction = to_target.normalized() if to_target.length() > 0.001 else Vector2.RIGHT
	enemy.velocity = Vector2.ZERO
	var circle := enemy.get_node_or_null("TelegraphCircle") as Node2D
	if circle != null:
		circle.global_position = _defense_center()
		circle.set(&"radius", DEFENSE_RADIUS)
		circle.set(&"color", Enemy.TELEGRAPH_COLOR)
		circle.visible = true
	var sprite := enemy.get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite != null:
		if absf(_defense_direction.x) > 0.1:
			sprite.flip_h = _defense_direction.x < 0.0
		_play_strike_animation(sprite)


func _tick_defense(delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	_defense_left -= delta
	if _defense_left > 0.0:
		return
	if _defense == Defense.WIND_UP:
		_strike()
	else:
		_end_defense()


## One attack instance over the normal hit chain (own hit ID, D-020; blocked by I-frames and dash).
func _strike() -> void:
	_hide_telegraph()
	_defense = Defense.STRIKE
	_defense_left = DEFENSE_ACTIVE_TIME
	_defense_cooldown = DEFENSE_COOLDOWN
	var hitbox := _ensure_defense_hitbox()
	hitbox.global_position = _defense_center()
	var damage := DamageData.new()
	damage.amount = DEFENSE_DAMAGE
	damage.source = enemy
	if enemy.data != null:
		damage.tags.assign(enemy.data.tags)
	damage.tags.append(&"crowned_defense")
	hitbox.begin_attack(damage)


func _end_defense() -> void:
	_defense = Defense.NONE
	_defense_left = 0.0
	_hide_telegraph()
	if _defense_hitbox != null and is_instance_valid(_defense_hitbox):
		_defense_hitbox.end_attack()


func _defense_center() -> Vector2:
	return enemy.global_position + _defense_direction * DEFENSE_REACH


func _hide_telegraph() -> void:
	if not is_instance_valid(enemy):
		return
	var circle := enemy.get_node_or_null("TelegraphCircle") as CanvasItem
	if circle != null:
		circle.visible = false


func _ensure_defense_hitbox() -> Hitbox:
	if _defense_hitbox != null and is_instance_valid(_defense_hitbox):
		return _defense_hitbox
	_defense_hitbox = Hitbox.new()
	_defense_hitbox.name = DEFENSE_HITBOX_NAME
	var attack := enemy.get_node_or_null("AttackHitbox") as Area2D
	_defense_hitbox.collision_layer = 0
	_defense_hitbox.collision_mask = attack.collision_mask if attack != null else 8
	_defense_hitbox.knockback_strength = DEFENSE_KNOCKBACK
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = DEFENSE_RADIUS
	shape.shape = circle
	_defense_hitbox.add_child(shape)
	enemy.add_child(_defense_hitbox)
	_defense_hitbox.hit_landed.connect(_on_defense_hit)
	return _defense_hitbox


func _on_defense_hit(hurtbox: Hurtbox, _result: DamageResult) -> void:
	var body := hurtbox.get_parent() as CharacterBody2D
	if body == null:
		return
	var away := body.global_position - enemy.global_position
	_shove(body, away.normalized() if away.length() > 0.001 else _defense_direction)


## Knockback for players: a player with apply_knockback(impulse) gets the impulse (D-208);
## otherwise the local player slides SHOVE_DISTANCE
## (walls stop him). Remote players move on their own machine and keep only DamageData.knockback.
func _shove(body: CharacterBody2D, direction: Vector2) -> void:
	if body.has_method(&"apply_knockback"):
		body.call(&"apply_knockback", direction * DEFENSE_KNOCKBACK)
		return
	var player := body as Player
	if player != null and not player.is_local:
		return
	_shove_body = body
	_shove_velocity = direction * SHOVE_DISTANCE / SHOVE_TIME
	_shove_left = SHOVE_TIME


func _tick_shove(delta: float) -> void:
	if _shove_left <= 0.0:
		return
	_shove_left -= delta
	if _shove_body == null or not is_instance_valid(_shove_body) or not _shove_body.is_inside_tree():
		_shove_left = 0.0
		return
	if _shove_body.move_and_collide(_shove_velocity * delta) != null:
		_shove_left = 0.0


func _play_strike_animation(sprite: AnimatedSprite2D) -> void:
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(&"attack"):
		return
	var strike := enemy.data.strike_frame if enemy.data != null else 2
	var lead_time := float(strike) / maxf(1.0, frames.get_animation_speed(&"attack"))
	sprite.play(&"attack")
	sprite.speed_scale = lead_time / DEFENSE_WIND_UP


func _begin_jump() -> void:
	_end_defense()
	state = State.JUMPING
	_jump_left = HuntRules.JUMP_TIME
	var tween := enemy.create_tween()
	tween.tween_property(enemy, "global_position", hole_position, HuntRules.JUMP_TIME * 0.6)
	tween.parallel().tween_property(enemy, "scale", Vector2(0.2, 0.2), HuntRules.JUMP_TIME)


func _on_enemy_died(_enemy: Enemy) -> void:
	if state == State.ESCAPED or state == State.CAUGHT:
		return
	state = State.CAUGHT
	_end_defense()
	if _crown != null:
		_crown.visible = false


func _build_crown() -> void:
	_crown = VariantArt.make_sprite(VariantArt.BOUNTY_CROWN)
	_crown.name = "Crown"
	_crown.z_index = 21
	enemy.add_child(_crown)
	_update_crown()


## Floats above the head, bobs a little; blinks during the last HuntRules.WARN_TIME seconds.
func _update_crown() -> void:
	if _crown == null or not is_instance_valid(_crown):
		return
	_crown.position = Vector2(0.0, -_head_height() - CROWN_HEIGHT + sin(_clock * 4.0) * CROWN_BOB)
	var warn := state == State.FLEEING and HuntRules.warns(time_fleeing)
	_crown.modulate.a = (0.35 if fmod(_clock * BLINK_SPEED, 2.0) < 1.0 else 1.0) if warn else 1.0


## Height of the top of the enemy's sprite above its origin (the crown sits on it, also on a small
## slime); the body radius when the sprite is unknown.
func _head_height() -> float:
	var sprite := enemy.get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation):
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if texture != null:
			var height := float(texture.get_height())
			var top := sprite.offset.y - (height * 0.5 if sprite.centered else 0.0)
			return maxf(8.0, -(sprite.position.y + top * absf(sprite.scale.y)))
	var data := enemy.data
	return (data.body_radius * data.sprite_scale if data != null else 12.0) + 44.0


static func _play(sprite: AnimatedSprite2D, animation: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
		return
	if sprite.animation != animation or not sprite.is_playing():
		sprite.speed_scale = 1.0
		sprite.play(animation)
