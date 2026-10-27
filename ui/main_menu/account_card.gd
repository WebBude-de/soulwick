class_name AccountCard
extends PanelContainer
## The player's name with the account level (D-188, KF2): level badge, name, "Level 7" with the XP
## bar and "340 / 700 XP". Top right in the main menu (on phones bottom right over gold and record);
## a click or tap opens "Dein Fortschritt" (pressed). Only for show, nothing here changes values.
## KE1: a line under it with the rank badge and name ("Kerze II", the own danger level, D-196) and the
## free talent points ("3 Punkte frei", KONZEPT §4; the level badge gets a spark while any are free).

signal pressed

## Width of the bar in mockup pixels.
const BAR_WIDTH := 64.0
## Rank badge size in mockup pixels.
const RANK_BADGE_SIZE := 10.0

var badge: LevelBadge = null
var bar: PixelBar = null
var _name_label: Label = null
var _level_label: Label = null
var _xp_label: Label = null
var rank_badge: RankBadge = null
var _rank_label: Label = null
var _points_label: Label = null


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
	var rank_line := UiKit.hbox(int(UiKit.px(3)))
	rank_line.name = "RankLine"
	rank_badge = RankBadge.create(0, RANK_BADGE_SIZE)
	rank_line.add_child(rank_badge)
	_rank_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_TEXT_SOFT, true)
	_rank_label.name = "Rank"
	_rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_line.add_child(_rank_label)
	_points_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_GOLD)
	_points_label.name = "FreePoints"
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_line.add_child(_points_label)
	text.add_child(rank_line)
	row.add_child(text)
	add_child(row)
	refresh()


## Reads the profile name and the account level again.
func refresh() -> void:
	if _name_label == null:
		return
	var progress := AccountProgress.current()
	var info := progress.get_level_info()
	_name_label.text = PlayerProfile.current().get_display_name()
	_level_label.text = Loc.t(&"ACCOUNT_LEVEL", [int(info["level"])])
	_xp_label.text = Loc.t(&"ACCOUNT_XP_OF", [int(info["into"]), int(info["needed"])])
	badge.level = int(info["level"])
	bar.ratio = float(info["ratio"])
	var danger := progress.get_danger_level()
	rank_badge.danger = danger
	_rank_label.text = DangerRank.rank_text(danger)
	var free := progress.get_free_points()
	_points_label.text = free_points_text(free)
	_points_label.visible = free > 0
	badge.show_points = free > 0
	tooltip_text = Loc.t(&"PROGRESS_TITLE")


## "1 Punkt frei" / "3 Punkte frei" ("" for none).
static func free_points_text(free: int) -> String:
	if free <= 0:
		return ""
	return Loc.t(&"ACCOUNT_POINTS_FREE_ONE") if free == 1 else Loc.t(&"ACCOUNT_POINTS_FREE", [free])


func get_level_text() -> String:
	return _level_label.text if _level_label != null else ""


func get_xp_text() -> String:
	return _xp_label.text if _xp_label != null else ""


func get_rank_text() -> String:
	return _rank_label.text if _rank_label != null else ""


## "" while no point is free.
func get_points_text() -> String:
	return _points_label.text if _points_label != null and _points_label.visible else ""


func _gui_input(event: InputEvent) -> void:
	# Touch screens send emulated mouse clicks (project setting), so one check serves both.
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		Sfx.play_ui(self, &"ui_click")
		pressed.emit()
