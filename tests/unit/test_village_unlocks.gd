extends GutTest
## Locked village buildings (D-087): visible with a lock and "Öffnet nach …", the door only shows a
## notice, they open after the event; the village announces new unlocks once; the forge hides locked
## upgrades; the trader has no crystal exchange any more. Uses a test save file only.

const TEST_PATH := "user://test_village_unlocks.cfg"
const VILLAGE_SCENE := "res://world/village/village.tscn"

var _old_locale: String
var _old_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	# The expected texts are German; English is the default language (D-111).
	Loc.apply(&"de")
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	for suffix in ["", ".bak", ".v2.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


func _door(village: Village, building_id: StringName) -> Interactable:
	for building in village.get_node("Buildings").get_children():
		if building.has_meta(&"building_id") and StringName(building.get_meta(&"building_id")) == building_id:
			return building.get_node("Door") as Interactable
	return null


func _notice_lines(ui: VillageUI) -> Array[String]:
	var lines: Array[String] = []
	var notice := ui.get_notice()
	if notice != null:
		for node in notice.find_children("*", "Label", true, false):
			if node.is_in_group(&"village_notice_line"):
				lines.append((node as Label).text)
	return lines


func _notice_title(ui: VillageUI) -> String:
	var notice := ui.get_notice()
	var title := notice.find_child("NoticeTitle", true, false) as Label if notice != null else null
	return title.text if title != null else ""


# --- Locked buildings ---

func test_locked_buildings_show_lock_and_text() -> void:
	var village := _village()
	for id in [VillageBuildings.CHRONICLE, VillageBuildings.TRADER]:
		assert_true(village.has_lock_marker(id), "%s locked in a fresh save" % id)
		var building := _door(village, id).get_parent()
		var text := building.find_child("LockText", true, false) as Label
		assert_not_null(text)
		assert_eq(text.text, MetaUnlocks.get_building_lock_text(id))
		assert_not_null(building.find_child("LockIcon", true, false), "icon_lock")
		assert_string_contains(_door(village, id).prompt, "Öffnet")
		assert_true(building.visible, "the building stays visible")
	for id in [VillageBuildings.FORGE, VillageBuildings.GUILD, VillageBuildings.HOME]:
		assert_false(village.has_lock_marker(id), "%s open" % id)


func test_locked_door_shows_a_notice_instead_of_the_dialog() -> void:
	var village := _village()
	watch_signals(village)
	village.enter_building(VillageBuildings.CHRONICLE)
	assert_null(village.ui.get_building_modal(), "no dialog")
	assert_null(village.ui.get_intro_modal(), "no explanation either")
	assert_false(village.ui.is_dialog_open())
	assert_signal_not_emitted(village, "building_entered")
	assert_eq(_notice_title(village.ui), "Chronik")
	assert_eq(_notice_lines(village.ui), ["Öffnet nach deinem ersten Run."] as Array[String])
	assert_false(GameManager.has_pause_reason(VillageUI.PAUSE_VILLAGE_DIALOG), "a notice never pauses")
	assert_true(VillageBuildings.needs_intro(VillageBuildings.CHRONICLE), "explanation still waits for the first visit")


func test_open_building_after_the_event() -> void:
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_RUN)
	var village := _village()
	assert_false(village.has_lock_marker(VillageBuildings.CHRONICLE))
	assert_true(village.has_intro_marker(VillageBuildings.CHRONICLE), "explains itself on the first visit")
	assert_eq(_door(village, VillageBuildings.CHRONICLE).prompt, "Chronik betreten")
	assert_true(village.has_lock_marker(VillageBuildings.TRADER))
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.CHRONICLE))
	village.enter_building(VillageBuildings.CHRONICLE)
	assert_not_null(village.ui.get_building_modal(), "the chronicle opens")
	village.ui.get_building_modal().finish()


func test_refresh_locks_opens_without_reloading() -> void:
	var village := _village()
	assert_true(village.has_lock_marker(VillageBuildings.TRADER))
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_CRYSTAL)
	village.refresh_locks()
	assert_false(village.has_lock_marker(VillageBuildings.TRADER))
	assert_eq(_door(village, VillageBuildings.TRADER).prompt, "Handelsposten betreten")


# --- Announcement on return ---

func test_village_announces_new_unlocks_once() -> void:
	SaveManager.add_stat(StatsTracker.DEATHS, 1)
	SaveManager.add_stat(StatsTracker.BOSSES, 1)
	var village := _village()
	assert_eq(_notice_title(village.ui), MetaUnlocks.get_announce_title())
	assert_eq(_notice_lines(village.ui), ["Chronik", "Schmiede: Goldgier, Dash-Training und Arsenal"] as Array[String])
	assert_false(village.has_lock_marker(VillageBuildings.CHRONICLE), "synced from the statistics on load")
	assert_eq(SaveManager.load_game(), OK)
	assert_true(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_BOSS), "the village saved the events")
	var again := _village()
	assert_null(again.ui.get_notice(), "only once")


func test_fresh_and_old_saves_get_no_announcement() -> void:
	assert_null(_village().ui.get_notice(), "fresh save: nothing new")
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[meta]\nversion=2\n[progress]\npermanent_gold=5\n[stats]\nbosses=4\ndeaths=2\n")
	file.close()
	assert_eq(SaveManager.load_game(), OK)
	assert_null(_village().ui.get_notice(), "old save: everything unlocked silently")


# --- Forge and trader dialogs ---

func test_forge_hides_locked_upgrades_with_a_hint() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	var modal := ui.get_building_modal()
	var hint := modal.find_child("LockedUpgradesHint", true, false)
	assert_not_null(hint, "one line says when more come")
	var texts: Array[String] = []
	for node in modal.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	assert_has(texts, "Weitere Verbesserungen öffnen nach deinem ersten Boss.")
	for id in [MetaProgression.GOLD_GREED, MetaProgression.DASH_TRAINING, MetaProgression.ARSENAL]:
		assert_does_not_have(texts, MetaProgression.get_upgrade_name(id), "%s hidden while locked" % id)
	modal.finish()


func test_trader_has_proviant_but_no_crystal_exchange() -> void:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.TRADER))
	SaveManager.add_permanent_crystals(10)
	SaveManager.add_permanent_gold(500)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_trader()
	var modal := ui.get_building_modal()
	var texts: Array[String] = []
	for node in modal.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	for node in modal.find_children("*", "Button", true, false):
		texts.append((node as Button).text)
	assert_does_not_have(texts, "Tausch")
	for text in texts:
		assert_false(text.contains("→"), "no exchange button: %s" % text)
	for id in MetaProgression.BOOST_ORDER:
		assert_has(texts, MetaProgression.get_boost_name(id), "Proviant %s offered" % id)
	modal.finish()
	assert_eq(SaveManager.get_permanent_crystals(), 10)
	assert_eq(SaveManager.get_permanent_gold(), 500)
