class_name TutorialDummy
extends StaticBody2D
## A practice dummy of the practice run (WK10): a straw dummy (station 1, falls after
## TutorialRules.DUMMY_HITS hits) or a dummy with a wooden shield (station 4: normal hits bounce off,
## a special attack breaks the shield and the dummy). It takes hits like an enemy (a Hurtbox on the
## enemy hurtbox layer, so every weapon, projectile and special reaches it) but is no enemy: no
## group, no gold, no kill - its health is topped up after every hit, so "on kill" upgrades never
## trigger on it. The decision is TutorialRules.hit_result; the look (animations, sounds, shake)
## follows the signals.

signal hit(dummy: TutorialDummy, result: TutorialRules.Hit)
signal broken(dummy: TutorialDummy)

## Collision at the feet (px), so players walk round the pole, and the hit area around the body.
const FOOT_RADIUS := 12.0
const BODY_SIZE := Vector2(40, 60)
## Health that a hit never empties (topped up after every hit).
const HEALTH := 999.0
## Wobble on a hit: angle (rad) and time (s).
const WOBBLE_ANGLE := 0.18
const WOBBLE_TIME := 0.25

@export var shielded := false

var hits := 0
var is_broken := false

var _sprite: AnimatedSprite2D = null
var _health: HealthComponent = null
var _hurtbox: Hurtbox = null
var _foot: CollisionShape2D = null


func _ready() -> void:
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = TutorialArt.dummy_frames(shielded)
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_sprite.offset = SpriteStrip.pivot_offset(Vector2i(32, 32), TutorialArt.pivot(&"dummy_idle"))
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.play(&"idle")
	_sprite.animation_finished.connect(_on_animation_finished)
	add_child(_sprite)
	DropShadow.attach(self, 14.0, 0.0)
	_foot = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FOOT_RADIUS
	_foot.shape = circle
	add_child(_foot)
	_health = HealthComponent.new()
	_health.name = "HealthComponent"
	_health.max_health = HEALTH
	add_child(_health)
	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.health = _health
	_hurtbox.collision_layer = PhysicsLayers.ENEMY_HURTBOX
	_hurtbox.collision_mask = 0
	var body := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY_SIZE
	body.shape = rect
	body.position = Vector2(0, -BODY_SIZE.y * 0.5)
	_hurtbox.add_child(body)
	add_child(_hurtbox)
	_hurtbox.hit_received.connect(_on_hit_received)


func get_hurtbox() -> Hurtbox:
	return _hurtbox


## Where to aim at the dummy (global, the middle of its body).
func get_aim_point() -> Vector2:
	return global_position + Vector2(0, -BODY_SIZE.y * 0.5)


## Takes a hit with these damage tags (the hurtbox calls it; tests too). Returns what it did.
func take_hit(tags: Array[StringName]) -> TutorialRules.Hit:
	var result := TutorialRules.hit_result(shielded, is_broken, hits, tags)
	match result:
		TutorialRules.Hit.IGNORED:
			return result
		TutorialRules.Hit.COUNTED:
			hits += 1
			_play(&"hit")
			Sfx.play_at(self, &"hit_enemy", global_position, -4.0)
		TutorialRules.Hit.BLOCKED:
			_play(&"hit")
			Sfx.play_at(self, &"stone_clank", global_position, -2.0)
		TutorialRules.Hit.BREAKS, TutorialRules.Hit.SHIELD_BREAKS:
			hits += 1
			_break(result == TutorialRules.Hit.SHIELD_BREAKS)
	_wobble()
	hit.emit(self, result)
	if is_broken:
		broken.emit(self)
	return result


func _on_hit_received(_result: DamageResult, damage: DamageData) -> void:
	# Never empty: a dummy is no kill (no gold, no "on kill" upgrades).
	_health.set_current(_health.get_max_health())
	take_hit(damage.tags)


func _break(shield_too: bool) -> void:
	is_broken = true
	_play(&"break")
	Sfx.play_at(self, &"plate_break" if shield_too else &"crate_break", global_position, -2.0)
	_foot.set_deferred(&"disabled", true)
	_hurtbox.set_deferred(&"monitorable", false)


func _play(animation: StringName) -> void:
	if _sprite == null or (is_broken and animation != &"break"):
		return
	_sprite.play(animation)


func _wobble() -> void:
	if _sprite == null or is_broken:
		return
	var tween := create_tween()
	tween.tween_property(_sprite, ^"rotation", WOBBLE_ANGLE, WOBBLE_TIME * 0.3)
	tween.tween_property(_sprite, ^"rotation", 0.0, WOBBLE_TIME * 0.7).set_trans(Tween.TRANS_ELASTIC)


func _on_animation_finished() -> void:
	if _sprite.animation == &"hit" and not is_broken:
		_sprite.play(&"idle")
