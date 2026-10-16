extends GutTest
## English in the dungeon (P0-1, D-111): enemy, boss, biome and character data hold translation keys
## instead of German text, every key they and the code use (elite prefixes, champion and phase-two
## cards, curses, biome names) has English and German in localization/translations.csv, and names,
## hints, boss intros and curse texts follow the language. The CSV is registered directly (on top of
## the imported .translation files), so the test checks the CSV even before `godot --import`.

const ENEMY_DIR := "res://enemies/data"
const BIOME_DIR := "res://dungeon/biomes"
const CHARACTER_DIR := "res://characters"
## Same limits as test_boss_intro.gd, here checked in both languages.
const MAX_LINE_LENGTH := 42
const MIN_STORY_LINES := 4
const MAX_STORY_LINES := 7
const SKELETON := preload("res://enemies/data/skeleton.tres")

var _old_save_path: String
var _old_locale: String
var _csv: Dictionary = {}
var _key_re := RegEx.new()


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_i18n_dungeon_save.cfg"
	_old_locale = TranslationServer.get_locale()
	_key_re.compile("^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$")
	_csv = Loc.load_csv(Loc.CSV_PATH)
	Loc.install()
	for language in _csv:
		TranslationServer.add_translation(_csv[language])


func after_all() -> void:
	for language in _csv:
		TranslationServer.remove_translation(_csv[language])
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	Loc.apply(&"de")


# --- Data holds keys ---

func test_enemy_data_holds_keys_not_text() -> void:
	var count := 0
	for data: EnemyData in _load_all(ENEMY_DIR):
		count += 1
		for text in _enemy_texts(data):
			assert_true(_is_key(text), "%s: '%s' is a translation key" % [data.id, text])
		assert_false(data.display_name.is_empty(), "%s has a name" % data.id)
	assert_gt(count, 15, "all enemy data found")


func test_biome_and_character_data_hold_keys() -> void:
	var biomes := _load_all(BIOME_DIR)
	assert_eq(biomes.size(), RoomSequence.Biome.size(), "one BiomeData per biome")
	for biome: BiomeData in biomes:
		assert_true(_is_key(biome.display_name), "%s: '%s' is a key" % [biome.id, biome.display_name])
	for character in _load_all(CHARACTER_DIR):
		var data := character as CharacterData
		if data == null:
			continue
		for color_name in data.color_names:
			assert_true(_is_key(color_name), "%s: colour '%s' is a key" % [data.id, color_name])


func test_every_used_key_has_english_and_german() -> void:
	var keys := _used_keys()
	assert_gt(keys.size(), 80, "keys collected")
	for key in keys:
		for language in Loc.LANGUAGES:
			var translation: Translation = _csv.get(language, null)
			assert_not_null(translation, "CSV column %s" % language)
			if translation != null:
				assert_ne(String(translation.get_message(key)), "", "%s has %s text in translations.csv" % [key, language])


func test_biome_data_and_room_sequence_use_the_same_key() -> void:
	for biome: BiomeData in _load_all(BIOME_DIR):
		var index := RoomSequence.Biome.keys().find(String(biome.id).to_upper())
		assert_gte(index, 0, "%s is a RoomSequence.Biome" % biome.id)
		assert_eq(String(RoomSequence.get_biome_name_key(index)), biome.display_name, String(biome.id))


# --- Texts follow the language ---

func test_names_hints_and_curses_follow_the_language() -> void:
	Loc.apply(&"en")
	var entries := EnemyHints.get_entries(SKELETON, Enemy.Elite.VOLATILE, true)
	assert_eq(entries.size(), 3)
	assert_eq(entries[0]["title"], "Champion")
	assert_eq(entries[1]["title"], "Elite: Volatile")
	assert_eq(entries[2]["title"], "Skeleton")
	assert_false(String(entries[2]["text"]).begins_with("Skeleton"), "the name is stripped from the hint")
	assert_eq(EnemyHints.phase_two_entry()["title"], "Second Phase")
	assert_eq(RoomSequence.get_biome_name(RoomSequence.Biome.CRYPT), "Crypt")
	assert_eq(PlayerCurses.get_curse_name(PlayerCurses.Curse.GLOOM), "Gloom")
	assert_eq(PlayerCurses.get_curse_effect(PlayerCurses.Curse.HASTE), "Enemies +10 % speed")
	assert_eq(BossRules.boss_title("ENEMY_BOSS_SLIME_QUEEN_NAME", 1), "Slime Queen II")
	var enemy: Enemy = autofree(Enemy.new())
	enemy.data = SKELETON
	enemy.elite = Enemy.Elite.SWIFT
	assert_eq(enemy.get_display_name(), "Swift Skeleton")

	Loc.apply(&"de")
	assert_eq(EnemyHints.get_entries(SKELETON, Enemy.Elite.NONE, false)[0]["title"], "Skelett")
	assert_eq(RoomSequence.get_biome_name(RoomSequence.Biome.CRYPT), "Krypta")
	assert_eq(PlayerCurses.get_curse_effect(PlayerCurses.Curse.HASTE), "Gegner +10 % Tempo")
	assert_eq(enemy.get_display_name(), "Flink Skelett")
	var wick := load("res://characters/wick.tres") as CharacterData
	assert_eq(wick.get_color_name(5), "Türkis")


