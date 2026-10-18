class_name AccountCard
extends PanelContainer
## The player's name with the account level (D-188, KF2): level badge, name, "Level 7" with the XP
## bar and "340 / 700 XP". Top right in the main menu (on phones bottom right over gold and record);
## a click or tap opens "Dein Fortschritt" (pressed). Only for show, nothing here changes values.

signal pressed

## Width of the bar in mockup pixels.
const BAR_WIDTH := 64.0

var badge: LevelBadge = null
var bar: PixelBar = null
var _name_label: Label = null
var _level_label: Label = null
var _xp_label: Label = null


func _ready() -> void:
	name = "AccountCard"
	add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 3, 5))
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = Loc.t(&"PROGRESS_TITLE")
	var row := UiKit.hbox(int(UiKit.px(5)))
	badge = LevelBadge.create(1)
	row.add_child(badge)
	var text := UiKit.vbox(0)
	_name_label = UiKit.text_label("", UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true)
	_name_label.name = "Name"
	text.add_child(_name_label)
	var line := UiKit.hbox(int(UiKit.px(4)))
	_level_label = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
	_level_label.name = "Level"
	line.add_child(_level_label)
	bar = PixelBar.create(0.0, UiKit.COLOR_GOLD, BAR_WIDTH, 4.0)
	bar.name = "XpBar"
	line.add_child(bar)
	text.add_child(line)
	_xp_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_xp_label.name = "Xp"
	text.add_child(_xp_label)
	row.add_child(text)
	add_child(row)
	refresh()


## Reads the profile name and the account level again.
func refresh() -> void:
	if _name_label == null:
		return
	var info := AccountProgress.current().get_level_info()
	_name_label.text = PlayerProfile.current().get_display_name()
	_level_label.text = Loc.t(&"ACCOUNT_LEVEL", [int(info["level"])])
	_xp_label.text = Loc.t(&"ACCOUNT_XP_OF", [int(info["into"]), int(info["needed"])])
	badge.level = int(info["level"])
	bar.ratio = float(info["ratio"])
	tooltip_text = Loc.t(&"PROGRESS_TITLE")


func get_level_text() -> String:
	return _level_label.text if _level_label != null else ""


func get_xp_text() -> String:
	return _xp_label.text if _xp_label != null else ""


func _gui_input(event: InputEvent) -> void:
	# Touch screens send emulated mouse clicks (project setting), so one check serves both.
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		Sfx.play_ui(self, &"ui_click")
		pressed.emit()
