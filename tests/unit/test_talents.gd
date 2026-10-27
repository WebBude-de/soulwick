extends GutTest
## Talent tree data and distribution rules (KE6, KONZEPT §6.1, D-194, D-196): the catalog, ranks that
## open after 0/3/7/11 points in the same path, the point budget, taking points back, spells and
## slots, the respec fee in Seelenkristalle and the storage form. Never touches a save.

const IDS: Array[StringName] = [&"light_foot", &"dash_training", &"swift_blade", &"evasion", &"double_dash",
	&"wind_runner", &"vitality", &"might", &"steadfast", &"shield_breaker", &"second_heart", &"ember_heart",
	&"spell_power", &"focus", &"staff_master", &"second_spell_slot"]
const SPELLS: Array[StringName] = [&"light_flash", &"soul_shield", &"flame_ring", &"will_o_wisp", &"heal_spark"]

var _tree: TalentTree
var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_talents_save.cfg"
	_tree = TalentTree.get_default()


func after_all() -> void:
	SaveManager.save_path = _old_save_path


## Raises id count times, failing the test if one step is refused.
func _raise(state: TalentState, id: StringName, count: int, points := 99) -> void:
	for i in count:
		assert_true(state.raise(id, points, _tree), "raise %s step %d" % [id, i + 1])


# --- Catalog ---

func test_catalog_has_every_talent_and_spell_node() -> void:
	assert_not_null(_tree, "talent_tree.tres loads")
	for id in IDS:
		assert_true(_tree.has_talent(id), "talent %s" % id)
	for spell in SPELLS:
		var talent := _tree.get_talent(spell)
		assert_not_null(talent, "spell node %s" % spell)
		if talent != null:
			assert_true(talent.unlocks_spell(), "%s unlocks a spell" % spell)
			assert_eq(talent.spell, spell)
			assert_eq(talent.path, TalentDef.PATH_SOUL)
	assert_eq(_tree.talents.size(), IDS.size() + SPELLS.size(), "no other talents")
	assert_eq(_tree.get_spells(), SPELLS, "spells in catalog order")


func test_paths_have_four_ranks_and_one_capstone_each() -> void:
	assert_eq(_tree.rank_thresholds, [0, 3, 7, 11] as Array[int], "ranks open after 0/3/7/11 points")
	for talent_path in TalentDef.PATHS:
		for rank in range(1, 5):
			assert_false(_tree.get_rank_talents(talent_path, rank).is_empty(), "%s rank %d" % [talent_path, rank])
		var capstones := _tree.get_rank_talents(talent_path, TalentDef.MAX_RANK)
		assert_eq(capstones.size(), 1, "%s has one capstone" % talent_path)
		assert_eq(capstones[0].max_level, 1, "capstones take one point")


func test_concept_table_levels_and_values() -> void:
	var expected := {
		&"light_foot": [TalentDef.PATH_WIND, 1, 3, 0.05], &"dash_training": [TalentDef.PATH_WIND, 1, 3, 0.15],
		&"swift_blade": [TalentDef.PATH_WIND, 2, 3, 0.08], &"evasion": [TalentDef.PATH_WIND, 2, 2, 0.15],
		&"double_dash": [TalentDef.PATH_WIND, 3, 1, 1.0], &"wind_runner": [TalentDef.PATH_WIND, 4, 1, 1.0],
		&"vitality": [TalentDef.PATH_EMBER, 1, 5, 1.0], &"might": [TalentDef.PATH_EMBER, 1, 3, 0.08],
		&"steadfast": [TalentDef.PATH_EMBER, 2, 2, 0.25], &"shield_breaker": [TalentDef.PATH_EMBER, 2, 2, 0.2],
		&"second_heart": [TalentDef.PATH_EMBER, 3, 1, 1.0], &"ember_heart": [TalentDef.PATH_EMBER, 4, 1, 1.0],
		&"light_flash": [TalentDef.PATH_SOUL, 1, 1, 1.0], &"spell_power": [TalentDef.PATH_SOUL, 1, 3, 0.1],
		&"focus": [TalentDef.PATH_SOUL, 2, 3, 0.08], &"soul_shield": [TalentDef.PATH_SOUL, 2, 1, 1.0],
		&"flame_ring": [TalentDef.PATH_SOUL, 2, 1, 1.0], &"will_o_wisp": [TalentDef.PATH_SOUL, 3, 1, 1.0],
		&"heal_spark": [TalentDef.PATH_SOUL, 3, 1, 1.0], &"staff_master": [TalentDef.PATH_SOUL, 3, 2, 0.08],
		&"second_spell_slot": [TalentDef.PATH_SOUL, 4, 1, 1.0],
	}
	for id: StringName in expected:
		var talent := _tree.get_talent(id)
		var row: Array = expected[id]
		assert_eq(talent.path, row[0], "%s path" % id)
		assert_eq(talent.rank, row[1], "%s rank" % id)
		assert_eq(talent.max_level, row[2], "%s levels" % id)
		assert_almost_eq(talent.value, float(row[3]), 0.0001, "%s value" % id)
	assert_eq(_tree.get_talent(&"swift_blade").weapon_tags, [&"dagger", &"bow"] as Array[StringName])
	assert_eq(_tree.get_talent(&"might").weapon_tags, [&"sword", &"hammer"] as Array[StringName])
	assert_eq(_tree.get_talent(&"staff_master").weapon_tags, [&"staff"] as Array[StringName])


