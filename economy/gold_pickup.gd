class_name GoldPickup
extends Area2D
## Gold (or a heart) dropped by enemies and crates. Pops out, then homes in on the player.
## Homing steers straight at the player (no inertia) and collects by distance, so a fast coin can
## neither orbit the player nor tunnel through the small player collider.
## Never in an abyss (A4): a pickup that appears over a pit moves to the nearest solid floor, and
## the pop stops at the rim. Homing may fly over pits (it is on its way to a player).

enum Kind { GOLD, HEART }

const POP_TIME := 0.35
const POP_FRICTION := 300.0
const MAGNET_DELAY := 0.5
const MAGNET_ACCELERATION := 900.0
const MAX_SPEED := 650.0
const COLLECT_DISTANCE := 20.0
const HEART_TEXTURE: Texture2D = preload("res://art/ui/heart_full.png")

var amount := 1
var kind := Kind.GOLD

var _age := 0.0
var _pop_velocity := Vector2.ZERO
var _homing_speed := 0.0
var _collected := false

@onready var _sprite: AnimatedProp = $Sprite


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	monitorable = false
	body_entered.connect(_on_body_entered)
	_pop_velocity = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 120.0)
	var probe := PitProbe.probe_for(self)
	if probe.call(global_position):
		global_position = PitProbe.nearest_safe_point(global_position, probe)
	DropShadow.attach(self, 7.0, 10.0)
	if kind == Kind.HEART:
		_sprite.strip = HEART_TEXTURE
		($Glow as LightSource).radius = 60.0


func _physics_process(delta: float) -> void:
	_age += delta
	var player := EnemyTargeting.nearest_living(get_tree().get_nodes_in_group(&"player"), global_position) as Player
	if _age < MAGNET_DELAY or player == null or not player.is_alive():
		_pop_velocity = _pop_velocity.move_toward(Vector2.ZERO, POP_FRICTION * delta)
		var next := global_position + _pop_velocity * delta
		if _pop_velocity != Vector2.ZERO and PitProbe.is_pit_at(get_world_2d(), next):
			_pop_velocity = Vector2.ZERO
			return
		global_position = next
		return
	_homing_speed = minf(_homing_speed + MAGNET_ACCELERATION * delta, MAX_SPEED)
	var to_player := player.global_position - global_position
	var step := _homing_speed * delta
	if to_player.length() <= COLLECT_DISTANCE + step:
		_collect(player)
		return
	global_position += to_player.normalized() * step


func _on_body_entered(body: Node2D) -> void:
	if body is Player and _age >= POP_TIME:
		_collect(body)


func _collect(player: Player) -> void:
	if _collected:
		return
	_collected = true
	if kind == Kind.HEART:
		player.health.heal(amount)
		Sfx.play_at(player, &"heart", player.global_position)
	else:
		RunManager.add_run_gold(amount)
		Sfx.play_at(player, &"coin", player.global_position, -4.0)
	queue_free()
