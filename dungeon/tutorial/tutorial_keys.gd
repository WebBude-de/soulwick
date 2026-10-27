class_name TutorialKeys
extends RefCounted
## Key symbols of the practice run per input device (WK10): the shared input symbols (InputGlyphs,
## KeyCap) for keyboard and mouse, the gamepad in use, or the touch buttons (in the side view the
## dash button is the jump button). Flint's bubble is plain text, so the keys stand on the station
## signs in the world (TutorialSign, TutorialShortcut), never in an overlay over the playfield; the
## signs rebuild their caps on InputDevice.shared().changed.

## Cap of an action for the device in use (side_view: the jump of a side segment).
static func cap(action: StringName, side_view := false, scale := KeyCap.HUD_PIXEL) -> KeyCap:
	if InputGlyphs.is_touch():
		var touch := InputGlyphs.touch_id_for_action(action, side_view)
		if touch != &"":
			return KeyCap.for_name(String(touch), scale)
	return KeyCap.for_action(action, scale)
