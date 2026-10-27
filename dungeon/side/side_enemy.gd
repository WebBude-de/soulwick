class_name SideEnemy
extends CharacterBody2D
## An enemy of a side segment (M5, D-144): a slime hops along its platform, a skeleton walks it and
## turns at edges and walls; both turn towards a player in sight and never leave their platform.
## Contact hurts (shield first, D-018); weapons hit it through the enemy hurtbox like any enemy, and
## every hit is reported on the EventBus, so kill rewards and upgrade effects work as usual. The
## origin is the feet. The body collides only with the world (players walk through it).
##
## Enemies as obstacles (SV4, D-195, D-216): stomping (landing from above) or a weapon defeats normal
## side enemies; nobody is run over - touching one from the side hurts at any speed (D-216).
## The player side (SV1) decides that a stomp happens and asks the enemy:
##   on_stomped(player: Player) -> bool   true = accepted and defeated (pops flat), the player
##                                         bounces; false = rejected (the enemy strikes at once with
##                                         its usual contact damage, no bounce).
## It goes through the normal damage pipeline (DamageData tagged &"stomp", source = player), so
## kills, kill rewards, stats and the coin drop are those of a normal defeat; a short hit stop
## follows (HitStop, single player only). Calls are for the host only: on a client (puppet) it
## returns false. While a player falls onto a stompable enemy, the contact waits for that call
## instead of hurting first (SideContact). Which kinds take a stomp: kind_accepts_stomp(); the other
## kinds live in dungeon/side/enemies/ and are made by SideEnemyKinds.create(). Side view has no
## floor shadow (feedback #e0486234).

signal died(enemy: SideEnemy)
## A stomp defeated this enemy.
signal defeated(enemy: SideEnemy, player: Player, style: Defeat)

enum Kind { SLIME, SKELETON, BAT, SPIKE_HEDGEHOG, SHIELD_BEARER }
## How a defeat looks: NORMAL death animation, POP (stomped flat). New styles only at the end (the
## number travels, NetSide).
enum Defeat { NORMAL, POP }

const SLIME_DATA: EnemyData = preload("res://enemies/data/slime.tres")
const SKELETON_DATA: EnemyData = preload("res://enemies/data/skeleton.tres")
const GOLD_PICKUP_SCENE: PackedScene = preload("res://economy/gold_pickup.tscn")
const FRAME := Vector2i(32, 32)
const FEET_PIVOT := Vector2(16, 30)

## TESTWERTE: weaker than in a room ("wenig kämpfen"), slower, short sight.
const HEALTH_FACTOR := 0.75
const GOLD_DROP_FACTOR := 0.4
const HOP_INTERVAL := Vector2(0.9, 1.5)
const HOP_SPEED := Vector2(150.0, 520.0)
const WALK_SPEED := 65.0
const CHASE_SPEED := 115.0
const SIGHT_DISTANCE := 320.0
const SIGHT_HEIGHT := 80.0
const CONTACT_REARM := 0.8
const KNOCKBACK_FRICTION := 900.0
const DEATH_TIME := 0.6
const SLIME_BODY := Vector2(26, 22)
const SKELETON_BODY := Vector2(22, 44)
const EDGE_PROBE := 18.0

## TESTWERTE (SV4, D-195): stomp.
## Contact guard only (SV1 decides the stomp, SideContactRules.STOMP_TOLERANCE): a falling player
## whose feet are at most this far below the top, plus one frame of the fall, is stomping.
const STOMP_BAND := 14.0
const STOMP_HIT_STOP := 0.05
const STOMP_SHAKE := 2.5
const POP_SQUASH := Vector2(1.7, 0.25)
const POP_TIME := 0.18
const STOMP_TAGS: Array[StringName] = [&"stomp", &"contact"]
const SOUND_STOMP := &"side_stomp"
const SOUND_STOMP_FALLBACK := &"slime_land"
const SOUND_REJECT := &"side_reject"
const SOUND_REJECT_FALLBACK := &"shield"

