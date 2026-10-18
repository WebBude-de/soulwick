class_name Loc
extends RefCounted
## Game languages (D-111, UX3): English is the default, German the second language. The texts live
## in localization/translations.csv (columns keys,en,de); Godot's import writes one
## translations.<lang>.translation per column next to it. install() registers both at runtime with
## the TranslationServer (project.godot stays untouched, D-044 keeps the four autoloads), apply()
## sets the locale from the player's option ("auto", "en", "de"; GameOptions.LANGUAGE).
##
## Texts in the scene tree: give Label/Button the key as text, Godot translates it and re-translates
## on NOTIFICATION_TRANSLATION_CHANGED. Texts with format arguments: tr(key) % args in a node, or
## Loc.t(key, args) anywhere; rebuild them in _notification(NOTIFICATION_TRANSLATION_CHANGED).
## Without the imported .translation files (fresh checkout before --import) the CSV is read directly.

const LANGUAGES: Array[StringName] = [&"en", &"de"]
const DEFAULT_LANGUAGE: StringName = &"en"
## Option value: take the system language (German -> de, everything else -> en).
const AUTO: StringName = &"auto"
const CSV_PATH := "res://localization/translations.csv"
const TRANSLATION_PATH := "res://localization/translations.%s.translation"

static var _installed := false
## Replaces OS.get_locale_language() for "auto" when set (tests/gut_pre_run.gd pins "de", so a test
## that resets the settings to "auto" still gets German on an English system).
static var system_language_override := ""


## Registers the translations once (idempotent). Called by apply() and t(), so it is safe to call early.
static func install() -> void:
	if _installed:
		return
	_installed = true
	var from_csv: Dictionary = {}
	for language in LANGUAGES:
		var path := TRANSLATION_PATH % language
		var translation: Translation = null
		if ResourceLoader.exists(path):
			translation = load(path) as Translation
		if translation == null:
			if from_csv.is_empty():
				from_csv = load_csv(CSV_PATH)
			translation = from_csv.get(language, null)
		if translation == null:
			push_warning("Loc: no translation for '%s' (run godot --import)." % language)
			continue
		TranslationServer.add_translation(translation)


## Applies a language option ("auto", "en", "de") to the TranslationServer. Changing the locale
## sends NOTIFICATION_TRANSLATION_CHANGED to every node, so open menus update at once.
static func apply(language: StringName) -> void:
	install()
	TranslationServer.set_locale(String(resolve(language)))


## The locale for an option value. system_language replaces OS.get_locale_language() (tests).
static func resolve(language: StringName, system_language := "") -> StringName:
	if LANGUAGES.has(language):
		return language
	var detected := system_language
	if detected.is_empty():
		detected = system_language_override if not system_language_override.is_empty() else OS.get_locale_language()
	return &"de" if detected == "de" else DEFAULT_LANGUAGE


## Language currently shown ("en" or "de"), whatever the option says.
static func current_language() -> StringName:
	var locale := TranslationServer.get_locale()
	for language in LANGUAGES:
		if locale == String(language) or locale.begins_with(String(language) + "_"):
			return language
	return DEFAULT_LANGUAGE


## Translated text of a key, formatted with args ("%d / %d used" % [1, 3]). Unknown keys come back
## unchanged, so a missing entry shows the key instead of nothing.
static func t(key: StringName, args: Array = []) -> String:
	install()
	var text := String(TranslationServer.translate(key))
	return text % args if not args.is_empty() else text


## true if the key has a text in the given language (tests, tools).
static func has_key(key: StringName, language: StringName = DEFAULT_LANGUAGE) -> bool:
	install()
	var translation := TranslationServer.get_translation_object(String(language))
	return translation != null and not String(translation.get_message(key)).is_empty()


## Reads a Godot translation CSV (first column keys, header row = locales) into
## {locale: Translation}. Backslash escapes are unescaped like Godot's importer does ("\n").
static func load_csv(path: String) -> Dictionary:
	var result: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var header := file.get_csv_line()
	if header.size() < 2:
		return result
	var locales: Array[String] = []
	for i in range(1, header.size()):
		var locale := header[i].strip_edges()
		locales.append(locale)
		var translation := Translation.new()
		translation.locale = locale
		result[StringName(locale)] = translation
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.is_empty() or line[0].strip_edges().is_empty():
			continue
		for i in locales.size():
			var text := line[i + 1].c_unescape() if i + 1 < line.size() else ""
			(result[StringName(locales[i])] as Translation).add_message(StringName(line[0].strip_edges()), text)
	return result
