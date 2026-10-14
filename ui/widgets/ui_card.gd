class_name UiCard
extends PanelContainer
## Clickable panel card of the dungeon menu kit (upgrade, shop offer, weapon slot). Normal = panel,
## focused = panel_gold. Hovering focuses the card (focus_requested); a left click releases
## "pressed". The owner decides what focus and pressed mean.
## Blocked cards (disabled = true: too little gold, at the limit, sold) stay fully visible (UX2: no
## half transparency); the owner shows why with a badge (UiChip.badge). Clicks and number keys on
## a blocked card answer with UiSound.error and a short shake instead of silence.
## R8 (more life): an accent colour (upgrade category, offer kind) runs as a band along the top
## inner edge; the focused card glows in it (soft pulse) and its symbol (symbol) does a small hop;
## a pick plays pick_sound and leaves a burst (UiKit.pick_burst) that outlasts the closing dialog.

signal pressed
## Emitted on mouse enter so the owner can move the focus here.
signal focus_requested
## A click or key on a blocked card (the error sound and shake already happened).
signal rejected

## Shake on a rejected click: amplitude in mockup pixels and duration (TESTWERTE, optics only).
const SHAKE_AMPLITUDE := 2.0
const SHAKE_TIME := 0.18
## Accent band on the top inner frame line: art pixels from the panel edge and its height in art
## pixels (panel.png: 3 px outer frame, then the inner line), and the glow of the focused card.
const FRAME_INSET := 3
const ACCENT_ROWS := 2
const GLOW_RINGS := 3
const GLOW_SPEED := 4.0
## Symbol hop when the card gets the focus (scale).
const HOP_SCALE := 1.18

## Panel kinds (UiKit.panel_style) for the two states.
var normal_kind := &"normal"
var focused_kind := &"gold"
## Content padding in mockup pixels (vertical, horizontal).
var padding := Vector2(6, 8)
## Accent band and glow colour (alpha 0 = none).
var accent := Color(0, 0, 0, 0):
	set(value):
		accent = value
		queue_redraw()
## The card's symbol: hops on focus, flies off on a pick (optional).
var symbol: Control = null
## Sound of a pick (UiSound / Sfx name).
var pick_sound: StringName = UiSound.CLICK
## Blocked: no pressed, no gold focus; the card itself is drawn as usual.
var disabled := false:
	set(value):
		disabled = value
		_refresh()
var focused := false:
	set(value):
		var gained := value and not focused
		focused = value
		_refresh()
		if gained:
			_hop()

var _pressing := false
var _shake: Tween = null
var _glow := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(func() -> void: _pressing = false)


func _ready() -> void:
	_refresh()


func _process(delta: float) -> void:
	if focused and not disabled and accent.a > 0.0:
		_glow += delta * GLOW_SPEED
		queue_redraw()


func _draw() -> void:
	if accent.a <= 0.0:
		return
	# The band replaces the inner frame line of the nine-patch (art rows 3-4 of panel.png).
	var inset := float(FRAME_INSET * UiKit.ART_SCALE)
	var band := Color(accent, 0.55 if disabled else 1.0)
	draw_rect(Rect2(inset, inset, size.x - inset * 2.0, ACCENT_ROWS * UiKit.ART_SCALE), band)
	if not focused or disabled:
		return
	# Soft pixel glow around the focused card, breathing slowly.
	var breath := 0.5 + 0.5 * sin(_glow)
	var step := float(UiKit.ART_SCALE)
	for i in GLOW_RINGS:
		var grow := step * (i + 1)
		var alpha := (0.22 - 0.06 * i) * (0.6 + 0.4 * breath)
		draw_rect(Rect2(-grow, -grow, size.x + grow * 2.0, size.y + grow * 2.0), Color(accent, alpha), false, step)


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
	Sfx.play_ui(self, pick_sound)
	var texture := (symbol as TextureRect).texture if symbol is TextureRect else null
	UiKit.pick_burst(self, texture, accent if accent.a > 0.0 else UiKit.COLOR_GOLD)
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
	_shake = UiKit.ui_tween(self)
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


## The symbol hops once when the card gets the focus.
func _hop() -> void:
	if disabled or symbol == null or not is_instance_valid(symbol) or not symbol.is_inside_tree():
		return
	symbol.pivot_offset = symbol.size * 0.5
	var tween := UiKit.ui_tween(symbol)
	tween.tween_property(symbol, "scale", Vector2.ONE * HOP_SCALE, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(symbol, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh() -> void:
	var kind := focused_kind if focused and not disabled else normal_kind
	add_theme_stylebox_override("panel", UiKit.padded_style(kind, padding.x, padding.y))
	queue_redraw()
