extends GutTest
## Cloud merge rules (KF9, D-188 rule 7, KONZEPT §10): one check per field of the v5 save
## (SaveMerge.FIELD_RULES), the choice of the state played last, the cloud blob both ways and its
## content hash. Pure ConfigFiles, no save file is touched.

const WORLD_ID := "3f0c1d5e-8a2b-4c6d-9e1f-0a1b2c3d4e5f"
const OLD := 1_760_000_000
const NEW := 1_760_009_999
## The only save file these tests write (AGENTS §6.4).
const TEST_PATH := "user://test_save_merge_full.cfg"

var _old_path: String


func before_all() -> void:
	_old_path = SaveManager.save_path
	SaveManager.save_path = TEST_PATH


func after_all() -> void:
	_remove_test_files()
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _remove_test_files() -> void:
	for suffix in ["", ".v4.bak", ".prev.bak", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))


## A v5 state of the test world; body is added as it is (sections may repeat keys of the head).
func _state(last_played: int, body := "") -> ConfigFile:
	var config := ConfigFile.new()
	var text := "[meta]\nversion=5\n[world]\nid=\"%s\"\n[profile]\nlast_played=%d\n%s\n" % [WORLD_ID, last_played, body]
	assert_eq(config.parse(_merge_sections(text)), OK, "test state parses")
	return config


## ConfigFile.parse does not allow a section twice: join repeated sections of the test text.
func _merge_sections(text: String) -> String:
	var sections := {}
	var order: Array[String] = []
	var current := ""
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		if stripped.begins_with("["):
			current = stripped
			if not sections.has(current):
				sections[current] = []
				order.append(current)
			continue
		(sections[current] as Array).append(stripped)
	var out := ""
	for section in order:
		out += section + "\n" + "\n".join(PackedStringArray(sections[section])) + "\n"
	return out


## Merges a local state (played at local_time) with a server state (server_time).
func _merge(local_time: int, local_body: String, server_time: int, server_body: String) -> ConfigFile:
	var result := SaveMerge.merge(_state(local_time, local_body), _state(server_time, server_body))
	assert_true(result["ok"], "merge works: %s" % result["error"])
	return result["config"]


# --- The table covers every field ---

func test_every_saved_field_has_a_rule() -> void:
	var saved := _full_save()
	for section in saved.get_sections():
		for key in saved.get_section_keys(section):
			var listed := SaveMerge.FIELD_RULES.has("%s/%s" % [section, key]) or SaveMerge.FIELD_RULES.has("%s/*" % section)
			assert_true(listed, "[%s] %s has its merge rule in SaveMerge.FIELD_RULES (ROADMAP rule 4)" % [section, key])


## A v5 world with every field SaveManager writes (from a v4 file with forge, legacy profile, …).
func _full_save() -> ConfigFile:
	_remove_test_files()
	var path := TEST_PATH
	SaveManager.save_path = path
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string("res://tests/fixtures/save_v4_forge_test.cfg"))
	file.close()
	SaveManager.load_game()
	SaveManager.set_trade_level(&"luck", 1)
	SaveManager.add_pending_boost(&"healing_potion")
	SaveManager.mark_seen(&"intro_forge")
	SaveManager.set_world_name("Testwelt")
	SaveManager.save_game()
	var saved := ConfigFile.new()
	saved.load(path)
	return saved


# --- One check per field ---

func test_meta_version_is_the_current_one() -> void:
	var server := ConfigFile.new()
	server.parse("[meta]\nversion=4\n[world]\nid=\"%s\"\n[progress]\npermanent_gold=5\n" % WORLD_ID)
	var result := SaveMerge.merge(_state(NEW), server)
	assert_true(result["ok"])
	assert_eq((result["config"] as ConfigFile).get_value("meta", "version"), SaveManager.SAVE_VERSION, "older side migrated first")


func test_gold_comes_from_the_state_played_last() -> void:
	assert_eq(_merge(NEW, "[progress]\npermanent_gold=10", OLD, "[progress]\npermanent_gold=900").get_value("progress", "permanent_gold"), 10)
	assert_eq(_merge(OLD, "[progress]\npermanent_gold=10", NEW, "[progress]\npermanent_gold=900").get_value("progress", "permanent_gold"), 900)


func test_crystals_come_from_the_state_played_last() -> void:
	assert_eq(_merge(OLD, "[progress]\npermanent_crystals=1", NEW, "[progress]\npermanent_crystals=7").get_value("progress", "permanent_crystals"), 7)


