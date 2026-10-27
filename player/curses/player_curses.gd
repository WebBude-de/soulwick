class_name PlayerCurses
extends Node
## Curses of one player for the rest of the run (pact altar, D-112). Lives as a child
## node of its player (per-player state, D-088) and is attached at runtime by ensure(), so player.gd
## does not need to know it. In co-op a pact only curses the player who sealed it.
## All queries are static and take the player: enemies, the vision, the fountain and the Tab
## overview ask the same place, and a player without curses gets the neutral value (factor 1).
## Decision and effect are separate (D-088): add_curse() records and emits curse_added; the effect
## on this player (lower max HP) follows the signal.

signal curse_added(curse: Curse)

enum Curse { FRAILTY, HASTE, GLOOM, DRY_FOUNTAINS }

const NODE_NAME := &"PlayerCurses"
## Curse values (D-112, TESTWERTE).
## FRAILTY: -1 heart = 2 HP of maximum health; never below MIN_MAX_HEALTH.
const MAX_HEALTH_LOSS := 2.0  # TESTWERT
const MIN_MAX_HEALTH := 2.0  # TESTWERT
## HASTE: enemies move this much faster (hook for enemies/, see enemy_speed_factor()).
const ENEMY_SPEED_FACTOR := 1.1  # TESTWERT
## GLOOM: light circle of the player (hook for the vision, see vision_factor()).
const VISION_FACTOR := 0.8  # TESTWERT
## DRY_FOUNTAINS: fountains heal only this share.
const FOUNTAIN_HEAL_FACTOR := 0.5  # TESTWERT

var _curses: Array[Curse] = []


func _init() -> void:
	# In _init, so the effect also follows for a player that is not in the tree yet.
	curse_added.connect(_on_curse_added)


## Curses node of player, null if the player has none yet.
static func of(player: Node) -> PlayerCurses:
	if player == null or not is_instance_valid(player):
		return null
	return player.get_node_or_null(NodePath(NODE_NAME)) as PlayerCurses


## Curses node of player; created and attached on first use.
static func ensure(player: Node) -> PlayerCurses:
	var curses := of(player)
	if curses != null or player == null:
		return curses
	curses = PlayerCurses.new()
	curses.name = NODE_NAME
	player.add_child(curses)
	return curses


static func get_curses_of(player: Node) -> Array[Curse]:
	var curses := of(player)
	var result: Array[Curse] = []
	if curses != null:
		result.assign(curses._curses)
	return result


static func has_curse(player: Node, curse: Curse) -> bool:
	return get_curses_of(player).has(curse)


## Speed factor of enemies chasing player (1.0 without HASTE).
static func enemy_speed_factor(player: Node) -> float:
	return ENEMY_SPEED_FACTOR if has_curse(player, Curse.HASTE) else 1.0


## Speed factor for enemies that do not pick a single target: the strongest of all living players.
static func group_enemy_speed_factor(players: Array) -> float:
	var factor := 1.0
	for player: Node in players:
		if player != null and is_instance_valid(player):
			factor = maxf(factor, enemy_speed_factor(player))
	return factor


## Light circle factor of player (1.0 without GLOOM; Klarsicht, KE5, makes it immune).
static func vision_factor(player: Node) -> float:
	return VISION_FACTOR if has_curse(player, Curse.GLOOM) and not MetaProgression.player_blind_immune(player) else 1.0


## Share of a fountain heal player gets (1.0 without DRY_FOUNTAINS).
static func fountain_heal_factor(player: Node) -> float:
	return FOUNTAIN_HEAL_FACTOR if has_curse(player, Curse.DRY_FOUNTAINS) else 1.0


## A curse can be taken once; FRAILTY only while the maximum stays at MIN_MAX_HEALTH or above.
static func can_take(player: Node, curse: Curse) -> bool:
	if player == null or has_curse(player, curse):
		return false
	if curse == Curse.FRAILTY:
		var target := player as Player
		return target == null or target.health.get_max_health() - MAX_HEALTH_LOSS >= MIN_MAX_HEALTH
	return true


## Curses a pact may still demand from player, in Curse order.
static func get_available(player: Node) -> Array[Curse]:
	var available: Array[Curse] = []
	for curse: Curse in Curse.values():
		if can_take(player, curse):
			available.append(curse)
	return available


## Translation keys (D-111): name and short effect text ("%s"/"%d" take the values below).
const NAME_KEYS := {
	Curse.FRAILTY: &"CURSE_FRAILTY",
	Curse.HASTE: &"CURSE_HASTE",
	Curse.GLOOM: &"CURSE_GLOOM",
	Curse.DRY_FOUNTAINS: &"CURSE_DRY_FOUNTAINS",
}
const EFFECT_KEYS := {
	Curse.FRAILTY: &"CURSE_FRAILTY_EFFECT",
	Curse.HASTE: &"CURSE_HASTE_EFFECT",
	Curse.GLOOM: &"CURSE_GLOOM_EFFECT",
	Curse.DRY_FOUNTAINS: &"CURSE_DRY_FOUNTAINS_EFFECT",
}


## Curse name in the current language.
static func get_curse_name(curse: int) -> String:
	return Loc.t(NAME_KEYS[curse]) if NAME_KEYS.has(curse) else ""


## Short effect text for the altar and the Tab overview, in the current language.
static func get_curse_effect(curse: int) -> String:
	match curse:
		Curse.FRAILTY:
			return Loc.t(EFFECT_KEYS[curse], [_number(MAX_HEALTH_LOSS * 0.5)])
		Curse.HASTE:
			return Loc.t(EFFECT_KEYS[curse], [roundi((ENEMY_SPEED_FACTOR - 1.0) * 100.0)])
		Curse.GLOOM:
			return Loc.t(EFFECT_KEYS[curse], [roundi((1.0 - VISION_FACTOR) * 100.0)])
		Curse.DRY_FOUNTAINS:
			return Loc.t(EFFECT_KEYS[curse], [roundi(FOUNTAIN_HEAL_FACTOR * 100.0)])
	return ""


## Records a curse for the rest of the run. false if it was not allowed (see can_take).
func add_curse(curse: Curse) -> bool:
	if not can_take(get_parent(), curse):
		return false
	_curses.append(curse)
	curse_added.emit(curse)
	return true


func get_curses() -> Array[Curse]:
	return _curses.duplicate()


## Effects on this player. HASTE, GLOOM and DRY_FOUNTAINS act through the queries above.
func _on_curse_added(curse: Curse) -> void:
	var player := get_parent() as Player
	if player == null or curse != Curse.FRAILTY:
		return
	var health := player.health
	var new_max := maxf(MIN_MAX_HEALTH, health.get_max_health() - MAX_HEALTH_LOSS)
	health.max_health = new_max
	if health.get_health() > new_max:
		health.take_damage(health.get_health() - new_max)
	else:
		# Only the maximum changed: the HUD hearts still need to know.
		health.health_changed.emit(health.get_health(), new_max)


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
