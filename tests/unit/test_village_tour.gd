extends GutTest
## WK9 (KONZEPT §7.2): Flint's village tour on the first start of an account: greeting, a camera
## ride over dungeon entrance, forge, trading post, home, chronicle and guild with one sentence each
## (the locked buildings say when they open), goodbye; a ring marks the station he talks about; once
## per account; only for local players, only their own camera, nothing pauses (a guest in the host's
## village gets his own tour). Also: every FLINT_VILLAGE_* text in two languages fits Flint's bubble,
## and the bubble's tail never lies across the text (report #94669ed6). Test folder only
## (SaveManager.set_storage_root), never the real save or progress.cfg.

const ROOT := "user://test_village_tour"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DT := 1.0 / 60.0

var _old_locale: String
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	OnlineMenu.login_on_open = false
	_old_locale = TranslationServer.get_locale()
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	Loc.apply(&"de")
	VillageTour.force_in_scripts = true


func after_each() -> void:
	VillageTour.force_in_scripts = false
	GameManager.clear_pause_reasons()


func after_all() -> void:
	OnlineMenu.login_on_open = true
	_wipe()
	AccountProgress.path_override = ""
	AccountProgress.reset()
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


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


## A player in the village at the spawn; its guide is stepped by hand (with_view: the corner too).
func _player(village: Village, local := true, with_view := false) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = local
	village.add_child(player)
	var spawn := village.find_child("PlayerSpawn", true, false) as Node2D
	player.global_position = spawn.global_position
	if local:
		var guide := FlintGuide.for_player(player)
		guide.set_process(false)
		guide.shows_view = with_view
	return player


func _run(guide: FlintGuide, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		guide.advance(DT)
		left -= DT


## Into the next sentence: past the grace time, show all, go on.
func _next(guide: FlintGuide) -> void:
	_run(guide, FlintGuideRules.PRESS_GRACE + DT)
	guide.press()
	_run(guide, FlintGuideRules.PRESS_DEBOUNCE + DT)
	guide.press()


func _talk_through(guide: FlintGuide) -> bool:
	for i in 3600:
		if guide.phase == FlintGuide.Phase.IDLE:
			return true
		guide.advance(DT)
		if guide.phase == FlintGuide.Phase.TALK:
			guide.press()
	return guide.phase == FlintGuide.Phase.IDLE


func _tour_of(village: Village) -> VillageTour:
	return village.get_node_or_null(^"VillageTour") as VillageTour


# --- What Flint says ---

func test_the_tour_visits_the_six_stations_in_order() -> void:
	var village := _village()
	var tour := VillageTour.build_tour(village)
	assert_true(tour.is_valid(), "%s" % [tour.problems()])
	assert_eq(tour.id, VillageTour.TOUR_ID)
	assert_eq(tour.style, FlintExplanation.Style.TOUR, "camera, lock, 'Weiter'")
	assert_true(tour.once, "once per account")
	assert_eq(tour.max_pan_distance, 0.0, "the whole village")
	assert_eq(tour.steps.size(), VillageTour.STATIONS.size() + 2, "greeting, six stations, goodbye")
	assert_eq(tour.steps[0].text_key, VillageTour.WELCOME_KEY)
	assert_false(tour.steps[0].wants_camera(), "the greeting stays with the player")
	assert_eq(tour.steps[tour.steps.size() - 1].text_key, VillageTour.DONE_KEY)
	var expected_nodes := [^"Buildings/DungeonEntrance", ^"Buildings/Forge", ^"Buildings/TradingPost",
		^"Buildings/Home", ^"Buildings/Chronicle", ^"Buildings/Guild"]
	for i in VillageTour.STATIONS.size():
		var step := tour.steps[i + 1]
		assert_eq(step.focus_node, village.get_node(expected_nodes[i]), "station %d: %s" % [i, expected_nodes[i]])
		assert_eq(step.mood, FlintGuideStep.Mood.POINT, "Flint points")
	# A fresh world: chronicle (first run) and trading post (first crystal) are still closed.
	assert_eq(tour.steps[3].text_key, &"FLINT_VILLAGE_TRADER_LOCKED")
	assert_eq(tour.steps[5].text_key, &"FLINT_VILLAGE_CHRONICLE_LOCKED")
	assert_eq(tour.steps[2].text_key, &"FLINT_VILLAGE_FORGE")
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_RUN)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_CRYSTAL)
	var open := VillageTour.build_tour(village)
	assert_eq(open.steps[3].text_key, &"FLINT_VILLAGE_TRADER", "open: what it is for")
	assert_eq(open.steps[5].text_key, &"FLINT_VILLAGE_CHRONICLE")