func test_start_weapon_comes_from_the_state_played_last() -> void:
	var merged := _merge(NEW, "[progress]\nstart_weapon=\"bow\"", OLD, "[progress]\nstart_weapon=\"staff\"")
	assert_eq(merged.get_value("progress", "start_weapon"), "bow")


func test_second_weapon_comes_from_the_state_played_last() -> void:
	var merged := _merge(OLD, "[progress]\nsecond_weapon=\"bow\"", NEW, "[progress]\nsecond_weapon=\"\"")
	assert_eq(merged.get_value("progress", "second_weapon"), "")


func test_unlocks_are_united() -> void:
	var merged := _merge(NEW, "[progress]\nunlocked=PackedStringArray(\"hint_slime\", \"event_first_run\")",
			OLD, "[progress]\nunlocked=PackedStringArray(\"hint_slime\", \"hint_golem\")")
	var unlocked: PackedStringArray = merged.get_value("progress", "unlocked")
	assert_eq(unlocked.size(), 3)
	for id in ["hint_slime", "event_first_run", "hint_golem"]:
		assert_has(unlocked, id)


func test_forge_weapon_levels_take_the_maximum() -> void:
	var merged := _merge(NEW, "[meta_upgrades]\nsmith_sword=1\nsmith_bow=4", OLD, "[meta_upgrades]\nsmith_sword=3\nsmith_bow=2")
	assert_eq(merged.get_value("meta_upgrades", "smith_sword"), 3)
	assert_eq(merged.get_value("meta_upgrades", "smith_bow"), 4)


func test_forge_unlocks_are_kept_from_both_sides() -> void:
	var merged := _merge(NEW, "[meta_upgrades]\narsenal_bow=1", OLD, "[meta_upgrades]\narsenal_staff=1\nsecond_slot=1")
	assert_eq(merged.get_value("meta_upgrades", "arsenal_bow"), 1)
	assert_eq(merged.get_value("meta_upgrades", "arsenal_staff"), 1)
	assert_eq(merged.get_value("meta_upgrades", "second_slot"), 1)


func test_shield_plate_and_lantern_take_the_maximum() -> void:
	var merged := _merge(NEW, "[meta_upgrades]\nshield_plate=1\nlantern=2", OLD, "[meta_upgrades]\nshield_plate=3\nlantern=1")
	assert_eq(merged.get_value("meta_upgrades", "shield_plate"), 3)
	assert_eq(merged.get_value("meta_upgrades", "lantern"), 2)


func test_trade_levels_take_the_maximum() -> void:
	var merged := _merge(NEW, "[trade_levels]\nprovision_slot=2\nluck=0\nmerchant_friend=1",
			OLD, "[trade_levels]\nprovision_slot=1\nluck=3\nmerchant_friend=1")
	assert_eq(merged.get_value("trade_levels", "provision_slot"), 2)
	assert_eq(merged.get_value("trade_levels", "luck"), 3)
	assert_eq(merged.get_value("trade_levels", "merchant_friend"), 1)


func test_packed_proviant_comes_from_the_state_played_last() -> void:
	var merged := _merge(OLD, "[boosts]\npending=PackedStringArray(\"healing_potion\")", NEW, "[boosts]\npending=PackedStringArray()")
	assert_eq(merged.get_value("boosts", "pending"), PackedStringArray(), "the newer state used it up")


func test_records_take_the_maximum() -> void:
	var merged := _merge(NEW, "[stats]\ndeepest_room=12\nbest_run_gold=300", OLD, "[stats]\ndeepest_room=40\nbest_run_gold=100")
	assert_eq(merged.get_value("stats", "deepest_room"), 40)
	assert_eq(merged.get_value("stats", "best_run_gold"), 300)


func test_chronicle_counters_take_the_maximum() -> void:
	var merged := _merge(NEW, "[stats]\nruns=5\nkills=90\nplay_time=100.5", OLD, "[stats]\nruns=8\nkills=40\nplay_time=900.25\nexits=2")
	assert_eq(merged.get_value("stats", "runs"), 8)
	assert_eq(merged.get_value("stats", "kills"), 90)
	assert_almost_eq(float(merged.get_value("stats", "play_time")), 900.25, 0.001)
	assert_eq(merged.get_value("stats", "exits"), 2, "a counter only one side has")


