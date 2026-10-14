extends GutTest
## Village unlocks (D-087): a fresh save starts with forge (Vitalität, Startschild, Schärfe), guild,
## home and dungeon; Chronik opens after the first run, Handelsposten with the first crystal, Goldgier,
## Dash-Training and Arsenal after the first boss. Events persist, are recorded by StatsTracker and
## are announced exactly once. Uses a test save file only.

const TEST_PATH := "user://test_meta_unlocks.cfg"
const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const BOSS_DATA := "res://enemies/data/boss_bone_king.tres"
const NORMAL_DATA := "res://enemies/data/skeleton.tres"

var _old_path: String


func before_all() -> void:
	_old_path = SaveManager.save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()


func after_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _kill(data_path: String) -> void:
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load(data_path)
	var result := DamageResult.new()
	result.killed = true
	EventBus.enemy_damaged.emit(enemy, result, null)
	enemy.free()


# --- Start state ---

func test_fresh_save_starts_with_the_d087_set() -> void:
	for id in [VillageBuildings.FORGE, VillageBuildings.GUILD, VillageBuildings.HOME]:
		assert_true(MetaUnlocks.is_building_open(id), "%s open from the start" % id)
	for id in [VillageBuildings.CHRONICLE, VillageBuildings.TRADER]:
		assert_false(MetaUnlocks.is_building_open(id), "%s locked" % id)
	assert_eq(MetaUnlocks.get_open_upgrades(), [MetaProgression.VITALITY, MetaProgression.START_SHIELD,
		MetaProgression.SHARPNESS] as Array[StringName])
	assert_eq(MetaUnlocks.get_locked_upgrade_events(), [MetaUnlocks.EVENT_FIRST_BOSS] as Array[StringName])


func test_lock_texts() -> void:
	assert_eq(MetaUnlocks.get_building_lock_text(VillageBuildings.CHRONICLE), "Öffnet nach deinem ersten Run")
	assert_eq(MetaUnlocks.get_building_lock_text(VillageBuildings.TRADER), "Öffnet mit deinem ersten Seelenkristall")
	assert_eq(MetaUnlocks.get_building_lock_text(VillageBuildings.FORGE), "", "open buildings have no lock text")
	assert_eq(MetaUnlocks.get_forge_lock_text(MetaUnlocks.EVENT_FIRST_BOSS), "Weitere Verbesserungen öffnen nach deinem ersten Boss.")


# --- Conditions (pure) ---

func test_reached_events_per_condition() -> void:
	assert_true(MetaUnlocks.reached_events({}).is_empty(), "nothing at the start")
	assert_eq(MetaUnlocks.reached_events({"runs_finished": 1}), [MetaUnlocks.EVENT_FIRST_RUN] as Array[StringName])
	assert_eq(MetaUnlocks.reached_events({"crystals": 1}), [MetaUnlocks.EVENT_FIRST_CRYSTAL] as Array[StringName])
	assert_eq(MetaUnlocks.reached_events({"crystals_earned": 2}), [MetaUnlocks.EVENT_FIRST_CRYSTAL] as Array[StringName],
		"crystals already spent on Proviant still count")
	assert_eq(MetaUnlocks.reached_events({"bosses": 1}), [MetaUnlocks.EVENT_FIRST_BOSS] as Array[StringName])
	assert_eq(MetaUnlocks.reached_events({"runs_finished": 3, "crystals": 4, "bosses": 2}).size(), 3)


func test_each_event_opens_exactly_its_part() -> void:
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_RUN)
	assert_true(MetaUnlocks.is_building_open(VillageBuildings.CHRONICLE))
	assert_false(MetaUnlocks.is_building_open(VillageBuildings.TRADER))
	assert_false(MetaUnlocks.is_upgrade_open(MetaProgression.ARSENAL))
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_CRYSTAL)
	assert_true(MetaUnlocks.is_building_open(VillageBuildings.TRADER))
	assert_false(MetaUnlocks.is_upgrade_open(MetaProgression.GOLD_GREED))
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	for id in MetaProgression.UPGRADE_ORDER:
		assert_true(MetaUnlocks.is_upgrade_open(id), String(id))
	assert_true(MetaUnlocks.get_locked_upgrade_events().is_empty())


func test_events_persist_and_are_recorded_once() -> void:
	watch_signals(SaveManager)
	assert_true(MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS))
	assert_false(MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS), "second time is not new")
	assert_false(MetaUnlocks.record_event(&"not_an_event"))
	assert_signal_emit_count(SaveManager, "content_unlocked", 1)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_true(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_BOSS), "stored in the save")
	assert_false(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_RUN))