func test_the_forge_sentence_is_the_one_from_the_concept() -> void:
	assert_eq(Loc.t(&"FLINT_VILLAGE_FORGE"), "Das ist die Schmiede. Hier machst du deine Waffen stärker – mit Gold aus dem Dungeon.")


func test_every_village_text_is_translated_and_fits_two_lines() -> void:
	var keys: Array[StringName] = [VillageTour.WELCOME_KEY, VillageTour.DONE_KEY]
	for station in VillageTour.STATION_TEXTS:
		for key: StringName in VillageTour.STATION_TEXTS[station]:
			if key != &"":
				keys.append(key)
	for building in VillageTour.BUILDING_TEXTS:
		for key: StringName in VillageTour.BUILDING_TEXTS[building]:
			keys.append(key)
	assert_eq(keys.size(), 18)
	var translations := Loc.load_csv(Loc.CSV_PATH)
	var font := UiKit.get_font()
	var width := UiKit.px(FlintGuideView.BUBBLE_WIDTH)
	var size := UiKit.font_px(FlintGuideView.TEXT_SIZE)
	for key in keys:
		assert_true(String(key).begins_with("FLINT_VILLAGE_"), String(key))
		for language: StringName in Loc.LANGUAGES:
			var text := String((translations[language] as Translation).get_message(key))
			assert_false(text.is_empty() or text == String(key), "%s has %s" % [key, language])
			assert_lte(FlintGuideRules.line_count(text, font, size, width), FlintGuideRules.MAX_LINES,
					"%s (%s) fits two lines: %s" % [key, language, text])


# --- The tour ---

func test_the_village_offers_the_tour_to_its_local_player() -> void:
	var village := _village()
	var player := _player(village)
	village.on_player_spawned(player)
	var guide := FlintGuide.of(player)
	assert_true(guide.is_running(), "first start: Flint shows the village")
	assert_eq(guide.current.id, VillageTour.TOUR_ID)
	assert_true(player.is_protected(), "the listener stands still and is safe (D-123)")
	assert_false(get_tree().paused, "nothing pauses (D-085)")
	assert_false(GameManager.is_game_paused(), "no pause reason either")
	assert_false(village.ui.is_dialog_open(), "no dialog, no card")
	assert_not_null(_tour_of(village), "the station marker")


func test_the_camera_flies_to_each_station_and_home() -> void:
	var village := _village()
	var player := _player(village)
	assert_true(VillageTour.offer(player, village))
	var guide := FlintGuide.of(player)
	var camera := guide.get_camera()
	assert_not_null(camera, "the player's own camera rides along")
	_run(guide, FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)
	assert_eq(guide.step_index, 0, "the greeting")
	assert_false(camera.is_away(), "still at the player")
	assert_null(_tour_of(village).get_focus(), "no station marked yet")
	var expected := [
		village.get_node(^"Buildings/DungeonEntrance").global_position + VillageTour.ENTRANCE_FOCUS_OFFSET,
		village.get_node(^"Buildings/Forge").global_position + VillageTour.BUILDING_FOCUS_OFFSET,
		village.get_node(^"Buildings/TradingPost").global_position + VillageTour.BUILDING_FOCUS_OFFSET,
		village.get_node(^"Buildings/Home").global_position + VillageTour.BUILDING_FOCUS_OFFSET,
		village.get_node(^"Buildings/Chronicle").global_position + VillageTour.BUILDING_FOCUS_OFFSET,
		village.get_node(^"Buildings/Guild").global_position + VillageTour.BUILDING_FOCUS_OFFSET,
	]
	for i in expected.size():
		_next(guide)
		assert_eq(guide.step_index, i + 1)
		assert_true(camera.is_away(), "station %d: the camera is there" % i)
		assert_almost_eq(camera.get_target(), (expected[i] as Vector2) - player.global_position, Vector2.ONE, "station %d" % i)
		assert_eq(_tour_of(village).get_focus(), guide.get_step().focus_node, "station %d marked" % i)
	_next(guide)
	assert_eq(guide.get_step().text_key, VillageTour.DONE_KEY)
	assert_false(camera.is_away(), "back at the player for the goodbye")
	assert_true(_talk_through(guide))
	assert_true(AccountSeen.has_seen(VillageTour.TOUR_ID), "seen for the account")
	assert_false(player.is_protected(), "free again")
	await wait_physics_frames(2)
	assert_null(_tour_of(village), "the marker is gone")


