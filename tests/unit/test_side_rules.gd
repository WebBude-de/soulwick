extends GutTest
## Where side segments sit and what they give (M5): after the campfire, the ladder way of a branch,
## the way into every champion room (D-216, Nachtrag 26.10.2026); never into or out of the boss room,
## never twice in a row, never when switched off;
## a segment pays about a combat room (coins × wave count, golden coin = 2 coins, no crystals, the
## chest only on the ladder way), a pit costs what an abyss costs; the jump hint on the first three
## segments; the physics numbers (2.5-tile jump, double jump, apex hang); the plan choice.


func test_campfire_and_ladder_way_lead_into_a_segment() -> void:
	assert_eq(SideRules.roll_reason(true, false, false, false, false, false), SideRules.Reason.BIOME_CHANGE)
	assert_eq(SideRules.roll_reason(false, true, false, false, false, false), SideRules.Reason.LADDER_WAY)
	assert_eq(SideRules.roll_reason(false, false, false, false, false, false), SideRules.Reason.NONE)


func test_never_before_the_boss_never_twice_never_when_skipped() -> void:
	assert_eq(SideRules.roll_reason(true, true, true, true, false, false), SideRules.Reason.NONE, "boss next")
	assert_eq(SideRules.roll_reason(true, true, true, false, true, false), SideRules.Reason.NONE, "segment before")
	assert_eq(SideRules.roll_reason(true, true, true, false, false, true), SideRules.Reason.NONE, "switched off")
	assert_false(SideRules.allows_ladder_way(true, false, false))
	assert_false(SideRules.allows_ladder_way(false, true, false))
	assert_false(SideRules.allows_ladder_way(false, false, true))
	assert_true(SideRules.allows_ladder_way(false, false, false))


func test_the_way_into_a_champion_room_is_a_run_and_nothing_else_draws() -> void:
	assert_eq(SideRules.roll_reason(false, false, false, false, false, false, true), SideRules.Reason.SHARE, "into the champion")
	assert_eq(SideRules.roll_reason(false, false, false, false, false, false, false), SideRules.Reason.NONE, "no random ways")
	assert_eq(SideRules.roll_reason(false, false, false, false, true, false, true), SideRules.Reason.NONE, "never twice in a row")
	assert_eq(SideRules.roll_reason(false, false, false, false, false, true, true), SideRules.Reason.NONE, "switched off")
	assert_eq(SideRules.roll_reason(false, false, true, false, false, false, true), SideRules.Reason.NONE, "never out of the boss room")
	assert_eq(SideRules.roll_reason(false, true, false, false, false, false, true), SideRules.Reason.LADDER_WAY, "the ladder way keeps its chest")


func test_coins_scale_like_combat_room_gold() -> void:
	assert_eq(SideRules.coin_gold(16), 1, "one gold per coin before room 30")
	assert_eq(SideRules.coin_gold(31), RoomSequence.get_wave_count(31), "two waves, twice the gold")
	assert_eq(SideRules.coin_gold(61), RoomSequence.get_wave_count(61))
	assert_eq(SideRules.golden_coin_gold(16), 2, "the golden coin = two coins")
	assert_eq(SideRules.coin_gold(16, 1.6), 2, "the village gold multiplier counts (rounded)")
	assert_eq(SideRules.coin_gold(16, 0.0), 1, "never less than one")


func test_a_segment_pays_about_a_combat_room() -> void:
	# A normal combat room before room 30: 4-6 enemies at about 1 gold plus 1-2 from crates.
	var room_low := 4 + 1
	var room_high := 6 + 2
	for id in SidePlans.all_ids():
		var layout := SidePlans.build(id)
		var gold := SideRules.segment_gold(layout.coins.size(), 16)
		assert_between(gold, room_low, room_high + 1, "%s: %d gold if every coin is taken" % [id, gold])
	assert_eq(SideRules.ENEMY_GOLD, 0, "side enemies drop nothing")


func test_chest_only_on_the_ladder_way() -> void:
	assert_true(SideRules.has_chest(SideRules.Reason.LADDER_WAY))
	assert_false(SideRules.has_chest(SideRules.Reason.BIOME_CHANGE))
	assert_false(SideRules.has_chest(SideRules.Reason.AFTER_REST))


func test_pit_costs_what_an_abyss_costs() -> void:
	assert_eq(SideRules.pit_damage(), ChasmRules.fall_damage(), "a whole heart like an abyss in a room")


