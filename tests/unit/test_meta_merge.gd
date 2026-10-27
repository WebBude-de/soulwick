extends GutTest
## Merge rules of the v5 fields (KONZEPT §10, KE4) as pure functions for the cloud merge (KF9): forge
## and trading post levels take the maximum per key, unlocks the union, the refund marker the
## maximum, the rest comes from the last played state. Also the forge snapshot at the player (co-op
## state, D-088) that a lobby message carries. No save file is touched.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")


func test_forge_levels_take_the_maximum_per_key() -> void:
	var a := {"weapon_sword": 3, "shield_plate": 1, "arsenal_bow": 1}
	var b := {"weapon_sword": 2, "shield_plate": 3, "lantern": 2}
	assert_eq(MetaProgression.merge_levels(a, b), {"weapon_sword": 3, "shield_plate": 3, "arsenal_bow": 1, "lantern": 2})
	assert_eq(MetaProgression.merge_levels(b, a), MetaProgression.merge_levels(a, b), "order does not matter")
	assert_eq(MetaProgression.merge_levels({"luck": "x"}, {"luck": -2}), {"luck": 0}, "non-numbers and negatives count as 0")


func test_trade_levels_take_the_maximum() -> void:
	var merged := MetaProgression.merge_levels({"provision_slot": 1, "luck": 3}, {"provision_slot": 2, "merchant_friend": 1})
	assert_eq(merged, {"provision_slot": 2, "luck": 3, "merchant_friend": 1})


func test_unlocks_are_united() -> void:
	assert_eq(MetaProgression.merge_unlocked(["bow"], ["staff", "bow"]), PackedStringArray(["bow", "staff"]))
	assert_eq(MetaProgression.merge_unlocked([], []), PackedStringArray())
	var levels := MetaProgression.merge_levels({"arsenal_bow": 1}, {"arsenal_hammer": 1})
	assert_eq(MetaProgression.unlocked_weapons_from_levels(levels), PackedStringArray(["sword", "bow", "hammer"]),
		"Arsenal entries are 0/1 levels: their maximum is the union of the unlocks")


func test_refund_marker_takes_the_maximum() -> void:
	assert_eq(MetaProgression.merge_refund_marker(0, 680), 680)
	assert_eq(MetaProgression.merge_refund_marker(680, 0), 680)
	assert_eq(MetaProgression.merge_refund_marker(null, "x"), 0)


func test_rule_per_field() -> void:
	assert_eq(MetaProgression.merge_rule("meta_upgrades", "weapon_bow"), MetaProgression.MERGE_MAX)
	assert_eq(MetaProgression.merge_rule("trade_levels", "luck"), MetaProgression.MERGE_MAX)
	assert_eq(MetaProgression.merge_rule("migration", "v5_refund_gold"), MetaProgression.MERGE_MAX)
	assert_eq(MetaProgression.merge_rule("migration", "v5_weapons"), MetaProgression.MERGE_UNION)
	assert_eq(MetaProgression.merge_rule("progress", "start_weapon"), MetaProgression.MERGE_LAST_PLAYED)
	assert_eq(MetaProgression.merge_rule("boosts", "pending"), MetaProgression.MERGE_LAST_PLAYED, "Proviant: last played")
	assert_eq(MetaProgression.merge_rule("progress", "permanent_gold"), MetaProgression.MERGE_LAST_PLAYED, "D-188 rule 7")


# --- The forge at the player (lobby snapshot) ---

func test_snapshot_from_elsewhere_is_cleaned() -> void:
	var clean := MetaProgression.sanitize_snapshot({
		"weapons": {"sword": 9, "bow": "3", "laser": 5}, "shield_plate": 7, "lantern": -1,
		"start": ["bow", "bow", "staff", "hammer"],
	})
	assert_eq(clean["weapons"]["sword"], 5, "clamped to V")
	assert_eq(clean["weapons"]["bow"], 0, "a text is no level")
	assert_false((clean["weapons"] as Dictionary).has("laser"), "unknown weapons dropped")
	assert_eq(clean["shield_plate"], 3)
	assert_eq(clean["lantern"], 0)
	assert_eq(clean["start"], ["bow", "staff"], "two different start weapons at most")
	assert_eq(MetaProgression.sanitize_snapshot(null)["start"], ["sword"], "nothing: the sword")


func test_player_without_forge_gets_neutral_values() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var sword := load("res://weapons/data/sword.tres") as WeaponData
	assert_true(MetaProgression.get_player_forge(player).is_empty())
	assert_eq(MetaProgression.player_weapon_damage_bonus(player, sword), 0.0)
	assert_eq(MetaProgression.player_special_factor(player, sword), 1.0)
	assert_false(MetaProgression.player_is_masterwork(player, sword))
	assert_eq(MetaProgression.player_light_factor(player), 1.0)
	assert_eq(MetaProgression.player_weapon_damage_bonus(null, null), 0.0, "safe without a player")


func test_host_puts_a_players_own_snapshot_on_its_copy() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var snapshot := {"weapons": {"hammer": 5}, "shield_plate": 2, "lantern": 3, "start": ["hammer", "sword"]}
	MetaProgression.apply_forge_snapshot(player, snapshot)
	var hammer := player.weapon_controller.get_weapon(0)
	assert_eq(hammer.id, &"hammer", "the player's own start weapon")
	assert_eq(player.weapon_controller.get_weapon(1).id, &"sword")
	assert_almost_eq(MetaProgression.player_weapon_damage_bonus(player, hammer), 0.4, 0.0001, "V: +40 %")
	assert_almost_eq(MetaProgression.player_special_factor(player, hammer), 1.25, 0.0001)
	assert_true(MetaProgression.player_is_masterwork(player, hammer), "Meisterstück")
	assert_almost_eq(MetaProgression.player_light_factor(player), 1.3, 0.0001)
	assert_almost_eq(player.shield.get_shield(), 6.0, 0.001)


func test_effect_values_per_level() -> void:
	assert_almost_eq(MetaProgression.weapon_damage_factor_at(0), 1.0, 0.0001)
	assert_almost_eq(MetaProgression.weapon_damage_factor_at(5), 1.4, 0.0001)
	assert_almost_eq(MetaProgression.weapon_damage_factor_at(9), 1.4, 0.0001, "clamped")
	assert_eq(MetaProgression.weapon_special_factor_at(2), 1.0)
	assert_almost_eq(MetaProgression.weapon_special_factor_at(3), 1.25, 0.0001)
	assert_false(MetaProgression.is_masterwork_at(4))
	assert_true(MetaProgression.is_masterwork_at(5))
	assert_almost_eq(MetaProgression.light_radius_factor_at(3), 1.3, 0.0001)