func test_every_rank_of_every_path_can_be_reached() -> void:
	for talent_path in TalentDef.PATHS:
		var state := TalentState.new()
		for talent in _tree.get_path_talents(talent_path):
			_raise(state, talent.id, talent.max_level)
		assert_true(state.is_valid(99, _tree), "%s can be filled" % talent_path)


func test_texts_exist_in_both_languages() -> void:
	for talent in _tree.talents:
		for language: StringName in Loc.LANGUAGES:
			assert_true(Loc.has_key(talent.name_key(), language), "%s %s" % [talent.name_key(), language])
			assert_true(Loc.has_key(talent.description_key(), language), "%s %s" % [talent.description_key(), language])
		assert_false(talent.get_description().contains("%s"), "%s description is formatted: %s" % [talent.id, talent.get_description()])
	for talent_path in TalentDef.PATHS:
		assert_true(Loc.has_key(TalentDef.path_name_key(talent_path), &"de"), "path name %s" % talent_path)
		assert_true(Loc.has_key(TalentDef.path_description_key(talent_path), &"de"), "path text %s" % talent_path)


func test_description_shows_the_value_of_one_level() -> void:
	assert_eq(_tree.get_talent(&"light_foot").get_description(), "+5 % Lauftempo je Stufe")
	assert_eq(_tree.get_talent(&"dash_training").get_description(), "−0,15 s Dash-Abklingzeit je Stufe")
	assert_eq(_tree.get_talent(&"vitality").get_description(), "+1 Max-HP je Stufe")
	assert_eq(_tree.get_talent(&"vitality").get_display_name(), "Vitalität")


# --- Points and ranks ---

func test_points_per_level() -> void:
	assert_eq(TalentState.points_for_level(1), 0, "level 1 has no point")
	assert_eq(TalentState.points_for_level(2), 1, "level 2 gives the first")
	assert_eq(TalentState.points_for_level(50), 49)
	assert_eq(TalentState.points_for_level(0), 0)


func test_rank_opens_after_points_in_lower_ranks_of_the_same_path() -> void:
	var state := TalentState.new()
	assert_false(state.can_raise(&"swift_blade", 20, _tree), "rank 2 closed with 0 points")
	_raise(state, &"vitality", 3)
	assert_false(state.can_raise(&"swift_blade", 20, _tree), "points in another path do not count")
	_raise(state, &"light_foot", 2)
	assert_false(state.can_raise(&"swift_blade", 20, _tree), "2 of 3")
	_raise(state, &"dash_training", 1)
	assert_true(state.is_rank_open(TalentDef.PATH_WIND, 2, _tree))
	assert_true(state.can_raise(&"swift_blade", 20, _tree), "rank 2 open with 3 points")
	assert_false(state.can_raise(&"double_dash", 20, _tree), "rank 3 needs 7")
	_raise(state, &"swift_blade", 3)
	_raise(state, &"light_foot", 1)
	assert_eq(state.get_path_points(TalentDef.PATH_WIND, _tree), 7)
	assert_true(state.can_raise(&"double_dash", 20, _tree), "rank 3 open with 7")
	_raise(state, &"double_dash", 1)
	assert_false(state.can_raise(&"wind_runner", 20, _tree), "rank 4 needs 11 below it")


