extends GutTest
## Rules of the practice run (WK10, TutorialRules): offered alone and once per account, never in a
## group game (tips there), what a hit does to the dummies, when the dash station is done, the XP of
## the first completion (hook on AccountProgress), and that every text exists in English and German.

const SAVE_PATH := "user://test_tutorial_rules_save.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH


func after_all() -> void:
	SaveManager.save_path = _old_save_path


class FakeProgress:
	extends RefCounted
	var credits: Array = []

	func add_bonus_xp(id: String, amount: int) -> bool:
		for credit: Array in credits:
			if credit[0] == id:
				return false
		credits.append([id, amount])
		return true


func test_offered_alone_and_once() -> void:
	assert_true(TutorialRules.should_offer(false, false), "a new account alone gets it")
	assert_false(TutorialRules.should_offer(true, false), "done or skipped: not again")
	assert_true(TutorialRules.should_offer(true, false, true), "tools may force it")
	assert_false(TutorialRules.should_offer(false, true), "never in a group game")
	assert_false(TutorialRules.should_offer(false, true, true), "not even forced")


func test_coop_tips_only_for_who_has_not_done_it() -> void:
	assert_true(TutorialRules.wants_coop_tips(false, true))
	assert_false(TutorialRules.wants_coop_tips(true, true), "done alone: no tips")
	assert_false(TutorialRules.wants_coop_tips(false, false), "alone the practice run itself teaches")
	assert_eq(TutorialRules.coop_tip_for_room(1), &"FLINT_TUTORIAL_TIP_1")
	assert_eq(TutorialRules.coop_tip_for_room(TutorialRules.COOP_TIP_ROOMS), TutorialRules.COOP_TIPS[TutorialRules.COOP_TIP_ROOMS - 1])
	assert_eq(TutorialRules.coop_tip_for_room(TutorialRules.COOP_TIP_ROOMS + 1), &"", "only the first rooms")
	assert_eq(TutorialRules.coop_tip_for_room(0), &"")


func test_straw_dummies_fall_after_their_hits() -> void:
	var none: Array[StringName] = []
	for hits in TutorialRules.DUMMY_HITS - 1:
		assert_eq(TutorialRules.hit_result(false, false, hits, none), TutorialRules.Hit.COUNTED)
	assert_eq(TutorialRules.hit_result(false, false, TutorialRules.DUMMY_HITS - 1, none), TutorialRules.Hit.BREAKS)
	assert_eq(TutorialRules.hit_result(false, true, 5, none), TutorialRules.Hit.IGNORED, "broken stays broken")
	var special: Array[StringName] = [&"sword", TutorialRules.SPECIAL_TAG]
	assert_eq(TutorialRules.hit_result(false, false, 0, special), TutorialRules.Hit.COUNTED, "a special is a hit like any on straw")


func test_the_shield_only_breaks_with_a_special() -> void:
	var normal: Array[StringName] = [&"sword"]
	var special: Array[StringName] = [&"bow", TutorialRules.SPECIAL_TAG]
	for hits in 6:
		assert_eq(TutorialRules.hit_result(true, false, hits, normal), TutorialRules.Hit.BLOCKED, "normal hits bounce off")
	assert_eq(TutorialRules.hit_result(true, false, 0, special), TutorialRules.Hit.SHIELD_BREAKS)


func test_the_dash_station_is_done_on_safe_ground_beyond_the_abyss() -> void:
	assert_true(TutorialRules.is_dash_done(110.0, 100.0, false, false))
	assert_false(TutorialRules.is_dash_done(90.0, 100.0, false, false), "still before the east edge")
	assert_false(TutorialRules.is_dash_done(110.0, 100.0, true, false), "falling does not count")
	assert_false(TutorialRules.is_dash_done(110.0, 100.0, false, true), "mid-dash does not count yet")


func test_xp_only_for_the_first_completion() -> void:
	assert_eq(TutorialRules.xp_for(true, false), TutorialRules.XP_FIRST_COMPLETION)
	assert_eq(TutorialRules.XP_FIRST_COMPLETION, 25, "KONZEPT §7.2: +25 XP")
	assert_eq(TutorialRules.xp_for(false, false), 0, "skipping gives nothing")
	assert_eq(TutorialRules.xp_for(true, true), 0, "a forced replay gives nothing")