func test_every_hint_starts_with_its_name_in_both_languages() -> void:
	for language in Loc.LANGUAGES:
		Loc.apply(language)
		for data: EnemyData in _load_all(ENEMY_DIR):
			if data.hint.is_empty():
				continue
			var name := Loc.t(StringName(data.display_name))
			var hint := Loc.t(StringName(data.hint))
			assert_false(_is_key(name) or _is_key(hint), "%s/%s: translated" % [data.id, language])
			assert_true(hint.begins_with(name + ":"), "%s/%s: '%s' starts with '%s:'" % [data.id, language, hint, name])
			assert_ne(EnemyHints.strip_name(hint, name), hint, "%s/%s: the card strips the name" % [data.id, language])


func test_boss_intros_are_short_and_readable_in_both_languages() -> void:
	var digits := RegEx.new()
	digits.compile("[0-9]")
	for language in Loc.LANGUAGES:
		Loc.apply(language)
		for data: EnemyData in _load_all(ENEMY_DIR):
			if not data.is_boss:
				continue
			var story := BossIntroRules.story_lines(data)
			assert_between(story.size(), MIN_STORY_LINES, MAX_STORY_LINES, "%s/%s: story length" % [data.id, language])
			var lines := PackedStringArray(story)
			for tier in 4:
				for encounter in 5:
					var short := BossIntroRules.pick_lines(data, tier, false, encounter)
					assert_between(short.size(), 1, BossIntroRules.MAX_REPEAT_LINES, "%s/%s: 1-2 lines" % [data.id, language])
					var duration := BossIntroRules.total_duration(short, data.intro_type_speed)
					assert_between(duration, 2.5, 5.5, "%s/%s tier %d run %d: %.2f s" % [data.id, language, tier, encounter, duration])
					lines.append_array(short)
			for line in lines:
				assert_false(_is_key(line), "%s/%s: '%s' is translated" % [data.id, language, line])
				assert_lte(line.length(), MAX_LINE_LENGTH, "%s/%s: '%s' is short" % [data.id, language, line])
				assert_null(digits.search(line), "'%s' has no numbers" % line)
				assert_false(line.contains(BossIntroRules.LINE_SEPARATOR), "'%s' is split" % line)
			var phase_two := Loc.t(StringName(data.enrage_text))
			assert_false(_is_key(phase_two), "%s/%s: phase-two banner translated" % [data.id, language])


func test_story_differs_between_languages() -> void:
	var boss := load("res://enemies/data/boss_bone_king.tres") as EnemyData
	Loc.apply(&"en")
	var english := BossIntroRules.story_lines(boss)
	Loc.apply(&"de")
	var german := BossIntroRules.story_lines(boss)
	assert_eq(english.size(), german.size())
	assert_ne(english[0], german[0], "the story is translated")
	assert_eq(BossIntroRules.repeat_lines(boss, 0, 0).size(), 2, "a variant still splits into two lines after translation")


# --- Helpers ---

func _is_key(text: String) -> bool:
	return _key_re.search(text) != null


func _enemy_texts(data: EnemyData) -> PackedStringArray:
	var texts := PackedStringArray([data.display_name])
	for text in [data.hint, data.enrage_text]:
		if not String(text).is_empty():
			texts.append(text)
	texts.append_array(data.intro_story)
	texts.append_array(data.intro_lines)
	return texts


func _used_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for data: EnemyData in _load_all(ENEMY_DIR):
		for text in _enemy_texts(data):
			keys.append(StringName(text))
	for biome: BiomeData in _load_all(BIOME_DIR):
		keys.append(StringName(biome.display_name))
	for character in _load_all(CHARACTER_DIR):
		if character is CharacterData:
			for color_name in (character as CharacterData).color_names:
				keys.append(StringName(color_name))
	for biome in RoomSequence.Biome.size():
		keys.append(RoomSequence.get_biome_name_key(biome))
	for key in Enemy.ELITE_NAMES.values():
		keys.append(key)
	keys.append(Enemy.CHAMPION_LABEL_KEY)
	for key in EnemyHints.ELITE_HINTS.values():
		keys.append(key)
	for key in [EnemyHints.ELITE_TITLE, EnemyHints.CHAMPION_TITLE, EnemyHints.CHAMPION_TEXT,
			EnemyHints.PHASE_TWO_TITLE, EnemyHints.PHASE_TWO_TEXT]:
		keys.append(StringName(key))
	for key in PlayerCurses.NAME_KEYS.values() + PlayerCurses.EFFECT_KEYS.values():
		keys.append(key)
	return keys


func _load_all(dir_path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	for file in DirAccess.get_files_at(dir_path):
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var resource := load(dir_path.path_join(file_name))
			if resource != null:
				result.append(resource)
	return result
