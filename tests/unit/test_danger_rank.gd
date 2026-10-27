extends GutTest
## Danger level and rank (KE1, D-194, D-196, KONZEPT §3, §3.1): G from the level (floor((L − 1) / 2))
## and from the median deepest room of the 5 newest runs (floor(median / 5) + 1, only with 3 runs
## or more), G = min of both; ranks spark I … beacon III, then soul_master G − 14; XP +5 % per level
## up to DANGER_MAX. DangerRank mirrors the platform contract 1:1 (packages/contracts/src/rank.ts,
## xp.ts runXp): the first tests use exactly the example values of the platform's
## apps/api/test/account-state.test.ts, so both sides stay in step.

var _old_locale: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)


# --- The platform's examples (account-state.test.ts, "danger level and rank (contract)") ---

func test_contract_level_part_median_and_skill_part() -> void:
	var levels: Array[int] = []
	for level in [1, 2, 3, 4, 5, 6, 50]:
		levels.append(DangerRank.danger_from_level(level))
	assert_eq(levels, [0, 0, 1, 1, 2, 2, 24] as Array[int])
	assert_eq(DangerRank.median_room([]), 0)
	assert_eq(DangerRank.median_room([7]), 7)
	assert_eq(DangerRank.median_room([9, 3]), 6)
	assert_eq(DangerRank.median_room([3, 10]), 6)
	assert_eq(DangerRank.median_room([5, 1, 9]), 5)
	assert_eq(DangerRank.median_room([4, 1, 3, 2]), 2)
	# Fewer than 3 runs: unknown (the contract's null), the level decides alone.
	assert_eq(DangerRank.danger_from_skill([]), DangerRank.SKILL_UNKNOWN)
	assert_eq(DangerRank.danger_from_skill([30, 30]), DangerRank.SKILL_UNKNOWN)
	assert_eq(DangerRank.danger_from_skill([10, 12, 14]), 3)
	assert_eq(DangerRank.danger_from_skill([0, 1, 4]), 1)
	# Only the 5 newest (first) values count.
	assert_eq(DangerRank.danger_from_skill([0, 0, 0, 50, 50, 99, 99]), 1)
	assert_eq(DangerRank.danger_from_skill([50, 50, 50, 0, 0, 0, 0]), 11)


func test_contract_danger_level_is_the_smaller_part() -> void:
	assert_eq(DangerRank.danger_level(20, [10, 12, 14]), 3)
	assert_eq(DangerRank.danger_level(3, [100, 100, 100]), 1)
	assert_eq(DangerRank.danger_level(9, [1, 2]), 4)
	assert_eq(DangerRank.danger_level(1, []), 0)
	assert_eq(DangerRank.danger_level(99, [20, 20, 20, 20, 20]), 5)


func test_contract_ranks() -> void:
	var shown: Array[String] = []
	for g in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 16, 30]:
		var rank := DangerRank.rank_for_danger(g)
		shown.append("%s %d" % [rank["tier"], rank["step"]])
	assert_eq(shown, ["spark 1", "spark 2", "spark 3", "candle 1", "candle 3", "flame 1", "flame 3",
		"lantern 1", "lantern 3", "beacon 1", "beacon 3", "soul_master 1", "soul_master 2", "soul_master 16"] as Array[String])
	assert_eq(DangerRank.rank_for_danger(-3), {"tier": DangerRank.SPARK, "step": 1})


## The platform's runXp examples, through AccountProgress.compute_run_xp (same order: sum, co-op
## bonus, danger bonus on both, G limited to DANGER_MAX, then the run cap).
func test_contract_xp_danger_bonus() -> void:
	# rooms 6, champion 1, record rooms 6, first run of the day, solo: 30 + 10 + 30 + 25 = 95.
	var base := {"rooms_cleared": 6, "champions": 1, "room": 6, "record_before": 0, "first_of_day": true, "players": 1}
	assert_eq(AccountProgress.compute_run_xp(base)["xp"], 95)
	var g4 := base.duplicate()
	g4["danger"] = 4
	assert_eq(AccountProgress.compute_run_xp(g4)["xp"], 114, "95 · 20 % = 19")
	# Co-op: rooms 7, boss 1, portal, 3 players: 35 + 50 + 20 = 105, +21 = 126, then 15 % = 18.
	var coop := AccountProgress.compute_run_xp({"rooms_cleared": 7, "bosses": 1, "exit": true, "players": 3, "danger": 3})
	assert_eq(_part(coop, AccountProgress.PART_COOP), 21)
	assert_eq(_part(coop, AccountProgress.PART_DANGER), 18)
	assert_eq(coop["xp"], 144)
	var g50 := base.duplicate()
	g50["danger"] = 50
	assert_eq(_part(AccountProgress.compute_run_xp(g50), AccountProgress.PART_DANGER), 142, "above DANGER_MAX it counts as 30: 95 · 150 %")
	assert_eq(AccountProgress.compute_run_xp(g50)["xp"], 237)
	var big := base.duplicate()
	big["rooms_cleared"] = 300
	big["room"] = 6
	var big_hard := big.duplicate()
	big_hard["danger"] = 10
	assert_eq(AccountProgress.compute_run_xp(big)["xp"], 1565, "under the cap without danger")
	assert_eq(AccountProgress.compute_run_xp(big_hard)["xp"], AccountProgress.MAX_XP_PER_RUN, "the danger bonus hits the cap")
	assert_eq(DangerRank.DANGER_MAX, 30)


