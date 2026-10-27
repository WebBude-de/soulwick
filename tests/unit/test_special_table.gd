extends GutTest
## Weighted special room draw (D-102, ROADMAP A8): weights from special_table.tres, no type
## twice in a row, the pact share of the extra-upgrade rooms and the kind of trial.

const DRAWS := 20000
const TOLERANCE := 0.015


func _rng(seed_value := 1234) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_default_table_has_the_weights_of_d102() -> void:
	var table := SpecialTable.load_default()
	assert_eq(table.get_base_weights(), [35.0, 20.0, 15.0, 15.0, 15.0] as Array[float])
	assert_almost_eq(table.pact_chance, 1.0 / 3.0, 0.001)
	assert_eq(table.crumble_weight, 1.0, "crumbling floor is a third of the trials (A4)")


func test_type_ids_follow_the_room_sequence_enum() -> void:
	assert_eq(SpecialTable.SHOP, RoomSequence.SpecialType.SHOP)
	assert_eq(SpecialTable.WEAPON, RoomSequence.SpecialType.WEAPON)
	assert_eq(SpecialTable.FOUNTAIN, RoomSequence.SpecialType.FOUNTAIN)
	assert_eq(SpecialTable.UPGRADE, RoomSequence.SpecialType.UPGRADE)
	# TRIAL is appended to the enum by the integrator; until then the id is the next free value.
	var enum_values: Dictionary = RoomSequence.SpecialType
	if enum_values.has("TRIAL"):
		assert_eq(SpecialTable.TRIAL, enum_values.get("TRIAL"))
	else:
		assert_eq(SpecialTable.TRIAL, enum_values.size())


func test_weights_hold_over_many_draws() -> void:
	var table := SpecialTable.load_default()
	var rng := _rng()
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for i in DRAWS:
		counts[table.roll(-1, rng)] += 1
	var chances := table.get_chances(-1)
	for type in SpecialTable.TYPE_COUNT:
		assert_almost_eq(float(counts[type]) / DRAWS, chances[type], TOLERANCE, SpecialTable.get_type_name(type))
	assert_almost_eq(chances[SpecialTable.SHOP], 0.35, 0.0001)
	assert_almost_eq(chances[SpecialTable.TRIAL], 0.15, 0.0001)


func test_previous_type_never_repeats() -> void:
	var table := SpecialTable.load_default()
	var rng := _rng(77)
	var previous := -1
	var seen: Dictionary[int, bool] = {}
	for i in 5000:
		var type := table.roll(previous, rng)
		assert_ne(type, previous, "draw %d repeated the type before" % i)
		if type == previous:
			return
		seen[type] = true
		previous = type
	assert_eq(seen.size(), SpecialTable.TYPE_COUNT, "every type shows up")


func test_the_previous_share_goes_proportionally_to_the_others() -> void:
	var table := SpecialTable.load_default()
	var chances := table.get_chances(SpecialTable.SHOP)
	assert_eq(chances[SpecialTable.SHOP], 0.0)
	assert_almost_eq(chances[SpecialTable.WEAPON], 20.0 / 65.0, 0.0001)
	assert_almost_eq(chances[SpecialTable.TRIAL], 15.0 / 65.0, 0.0001)
	var rng := _rng(5)
	var weapon := 0
	for i in DRAWS:
		var type := table.roll(SpecialTable.SHOP, rng)
		assert_ne(type, SpecialTable.SHOP)
		if type == SpecialTable.WEAPON:
			weapon += 1
	assert_almost_eq(float(weapon) / DRAWS, 20.0 / 65.0, TOLERANCE)


func test_one_random_number_per_draw() -> void:
	var table := SpecialTable.load_default()
	var a := _rng(9)
	var b := _rng(9)
	table.roll(SpecialTable.FOUNTAIN, a)
	b.randf()
	assert_eq(a.state, b.state, "roll() draws exactly one number, the run stays reproducible")
	table.roll_pact(a)
	b.randf()
	table.roll_trial_kind(a)
	b.randf()
	assert_eq(a.state, b.state)


