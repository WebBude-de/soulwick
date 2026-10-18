class_name ProfileLevelRow
extends HBoxContainer
## The account level above the profile editor (D-188, KF2: "Profil (Figur, Spiegel)"): level badge,
## "Level 7", the XP bar, "340 / 700 XP" and the next reward as a preview ("Nächste Belohnung:
## Level 10"). Only for show; the rewards themselves come with the outfits (WK2, D-176).

var badge: LevelBadge = null
var bar: PixelBar = null
var _level_label: Label = null
var _xp_label: Label = null
var _reward_label: Label = null


static func create() -> ProfileLevelRow:
	var row := ProfileLevelRow.new()
	row.name = "LevelRow"
	return row


func _ready() -> void:
	add_theme_constant_override("separation", int(UiKit.px(5)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge = LevelBadge.create(1, 14.0)
	add_child(badge)
	var right := UiKit.vbox(0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := UiKit.hbox(int(UiKit.px(4)))
	_level_label = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
	_level_label.name = "Level"
	line.add_child(_level_label)
	bar = PixelBar.create(0.0, UiKit.COLOR_GOLD, 0.0, 4.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(bar)
	_xp_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_TEXT_SOFT)
	_xp_label.name = "Xp"
	line.add_child(_xp_label)
	right.add_child(line)
	_reward_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_reward_label.name = "NextReward"
	right.add_child(_reward_label)
	add_child(right)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _level_label != null:
		refresh()


func refresh() -> void:
	var info := AccountProgress.current().get_level_info()
	var level := int(info["level"])
	badge.level = level
	bar.ratio = float(info["ratio"])
	_level_label.text = Loc.t(&"ACCOUNT_LEVEL", [level])
	_xp_label.text = Loc.t(&"ACCOUNT_XP_OF", [int(info["into"]), int(info["needed"])])
	var reward := AccountProgress.next_reward_level(level)
	_reward_label.text = Loc.t(&"PROFILE_LEVEL_NEXT", [reward]) if reward > 0 else Loc.t(&"PROFILE_LEVEL_ALL")


func get_reward_text() -> String:
	return _reward_label.text if _reward_label != null else ""
