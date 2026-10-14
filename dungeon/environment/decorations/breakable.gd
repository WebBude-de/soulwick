class_name Breakable
extends StaticBody2D
## Crate or barrel that player attacks can smash (D-069). Drops gold or a heart now and then.
## Its hurtbox sits on the enemy_hurtbox layer, so only player attacks hit it.

const GOLD_PICKUP_SCENE: PackedScene = preload("res://economy/gold_pickup.tscn")
const GOLD_CHANCE := 0.5
const HEART_CHANCE := 0.12
const GOLD_MIN := 1
const GOLD_MAX := 2
## Pickup growth per five-room block, like enemy gold (TESTWERT).
const GOLD_GROWTH_PER_BLOCK := 0.1

@export var debris_color := Color(0.62, 0.42, 0.22)

@onready var _sprite: Sprite2D = $Sprite
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	SpriteFx.apply(_sprite)
	DropShadow.attach(self, 20.0, -2.0)
	_hurtbox.hit_received.connect(_on_hit)
	_health.died.connect(_on_broken)


func _on_hit(_result: DamageResult, _damage: DamageData) -> void:
	SpriteFx.flash(_sprite)
	Burst.spawn(get_parent(), global_position + Vector2(0, -16), debris_color, 5, 90.0, 0.3, 3.0)
	var tween := create_tween()
	tween.tween_property(_sprite, "rotation", 0.12, 0.05)
	tween.tween_property(_sprite, "rotation", -0.08, 0.05)
	tween.tween_property(_sprite, "rotation", 0.0, 0.05)


func _on_broken() -> void:
	Burst.spawn(get_parent(), global_position + Vector2(0, -16), debris_color, 20, 200.0, 0.55, 5.0)
	Sfx.play_at(self, &"crate_break", global_position)
	CameraShake.shake(self, 2.0)
	_drop()
	set_deferred("collision_layer", 0)
	_hurtbox.set_deferred("monitorable", false)
	queue_free.call_deferred()


func _drop() -> void:
	var roll := randf()
	if roll >= GOLD_CHANCE + HEART_CHANCE:
		return
	var pickup := GOLD_PICKUP_SCENE.instantiate() as GoldPickup
	if roll < HEART_CHANCE:
		pickup.kind = GoldPickup.Kind.HEART
		pickup.amount = 1
	else:
		var base := randi_range(GOLD_MIN, GOLD_MAX)
		pickup.amount = EconomySystem.scale_by_block(base, RunManager.get_current_room(), GOLD_GROWTH_PER_BLOCK)
	pickup.position = position + Vector2(0, -12)
	get_parent().add_child.call_deferred(pickup)
