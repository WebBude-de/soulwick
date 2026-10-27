extends GutTest
## Village explanations (D-087, WK9): on the first entry Flint explains every building (role and a
## tip, once per account) before its dialog opens; skipping counts as heard; the info button asks him
## again; old saves count as explained; without a local player (a remote copy, a tool) the dialog
## opens directly. The role sentence stays as dialog subtitle, the forge shows real values, door signs
## and the "not explained yet" markers exist. Test folder only (SaveManager.set_storage_root), never
## the real save or progress.cfg.

const ROOT := "user://test_village_intro"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DT := 1.0 / 60.0

var _old_locale: String
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _ui: VillageUI = null


func before_all() -> void:
	# The guild building is the online menu (D-147): no login against a server from the tests.
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
	# The expected texts are German; English is the default language (D-111).
	Loc.apply(&"de")
	VillageTour.force_in_scripts = true
	_ui = VillageUI.new()
	add_child_autofree(_ui)


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


## A player of this machine (or a remote copy) next to the UI; its guide is stepped by hand.
func _player(local := true) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = local
	add_child_autofree(player)
	player.global_position = Vector2(400, 300)
	var guide := FlintGuide.for_player(player)
	guide.set_process(false)
	guide.shows_view = false
	return player


## Steps the guide with "Weiter" until Flint is back (true if he finished).
func _talk_through(guide: FlintGuide) -> bool:
	for i in 2400:
		if guide.phase == FlintGuide.Phase.IDLE:
			return true
		guide.advance(DT)
		if guide.phase == FlintGuide.Phase.TALK:
			guide.press()
	return guide.phase == FlintGuide.Phase.IDLE


func _to_talk(guide: FlintGuide) -> void:
	for i in ceili((FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME) / DT) + 1:
		guide.advance(DT)


func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false) if node != null else null


func _close_building() -> void:
	var modal := _ui.get_building_modal()
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


func test_every_building_has_name_hints_npc_sign_and_flint() -> void:
	for id in VillageBuildings.ORDER:
		assert_false(VillageBuildings.get_display_name(id).is_empty(), String(id))
		assert_false(VillageBuildings.get_hints(id).is_empty(), String(id))
		assert_not_null(VillageBuildings.get_npc_frames(id), "%s NPC sprite" % id)
		assert_not_null(VillageBuildings.get_sign_texture(id), "%s door sign" % id)
		var explanation := VillageTour.building_explanation(id)
		assert_not_null(explanation, "%s: Flint explains it" % id)
		assert_true(explanation.is_valid(), "%s: %s" % [id, explanation.problems()])
		assert_eq(explanation.id, StringName("flint_village_" + String(id)))
		assert_eq(explanation.style, FlintExplanation.Style.TOUR, "%s: 'Weiter' paces it, the dialog waits" % id)
		assert_false(explanation.uses_camera(), "%s: the player stands at the door, no camera ride" % id)
	assert_null(VillageTour.building_explanation(VillageBuildings.HOME), "Zuhause explains itself inside (KE8)")


# --- Flint explains on the first entry ---

func test_first_visit_flint_explains_then_the_dialog_opens() -> void:
	var player := _player()
	var guide := FlintGuide.of(player)
	_ui.open_forge()
	assert_true(guide.is_running(), "Flint explains first")
	assert_eq(guide.current.id, &"flint_village_forge")
	assert_true(_ui.is_intro_open())
	assert_eq(_ui.get_explaining(), VillageBuildings.FORGE)
	assert_null(_ui.get_building_modal(), "the dialog waits for Flint")
	assert_true(_ui.is_dialog_open(), "no second door meanwhile")
	assert_null(_ui.get_intro_modal(), "no explanation card any more")
	assert_false(get_tree().paused, "Flint never pauses (Koop)")
	assert_true(player.is_protected(), "the listener is protected like in a menu (D-123)")
	_to_talk(guide)
	assert_eq(guide.get_text(), Loc.t(&"FLINT_VILLAGE_FORGE_INTRO"), "the role first")
	assert_true(VillageBuildings.needs_intro(VillageBuildings.FORGE), "not heard yet")
	assert_true(_talk_through(guide))
	assert_false(VillageBuildings.needs_intro(VillageBuildings.FORGE), "heard")
	assert_true(AccountSeen.has_seen(&"flint_village_forge"), "for the account")
	assert_true(SaveManager.has_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE)), "and for the world (D-087)")
	assert_false(_ui.is_intro_open())
	assert_not_null(_ui.get_building_modal(), "the dialog opens after Flint")
	assert_false(player.is_protected(), "free again")
	_close_building()
	assert_false(_ui.is_dialog_open())