var kind := Kind.SLIME
var data: EnemyData = SLIME_DATA
var room_index := 1
var segment: SideSegment = null
var health: HealthComponent = null
var hurtbox: Hurtbox = null
## A client's copy of the host's enemy (no AI, no stomp decisions). NetSide may set it; a
## switched-off physics process (how NetSide holds puppets today) counts as well.
var puppet := false
## How the defeat looked (the host sends it with the death, apply_remote_defeat on a client).
var defeat_style := Defeat.NORMAL
## Delivered art in use (false = placeholder frames or a drawn stand-in).
var has_art := false

var _facing := -1.0
var _hop_left := 1.0
var _contact_left := 0.0
var _knockback := 0.0
var _dead := false
var _defeat_direction := 1.0
var _rng := RandomNumberGenerator.new()
var _visual: Node2D = null
var _sprite: AnimatedSprite2D = null
var _placeholder: SideEnemyPlaceholder = null
var _contact: SideContact = null
## Seconds a one-shot animation (refuse) still holds against idle and walk.
var _hold_animation_left := 0.0


## Before entering the tree. seed: from the segment's RNG (multiplayer rule). The new kinds come
## from SideEnemyKinds.create(kind) (their own classes); this class runs SLIME and SKELETON.
func setup(enemy_kind: Kind, index: int, owner_segment: SideSegment, rng_seed: int) -> void:
	kind = enemy_kind
	data = _default_data()
	room_index = index
	segment = owner_segment
	_rng.seed = rng_seed
	_facing = -1.0 if _rng.randf() < 0.5 else 1.0
	_hop_left = _rng.randf_range(HOP_INTERVAL.x, HOP_INTERVAL.y)


## Kinds a stomp defeats: all but the spike hedgehog (spikes on top).
static func kind_accepts_stomp(enemy_kind: Kind) -> bool:
	return enemy_kind != Kind.SPIKE_HEDGEHOG


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.WORLD
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_snap_length = 8.0
	var body_size := get_body_size()
	var box := RectangleShape2D.new()
	box.size = body_size
	var shape := CollisionShape2D.new()
	shape.shape = box
	shape.position = Vector2(0, -body_size.y * 0.5)
	add_child(shape)

	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_build_visual()
	_play(&"idle")

	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = maxf(1.0, roundf(data.max_health * EnemyScaling.health_multiplier(room_index, false) * HEALTH_FACTOR))
	add_child(health)
	health.died.connect(_on_died)

	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.health = health
	hurtbox.collision_layer = PhysicsLayers.ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	var hurt_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = maxf(body_size.x, body_size.y) * 0.55
	hurt_shape.shape = circle
	hurtbox.add_child(hurt_shape)
	hurtbox.position = Vector2(0, -body_size.y * 0.5)
	add_child(hurtbox)
	hurtbox.hit_received.connect(_on_hit_received)

	_contact = SideContact.new()
	_contact.name = "Contact"
	_contact.collision_layer = 0
	_contact.collision_mask = PhysicsLayers.PLAYER_HURTBOX
	_contact.knockback_strength = data.knockback_strength
	_contact.spares = spares_contact
	var contact_shape := CollisionShape2D.new()
	var contact_box := RectangleShape2D.new()
	contact_box.size = body_size * 0.9
	contact_shape.shape = contact_box
	_contact.add_child(contact_shape)
	_contact.position = Vector2(0, -body_size.y * 0.5)
	add_child(_contact)


func is_dead() -> bool:
	return _dead


func get_facing() -> float:
	return _facing


## Collision body size (origin = feet, bottom centre).
func get_body_size() -> Vector2:
	return SLIME_BODY if kind == Kind.SLIME else SKELETON_BODY


## Top edge of the body in global coordinates.
func get_top_y() -> float:
	return global_position.y - get_body_size().y


## Direction of the defeat, away from the player (-1 / 1; the network sends it with the death).
func get_defeat_direction() -> float:
	return _defeat_direction


func is_puppet() -> bool:
	return puppet or (is_inside_tree() and not is_physics_processing())


