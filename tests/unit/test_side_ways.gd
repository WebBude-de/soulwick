extends GutTest
## Where the dungeon runs through obstacle runs (M5, D-144; D-216 with its Nachtrag 26.10.2026):
## SideWays.reason_for answers what SideWays.plan does later (the way into every champion room, the
## campfire, the ladder way; no random ways; never into or out of the boss room, never twice in a
## row, never with "Seitenwege auslassen"), every gate carries an obstacle run of the next room's
## biome and tier, the ladder way's with the chest, and the DungeonManager asks it before a branch
## may show the ladder door.
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


func test_a_run_before_every_champion_and_no_random_ways() -> void:
	# Two biomes: slots 1-33 (rooms 15 and 30 the bosses, slots 16 and 32 the campfires).
	var rooms: Array[RoomController] = []
	for slot in range(1, 34):
		var slot_type := RoomSequence.get_slot_type(slot)
		var special := RoomSequence.SpecialType.FOUNTAIN if slot_type == RoomSequence.RoomType.SPECIAL else -1
		rooms.append(_room(RoomSequence.get_room_for_slot(slot), slot, slot_type, special))
	var runs := 0
	var champions := 0
	var ways := 0
	for run_seed in 20:
		var previous := false
		for i in rooms.size() - 1:
			var room := rooms[i]
			var next := rooms[i + 1]
			var reason := SideWays.reason_for(room, next, run_seed, previous)
			if next.room_type == RoomSequence.RoomType.BOSS or room.room_type == RoomSequence.RoomType.BOSS:
				assert_eq(reason, SideRules.Reason.NONE, "never into or out of the boss room")
			elif next.room_type == RoomSequence.RoomType.MINIBOSS:
				assert_false(previous, "the way into the room before a champion is never a run (room %d)" % room.room_index)
				assert_eq(reason, SideRules.Reason.SHARE, "a run before the champion of room %d" % next.room_index)
				champions += 1
			elif room.is_campfire():
				assert_eq(reason, SideRules.Reason.BIOME_CHANGE, "behind the campfire always")
			else:
				assert_eq(reason, SideRules.Reason.NONE, "no random way into room %d" % next.room_index)
			ways += 1
			if reason != SideRules.Reason.NONE:
				runs += 1
			previous = reason != SideRules.Reason.NONE
	assert_eq(champions, 20 * 4, "rooms 5, 10, 20, 25")
	var share := float(runs) / ways
	# Without the ladder ways of branches (they count too, a little more in a run).
	assert_between(share, SideRules.SHARE_TARGET - 0.04, SideRules.SHARE_TARGET + 0.01, "share of the ways (%.3f)" % share)
	gut.p("share %.3f (%d obstacle runs on %d ways)" % [share, runs, ways])


func test_the_champion_way_never_meets_a_ladder_way() -> void:
	# The room before a champion is the special room (place 4): it never branches, and the way into
	# it is no run, so "never twice in a row" never takes the champion's run away.
	for champion_room: int in [5, 10, 20, 25, 35, 40, 50, 55, 65, 70]:
		assert_eq(RoomSequence.get_room_type(champion_room), RoomSequence.RoomType.MINIBOSS)
		var before := champion_room - 1
		assert_false(SideRules.may_offer_ladder(before, RoomSequence.get_room_type(before), RoomSequence.RoomType.MINIBOSS),
				"room %d shows no ladder door" % before)
		assert_false(SideRules.may_offer_ladder(before - 1, RoomSequence.get_room_type(before - 1), RoomSequence.get_room_type(before)),
				"no ladder way into room %d" % before)
	var sixth := _room(6, 6, RoomSequence.RoomType.COMBAT)
	var seventh := _room(7, 7, RoomSequence.RoomType.COMBAT)
	assert_true(SideRules.may_offer_ladder(6, RoomSequence.RoomType.COMBAT, RoomSequence.get_slot_type(7)))
	assert_eq(SideWays.reason_for(_room(5, 5, RoomSequence.RoomType.MINIBOSS), sixth, 3, false), SideRules.Reason.NONE,
			"out of the champion room a plain corridor: room 6 may show the ladder door")
	assert_eq(SideWays.reason_for(sixth, seventh, 3, false, true), SideRules.Reason.LADDER_WAY, "the ladder way itself is an obstacle run")


