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
	assert_eq(home.get_camera_limits(), Rect2i(Vector2i.ZERO, Vector2i(704, 448)), "KE8b: 11×7 tiles")
	assert_true(home.y_sort_enabled, "players sort with the furniture")
	var floor_area := HomeLayout.floor_rect()
	assert_true(floor_area.has_point(HomeLayout.SPAWN_AT), "spawn on the floor")
	# Door circle plus the player's interaction radius (player.tscn, 44 px): no prompt on arrival.
	assert_gt(spawn.position.distance_to(home.exit_door.position), HomeLayout.DOOR_USE_RADIUS * HomeLayout.SCALE + 44.0,
		"a new arrival is not standing in the door")


func test_starting_furniture_is_all_there() -> void:
	var home := _home()
	# WK7: the starter set is catalog furniture of the save (DecorState.STARTER_HOME).
	assert_not_null(home.furniture, "furniture layer")
	assert_eq(home.furniture.get_pieces().size(), DecorState.STARTER_HOME.size(), "every starter piece stands")
	for entry in DecorState.STARTER_HOME:
		assert_true(DecorCatalog.has_item(String(DecorState.parse(entry)["id"])), "%s is in the catalog" % entry)
	for prop_name in ["broom"]:
		assert_not_null(home.get_prop(prop_name), "%s stays a fixed prop" % prop_name)
	assert_not_null(home.altar, "candle altar")
	assert_not_null(home.mirror, "mirror moved in")
	assert_not_null(home.exit_door, "door out")
	assert_not_null(home.decor_station, "catalog stand by the door")


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
	assert_eq(home.window_lights.size(), HomeLayout.WINDOW_COLS.size(), "a light under every window")


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
	assert_eq(explanation.steps[-1].focus_node, home.mirror, "and the mirror (KE8b: the stand has its own hint)")
	for step in explanation.steps:
		assert_true(String(step.text_key).begins_with("FLINT_HOME_"))
		assert_true(Loc.has_key(step.text_key, &"de") and Loc.has_key(step.text_key, &"en"), String(step.text_key))


func test_moon_dust_stays_in_the_shaft() -> void:
	var beam := HomeMoonBeam.create(HomeLayout.WINDOW_COLS[0])
	add_child_autofree(beam)
	var box := Rect2(HomeMoonBeam.TOP_LEFT, Vector2.ZERO).expand(HomeMoonBeam.BOTTOM_RIGHT).expand(HomeMoonBeam.BOTTOM_LEFT).grow(1)
	for t in [0.0, 3.3, 12.7, 40.0]:
		for index in HomeMoonBeam.DUST_COUNT:
			assert_true(box.has_point(beam.dust_position(index, t)), "mote %d at %s" % [index, t])
	beam.set_night(0.0)
	assert_eq(beam.colour, HomeLayout.SUN_COLOR, "by day the sun shines in")


# --- KE8b: the view outside follows the clock ---

func test_ke8b_three_windows_in_the_back_wall() -> void:
	var home := _home()
	assert_eq(home.room.windows.size(), 3, "TESTWERT: three windows")
	assert_eq(home.beams.size(), 3, "a light shaft under every window")
	for window in home.room.windows:
		assert_true(HomeLayout.WINDOW_COLS.has(window.col))
		assert_lt(window.position.y, float(HomeLayout.WALL_ROWS * HomeLayout.TILE), "in the back wall")


func test_ke8b_the_view_follows_the_village_clock() -> void:
	# The same curve as the village (VillageDaylight): noon is day, 18:45 dusk, 23:00 night.
	assert_eq(HomeWindow.phase_for(VillageDaylight.night_amount(12.0)), HomeWindow.Phase.DAY)
	assert_eq(HomeWindow.phase_for(VillageDaylight.night_amount(18.75)), HomeWindow.Phase.DUSK)
	assert_eq(HomeWindow.phase_for(VillageDaylight.night_amount(23.0)), HomeWindow.Phase.NIGHT)
	assert_eq(HomeWindow.phase_for(VillageDaylight.night_amount(6.0)), HomeWindow.Phase.DUSK, "dawn")
	var home := _home()
	assert_almost_eq(home.night, VillageDaylight.night_amount(VillageDaylight.current_hour()), 0.01, "starts with the clock")
	home.pin_night(0.0)
	assert_eq(home.room.windows[0].get_phase(), HomeWindow.Phase.DAY)
	assert_eq(home.moon_beam.colour, HomeLayout.SUN_COLOR, "the sun shines in by day")
	assert_eq(home.lights[&"moon"].color, HomeLayout.SUN_COLOR)
	assert_eq(home.get_dark_color(), HomeLayout.DARK_COLOR_DAY, "a warm shade by day, not the night blue")
	assert_lt(home.get_darkness(), 0.2, "bright by day")
	home.pin_night(1.0)
	assert_eq(home.room.windows[0].get_phase(), HomeWindow.Phase.NIGHT)
	assert_eq(home.moon_beam.colour, HomeLayout.MOON_COLOR, "the moon at night")
	assert_eq(home.get_dark_color(), HomeLayout.DARK_COLOR)
	assert_gt(home.get_darkness(), 0.5)
	home.pin_night(0.55)
	assert_eq(home.room.windows[0].get_phase(), HomeWindow.Phase.DUSK)