## Host: a player landed on this enemy from above (SV1). See the head comment.
func on_stomped(player: Player) -> bool:
	if not _can_decide(player):
		return false
	if not kind_accepts_stomp(kind):
		_reject(player)
		return false
	_defeat_by(player, Defeat.POP, STOMP_TAGS, signf(global_position.x - player.global_position.x))
	return _dead


## The player is falling onto the top of the body (the shape of a stomp, not the decision).
func is_stomp_approach(player: Player) -> bool:
	if player == null or player.velocity.y <= 0.0:
		return false
	var frame := player.velocity.y / float(Engine.physics_ticks_per_second)
	return player.get_feet_position().y <= get_top_y() + STOMP_BAND + frame


## Contact holds back for a player about to stomp this enemy successfully (SV1 then calls
## on_stomped); everyone else is hurt as usual, also from the side at any speed (D-216).
func spares_contact(player: Player) -> bool:
	if _dead or player == null:
		return false
	return kind_accepts_stomp(kind) and is_stomp_approach(player)


## Client: the host's defeat of this enemy, with its look (NetSide hook, see the report of SV4).
func apply_remote_defeat(style: Defeat, direction: float) -> void:
	if _dead or health == null:
		return
	defeat_style = style
	_defeat_direction = -1.0 if direction < 0.0 else 1.0
	health.take_damage(health.get_health() + 1.0)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_move(delta)
	_tick_contact(delta)
	if segment != null and position.y > segment.layout.kill_y():
		# Pushed out of the segment: gone without loot.
		_dead = true
		queue_free()
		return
	_sprite.flip_h = _facing < 0.0
	_after_move()


## Gravity, the kind's own motion, knockback, move_and_slide (SLIME hops, SKELETON walks).
func _move(delta: float) -> void:
	velocity.y = minf(velocity.y + PlayerSideMotion.gravity_for(velocity.y) * delta, SideRules.MAX_FALL_SPEED)
	match kind:
		Kind.SLIME:
			_hop(delta)
		_:
			_walk()
	if _knockback != 0.0:
		velocity.x += _knockback
		_knockback = move_toward(_knockback, 0.0, KNOCKBACK_FRICTION * delta)
		if not _has_floor_ahead(signf(velocity.x)):
			velocity.x = 0.0
	move_and_slide()
	if is_on_floor() and kind == Kind.SLIME:
		velocity.x = 0.0


## Hook for subclasses after each move; the drawn stand-in follows the facing.
func _after_move() -> void:
	if _placeholder != null and _placeholder.facing != _facing:
		_placeholder.facing = _facing
		_placeholder.queue_redraw()


func _tick_contact(delta: float) -> void:
	_hold_animation_left = maxf(0.0, _hold_animation_left - delta)
	_contact_left -= delta
	if _contact_left <= 0.0:
		_strike()


## A new contact attack instance (D-020): hurts every overlapping player once.
func _strike() -> void:
	_contact_left = CONTACT_REARM
	var damage := DamageData.new()
	damage.amount = data.damage * EnemyScaling.damage_multiplier(room_index, false)
	damage.source = self
	damage.tags.assign([&"melee", &"contact"])
	_contact.begin_attack(damage)


## Slime: hops every 0.9-1.5 s, towards a player in sight, never off its platform.
func _hop(delta: float) -> void:
	if not is_on_floor():
		return
	_play(&"idle")
	_hop_left -= delta
	if _hop_left > 0.0:
		return
	_hop_left = _rng.randf_range(HOP_INTERVAL.x, HOP_INTERVAL.y)
	var target := _player_in_sight()
	if target != null:
		_facing = signf(target.global_position.x - global_position.x)
	if not _has_floor_ahead(_facing, HOP_SPEED.x * 0.6):
		_facing = -_facing
		if not _has_floor_ahead(_facing, HOP_SPEED.x * 0.6):
			velocity.y = -HOP_SPEED.y * 0.6
			return
	velocity = Vector2(_facing * HOP_SPEED.x, -HOP_SPEED.y)
	_play(&"walk")
	if is_inside_tree():
		Sfx.play_at(self, &"slime_hop", global_position, -14.0)