func test_a_plan_draws_an_obstacle_run_of_the_biome_and_tier() -> void:
	var room := _room(9, 9, RoomSequence.RoomType.SPECIAL, RoomSequence.SpecialType.SHOP, true)
	var next := _room(10, 10, RoomSequence.RoomType.MINIBOSS, -1, true)
	var runs := {}
	for run_seed in 120:
		var gate := SideWays.plan(room, next, run_seed, false, false, false)
		assert_not_null(gate, "the way into the champion is always a run")
		if gate == null:
			continue
		assert_eq(gate.reason, SideRules.Reason.SHARE)
		assert_true(gate.layout.is_obstacle_run(), "every section is an obstacle run (D-216)")
		assert_true(ObstacleRunPlans.ids_for(&"crypt", SideRules.tier_for(10)).has(gate.layout.plan_id), "a crypt run of tier 1")
		assert_false(gate.layout.chest_enabled, "no chest outside the ladder way")
		runs[gate.layout.plan_id] = true
		var again := SideWays.plan(room, next, run_seed, false, false, false)
		assert_eq(again.layout.plan_id, gate.layout.plan_id, "same seed, same run")
		assert_eq(again.layout.is_mirrored, gate.layout.is_mirrored)
		assert_eq(again.rng_seed, gate.rng_seed)
		gate.free()
		again.free()
	assert_gt(runs.size(), 1, "more than one run comes up")


func test_the_ladder_way_gets_a_gate_with_the_chest() -> void:
	var room := _room(7, 7, RoomSequence.RoomType.COMBAT, -1, true)
	var next := _room(8, 8, RoomSequence.RoomType.COMBAT, -1, true)
	assert_eq(SideWays.reason_for(room, next, 5, false), SideRules.Reason.NONE, "between two fights a plain corridor")
	assert_eq(SideWays.reason_for(room, next, 5, false, true), SideRules.Reason.LADDER_WAY)
	var gate := SideWays.plan(room, next, 5, false, true)
	assert_not_null(gate)
	assert_eq(gate.reason, SideRules.Reason.LADDER_WAY, "plan gives what reason_for said")
	assert_true(gate.layout.chest_enabled, "the chest only on the ladder way")
	assert_gte(gate.layout.chest.x, 0, "a run with a chest niche")
	assert_true(gate.layout.is_obstacle_run())
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
	assert_false(manager.call(&"_enters_through_side", first, second), "between two fights a plain corridor")
	var special := _room(19, 20, RoomSequence.RoomType.SPECIAL, RoomSequence.SpecialType.SHOP)
	var champion := _room(20, 21, RoomSequence.RoomType.MINIBOSS)
	assert_true(manager.call(&"_enters_through_side", special, champion), "into the champion through a run")
	assert_false(manager.call(&"_enters_through_side", null, first), "room 1 has no way in")
	manager.set(&"_last_side_slot", campfire.slot_index)
	assert_false(manager.call(&"_enters_through_side", campfire, first), "not after another segment")


func test_every_run_has_its_chest_niche_and_one_pick_draws_twice() -> void:
	for biome: StringName in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		for run_seed in 20:
			var layout := ObstacleRunPlans.pick(biome, SideRules.make_rng(run_seed, 8), SideRules.MAX_TIER)
			assert_gte(layout.chest.x, 0, "%s: %s has its chest niche" % [biome, layout.plan_id])
			assert_eq(layout.biome_id, biome)
	var rng := SideRules.make_rng(3, 8)
	ObstacleRunPlans.pick(&"crypt", rng)
	var reference := SideRules.make_rng(3, 8)
	reference.randi()
	reference.randf()
	assert_eq(rng.state, reference.state, "two draws: the run and its turrets")

