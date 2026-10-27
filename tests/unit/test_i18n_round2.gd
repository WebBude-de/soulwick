extends GutTest
## Second translation round (D-111): every DungeonTexts key has English in
## localization/translations.csv and the same German as DungeonTexts.DE, DungeonTexts.t() follows the
## language, the keys used by HUD, pause menu, village, meta progression, run recap and boss intro
## exist, upgrade and weapon names resolve by naming convention (DataTexts), and open HUD/pause/village
## texts switch at once. Runs in a test folder (SaveManager.set_storage_root), never on the real save.
##
## A failing test_every_dungeon_text_has_english means new DungeonTexts keys without English:
## python tools/i18n_check.py --dungeon-texts --export prints the missing CSV lines.

const ROOT := "user://test_i18n_round2"
## Prefixes of the round-two keys; every &"PREFIX_..." in KEY_FILES must be in the CSV.
const KEY_PREFIXES := ["HUD", "GAME_UI", "VILLAGE", "FORGE", "BOOST", "META", "UNLOCK", "SAVE", "RECAP",
	"BOSS_INTRO", "MENU", "RUNEND", "WEAPON_STATS"]
const KEY_FILES := ["res://ui/hud", "res://world", "res://meta", "res://ui/boss_intro", "res://localization",
	"res://ui/menus/game_ui.gd", "res://ui/menus/village_ui.gd", "res://ui/menus/run_recap.gd"]
const DATA_FOLDERS := {"res://upgrades/data": "UpgradeData", "res://weapons/data": "WeaponData"}

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String
var _csv: Dictionary = {}


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()
	_csv = Loc.load_csv(Loc.CSV_PATH)


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	Loc.apply(&"de")


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
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


func _csv_text(language: StringName, key: StringName) -> String:
	var translation := _csv.get(language, null) as Translation
	return String(translation.get_message(key)) if translation != null else ""


static func _scripts_in(path: String) -> PackedStringArray:
	if path.ends_with(".gd"):
		return PackedStringArray([path])
	var files: PackedStringArray = []
	var dir := DirAccess.open(path)
	if dir == null:
		return files
	for name in dir.get_files():
		if name.ends_with(".gd"):
			files.append(path.path_join(name))
	for sub in dir.get_directories():
		files.append_array(_scripts_in(path.path_join(sub)))
	return files


# --- DungeonTexts ---

func test_every_dungeon_text_has_english() -> void:
	var missing: PackedStringArray = []
	for key in DungeonTexts.get_keys():
		if _csv_text(&"en", key).strip_edges().is_empty():
			missing.append(String(key))
	assert_eq(missing, PackedStringArray(),
		"DungeonTexts keys without English in translations.csv (python tools/i18n_check.py --dungeon-texts --export): %s" % ", ".join(missing))


func test_csv_german_matches_dungeon_texts() -> void:
	for key in DungeonTexts.get_keys():
		if _csv_text(&"en", key).is_empty():
			continue
		assert_eq(_csv_text(&"de", key), DungeonTexts.DE[key], "%s: German in the CSV = DungeonTexts.DE" % key)


func test_dungeon_texts_follow_the_language() -> void:
	Loc.apply(&"en")
	assert_eq(DungeonTexts.t(&"MENU_CLOSE"), "Close")
	assert_eq(DungeonTexts.t(&"RUNEND_SUBTITLE", [7, 1]), "Reached room 7 · Cycle 1")
	assert_eq(DungeonTexts.t(&"WAGER_CURSE_GLOOM_RULE", [30]), "Light radius −30 % in this room", "%% stays a percent sign")
	for key in DungeonTexts.get_keys():
		var english := _csv_text(&"en", key)
		if not english.is_empty():
			assert_eq(DungeonTexts.t(key), english, "%s in English" % key)
	Loc.apply(&"de")
	assert_eq(DungeonTexts.t(&"MENU_CLOSE"), "Schließen")
	for key in DungeonTexts.get_keys():
		assert_eq(DungeonTexts.t(key), DungeonTexts.DE[key], "%s in German" % key)


# --- Keys of round two ---