func test_rescued_villagers_and_chickens_take_the_maximum() -> void:
	var merged := _merge(NEW, "[stats]\nrescued_villagers=1\nrescued_chickens=4", OLD, "[stats]\nrescued_villagers=3\nrescued_chickens=2")
	assert_eq(merged.get_value("stats", "rescued_villagers"), 3)
	assert_eq(merged.get_value("stats", "rescued_chickens"), 4)


func test_seen_ids_are_united() -> void:
	var merged := _merge(NEW, "[seen]\nids=PackedStringArray(\"intro_forge\")", OLD, "[seen]\nids=PackedStringArray(\"intro_trader\", \"intro_forge\")")
	var seen: PackedStringArray = merged.get_value("seen", "ids")
	assert_eq(seen.size(), 2)
	assert_has(seen, "intro_trader")


func test_seen_all_is_true_if_one_side_has_it() -> void:
	assert_true(_merge(NEW, "[seen]\nall=false", OLD, "[seen]\nall=true").get_value("seen", "all"))
	assert_false(_merge(NEW, "[seen]\nall=false", OLD, "[seen]\nall=false").get_value("seen", "all"))


func test_world_id_must_be_the_same() -> void:
	var other := ConfigFile.new()
	other.parse("[meta]\nversion=5\n[world]\nid=\"11111111-2222-4333-8444-555555555555\"\n")
	var result := SaveMerge.merge(_state(NEW), other)
	assert_false(result["ok"])
	assert_eq(result["error"], "world_id_mismatch")
	var upper := ConfigFile.new()
	upper.parse("[meta]\nversion=5\n[world]\nid=\"%s\"\n" % WORLD_ID.to_upper())
	assert_true(SaveMerge.merge(_state(NEW), upper)["ok"], "case does not matter")


func test_world_name_comes_from_the_state_played_last() -> void:
	assert_eq(_merge(OLD, "[world]\nname=\"Alt\"", NEW, "[world]\nname=\"Neu\"").get_value("world", "name"), "Neu")


func test_created_takes_the_earliest_known_time() -> void:
	assert_eq(_merge(NEW, "[profile]\ncreated=500", OLD, "[profile]\ncreated=300").get_value("profile", "created"), 300)
	assert_eq(_merge(NEW, "[profile]\ncreated=500", OLD, "[profile]\ncreated=0").get_value("profile", "created"), 500, "0 = unknown")


func test_last_played_takes_the_latest() -> void:
	assert_eq(_merge(OLD, "", NEW, "").get_value("profile", "last_played"), NEW)
	assert_eq(_merge(NEW, "", OLD, "").get_value("profile", "last_played"), NEW)


func test_v5_refund_counts_once_with_the_maximum() -> void:
	var merged := _merge(NEW, "[migration]\nv5_refund_gold=0\nv5_shield_plate=0",
			OLD, "[migration]\nv5_refund_gold=460\nv5_shield_plate=2")
	assert_eq(merged.get_value("migration", "v5_refund_gold"), 460)
	assert_eq(merged.get_value("migration", "v5_shield_plate"), 2)


func test_v5_refund_lists_are_united() -> void:
	var merged := _merge(NEW, "[migration]\nv5_refunded=PackedStringArray(\"vitality:2\")\nv5_weapons=PackedStringArray()",
			OLD, "[migration]\nv5_refunded=PackedStringArray(\"vitality:2\", \"sharpness:1\")\nv5_weapons=PackedStringArray(\"bow\")")
	assert_eq(merged.get_value("migration", "v5_refunded"), PackedStringArray(["vitality:2", "sharpness:1"]))
	assert_eq(merged.get_value("migration", "v5_weapons"), PackedStringArray(["bow"]))


func test_v5_notice_is_shown_once_on_any_device() -> void:
	assert_false(_merge(OLD, "[migration]\nv5_notice_pending=true", NEW, "[migration]\nv5_notice_pending=false").get_value("migration", "v5_notice_pending"))
	assert_false(_merge(NEW, "[migration]\nv5_notice_pending=false", OLD, "[migration]\nv5_notice_pending=true").get_value("migration", "v5_notice_pending"))
	assert_true(_merge(NEW, "[migration]\nv5_notice_pending=true", OLD, "[migration]\nv5_notice_pending=true").get_value("migration", "v5_notice_pending"))


