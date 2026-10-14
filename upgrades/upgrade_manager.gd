class_name UpgradeManager
extends Node
## Run-wide upgrade stacks and availability (D-027). Scene-local to the dungeon, not an autoload.
## Upgrades are not bound to weapon instances, so they survive weapon swaps.

signal upgrade_acquired(upgrade: UpgradeData, stacks: int)

const OFFER_SIZE := 3

@export var upgrade_pool: Array[UpgradeData] = []

## Receives instant effects such as "Schildverstärkung". Set by the dungeon on player spawn.
var player: Player = null

var _stacks: Dictionary[StringName, int] = {}


func get_stacks(upgrade_id: StringName) -> int:
	return _stacks.get(upgrade_id, 0)


func is_maxed(upgrade: UpgradeData) -> bool:
	return upgrade.is_limited() and get_stacks(upgrade.id) >= upgrade.max_stacks


func acquire_upgrade(upgrade: UpgradeData) -> bool:
	if upgrade == null or is_maxed(upgrade):
		return false
	var stacks := get_stacks(upgrade.id) + 1
	_stacks[upgrade.id] = stacks
	if upgrade.effect == UpgradeData.Effect.SHIELD_GAIN and player != null:
		player.shield.add_shield(upgrade.value)
	upgrade_acquired.emit(upgrade, stacks)
	EventBus.upgrade_acquired.emit(upgrade.id, stacks)
	return true


func get_active_upgrades() -> Array[UpgradeData]:
	var active: Array[UpgradeData] = []
	for upgrade in upgrade_pool:
		if get_stacks(upgrade.id) > 0:
			active.append(upgrade)
	return active


## Upgrades below their stack limit that affect at least one owned weapon (or every attack).
func get_available_upgrades(owned_weapons: Array[WeaponData] = []) -> Array[UpgradeData]:
	var available: Array[UpgradeData] = []
	for upgrade in upgrade_pool:
		if is_maxed(upgrade):
			continue
		if _is_relevant(upgrade, owned_weapons):
			available.append(upgrade)
	return available


## Up to count different available upgrades; no duplicates within one offer (D-027).
func roll_offer(owned_weapons: Array[WeaponData], rng: RandomNumberGenerator, count := OFFER_SIZE) -> Array[UpgradeData]:
	var candidates := get_available_upgrades(owned_weapons)
	var offer: Array[UpgradeData] = []
	while not candidates.is_empty() and offer.size() < count:
		offer.append(candidates.pop_at(rng.randi_range(0, candidates.size() - 1)))
	return offer


## Sum of value * stacks of all upgrades with this effect that apply to an attack with these tags.
func get_modifier(effect: UpgradeData.Effect, attack_tags: Array[StringName]) -> float:
	var total := 0.0
	for upgrade in upgrade_pool:
		if upgrade.effect != effect:
			continue
		var stacks := get_stacks(upgrade.id)
		if stacks > 0 and upgrade.applies_to(attack_tags):
			total += upgrade.value * stacks
	return total


## Sum for effects that are not tied to an attack (ON_KILL rewards).
func get_total(effect: UpgradeData.Effect) -> float:
	var total := 0.0
	for upgrade in upgrade_pool:
		if upgrade.effect == effect:
			total += upgrade.value * get_stacks(upgrade.id)
	return total


func _is_relevant(upgrade: UpgradeData, owned_weapons: Array[WeaponData]) -> bool:
	if upgrade.applicable_tags.is_empty() and upgrade.required_tags.is_empty():
		return true
	for weapon in owned_weapons:
		if weapon != null and upgrade.applies_to(weapon.tags):
			return true
	return false
