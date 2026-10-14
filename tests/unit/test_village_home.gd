extends GutTest
## Zuhause and the wardrobe (MM1): the home door opens "Umkleiden", it explains itself once (D-087
## pattern), a colour click puts it on, saves it in the slot and notifies the player hook; the door
## sign is a placeholder until art/ui/sign_home.png exists. Uses a test save file only.

const TEST_PATH := "user://test_village_home.cfg"
const VILLAGE_SCENE := "res://world/village/village.tscn"

var _old_path: String
var _ui: VillageUI = null


func before_all() -> void:
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()
	_ui = VillageUI.new()
	add_child_autofree(_ui)


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	for version in [1, 2]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + SaveManager.MIGRATION_BACKUP_SUFFIX % version))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false) if node != null else null


func _open_home_seen() -> Modal:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.HOME))
	_ui.open_home()
	return _ui.get_building_modal()


func test_home_is_a_building_with_texts() -> void:
	assert_true(VillageBuildings.has_building(VillageBuildings.HOME))
	assert_has(VillageBuildings.ALL, VillageBuildings.HOME)
	assert_eq(VillageBuildings.get_display_name(VillageBuildings.HOME), "Zuhause")
	assert_false(VillageBuildings.get_role(VillageBuildings.HOME).is_empty())
	assert_false(VillageBuildings.get_hints(VillageBuildings.HOME).is_empty())
	assert_null(VillageBuildings.get_npc_frames(VillageBuildings.HOME), "no NPC at home")


func test_first_visit_explains_home_once_with_own_character() -> void:
	_ui.open_home()
	var intro := _ui.get_intro_modal()
	assert_not_null(intro, "explanation first")
	assert_eq((_find(intro, "RoleLabel") as Label).text, VillageBuildings.get_role(VillageBuildings.HOME))
	assert_true(_find(intro, "OwnPortrait") is CharacterPreview, "shows the player's character")
	(_find(intro, "ConfirmButton") as Button).pressed.emit()
	assert_false(VillageBuildings.needs_intro(VillageBuildings.HOME))
	assert_not_null(_ui.get_building_modal(), "wardrobe opens after the explanation")
	_ui.get_building_modal().finish()
	_ui.open_home()
	assert_null(_ui.get_intro_modal(), "second visit without explanation")
	_ui.get_building_modal().finish()


func test_wardrobe_shows_one_swatch_per_colour() -> void:
	var modal := _open_home_seen()
	assert_not_null(modal)
	var hero := CharacterCatalog.get_active()
	var swatches := _find(modal, "Swatches")
	assert_not_null(swatches)
	assert_eq(swatches.get_child_count(), hero.color_choices.size())
	assert_not_null(_find(modal, "WardrobePreview"))
	modal.finish()


func test_picking_a_colour_puts_it_on_and_saves() -> void:
	watch_signals(SaveManager)
	var modal := _open_home_seen()
	(_find(modal, "Swatch2") as Button).pressed.emit()
	assert_signal_emitted(SaveManager, "profile_changed", "player hook is notified")
	assert_eq(SaveManager.get_character_color().to_html(false), "e0463a")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_character_color().to_html(false), "e0463a", "saved in the slot")
	modal.finish()


func test_number_keys_pick_colours() -> void:
	var modal := _open_home_seen()
	await wait_physics_frames(1)
	assert_true(modal.hotkeys.has(KEY_3))
	(modal.hotkeys[KEY_3] as Callable).call()
	assert_eq(SaveManager.get_character_color().to_html(false), "5fcd62")
	modal.finish()


func test_put_on_the_same_colour_twice_is_no_change() -> void:
	assert_true(_ui.put_on_color(1))
	assert_false(_ui.put_on_color(1))
	assert_false(_ui.put_on_color(99))


func test_village_has_home_door_and_placeholder_sign() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	var home := village.get_node("Buildings/Home")
	assert_eq(StringName(home.get_meta(&"building_id")), VillageBuildings.HOME)
	var door := home.get_node("Door") as Interactable
	assert_not_null(door)
	assert_eq(door.prompt, "Umkleiden")
	var sign := home.get_node_or_null("Sign") as Sprite2D
	assert_not_null(sign, "sign file or placeholder")
	assert_eq(sign.texture.get_size(), Vector2(24, 16))
	assert_true(village.has_intro_marker(VillageBuildings.HOME), "marker while unexplained")
	GameManager.clear_pause_reasons()


func test_door_opens_the_wardrobe() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.HOME))
	village.enter_building(VillageBuildings.HOME)
	var modal := village.ui.get_building_modal()
	assert_not_null(modal)
	assert_not_null(_find(modal, "Swatches"))
	modal.finish()
	GameManager.clear_pause_reasons()
