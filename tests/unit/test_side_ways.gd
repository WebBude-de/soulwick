extends GutTest
## Where the dungeon runs through side segments (M5, D-144): SideWays.reason_for answers what
## SideWays.plan does later (campfire, ladder way, now and then after a rest room; never before
## the boss, never twice in a row, never with "Seitenwege auslassen"), the ladder way gets a gate
## with the chest, and the DungeonManager asks it before a branch may show the ladder door.
## Runs in a test folder (SaveManager.set_storage_root), never on the real settings/save.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const ROOT := "user://test_side_ways"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	SaveManager.set_storage_root(ROOT)


func before_each() -> void:
	SaveManager.set_option(SideRules.OPTION_SKIP, false)


func after_all() -> void:
	SaveManager.set_option(SideRules.OPTION_SKIP, false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join("settings.cfg")))
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()


## A room of the given type in a slot (not in the tree unless asked).
func _room(index: int, slot: int, room_type: RoomSequence.RoomType, special := -1, in_tree := false) -> RoomController:
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(index, room_type, special, false, context)
	room.slot_index = slot
	if in_tree:
		add_child_autofree(room)
	else:
		autofree(room)
	return room


func test_campfire_always_leads_into_a_segment_unless_boss_twice_or_skipped() -> void:
	var campfire := _room(15, 16, RoomSequence.RoomType.CAMPFIRE)
	var next := _room(16, 17, RoomSequence.RoomType.COMBAT)
	assert_eq(SideWays.reason_for(campfire, next, 11, false), SideRules.Reason.BIOME_CHANGE)
	assert_eq(SideWays.reason_for(campfire, next, 11, true), SideRules.Reason.NONE, "never twice in a row")
	var boss := _room(16, 17, RoomSequence.RoomType.BOSS)
	assert_eq(SideWays.reason_for(campfire, boss, 11, false), SideRules.Reason.NONE, "never before the boss")
	SaveManager.set_option(SideRules.OPTION_SKIP, true)
	assert_true(SideWays.is_skipped())
	assert_eq(SideWays.reason_for(campfire, next, 11, false), SideRules.Reason.NONE, "switched off")
	assert_eq(SideWays.reason_for(null, next, 11, false), SideRules.Reason.NONE)


func test_after_a_rest_room_now_and_then_and_stable_per_seed() -> void:
	var rest := _room(4, 4, RoomSequence.RoomType.SPECIAL, RoomSequence.SpecialType.FOUNTAIN)
	var trial := _room(4, 4, RoomSequence.RoomType.SPECIAL, RoomSequence.SpecialType.TRIAL)
	var next := _room(5, 5, RoomSequence.RoomType.MINIBOSS)
	var hits := 0
	for run_seed in 1000:
		var reason := SideWays.reason_for(rest, next, run_seed, false)
		assert_eq(reason, SideWays.reason_for(rest, next, run_seed, false), "same seed, same answer")
		if reason == SideRules.Reason.AFTER_REST:
			hits += 1
		assert_eq(SideWays.reason_for(trial, next, run_seed, false), SideRules.Reason.NONE, "the trial is no rest")
	assert_almost_eq(hits / 1000.0, SideRules.AFTER_REST_CHANCE, 0.04, "SideRules.AFTER_REST_CHANCE (%d of 1000)" % hits)


func test_the_ladder_way_gets_a_gate_with_the_chest() -> void:
	var room := _room(7, 7, RoomSequence.RoomType.COMBAT, -1, true)
	var next := _room(8, 8, RoomSequence.RoomType.COMBAT, -1, true)
	assert_eq(SideWays.reason_for(room, next, 5, false), SideRules.Reason.NONE, "a plain combat room leads into a corridor")
	assert_null(SideWays.plan(room, next, 5, false))
	assert_eq(SideWays.reason_for(room, next, 5, false, true), SideRules.Reason.LADDER_WAY)
	var gate := SideWays.plan(room, next, 5, false, true)
	assert_not_null(gate)
	assert_eq(gate.reason, SideRules.Reason.LADDER_WAY, "plan gives what reason_for said")
	assert_true(gate.layout.chest_enabled, "the chest only on the ladder way")
	assert_gte(gate.layout.chest.x, 0, "a plan with a chest niche")
	assert_eq(gate.next_room, next)
	assert_eq(gate.get_parent(), room, "the gate goes with the room it leads out of")
	assert_eq(gate.layout.biome_id, RoomCatalog.biome_id_for_room(next.room_index))
	var again := SideWays.plan(room, next, 5, false, true)
	assert_eq(again.layout.plan_id, gate.layout.plan_id, "same seed and slot, same layout")
	assert_eq(again.rng_seed, gate.rng_seed)
	assert_null(SideWays.plan(room, next, 5, true, true), "never twice in a row")


func test_manager_asks_before_a_branch_shows_the_ladder_door() -> void:
	var manager := DungeonManager.new()
	autofree(manager)
	manager.set(&"_run_seed", 21)
	var campfire := _room(15, 16, RoomSequence.RoomType.CAMPFIRE)
	var first := _room(16, 17, RoomSequence.RoomType.COMBAT)
	var second := _room(17, 18, RoomSequence.RoomType.COMBAT)
	assert_true(manager.call(&"_enters_through_side", campfire, first), "behind the campfire the way runs through a segment")
	assert_false(manager.call(&"_enters_through_side", first, second), "between two fights a corridor")
	assert_false(manager.call(&"_enters_through_side", null, first), "room 1 has no way in")
	manager.set(&"_last_side_slot", campfire.slot_index)
	assert_false(manager.call(&"_enters_through_side", campfire, first), "not after another segment")


func test_the_ladder_way_always_draws_a_plan_with_a_chest_niche() -> void:
	for biome: StringName in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		assert_false(SidePlans.chest_ids_for(biome).is_empty(), "%s has a plan with a chest niche" % biome)
		for run_seed in 40:
			var layout := SidePlans.pick(biome, SideRules.make_rng(run_seed, 8), true)
			assert_gte(layout.chest.x, 0, "%s: %s has its chest niche" % [biome, layout.plan_id])
			assert_eq(layout.biome_id, biome)
	var rng := SideRules.make_rng(3, 8)
	SidePlans.pick(&"crypt", rng, true)
	var reference := SideRules.make_rng(3, 8)
	SidePlans.pick(&"crypt", reference)
	assert_eq(rng.state, reference.state, "one draw, like without the chest")