## Walkers: patrol the platform, turn at edges and walls, faster towards a player in sight.
func _walk() -> void:
	var target := _player_in_sight()
	var speeds := _walk_speeds()
	var speed := speeds.x
	if target != null:
		_facing = signf(target.global_position.x - global_position.x)
		speed = speeds.y
	if is_on_floor() and (not _has_floor_ahead(_facing) or is_on_wall()):
		if target != null:
			# Waits at the edge instead of following the player down.
			velocity.x = 0.0
			_play(&"idle")
			return
		_facing = -_facing
	velocity.x = _facing * speed * EnemyScaling.speed_multiplier(room_index)
	_play(&"walk")


## Patrol and chase speed (px/s) of a walker.
func _walk_speeds() -> Vector2:
	return Vector2(WALK_SPEED, CHASE_SPEED)


func _default_data() -> EnemyData:
	return SLIME_DATA if kind == Kind.SLIME else SKELETON_DATA


## The sprite: the data's frames (slime, skeleton), for the newer kinds their delivered art
## (SideEnemyArt) or else the data's frames plus a drawn placeholder (_build_placeholder).
func _build_visual() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = data.sprite_frames
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_sprite.offset = SpriteStrip.pivot_offset(FRAME, FEET_PIVOT)
	_visual.add_child(_sprite)
	SpriteFx.apply(_sprite)
	if not _uses_side_art():
		return
	var art := SideEnemyArt.get_art(data.id)
	if art == null:
		_build_placeholder()
		return
	has_art = true
	_sprite.modulate = Color.WHITE
	_sprite.sprite_frames = art.frames
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE * (FRAME.x / float(art.frame_size.x))
	_sprite.offset = SpriteStrip.pivot_offset(art.frame_size, art.pivot)


## The newer kinds look for art by their data id (SPRITES_V13 §B10).
func _uses_side_art() -> bool:
	return false


## Look of the drawn stand-in while the art is missing (SideEnemyPlaceholder.Look, -1 = none).
func _placeholder_look() -> int:
	return -1


func _build_placeholder() -> void:
	var look := _placeholder_look()
	if look < 0:
		return
	_placeholder = SideEnemyPlaceholder.new()
	_placeholder.name = "Placeholder"
	_placeholder.look = look as SideEnemyPlaceholder.Look
	_placeholder.facing = _facing
	_visual.add_child(_placeholder)


## Hit flash on the sprite and the drawn stand-in.
func _flash(color := Color.WHITE) -> void:
	SpriteFx.flash(_sprite, color)
	if _placeholder != null:
		_placeholder.modulate = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0)
		_placeholder.create_tween().tween_property(_placeholder, ^"modulate", Color.WHITE, SpriteFx.FLASH_TIME)


func _player_in_sight() -> Player:
	if segment == null:
		return null
	var best: Player = null
	var best_distance := SIGHT_DISTANCE
	for player in segment.get_players():
		if not is_instance_valid(player) or not player.is_alive():
			continue
		var offset := player.get_feet_position() - global_position
		if absf(offset.y) > SIGHT_HEIGHT:
			continue
		if absf(offset.x) < best_distance:
			best_distance = absf(offset.x)
			best = player
	return best


## Ground in front (a stand cell) at distance px, no wall.
func _has_floor_ahead(direction: float, distance := EDGE_PROBE) -> bool:
	if segment == null or direction == 0.0:
		return true
	var probe := segment.to_local(global_position) + Vector2(direction * distance, -4.0)
	var cell := SideLayout.cell_at(probe)
	return segment.layout.is_standable(cell)


func _play(animation: StringName) -> void:
	if _hold_animation_left > 0.0 and animation != &"death":
		return
	if _sprite != null and _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(animation) and _sprite.animation != animation:
		_sprite.play(animation)


func _can_decide(player: Player) -> bool:
	return not _dead and health != null and is_instance_valid(player) and not is_puppet()


