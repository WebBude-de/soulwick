class_name UiCard
extends PanelContainer
## Clickable panel card (upgrade, shop offer, weapon slot). Normal = panel, focused = panel_gold.
## Hovering focuses the card (focus_requested); a left click releases "pressed". Disabled cards
## are dimmed and ignore clicks. The owner decides what focus and pressed mean.

signal pressed
## Emitted on mouse enter so the owner can move the focus here.
signal focus_requested

## Panel kinds (UiKit.panel_style) for the two states.
var normal_kind := &"normal"
var focused_kind := &"gold"
## Content padding in mockup pixels (vertical, horizontal).
var padding := Vector2(6, 8)
var disabled := false:
	set(value):
		disabled = value
		_refresh()
var focused := false:
	set(value):
		focused = value
		_refresh()
## Opacity while disabled (ui_spec shop.unaffordable.opacity).
var disabled_alpha := 0.55

var _pressing := false


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
			# Not possible (too little gold, at the limit): a short "no" instead of silence.
			UiSound.error(self)
		return
	if click.pressed:
		_pressing = true
	elif _pressing:
		_pressing = false
		activate()


## Same as a click (also used by number keys / Enter).
func activate() -> void:
	if disabled:
		return
	Sfx.play_ui(self, &"ui_click")
	pressed.emit()


func _on_mouse_entered() -> void:
	if not disabled:
		if not focused:
			UiSound.hover(self)
		focus_requested.emit()


func _refresh() -> void:
	var kind := focused_kind if focused and not disabled else normal_kind
	add_theme_stylebox_override("panel", UiKit.padded_style(kind, padding.x, padding.y))
	modulate.a = disabled_alpha if disabled else 1.0