func test_sync_from_save_uses_the_statistics() -> void:
	SaveManager.add_stat(StatsTracker.BOSSES, 1)
	SaveManager.add_stat(StatsTracker.DEATHS, 1)
	var added := MetaUnlocks.sync_from_save()
	assert_eq(added, [MetaUnlocks.EVENT_FIRST_RUN, MetaUnlocks.EVENT_FIRST_BOSS] as Array[StringName])
	assert_true(MetaUnlocks.sync_from_save().is_empty(), "only new events")
	SaveManager.add_permanent_crystals(1)
	assert_eq(MetaUnlocks.sync_from_save(), [MetaUnlocks.EVENT_FIRST_CRYSTAL] as Array[StringName])


func test_an_aborted_run_counts_once_it_is_over() -> void:
	RunManager.start_run()
	SaveManager.add_stat(StatsTracker.RUNS, 1)
	assert_true(MetaUnlocks.sync_from_save().is_empty(), "the run that is still going does not count")
	RunManager.end_run(RunManager.EndReason.ABORT)
	assert_eq(MetaUnlocks.sync_from_save(), [MetaUnlocks.EVENT_FIRST_RUN] as Array[StringName],
		"no death and no exit, but the run is over")


# --- Recorded while playing (StatsTracker) ---

func test_first_run_opens_the_chronicle_at_run_end() -> void:
	var tracker := StatsTracker.new()
	add_child_autofree(tracker)
	RunManager.start_run()
	assert_false(MetaUnlocks.is_building_open(VillageBuildings.CHRONICLE), "not during the first run")
	RunManager.end_run(RunManager.EndReason.ABORT)
	assert_true(MetaUnlocks.is_building_open(VillageBuildings.CHRONICLE), "also an aborted run counts")
	assert_false(MetaUnlocks.is_building_open(VillageBuildings.TRADER), "no crystal yet")
	assert_eq(SaveManager.load_game(), OK)
	assert_true(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_RUN), "saved at the run end")


func test_first_crystal_opens_the_trader() -> void:
	var tracker := StatsTracker.new()
	add_child_autofree(tracker)
	RunManager.start_run()
	RunManager.add_run_crystals(1)
	RunManager.end_run(RunManager.EndReason.DEATH)
	assert_eq(SaveManager.get_permanent_crystals(), 1, "50 % of 1 rounded up")
	assert_true(MetaUnlocks.is_building_open(VillageBuildings.TRADER))
	assert_eq(SaveManager.load_game(), OK)
	assert_true(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_CRYSTAL))


func test_first_boss_kill_is_saved_at_once() -> void:
	var tracker := StatsTracker.new()
	add_child_autofree(tracker)
	RunManager.start_run()
	_kill(NORMAL_DATA)
	assert_false(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_BOSS), "a normal enemy does not count")
	_kill(BOSS_DATA)
	assert_true(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_BOSS))
	assert_eq(SaveManager.get_stat(StatsTracker.BOSSES), 1)
	# Reload without ending the run: the event was written right away (a crash keeps it).
	var config := ConfigFile.new()
	assert_eq(config.load(TEST_PATH), OK)
	assert_true((config.get_value("progress", "unlocked", PackedStringArray()) as PackedStringArray).has(String(MetaUnlocks.EVENT_FIRST_BOSS)))


# --- Announcement ---

func test_announcement_once_per_event() -> void:
	assert_true(MetaUnlocks.take_announcements().is_empty(), "nothing unlocked, nothing to say")
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_RUN)
	var lines := MetaUnlocks.take_announcements()
	assert_eq(lines, ["Chronik", "Schmiede: Goldgier, Dash-Training und Arsenal"] as Array[String])
	assert_true(MetaUnlocks.take_announcements().is_empty(), "only once")
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_true(MetaUnlocks.take_announcements().is_empty(), "also after reloading")
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_CRYSTAL)
	assert_eq(MetaUnlocks.take_announcements(), ["Handelsposten"] as Array[String])


func test_join_names() -> void:
	assert_eq(MetaUnlocks.join_names([] as Array[String]), "")
	assert_eq(MetaUnlocks.join_names(["A"] as Array[String]), "A")
	assert_eq(MetaUnlocks.join_names(["A", "B"] as Array[String]), "A und B")
	assert_eq(MetaUnlocks.join_names(["A", "B", "C"] as Array[String]), "A, B und C")
