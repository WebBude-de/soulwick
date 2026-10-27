extends GutTest
## The way into the home and back (KE8, KONZEPT §6): the home's door opens (second state of the
## building), the WorldController loads the interior, the door out brings the players back to the
## spot in front of the home. Koop-Check: in a group session nobody goes inside, the door shows the
## talent tree read-only (no respec for guests). Uses a test save and a test account file only.

const VILLAGE_SCENE := "res://world/village/village.tscn"
const SAVE_PATH := "user://test_home_travel.cfg"
const PROGRESS_PATH := "user://test_home_travel_progress.cfg"

var _old_save_path: String
var _old_phase: GameManager.Phase


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	AccountProgress.path_override = PROGRESS_PATH
	_old_phase = GameManager.get_phase()


func before_each() -> void:
	for path in [SAVE_PATH, PROGRESS_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveManager.load_game()
	AccountProgress.reset()
	# No Flint tours over the worlds (they would open dialogs).
	AccountSeen.mark_seen(HomeInterior.EXPLANATION_ID)
	HomeTravel.reset()


func after_each() -> void:
	GameManager.clear_pause_reasons()
	HitStop.reset()
	HomeTravel.reset()


func after_all() -> void:
	GameManager.set_phase(_old_phase)
	await wait_seconds(0.3)
	for path in [SAVE_PATH, SAVE_PATH + ".bak", SAVE_PATH + ".prev.bak", PROGRESS_PATH, PROGRESS_PATH + ".prev.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## A WorldController without HUD, menus and vision, the village first.
func _controller(mode: GameMode) -> WorldController:
	var world_root := Node2D.new()
	add_child_autofree(world_root)
	var controller := WorldController.new()
	controller.world_root = world_root
	controller.village_scene = load(VILLAGE_SCENE) as PackedScene
	controller.dungeon_scene = load(VILLAGE_SCENE) as PackedScene
	controller.game_mode = mode
	add_child_autofree(controller)
	await wait_process_frames(2)
	return controller


func test_door_leads_inside_and_back_to_the_same_spot() -> void:
	var controller := await _controller(GameMode.solo())
	var village := controller.get_world() as Village
	assert_not_null(village)
	var home := village.get_node(HomeTravel.HOME_NODE) as Node2D
	var door := HomeTravel.door_point(home)
	assert_true(HomeTravel.can_enter(village))
	var entering: Array = [false]
	var go := func() -> void: entering[0] = await HomeTravel.enter(village)
	go.call()
	await wait_process_frames(1)
	assert_true(VillageBuildings.is_home_door_open(home), "the door opens first")
	assert_true(HomeTravel.is_travelling())
	await wait_seconds(HomeTravel.DOOR_OPEN_TIME + 0.15)
	assert_true(entering[0])
	var interior := controller.get_world() as HomeInterior
	assert_not_null(interior, "the interior is the world now")
	assert_eq(GameManager.get_phase(), GameManager.Phase.VILLAGE, "a peaceful world")
	var player := controller.get_player()
	assert_not_null(player)
	assert_false(player.is_armed(), "no weapon at home")
	assert_almost_eq(player.global_position.distance_to(interior.to_global(HomeLayout.to_world(HomeLayout.SPAWN_AT))), 0.0, 1.0)
	assert_true(interior.leave())
	await wait_process_frames(3)
	var back := controller.get_world() as Village
	assert_not_null(back, "back in the village")
	var player_back := controller.get_player()
	assert_almost_eq(player_back.global_position.distance_to(door + HomeTravel.DOOR_STEP), 0.0, 1.0,
		"in front of the home's door, where the player went in")
	var home_back := back.get_node(HomeTravel.HOME_NODE) as Node2D
	assert_true(VillageBuildings.is_home_door_open(home_back), "the door is open as the player comes out")
	await wait_seconds(HomeTravel.DOOR_CLOSE_DELAY + 0.2)
	assert_false(VillageBuildings.is_home_door_open(home_back), "and closes behind them")


func test_group_session_does_not_go_inside() -> void:
	var controller := await _controller(GameMode.quick(2))
	var village := controller.get_world() as Village
	assert_false(HomeTravel.can_enter(village), "co-op: each home only alone")
	assert_false(await HomeTravel.enter(village))
	assert_true(controller.get_world() is Village, "the shared village stays")


func test_group_door_shows_the_tree_read_only() -> void:
	var controller := await _controller(GameMode.quick(2))
	var village := controller.get_world() as Village
	VillageBuildings.enter_home(village)
	await wait_process_frames(2)
	var dialog := village.ui.find_child("TalentTree", true, false) as TalentTreeDialog
	assert_not_null(dialog, "the talent tree shows")
	assert_false(dialog.edit.editable, "guests only look, no respec")
	assert_false(VillageBuildings.needs_intro(VillageBuildings.HOME), "the home counts as explained")
	dialog.close()
	await wait_process_frames(1)


func test_door_states_swap_the_building_art() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	var home := village.get_node(HomeTravel.HOME_NODE) as Node2D
	var closed := (home.get_node("Sprite") as Sprite2D).texture
	assert_false(VillageBuildings.is_home_door_open(home))
	VillageBuildings.set_home_door_open(home, true)
	assert_true(VillageBuildings.is_home_door_open(home))
	assert_eq((home.get_node("Sprite") as Sprite2D).texture.get_size(), closed.get_size(), "same size as home.png")
	VillageBuildings.set_home_door_open(home, false)
	assert_eq((home.get_node("Sprite") as Sprite2D).texture, closed)


func test_home_inside_texts_exist() -> void:
	for key: Variant in [VillageBuildings.HOME_INSIDE_TEXTS["role"], VillageBuildings.HOME_INSIDE_TEXTS["prompt"]] + VillageBuildings.HOME_INSIDE_TEXTS["hints"]:
		assert_true(Loc.has_key(key, &"de") and Loc.has_key(key, &"en"), String(key))
