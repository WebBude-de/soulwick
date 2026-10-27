extends GutTest
## "Dein Fortschritt" (D-188, KF1): ProgressSummary reads a world without loading it (also an old
## v2 save, migrated in memory), counts forge levels, bosses per biome and unlocks, and orders the
## next goals. Pure rules on snapshots plus file reads in a test folder; never the real save.

const ROOT := "user://test_progress_summary"
const V2_FIXTURE := "res://tests/fixtures/save_v2_legacy.cfg"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	Loc.apply(&"de")


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	PlayerProfile.reset()
	TranslationServer.set_locale(_old_locale)


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root.path_join("saves"))


func _world(levels := {}, events: Array[StringName] = [], deepest := 0, bosses := 0, gold := 0) -> Dictionary:
	var world := ProgressSummary.empty_world()
	world["exists"] = true
	world["levels"] = levels
	world["events"] = events
	world["stats"] = {StatsTracker.DEEPEST_ROOM: deepest, StatsTracker.BOSSES: bosses}
	world["gold"] = gold
	return world


func _kinds(summary: Dictionary) -> Array:
	return (summary["goals"] as Array).map(func(goal: Dictionary) -> StringName: return goal["kind"])


# --- Pure rules ---

func test_fresh_world_aims_at_the_first_run() -> void:
	var summary := ProgressSummary.build(_world())
	assert_eq(summary["forge_level"], 0)
	assert_eq(summary["forge_max"], 36, "KONZEPT §5.1: 36 forge levels (KE4)")
	assert_eq(_kinds(summary), [ProgressSummary.GOAL_UNLOCK, ProgressSummary.GOAL_FORGE_SAVE], "the unlock is the dungeon goal")
	assert_eq(summary["goals"][0]["event"], MetaUnlocks.EVENT_FIRST_RUN)
	assert_eq(ProgressSummary.next_goal_text(summary), "Nächstes Ziel: Beende deinen ersten Run – öffnet: Chronik")
	assert_eq(summary["next_boss"]["room"], 15)
	var save: Dictionary = summary["goals"][1]
	assert_eq(save["id"], MetaProgression.SHIELD_PLATE, "the cheapest open step (Schildplatte I for 40)")
	assert_eq(ProgressSummary.goal_text(save), "Noch 40 Gold bis Schildplatte I")
	for biome: Dictionary in summary["biomes"]:
		assert_false(biome["reached"], "no biome reached before the first run")


func test_affordable_forge_step_comes_first() -> void:
	var events: Array[StringName] = [MetaUnlocks.EVENT_FIRST_RUN]
	var summary := ProgressSummary.build(_world({}, events, 6, 0, 45))
	var first: Dictionary = summary["goals"][0]
	assert_eq(first["kind"], ProgressSummary.GOAL_FORGE_BUY)
	assert_eq(ProgressSummary.goal_text(first), "Kauf Schildplatte I in der Schmiede (40 Gold)")
	assert_eq(summary["goals"][1]["event"], MetaUnlocks.EVENT_FIRST_CRYSTAL, "then the next unlock")
	assert_false(_kinds(summary).has(ProgressSummary.GOAL_FORGE_SAVE), "no 'save gold' when it is affordable")


func test_first_boss_is_the_unlock_goal() -> void:
	var events: Array[StringName] = [MetaUnlocks.EVENT_FIRST_RUN, MetaUnlocks.EVENT_FIRST_CRYSTAL]
	var summary := ProgressSummary.build(_world({}, events, 12))
	assert_eq(_kinds(summary), [ProgressSummary.GOAL_UNLOCK, ProgressSummary.GOAL_FORGE_SAVE])
	assert_eq(ProgressSummary.goal_text(summary["goals"][0]),
			"Besiege deinen ersten Boss (Raum 15) – öffnet: Schmiede: Arsenal und Zweiter Startplatz")


func test_bosses_per_biome_follow_the_record() -> void:
	assert_eq(ProgressSummary.bosses_passed(0, 0), 0)
	assert_eq(ProgressSummary.bosses_passed(14, 0), 0)
	assert_eq(ProgressSummary.bosses_passed(15, 0), 0, "died at the first boss")
	assert_eq(ProgressSummary.bosses_passed(15, 1), 1, "beat it and left at the campfire")
	assert_eq(ProgressSummary.bosses_passed(16, 1), 1)
	assert_eq(ProgressSummary.bosses_passed(31, 2), 2)
	assert_eq(ProgressSummary.bosses_passed(45, 2), 2, "the third boss is not beaten yet")
	var summary := ProgressSummary.build(_world({}, MetaUnlocks.EVENTS.duplicate(), 31, 2))
	var biomes: Array = summary["biomes"]
	assert_true(biomes[0]["beaten"] and biomes[1]["beaten"])
	assert_true(biomes[2]["reached"], "room 31 is in the Schattenreich")
	assert_false(biomes[2]["beaten"])
	assert_false(biomes[3]["reached"])
	var boss: Dictionary = summary["next_boss"]
	assert_eq(boss["room"], 45)
	assert_eq(boss["biome"], RoomSequence.Biome.SHADOW_REALM)
	var goal: Dictionary = summary["goals"].filter(func(g: Dictionary) -> bool: return g["kind"] == ProgressSummary.GOAL_BOSS)[0]
	assert_eq(ProgressSummary.goal_text(goal), "Nächster Boss: Schattenlord in Raum 45")