func test_each_building_is_explained_exactly_once() -> void:
	var guide := FlintGuide.of(_player())
	for id in VillageBuildings.ORDER:
		_open(id)
		assert_true(guide.is_running(), "%s: first visit, Flint explains" % id)
		assert_true(_talk_through(guide), String(id))
		assert_not_null(_ui.get_building_modal(), "%s: then the dialog" % id)
		_close_building()
		_open(id)
		assert_false(guide.is_running(), "%s: second visit without Flint" % id)
		assert_not_null(_ui.get_building_modal(), "%s: dialog opens directly" % id)
		_close_building()


func test_skipping_counts_as_heard() -> void:
	var guide := FlintGuide.of(_player())
	_ui.open_guild()
	_to_talk(guide)
	assert_true(guide.skip(), "Überspringen")
	for i in 60:
		guide.advance(DT)
	assert_false(VillageBuildings.needs_intro(VillageBuildings.GUILD))
	assert_not_null(_ui.get_building_modal(), "the dialog opens after a skip too")
	_close_building()


func test_heard_once_counts_in_a_new_world_of_the_account() -> void:
	var guide := FlintGuide.of(_player())
	_ui.open_chronicle()
	assert_true(_talk_through(guide))
	_close_building()
	assert_eq(SaveManager.load_game(), OK, "mark_intro_seen saved the game")
	assert_false(VillageBuildings.needs_intro(VillageBuildings.CHRONICLE))
	assert_true(VillageBuildings.needs_intro(VillageBuildings.GUILD))
	# A new world: its [seen] is empty, the account still knows the chronicle (KONZEPT §7.2).
	SaveManager.save_path = SaveManager.slot_path(2)
	SaveManager.load_game()
	assert_false(SaveManager.has_seen(VillageBuildings.get_intro_key(VillageBuildings.CHRONICLE)), "new world")
	assert_false(VillageBuildings.needs_intro(VillageBuildings.CHRONICLE), "not explained twice")
	assert_true(VillageBuildings.needs_intro(VillageBuildings.GUILD))
	_ui.open_chronicle()
	assert_false(guide.is_running(), "Flint stays quiet")
	assert_not_null(_ui.get_building_modal())
	_close_building()


func test_without_a_local_player_the_dialog_opens_directly() -> void:
	var remote := _player(false)
	_ui.open_forge()
	assert_false(FlintGuide.of(remote).is_running(), "a remote copy is never explained")
	assert_not_null(_ui.get_building_modal(), "the dialog opens directly")
	assert_true(VillageBuildings.needs_intro(VillageBuildings.FORGE), "nobody heard it: still due")
	_close_building()


func test_script_runs_skip_flint_unless_forced() -> void:
	var guide := FlintGuide.of(_player())
	VillageTour.force_in_scripts = false
	_ui.open_trader()
	assert_false(guide.is_running(), "tools and tests are not held up")
	assert_not_null(_ui.get_building_modal())
	_close_building()


func test_info_button_asks_flint_again() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	var guide := FlintGuide.of(_player())
	_ui.open_forge()
	assert_false(guide.is_running())
	var info := _find(_ui.get_building_modal(), "InfoButton") as Button
	assert_not_null(info)
	assert_true(info.visible, "Flint can explain here")
	info.pressed.emit()
	assert_null(_ui.get_building_modal(), "the dialog makes room for Flint")
	assert_true(guide.is_running(), "Flint explains again")
	assert_true(_ui.is_dialog_open(), "still busy: no second door")
	assert_false(GameManager.has_pause_reason(VillageUI.PAUSE_VILLAGE_DIALOG), "the village runs while he talks")
	assert_true(_talk_through(guide))
	assert_not_null(_ui.get_building_modal(), "and the dialog is back")
	assert_true(GameManager.has_pause_reason(VillageUI.PAUSE_VILLAGE_DIALOG), "the dialog pauses the village again")
	_close_building()
	assert_false(_ui.is_dialog_open())


