extends GutTest
## Forge values per level (D-087, KE4: "Schaden 15 → 16,2" instead of "+8 % je Stufe") and the
## run-start banner that sums up all village bonuses. Uses a test save file only.

const TEST_PATH := "user://test_meta_values.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_locale: String
var _old_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	# The expected texts are German; English is the default language (D-111).
	Loc.apply(&"de")
	_old_path = SaveManager.save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	# P1-8: the last good copy would otherwise stand in for a broken test file.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".prev.bak"))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


# --- Values per level ---

func test_base_values_match_player_defaults() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	assert_almost_eq(player.health.get_max_health(), MetaProgression.BASE_MAX_HEALTH, 0.001)
	assert_almost_eq(player.dash_cooldown, MetaProgression.BASE_DASH_COOLDOWN, 0.001)


func test_weapon_values_use_the_real_base_damage() -> void:
	for weapon in MetaProgression.WEAPON_ORDER:
		var data := load(MetaProgression.WEAPON_PATHS[weapon]) as WeaponData
		assert_eq(data.id, weapon, "WEAPON_PATHS and WeaponData.id agree")
		for level in MetaProgression.get_max_level(MetaProgression.smith_id(weapon)) + 1:
			assert_almost_eq(MetaProgression.get_value_at_level(MetaProgression.smith_id(weapon), level),
				data.base_damage * (1.0 + 0.08 * level), 0.001, "%s level %d" % [weapon, level])


func test_value_matches_effect_getters_at_every_level() -> void:
	for id in MetaProgression.UPGRADE_ORDER:
		for level in MetaProgression.get_max_level(id) + 1:
			SaveManager.set_meta_level(id, level)
			var value := MetaProgression.get_value_at_level(id, level)
			match id:
				MetaProgression.SHIELD_PLATE:
					assert_almost_eq(value, MetaProgression.get_start_shield(), 0.001)
				MetaProgression.LANTERN:
					assert_almost_eq(value, MetaProgression.get_light_radius_factor() - 1.0, 0.001)
				MetaProgression.SECOND_SLOT:
					assert_eq(MetaProgression.has_second_slot(), level >= 1)
			if MetaProgression.get_kind(id) == MetaProgression.KIND_WEAPON:
				var weapon := MetaProgression.get_upgrade_weapon(id)
				assert_almost_eq(value, MetaProgression.get_weapon_base_damage(weapon) * MetaProgression.weapon_damage_factor(weapon), 0.001)
			elif MetaProgression.get_kind(id) == MetaProgression.KIND_ARSENAL:
				assert_eq(MetaProgression.is_weapon_unlocked(MetaProgression.get_upgrade_weapon(id)), level >= 1)
			SaveManager.set_meta_level(id, 0)


func test_value_texts_per_level() -> void:
	var expected := {
		MetaProgression.SMITH_SWORD: ["15", "16,2", "17,4", "18,6", "19,8", "21"],
		MetaProgression.SMITH_BOW: ["8", "8,6", "9,3", "9,9", "10,6", "11,2"],
		MetaProgression.SHIELD_PLATE: ["0", "3", "6", "9"],
		MetaProgression.LANTERN: ["+0 %", "+10 %", "+20 %", "+30 %"],
		MetaProgression.SECOND_SLOT: ["1", "2"],
		MetaProgression.ARSENAL_BOW: ["gesperrt", "frei"],
	}
	for id in expected:
		var texts: Array = expected[id]
		assert_eq(texts.size(), MetaProgression.get_max_level(id) + 1, "one text per level of %s" % id)
		for level in texts.size():
			assert_eq(MetaProgression.format_value_at_level(id, level), texts[level], "%s level %d" % [id, level])


func test_level_step_shows_current_and_next_value() -> void:
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SMITH_SWORD, 0), "Schaden 15 → 16,2")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SMITH_SWORD, 2), "Schaden 17,4 → 18,6 · Spezial +25 %", "III: the special")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SMITH_SWORD, 4), "Schaden 19,8 → 21 · Meisterstück", "V: masterwork")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SHIELD_PLATE, 2), "Schild 6 → 9")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.LANTERN, 0), "Lichtradius +0 % → +10 %")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SECOND_SLOT, 0), "Startwaffen 1 → 2")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.ARSENAL_STAFF, 0), "Startwaffe: gesperrt → frei")


func test_level_step_at_max_has_no_arrow() -> void:
	for id in MetaProgression.UPGRADE_ORDER:
		var text := MetaProgression.describe_level_step(id, MetaProgression.get_max_level(id))
		assert_false(text.contains("→"), "%s at max: %s" % [id, text])
		if MetaProgression.get_max_level(id) > 1:
			assert_true(text.ends_with("(max.)"), text)
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SMITH_SWORD, 5), "Schaden 21 (max.)")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SHIELD_PLATE, 3), "Schild 9 (max.)")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.LANTERN, 3), "Lichtradius +30 % (max.)")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.ARSENAL_BOW, 1), "Startwaffe: frei", "unlocks have no (max.)")


