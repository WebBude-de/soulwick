extends GutTest
## Save format v6/v7 (WK5, WK7, KE8b, D-059): decoration. One check per field ([decor_owned], [decor_placed]
## village and home, [decor] home_wall and home_floor), the migration v5 -> v6 (the home gets the
## starter set, owned; nothing else changes; *.v5.bak), real older files (v2 legacy, v4), invalid
## entries, and DecorState (buy, place, move, put away, surfaces, snapshot). KE8b (v7): the home
## shrank to 11×7, v6 -> v7 lays its furniture out anew without losing a piece (*.v6.bak, a v6
## fixture). Uses a test save only.

const TEST_PATH := "user://test_save_decor.cfg"
const FIXTURE_V2_LEGACY := "res://tests/fixtures/save_v2_legacy.cfg"
const FIXTURE_V4_REAL := "res://tests/fixtures/save_v4_real.cfg"
const FIXTURE_V6_HOME := "res://tests/fixtures/save_v6_home_test.cfg"
const WORLD_ID := "3f0c1d5e-8a2b-4c6d-9e1f-0a1b2c3d4e5f"

var _old_path: String


func before_all() -> void:
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	_remove_files()
	SaveManager.load_game()


func after_all() -> void:
	_remove_files()
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _remove_files() -> void:
	for suffix in ["", ".bak", ".v2.bak", ".v3.bak", ".v4.bak", ".v5.bak", ".v6.bak", ".prev.bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))


func _write(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _saved() -> ConfigFile:
	assert_eq(SaveManager.save_game(), OK)
	var config := ConfigFile.new()
	assert_eq(config.load(TEST_PATH), OK)
	return config


func _v5(body := "") -> String:
	return "[meta]\nversion=5\n[progress]\npermanent_gold=500\npermanent_crystals=2\n[world]\nid=\"%s\"\nname=\"Testwelt\"\n%s\n" % [WORLD_ID, body]


# --- Fresh world ---

func test_version_is_7() -> void:
	assert_eq(SaveManager.SAVE_VERSION, 7)
	assert_eq(_saved().get_value("meta", "version"), 7)


func test_a_fresh_world_has_the_furnished_home_and_a_bare_village() -> void:
	assert_eq(SaveManager.get_decor_placements(DecorState.HOME), PackedStringArray(DecorState.STARTER_HOME))
	assert_true(SaveManager.get_decor_placements(DecorState.VILLAGE).is_empty())
	for id: String in DecorState.starter_owned():
		assert_eq(DecorState.owned_count(id), DecorState.starter_owned()[id], "%s owned" % id)
		assert_eq(DecorState.stored_count(id), 0, "%s stands, nothing in the Lager" % id)
	var config := _saved()
	assert_eq(config.get_value("decor_placed", "home"), PackedStringArray(DecorState.STARTER_HOME))
	assert_eq(config.get_value("decor_placed", "village"), PackedStringArray())
	assert_eq(config.get_value("decor", "home_wall"), "")
	assert_eq(config.get_value("decor", "home_floor"), "")


# --- One check per field ---

func test_owned_counts_are_saved() -> void:
	SaveManager.set_decor_owned("lamp_post", 3)
	assert_eq(_saved().get_value("decor_owned", "lamp_post"), 3)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(DecorState.owned_count("lamp_post"), 3)


func test_village_placements_are_saved() -> void:
	SaveManager.set_decor_owned("bush", 1)
	SaveManager.set_decor_placements(DecorState.VILLAGE, PackedStringArray(["bush:10:12:0"]))
	assert_eq(_saved().get_value("decor_placed", "village"), PackedStringArray(["bush:10:12:0"]))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(DecorState.placements(DecorState.VILLAGE)[0]["cell"], Vector2i(10, 12))


func test_home_placements_are_saved() -> void:
	SaveManager.set_decor_placements(DecorState.HOME, PackedStringArray(["chest_cozy:5:6:2"]))
	assert_eq(_saved().get_value("decor_placed", "home"), PackedStringArray(["chest_cozy:5:6:2"]))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(DecorState.placements(DecorState.HOME)[0]["rot"], 2)
	SaveManager.set_decor_placements(DecorState.HOME, PackedStringArray())
	assert_eq(_saved().get_value("decor_placed", "home"), PackedStringArray(), "an empty home stays empty")
	assert_eq(SaveManager.load_game(), OK)
	assert_true(SaveManager.get_decor_placements(DecorState.HOME).is_empty(), "no starter set again")


func test_home_wall_is_saved() -> void:
	SaveManager.set_decor_setting(DecorState.SETTING_WALL, "soul")
	assert_eq(_saved().get_value("decor", "home_wall"), "soul")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(DecorState.surface_style(DecorState.SETTING_WALL), "soul")


func test_home_floor_is_saved() -> void:
	SaveManager.set_decor_setting(DecorState.SETTING_FLOOR, "rustic")
	assert_eq(_saved().get_value("decor", "home_floor"), "rustic")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(DecorState.surface_style(DecorState.SETTING_FLOOR), "rustic")


# --- Migration v5 -> v6 ---

func test_v5_world_gets_the_starter_home() -> void:
	_write(_v5())
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_decor_placements(DecorState.HOME), PackedStringArray(DecorState.STARTER_HOME))
	assert_true(SaveManager.get_decor_placements(DecorState.VILLAGE).is_empty())
	assert_eq(DecorState.owned_count("bed_single_cozy"), 1, "starter pieces are owned")
	assert_eq(SaveManager.get_permanent_gold(), 500, "nothing else changes")
	assert_eq(SaveManager.get_permanent_crystals(), 2)
	assert_eq(SaveManager.get_world_name(), "Testwelt")
	assert_eq(SaveManager.get_world_id(), WORLD_ID)
	assert_true(FileAccess.file_exists(TEST_PATH + ".v5.bak"), "the v5 file is kept once")


func test_migrate_is_additive_and_keeps_existing_decoration() -> void:
	var config := ConfigFile.new()
	config.parse(_v5("[decor_owned]\nbush=2\n[decor_placed]\nhome=PackedStringArray(\"chest_cozy:2:3:0\")"))
	assert_eq(SaveManager.migrate(config), 5)
	assert_eq(config.get_value("meta", "version"), SaveManager.SAVE_VERSION)
	assert_eq(config.get_value("decor_placed", "home"), PackedStringArray(["chest_cozy:2:3:0"]), "an arrangement stays")
	assert_eq(config.get_value("decor_owned", "bush"), 2)
	assert_false(config.has_section_key("decor_owned", "bed_single_cozy"), "no starter set over a home that exists")
	assert_eq(config.get_value("decor_placed", "village"), PackedStringArray())


func test_real_v2_world_loads_with_the_starter_home() -> void:
	var original := FileAccess.get_file_as_string(FIXTURE_V2_LEGACY)
	assert_false(original.is_empty(), "fixture exists")
	_write(original)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_crystals(), 6, "progress kept")
	assert_eq(SaveManager.get_decor_placements(DecorState.HOME).size(), DecorState.STARTER_HOME.size())
	var config := _saved()
	assert_eq(config.get_value("meta", "version"), SaveManager.SAVE_VERSION)
	assert_eq(SaveManager.load_game(), OK, "the saved file loads again")