func test_legacy_profile_comes_from_the_state_played_last() -> void:
	var merged := _merge(OLD, "[legacy_profile]\nname=\"Alt\"", NEW, "[legacy_profile]\nname=\"Neu\"")
	assert_eq(merged.get_value("legacy_profile", "name"), "Neu")


func test_bought_decoration_takes_the_maximum() -> void:
	var merged := _merge(NEW, "[decor_owned]\nbush=1\nlamp_post=2", OLD, "[decor_owned]\nbush=3\nfence_gate=1")
	assert_eq(merged.get_value("decor_owned", "bush"), 3, "bought pieces never get lost")
	assert_eq(merged.get_value("decor_owned", "lamp_post"), 2)
	assert_eq(merged.get_value("decor_owned", "fence_gate"), 1)


func test_village_decoration_comes_from_the_state_played_last() -> void:
	var local := "[decor_placed]\nvillage=PackedStringArray(\"bush:1:1:0\")"
	var server := "[decor_placed]\nvillage=PackedStringArray(\"bush:5:5:0\", \"bush:6:5:0\")"
	assert_eq(_merge(NEW, local, OLD, server).get_value("decor_placed", "village"), PackedStringArray(["bush:1:1:0"]))
	assert_eq(_merge(OLD, local, NEW, server).get_value("decor_placed", "village"), PackedStringArray(["bush:5:5:0", "bush:6:5:0"]),
		"one arrangement, never two on top of each other")


func test_home_furniture_comes_from_the_state_played_last() -> void:
	var local := "[decor_placed]\nhome=PackedStringArray(\"chest_cozy:2:3:0\")"
	var server := "[decor_placed]\nhome=PackedStringArray()"
	assert_eq(_merge(NEW, local, OLD, server).get_value("decor_placed", "home"), PackedStringArray(["chest_cozy:2:3:0"]))
	assert_eq(_merge(OLD, local, NEW, server).get_value("decor_placed", "home"), PackedStringArray())


func test_home_wallpaper_comes_from_the_state_played_last() -> void:
	assert_eq(_merge(NEW, "[decor]\nhome_wall=\"soul\"", OLD, "[decor]\nhome_wall=\"cozy\"").get_value("decor", "home_wall"), "soul")
	assert_eq(_merge(OLD, "[decor]\nhome_wall=\"soul\"", NEW, "[decor]\nhome_wall=\"cozy\"").get_value("decor", "home_wall"), "cozy")


func test_home_floor_comes_from_the_state_played_last() -> void:
	assert_eq(_merge(NEW, "[decor]\nhome_floor=\"rustic\"", OLD, "[decor]\nhome_floor=\"\"").get_value("decor", "home_floor"), "rustic")
	assert_eq(_merge(OLD, "[decor]\nhome_floor=\"rustic\"", NEW, "[decor]\nhome_floor=\"\"").get_value("decor", "home_floor"), "")


func test_cloud_section_stays_local() -> void:
	var merged := _merge(OLD, "[cloud]\nbase_revision=4\nplayer_id=\"me\"", NEW, "[cloud]\nbase_revision=9\nplayer_id=\"other\"")
	assert_eq(merged.get_value("cloud", "base_revision"), 4)
	assert_eq(merged.get_value("cloud", "player_id"), "me")


func test_unknown_sections_come_whole_from_the_state_played_last() -> void:
	var merged := _merge(OLD, "[village_decor]\nbench=\"oak\"\nlamp=\"red\"", NEW, "[village_decor]\nbench=\"stone\"")
	assert_eq(merged.get_value("village_decor", "bench"), "stone")
	assert_false(merged.has_section_key("village_decor", "lamp"), "the older state's deco is not mixed in")


# --- Who won, backups, versions ---

func test_a_tie_keeps_this_devices_state() -> void:
	var result := SaveMerge.merge(_state(NEW, "[progress]\npermanent_gold=1"), _state(NEW, "[progress]\npermanent_gold=2"))
	assert_eq(result["winner"], SaveMerge.LOCAL)
	assert_eq((result["config"] as ConfigFile).get_value("progress", "permanent_gold"), 1)


func test_loser_lost_only_when_a_last_played_field_differs() -> void:
	var same := SaveMerge.merge(_state(NEW, "[progress]\npermanent_gold=5\n[stats]\nruns=3"), _state(OLD, "[progress]\npermanent_gold=5\n[stats]\nruns=1"))
	assert_false(same["loser_lost"], "only monotone fields differ: nothing is lost")
	var other := SaveMerge.merge(_state(NEW, "[progress]\npermanent_gold=5"), _state(OLD, "[progress]\npermanent_gold=50"))
	assert_true(other["loser_lost"], "the older gold is replaced")
	assert_eq(other["winner"], SaveMerge.LOCAL)


