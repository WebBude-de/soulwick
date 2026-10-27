extends GutTest
## The home interior (KE8, D-205, Antwort 20 §1): its own scene, furnished "basic cozy" from the
## first visit, lit by the fireplace, the window, the night lamp and the altar's candles; the altar
## burns brighter while talent points are free; the mirror and the door out are there; Flint
## explains the altar once. Uses a test save and a test account file only.

const HOME_SCENE := "res://world/village/home/home.tscn"
const SAVE_PATH := "user://test_home_interior.cfg"
const PROGRESS_PATH := "user://test_home_interior_progress.cfg"

var _old_save_path: String
var _old_locale: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	AccountProgress.path_override = PROGRESS_PATH


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))
	SaveManager.load_game()
	AccountProgress.reset()
	HomeArt.clear_cache()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	for path in [SAVE_PATH, SAVE_PATH + ".bak", SAVE_PATH + ".prev.bak", PROGRESS_PATH, PROGRESS_PATH + ".prev.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _home() -> HomeInterior:
	var home := (load(HOME_SCENE) as PackedScene).instantiate() as HomeInterior
	add_child_autofree(home)
	return home


func test_scene_is_a_world_with_spawn_and_camera_limits() -> void:
	var home := _home()
	assert_not_null(home, "home.tscn has the HomeInterior script")
	var spawn := home.find_child(WorldController.PLAYER_SPAWN_NODE, false, false) as Node2D
	assert_not_null(spawn)
	assert_true(HomeLayout.room_rect().has_point(spawn.position), "spawn inside the room")
	assert_eq(home.get_camera_limits(), Rect2i(Vector2i.ZERO, Vector2i(960, 576)))
	assert_true(home.y_sort_enabled, "players sort with the furniture")
	var floor_area := HomeLayout.floor_rect()
	assert_true(floor_area.has_point(HomeLayout.SPAWN_AT), "spawn on the floor")
	# Door circle plus the player's interaction radius (player.tscn, 44 px): no prompt on arrival.
	assert_gt(spawn.position.distance_to(home.exit_door.position), HomeLayout.DOOR_USE_RADIUS * HomeLayout.SCALE + 44.0,
		"a new arrival is not standing in the door")


func test_starting_furniture_is_all_there() -> void:
	var home := _home()
	for item in HomeLayout.FURNITURE:
		var prop_name := String(item["name"])
		if bool(item.get("optional", false)) and not HomeArt.has_prop(prop_name):
			assert_null(home.get_prop(prop_name), "%s only with art" % prop_name)
			continue
		assert_not_null(home.get_prop(prop_name), "%s placed" % prop_name)
	assert_not_null(home.altar, "candle altar")
	assert_not_null(home.mirror, "mirror moved in")
	assert_not_null(home.exit_door, "door out")
	for prop_name in ["bed", "fireplace", "chest", "shelf", "rug_round", "pet_bed", "plant_pot"]:
		assert_true(HomeArt.has_prop(prop_name), "%s is delivered art" % prop_name)


func test_missing_furniture_gets_placeholders_in_the_briefed_size() -> void:
	for prop_name: String in HomeArt.PLACEHOLDER_SIZES:
		if HomeArt.has_prop(prop_name):
			continue
		var texture := HomeArt.prop_texture(prop_name)
		assert_not_null(texture, prop_name)
		assert_eq(Vector2i(texture.get_size()), HomeArt.PLACEHOLDER_SIZES[prop_name], "%s size" % prop_name)


func test_lights_follow_answer_20() -> void:
	var home := _home()
	var fire := home.lights[&"fire"]
	assert_eq(fire.color, HomeLayout.FIRE_COLOR, "fireplace is the warm main light")
	assert_almost_eq(fire.radius, 5.0 * 64.0, 0.1, "5 tiles")
	assert_gt(fire.flicker, 0.0)
	assert_almost_eq(home.lights[&"lamp"].radius, 2.0 * 64.0, 0.1, "night lamp 2 tiles")
	assert_eq(home.lights[&"lamp"].color, HomeLayout.NIGHT_LAMP_COLOR)
	assert_not_null(home.lights[&"moon"])
	assert_eq(home.altar.lights.size(), 3, "three candles in the path colours")
	assert_almost_eq(home.altar.lights[0].radius, 1.5 * 64.0, 0.1)
	assert_eq(home.altar.lights[0].color, TalentTreeArt.path_color(TalentDef.PATH_WIND))
	assert_eq(home.altar.lights[2].color, TalentTreeArt.path_color(TalentDef.PATH_SOUL))
	assert_almost_eq(home.get_darkness(), lerpf(HomeLayout.DARKNESS_DAY, HomeLayout.DARKNESS_NIGHT, home.night), 0.001)


func test_altar_burns_brighter_with_free_points() -> void:
	var home := _home()
	assert_false(home.altar.is_ready, "level 1: no point, calm candles")
	AccountProgress.current().xp = AccountProgress.xp_for_level(3)
	home.altar.refresh_from_account()
	assert_true(home.altar.is_ready, "free points: the altar burns brighter")
	assert_almost_eq(home.altar.lights[0].intensity, HomeLayout.ALTAR_LIGHT_READY, 0.001)
	assert_eq(home.altar.sprite.sprite_frames.get_frame_count(&"default"), 4, "candle_altar_ready_4f")
	home.altar.set_ready(false)
	assert_eq(home.altar.sprite.sprite_frames.get_frame_count(&"default"), 6, "candle_altar_idle_6f")


func test_altar_opens_the_talent_tree_and_refreshes() -> void:
	AccountProgress.current().xp = AccountProgress.xp_for_level(3)
	var home := _home()
	home.open_talent_tree()
	await get_tree().process_frame
	var dialog := home.ui.find_child("TalentTree", true, false) as TalentTreeDialog
	assert_not_null(dialog, "the tree opens on the home's dialog layer")
	assert_true(home.is_dialog_open())
	assert_true(dialog.edit.editable, "alone at home the tree is editable")
	assert_eq(dialog.get_points_text(), "Talentpunkte: 2")
	dialog.close()
	await get_tree().process_frame
	assert_false(home.is_dialog_open())


func test_mirror_opens_the_profile_editor() -> void:
	var home := _home()
	home.open_mirror()
	await get_tree().process_frame
	var modal := home.ui.find_child("MirrorModal", true, false) as Modal
	assert_not_null(modal)
	assert_not_null(modal.find_child("*", true, false))
	assert_true(modal.find_children("*", "ProfileEditor", true, false).size() == 1, "the profile editor")
	modal.finish()
	await get_tree().process_frame
	assert_false(home.is_dialog_open())


func test_flint_explains_the_altar_once() -> void:
	var home := _home()
	var explanation := home.first_visit_explanation()
	assert_true(explanation.is_valid(), str(explanation.problems()))
	assert_eq(explanation.id, HomeInterior.EXPLANATION_ID)
	assert_eq(explanation.style, FlintExplanation.Style.TOUR)
	assert_true(explanation.once)
	assert_eq(explanation.steps[1].focus_node, home.altar, "the camera shows the altar")
	assert_eq(explanation.steps[-1].focus_node, home.mirror, "and the mirror")
	for step in explanation.steps:
		assert_true(String(step.text_key).begins_with("FLINT_HOME_"))
		assert_true(Loc.has_key(step.text_key, &"de") and Loc.has_key(step.text_key, &"en"), String(step.text_key))


func test_moon_dust_stays_in_the_shaft() -> void:
	var beam := HomeMoonBeam.new()
	add_child_autofree(beam)
	var box := Rect2(HomeMoonBeam.TOP_LEFT, Vector2.ZERO).expand(HomeMoonBeam.BOTTOM_RIGHT).expand(HomeMoonBeam.BOTTOM_LEFT).grow(1)
	for t in [0.0, 3.3, 12.7, 40.0]:
		for index in HomeMoonBeam.DUST_COUNT:
			assert_true(box.has_point(beam.dust_position(index, t)), "mote %d at %s" % [index, t])
	beam.set_night(0.0)
	assert_eq(beam.colour, HomeLayout.SUN_COLOR, "by day the sun shines in")


func test_texts_exist() -> void:
	for key in [&"HOME_EXIT_PROMPT", &"HOME_ALTAR_PROMPT", &"VILLAGE_HOME_INSIDE_ENTER", &"VILLAGE_HOME_INSIDE_ROLE"]:
		assert_true(Loc.has_key(key, &"de") and Loc.has_key(key, &"en"), String(key))
	var home := _home()
	assert_eq(home.exit_door.prompt, "Nach draußen")
	assert_eq(home.altar.door.prompt, "Kerzen-Altar · Talente")
