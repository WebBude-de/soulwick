extends GutTest
## Forge values per level (D-087: "Max-HP 6 → 7" instead of "+1 je Stufe") and the run-start banner
## that sums up all village bonuses. Uses a test save file only.

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
	assert_almost_eq(player.health.get_max_health(), MetaProgression.BASE_MAX_HEALTH, 0.001, "forge shows the real base max HP")
	assert_almost_eq(player.dash_cooldown, MetaProgression.BASE_DASH_COOLDOWN, 0.001, "forge shows the real dash cooldown")


func test_value_matches_effect_getters_at_every_level() -> void:
	for id in MetaProgression.UPGRADE_ORDER:
		for level in MetaProgression.get_max_level(id) + 1:
			SaveManager.set_meta_level(id, level)
			var value := MetaProgression.get_value_at_level(id, level)
			match id:
				MetaProgression.VITALITY:
					assert_almost_eq(value, MetaProgression.BASE_MAX_HEALTH + MetaProgression.get_bonus_max_health(), 0.001)
				MetaProgression.START_SHIELD:
					assert_almost_eq(value, MetaProgression.get_start_shield(), 0.001)
				MetaProgression.SHARPNESS:
					assert_almost_eq(value, MetaProgression.get_damage_bonus(), 0.001)
				MetaProgression.GOLD_GREED:
					assert_almost_eq(value, MetaProgression.get_gold_multiplier() - 1.0, 0.001)
				MetaProgression.DASH_TRAINING:
					assert_almost_eq(value, maxf(MetaProgression.MIN_DASH_COOLDOWN,
						MetaProgression.BASE_DASH_COOLDOWN - MetaProgression.get_dash_cooldown_reduction()), 0.001)
				MetaProgression.ARSENAL:
					assert_eq(int(value), level)
			SaveManager.set_meta_level(id, 0)


func test_value_texts_per_level() -> void:
	var expected := {
		MetaProgression.VITALITY: ["6", "7", "8", "9", "10", "11"],
		MetaProgression.START_SHIELD: ["0", "3", "6", "9"],
		MetaProgression.SHARPNESS: ["+0 %", "+10 %", "+20 %", "+30 %", "+40 %"],
		MetaProgression.GOLD_GREED: ["+0 %", "+15 %", "+30 %", "+45 %"],
		MetaProgression.DASH_TRAINING: ["1,5 s", "1,35 s", "1,2 s", "1,05 s"],
		MetaProgression.ARSENAL: ["keine", "Bogen", "Bogen oder Stab"],
	}
	for id in expected:
		var texts: Array = expected[id]
		assert_eq(texts.size(), MetaProgression.get_max_level(id) + 1, "one text per level of %s" % id)
		for level in texts.size():
			assert_eq(MetaProgression.format_value_at_level(id, level), texts[level], "%s level %d" % [id, level])


func test_level_step_shows_current_and_next_value() -> void:
	assert_eq(MetaProgression.describe_level_step(MetaProgression.VITALITY, 0), "Max-HP 6 → 7")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SHARPNESS, 1), "Schaden +10 % → +20 %")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.START_SHIELD, 2), "Schild 6 → 9")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.GOLD_GREED, 0), "Gold +0 % → +15 %")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.DASH_TRAINING, 1), "Dash-Abklingzeit 1,35 s → 1,2 s")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.ARSENAL, 0), "Zweite Startwaffe: keine → Bogen")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.ARSENAL, 1), "Zweite Startwaffe: Bogen → Bogen oder Stab")


func test_level_step_at_max_has_no_arrow() -> void:
	for id in MetaProgression.UPGRADE_ORDER:
		var text := MetaProgression.describe_level_step(id, MetaProgression.get_max_level(id))
		assert_false(text.contains("→"), "%s at max: %s" % [id, text])
		assert_true(text.ends_with("(max.)"), text)
	assert_eq(MetaProgression.describe_level_step(MetaProgression.VITALITY, 5), "Max-HP 11 (max.)")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SHARPNESS, 4), "Schaden +40 % (max.)")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.START_SHIELD, 3), "Schild 9 (max.)")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.GOLD_GREED, 3), "Gold +45 % (max.)")