func test_a_newer_save_version_is_not_merged() -> void:
	var newer := ConfigFile.new()
	newer.parse("[meta]\nversion=%d\n[world]\nid=\"%s\"\n" % [SaveManager.SAVE_VERSION + 1, WORLD_ID])
	var result := SaveMerge.merge(_state(NEW), newer)
	assert_false(result["ok"])
	assert_eq(result["error"], "newer_version")


func test_merge_does_not_change_its_inputs() -> void:
	var local := _state(NEW, "[stats]\nruns=1")
	var server := _state(OLD, "[stats]\nruns=9")
	SaveMerge.merge(local, server)
	assert_eq(local.get_value("stats", "runs"), 1)
	assert_eq(server.get_value("stats", "runs"), 9)


# --- The cloud blob ---

func test_world_data_round_trip_keeps_the_types() -> void:
	var state := _state(NEW, "[progress]\npermanent_gold=12\nunlocked=PackedStringArray(\"a\", \"b\")\n[seen]\nall=false\nids=PackedStringArray()\n[stats]\nplay_time=12.25\nruns=3\n[cloud]\nbase_revision=2")
	var data := SaveMerge.to_world_data(state)
	assert_false(data.has("cloud"), "[cloud] never goes up")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data))
	var back := SaveMerge.from_world_data(parsed)
	assert_eq(typeof(back.get_value("progress", "permanent_gold")), TYPE_INT)
	assert_eq(back.get_value("progress", "unlocked"), PackedStringArray(["a", "b"]))
	assert_eq(typeof(back.get_value("seen", "ids")), TYPE_PACKED_STRING_ARRAY, "an empty list is a string list")
	assert_eq(back.get_value("seen", "all"), false)
	assert_almost_eq(float(back.get_value("stats", "play_time")), 12.25, 0.0001)
	assert_eq(back.get_value("profile", "last_played"), NEW)
	assert_eq(SaveManager.check_world_config(back), "", "loads like a save file")
	assert_eq(SaveMerge.content_hash(SaveMerge.to_world_data(back)), SaveMerge.content_hash(data), "same content after JSON")


func test_content_hash_ignores_last_played_and_list_order() -> void:
	var a := SaveMerge.to_world_data(_state(OLD, "[progress]\nunlocked=PackedStringArray(\"a\", \"b\")"))
	var b := SaveMerge.to_world_data(_state(NEW, "[progress]\nunlocked=PackedStringArray(\"b\", \"a\")"))
	assert_eq(SaveMerge.content_hash(a), SaveMerge.content_hash(b))
	var c := SaveMerge.to_world_data(_state(NEW, "[progress]\nunlocked=PackedStringArray(\"a\")"))
	assert_ne(SaveMerge.content_hash(a), SaveMerge.content_hash(c))


func test_whole_floats_become_ints_and_others_are_rounded() -> void:
	assert_eq(SaveMerge.to_json_value(4133.0), 4133)
	assert_eq(typeof(SaveMerge.to_json_value(4133.0)), TYPE_INT)
	assert_almost_eq(float(SaveMerge.to_json_value(4133.2386317)), 4133.239, 0.0000001)
	assert_eq(SaveMerge.from_json_value(7.0), 7)
	assert_eq(typeof(SaveMerge.from_json_value(7.0)), TYPE_INT)


func test_real_v4_world_round_trips() -> void:
	var config := ConfigFile.new()
	assert_eq(config.load("res://tests/fixtures/save_v4_real.cfg"), OK)
	SaveManager.migrate(config)
	var data := SaveMerge.to_world_data(config)
	assert_lt(SaveMerge.data_size(data), CloudSave.MAX_DATA_BYTES, "a real world fits the cloud limit")
	var back := SaveMerge.from_world_data(JSON.parse_string(JSON.stringify(data)))
	assert_eq(back.get_value("progress", "unlocked"), config.get_value("progress", "unlocked"))
	assert_eq(back.get_value("stats", "deepest_room"), config.get_value("stats", "deepest_room"))
	var merged := SaveMerge.merge(config, back)
	assert_true(merged["ok"])
	assert_false(merged["loser_lost"], "a world merged with itself loses nothing")
