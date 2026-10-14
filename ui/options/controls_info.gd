class_name ControlsInfo
extends RefCounted
## The game's controls for players (UX1): German captions plus key names read from the InputMap,
## so a later rebinding shows the right keys. Used by the controls page of the options and by the
## first-run hint in the dungeon (ControlsHint).

## Entry ids (also the ids of the first-run hint rows).
const MOVE: StringName = &"move"
const AIM: StringName = &"aim"
const ATTACK: StringName = &"attack"
const DASH: StringName = &"dash"
const SPECIAL: StringName = &"special"
const SWITCH: StringName = &"switch"
const INTERACT: StringName = &"interact"
const OVERVIEW: StringName = &"overview"
const PAUSE: StringName = &"pause"
const CHOICE: StringName = &"choice"

## id -> [caption, short note, actions]. Order = order on the controls page.
const ENTRIES: Array[Array] = [
	[MOVE, "Bewegen", "", [&"move_up", &"move_left", &"move_down", &"move_right"]],
	[AIM, "Zielen", "Waffe zeigt zur Maus", []],
	[ATTACK, "Angreifen", "halten = Dauerangriff", [&"attack"]],
	[DASH, "Dash", "kurz unverwundbar", [&"dash"]],
	[SPECIAL, "Spezialangriff", "eigene Abklingzeit", [&"special_attack"]],
	[SWITCH, "Waffe wechseln", "bei zwei Waffen", [&"switch_weapon"]],
	[INTERACT, "Benutzen", "Händler, Altar, Portal", [&"interact"]],
	[OVERVIEW, "Upgrades und Werte", "pausiert", [&"upgrade_overview"]],
	[PAUSE, "Pause und Optionen", "", [&"pause_menu"]],
	[CHOICE, "Auswahl im Dialog", "Enter bestätigt", []],
]
## Key texts for entries without an action.
const FIXED_KEYS := {AIM: "Maus", CHOICE: "1 – 3"}
## Engine key names -> German.
const KEY_NAMES := {
	"Space": "Leertaste", "Escape": "Esc", "Shift": "Umschalt", "Ctrl": "Strg", "Enter": "Enter",
	"Kp Enter": "Enter", "Backspace": "Rücktaste", "Delete": "Entf", "Up": "↑", "Down": "↓",
	"Left": "←", "Right": "→",
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Linksklick",
	MOUSE_BUTTON_RIGHT: "Rechtsklick",
	MOUSE_BUTTON_MIDDLE: "Mausrad",
}


static func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in ENTRIES:
		ids.append(entry[0])
	return ids


static func caption(id: StringName) -> String:
	var entry := _entry(id)
	return entry[1] if not entry.is_empty() else ""


static func note(id: StringName) -> String:
	var entry := _entry(id)
	return entry[2] if not entry.is_empty() else ""


static func actions(id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var entry := _entry(id)
	if not entry.is_empty():
		result.assign(entry[3])
	return result


## Key text of an entry, e.g. "W A S D", "Leertaste", "Linksklick".
static func key_text(id: StringName) -> String:
	if FIXED_KEYS.has(id):
		return FIXED_KEYS[id]
	var names: PackedStringArray = []
	for action in actions(id):
		var name := action_key(action)
		if not name.is_empty() and not names.has(name):
			names.append(name)
	return " ".join(names)


## First bound key or mouse button of an action, in German ("" when unbound).
static func action_key(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		var text := event_text(event)
		if not text.is_empty():
			return text
	return ""


static func event_text(event: InputEvent) -> String:
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return MOUSE_NAMES.get(mouse.button_index, "Maustaste %d" % mouse.button_index)
	var key := event as InputEventKey
	if key == null:
		return ""
	var code := key.keycode
	if code == KEY_NONE and key.physical_keycode != KEY_NONE:
		code = key.physical_keycode
		# Physical bindings: show the letter of the player's keyboard layout (QWERTZ, AZERTY …).
		# The headless display server (tests, tools) has no keyboard layout.
		if DisplayServer.get_name() != "headless":
			var local := DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			if local != KEY_NONE:
				code = local
	var name := OS.get_keycode_string(code)
	return KEY_NAMES.get(name, name)


static func _entry(id: StringName) -> Array:
	for entry in ENTRIES:
		if entry[0] == id:
			return entry
	return []
