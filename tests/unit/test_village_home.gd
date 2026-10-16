extends GutTest
## Zuhause and the mirror (MM1, D-152): the home door opens "Umkleiden" with the profile editor, it
## explains itself once (D-087 pattern); the mirror next to the house opens the same editor; saving
## puts the look on, writes the profile and notifies the player hook. The door sign is a placeholder
## until art/ui/sign_home.png exists. Uses a test save file and a test profile only.

const TEST_PATH := "user://test_village_home.cfg"
const PROFILE_PATH := "user://test_village_home_profile.cfg"
const VILLAGE_SCENE := "res://world/village/village.tscn"

var _old_locale: String
var _old_path: String
var _ui: VillageUI = null


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	# The expected texts are German; English is the default language (D-111).
	Loc.apply(&"de")
	_old_path = SaveManager.save_path
	PlayerProfile.path_override = PROFILE_PATH


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	PlayerProfile.reset()
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())
	SaveManager.load_game()
	_ui = VillageUI.new()
	add_child_autofree(_ui)


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	for version in [1, 2, 3]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + SaveManager.MIGRATION_BACKUP_SUFFIX % version))
	PlayerProfile.path_override = ""
	PlayerProfile.reset()
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
	assert_not_null(_ui.get_building_modal(), "the editor opens after the explanation")
	_ui.get_building_modal().finish()
	_ui.open_home()
	assert_null(_ui.get_intro_modal(), "second visit without explanation")
	_ui.get_building_modal().finish()


func test_home_shows_the_profile_editor() -> void:
	var modal := _open_home_seen()
	assert_not_null(modal)
	var editor := _ui.get_profile_editor()
	assert_not_null(editor, "name, figure and colours")
	assert_eq(editor.get_player_name(), "Kerze")
	for slot in PlayerLook.SLOTS:
		assert_not_null(_find(editor, "Swatch_%s_7" % slot), "eight colours for %s" % slot)
	assert_null(_find(editor, "CancelProfile"), "the dialog has its own close button")
	modal.finish()


func test_saving_puts_the_look_on_and_writes_the_profile() -> void:
	watch_signals(SaveManager)
	var modal := _open_home_seen()
	var editor := _ui.get_profile_editor()
	(_find(editor, "Swatch_outfit_1") as Button).pressed.emit()
	editor.handle_input(MenuInput.key_event(KEY_DOWN))
	assert_eq(editor.get_row(), ProfileEditor.Row.SKIN, "↓ from the outfit row")
	editor.handle_input(MenuInput.key_event(KEY_4))
	assert_eq(PlayerLook.get_index(editor.get_look(), PlayerLook.SKIN), 3, "number keys pick directly")
	editor.confirm()
	await wait_physics_frames(2)
	assert_signal_emitted(SaveManager, "profile_changed", "player hook is notified")
	assert_null(_ui.get_building_modal(), "saving closes the dialog")
	PlayerProfile.reset()
	var profile := PlayerProfile.current()
	assert_eq(PlayerLook.get_index(profile.look, PlayerLook.OUTFIT), 1, "saved in profile.cfg")
	assert_eq(PlayerLook.get_index(profile.look, PlayerLook.SKIN), 3)
	assert_eq(SaveManager.get_character_color().to_html(false), "e0463a", "old one-colour API still answers")
	assert_false(is_instance_valid(modal) and modal.is_inside_tree(), "the dialog is gone")


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


func test_door_opens_the_editor() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.HOME))
	village.enter_building(VillageBuildings.HOME)
	var modal := village.ui.get_building_modal()
	assert_not_null(modal)
	assert_not_null(village.ui.get_profile_editor())
	modal.finish()
	GameManager.clear_pause_reasons()


func test_mirror_next_to_home_opens_the_same_editor() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	var mirror := village.get_mirror()
	assert_not_null(mirror, "D-152: a mirror stands next to the house")
	var home := village.get_node("Buildings/Home") as Node2D
	assert_lt(mirror.position.distance_to(home.position), 200.0, "close to Zuhause")
	assert_eq(mirror.door.prompt, "Spiegel · Aussehen ändern")
	mirror.door.interact(null)
	await wait_physics_frames(1)
	var editor := village.ui.get_profile_editor()
	assert_not_null(editor, "the mirror opens the profile editor")
	assert_true(village.ui.is_dialog_open())
	editor.set_player_name("Lumen")
	editor.change_character(1)
	editor.confirm()
	await wait_physics_frames(2)
	assert_false(village.ui.is_dialog_open(), "saved and closed")
	assert_eq(PlayerProfile.current().player_name, "Lumen", "the name can be changed there too")
	assert_eq(PlayerLook.get_character(PlayerProfile.current().look), &"ember")
	village.open_mirror()
	await wait_physics_frames(1)
	var again := village.ui.get_profile_editor()
	assert_not_null(again)
	again.handle_input(MenuInput.key_event(KEY_ESCAPE))
	await wait_physics_frames(1)
	assert_false(village.ui.is_dialog_open(), "Esc leaves without saving")
	GameManager.clear_pause_reasons()