func test_info_button_hides_without_flint() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	VillageTour.force_in_scripts = false
	_ui.open_forge()
	var info := _find(_ui.get_building_modal(), "InfoButton") as Button
	assert_not_null(info)
	assert_false(info.visible, "nobody could answer it")
	_close_building()


func test_subtitle_is_the_role_sentence() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.TRADER))
	_ui.open_trader()
	var subtitle := _find(_ui.get_building_modal(), "Subtitle") as Label
	assert_not_null(subtitle)
	assert_eq(subtitle.text, VillageBuildings.get_role(VillageBuildings.TRADER))
	_close_building()


# --- Forge values ---

func test_forge_cards_show_real_values() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	SaveManager.set_meta_level(MetaProgression.SMITH_SWORD, 1)
	_ui.open_forge()
	var texts: Array[String] = []
	for node in _ui.get_building_modal().find_children("StepLabel", "Label", true, false):
		texts.append((node as Label).text)
	assert_eq(texts.size(), 7, "fresh save: five weapons, Schildplatte, Laterne (KE4)")
	assert_has(texts, "Schaden 16,2 → 17,4", "sword I -> II with the real damage (D-087)")
	assert_has(texts, "Schaden 8 → 8,6", "bow")
	assert_has(texts, "Schild 0 → 3")
	assert_has(texts, "Lichtradius +0 % → +10 %")
	_close_building()


func test_forge_shows_all_upgrades_after_the_first_boss() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	_ui.open_forge()
	var steps := _ui.get_building_modal().find_children("StepLabel", "Label", true, false)
	assert_eq(steps.size(), MetaProgression.WEAPON_UPGRADES.size() + MetaProgression.EQUIPMENT_UPGRADES.size(),
		"one value line per weapon and equipment (Arsenal sits in the weapon rows)")
	for id in MetaProgression.ARSENAL_UPGRADES:
		assert_not_null(_find(_ui.get_building_modal(), "Buy_%s" % id), "%s can be bought" % id)
	assert_null(_find(_ui.get_building_modal(), "LockedUpgradesHint"), "no lock line any more")
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


func test_door_of_the_village_lets_flint_explain() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	var player := PLAYER_SCENE.instantiate() as Player
	village.add_child(player)
	var forge := VillageTour.station_node(village, VillageBuildings.FORGE)
	player.global_position = forge.global_position + Vector2(0, 40)
	var guide := FlintGuide.for_player(player)
	guide.set_process(false)
	guide.shows_view = false
	village.enter_building(VillageBuildings.FORGE)
	assert_true(guide.is_running(), "the door: Flint first")
	assert_true(village.has_intro_marker(VillageBuildings.FORGE), "the marker stays while he talks")
	assert_true(_talk_through(guide))
	assert_false(village.has_intro_marker(VillageBuildings.FORGE), "heard: the marker goes")
	assert_not_null(village.ui.get_building_modal())
	village.ui.get_building_modal().finish()
	GameManager.clear_pause_reasons()


func test_no_markers_and_no_flint_for_old_saves() -> void:
	var file := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	file.store_string("[meta]\nversion=2\n[progress]\npermanent_gold=5\n")
	file.close()
	assert_eq(SaveManager.load_game(), OK)
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	for id in VillageBuildings.ORDER:
		assert_false(village.has_intro_marker(id), "%s: old save counts as explained" % id)
		assert_false(village.has_lock_marker(id), "%s: old save counts as unlocked (D-087)" % id)
	var guide := FlintGuide.of(_player())
	_ui.open_forge()
	assert_false(guide.is_running(), "old players know the forge (D-087)")
	assert_not_null(_ui.get_building_modal())
	_close_building()
	GameManager.clear_pause_reasons()