func test_ke8b_day_sky_is_blue_and_night_sky_is_dark() -> void:
	var window := HomeWindow.create(HomeLayout.WINDOW_COLS[0])
	add_child_autofree(window)
	var day := window.build_image(0.0, 0.0)
	var night := window.build_image(1.0, 0.0)
	var glass := HomeWindow.glass_mask().get_used_rect()
	assert_true(glass.has_area(), "the glass is found in the delivered window pictures")
	var top := glass.position + Vector2i(1, 1)
	var sky_day := day.get_pixelv(top)
	var sky_night := night.get_pixelv(top)
	assert_gt(sky_day.b, sky_day.r, "blue sky by day")
	assert_gt(sky_day.get_luminance(), 0.45, "a bright sky by day")
	assert_lt(sky_night.get_luminance(), 0.2, "a dark sky at night")
	var frame := HomeWindow.frame_image()
	var frame_pixel := frame.get_used_rect().position + Vector2i(floori(frame.get_used_rect().size.x * 0.5), 0)
	assert_eq(day.get_pixelv(frame_pixel), night.get_pixelv(frame_pixel), "the frame stays")


func test_ke8b_every_window_colour_is_a_hard_pixel() -> void:
	var window := HomeWindow.create(HomeWindow.middle_col(), true)
	add_child_autofree(window)
	for amount in [0.0, 0.5, 1.0]:
		var image := window.build_image(amount, 7.0)
		for y in image.get_height():
			for x in image.get_width():
				var alpha := image.get_pixel(x, y).a
				assert_true(alpha == 0.0 or alpha == 1.0, "no soft edge (D-218) at %d,%d" % [x, y])
				if alpha != 0.0 and alpha != 1.0:
					return


func test_ke8b_the_doorway_is_open_with_a_mat() -> void:
	var gap := HomeRoom.door_gap()
	var mat := HomeRoom.door_mat_rect()
	assert_almost_eq(gap.get_center().x, HomeLayout.DOOR_AT.x, 0.01, "the opening is the door")
	assert_lt(mat.end.y, gap.position.y, "the mat lies in front of the opening")
	assert_true(HomeLayout.floor_rect().encloses(mat.grow(-1)), "on the floor")
	var home := _home()
	home.pin_night(0.0)
	var day := home.room.outside_color()
	home.pin_night(1.0)
	assert_gt(day.get_luminance(), home.room.outside_color().get_luminance(), "bright outside by day")


func test_ke8b_the_front_wall_lies_over_the_furniture() -> void:
	var home := _home()
	var wall := home.room.front_wall
	assert_not_null(wall, "the front wall is its own layer")
	assert_false(wall.z_as_relative)
	var chest := DecorCatalog.get_item("chest_cozy")
	var cell := Vector2i(8, HomeLayout.ROWS - 1)
	SaveManager.set_decor_owned("chest_cozy", 2)
	DecorState.place(DecorState.HOME, "chest_cozy", cell, 0)
	home.furniture.rebuild()
	var piece: DecorPiece = null
	for each in home.furniture.get_pieces():
		if each.item == chest and each.cell == cell:
			piece = each
	assert_not_null(piece, "a piece may stand in the last row")
	assert_gt(wall.z_index, piece.z_index, "and it stands behind the front wall, not on it")
	assert_gt(wall.z_index, HomeRoom.Z, "the wall is over the floor")
	assert_lt(wall.z_index, 40, "the decorating mode stays on top")


func test_ke8b_no_starter_piece_stands_half_behind_the_front_wall() -> void:
	for entry in DecorState.parse_list(PackedStringArray(DecorState.STARTER_HOME)):
		var item := DecorCatalog.get_item(String(entry["id"]))
		if item.is_wall() or item.is_flat():
			continue
		for cell in DecorGrid.cells_of(item, entry["cell"], int(entry["rot"])):
			assert_lt(cell.y, HomeLayout.ROWS - 1, "%s is not in the last row" % entry["id"])


func test_texts_exist() -> void:
	for key in [&"HOME_EXIT_PROMPT", &"HOME_ALTAR_PROMPT", &"VILLAGE_HOME_INSIDE_ENTER", &"VILLAGE_HOME_INSIDE_ROLE"]:
		assert_true(Loc.has_key(key, &"de") and Loc.has_key(key, &"en"), String(key))
	var home := _home()
	assert_eq(home.exit_door.prompt, "Nach draußen")
	assert_eq(home.altar.door.prompt, "Kerzen-Altar · Talente")