func test_no_more_points_than_available_and_no_level_above_max() -> void:
	var state := TalentState.new()
	assert_true(state.raise(&"vitality", 2, _tree))
	assert_true(state.raise(&"vitality", 2, _tree))
	assert_false(state.raise(&"vitality", 2, _tree), "budget of 2 spent")
	assert_eq(state.get_spent_points(), 2)
	_raise(state, &"vitality", 3)
	assert_false(state.raise(&"vitality", 99, _tree), "vitality stops at 5")
	assert_false(state.raise(&"no_such_talent", 99, _tree), "unknown talents are refused")


func test_lowering_keeps_higher_ranks_standing() -> void:
	var state := TalentState.new()
	_raise(state, &"light_foot", 3)
	_raise(state, &"swift_blade", 1)
	assert_false(state.can_lower(&"light_foot", _tree), "rank 2 would stand on 2 points")
	assert_true(state.can_lower(&"swift_blade", _tree))
	assert_true(state.lower(&"swift_blade", _tree))
	assert_true(state.lower(&"light_foot", _tree), "free again without rank 2")
	assert_eq(state.get_level(&"light_foot"), 2)
	assert_false(state.can_lower(&"evasion", _tree), "nothing to take back")


# --- Respec fee (D-196) ---

func test_respec_cost_is_ten_percent_rounded_up_at_least_one() -> void:
	assert_eq(TalentState.respec_cost(0), 0, "nothing taken back, nothing to pay")
	assert_eq(TalentState.respec_cost(1), 1, "at least 1")
	assert_eq(TalentState.respec_cost(10), 1)
	assert_eq(TalentState.respec_cost(11), 2, "rounded up")
	assert_eq(TalentState.respec_cost(30), 3)
	assert_eq(TalentState.respec_cost(49), 5, "full respec at level 50 costs 5 (D-196)")


func test_refunded_points_count_only_what_was_taken_back() -> void:
	var before := TalentState.new()
	_raise(before, &"vitality", 4)
	_raise(before, &"might", 2)
	var after := before.duplicate_state()
	after.lower(&"vitality", _tree)
	after.lower(&"vitality", _tree)
	_raise(after, &"light_foot", 3)
	assert_eq(TalentState.refunded_points(before, after), 2, "raising elsewhere does not offset")
	assert_eq(TalentState.respec_cost(TalentState.refunded_points(before, after)), 1)
	assert_eq(TalentState.refunded_points(before, before.duplicate_state()), 0)
	var cleared := before.duplicate_state()
	cleared.clear()
	assert_eq(TalentState.refunded_points(before, cleared), 6)


# --- Spells ---

func test_light_flash_opens_the_slot_and_the_capstone_a_second() -> void:
	var state := TalentState.new()
	_raise(state, &"spell_power", 3)
	_raise(state, &"flame_ring", 1)
	assert_eq(state.get_unlocked_spells(_tree), [&"flame_ring"] as Array[StringName])
	assert_eq(state.get_spell_slots(_tree), 0, "the slot opens with Lichtblitz")
	assert_false(state.equip_spell(&"flame_ring", 0, _tree), "no slot yet")
	_raise(state, &"light_flash", 1)
	assert_eq(state.get_spell_slots(_tree), 1)
	assert_true(state.equip_spell(&"flame_ring", 0, _tree))
	assert_false(state.equip_spell(&"light_flash", 1, _tree), "only one slot")
	assert_false(state.equip_spell(&"heal_spark", 0, _tree), "locked spell")
	for id in [&"focus", &"focus", &"focus", &"soul_shield", &"will_o_wisp", &"heal_spark", &"staff_master"]:
		_raise(state, id, 1)
	_raise(state, &"second_spell_slot", 1)
	assert_eq(state.get_spell_slots(_tree), 2)
	assert_true(state.equip_spell(&"light_flash", 1, _tree))
	assert_true(state.equip_spell(&"flame_ring", 1, _tree), "moving a spell clears its old slot")
	assert_eq(state.get_equipped_spell(0), &"")
	assert_eq(state.get_equipped_spell(1), &"flame_ring")
	assert_true(state.is_valid(99, _tree))