func test_round_two_keys_in_code_exist() -> void:
	var pattern := RegEx.create_from_string("&\"((?:%s)_[A-Z0-9_]+)\"" % "|".join(KEY_PREFIXES))
	var used := 0
	for folder in KEY_FILES:
		for path in _scripts_in(folder):
			var source := FileAccess.get_file_as_string(path)
			for found in pattern.search_all(source):
				var key := found.get_string(1)
				used += 1
				assert_false(_csv_text(&"en", key).is_empty(), "%s (%s) has English" % [key, path.get_file()])
				assert_false(_csv_text(&"de", key).is_empty(), "%s (%s) has German" % [key, path.get_file()])
	assert_gt(used, 100, "the round-two files use keys")


func test_data_resources_have_keys_by_convention() -> void:
	for folder: String in DATA_FOLDERS:
		var dir := DirAccess.open(folder)
		assert_not_null(dir, folder)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".tres"):
				continue
			var resource := load(folder.path_join(file))
			if resource is UpgradeData:
				var upgrade := resource as UpgradeData
				for key in [DataTexts.key_for("upgrade", upgrade.id, "name"), DataTexts.key_for("upgrade", upgrade.id, "desc")]:
					assert_false(_csv_text(&"en", key).is_empty(), "%s for %s" % [key, file])
				assert_eq(_csv_text(&"de", DataTexts.key_for("upgrade", upgrade.id, "name")), upgrade.display_name, "%s: German = .tres" % file)
				assert_eq(_csv_text(&"de", DataTexts.key_for("upgrade", upgrade.id, "desc")), upgrade.description, "%s: German = .tres" % file)
			elif resource is WeaponData:
				var weapon := resource as WeaponData
				assert_eq(_csv_text(&"de", DataTexts.key_for("weapon", weapon.id, "name")), weapon.display_name, "%s: German = .tres" % file)
				assert_eq(_csv_text(&"de", DataTexts.key_for("weapon", weapon.id, "special")), weapon.special_name, file)
				assert_eq(_csv_text(&"de", DataTexts.key_for("weapon", weapon.id, "special_desc")), weapon.special_description, file)


func test_data_texts_follow_the_language_and_fall_back() -> void:
	var sword := load("res://weapons/data/sword.tres") as WeaponData
	var pierce := load("res://upgrades/data/pierce.tres") as UpgradeData
	assert_eq(DataTexts.weapon_name(sword), "Schwert")
	assert_eq(DataTexts.upgrade_name(pierce), pierce.display_name)
	Loc.apply(&"en")
	assert_eq(DataTexts.weapon_name(sword), "Sword")
	assert_eq(DataTexts.weapon_special_name(sword), "Whirlwind")
	assert_eq(DataTexts.upgrade_name(pierce), "Piercing")
	assert_eq(sword.display_name, "Schwert", "the resource keeps its German text (logic, tools)")
	var unknown := UpgradeData.new()
	unknown.id = &"no_such_upgrade"
	unknown.display_name = "Unbekannt"
	assert_eq(DataTexts.upgrade_name(unknown), "Unbekannt", "no CSV entry: the resource text")
	assert_eq(DataTexts.upgrade_name(null), "")


# --- Texts in English ---

func test_meta_texts_in_english() -> void:
	Loc.apply(&"en")
	assert_eq(MetaProgression.get_upgrade_name(MetaProgression.SHIELD_PLATE), "Shield Plate")
	assert_eq(MetaProgression.get_upgrade_name(MetaProgression.SMITH_BOW), "Forge Bow")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SMITH_SWORD, 0), "Damage 15 → 16.2", "English decimal point")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.ARSENAL_BOW, 0), "Starting weapon: locked → unlocked")
	assert_eq(MetaProgression.get_boost_name(MetaProgression.BOOST_GOLD_RAIN), "Gold Rain")
	assert_eq(MetaProgression.get_run_banner_title(), "From the village")
	assert_eq(MetaProgression.describe_forge_bonuses({MetaProgression.SHIELD_PLATE: 2, MetaProgression.LANTERN: 2}, [&"sword"]),
		["+6 shield", "+20 % light"] as Array[String])
	assert_eq(MetaUnlocks.get_building_lock_text(VillageBuildings.CHRONICLE), "Opens after your first run")
	assert_eq(MetaUnlocks.get_forge_lock_text(MetaUnlocks.EVENT_FIRST_BOSS), "More upgrades open after your first boss.")
	assert_eq(MetaUnlocks.join_names(["A", "B", "C"] as Array[String]), "A, B and C")
	assert_eq(MetaUnlocks.describe_event(MetaUnlocks.EVENT_FIRST_BOSS), "Forge: Arsenal and Second Starting Slot")
	assert_eq(SaveSlots.default_name(2), "World 2")
	var now := int(Time.get_unix_time_from_system())
	assert_string_starts_with(SaveSlots.format_last_played(now, now), "today")
	assert_eq(VillageBuildings.get_display_name(VillageBuildings.TRADER), "Trading Post")
	assert_eq(VillageBuildings.get_prompt(VillageBuildings.HOME), "Go inside")
	assert_eq(RunRecap.describe_hit(_trap_hit([&"trap", &"fire"])), "Lava fissure")
	Loc.apply(&"de")
	assert_eq(MetaProgression.describe_level_step(MetaProgression.SMITH_SWORD, 0), "Schaden 15 → 16,2")
	assert_eq(SaveSlots.default_name(2), "Welt 2")


