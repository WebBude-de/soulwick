extends PanelContainer
## Panel of a downed local player in a group game (D-084; feedback 16.10.2026 "wenn man stirbt …
## dass das UI besser ist"): what happened (who took you down, when known), what happens now (a
## teammate helps you up by standing next to you, a cleared room gets everyone up, everyone down ends
## the run) and the revive progress while a teammate helps. Bottom centre: the top band stays free
## for the coop countdown and the banners, the body in the middle stays visible. Look only;
## DungeonUI shows it and feeds it (set_cause, set_revive_share). No class_name (preloaded).

const COLOR := Color("#ff7366")
## Width of the text column and of the progress bar (mockup px), gap to the bottom edge.
const WIDTH := 200.0
const BAR_HEIGHT := 3.0
const BOTTOM := 34.0
const FADE_TIME := 0.25

var _cause: Label = null
var _bar_row: Control = null
var _bar: ProgressBar = null
var _bar_text: Label = null
var _closing := false


func _init() -> void:
	name = "DownedPanel"
	theme = UiKit.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiKit.padded_style(&"dark", 4, 6).duplicate() as StyleBoxTexture
	style.content_margin_left = UiKit.px(3)
	add_theme_stylebox_override("panel", style)
	var row := UiKit.hbox(int(UiKit.px(5)))
	add_child(row)
	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.color = COLOR
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.custom_minimum_size.x = UiKit.px(3)
	row.add_child(stripe)
	var box := UiKit.vbox(int(UiKit.px(2)))
	row.add_child(box)
	box.add_child(UiKit.eyebrow(DungeonTexts.t(&"DOWNED_EYEBROW"), COLOR))
	_cause = UiKit.text_label("", UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	_cause.name = "Cause"
	_cause.visible = false
	box.add_child(_cause)
	var help := UiKit.wrapped_text(DungeonTexts.t(&"DOWNED_HELP", [DamageNumber.format_amount(CoopRules.REVIVE_TIME)]),
			WIDTH, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	help.name = "Help"
	box.add_child(help)
	var rules := UiKit.wrapped_text("%s %s" % [DungeonTexts.t(&"DOWNED_ROOM"), DungeonTexts.t(&"DOWNED_ALL")],
			WIDTH, UiKit.SIZE_EYEBROW + 1, UiKit.COLOR_MUTED)
	rules.name = "Rules"
	box.add_child(rules)
	_bar_row = UiKit.hbox(int(UiKit.px(4)))
	_bar_row.name = "Revive"
	_bar_row.visible = false
	box.add_child(_bar_row)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.custom_minimum_size.y = UiKit.px(BAR_HEIGHT)
	_bar.add_theme_stylebox_override("fill", UiKit.bar_style(UiKit.COLOR_SUCCESS))
	_bar.add_theme_stylebox_override("background", UiKit.bar_style(UiKit.COLOR_SHADOW))
	_bar_row.add_child(_bar)
	_bar_text = UiKit.text_label("", UiKit.SIZE_EYEBROW + 1, UiKit.COLOR_SUCCESS, true)
	_bar_text.name = "ReviveText"
	_bar_row.add_child(_bar_text)


func _ready() -> void:
	minimum_size_changed.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout()
	modulate.a = 0.0
	UiKit.ui_tween(self).tween_property(self, "modulate:a", 1.0, FADE_TIME)


## "Erwischt von: Skelett"; "" hides the line (cause unknown).
func set_cause(cause: String) -> void:
	_cause.text = DungeonTexts.t(&"DOWNED_CAUSE", [cause]) if not cause.is_empty() else ""
	_cause.visible = not cause.is_empty()


func get_cause_text() -> String:
	return _cause.text if _cause.visible else ""


## Revive progress 0..1 while a teammate helps (the bar shows from the first moment); <= 0 hides it.
func set_revive_share(share: float) -> void:
	var helping := share > 0.0
	_bar_row.visible = helping
	if helping:
		_bar.value = clampf(share, 0.0, 1.0)
		_bar_text.text = DungeonTexts.t(&"DOWNED_REVIVING", [roundi(100.0 * clampf(share, 0.0, 1.0))])


func is_reviving() -> bool:
	return _bar_row.visible


## Fades out and frees itself (up again, run over).
func close() -> void:
	if _closing:
		return
	_closing = true
	var tween := UiKit.ui_tween(self)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)


func is_closing() -> bool:
	return _closing


## Bottom centre, above the HUD's bottom row.
func _layout() -> void:
	if not is_inside_tree():
		return
	var own := get_combined_minimum_size()
	size = own
	var view := get_viewport_rect().size
	position = Vector2(roundf((view.x - own.x) * 0.5), roundf(view.y - own.y - UiKit.px(BOTTOM)))