# --- Game side ---

func test_skill_part_takes_only_the_newest_five() -> void:
	assert_eq(DangerRank.danger_from_skill([10, 20, 15, 25, 5]), 4, "odd: median 15")
	assert_eq(DangerRank.danger_from_skill([9, 12, 4, 30]), 3, "even: (9 + 12) / 2 = 10.5 -> 10 -> 3")
	assert_eq(DangerRank.danger_from_skill([3, 4, 2, 100, 100, 100, 100]), 1, "newest first: median 3")
	assert_eq(DangerRank.median_room([-4, 2, 6]), 2, "negative rooms count as 0")


func test_where_the_level_settles() -> void:
	# A median of 5·(G−1) … 5·G−1 keeps G, 5·G climbs to G + 1.
	for g in range(1, 12):
		assert_eq(DangerRank.danger_level(99, [5 * g - 1, 5 * g - 1, 5 * g - 1]), g)
		assert_eq(DangerRank.danger_level(99, [5 * (g - 1), 5 * (g - 1), 5 * (g - 1)]), g)
		assert_eq(DangerRank.danger_level(99, [5 * g, 5 * g, 5 * g]), g + 1)


func test_rank_texts_in_both_languages() -> void:
	assert_eq(DangerRank.rank_text(4), "Kerze II")
	assert_eq(DangerRank.rank_text(0), "Funke I")
	assert_eq(DangerRank.rank_text(13), "Leuchtfeuer II")
	assert_eq(DangerRank.rank_text(16), "Seelenmeister 2")
	for tier: StringName in DangerRank.TIERS:
		assert_true(Loc.has_key(DangerRank.TIER_KEYS[tier], &"en"), "en text for %s" % tier)
		assert_true(Loc.has_key(DangerRank.TIER_KEYS[tier], &"de"), "de text for %s" % tier)
	Loc.apply(&"en")
	assert_eq(DangerRank.rank_text(7), "Flame II")
	assert_eq(DangerRank.rank_text(15), "Soul Master 1")
	Loc.apply(&"de")


func test_loot_and_xp_bonus() -> void:
	assert_almost_eq(DangerRank.loot_factor(0), 1.0, 0.0001)
	assert_almost_eq(DangerRank.loot_factor(4), 1.2, 0.0001)
	assert_eq(DangerRank.loot_percent(10), 50)
	assert_eq(DangerRank.xp_bonus(100, 3), 15)
	assert_eq(DangerRank.xp_bonus(37, 3), 5, "37 · 15 / 100 = 5.55, rounded down")
	assert_eq(DangerRank.xp_bonus(100, 0), 0)
	assert_eq(DangerRank.xp_bonus(100, 99), 150, "G limited to DANGER_MAX")


func test_rank_badge_placeholder_and_art() -> void:
	var badge := RankBadge.create(4, 16.0)
	add_child_autofree(badge)
	await wait_process_frames(1)
	assert_eq(badge.get_rank()["tier"], DangerRank.CANDLE)
	assert_gt(badge.custom_minimum_size.x, 0.0)
	var expected := ResourceLoader.exists(RankBadge.SMALL_TEXTURE_PATH % "candle") or ResourceLoader.exists(RankBadge.TEXTURE_PATH % "candle")
	assert_eq(badge.get_texture() != null, expected, "art when delivered, the placeholder otherwise")
	badge.danger = 17
	assert_eq(badge.get_rank()["tier"], DangerRank.SOUL_MASTER)


func test_rank_badge_art_shows_the_step_under_the_badge() -> void:
	var badge := RankBadge.create(4, 16.0)
	add_child_autofree(badge)
	await wait_process_frames(1)
	if badge.get_texture() == null:
		assert_eq(badge.get_step_strip_height(), 0.0, "the placeholder draws its own pips")
		return
	assert_gt(badge.get_step_strip_height(), 0.0, "a strip under the art for the step")
	assert_gt(badge.custom_minimum_size.y, badge.custom_minimum_size.x, "the badge stays square, the strip hangs below")
	var pips := badge.get_pips_texture()
	assert_not_null(pips, "rank_pips.png is delivered with the badges")
	assert_eq(Vector2i(pips.get_size()), Vector2i(RankBadge.PIP_FRAME * 3, RankBadge.PIP_FRAME), "3 × 8x8")
	assert_eq(RankBadge.pip_region(1), Rect2(0, 0, 8, 8), "I")
	assert_eq(RankBadge.pip_region(2), Rect2(8, 0, 8, 8), "II")
	assert_eq(RankBadge.pip_region(3), Rect2(16, 0, 8, 8), "III")
	assert_eq(RankBadge.pip_region(9), Rect2(16, 0, 8, 8), "clamped")
	badge.danger = DangerRank.SOUL_MASTER_DANGER + 1
	assert_gt(badge.get_step_strip_height(), 0.0, "Seelenmeister shows his number in the strip")
	assert_eq(DangerRank.step_text(badge.get_rank()), "2")


func _part(result: Dictionary, id: StringName) -> int:
	for part: Dictionary in result["parts"]:
		if part["id"] == id:
			return int(part["xp"])
	return 0