func test_hud_switches_language_at_once() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	hud.set_dungeon_mode(true)
	hud.set_heal_countdown(2)
	assert_string_starts_with(hud._room_label.text, "Raum ")
	assert_string_contains(hud._room_detail.text, "nächste Heilung in 2")
	Loc.apply(&"en")
	await wait_physics_frames(1)
	assert_string_starts_with(hud._room_label.text, "Room ")
	assert_string_contains(hud._room_detail.text, "next heal in 2")
	assert_string_starts_with(hud._chronicle_room.text, "Best: room")
	assert_eq(tr(hud._hint_label.text), Loc.t(Hud.CONTROLS_HINT_SHORT) if SaveManager.has_seen(ControlsHint.SEEN_ID) else Loc.t(Hud.CONTROLS_HINT))
	assert_eq(Hud.room_type_name(RoomSequence.RoomType.SPECIAL), "Special room")
	Loc.apply(&"de")
	await wait_physics_frames(1)
	assert_string_starts_with(hud._room_label.text, "Raum ")
	assert_eq(Hud.room_type_name(RoomSequence.RoomType.SPECIAL), RoomSequence.get_type_name(RoomSequence.RoomType.SPECIAL), "German = RoomSequence")


func test_pause_menu_follows_a_language_switch() -> void:
	var ui := GameUI.new()
	add_child_autofree(ui)
	ui.open_pause_menu()
	await wait_physics_frames(1)
	var texts := _button_texts(ui.get_pause_modal())
	assert_has(texts, "Weiterspielen")
	assert_has(texts, "Hauptmenü")
	Loc.apply(&"en")
	await wait_physics_frames(1)
	texts = _button_texts(ui.get_pause_modal())
	assert_has(texts, "Resume", "pause menu in English: %s" % [texts])
	assert_has(texts, "Main menu")
	assert_has(texts, "Options")
	ui.get_pause_modal().finish(&"resume")
	await wait_physics_frames(1)


func test_village_prompts_and_captions_follow_the_language() -> void:
	var village: Village = (load("res://world/village/village.tscn") as PackedScene).instantiate()
	add_child_autofree(village)
	await wait_physics_frames(2)
	var forge := village.get_node("Buildings/Forge")
	var door := forge.get_node("Door") as Interactable
	var caption := forge.get_node("Caption") as Label
	assert_eq(door.prompt, "Schmiede betreten")
	assert_eq(tr(caption.text), "Schmiede")
	Loc.apply(&"en")
	await wait_physics_frames(1)
	assert_eq(door.prompt, "Enter the forge")
	assert_eq(tr(caption.text), "Forge")
	var chronicle_door := village.get_node("Buildings/Chronicle/Door") as Interactable
	assert_string_contains(chronicle_door.prompt, "Opens after your first run", "locked door in English")
	Loc.apply(&"de")
	await wait_physics_frames(1)
	assert_eq(door.prompt, "Schmiede betreten")


func _button_texts(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node == null:
		return result
	for child in node.find_children("*", "Button", true, false):
		result.append((child as Button).text)
	return result


func _trap_hit(tags: Array[StringName]) -> DamageData:
	var damage := DamageData.new()
	damage.amount = 1.0
	damage.tags.assign(tags)
	return damage
