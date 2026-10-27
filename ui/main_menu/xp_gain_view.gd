class_name XpGainView
extends VBoxContainer
## "+86 XP" at the run end (D-188, KF2): the XP of the run with its parts (rooms, bosses, record,
## co-op …), the level badge and the bar, which fills from the old total to the new one. A level up
## fills the bar, the badge jumps to the new number and a small gold banner "Level 4!" pops in over
## it (its own layer above the dialog, so the dialog never changes its size; a reward line on reward
## levels) and fades; "+86 XP · Level 4!" stays. Several levels fill one after another. Runs while
## the game is paused (the run end dialog pauses, UiKit.ui_tween); skip() shows the end at once.
## Built by RunRecap.create_xp_view() from AccountProgress.record_run()'s result.
## KE1: a level up names its talent point ("+1 Talentpunkt"); when the run changed the own rank, a
## line with the rank badge says so ("Rang gestiegen: Kerze II", gold; falling: muted) and the badge
## bumps once the bar is done.

signal finished
signal leveled_up(level: int)

## Seconds for a full bar, pause before it starts and the banner's stay (TESTWERT, feel).
const FILL_TIME := 0.9
const START_DELAY := 0.35
const BANNER_TIME := 1.6
const BAR_WIDTH := 150.0
## Badge size in mockup pixels (smaller than in the menu: the run end stays low, R8).
const BADGE_SIZE := 12.0

var result: Dictionary = {}
var badge: LevelBadge = null
var bar: PixelBar = null
var _gain_label: Label = null
var _parts_label: Label = null
var _xp_label: Label = null
var _banner_layer: CanvasLayer = null
var _banner_text := ""
var _rank_line: HBoxContainer = null
var _rank_badge: RankBadge = null
var _shown_xp := 0
var _tween: Tween = null
var _done := false


## result: {"xp", "parts", "xp_before", "xp_after", "level_before", "level_after"}.
static func create(xp_result: Dictionary) -> XpGainView:
	var view := XpGainView.new()
	view.name = "XpGain"
	view.result = xp_result
	return view


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(UiKit.px(1)))
	var row := UiKit.hbox(int(UiKit.px(5)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shown_xp = int(result.get("xp_before", 0))
	badge = LevelBadge.create(AccountProgress.level_for_xp(_shown_xp), BADGE_SIZE)
	row.add_child(badge)
	_gain_label = UiKit.text_label(Loc.t(&"XP_GAIN", [int(result.get("xp", 0))]), UiKit.SIZE_VALUE, UiKit.COLOR_GOLD, true)
	_gain_label.name = "Gain"
	_gain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_gain_label)
	var info := AccountProgress.level_info(_shown_xp)
	bar = PixelBar.create(float(info["ratio"]), UiKit.COLOR_GOLD, BAR_WIDTH, 5.0)
	bar.name = "XpBar"
	row.add_child(bar)
	_xp_label = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	_xp_label.name = "XpText"
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_xp_label)
	add_child(row)
	_parts_label = UiKit.text_label(parts_text(result.get("parts", [])), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_parts_label.name = "Parts"
	_parts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_parts_label)
	_add_rank_line()
	_show_xp(_shown_xp)
	_play.call_deferred()


## "Rang gestiegen: Kerze II" with the new rank's badge, only when the rank changed.
func _add_rank_line() -> void:
	var before := int(result.get("danger_before", 0))
	var after := int(result.get("danger_after", before))
	var text := RunRecap.rank_change_text(before, after)
	if text.is_empty():
		return
	_rank_line = UiKit.hbox(int(UiKit.px(3)))
	_rank_line.name = "RankChange"
	_rank_line.alignment = BoxContainer.ALIGNMENT_CENTER
	_rank_badge = RankBadge.create(after, BADGE_SIZE)
	_rank_line.add_child(_rank_badge)
	var label := UiKit.text_label(text, UiKit.SIZE_BODY, UiKit.COLOR_GOLD if after > before else UiKit.COLOR_MUTED, after > before)
	label.name = "RankText"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_line.add_child(label)
	add_child(_rank_line)


## The rank line's text ("" when the rank stayed).
func get_rank_text() -> String:
	if _rank_line == null:
		return ""
	return (_rank_line.get_node(^"RankText") as Label).text


## "Räume ×12 +60 · Boss +50 · Koop-Bonus +22".
static func parts_text(parts: Array) -> String:
	var texts: Array[String] = []
	for part: Dictionary in parts:
		texts.append("%s +%d" % [AccountProgress.part_text(part), int(part.get("xp", 0))])
	return " · ".join(texts)


