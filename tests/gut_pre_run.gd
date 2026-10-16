extends GutHookScript
## GUT pre-run hook (.gutconfig.json "pre_run_script"): the tests read German texts, whatever the
## system language of the machine is. The language option "auto" follows OS.get_locale_language()
## (Loc.resolve), so on an English PC or a Linux runner without LANG=de_* many texts came back in
## English. Before the first test this hook points SaveManager's global settings at a fresh test
## file whose language option is "de" and applies it. Tests that remember and restore
## settings_path come back to this file, so a later GameOptions.apply_language() (main menu,
## world, options) stays German as well. Side effect: from here on the tests neither read nor
## write the real settings.cfg (AGENTS.md §6.4); the profile stays user://script_profile.cfg
## because the test file lies in the same folder as the real one.

const SETTINGS_PATH := "user://gut_settings.cfg"
const TEST_LANGUAGE: StringName = &"de"


func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	SaveManager.settings_path = SETTINGS_PATH
	SaveManager.load_settings()
	PlayerProfile.reset()
	GameOptions.set_language(TEST_LANGUAGE)
	if Loc.current_language() != TEST_LANGUAGE:
		gut.logger.error("gut_pre_run: test language is %s, expected %s." % [Loc.current_language(), TEST_LANGUAGE])
