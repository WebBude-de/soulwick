class_name BountyFlight
extends Node
## The crowned enemy of the variant "Kopfgeld" (KONZEPT_RAEUME §4.6). A child node of that enemy:
## it wears a gold crown; once it sees a player (range and free line) it stops fighting and flees
## to an escape hole the variant opens. The hole opens over VariantRules.BOUNTY_CATCH_TIME seconds;
## when it is fully open the enemy jumps in and is gone. Killed before that = caught.
## While fleeing this node drives the enemy (its own AI is paused): path over the room navigation
## (EnemyNavigation), walk animation, no attacks. Decisions (spot, escape) emit signals; the
## variant places the hole and removes the escaped enemy.

signal spotted(flight: BountyFlight)
signal escaped(flight: BountyFlight)

enum State { WATCHING, FLEEING, JUMPING, ESCAPED, CAUGHT }

const NODE_NAME := &"BountyFlight"
const CROWN_HEIGHT := 18.0
const CROWN_BOB := 2.0
const BLINK_SPEED := 8.0

var enemy: Enemy = null
## Global position of the escape hole (set by the variant on spotted).
var hole_position := Vector2.ZERO
var state := State.WATCHING
var time_fleeing := 0.0

var _crown: Sprite2D = null
var _jump_left := 0.0
var _clock := 0.0


## Puts the crown on enemy and makes it the bounty. Before or after the enemy entered the tree.
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
			if sees_player():
				spot()
		State.FLEEING:
			time_fleeing += delta
			_run(delta)
			if VariantRules.bounty_escapes(time_fleeing):
				_begin_jump()
		State.JUMPING:
			_jump_left -= delta
			if _jump_left <= 0.0:
				escape()
	_update_crown()


## Does the enemy see a living player (within BOUNTY_SIGHT_RANGE, free line)?
func sees_player() -> bool:
	if not enemy.is_inside_tree():
		return false
	var navigation := enemy.get_navigation()
	for node in EnemyTargeting.living_players(enemy.get_tree()):
		var distance := enemy.global_position.distance_to(node.global_position)
		var free_line := navigation == null or navigation.has_free_shot(enemy.global_position, node.global_position)
		if VariantRules.bounty_sees(distance, free_line):
			return true
	return false


## Decision: the enemy saw a player and flees from now on.
func spot() -> bool:
	if state != State.WATCHING or enemy.is_dead():
		return false
	state = State.FLEEING
	time_fleeing = 0.0
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
	return VariantRules.hole_progress(time_fleeing) if state != State.WATCHING else 0.0


func _run(delta: float) -> void:
	var body := enemy.get_node_or_null("CollisionShape2D") as Node2D
	var from := body.global_position if body != null else enemy.global_position
	var to_hole := hole_position - enemy.global_position
	var sprite := enemy.get_node_or_null("Sprite") as AnimatedSprite2D
	if to_hole.length() <= VariantRules.BOUNTY_ARRIVE_RADIUS:
		# At the hole: it cowers there until the hole is open.
		enemy.velocity = Vector2.ZERO
		_play(sprite, &"idle")
		return
	var navigation := enemy.get_navigation()
	var direction := Vector2.ZERO
	if navigation != null:
		navigation.tick(delta)
		direction = navigation.direction_to(from, hole_position)
	if direction == Vector2.ZERO:
		direction = to_hole.normalized()
	enemy.velocity = direction * enemy.get_move_speed() * VariantRules.BOUNTY_FLEE_SPEED_FACTOR
	enemy.move_and_slide()
	_play(sprite, &"walk")
	if sprite != null and absf(direction.x) > 0.1:
		sprite.flip_h = direction.x < 0.0


func _begin_jump() -> void:
	state = State.JUMPING
	_jump_left = VariantRules.BOUNTY_JUMP_TIME
	var tween := enemy.create_tween()
	tween.tween_property(enemy, "global_position", hole_position, VariantRules.BOUNTY_JUMP_TIME * 0.6)
	tween.parallel().tween_property(enemy, "scale", Vector2(0.2, 0.2), VariantRules.BOUNTY_JUMP_TIME)


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


## Floats above the head, bobs a little; blinks during the last BOUNTY_WARN_TIME seconds.
func _update_crown() -> void:
	if _crown == null or not is_instance_valid(_crown):
		return
	var data := enemy.data
	var head := (data.body_radius * data.sprite_scale if data != null else 12.0) + 44.0
	_crown.position = Vector2(0.0, -head - CROWN_HEIGHT + sin(_clock * 4.0) * CROWN_BOB)
	var warn := state == State.FLEEING and VariantRules.bounty_warns(time_fleeing)
	_crown.modulate.a = (0.35 if fmod(_clock * BLINK_SPEED, 2.0) < 1.0 else 1.0) if warn else 1.0


static func _play(sprite: AnimatedSprite2D, animation: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
		return
	if sprite.animation != animation or not sprite.is_playing():
		sprite.speed_scale = 1.0
		sprite.play(animation)