func test_describe_next_level_uses_saved_level() -> void:
	SaveManager.set_meta_level(MetaProgression.SHIELD_PLATE, 2)
	assert_eq(MetaProgression.describe_next_level(MetaProgression.SHIELD_PLATE), "Schild 6 → 9")
	assert_eq(MetaProgression.describe_level_step(&"unknown", 1), "")


func test_format_number_uses_german_decimals() -> void:
	assert_eq(MetaProgression.format_number(7.0), "7")
	assert_eq(MetaProgression.format_number(1.35), "1,35")
	assert_eq(MetaProgression.format_number(1.5), "1,5")
	assert_eq(MetaProgression.format_number(0.0), "0")
	assert_eq(MetaProgression.format_number(10.0), "10")


func test_every_upgrade_has_texts() -> void:
	for id in MetaProgression.UPGRADE_ORDER:
		for text in [MetaProgression.get_upgrade_name(id), MetaProgression.get_upgrade_summary(id),
				MetaProgression.get_upgrade_effect(id), MetaProgression.get_upgrade_stat(id), MetaProgression.get_upgrade_group(id)]:
			assert_false(text.is_empty(), String(id))
			assert_false(text.begins_with("FORGE_"), "%s translated: %s" % [id, text])
	assert_eq(MetaProgression.get_upgrade_name(MetaProgression.SMITH_DAGGER), "Dolche schmieden")
	assert_eq(MetaProgression.get_upgrade_name(MetaProgression.ARSENAL_HAMMER), "Arsenal: Hammer")
	assert_eq(MetaProgression.get_upgrade_effect(MetaProgression.ARSENAL_BOW), "Bogen als Startwaffe wählbar")
	assert_eq(MetaProgression.get_step_name(MetaProgression.SMITH_SWORD, 3), "Schwert schmieden III")
	assert_eq(MetaProgression.get_step_name(MetaProgression.ARSENAL_BOW, 1), "Arsenal: Bogen", "one level: no number")


# --- Run-start banner ---

func test_no_bonus_means_no_banner() -> void:
	var none: Array[String] = []
	assert_eq(MetaProgression.get_run_start_summary(none), "")
	assert_eq(MetaProgression.get_run_start_banner_line(none), "")


func test_forge_bonus_parts_for_levels() -> void:
	var levels := {MetaProgression.SMITH_BOW: 2, MetaProgression.SHIELD_PLATE: 1, MetaProgression.LANTERN: 2}
	var parts := MetaProgression.describe_forge_bonuses(levels, [MetaProgression.WEAPON_BOW, MetaProgression.WEAPON_STAFF])
	assert_eq(parts, ["Bogen II + Stab", "+3 Schild", "+20 % Licht"] as Array[String])


func test_forge_bonus_parts_skip_level_zero_and_clamp() -> void:
	var parts := MetaProgression.describe_forge_bonuses({MetaProgression.SHIELD_PLATE: 99}, [MetaProgression.WEAPON_SWORD])
	assert_eq(parts, ["+9 Schild"] as Array[String], "clamped to max level, the plain sword is not listed")
	assert_eq(MetaProgression.describe_forge_bonuses({MetaProgression.SMITH_SWORD: 1}, [MetaProgression.WEAPON_SWORD]),
		["Schwert I"] as Array[String], "a smithed sword is")


func test_banner_sums_forge_and_proviant() -> void:
	SaveManager.set_meta_level(MetaProgression.SHIELD_PLATE, 2)
	SaveManager.set_meta_level(MetaProgression.ARSENAL_BOW, 1)
	SaveManager.set_meta_level(MetaProgression.SECOND_SLOT, 1)
	SaveManager.set_second_weapon(MetaProgression.WEAPON_BOW)
	var applied: Array[String] = ["Heiltrank: +2 Max-HP"]
	assert_eq(MetaProgression.get_run_start_summary(applied), "Schwert + Bogen · +6 Schild · Heiltrank: +2 Max-HP")
	assert_eq(MetaProgression.get_run_start_banner_line(applied), "Aus dem Dorf: Schwert + Bogen, +6 Schild, Heiltrank: +2 Max-HP")


func test_banner_with_proviant_only() -> void:
	var applied: Array[String] = ["Goldbeutel: +25 % Gold"]
	assert_eq(MetaProgression.get_run_start_summary(applied), "Goldbeutel: +25 % Gold")
	assert_eq(MetaProgression.get_run_banner_title(), "Aus dem Dorf")


func test_banner_matches_applied_run() -> void:
	SaveManager.set_meta_level(MetaProgression.SHIELD_PLATE, 1)
	SaveManager.add_pending_boost(MetaProgression.BOOST_HEALING_POTION)
	RunManager.start_run()
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var applied := MetaProgression.apply_to_run(player, null)
	assert_eq(MetaProgression.get_run_start_summary(applied), "+3 Schild · Heiltrank: +2 Max-HP")
	assert_almost_eq(player.health.get_max_health(), MetaProgression.BASE_MAX_HEALTH + 2.0, 0.001)
	RunManager.end_run(RunManager.EndReason.ABORT)