func test_forge_step_skips_locked_and_maxed_upgrades() -> void:
	var levels := {MetaProgression.SHIELD_PLATE: 3, MetaProgression.LANTERN: 3}
	for id in MetaProgression.WEAPON_UPGRADES:
		levels[id] = 5
	var events: Array[StringName] = [MetaUnlocks.EVENT_FIRST_RUN]
	assert_eq(ProgressSummary.forge_step(levels, events, 999), {}, "the rest is locked until the first boss")
	events.append(MetaUnlocks.EVENT_FIRST_BOSS)
	var step := ProgressSummary.forge_step(levels, events, 100)
	assert_eq(step["id"], MetaProgression.ARSENAL_BOW, "80 gold: the cheapest Arsenal entry")
	assert_eq(step["level"], 1)
	assert_eq(step["missing"], 0)
	assert_eq(ProgressSummary.goal_text({"kind": ProgressSummary.GOAL_FORGE_BUY, "id": step["id"], "level": 1, "cost": 80}),
		"Kauf Arsenal: Bogen in der Schmiede (80 Gold)", "one level: no number")
	assert_eq(ProgressSummary.forge_level(levels), 31)
	assert_eq(ProgressSummary.forge_level({MetaProgression.SHIELD_PLATE: 99}), 3, "at most the maximum")


func test_reward_goal_comes_from_the_account() -> void:
	var events: Array[StringName] = MetaUnlocks.EVENTS.duplicate()
	var summary := ProgressSummary.build(_world({}, events, 20, 1), {"xp": 660, "best_room": 31, "bosses": 4})
	var account: Dictionary = summary["account"]
	assert_eq(account["level"], 4, "660 XP")
	assert_eq(account["next_reward"], 5)
	assert_eq(account["reward_missing"], 340, "level 5 at 1000 XP")
	assert_eq(account["best_room"], 31)
	assert_true(_kinds(summary).has(ProgressSummary.GOAL_REWARD))
	var goal: Dictionary = summary["goals"].filter(func(g: Dictionary) -> bool: return g["kind"] == ProgressSummary.GOAL_REWARD)[0]
	assert_eq(ProgressSummary.goal_text(goal), "Level 5: neue Belohnung (noch 340 XP)")
	assert_lte((summary["goals"] as Array).size(), ProgressSummary.MAX_GOALS)


# --- Files ---

func test_old_v2_save_is_read_without_loading_it() -> void:
	var path := SaveManager.slot_path(2)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(V2_FIXTURE), ProjectSettings.globalize_path(path))
	var before := FileAccess.get_file_as_string(path)
	var world := ProgressSummary.world_from_file(path)
	assert_true(world["exists"])
	assert_eq(world["events"], MetaUnlocks.EVENTS, "D-087: old saves count as everything unlocked")
	assert_eq(world["gold"], 54 + 570, "migrated in memory: the v5 refund (KE4)")
	assert_eq(int(world["stats"][StatsTracker.DEEPEST_ROOM]), 45)
	var summary := ProgressSummary.build(world)
	assert_eq(summary["forge_level"], SaveSlots.forge_progress(_migrated(path)), "same count as the world list")
	assert_eq(summary["bosses"], 10)
	assert_eq(FileAccess.get_file_as_string(path), before, "the file is not touched")
	assert_eq(SaveManager.get_active_slot(), 0, "nothing was loaded")


func test_missing_or_broken_file_is_an_empty_world() -> void:
	assert_false(ProgressSummary.world_from_file(ROOT.path_join("nothing.cfg"))["exists"])
	var broken := ROOT.path_join("broken.cfg")
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("[meta]\nversion=99\n")
	file.close()
	assert_false(ProgressSummary.world_from_file(broken)["exists"], "a newer version is not guessed at")


func test_snapshot_of_the_loaded_save_matches_the_file() -> void:
	SaveManager.create_slot(1, "Nebeltal")
	SaveManager.set_meta_level(MetaProgression.SMITH_SWORD, 2)
	SaveManager.add_permanent_gold(33)
	SaveManager.record_stat_max(StatsTracker.DEEPEST_ROOM, 17)
	SaveManager.add_stat(StatsTracker.BOSSES, 1)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_RUN)
	SaveManager.save_game()
	var loaded := ProgressSummary.build(ProgressSummary.world_from_save())
	var read := ProgressSummary.build(ProgressSummary.world_from_file(SaveManager.slot_path(1)))
	assert_eq(loaded, read)
	assert_eq(loaded["forge_level"], 2)
	assert_eq(ProgressSummary.world_from_save()["name"], "Nebeltal")


func _migrated(path: String) -> ConfigFile:
	var config := ConfigFile.new()
	config.load(path)
	return config