func test_credit_xp_uses_the_progress_hook_once() -> void:
	var progress := FakeProgress.new()
	assert_true(TutorialRules.credit_xp(progress, 25))
	assert_false(TutorialRules.credit_xp(progress, 25), "once per account (the hook counts the id once)")
	assert_eq(progress.credits, [[TutorialRules.XP_CREDIT_ID, 25]])
	assert_false(TutorialRules.credit_xp(RefCounted.new(), 25), "without the hook nothing is credited")
	assert_false(TutorialRules.credit_xp(null, 25))
	assert_false(TutorialRules.credit_xp(progress, 0))


func test_stations_in_order_with_flint_ids() -> void:
	assert_eq(TutorialRules.STATIONS.size(), 4)
	for station in TutorialRules.STATIONS:
		assert_true(String(TutorialRules.explanation_id(station)).begins_with(FlintExplanation.ID_PREFIX), "Flint ids start with flint_")
		assert_eq(TutorialRules.station_number(station), int(station) + 1)
	assert_eq(TutorialRules.next_station(TutorialRules.Station.ATTACK), TutorialRules.Station.DASH)
	assert_eq(TutorialRules.next_station(TutorialRules.Station.SPECIAL), -1, "after the last: the gate")


func test_every_text_exists_in_both_languages() -> void:
	var keys: Array[StringName] = [
		&"FLINT_TUTORIAL_DASH_FALL", &"FLINT_TUTORIAL_SPECIAL_BLOCKED", &"FLINT_TUTORIAL_FINISH",
		&"FLINT_TUTORIAL_DONE", &"FLINT_TUTORIAL_DONE_XP",
		TutorialJump.MOMENTUM_KEY, TutorialJump.DITCH_KEY,
		&"TUTORIAL_STATION_CAPTION", &"TUTORIAL_SKIP", &"TUTORIAL_GATE",
	]
	keys.append_array([TutorialRules.WELCOME_INTRO_KEY, TutorialRules.WELCOME_KNOWN_KEY])
	keys.append_array(TutorialRules.COOP_TIPS)
	keys.append_array(TutorialRules.TITLE_KEYS)
	keys.append_array(TutorialRules.DONE_KEYS)
	for list: Array in TutorialRules.EXPLANATIONS:
		for key: StringName in list:
			keys.append(key)
	for spot: Array in TutorialPlans.JUMP_HINTS:
		keys.append(spot[1])
	for key in keys:
		assert_true(Loc.has_key(key, &"en"), "%s has English" % key)
		assert_true(Loc.has_key(key, &"de"), "%s has German" % key)


## WK10b: Flint explains while the player plays - one sentence per moment, at most two lines in his
## bubble in both languages (the strip and the signs carry no explanations of their own).
func test_flint_says_one_short_sentence_per_moment() -> void:
	assert_eq(TutorialRules.welcome_key(false), TutorialRules.WELCOME_INTRO_KEY, "no village tour: Flint introduces himself")
	assert_eq(TutorialRules.welcome_key(true), TutorialRules.WELCOME_KNOWN_KEY, "met in the village: no second introduction")
	for list: Array in TutorialRules.EXPLANATIONS:
		assert_eq(list.size(), 1, "one sentence per station: nobody waits for Flint")
	var keys: Array[StringName] = [
		&"FLINT_TUTORIAL_DASH_FALL", &"FLINT_TUTORIAL_SPECIAL_BLOCKED", &"FLINT_TUTORIAL_FINISH",
		&"FLINT_TUTORIAL_DONE", &"FLINT_TUTORIAL_DONE_XP", TutorialJump.MOMENTUM_KEY, TutorialJump.DITCH_KEY,
	]
	keys.append_array([TutorialRules.WELCOME_INTRO_KEY, TutorialRules.WELCOME_KNOWN_KEY])
	keys.append_array(TutorialRules.DONE_KEYS)
	keys.append_array(TutorialRules.COOP_TIPS)
	for list: Array in TutorialRules.EXPLANATIONS:
		keys.append(list[0])
	for spot: Array in TutorialPlans.JUMP_HINTS:
		keys.append(spot[1])
	var translations := Loc.load_csv(Loc.CSV_PATH)
	var font := UiKit.get_font()
	var width := UiKit.px(FlintGuideView.BUBBLE_WIDTH)
	var size := UiKit.font_px(FlintGuideView.TEXT_SIZE)
	for key in keys:
		for language: StringName in Loc.LANGUAGES:
			var translation: Translation = translations[language]
			var text := String(translation.get_message(key)).replace("%d", "25")
			assert_lte(FlintGuideRules.line_count(text, font, size, width), FlintGuideRules.MAX_LINES,
					"%s (%s) fits two lines: %s" % [key, language, text])
