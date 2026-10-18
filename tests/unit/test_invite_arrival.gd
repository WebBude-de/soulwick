extends GutTest
## MP2b (D-190): arriving by an invite link skips the main menu. With a profile the game starts at
## once in the world of "Weiterspielen" (or a fresh "Welt 1", D-161) and the village gets the join
## wish with via_link; without a profile the first start asks name and figure on one page that names
## the room, then goes straight in. The invite is taken once. Test folder (SaveManager.
## set_storage_root, the profile lives there too), never the real save or profile; no network.

const ROOT := "user://test_invite_arrival"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String


func before_all() -> void:
	MainMenu.online_check = false
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	GameOptions.set_language(&"de")
	assert_true(PlayerProfile.current().path.begins_with(ROOT), "the profile lives in the test folder")
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())
	LobbyClient.take_launch()


func after_each() -> void:
	InviteLink.set_arrival("")
	LobbyClient.take_launch()
	GameManager.clear_pause_reasons()


func after_all() -> void:
	MainMenu.online_check = true
	_wipe()
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
	DirAccess.make_dir_recursive_absolute(root)


func _menu() -> MainMenu:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	return menu


func test_invite_skips_the_menu_and_creates_the_first_world() -> void:
	InviteLink.set_arrival("abc234")
	var menu := _menu()
	watch_signals(menu)
	await wait_physics_frames(3)
	assert_true(menu.is_starting(), "straight into the game")
	assert_signal_emitted(menu, "play_requested")
	assert_null(menu.get_open_panel(), "no panel on the way")
	assert_true(SaveManager.has_slot(1), "a fresh world (D-161)")
	assert_eq(SaveManager.get_slot_summary(1)["name"], "Welt 1")
	var launch := LobbyClient.take_launch()
	assert_eq(launch.get("action"), LobbyClient.LAUNCH_JOIN)
	assert_eq(launch.get("code"), "ABC234")
	assert_true(bool(launch.get("via_link", false)), "the village knows it came from a link")
	assert_eq(menu.get_invite_code(), "", "on its way")


func test_invite_uses_the_continue_world() -> void:
	SaveManager.create_slot(1, "Nebeltal")
	SaveManager.create_slot(2, "Moorhang")
	SaveManager.load_slot(2)
	InviteLink.set_arrival("ABC234")
	var menu := _menu()
	await wait_physics_frames(3)
	assert_true(menu.is_starting())
	assert_eq(SaveManager.get_active_slot(), 2, "the world of Weiterspielen")
	assert_false(SaveManager.has_slot(3), "no extra world")
	assert_eq(LobbyClient.take_launch().get("code"), "ABC234")


func test_invite_is_taken_once() -> void:
	InviteLink.set_arrival("ABC234")
	_menu()
	await wait_physics_frames(3)
	LobbyClient.take_launch()
	var again := _menu()
	await wait_physics_frames(3)
	assert_false(again.is_starting(), "back in the menu later: no second join")
	assert_false(LobbyClient.has_pending_launch())


func test_invalid_invite_opens_the_menu_as_usual() -> void:
	InviteLink.set_arrival("ABC0O1")
	var menu := _menu()
	await wait_physics_frames(3)
	assert_false(menu.is_starting(), "an invalid code is dropped")
	assert_false(LobbyClient.has_pending_launch())


func test_first_start_by_invite_asks_name_and_figure_then_joins() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.current().path))
	PlayerProfile.reset()
	InviteLink.set_arrival("XYZ789")
	var menu := _menu()
	await wait_physics_frames(2)
	var panel := menu.get_open_panel() as ProfilePanel
	assert_not_null(panel, "name and figure first (D-152)")
	assert_true(panel.first_start)
	assert_eq(panel.invite_code, "XYZ789")
	assert_false(menu.is_starting(), "waits for the name")
	var intro := panel.find_child("Intro", true, false) as Label
	assert_string_contains(intro.text, "XYZ789", "names the room")
	var texts := PackedStringArray()
	for label: Label in panel.find_children("*", "Label", true, false):
		texts.append(tr(label.text))
	assert_string_contains(" | ".join(texts), "Einladung", "the invite's header")
	assert_false(panel.editor.find_children("*", "LineEdit", true, false).is_empty(), "name on the same page")
	panel.editor.set_player_name("Mira")
	panel.editor.change_character(1)
	panel.editor.confirm()
	await wait_physics_frames(3)
	assert_true(menu.is_starting(), "Los geht's goes straight into the room")
	assert_eq(PlayerProfile.current().player_name, "Mira")
	assert_true(SaveManager.has_slot(1), "Welt 1")
	var launch := LobbyClient.take_launch()
	assert_eq(launch.get("code"), "XYZ789")
	assert_true(bool(launch.get("via_link", false)))
