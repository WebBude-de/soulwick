extends GutTest
## Where side segments sit and what they give (M5): after the campfire, the ladder way of a branch,
## 10 % after a rest room; never before the boss, never twice in a row, never when switched off;
## coins pay run gold ×1.5 with carry, the golden coin a crystal, a pit half a heart (never the
## last 0.5 HP); the jump hint on the first three segments; the physics numbers; the plan choice.


func test_campfire_and_ladder_way_lead_into_a_segment() -> void:
	assert_eq(SideRules.roll_reason(true, false, false, false, false, false, null), SideRules.Reason.BIOME_CHANGE)
	assert_eq(SideRules.roll_reason(false, true, false, false, false, false, null), SideRules.Reason.LADDER_WAY)
	assert_eq(SideRules.roll_reason(false, false, false, false, false, false, null), SideRules.Reason.NONE)


func test_never_before_the_boss_never_twice_never_when_skipped() -> void:
	var rng := RandomNumberGenerator.new()
	assert_eq(SideRules.roll_reason(true, true, true, true, false, false, rng), SideRules.Reason.NONE, "boss next")
	assert_eq(SideRules.roll_reason(true, true, true, false, true, false, rng), SideRules.Reason.NONE, "segment before")
	assert_eq(SideRules.roll_reason(true, true, true, false, false, true, rng), SideRules.Reason.NONE, "switched off")
	assert_false(SideRules.allows_ladder_way(true, false, false))
	assert_false(SideRules.allows_ladder_way(false, true, false))
	assert_false(SideRules.allows_ladder_way(false, false, true))
	assert_true(SideRules.allows_ladder_way(false, false, false))


func test_after_a_rest_room_about_one_in_ten() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var hits := 0
	for i in 2000:
		if SideRules.roll_reason(false, false, true, false, false, false, rng) == SideRules.Reason.AFTER_REST:
			hits += 1
	assert_between(hits, 150, 250, "about 10 %% (%d of 2000)" % hits)


func test_only_the_rest_case_draws() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var state := rng.state
	SideRules.roll_reason(true, false, false, false, false, false, rng)
	SideRules.roll_reason(false, true, false, false, false, false, rng)
	SideRules.roll_reason(false, false, false, false, false, false, rng)
	assert_eq(rng.state, state, "no draw without a rest room")
	SideRules.roll_reason(false, false, true, false, false, false, rng)
	assert_ne(rng.state, state, "one draw after a rest room")


func test_coins_pay_one_and_a_half_with_carry() -> void:
	var total := 0
	for i in 8:
		total += SideRules.coin_gold(i)
	assert_eq(total, 12, "8 coins = 12 gold")
	assert_eq(SideRules.coin_gold(0), 1)
	assert_eq(SideRules.coin_gold(1), 2, "the carried half")
	var greedy := 0
	for i in 10:
		greedy += SideRules.coin_gold(i, 1.3)
	assert_eq(greedy, floori(10 * 1.5 * 1.3 + 0.0001), "the village gold multiplier counts too")


func test_pit_costs_half_a_heart_but_never_the_last() -> void:
	assert_eq(SideRules.pit_damage(6.0), 1.0)
	assert_eq(SideRules.pit_damage(1.5), 1.0)
	assert_eq(SideRules.pit_damage(1.0), 0.5)
	assert_eq(SideRules.pit_damage(0.5), 0.0)


func test_jump_hint_on_the_first_three_segments() -> void:
	assert_true(SideRules.shows_jump_hint(0))
	assert_true(SideRules.shows_jump_hint(2))
	assert_false(SideRules.shows_jump_hint(3))


func test_jump_reaches_two_and_a_half_tiles() -> void:
	assert_almost_eq(SideRules.jump_height(), SideRules.JUMP_HEIGHT_TILES * SideRules.TILE, 1.0)
	assert_almost_eq(SideRules.jump_velocity_for(2.5 * SideRules.TILE), SideRules.JUMP_VELOCITY, 1.0)


func test_segment_rng_is_derived_and_stable() -> void:
	var a := SideRules.make_rng(1234, 16)
	var b := SideRules.make_rng(1234, 16)
	var c := SideRules.make_rng(1234, 17)
	var first := a.randi()
	assert_eq(b.randi(), first, "same run and slot = same segment")
	assert_ne(c.randi(), first, "another slot, another segment")


func test_pick_draws_one_of_eight_layouts_of_the_biome() -> void:
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		var layout := SidePlans.pick(&"shadow_realm", rng)
		assert_eq(layout.biome_id, &"shadow_realm")
		assert_true(SidePlans.ids_for(&"shadow_realm").has(layout.plan_id))
		seen["%s_%s" % [layout.plan_id, layout.is_mirrored]] = true
	assert_eq(seen.size(), 8, "four plans, each plain and mirrored")
	var again := RandomNumberGenerator.new()
	again.seed = 9
	var other := RandomNumberGenerator.new()
	other.seed = 9
	assert_eq(SidePlans.pick(&"crypt", again).plan_id, SidePlans.pick(&"crypt", other).plan_id, "same seed, same plan")


func test_texts_exist_in_both_tables() -> void:
	for key in [&"SIDE_DESCENT_TITLE", &"SIDE_DESCENT_SUB", &"SIDE_HINT_JUMP", &"SIDE_GOLDEN_COIN_TITLE",
			&"SIDE_GOLDEN_COIN_SUB", &"SIDE_WAY_NAME", &"SIDE_OPTION_SKIP", &"SIDE_OPTION_SKIP_NOTE"]:
		assert_true(DungeonTexts.has_text(key), "%s in DungeonTexts" % key)
	var csv := FileAccess.get_file_as_string("res://localization/translations.csv")
	assert_true(csv.contains("SIDE_DESCENT_TITLE,\"Descent\",\"Abstieg\""), "English and German in the CSV")
	assert_eq(DungeonTexts.t(&"SIDE_HINT_JUMP", ["Leertaste", "Umschalt"]).count("Leertaste"), 1)
