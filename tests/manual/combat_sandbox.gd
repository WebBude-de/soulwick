extends Node2D
## Manual M1 test arena: player vs. the three enemy types. Not part of the dungeon.
## Enemies respawn once all are dead; the player gets a second weapon to test Q switching.

const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const RESPAWN_DELAY := 2.0

@export var second_weapon: WeaponData

var _spawn_setups: Array[Dictionary] = []
var _alive_enemies := 0

@onready var _enemy_container: Node2D = $Enemies


func _ready() -> void:
	for child in _enemy_container.get_children():
		var enemy := child as Enemy
		if enemy == null:
			continue
		_spawn_setups.append({"data": enemy.data, "position": enemy.position})
		_track(enemy)
	_equip_second_weapon.call_deferred()


func _equip_second_weapon() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null and second_weapon != null:
		player.weapon_controller.equip_weapon(second_weapon, 1)


func _track(enemy: Enemy) -> void:
	_alive_enemies += 1
	enemy.died.connect(_on_enemy_died)


func _on_enemy_died(_enemy: Enemy) -> void:
	_alive_enemies -= 1
	if _alive_enemies > 0:
		return
	await get_tree().create_timer(RESPAWN_DELAY, false).timeout
	for setup in _spawn_setups:
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.data = setup["data"]
		enemy.position = setup["position"]
		_enemy_container.add_child(enemy)
		_track(enemy)