func test_taking_a_spell_back_unequips_it() -> void:
	var state := TalentState.new()
	_raise(state, &"light_flash", 1)
	assert_true(state.equip_spell(&"light_flash", 0, _tree))
	assert_true(state.lower(&"light_flash", _tree))
	assert_true(state.equipped_spells.is_empty(), "spell is gone with its talent")


# --- Checks and storage ---

func test_validate_names_every_problem() -> void:
	var state := TalentState.new()
	state.levels[&"wind_runner"] = 1
	state.levels[&"vitality"] = 9
	state.levels[&"made_up"] = 1
	state.equipped_spells.assign([&"heal_spark"])
	var problems := state.validate(3, _tree)
	assert_eq(problems.size(), 5, str(problems))
	assert_false(state.is_valid(99, _tree))
	assert_true(TalentState.new().is_valid(0, _tree), "empty is valid")


func test_sanitized_repairs_untrusted_input() -> void:
	var state := TalentState.new()
	state.levels[&"made_up"] = 3
	state.levels[&"vitality"] = 9
	state.levels[&"second_heart"] = 1
	state.levels[&"light_flash"] = 1
	state.equipped_spells.assign([&"light_flash", &"heal_spark"])
	var clean := state.sanitized(6, _tree)
	assert_true(clean.is_valid(6, _tree), str(clean.validate(6, _tree)))
	assert_eq(clean.get_level(&"made_up"), 0, "unknown dropped")
	assert_eq(clean.get_level(&"second_heart"), 0, "rank 3 without 7 points below dropped")
	assert_eq(clean.get_level(&"vitality"), 5, "clamped to max")
	assert_eq(clean.get_level(&"light_flash"), 1)
	assert_eq(clean.equipped_spells, [&"light_flash"] as Array[StringName], "only the unlocked spell in the one slot")
	var tight := state.sanitized(2, _tree)
	assert_true(tight.is_valid(2, _tree))
	assert_eq(tight.get_spent_points(), 2)
	var valid := TalentState.new()
	_raise(valid, &"might", 2)
	assert_eq(valid.sanitized(5, _tree).to_dict(), valid.to_dict(), "valid input comes back unchanged")


func test_dict_round_trip_and_garbage() -> void:
	var state := TalentState.new()
	_raise(state, &"light_flash", 1)
	_raise(state, &"spell_power", 2)
	state.equip_spell(&"light_flash", 0, _tree)
	var data := state.to_dict()
	assert_eq(int(data["version"]), TalentState.VERSION)
	var copy := TalentState.from_dict(JSON.parse_string(JSON.stringify(data)))
	assert_eq(copy.get_level(&"spell_power"), 2, "JSON numbers come back as levels")
	assert_eq(copy.equipped_spells, [&"light_flash"] as Array[StringName])
	assert_eq(copy.to_dict(), data)
	assert_eq(TalentState.from_dict(null).get_spent_points(), 0)
	assert_eq(TalentState.from_dict("x").get_spent_points(), 0)
	var odd := TalentState.from_dict({"talents": {"might": "3", "vitality": -2, "focus": 2.0}, "spells": 5})
	assert_eq(odd.get_level(&"might"), 0, "text levels are ignored")
	assert_eq(odd.get_level(&"vitality"), 0)
	assert_eq(odd.get_level(&"focus"), 2)


func test_spell_nodes_show_the_spell_symbol() -> void:
	for spell in SPELLS:
		var talent := _tree.get_talent(spell)
		assert_false(ResourceLoader.exists(TalentDef.ICON_PATH % spell), "no talent_%s.png: the spell symbol stands in" % spell)
		assert_eq(talent.get_icon(), SpellArt.icon(spell), "%s shows its spell symbol" % spell)
	var might := _tree.get_talent(&"might")
	var own := ResourceLoader.exists(TalentDef.ICON_PATH % "might")
	assert_eq(might.get_icon() != null, own, "other talents keep their own icon or none")