func test_once_per_account_even_in_a_new_world() -> void:
	var village := _village()
	var player := _player(village)
	assert_true(VillageTour.offer(player, village))
	var guide := FlintGuide.of(player)
	_run(guide, FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)
	assert_true(guide.skip(), "Überspringen counts as seen")
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_true(AccountSeen.has_seen(VillageTour.TOUR_ID))
	assert_false(VillageTour.offer(player, village), "not again")
	SaveManager.save_path = SaveManager.slot_path(2)
	SaveManager.load_game()
	var other := _village()
	var newcomer := _player(other)
	other.on_player_spawned(newcomer)
	assert_false(FlintGuide.of(newcomer).is_running(), "a new world of the same account: no second tour")


func test_old_worlds_get_the_tour_once_too() -> void:
	# A v2 save counts as "everything seen" (D-087) - except Flint's explanations (new content).
	var file := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	file.store_string("[meta]\nversion=2\n[progress]\npermanent_gold=5\n[stats]\nruns=3\n")
	file.close()
	assert_eq(SaveManager.load_game(), OK)
	var village := _village()
	var player := _player(village)
	village.on_player_spawned(player)
	assert_true(FlintGuide.of(player).is_running(), "the new tour shows once")
	var tour := FlintGuide.of(player).current
	assert_eq(tour.steps[3].text_key, &"FLINT_VILLAGE_TRADER", "old save: everything open")
	assert_eq(tour.steps[5].text_key, &"FLINT_VILLAGE_CHRONICLE")


func test_script_runs_get_no_tour_unless_forced() -> void:
	VillageTour.force_in_scripts = false
	var village := _village()
	var player := _player(village)
	village.on_player_spawned(player)
	assert_false(FlintGuide.of(player).is_running(), "tests and tools are not held up")


func test_coop_only_the_local_player_gets_the_tour() -> void:
	var village := _village()
	var guest := _player(village)
	var host_copy := _player(village, false)
	var host_camera := host_copy.get_node("Camera2D") as Camera2D
	var host_camera_before := host_camera.position
	village.on_player_spawned(host_copy)
	village.on_player_spawned(guest)
	assert_null(FlintGuide.of(host_copy), "the remote copy gets nothing on this machine")
	var guide := FlintGuide.of(guest)
	assert_true(guide.is_running(), "the guest of this machine gets his own tour")
	_run(guide, FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)
	_next(guide)
	_run(guide, FlintGuideRules.CAMERA_PAN_TIME)
	assert_eq(host_camera.position, host_camera_before, "nobody else's camera moves")
	assert_false(host_copy.is_protected(), "the others play on")
	assert_false(get_tree().paused)
	assert_false(GameManager.is_game_paused())


func test_the_tour_waits_behind_nothing_and_hints_queue_behind_it() -> void:
	var village := _village()
	var player := _player(village)
	village.on_player_spawned(player)
	var guide := FlintGuide.of(player)
	assert_true(FlintExplanations.talent_point(player), "a first-time hint arriving now")
	assert_eq(guide.current.id, VillageTour.TOUR_ID, "the tour comes first")
	assert_eq(guide.get_queue_size(), 1, "the hint waits")


# --- Report #94669ed6: the black stroke over Flint's bubble ---

func test_the_bubble_tail_does_not_cross_the_text_in_the_village() -> void:
	if FlintPortraitArt.texture(FlintPortraitArt.BUBBLE_TAIL_FILE) == null:
		pass_test("no delivered tail")
		return
	var village := _village()
	var player := _player(village, true, true)
	assert_true(VillageTour.offer(player, village))
	var guide := FlintGuide.of(player)
	_run(guide, FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)
	await wait_seconds(FlintGuideView.POP_TIME + 0.1)
	var view := guide.get_view() as FlintGuideView
	assert_not_null(view)
	var tail := view.get_bubble_tail()
	assert_not_null(tail)
	assert_ne(tail.get_parent(), view.get_bubble(), "the panel does not stretch it over the text")
	var text := view.get_speech().get_global_rect()
	assert_false(text.intersects(tail.get_global_rect()), "the tail stays out of the text (#94669ed6)")
	assert_lte(tail.size.x, UiKit.art_px(FlintGuideView.TAIL_SIZE, 8.0) + 1.0, "8x8 art, not a long stroke")
