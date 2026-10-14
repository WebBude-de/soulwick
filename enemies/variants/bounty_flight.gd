class_name BountyFlight
extends Node
## The crowned one of "Jagd" (KONZEPT_RAEUME_V2 §3.8; before "Kopfgeld", KONZEPT_RAEUME §4.6). A child
## node of that enemy: it wears a gold crown; once it sees a player (range and free line) it stops
## fighting and flees. The escape hole opens over HuntRules.CATCH_TIME seconds; until its last seconds
## he zigzags away from the players between the pillars (evade_points), then he runs for the hole and
## jumps in once it is open. Killed before that = caught.
## While fleeing this node drives the enemy (its own AI is paused): path over the room navigation
## (EnemyNavigation), walk animation, no attacks. Decisions (spot, escape) emit signals; the mode
## places the hole and removes the escaped enemy.

signal spotted(flight: BountyFlight)
signal escaped(flight: BountyFlight)

enum State { WATCHING, FLEEING, JUMPING, ESCAPED, CAUGHT }

const NODE_NAME := &"BountyFlight"
const CROWN_HEIGHT := 6.0
const CROWN_BOB := 2.0
const BLINK_SPEED := 8.0

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
			var at_hole := _run(delta)
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
	state = State.ESCAPED
	escaped.emit(self)
	return true


func is_fleeing() -> bool:
	return state == State.FLEEING or state == State.JUMPING


func is_caught() -> bool:
	return state == State.CAUGHT


func is_escaped() -> bool:
	return state == State.ESCAPED


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
## running far (HuntRules.evade_score).
func _choose_evade_target(delta: float) -> void:
	if evade_points.is_empty() or HuntRules.runs_to_hole(time_fleeing) or not enemy.is_inside_tree():
		return
	_repick_left -= delta
	if _repick_left > 0.0 and _evade_target != Vector2.INF:
		return
	_repick_left = HuntRules.EVADE_REPICK
	var players: Array[Vector2] = []
	for node in EnemyTargeting.living_players(enemy.get_tree()):
		players.append(node.global_position)
	if players.is_empty():
		return
	var best := Vector2.INF
	var best_score := -INF
	var reach := HuntRules.EVADE_RANGE_TILES * RoomTiles.TILE_WORLD
	for point in evade_points:
		var to_self := point.distance_to(enemy.global_position)
		if to_self > reach or to_self < RoomTiles.TILE_WORLD:
			continue
		var score := HuntRules.evade_score(WaveRules.distance_to_nearest(point, players), to_self)
		if score > best_score:
			best_score = score
			best = point
	if best != Vector2.INF:
		_evade_target = best


func _begin_jump() -> void:
	state = State.JUMPING
	_jump_left = HuntRules.JUMP_TIME
	var tween := enemy.create_tween()
	tween.tween_property(enemy, "global_position", hole_position, HuntRules.JUMP_TIME * 0.6)
	tween.parallel().tween_property(enemy, "scale", Vector2(0.2, 0.2), HuntRules.JUMP_TIME)


func _on_enemy_died(_enemy: Enemy) -> void:
	if state == State.ESCAPED or state == State.CAUGHT:
		return
	state = State.CAUGHT
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
