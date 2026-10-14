extends GutTest
## Village explanations (D-087): every building explains itself exactly once with "Verstanden",
## the role sentence stays as dialog subtitle, the forge shows real values, door signs and the
## "not explained yet" markers exist. Uses a test save file only.

const TEST_PATH := "user://test_village_intro.cfg"
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


func _modal(modal_name: String) -> Modal:
	return _ui.get_intro_modal() if modal_name == "IntroModal" else _ui.get_building_modal()


func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false) if node != null else null


func _confirm_intro() -> void:
	var button := _find(_modal("IntroModal"), "ConfirmButton") as Button
	assert_not_null(button, "intro has a Verstanden button")
	if button != null:
		assert_eq(button.text, "Verstanden")
		button.pressed.emit()


func _close_building() -> void:
	var modal := _modal("BuildingModal")
	if modal != null:
		modal.finish()


func _open(building_id: StringName) -> void:
	match building_id:
		VillageBuildings.FORGE:
			_ui.open_forge()
		VillageBuildings.TRADER:
			_ui.open_trader()
		VillageBuildings.CHRONICLE:
			_ui.open_chronicle()
		VillageBuildings.GUILD:
			_ui.open_guild()


# --- Texts ---

func test_roles_are_the_d087_sentences() -> void:
	assert_eq(VillageBuildings.get_role(VillageBuildings.FORGE), "Dauerhaft stärker werden – kostet Gold.")
	assert_eq(VillageBuildings.get_role(VillageBuildings.TRADER), "Proviant für den nächsten Run – kostet Seelenkristalle.")
	assert_eq(VillageBuildings.get_role(VillageBuildings.CHRONICLE), "Deine Rekorde und Statistiken.")
	assert_eq(VillageBuildings.get_role(VillageBuildings.GUILD), "Mit Freunden spielen.")


func test_every_building_has_name_hints_npc_and_sign() -> void:
	for id in VillageBuildings.ORDER:
		assert_false(VillageBuildings.get_display_name(id).is_empty(), String(id))
		assert_false(VillageBuildings.get_hints(id).is_empty(), String(id))
		assert_not_null(VillageBuildings.get_npc_frames(id), "%s NPC sprite" % id)
		assert_not_null(VillageBuildings.get_sign_texture(id), "%s door sign" % id)


# --- Explanation exactly once ---

func test_first_visit_shows_intro_then_dialog() -> void:
	_ui.open_forge()
	assert_not_null(_modal("IntroModal"), "explanation first")
	assert_null(_modal("BuildingModal"), "dialog waits for Verstanden")
	assert_true(_ui.is_dialog_open())
	var role := _find(_modal("IntroModal"), "RoleLabel") as Label
	assert_eq(role.text, VillageBuildings.get_role(VillageBuildings.FORGE))
	assert_true(VillageBuildings.needs_intro(VillageBuildings.FORGE), "not seen before confirming")
	_confirm_intro()
	assert_false(VillageBuildings.needs_intro(VillageBuildings.FORGE), "seen after Verstanden")
	assert_not_null(_modal("BuildingModal"), "dialog opens after the explanation")
	_close_building()
	assert_false(_ui.is_dialog_open())


func test_intro_appears_exactly_once_per_building() -> void:
	for id in VillageBuildings.ORDER:
		_open(id)
		assert_not_null(_modal("IntroModal"), "%s: first visit explains" % id)
		_confirm_intro()
		_close_building()
		_open(id)
		assert_null(_modal("IntroModal"), "%s: second visit without explanation" % id)
		assert_not_null(_modal("BuildingModal"), "%s: dialog opens directly" % id)
		_close_building()


func test_seen_intro_survives_reload() -> void:
	_ui.open_chronicle()
	_confirm_intro()
	_close_building()
	assert_eq(SaveManager.load_game(), OK, "mark_intro_seen saved the game")
	assert_false(VillageBuildings.needs_intro(VillageBuildings.CHRONICLE))
	assert_true(VillageBuildings.needs_intro(VillageBuildings.GUILD))


