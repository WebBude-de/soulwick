class_name TutorialHud
extends CanvasLayer
## Progress strip of the practice run (WK10, WK10b) for the local player: one slim line at the top
## edge, "2/4" with one flag per station (flying once done), the station's name and a quiet
## "Kenne ich schon" for the mouse (the shortcut sign in the hall does the same with the interact
## key, gamepad and touch). Nothing else: Flint explains the station in his corner (bottom right) and
## the key symbols stand on the station signs in the world, so the playfield stays free (feedback
## 22.10.2026: "man sieht teilweise das Game nicht"). TutorialRun hides it during the side-view
## stretch. Narrow enough to stay clear of the hearts (top left) and the room label (top right), also
## at the portrait zoom. Optics only: TutorialRun tells it what to show.

signal skip_pressed

const LAYER := 12
## Mockup pixels: distance to the top edge, padding of the strip, gaps in the row. TESTWERTE
const TOP_MARGIN := 2.0
const PAD_VERTICAL := 1.0
const PAD_HORIZONTAL := 5.0
const GAP := 4.0
## Screen pixels per art pixel of the flags (16x24 art) in the strip.
const FLAG_PIXEL := 1.0
## Zones: -1 the welcome, 0..3 the stations, FINISH the way to the gate.
const FINISH := 4

var zone := -1
var done: Array[bool] = [false, false, false, false]

var _root: Control = null
var _panel: PanelContainer = null
var _progress: Label = null
var _flags: HBoxContainer = null
var _station: Label = null
var _skip: Button = null


func _ready() -> void:
	layer = LAYER
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UiKit.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	# Phones: inside the safe area, in portrait as large as the rest of the HUD.
	UiKit.MobileUi.fit_to_safe_area(_root, true)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override(&"panel", UiKit.padded_style(&"dark", PAD_VERTICAL, PAD_HORIZONTAL))
	_root.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = UiKit.px(TOP_MARGIN)
	var row := UiKit.hbox(int(UiKit.px(GAP)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(row)
	_progress = UiKit.eyebrow("", UiKit.COLOR_GOLD)
	_progress.name = "Progress"
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_progress)
	_flags = UiKit.hbox(int(UiKit.px(1)))
	_flags.name = "Flags"
	_flags.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_flags)
	_station = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_TEXT)
	_station.name = "Station"
	_station.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_station)
	_skip = _build_skip()
	row.add_child(_skip)
	_refresh()


## The quiet "Kenne ich schon": muted text without a button frame.
func _build_skip() -> Button:
	var skip := UiKit.button(Loc.t(&"TUTORIAL_SKIP"), func() -> void: skip_pressed.emit())
	skip.name = "Skip"
	skip.flat = true
	skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		skip.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	skip.add_theme_font_size_override(&"font_size", UiKit.font_px(UiKit.SIZE_EYEBROW))
	skip.add_theme_color_override(&"font_color", UiKit.COLOR_DISABLED)
	skip.add_theme_color_override(&"font_hover_color", UiKit.COLOR_TEXT)
	skip.add_theme_color_override(&"font_pressed_color", UiKit.COLOR_TEXT)
	return skip


## Shows a zone: -1 welcome, 0..3 a station, FINISH the gate.
func show_zone(value: int) -> void:
	zone = value
	_refresh()


## A station is done: its flag flies.
func set_done(station: int) -> void:
	if station >= 0 and station < done.size():
		done[station] = true
	_refresh()


func get_skip_button() -> Button:
	return _skip


## The strip (tests and tools measure it).
func get_panel() -> PanelContainer:
	return _panel


## The station name as shown (tests).
func get_station_text() -> String:
	return _station.text if _station != null else ""


func get_progress_text() -> String:
	return _progress.text if _progress != null else ""


func _refresh() -> void:
	if _panel == null:
		return
	var count := done.count(true)
	_progress.text = "%d/%d" % [count, done.size()]
	for child in _flags.get_children():
		child.free()
	for value in done:
		_flags.add_child(_flag(value))
	# Only the station's name: what to do there Flint says, its keys stand on the sign.
	var station_name := ""
	if zone >= 0 and zone < TutorialRules.STATIONS.size():
		station_name = Loc.t(TutorialRules.title_key(TutorialRules.STATIONS[zone]))
	_station.text = station_name
	_station.visible = station_name != ""
	_skip.visible = zone != FINISH


func _flag(flying: bool) -> TextureRect:
	var flag := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = TutorialArt.texture(&"flag")
	var frame := TutorialArt.frame_size(&"flag")
	atlas.region = Rect2(frame.x if flying else 0, 0, frame.x, frame.y)
	flag.texture = atlas
	flag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flag.stretch_mode = TextureRect.STRETCH_SCALE
	flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag.custom_minimum_size = Vector2(frame) * FLAG_PIXEL
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return flag