func is_done() -> bool:
	return _done


## The current level shown on the badge.
func get_shown_level() -> int:
	return badge.level if badge != null else 1


## Title of the last level-up banner ("" = none yet).
func get_banner_text() -> String:
	return _banner_text


## Ends the animation: the bar, badge and texts show the new total at once.
func skip() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var after := int(result.get("xp_after", _shown_xp))
	var level_after := AccountProgress.level_for_xp(after)
	if level_after > badge.level:
		_mark_level_up(level_after)
	_show_xp(after)
	_finish()


func _play() -> void:
	if not is_inside_tree():
		return
	var before := int(result.get("xp_before", 0))
	var after := int(result.get("xp_after", before))
	if after <= before:
		_finish()
		return
	_tween = UiKit.ui_tween(self)
	_tween.tween_interval(START_DELAY)
	var from := before
	while from < after:
		var level := AccountProgress.level_for_xp(from)
		var level_end := AccountProgress.xp_for_level(level + 1)
		var to := mini(after, level_end)
		var share := float(to - from) / float(level_end - AccountProgress.xp_for_level(level))
		_tween.tween_method(_show_xp, from, to, maxf(0.15, FILL_TIME * share))
		if to >= level_end:
			_tween.tween_callback(_on_level_up.bind(level + 1))
			_tween.tween_interval(0.25)
		from = to
	_tween.tween_callback(_finish)


func _show_xp(total: int) -> void:
	_shown_xp = total
	var info := AccountProgress.level_info(total)
	bar.ratio = float(info["ratio"])
	_xp_label.text = Loc.t(&"ACCOUNT_XP_OF", [int(info["into"]), int(info["needed"])])
	if int(info["level"]) > badge.level:
		badge.level = int(info["level"])


func _on_level_up(level: int) -> void:
	badge.level = level
	UiKit.bump(badge, 1.4, 0.3)
	Sfx.play_ui(self, &"upgrade")
	_show_banner(level)
	leveled_up.emit(level)


## "+86 XP · Level 4!" stays after the banner faded.
func _mark_level_up(level: int) -> void:
	_banner_text = Loc.t(&"LEVEL_UP_TITLE", [level])
	_gain_label.text = "%s · %s" % [Loc.t(&"XP_GAIN", [int(result.get("xp", 0))]), _banner_text]


## The gold banner over the bar: pops in, stays BANNER_TIME, fades (own layer, like UiKit.pick_burst).
func _show_banner(level: int) -> void:
	_mark_level_up(level)
	if not is_inside_tree():
		return
	if _banner_layer != null and is_instance_valid(_banner_layer):
		_banner_layer.queue_free()
	_banner_layer = CanvasLayer.new()
	_banner_layer.name = "LevelUpBanner"
	_banner_layer.layer = 40
	_banner_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_banner_layer)
	var banner := UiKit.panel(&"gold")
	banner.name = "LevelUp"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold", 3, 10))
	var box := UiKit.vbox(0)
	var title := UiKit.text_label(_banner_text, UiKit.SIZE_TITLE, UiKit.COLOR_GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var reward := level % AccountProgress.REWARD_EVERY == 0 and level <= AccountProgress.REWARD_MAX_LEVEL
	var sub := UiKit.text_label(Loc.t(&"LEVEL_UP_REWARD") if reward else Loc.t(&"LEVEL_UP_POINT"), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	banner.add_child(box)
	_banner_layer.add_child(banner)
	banner.size = banner.get_combined_minimum_size()
	var anchor := bar.get_global_rect() if bar.is_inside_tree() else get_global_rect()
	banner.position = (Vector2(anchor.get_center().x - banner.size.x * 0.5, anchor.position.y - banner.size.y - UiKit.px(4))).round()
	UiKit.pop_in(banner, 0.0, 0.7, 0.3)
	var layer := _banner_layer
	var fade := UiKit.ui_tween(layer)
	fade.tween_interval(BANNER_TIME)
	fade.tween_property(banner, "modulate:a", 0.0, 0.4)
	fade.tween_callback(layer.queue_free)


func _exit_tree() -> void:
	if _banner_layer != null and is_instance_valid(_banner_layer):
		_banner_layer.queue_free()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _rank_badge != null and is_inside_tree() and int(result.get("danger_after", 0)) > int(result.get("danger_before", 0)):
		UiKit.bump(_rank_badge, 1.4, 0.3)
	finished.emit()