func test_same_seed_same_rooms() -> void:
	var table := SpecialTable.load_default()
	var first: Array[int] = []
	var second: Array[int] = []
	for list: Array[int] in [first, second]:
		var rng := _rng(4242)
		var previous := -1
		for i in 30:
			previous = table.roll(previous, rng)
			list.append(previous)
	assert_eq(first, second)


func test_balancing_without_code() -> void:
	var table := SpecialTable.new()
	table.shop_weight = 0.0
	table.weapon_weight = 0.0
	table.fountain_weight = 0.0
	table.upgrade_weight = 0.0
	table.trial_weight = 1.0
	var rng := _rng()
	assert_eq(table.roll(-1, rng), SpecialTable.TRIAL)
	assert_ne(table.roll(SpecialTable.TRIAL, rng), SpecialTable.TRIAL, "fallback never repeats either")
	assert_eq(SpecialTable.pick_weighted([0.0, 0.0] as Array[float], 0.5, 7), 7, "all zero: fallback")
	assert_eq(SpecialTable.pick_weighted([1.0, 1.0] as Array[float], 0.999999, 7), 1)


func test_pact_in_a_third_of_the_upgrade_rooms() -> void:
	var table := SpecialTable.load_default()
	var rng := _rng(31)
	var pacts := 0
	for i in DRAWS:
		if table.roll_pact(rng):
			pacts += 1
	assert_almost_eq(float(pacts) / DRAWS, 1.0 / 3.0, TOLERANCE)


func test_trial_kinds_skip_the_crumbling_floor_until_a4() -> void:
	var table := SpecialTable.load_default()
	table = table.duplicate() as SpecialTable
	table.crumble_weight = 5.0
	var rng := _rng(8)
	var counts: Array[int] = [0, 0, 0]
	for i in 4000:
		counts[table.roll_trial_kind(rng, false)] += 1
	assert_eq(counts[SpecialTable.TrialKind.CRUMBLE], 0)
	assert_almost_eq(float(counts[SpecialTable.TrialKind.GAUNTLET]) / 4000.0, 0.5, 0.03)
	assert_true(CrumbleCourse.is_available(), "built with the abyss of A4")
	var with_pits := 0
	for i in 4000:
		if table.roll_trial_kind(rng, true) == SpecialTable.TrialKind.CRUMBLE:
			with_pits += 1
	assert_gt(with_pits, 0, "with pits (A4) the weight counts")


func test_trial_template_and_content_exist() -> void:
	var template := SpecialTable.get_template_for(SpecialTable.TRIAL)
	assert_not_null(template)
	assert_null(SpecialTable.get_template_for(SpecialTable.SHOP), "other types keep the special template")
	assert_true(ResourceLoader.exists(SpecialTable.TRIAL_CONTENT_PATH))
	assert_true(autofree(load(SpecialTable.TRIAL_CONTENT_PATH).instantiate()) is TrialContent)
	assert_eq(SpecialTable.get_type_name(SpecialTable.TRIAL), "Prüfung")


func test_trial_names_are_translation_keys() -> void:
	assert_eq(SpecialTable.get_trial_title_key(SpecialTable.TrialKind.GAUNTLET), &"ROOM_TRIAL_GAUNTLET_TITLE")
	assert_eq(SpecialTable.get_trial_title_key(SpecialTable.TrialKind.LIGHT_RUN), &"ROOM_TRIAL_LIGHT_RUN_TITLE")
	assert_eq(SpecialTable.get_trial_title_key(SpecialTable.TrialKind.CRUMBLE), &"ROOM_TRIAL_CRUMBLE_TITLE")
	for kind: int in SpecialTable.TrialKind.values():
		var key := SpecialTable.get_trial_title_key(kind)
		assert_true(DungeonTexts.has_text(key), "%s has German" % key)
		assert_eq(SpecialTable.get_trial_name(kind), DungeonTexts.t(key))
		assert_ne(SpecialTable.get_trial_name(kind), String(key), "%s is translated" % key)
	assert_eq(RoomSequence.get_special_name(RoomSequence.SpecialType.TRIAL), SpecialTable.get_type_name(SpecialTable.TRIAL))