## Rejected stomp: the usual contact damage, at once (a fresh attack instance), plus a cue.
func _reject(player: Player) -> void:
	_strike()
	_on_rejected(player)
	if is_inside_tree():
		Sfx.play_at(self, SideRules.sound_or(SOUND_REJECT, SOUND_REJECT_FALLBACK), global_position, -6.0)


## Hook for subclasses: the look of a rejection (flash, the refuse animation of delivered art).
func _on_rejected(_player: Player) -> void:
	_flash(Color(1.0, 0.85, 0.5))
	if _sprite != null and _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(&"refuse"):
		_sprite.play(&"refuse")
		var frames := _sprite.sprite_frames
		_hold_animation_left = frames.get_frame_count(&"refuse") / maxf(1.0, frames.get_animation_speed(&"refuse"))


## A stomp kill through the normal damage pipeline (kill stats, kill rewards, coin drop).
func _defeat_by(player: Player, style: Defeat, tags: Array[StringName], direction: float) -> void:
	defeat_style = style
	_defeat_direction = -1.0 if direction < 0.0 else 1.0
	var damage := DamageData.new()
	damage.amount = health.get_health() + 1.0
	damage.source = player
	damage.tags.assign(tags)
	damage.hit_id = DamageData.next_hit_id()
	hurtbox.receive_hit(damage)
	if not _dead:
		defeat_style = Defeat.NORMAL
		return
	HitStop.trigger(self, STOMP_HIT_STOP)
	if player.is_local:
		CameraShake.shake(self, STOMP_SHAKE)
	defeated.emit(self, player, style)


func _on_hit_received(result: DamageResult, damage: DamageData) -> void:
	_flash()
	if damage.knockback.x != 0.0:
		_knockback = clampf(damage.knockback.x, -260.0, 260.0)
	if is_inside_tree() and defeat_style == Defeat.NORMAL:
		Sfx.play_at(self, &"hit_enemy", global_position, -4.0)
	EventBus.enemy_damaged.emit(self, result, damage)


func _on_died() -> void:
	_dead = true
	velocity = Vector2.ZERO
	_contact.end_attack()
	hurtbox.set_deferred(&"monitorable", false)
	match defeat_style:
		Defeat.POP:
			_play_pop()
		_:
			_play(&"death")
			if is_inside_tree():
				Sfx.play_at(self, &"enemy_death", global_position, -2.0)
	_drop_gold()
	died.emit(self)
	if is_inside_tree():
		get_tree().create_timer(DEATH_TIME, false).timeout.connect(queue_free)


## Stomped: squashed flat at the feet, a puff of the body colour, gone.
func _play_pop() -> void:
	_play(&"death")
	if not is_inside_tree():
		_visual.scale = POP_SQUASH
		return
	var tween := create_tween()
	tween.tween_property(_visual, ^"scale", POP_SQUASH, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, ^"modulate:a", 0.0, DEATH_TIME - POP_TIME - 0.05)
	# A pixel pop of the body colour (D-218) with the small light flash the burst had.
	SideDust.spawn(get_parent(), global_position + Vector2(0, -6), SideDust.Kind.POP, 0.8, 0.0, data.placeholder_color)
	if Burst.should_flash(12):
		LightSource.flash(get_parent(), global_position + Vector2(0, -6), Burst.flash_radius(150.0), 0.21, data.placeholder_color, Burst.FLASH_PEAK)
	Sfx.play_at(self, SideRules.sound_or(SOUND_STOMP, SOUND_STOMP_FALLBACK), global_position, -2.0)


## Side enemies are obstacles: the coins are the reward (SideRules.ENEMY_GOLD, round 2).
func _drop_gold() -> void:
	if SideRules.ENEMY_GOLD <= 0:
		return
	var amount := maxi(1, roundi(data.gold_drop * GOLD_DROP_FACTOR * MetaProgression.get_gold_multiplier()))
	var pickup := GOLD_PICKUP_SCENE.instantiate() as GoldPickup
	pickup.amount = amount
	pickup.position = position + Vector2(0, -16)
	get_parent().add_child.call_deferred(pickup)