func test_jump_hint_on_the_first_three_segments() -> void:
	assert_true(SideRules.shows_jump_hint(0))
	assert_true(SideRules.shows_jump_hint(2))
	assert_false(SideRules.shows_jump_hint(3))


func test_jump_reaches_two_and_a_half_tiles() -> void:
	assert_almost_eq(SideRules.jump_height(), SideRules.JUMP_HEIGHT_TILES * SideRules.TILE, 1.0)
	assert_almost_eq(SideRules.jump_velocity_for(2.5 * SideRules.TILE), SideRules.JUMP_VELOCITY, 1.0)
	assert_almost_eq(SideRules.jump_velocity_for(SideRules.DOUBLE_JUMP_HEIGHT_TILES * SideRules.TILE), SideRules.DOUBLE_JUMP_VELOCITY, 1.0)
	assert_almost_eq(SideRules.double_jump_height(), 4.5 * SideRules.TILE, 2.0, "both jumps: 4.5 tiles")


func test_gravity_hangs_at_the_apex_and_falls_faster() -> void:
	var rising := PlayerSideMotion.gravity_for(-500.0)
	var apex := PlayerSideMotion.gravity_for(-20.0)
	var falling := PlayerSideMotion.gravity_for(500.0)
	assert_eq(rising, SideRules.GRAVITY)
	assert_lt(apex, rising, "a short hang at the top")
	assert_gt(falling, rising, "faster down than up")


func test_segment_rng_is_derived_and_stable() -> void:
	var a := SideRules.make_rng(1234, 16)
	var b := SideRules.make_rng(1234, 16)
	var c := SideRules.make_rng(1234, 17)
	var first := a.randi()
	assert_eq(b.randi(), first, "same run and slot = same segment")
	assert_ne(c.randi(), first, "another slot, another segment")


func test_pick_draws_one_of_twelve_layouts_of_the_biome() -> void:
	var seen := {}
	var turrets := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 400:
		var layout := SidePlans.pick(&"shadow_realm", rng)
		assert_eq(layout.biome_id, &"shadow_realm")
		assert_true(SidePlans.ids_for(&"shadow_realm").has(layout.plan_id))
		assert_gte(layout.tier, SideRules.MAX_TIER - 1, "SV2: only the current and the previous tier")
		seen["%s_%s" % [layout.plan_id, layout.is_mirrored]] = true
		if layout.turrets_enabled:
			turrets += 1
	# SV2: the plans of the last two tiers, each plain and mirrored.
	var pool := SidePlans.ids_for(&"shadow_realm", SideRules.MAX_TIER, SidePlans.pick_min_tier(SideRules.MAX_TIER))
	assert_eq(seen.size(), pool.size() * 2, "every plan of the pool, each plain and mirrored")
	assert_between(turrets, 150, 250, "turrets in about half of the segments (%d of 400)" % turrets)
	assert_true(SidePlans.build(&"crypt_steps").turrets_enabled, "tools and tests build with turrets")
	assert_true(SidePlans.build(&"crypt_steps", true).turrets_enabled, "mirroring keeps the flag")
	var again := RandomNumberGenerator.new()
	again.seed = 9
	var other := RandomNumberGenerator.new()
	other.seed = 9
	assert_eq(SidePlans.pick(&"crypt", again).plan_id, SidePlans.pick(&"crypt", other).plan_id, "same seed, same plan")


func test_texts_exist_in_both_tables() -> void:
	for key in [&"SIDE_DESCENT_TITLE", &"SIDE_DESCENT_SUB", &"SIDE_HINT_JUMP", &"SIDE_GOLDEN_COIN_TITLE",
			&"SIDE_GOLDEN_COIN_SUB", &"SIDE_WAY_NAME", &"SIDE_OPTION_SKIP", &"SIDE_OPTION_SKIP_NOTE"]:
		assert_true(DungeonTexts.has_text(key), "%s in DungeonTexts" % key)
	for key in [&"SIDE_GOLDEN_COIN_GOLD"]:
		assert_true(Loc.has_key(key, &"en") and Loc.has_key(key, &"de"), "%s in the CSV (en + de)" % key)
	var csv := FileAccess.get_file_as_string("res://localization/translations.csv")
	assert_true(csv.contains("SIDE_DESCENT_TITLE,\"Descent\",\"Abstieg\""), "English and German in the CSV")
	assert_eq(DungeonTexts.t(&"SIDE_HINT_JUMP", ["Leertaste"]).count("Leertaste"), 1)