func test_real_v4_world_loads_with_the_starter_home() -> void:
	_write(FileAccess.get_file_as_string(FIXTURE_V4_REAL))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 13)
	assert_eq(DecorState.placements(DecorState.HOME).size(), DecorState.STARTER_HOME.size())


# --- Migration v6 -> v7 (KE8b: the smaller home) ---

func _v6(home: Array, owned := "") -> String:
	var entries := PackedStringArray()
	for entry: String in home:
		entries.append("\"%s\"" % entry)
	return "[meta]\nversion=6\n[progress]\npermanent_gold=500\n[world]\nid=\"%s\"\n[decor_owned]\n%s\n[decor_placed]\nhome=PackedStringArray(%s)\nvillage=PackedStringArray()\n" % [WORLD_ID, owned, ", ".join(entries)]


func test_untouched_v6_home_becomes_the_new_starter_home() -> void:
	_write(_v6(DecorState.STARTER_HOME_V6))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_decor_placements(DecorState.HOME), PackedStringArray(DecorState.STARTER_HOME))
	assert_eq(DecorState.owned_count("clock_cozy"), 1, "the new starter pieces are owned")
	assert_true(FileAccess.file_exists(TEST_PATH + ".v6.bak"), "the v6 file is kept once")
	var grid := DecorGrid.for_home()
	assert_eq(DecorState.fit_list(SaveManager.get_decor_placements(DecorState.HOME), grid)["stored"], PackedStringArray())


