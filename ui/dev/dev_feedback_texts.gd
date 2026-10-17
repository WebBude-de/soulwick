class_name DevFeedbackTexts
extends RefCounted
## Player-facing texts of the bug report tool (DevFeedback, overlay, toasts; D-111). Every text is
## a translation key with an English and a German fallback, looked up like Hud.hud_text: while a
## key is missing in localization/translations.csv the fallback of the current language is shown.
## TEXTS is the list to copy into the CSV (key, en, de). The report has two kinds (tabs): "bug" (default)
## and "idea"; there are no categories any more (17.10.2026).

const TEXTS := {
	&"BUG_REPORT_TITLE": ["REPORT A BUG", "FEHLER MELDEN"],
	# {open}: the keyboard shortcut (shortcut_hint), "Ctrl + B" / "Strg + B", "Cmd + B" on macOS.
	&"BUG_REPORT_HINT_KEYBOARD": [
		"Game paused · Drag: mark an area · Shift+drag: draw a line · Right-click: remove · Open with {open} or Select + Start",
		"Spiel pausiert · Ziehen: Bereich markieren · Umschalt+Ziehen: Strich · Rechtsklick: entfernen · Öffnen mit {open} oder Select + Start",
	],
	&"BUG_REPORT_KEY_CTRL": ["Ctrl", "Strg"],
	&"BUG_REPORT_HINT_TOUCH": [
		"Game paused · Drag: mark an area · Long press: remove",
		"Spiel pausiert · Ziehen: Bereich markieren · Lange drücken: entfernen",
	],
	&"BUG_REPORT_TAB_BUG": ["Report a bug", "Fehler melden"],
	&"BUG_REPORT_TAB_IDEA": ["Suggest an idea", "Idee einreichen"],
	&"BUG_REPORT_TITLE_IDEA": ["SUGGEST AN IDEA", "IDEE EINREICHEN"],
	&"BUG_REPORT_KEYS_DESKTOP": ["Ctrl+Enter: send · Ctrl+Tab: switch tab · Esc: cancel", "Strg+Enter: senden · Strg+Tab: Reiter wechseln · Esc: abbrechen"],
	&"BUG_REPORT_KEYS_PAD": ["LB/RB: switch tab · Start: send · B: cancel", "LB/RB: Reiter wechseln · Start: senden · B: abbrechen"],
	&"BUG_REPORT_NOTE_BUG": ["What is broken? (note, several lines)", "Was ist kaputt? (Notiz, mehrzeilig)"],
	&"BUG_REPORT_NOTE_IDEA": ["What would you like to see? (note, several lines)", "Was wünschst du dir? (Notiz, mehrzeilig)"],
	&"BUG_REPORT_MARKS_EMPTY": ["No mark yet: drag a rectangle", "Noch keine Markierung: Rechteck aufziehen"],
	&"BUG_REPORT_MARKS_HINT": ["Note per mark (optional):", "Notiz je Markierung (optional):"],
	&"BUG_REPORT_MARK_PLACEHOLDER": ["short note on %d", "kurze Notiz zu %d"],
	&"BUG_REPORT_PANEL_UP": ["Panel to top", "Leiste nach oben"],
	&"BUG_REPORT_PANEL_DOWN": ["Panel to bottom", "Leiste nach unten"],
	&"BUG_REPORT_CANCEL": ["Cancel", "Abbrechen"],
	&"BUG_REPORT_SEND": ["Send", "Senden"],
	&"BUG_REPORT_CONFIRM_DISCARD": ["Press Esc again to discard", "Nochmal Esc: Meldung verwerfen"],
	&"BUG_REPORT_MARK_REMOVED": ["Mark removed", "Markierung entfernt"],
	&"BUG_REPORT_PRIVACY": [
		"Screenshot, note and game info are sent to the developer team.",
		"Screenshot, Notiz und Spielinfos werden an das Entwicklerteam geschickt.",
	],
	&"BUG_REPORT_CONSENT_TITLE": ["Before you send", "Bevor du sendest"],
	&"BUG_REPORT_CONSENT_TEXT": [
		"Your report (screenshot, note and game info such as place, version and platform) goes to the developer team with your player account. It is kept for 90 days and deleted with your account. Nothing else is sent.",
		"Deine Meldung (Screenshot, Notiz und Spielinfos wie Ort, Version und Plattform) geht mit deinem Spielerkonto an das Entwicklerteam. Sie wird 90 Tage aufbewahrt und mit deinem Konto gelöscht. Sonst wird nichts geschickt.",
	],
	&"BUG_REPORT_CONSENT_OK": ["Agree and send", "Einverstanden, senden"],
	&"BUG_REPORT_CONSENT_BACK": ["Back", "Zurück"],
	&"BUG_REPORT_SAVED": ["Thanks! Report saved", "Danke! Meldung gespeichert"],
	&"BUG_REPORT_SAVED_IDEA": ["Thanks! Idea saved", "Danke! Idee gespeichert"],
	&"BUG_REPORT_SENT": ["Report sent", "Meldung gesendet"],
	&"BUG_REPORT_SAVE_FAILED": ["Could not save the report", "Meldung konnte nicht gespeichert werden"],
}

## Kind of report (contract field `kind`) -> tab text, overlay title and note placeholder.
const KIND_TEXT := {
	"bug": [&"BUG_REPORT_TAB_BUG", &"BUG_REPORT_TITLE", &"BUG_REPORT_NOTE_BUG", &"BUG_REPORT_SAVED"],
	"idea": [&"BUG_REPORT_TAB_IDEA", &"BUG_REPORT_TITLE_IDEA", &"BUG_REPORT_NOTE_IDEA", &"BUG_REPORT_SAVED_IDEA"],
}


## The text of key in the current language (CSV first, then the fallback of TEXTS).
static func t(key: StringName) -> String:
	var pair: Array = TEXTS.get(key, [String(key), String(key)])
	var fallback := str(pair[1]) if Loc.current_language() == &"de" else str(pair[0])
	return DataTexts.text_or(key, fallback)


## Hint line of the overlay header: the phone one, or the desktop one naming the shortcuts.
static func hint(touch: bool) -> String:
	if touch:
		return t(&"BUG_REPORT_HINT_TOUCH")
	return t(&"BUG_REPORT_HINT_KEYBOARD").replace("{open}", shortcut_hint())


## "Strg + B" / "Ctrl + B" in the current language, "Cmd + B" on macOS.
static func shortcut_hint() -> String:
	return DevFeedback.shortcut_text(t(&"BUG_REPORT_KEY_CTRL"))


## part: 0 tab, 1 title, 2 note placeholder, 3 "saved" toast; unknown kinds read as "bug".
static func kind_text(kind: String, part: int) -> String:
	var keys: Array = KIND_TEXT.get(kind, KIND_TEXT["bug"])
	return t(keys[clampi(part, 0, keys.size() - 1)])