func test_escape_also_counts_as_seen() -> void:
	_ui.open_guild()
	_modal("IntroModal").finish(null)
	assert_false(VillageBuildings.needs_intro(VillageBuildings.GUILD))
	assert_not_null(_modal("BuildingModal"))
	_close_building()


func test_enter_confirms_the_intro() -> void:
	_ui.open_chronicle()
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	_ui._unhandled_input(accept)
	assert_false(VillageBuildings.needs_intro(VillageBuildings.CHRONICLE))
	assert_not_null(_modal("BuildingModal"))
	_close_building()


func test_subtitle_is_the_role_sentence() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.TRADER))
	_ui.open_trader()
	var subtitle := _find(_modal("BuildingModal"), "Subtitle") as Label
	assert_not_null(subtitle)
	assert_eq(subtitle.text, VillageBuildings.get_role(VillageBuildings.TRADER))
	_close_building()


func test_info_button_shows_intro_again() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	_ui.open_forge()
	assert_null(_modal("IntroModal"))
	var info := _find(_modal("BuildingModal"), "InfoButton") as Button
	assert_not_null(info)
	info.pressed.emit()
	assert_not_null(_modal("IntroModal"), "info button reopens the explanation")
	assert_not_null(_modal("BuildingModal"), "on top of the open dialog")
	_confirm_intro()
	assert_null(_modal("IntroModal"))
	assert_true(GameManager.has_pause_reason(VillageUI.PAUSE_VILLAGE_DIALOG), "dialog still pauses the village")
	_close_building()


# --- Forge values ---

func test_forge_cards_show_real_values() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	SaveManager.set_meta_level(MetaProgression.VITALITY, 1)
	_ui.open_forge()
	var texts: Array[String] = []
	for node in _modal("BuildingModal").find_children("StepLabel", "Label", true, false):
		texts.append((node as Label).text)
	assert_eq(texts.size(), 3, "fresh save: Vitalität, Startschild, Schärfe (D-087)")
	assert_has(texts, "Max-HP 7 → 8")
	assert_has(texts, "Schild 0 → 3")
	assert_has(texts, "Schaden +0 % → +10 %")
	_close_building()


func test_forge_shows_all_upgrades_after_the_first_boss() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	_ui.open_forge()
	var steps := _modal("BuildingModal").find_children("StepLabel", "Label", true, false)
	assert_eq(steps.size(), MetaProgression.UPGRADE_ORDER.size(), "one value line per upgrade")
	assert_null(_find(_modal("BuildingModal"), "LockedUpgradesHint"), "no lock line any more")
	_close_building()


# --- Village world ---

func test_village_has_door_signs_and_intro_markers() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	for building in village.get_node("Buildings").get_children():
		if building.has_meta(&"building_id"):
			var id := StringName(building.get_meta(&"building_id"))
			assert_not_null(building.get_node_or_null("Sign"), "%s has a door sign" % id)
			if MetaUnlocks.is_building_open(id):
				assert_true(village.has_intro_marker(id), "%s: marker while unexplained" % id)
			else:
				assert_false(village.has_intro_marker(id), "%s: locked, lock instead of the info marker" % id)
				assert_true(village.has_lock_marker(id), "%s: lock marker" % id)
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	assert_false(village.has_intro_marker(VillageBuildings.FORGE), "marker goes away once seen")
	assert_true(village.has_intro_marker(VillageBuildings.GUILD))
	GameManager.clear_pause_reasons()


func test_no_markers_for_old_saves() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[meta]\nversion=2\n[progress]\npermanent_gold=5\n")
	file.close()
	assert_eq(SaveManager.load_game(), OK)
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	for id in VillageBuildings.ORDER:
		assert_false(village.has_intro_marker(id), "%s: old save counts as explained" % id)
		assert_false(village.has_lock_marker(id), "%s: old save counts as unlocked (D-087)" % id)
	GameManager.clear_pause_reasons()
