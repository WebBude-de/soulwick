class_name DevFeedbackTexts
extends RefCounted
## Player-facing texts of the bug report tool (DevFeedback, overlay, toasts; D-111). Every text is
## a translation key with an English and a German fallback, looked up like Hud.hud_text: while a
## key is missing in localization/translations.csv the fallback of the current language is shown.
## TEXTS is the list to copy into the CSV (key, en, de).

const TEXTS := {
	&"BUG_REPORT_TITLE": ["REPORT A BUG", "FEHLER MELDEN"],
	&"BUG_REPORT_HINT_DESKTOP": [
		"Game paused · Drag: mark an area · Shift+drag: draw a line · Right-click: remove · Key # or F9",
		"Spiel pausiert · Ziehen: Bereich markieren · Umschalt+Ziehen: Strich · Rechtsklick: entfernen · Taste # oder F9",
	],
	&"BUG_REPORT_HINT_TOUCH": [
		"Game paused · Drag: mark an area · Long press: remove",
		"Spiel pausiert · Ziehen: Bereich markieren · Lange drücken: entfernen",
	],
	&"BUG_REPORT_CATEGORY": ["Category:", "Kategorie:"],
	&"BUG_REPORT_CAT_UI": ["UI", "UI"],
	&"BUG_REPORT_CAT_GRAPHICS": ["Graphics", "Grafik"],
	&"BUG_REPORT_CAT_LIGHT": ["Light", "Licht"],
	&"BUG_REPORT_CAT_LAYOUT": ["Room/Layout", "Raum/Layout"],
	&"BUG_REPORT_CAT_GAMEPLAY": ["Gameplay", "Gameplay"],
	&"BUG_REPORT_CAT_BUG": ["Bug", "Bug"],
	&"BUG_REPORT_CAT_TEXT": ["Text", "Text"],
	&"BUG_REPORT_SHORTCUTS": ["Ctrl+Enter: send · Esc: cancel", "Strg+Enter: senden · Esc: abbrechen"],
	&"BUG_REPORT_NOTE_PLACEHOLDER": ["What is wrong here? (note, several lines)", "Was stimmt hier nicht? (Notiz, mehrzeilig)"],
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
	&"BUG_REPORT_SENT": ["Report sent", "Meldung gesendet"],
	&"BUG_REPORT_SAVE_FAILED": ["Could not save the report", "Meldung konnte nicht gespeichert werden"],
}

## Category key (API contract BugReportCategory, note.json) -> text key.
const CATEGORY_TEXT := {
	"ui": &"BUG_REPORT_CAT_UI",
	"graphics": &"BUG_REPORT_CAT_GRAPHICS",
	"light": &"BUG_REPORT_CAT_LIGHT",
	"layout": &"BUG_REPORT_CAT_LAYOUT",
	"gameplay": &"BUG_REPORT_CAT_GAMEPLAY",
	"bug": &"BUG_REPORT_CAT_BUG",
	"text": &"BUG_REPORT_CAT_TEXT",
}


## The text of key in the current language (CSV first, then the fallback of TEXTS).
static func t(key: StringName) -> String:
	var pair: Array = TEXTS.get(key, [String(key), String(key)])
	var fallback := str(pair[1]) if Loc.current_language() == &"de" else str(pair[0])
	return DataTexts.text_or(key, fallback)


static func category_label(category: String) -> String:
	return t(CATEGORY_TEXT[category]) if CATEGORY_TEXT.has(category) else category
