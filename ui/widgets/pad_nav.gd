extends RefCounted
## Gamepad key symbols of the menus (P0-2 step 2): which button picture a shown key name ("Enter",
## "Esc", "←→", "Tab") stands for while a gamepad is in use, and key lines with button pictures.
## Gamepad texts are translation keys with tokens for the buttons ("{dpad} wählen · {a} los ·
## {b} zurück"); fill() puts the pictures (InputGlyphs, from the current binding) in their place.
## Use: const PadNav := preload("res://ui/widgets/pad_nav.gd") (no class_name: new scripts are
## loaded by path until the next --import).

## Token -> [action whose gamepad binding is shown, fallback glyph when the action has none].
const TOKENS := {
	"a": [&"ui_accept", InputGlyphs.PAD_SOUTH],
	"b": [&"ui_cancel", InputGlyphs.PAD_EAST],
	"x": [&"interact", InputGlyphs.PAD_WEST],
	"y": [&"switch_weapon", InputGlyphs.PAD_NORTH],
	"start": [&"pause_menu", InputGlyphs.PAD_START],
	"back": [&"upgrade_overview", InputGlyphs.PAD_SELECT],
	"dpad": [&"", InputGlyphs.PAD_DPAD],
	"lb": [&"", InputGlyphs.PAD_LB],
	"rb": [&"", InputGlyphs.PAD_RB],
}
## Key names of arrow hints: on a gamepad the D-pad (and the left stick) moves.
const ARROW_NAMES: Array[String] = ["←→", "↑↓", "←→↑↓", "↑↓←→", "Pfeile", "Arrows"]


## Short names of gamepad buttons for plain-text places (Labels without pictures).
const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad", JOY_BUTTON_DPAD_DOWN: "D-Pad", JOY_BUTTON_DPAD_LEFT: "D-Pad", JOY_BUTTON_DPAD_RIGHT: "D-Pad",
}
const PAD_AXIS_NAMES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}


## Plain-text key of an action for the device in use: the gamepad button ("X") while a gamepad is
## in use, else the bound key ("E"). Hook for text-only prompts (the interaction prompt over the
## player's head, player.gd).
static func key_name(action: StringName) -> String:
	if is_pad() and InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			var button := event as InputEventJoypadButton
			if button != null and PAD_BUTTON_NAMES.has(button.button_index):
				return PAD_BUTTON_NAMES[button.button_index]
			var motion := event as InputEventJoypadMotion
			if motion != null and PAD_AXIS_NAMES.has(motion.axis):
				return PAD_AXIS_NAMES[motion.axis]
	var key := InputGlyphs.first_event(action, false)
	return InputGlyphs.cap_text(key) if key != null else ""


## Gamepad in use on this machine (InputGlyphs: the touch controls win).
static func is_pad() -> bool:
	return InputGlyphs.is_gamepad()


## Glyph of a token ("a", "dpad" …), "" for unknown tokens.
static func token_glyph(token: String) -> StringName:
	if not TOKENS.has(token):
		return &""
	var entry: Array = TOKENS[token]
	var action: StringName = entry[0]
	if action != &"":
		var bound := InputGlyphs.pad_id_for_action(action)
		if bound != &"":
			return bound
	return entry[1]


## Gamepad glyph of a shown key name while the gamepad is in use ("" = none: the name has no
## gamepad button, e.g. "1–3", "N", or the gamepad is not in use).
static func glyph_for_key(key_name: String) -> StringName:
	if not is_pad():
		return &""
	var text := key_name.strip_edges()
	if ARROW_NAMES.has(text):
		return InputGlyphs.PAD_DPAD
	return InputGlyphs.pad_id_for_name(text)


## Text cut into strings and glyph textures: every "{token}" becomes its button picture.
static func split(text: String) -> Array:
	var parts: Array = []
	var regex := RegEx.create_from_string("\\{([a-z]+)\\}")
	var at := 0
	for found in regex.search_all(text):
		var glyph := token_glyph(found.get_string(1))
		if glyph == &"":
			continue
		if found.get_start() > at:
			parts.append(text.substr(at, found.get_start() - at))
		parts.append(InputGlyphs.texture(glyph))
		at = found.get_end()
	if at < text.length():
		parts.append(text.substr(at))
	return parts


## Fills a RichTextLabel with text, tokens as pictures at pixel screen pixels per art pixel.
static func fill(label: RichTextLabel, text: String, pixel: int, alignment := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	label.clear()
	label.push_paragraph(alignment)
	for part: Variant in split(text):
		if part is Texture2D:
			var texture := part as Texture2D
			label.add_image(texture, texture.get_width() * pixel, texture.get_height() * pixel, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		else:
			label.add_text(String(part))
	label.pop()


## For menus that move with Godot's GUI focus (OnlineMenu): call from _input of a node above them.
## D-pad and left stick events are taken here, debounced (MenuInput), and moved one focus step
## inside root; Godot's own focus move would step on every motion event of the stick. Returns true
## when the event was used (the caller sets it as handled). Without a focus in root the event goes
## on, so the menu can give the focus to its default control.
static func step_gui_focus(event: InputEvent, root: Control) -> bool:
	if not MenuInput.is_pad_direction_event(event) or not root.is_visible_in_tree():
		return false
	var focused := root.get_viewport().gui_get_focus_owner()
	if focused == null or not root.is_ancestor_of(focused):
		return false
	var step := MenuInput.direction(event)
	if step == Vector2i.ZERO:
		# Stick bounce or a released D-pad: no step, and Godot must not step either.
		return true
	if focused is LineEdit and step.x != 0:
		# Left/right move the caret in a text field.
		return false
	var sides := {Vector2i.UP: SIDE_TOP, Vector2i.DOWN: SIDE_BOTTOM, Vector2i.LEFT: SIDE_LEFT, Vector2i.RIGHT: SIDE_RIGHT}
	var next := focused.find_valid_focus_neighbor(sides[step])
	if next != null and root.is_ancestor_of(next):
		next.grab_focus()
	return true


## Translated text of key formatted with args; fallback (the English text) while the key is not
## imported yet (new keys before godot --import), never a formatting error on a bare key.
static func text(key: StringName, args: Array = [], fallback := "") -> String:
	Loc.install()
	var result := String(TranslationServer.translate(key))
	if result == String(key) and not fallback.is_empty():
		result = fallback
	if args.is_empty() or not result.contains("%"):
		return result
	return result % args


## The text without its tokens' pictures ("{a} los" -> "A los"), e.g. for tools and tests.
static func plain(text: String) -> String:
	var regex := RegEx.create_from_string("\\{([a-z]+)\\}")
	return regex.sub(text, "[$1]", true)
