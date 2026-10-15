class_name SideEnemy
extends CharacterBody2D
## A simple enemy of a side segment (M5): a slime hops along its platform, a skeleton walks it and
## turns at edges and walls; both turn towards a player in sight and never leave their platform.
## Contact hurts (shield first, D-018); weapons hit it through the enemy hurtbox like any enemy, and
## every hit is reported on the EventBus, so kill rewards and upgrade effects work as usual. The
## origin is the feet. The body collides only with the world (players walk through it).

signal died(enemy: SideEnemy)

enum Kind { SLIME, SKELETON }

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

var kind := Kind.SLIME
var data: EnemyData = SLIME_DATA
var room_index := 1
var segment: SideSegment = null
var health: HealthComponent = null
var hurtbox: Hurtbox = null

var _facing := -1.0
var _hop_left := 1.0
var _contact_left := 0.0
var _knockback := 0.0
var _dead := false
var _rng := RandomNumberGenerator.new()
var _sprite: AnimatedSprite2D = null
var _contact: Hitbox = null


## Before entering the tree. seed: from the segment's RNG (multiplayer rule).
func setup(enemy_kind: Kind, index: int, owner_segment: SideSegment, rng_seed: int) -> void:
	kind = enemy_kind
	data = SLIME_DATA if kind == Kind.SLIME else SKELETON_DATA
	room_index = index
	segment = owner_segment
	_rng.seed = rng_seed
	_facing = -1.0 if _rng.randf() < 0.5 else 1.0
	_hop_left = _rng.randf_range(HOP_INTERVAL.x, HOP_INTERVAL.y)


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.WORLD
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_snap_length = 8.0
	var body_size := SLIME_BODY if kind == Kind.SLIME else SKELETON_BODY
	var box := RectangleShape2D.new()
	box.size = body_size
	var shape := CollisionShape2D.new()
	shape.shape = box
	shape.position = Vector2(0, -body_size.y * 0.5)
	add_child(shape)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = data.sprite_frames
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_sprite.offset = SpriteStrip.pivot_offset(FRAME, FEET_PIVOT)
	add_child(_sprite)
	SpriteFx.apply(_sprite)
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

	_contact = Hitbox.new()
	_contact.name = "Contact"
	_contact.collision_layer = 0
	_contact.collision_mask = PhysicsLayers.PLAYER_HURTBOX
	_contact.knockback_strength = data.knockback_strength
	var contact_shape := CollisionShape2D.new()
	var contact_box := RectangleShape2D.new()
	contact_box.size = body_size * 0.9
	contact_shape.shape = contact_box
	_contact.add_child(contact_shape)
	_contact.position = Vector2(0, -body_size.y * 0.5)
	add_child(_contact)
	DropShadow.attach(self, body_size.x * 0.5, 0.0)


func is_dead() -> bool:
	return _dead


func get_facing() -> float:
	return _facing


func _physics_process(delta: float) -> void:
	if _dead:
		return
	velocity.y = minf(velocity.y + PlayerSideMotion.gravity_for(velocity.y) * delta, SideRules.MAX_FALL_SPEED)
	match kind:
		Kind.SLIME:
			_hop(delta)
		Kind.SKELETON:
			_walk()
	if _knockback != 0.0:
		velocity.x += _knockback
		_knockback = move_toward(_knockback, 0.0, KNOCKBACK_FRICTION * delta)
		if not _has_floor_ahead(signf(velocity.x)):
			velocity.x = 0.0
	move_and_slide()
	if is_on_floor() and kind == Kind.SLIME:
		velocity.x = 0.0
	_contact_left -= delta
	if _contact_left <= 0.0:
		_contact_left = CONTACT_REARM
		var damage := DamageData.new()
		damage.amount = data.damage * EnemyScaling.damage_multiplier(room_index, false)
		damage.source = self
		damage.tags.assign([&"melee", &"contact"])
		_contact.begin_attack(damage)
	if segment != null and position.y > segment.layout.kill_y():
		# Pushed out of the segment: gone without loot.
		_dead = true
		queue_free()
		return
	_sprite.flip_h = _facing < 0.0


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


## Skeleton: walks its platform, turns at edges and walls, faster towards a player in sight.
func _walk() -> void:
	var target := _player_in_sight()
	var speed := WALK_SPEED
	if target != null:
		_facing = signf(target.global_position.x - global_position.x)
		speed = CHASE_SPEED
	if is_on_floor() and (not _has_floor_ahead(_facing) or is_on_wall()):
		if target != null:
			# Waits at the edge instead of following the player down.
			velocity.x = 0.0
			_play(&"idle")
			return
		_facing = -_facing
	velocity.x = _facing * speed * EnemyScaling.speed_multiplier(room_index)
	_play(&"walk")


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
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(animation) and _sprite.animation != animation:
		_sprite.play(animation)


func _on_hit_received(result: DamageResult, damage: DamageData) -> void:
	SpriteFx.flash(_sprite)
	if damage.knockback.x != 0.0:
		_knockback = clampf(damage.knockback.x, -260.0, 260.0)
	if is_inside_tree():
		Sfx.play_at(self, &"hit_enemy", global_position, -4.0)
	EventBus.enemy_damaged.emit(self, result, damage)


func _on_died() -> void:
	_dead = true
	velocity = Vector2.ZERO
	_contact.end_attack()
	hurtbox.set_deferred(&"monitorable", false)
	_play(&"death")
	if is_inside_tree():
		Sfx.play_at(self, &"enemy_death", global_position, -2.0)
	_drop_gold()
	died.emit(self)
	get_tree().create_timer(DEATH_TIME, false).timeout.connect(queue_free)


## Side enemies are obstacles: the coins are the reward (SideRules.ENEMY_GOLD, round 2).
func _drop_gold() -> void:
	if SideRules.ENEMY_GOLD <= 0:
		return
	var amount := maxi(1, roundi(data.gold_drop * GOLD_DROP_FACTOR * MetaProgression.get_gold_multiplier()))
	var pickup := GOLD_PICKUP_SCENE.instantiate() as GoldPickup
	pickup.amount = amount
	pickup.position = position + Vector2(0, -16)
	get_parent().add_child.call_deferred(pickup)
