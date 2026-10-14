class_name UiSound
extends RefCounted
## Names and volumes of the UI sounds (UX1, audio/sfx/ui_*.wav from tools/generate_audio.py), so all
## menus sound the same. Everything goes through Sfx.play_ui (bus SFX, keeps playing while paused).
## Missing files are silent (Sfx returns quietly), so a menu never breaks because of audio.

const CLICK: StringName = &"ui_click"
const OPEN: StringName = &"ui_open"
## Closing a panel or dialog without choosing (Esc, "Zurück").
const BACK: StringName = &"ui_back"
## Switch / segmented choice / checkbox.
const TOGGLE: StringName = &"ui_toggle"
## Not possible: disabled button, locked entry, too little gold.
const ERROR: StringName = &"ui_error"
## Something was created or confirmed for good (new save slot).
const CONFIRM: StringName = &"ui_confirm"
## Something was removed for good (save slot deleted).
const DELETE: StringName = &"ui_delete"
## Typing: ui_type_1 .. ui_type_<TYPE_VARIANTS> (slightly different pitches), deleting a character.
const TYPE_PREFIX := "ui_type_"
const TYPE_VARIANTS := 4
const TYPE_DELETE: StringName = &"ui_type_delete"

## Volumes in dB (TESTWERTE): hover ticks and typing stay well under clicks.
const HOVER_DB := -12.0
const STEP_DB := -8.0
const TYPE_DB := -6.0
const BACK_DB := -3.0
const ERROR_DB := -4.0

static var _last_type_variant := -1


static func play(context: Node, sound: StringName, volume_db := 0.0) -> void:
	Sfx.play_ui(context, sound, volume_db)


static func click(context: Node) -> void:
	Sfx.play_ui(context, CLICK)


## Soft tick when the pointer or the keyboard moves to another entry.
static func hover(context: Node) -> void:
	Sfx.play_ui(context, CLICK, HOVER_DB)


## Slider or list step with the keyboard.
static func step(context: Node) -> void:
	Sfx.play_ui(context, CLICK, STEP_DB)


static func back(context: Node) -> void:
	Sfx.play_ui(context, BACK, BACK_DB)


static func toggle(context: Node) -> void:
	Sfx.play_ui(context, TOGGLE)


static func error(context: Node) -> void:
	Sfx.play_ui(context, ERROR, ERROR_DB)


## One key stroke in a text field: a random variant (never the same twice in a row, so fast typing
## is not cut off by Sfx.MIN_INTERVAL_MS), or the delete sound.
static func type_key(context: Node, deleting := false) -> void:
	if deleting:
		Sfx.play_ui(context, TYPE_DELETE, TYPE_DB)
		return
	# randi() only picks a sound variant (optics/audio, not gameplay).
	var variant := randi() % TYPE_VARIANTS
	if variant == _last_type_variant:
		variant = (variant + 1) % TYPE_VARIANTS
	_last_type_variant = variant
	Sfx.play_ui(context, StringName(TYPE_PREFIX + str(variant + 1)), TYPE_DB)