func test_describe_next_level_uses_saved_level() -> void:
	SaveManager.set_meta_level(MetaProgression.VITALITY, 2)
	assert_eq(MetaProgression.describe_next_level(MetaProgression.VITALITY), "Max-HP 8 → 9")
	assert_eq(MetaProgression.describe_level_step(&"unknown", 1), "")


func test_format_number_uses_german_decimals() -> void:
	assert_eq(MetaProgression.format_number(7.0), "7")
	assert_eq(MetaProgression.format_number(1.35), "1,35")
	assert_eq(MetaProgression.format_number(1.5), "1,5")
	assert_eq(MetaProgression.format_number(0.0), "0")
	assert_eq(MetaProgression.format_number(10.0), "10")


func test_every_upgrade_has_summary_and_stat_label() -> void:
	for id in MetaProgression.UPGRADE_ORDER:
		var info: Dictionary = MetaProgression.UPGRADES[id]
		assert_false(String(info.get("summary", "")).is_empty(), String(id))
		assert_false(String(info.get("stat", "")).is_empty(), String(id))


# --- Run-start banner ---

func test_no_bonus_means_no_banner() -> void:
	var none: Array[String] = []
	assert_eq(MetaProgression.get_run_start_summary(none), "")
	assert_eq(MetaProgression.get_run_start_banner_line(none), "")


func test_forge_bonus_parts_for_levels() -> void:
	var levels := {
		MetaProgression.VITALITY: 2, MetaProgression.START_SHIELD: 1, MetaProgression.SHARPNESS: 4,
		MetaProgression.GOLD_GREED: 1, MetaProgression.DASH_TRAINING: 2, MetaProgression.ARSENAL: 1,
	}
	var parts := MetaProgression.describe_forge_bonuses(levels, MetaProgression.WEAPON_BOW)
	assert_eq(parts, ["+2 Max-HP", "+3 Schild", "+40 % Schaden", "+15 % Gold", "−0,3 s Dash", "Bogen"] as Array[String])


func test_forge_bonus_parts_skip_level_zero_and_clamp() -> void:
	var parts := MetaProgression.describe_forge_bonuses({MetaProgression.SHARPNESS: 99}, &"")
	assert_eq(parts, ["+40 % Schaden"] as Array[String], "clamped to max level, nothing else listed")
	assert_true(MetaProgression.describe_forge_bonuses({MetaProgression.ARSENAL: 1}, &"").is_empty(), "no weapon without a choice")


func test_banner_sums_forge_and_proviant() -> void:
	SaveManager.set_meta_level(MetaProgression.VITALITY, 2)
	SaveManager.set_meta_level(MetaProgression.SHARPNESS, 2)
	SaveManager.set_meta_level(MetaProgression.ARSENAL, 1)
	SaveManager.set_second_weapon(MetaProgression.WEAPON_BOW)
	var applied: Array[String] = ["Heiltrank: +2 Max-HP"]
	assert_eq(MetaProgression.get_run_start_summary(applied), "+2 Max-HP · +20 % Schaden · Bogen · Heiltrank: +2 Max-HP")
	assert_eq(MetaProgression.get_run_start_banner_line(applied), "Aus dem Dorf: +2 Max-HP, +20 % Schaden, Bogen, Heiltrank: +2 Max-HP")


func test_banner_with_proviant_only() -> void:
	var applied: Array[String] = ["Goldbeutel: +25 % Gold"]
	assert_eq(MetaProgression.get_run_start_summary(applied), "Goldbeutel: +25 % Gold")
	assert_eq(MetaProgression.get_run_banner_title(), "Aus dem Dorf")


func test_banner_matches_applied_run() -> void:
	SaveManager.set_meta_level(MetaProgression.VITALITY, 1)
	SaveManager.add_pending_boost(MetaProgression.BOOST_POTION)
	RunManager.start_run()
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var applied := MetaProgression.apply_to_run(player, null)
	assert_eq(MetaProgression.get_run_start_summary(applied), "+1 Max-HP · Heiltrank: +2 Max-HP")
	assert_almost_eq(player.health.get_max_health(), MetaProgression.BASE_MAX_HEALTH + 3.0, 0.001)
	RunManager.end_run(RunManager.EndReason.ABORT)