func test_v6_pieces_outside_the_new_room_go_to_the_storage() -> void:
	var home: Array = DecorState.STARTER_HOME_V6.duplicate()
	home.erase("chest_cozy:5:6:0")
	home.append("chest_cozy:7:5:0")
	home.append("sofa_rustic:10:7:0")
	_write(_v6(home, "sofa_rustic=1\nlantern_cozy=3"))
	assert_eq(SaveManager.load_game(), OK)
	var placed := SaveManager.get_decor_placements(DecorState.HOME)
	assert_true(placed.has("chest_cozy:7:5:0"), "an own place that still fits stays")
	assert_false(str(placed).contains("sofa_rustic"), "row 7 is gone: the sofa waits in the Lager")
	assert_eq(DecorState.stored_count("sofa_rustic"), 1, "nothing is lost")
	assert_eq(DecorState.stored_count("lantern_cozy"), 3, "the Lager stays")
	assert_true(placed.has("bed_single_cozy:1:2:0"), "unmoved starter pieces go to their new places")
	assert_true(placed.has("fireplace_cozy:8:2:0"))
	assert_false(str(placed).contains("clock_cozy"), "an own arrangement is not filled up")
	assert_eq(DecorState.stored_count("clock_cozy"), 1, "the new starter pieces wait in the Lager")
	assert_eq(DecorState.fit_list(placed, DecorGrid.for_home())["stored"], PackedStringArray(), "everything that stands fits")


func test_real_v6_home_fixture_loads_without_losing_a_piece() -> void:
	var original := FileAccess.get_file_as_string(FIXTURE_V6_HOME)
	assert_false(original.is_empty(), "fixture exists")
	var before := ConfigFile.new()
	assert_eq(before.parse(original), OK)
	_write(original)
	assert_eq(SaveManager.load_game(), OK)
	for id in before.get_section_keys("decor_owned"):
		assert_true(DecorCatalog.has_item(id), "fixture id %s exists" % id)
		assert_gte(DecorState.owned_count(id), int(before.get_value("decor_owned", id)), "%s still owned" % id)
	assert_eq(DecorState.stored_count("sofa_rustic"), 1, "out of the room: Lager")
	assert_eq(DecorState.stored_count("picture_flint_rustic"), 1, "beyond the back wall: Lager")
	assert_true(SaveManager.get_decor_placements(DecorState.HOME).has("lantern_cozy:2:6:0"), "fits: stays")
	assert_eq(SaveManager.get_decor_placements(DecorState.VILLAGE), PackedStringArray(["bush:2:3:0"]), "the village is untouched")
	assert_eq(DecorState.surface_style(DecorState.SETTING_WALL), "rustic")
	assert_eq(SaveManager.get_permanent_gold(), 13, "progress kept")
	assert_true(FileAccess.file_exists(TEST_PATH + ".v6.bak"))
	assert_eq(_saved().get_value("meta", "version"), 7)
	assert_eq(SaveManager.load_game(), OK, "the saved v7 file loads again")


func test_invalid_entries_are_dropped_and_owned_never_below_placed() -> void:
	_write("[meta]\nversion=6\n[progress]\npermanent_gold=5\n[decor_owned]\nbush=\"many\"\nlamp_post=-2\n" +
		"[decor_placed]\nvillage=PackedStringArray(\"bush:1:2:0\", \"nonsense\", \"bush:3\")\nhome=PackedStringArray()\n" +
		"[decor]\nhome_wall=7\n")
	assert_eq(SaveManager.load_game(), OK, "decoration is never worth a fresh start")
	assert_eq(SaveManager.get_decor_placements(DecorState.VILLAGE), PackedStringArray(["bush:1:2:0"]))
	assert_eq(DecorState.owned_count("bush"), 1, "what stands is owned")
	assert_eq(DecorState.owned_count("lamp_post"), 0)
	assert_eq(DecorState.surface_style(DecorState.SETTING_WALL), "")
	assert_eq(SaveManager.get_permanent_gold(), 5)


# --- DecorState ---

