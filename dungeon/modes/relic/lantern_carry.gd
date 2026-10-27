class_name LanternCarry
extends Node
## "This player carries something with both hands" - the relic of "Reliquie holen" (RAEUME
## §3.5; before the soul lantern, A9) - state per player at the player (D-088): a child node of the
## Player named NODE_NAME while it carries. The carrier walks slower (RelicRules.CARRY_SPEED_FACTOR),
## cannot attack, but may dash. The name stays: player.gd and weapon_controller.gd ask it.
## Decision: can_attack(player). Hooks for the integrator (player.gd, weapon_controller.gd) ask it;
## until they are wired, this node blocks attacks itself by keeping the weapon's attack cooldown
## up and switching the special input off (restored when the lantern is put down).

const NODE_NAME := &"LanternCarry"
## Weapon cooldown kept while carrying (fallback until the hooks are wired).
const BLOCK_COOLDOWN := 0.1

var player: Player = null
var lantern: Node2D = null

var _special_input_before := true


## Marks player as carrier of lantern. Returns the node (or null without a player).
static func attach(target: Player, carried: Node2D) -> LanternCarry:
	if target == null or not is_instance_valid(target):
		return null
	var carry := of(target)
	if carry == null:
		carry = LanternCarry.new()
		carry.name = NODE_NAME
		carry.player = target
		target.add_child(carry)
		carry._begin()
	carry.lantern = carried
	return carry


## Ends carrying (lantern put down, set in, carrier down). Safe to call twice.
static func detach(target: Node) -> void:
	var carry := of(target)
	if carry == null:
		return
	carry._end()
	target.remove_child(carry)
	carry.free()


static func of(target: Node) -> LanternCarry:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NodePath(NODE_NAME)) as LanternCarry


static func is_carrying(target: Node) -> bool:
	return of(target) != null


## The decision for the attack hooks: a carrier does not attack.
static func can_attack(target: Node) -> bool:
	return not is_carrying(target)


func _physics_process(_delta: float) -> void:
	_block_attacks()


func _begin() -> void:
	ToxicPuddle.apply_slow(player, get_instance_id(), RelicRules.CARRY_SPEED_FACTOR)
	var weapons := player.weapon_controller
	if weapons != null:
		_special_input_before = weapons.handle_special_input
		weapons.handle_special_input = false
		_block_attacks()


func _end() -> void:
	if player == null or not is_instance_valid(player):
		return
	ToxicPuddle.apply_slow(player, get_instance_id(), 1.0)
	var weapons := player.weapon_controller
	if weapons != null:
		weapons.handle_special_input = _special_input_before


## Fallback until player.gd asks can_attack(): a weapon on cooldown does not swing or shoot.
func _block_attacks() -> void:
	var weapons := player.weapon_controller if player != null and is_instance_valid(player) else null
	if weapons == null:
		return
	var left: Variant = weapons.get(&"_cooldown_left")
	if left is float and float(left) < BLOCK_COOLDOWN:
		weapons.set(&"_cooldown_left", BLOCK_COOLDOWN)
