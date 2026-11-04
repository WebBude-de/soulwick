extends GutTest
## Furnishing the home (WK7, D-202, D-205): the starter set is catalog furniture of the save, the
## catalog stand by the door opens the decorating mode, furniture is moved, turned (side view,
## mirrored), put away and bought in the catalog (Lager and shop with style filter), wallpaper and
## floor are bought and put up; nobody walls himself in. Uses a test save and a test account only.

const HOME_SCENE := "res://world/village/home/home.tscn"
const SAVE_PATH := "user://test_home_decor.cfg"
const PROGRESS_PATH := "user://test_home_decor_progress.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String
var _old_locale: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	AccountProgress.path_override = PROGRESS_PATH


func before_each() -> void:
	for path in [SAVE_PATH, PROGRESS_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveManager.load_game()
	AccountProgress.reset()


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


func _player(at: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.input = RemoteInput.new()
	player.is_local = false
	add_child_autofree(player)
	player.global_position = at
	return player


func _index_of(id: String) -> int:
	for entry in DecorState.placements(DecorState.HOME):
		if entry["id"] == id:
			return int(entry["index"])
	return -1


func _cell_of(id: String) -> Vector2i:
	for entry in DecorState.placements(DecorState.HOME):
		if entry["id"] == id:
			return entry["cell"]
	return Vector2i(-1, -1)


func test_the_starter_set_stands_with_lights_and_solids() -> void:
	var home := _home()
	var pieces := home.furniture.get_pieces()
	assert_eq(pieces.size(), DecorState.STARTER_HOME.size())
	var fireplace := home.furniture.get_piece(_index_of("fireplace_cozy"))
	assert_not_null(fireplace)
	assert_not_null(fireplace.get_node_or_null(^"Visual/Anim"), "fire strip over the fireplace")
	assert_eq(home.lights[&"fire"], fireplace.light, "the fireplace is the main light")
	assert_not_null(home.furniture.get_piece(_index_of("bed_single_cozy")).get_solid(), "the bed blocks")
	assert_null(home.furniture.get_piece(_index_of("rug_round_cozy")).get_solid(), "walk over the rug")
	assert_eq(home.furniture.get_piece(_index_of("rug_round_cozy")).z_index, HomeRoom.Z + 1, "the rug lies on the floor")
	assert_true(home.furniture.get_piece(_index_of("armchair_cozy")).is_mirrored(), "rot 3: side view mirrored")


func test_the_stand_opens_the_decorating_mode_alone() -> void:
	var home := _home()
	assert_eq(home.decor_station.door.prompt, "Einrichten")
	var player := _player(HomeLayout.to_world(HomeLayout.SPAWN_AT))
	var editor := home.open_decor_editor(player)
	assert_not_null(editor)
	assert_true(home.is_dialog_open(), "the home counts it as open")
	assert_eq(editor.space, DecorCatalog.HOME)
	editor.close()
	assert_false(home.is_decorating())


func test_move_turn_and_put_away_furniture() -> void:
	var home := _home()
	var player := _player(HomeLayout.to_world(HomeLayout.SPAWN_AT))
	var editor := home.open_decor_editor(player)
	editor.set_cursor(_cell_of("chest_cozy"))
	editor.primary()
	assert_eq(String(editor.held.get("id", "")), "chest_cozy", "picked up")
	assert_false(home.furniture.get_piece(int(editor.held["from"])).visible, "the old place shows empty")
	editor.set_cursor(Vector2i(8, 5))
	editor.turn()
	assert_true(editor.place_held())
	assert_eq(_cell_of("chest_cozy"), Vector2i(8, 5), "moved and saved")
	assert_eq(DecorState.placements(DecorState.HOME)[_index_of("chest_cozy")]["rot"], 1, "turned to the side")
	editor.set_cursor(Vector2i(8, 5))
	editor.store()
	assert_eq(_index_of("chest_cozy"), -1)
	assert_eq(DecorState.stored_count("chest_cozy"), 1, "in the Lager")
	editor.close()


func test_walling_in_a_corner_is_refused() -> void:
	var home := _home()
	var player := _player(HomeLayout.to_world(HomeLayout.SPAWN_AT))
	SaveManager.set_decor_placements(DecorState.HOME, PackedStringArray(["chest_cozy:1:6:0"]))
	SaveManager.set_decor_owned("chest_rustic", 1)
	var editor := home.open_decor_editor(player)
	editor.hold_from_storage("chest_rustic")
	editor.set_cursor(Vector2i(0, 5))
	assert_false(editor.place_held())
	assert_eq(editor.reason, DecorGrid.REASON_WAY)
	editor.close()


func test_wallpaper_and_floor_change_the_room() -> void:
	var home := _home()
	assert_null(HomeArt.style_texture("wall", ""), "the original room")
	assert_not_null(HomeArt.style_texture("wall", "soul"), "V13e wallpaper delivered")
	assert_not_null(HomeArt.style_texture("floor", "rustic"), "V13e floor delivered")
	SaveManager.add_permanent_gold(5000)
	assert_true(DecorState.buy(DecorCatalog.surface_id("floor", "rustic")))
	assert_true(DecorState.set_surface_style(DecorState.SETTING_FLOOR, "rustic"))
	assert_eq(DecorState.surface_style(DecorState.SETTING_FLOOR), "rustic")
	assert_not_null(home.room)


func test_the_catalog_buys_into_the_hand() -> void:
	var result: Array = []
	SaveManager.add_permanent_gold(1000)
	var open := func() -> void: result.append(await DecorCatalogDialog.open(self, DecorCatalog.HOME))
	open.call()
	var modal := find_child("DecorCatalogModal", true, false) as Modal
	assert_not_null(modal, "the catalog is open")
	var seating := modal.find_child("Tab_seating", true, false) as Button
	assert_not_null(seating)
	seating.pressed.emit()
	var soul := modal.find_child("Style_soul", true, false) as Button
	soul.pressed.emit()
	assert_null(modal.find_child("Card_armchair_cozy", true, false), "filtered to the soul style")
	var card := modal.find_child("Card_armchair_soul", true, false) as Button
	assert_not_null(card)
	assert_false(card.disabled, "affordable")
	card.pressed.emit()
	await wait_process_frames(2)
	assert_eq(result, ["armchair_soul"], "bought and held")
	assert_eq(DecorState.stored_count("armchair_soul"), 1)
	assert_eq(SaveManager.get_permanent_gold(), 1000 - DecorCatalog.get_item("armchair_soul").price)


func test_the_catalog_opens_on_the_lager_and_lists_stored_pieces() -> void:
	DecorState.remove(DecorState.HOME, _index_of("chest_cozy"))
	var result: Array = []
	var open := func() -> void: result.append(await DecorCatalogDialog.open(self, DecorCatalog.HOME))
	open.call()
	var modal := find_child("DecorCatalogModal", true, false) as Modal
	var card := modal.find_child("Card_chest_cozy", true, false) as Button
	assert_not_null(card, "the chest waits in the Lager")
	assert_eq((card.find_child("Line", true, false) as Label).text, "Im Lager: 1")
	card.pressed.emit()
	await wait_process_frames(2)
	assert_eq(result, ["chest_cozy"])


func test_a_card_without_gold_is_disabled() -> void:
	var open := func() -> void: await DecorCatalogDialog.open(self, DecorCatalog.VILLAGE)
	open.call()
	var modal := find_child("DecorCatalogModal", true, false) as Modal
	var first := DecorCatalog.groups_for(DecorCatalog.VILLAGE)[0]
	assert_true((modal.find_child("Tab_%s" % first, true, false) as Button).disabled, "an empty Lager opens on the first group")
	(modal.find_child("Tab_water", true, false) as Button).pressed.emit()
	var card := modal.find_child("Card_pond_small", true, false) as Button
	assert_true(card.disabled)
	assert_string_contains((card.find_child("Line", true, false) as Label).text, "Noch")
	modal.finish("")
	await wait_process_frames(1)


# --- KE8b: the decorating corner is easy to find ---

func test_ke8b_the_stand_waits_by_the_door_with_an_arrow_until_used() -> void:
	var home := _home()
	var station := HomeLayout.to_world(HomeLayout.DECOR_STATION_AT)
	var door := HomeLayout.to_world(HomeLayout.DOOR_USE_AT)
	assert_lt(station.distance_to(door), HomeLayout.tiles_to_world(1.5), "the stand stands beside the doorway")
	assert_lt(station.distance_to(HomeLayout.to_world(HomeLayout.SPAWN_AT)), HomeLayout.tiles_to_world(2.0), "in view on arrival")
	assert_true(home.decor_station.attention, "a new player sees the arrow")
	assert_true(home.decor_station.door.enabled, "alone the stand works")
	var player := _player(HomeLayout.to_world(HomeLayout.SPAWN_AT))
	var editor := home.open_decor_editor(player)
	assert_not_null(editor)
	assert_false(home.decor_station.attention, "used once: no arrow any more")
	assert_true(AccountSeen.has_seen(HomeInterior.OPENED_ID), "remembered per account")
	editor.close()
	var again := _home()
	assert_false(again.decor_station.attention, "not on the next visit either")


func test_ke8b_the_stand_opens_by_interacting_like_any_door() -> void:
	var home := _home()
	var player := _player(HomeLayout.to_world(HomeLayout.SPAWN_AT))
	home.decor_station.door.interact(player)
	assert_true(home.is_decorating(), "E (X, a tap) at the stand opens the decorating mode")
	home.get_decor_editor().close()


func test_ke8b_flint_points_at_the_stand_on_its_own() -> void:
	var home := _home()
	var hint := home.decor_hint()
	assert_true(hint.is_valid(), str(hint.problems()))
	assert_eq(hint.id, HomeInterior.DECOR_HINT_ID)
	assert_ne(hint.id, HomeInterior.EXPLANATION_ID, "not hidden inside the altar tour (seen before WK7)")
	assert_eq(hint.steps[0].focus_node, home.decor_station)
	assert_true(Loc.has_key(hint.steps[0].text_key, &"de") and Loc.has_key(hint.steps[0].text_key, &"en"))
	assert_true(SaveManager.is_excluded_from_seen_all(HomeInterior.DECOR_HINT_ID), "old accounts get it too")


func test_ke8b_pieces_that_do_not_fit_go_to_the_storage() -> void:
	SaveManager.set_decor_owned("chest_rustic", 1)
	var list := PackedStringArray(DecorState.STARTER_HOME)
	list.append("chest_rustic:13:7:0")
	SaveManager.set_decor_placements(DecorState.HOME, list)
	var home := _home()
	assert_eq(home.furniture.get_pieces().size(), DecorState.STARTER_HOME.size(), "the piece outside the room is not shown")
	assert_eq(DecorState.placements(DecorState.HOME).size(), DecorState.STARTER_HOME.size())
	assert_eq(DecorState.stored_count("chest_rustic"), 1, "in the Lager, nothing lost")