func test_buy_place_move_and_put_away() -> void:
	SaveManager.add_permanent_gold(1000)
	var item := DecorCatalog.get_item("lamp_post")
	assert_true(DecorState.buy("lamp_post"))
	assert_eq(SaveManager.get_permanent_gold(), 1000 - item.price)
	assert_eq(DecorState.stored_count("lamp_post"), 1, "into the Lager")
	assert_eq(DecorState.stored_ids(DecorState.VILLAGE), ["lamp_post"] as Array[String])
	assert_true(DecorState.place(DecorState.VILLAGE, "lamp_post", Vector2i(4, 5), 0))
	assert_eq(DecorState.stored_count("lamp_post"), 0)
	assert_false(DecorState.place(DecorState.VILLAGE, "lamp_post", Vector2i(6, 5), 0), "the Lager is empty")
	assert_true(DecorState.move(DecorState.VILLAGE, 0, Vector2i(6, 7), 2))
	assert_eq(DecorState.placements(DecorState.VILLAGE)[0]["cell"], Vector2i(6, 7))
	assert_true(DecorState.remove(DecorState.VILLAGE, 0))
	assert_eq(DecorState.stored_count("lamp_post"), 1, "back in the Lager")
	assert_eq(_saved().get_value("decor_owned", "lamp_post"), 1)


func test_buying_needs_the_gold() -> void:
	assert_eq(SaveManager.get_permanent_gold(), 0)
	assert_false(DecorState.can_buy("lamp_post"))
	assert_false(DecorState.buy("lamp_post"))
	assert_eq(DecorState.gold_missing("lamp_post"), DecorCatalog.get_item("lamp_post").price)
	assert_eq(DecorState.owned_count("lamp_post"), 0)


func test_starter_pieces_go_to_the_lager_and_back() -> void:
	var index := -1
	for entry in DecorState.placements(DecorState.HOME):
		if entry["id"] == "chest_cozy":
			index = int(entry["index"])
	assert_true(DecorState.remove(DecorState.HOME, index))
	assert_eq(DecorState.stored_count("chest_cozy"), 1)
	assert_has(DecorState.stored_ids(DecorState.HOME), "chest_cozy")
	assert_true(DecorState.place(DecorState.HOME, "chest_cozy", Vector2i(2, 7), 1))


func test_surfaces_are_bought_once_and_put_up() -> void:
	var id := DecorCatalog.surface_id(DecorCatalog.SURFACE_WALL, "soul")
	assert_false(DecorState.set_surface_style(DecorState.SETTING_WALL, "soul"), "not owned yet")
	SaveManager.add_permanent_gold(5000)
	assert_true(DecorState.buy(id))
	assert_false(DecorState.can_buy(id), "a surface is bought once")
	assert_true(DecorState.set_surface_style(DecorState.SETTING_WALL, "soul"))
	assert_eq(DecorState.surface_style(DecorState.SETTING_WALL), "soul")
	assert_true(DecorState.set_surface_style(DecorState.SETTING_WALL, ""), "back to the original room")


func test_collection_counts_owned_items() -> void:
	var before := DecorState.collection(DecorState.HOME)
	assert_eq(before.x, DecorState.starter_owned().size(), "the starter set counts")
	assert_gt(before.y, 100, "many pieces to collect")
	SaveManager.add_permanent_gold(5000)
	DecorState.buy("sofa_soul")
	assert_eq(DecorState.collection(DecorState.HOME).x, before.x + 1)
	assert_eq(DecorState.style_collection("soul").x, 1)


func test_snapshot_is_small_and_only_known_pieces_come_back() -> void:
	SaveManager.set_decor_owned("bush", 1)
	SaveManager.set_decor_placements(DecorState.VILLAGE, PackedStringArray(["bush:2:3:0"]))
	var snapshot := DecorState.snapshot()
	assert_lt(JSON.stringify(snapshot).length(), 16 * 1024, "KONZEPT §8: at most 16 KB")
	assert_eq(DecorState.snapshot_placements(snapshot, DecorState.VILLAGE), PackedStringArray(["bush:2:3:0"]))
	var foreign := {"village": ["bush:2:3:0", "unknown_thing:1:1:0", 42, "bush:x"]}
	assert_eq(DecorState.snapshot_placements(foreign, DecorState.VILLAGE), PackedStringArray(["bush:2:3:0"]))
