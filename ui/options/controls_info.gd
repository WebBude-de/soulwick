class_name ControlsInfo
extends RefCounted
## The game's controls for players (UX1): captions as translation keys (D-111, Loc) plus key names
## read from the InputMap, so a later rebinding shows the right keys. Used by the controls page of
## the options and by the first-run hint in the dungeon (ControlsHint). caption(), note() and
## key_text() return the text in the current language; rebuild them on
## NOTIFICATION_TRANSLATION_CHANGED.

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

## id -> [caption key, note key ("" = none), actions]. Order = order on the controls page.
const ENTRIES: Array[Array] = [
	[MOVE, &"CONTROLS_MOVE", &"", [&"move_up", &"move_left", &"move_down", &"move_right"]],
	[AIM, &"CONTROLS_AIM", &"CONTROLS_AIM_NOTE", []],
	[ATTACK, &"CONTROLS_ATTACK", &"CONTROLS_ATTACK_NOTE", [&"attack"]],
	[DASH, &"CONTROLS_DASH", &"CONTROLS_DASH_NOTE", [&"dash"]],
	[SPECIAL, &"CONTROLS_SPECIAL", &"CONTROLS_SPECIAL_NOTE", [&"special_attack"]],
	[SWITCH, &"CONTROLS_SWITCH", &"CONTROLS_SWITCH_NOTE", [&"switch_weapon"]],
	[INTERACT, &"CONTROLS_INTERACT", &"CONTROLS_INTERACT_NOTE", [&"interact"]],
	[OVERVIEW, &"CONTROLS_OVERVIEW", &"CONTROLS_OVERVIEW_NOTE", [&"upgrade_overview"]],
	[PAUSE, &"CONTROLS_PAUSE", &"", [&"pause_menu"]],
	[CHOICE, &"CONTROLS_CHOICE", &"CONTROLS_CHOICE_NOTE", []],
]
## Key texts for entries without an action (translation key or plain text).
const FIXED_KEYS := {AIM: &"KEY_MOUSE", CHOICE: "1 – 3"}
## Engine key names -> translation key or plain text (arrows and Esc/Enter read the same everywhere).
const KEY_NAMES := {
	"Space": &"KEY_SPACE", "Escape": "Esc", "Shift": &"KEY_SHIFT", "Ctrl": &"KEY_CTRL", "Enter": "Enter",
	"Kp Enter": "Enter", "Backspace": &"KEY_BACKSPACE", "Delete": &"KEY_DELETE", "Up": "↑", "Down": "↓",
	"Left": "←", "Right": "→",
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: &"KEY_MOUSE_LEFT",
	MOUSE_BUTTON_RIGHT: &"KEY_MOUSE_RIGHT",
	MOUSE_BUTTON_MIDDLE: &"KEY_MOUSE_MIDDLE",
}


static func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in ENTRIES:
		ids.append(entry[0])
	return ids


## Caption in the current language ("Bewegen" / "Move").
static func caption(id: StringName) -> String:
	var entry := _entry(id)
	return Loc.t(entry[1]) if not entry.is_empty() else ""


static func caption_key(id: StringName) -> StringName:
	var entry := _entry(id)
	return entry[1] if not entry.is_empty() else &""


## Short note in the current language ("" when the entry has none).
static func note(id: StringName) -> String:
	var entry := _entry(id)
	if entry.is_empty() or String(entry[2]).is_empty():
		return ""
	return Loc.t(entry[2])


static func actions(id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var entry := _entry(id)
	if not entry.is_empty():
		result.assign(entry[3])
	return result


## Key text of an entry, e.g. "W A S D", "Leertaste", "Linksklick".
static func key_text(id: StringName) -> String:
	if FIXED_KEYS.has(id):
		return _text(FIXED_KEYS[id])
	var names: PackedStringArray = []
	for action in actions(id):
		var name := action_key(action)
		if not name.is_empty() and not names.has(name):
			names.append(name)
	return " ".join(names)


## First bound key or mouse button of an action, in the current language ("" when unbound).
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
		if MOUSE_NAMES.has(mouse.button_index):
			return _text(MOUSE_NAMES[mouse.button_index])
		return Loc.t(&"KEY_MOUSE_BUTTON", [mouse.button_index])
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
	return _text(KEY_NAMES.get(name, name))


## A table value: translation keys (StringName) are translated, plain strings pass through.
static func _text(value: Variant) -> String:
	if value is StringName:
		return Loc.t(value)
	return String(value)


static func _entry(id: StringName) -> Array:
	for entry in ENTRIES:
		if entry[0] == id:
			return entry
	return []
