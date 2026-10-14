class_name UiCard
extends PanelContainer
## Clickable panel card of the dungeon menu kit (upgrade, shop offer, weapon slot). Normal = panel,
## focused = panel_gold. Hovering focuses the card (focus_requested); a left click releases
## "pressed". The owner decides what focus and pressed mean.
## Blocked cards (disabled = true: too little gold, at the limit, sold) stay fully visible (UX2: no
## half transparency); the owner shows why with a badge (UiChip.badge). Clicks and number keys on
## a blocked card answer with UiSound.error and a short shake instead of silence.

signal pressed
## Emitted on mouse enter so the owner can move the focus here.
signal focus_requested
## A click or key on a blocked card (the error sound and shake already happened).
signal rejected

## Shake on a rejected click: amplitude in mockup pixels and duration (TESTWERTE, optics only).
const SHAKE_AMPLITUDE := 2.0
const SHAKE_TIME := 0.18

## Panel kinds (UiKit.panel_style) for the two states.
var normal_kind := &"normal"
var focused_kind := &"gold"
## Content padding in mockup pixels (vertical, horizontal).
var padding := Vector2(6, 8)
## Blocked: no pressed, no gold focus; the card itself is drawn as usual.
var disabled := false:
	set(value):
		disabled = value
		_refresh()
var focused := false:
	set(value):
		focused = value
		_refresh()

var _pressing := false
var _shake: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(func() -> void: _pressing = false)


func _ready() -> void:
	_refresh()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if disabled:
		if click.pressed:
			reject()
		return
	if click.pressed:
		_pressing = true
	elif _pressing:
		_pressing = false
		activate()


## Same as a click (also used by number keys / Enter). Blocked cards reject instead.
func activate() -> void:
	if disabled:
		reject()
		return
	Sfx.play_ui(self, &"ui_click")
	pressed.emit()


## "Not possible": error sound and a short sideways shake (works while the game is paused).
func reject() -> void:
	UiSound.error(self)
	rejected.emit()
	if not is_inside_tree():
		return
	if _shake != null and _shake.is_valid():
		_shake.kill()
	var amplitude := UiKit.px(SHAKE_AMPLITUDE)
	var base_x := position.x
	_shake = create_tween().set_ignore_time_scale(true)
	var step := SHAKE_TIME / 4.0
	_shake.tween_property(self, "position:x", base_x + amplitude, step)
	_shake.tween_property(self, "position:x", base_x - amplitude, step)
	_shake.tween_property(self, "position:x", base_x + amplitude * 0.5, step)
	_shake.tween_property(self, "position:x", base_x, step)


func _on_mouse_entered() -> void:
	if not disabled:
		if not focused:
			UiSound.hover(self)
		focus_requested.emit()


func _refresh() -> void:
	var kind := focused_kind if focused and not disabled else normal_kind
	add_theme_stylebox_override("panel", UiKit.padded_style(kind, padding.x, padding.y))
