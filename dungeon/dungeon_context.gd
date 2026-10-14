class_name DungeonContext
extends RefCounted
## Shared references of one run, handed to rooms and special-room content.
## Holds no gameplay state of its own; every value is owned by the referenced system.

var manager: DungeonManager = null
var player: Player = null
var upgrade_manager: UpgradeManager = null
var economy: EconomySystem = null
var ui: DungeonUI = null
var rng: RandomNumberGenerator = null
var weapon_pool: Array[WeaponData] = []


## Weapons from the pool whose type the player does not own yet.
func get_unowned_weapons() -> Array[WeaponData]:
	var unowned: Array[WeaponData] = []
	for weapon in weapon_pool:
		if player == null or not player.weapon_controller.has_weapon_type(weapon.weapon_type):
			unowned.append(weapon)
	return unowned


func get_owned_weapons() -> Array[WeaponData]:
	if player == null:
		return []
	return player.weapon_controller.get_owned_weapons()
