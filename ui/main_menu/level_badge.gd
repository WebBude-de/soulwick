class_name LevelBadge
extends Control
## The account level as a small badge with its number (D-188, KF2): main menu, profile, progress
## overview and run end. Draws art/ui/level_badge.png when it exists (SPRITES briefing: 16×16, the
## number is drawn on top), else a pixel placeholder: a chamfered gold frame on dark violet.
## Every fifth level (a reward level, AccountProgress.REWARD_EVERY) gets a brighter frame.
## KE1: free talent points (KONZEPT §4) light a small spark at the top right (show_points), drawn
## from code over the art too, until art/ui/icon_talent_point.png exists (SPRITES_V13 §B3).

const TEXTURE_PATH := "res://art/ui/level_badge.png"
## Badge size in mockup pixels (art pixels of the placeholder).
const DEFAULT_SIZE := 16.0
const FILL := Color("#2a2340")
const FRAME := UiKit.COLOR_GOLD
const FRAME_REWARD := Color("#fff1a8")
## Chamfer of the placeholder per art row from the top (mirrored at the bottom).
const CHAMFER: Array[int] = [3, 2, 1]
const POINT_ICON_PATH := "res://art/ui/icon_talent_point.png"
const POINT_COLOR := Color("#ffe6a3")

var level := 1:
	set(value):
		level = maxi(1, value)
		if _number != null:
			_number.text = str(level)
			_fit_number()
		queue_redraw()

## True: a spark at the top right says "talent points free".
var show_points := false:
	set(value):
		show_points = value
		queue_redraw()

var _number: Label = null
var _spec_size := DEFAULT_SIZE
var _texture: Texture2D = null


static func create(start_level: int, spec_size := DEFAULT_SIZE) -> LevelBadge:
	var badge := LevelBadge.new()
	badge.name = "LevelBadge"
	badge._spec_size = spec_size
	badge.level = start_level
	return badge


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2.ONE * UiKit.px(_spec_size)
	if ResourceLoader.exists(TEXTURE_PATH):
		_texture = load(TEXTURE_PATH) as Texture2D
	_number = UiKit.text_label(str(level), UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	_number.name = "Number"
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_number)
	_fit_number()


func get_number_text() -> String:
	return _number.text if _number != null else str(level)


## Three digits and more get a smaller font so they stay inside the badge.
func _fit_number() -> void:
	var digits := str(level).length()
	var font_size := UiKit.SIZE_CARD_NAME if digits <= 2 else UiKit.SIZE_BODY
	if _spec_size < DEFAULT_SIZE:
		font_size = UiKit.SIZE_BODY if digits <= 2 else UiKit.SIZE_EYEBROW
	_number.add_theme_font_size_override("font_size", UiKit.font_px(font_size))


func _draw() -> void:
	var side := minf(size.x, size.y)
	var origin := ((size - Vector2.ONE * side) * 0.5).floor()
	if _texture != null:
		draw_texture_rect(_texture, Rect2(origin, Vector2.ONE * side), false)
		_draw_point(origin, side)
		return
	var cells := 16
	var unit := floorf(side / cells)
	if unit <= 0.0:
		return
	origin += Vector2.ONE * floorf((side - unit * cells) * 0.5)
	var frame := FRAME_REWARD if level % AccountProgress.REWARD_EVERY == 0 else FRAME
	for y in cells:
		var inset := 0
		if y < CHAMFER.size():
			inset = CHAMFER[y]
		elif cells - 1 - y < CHAMFER.size():
			inset = CHAMFER[cells - 1 - y]
		var from := inset
		var to := cells - inset
		_row(origin, unit, y, from, to, UiKit.COLOR_SHADOW)
		var edge := y == 0 or y == cells - 1
		if not edge:
			var ring_from := from + 1
			var ring_to := to - 1
			_row(origin, unit, y, ring_from, ring_to, frame)
			if y > 1 and y < cells - 2:
				# A lighter first row inside: a little shine under the top of the frame.
				_row(origin, unit, y, ring_from + 1, ring_to - 1, FILL if y > 2 else FILL.lightened(0.15))
	_draw_point(origin, side)


## The "points free" spark: the delivered icon or a small light diamond at the top right corner.
func _draw_point(origin: Vector2, side: float) -> void:
	if not show_points:
		return
	var point_size := maxf(2.0, floorf(side * 0.4))
	var rect := Rect2(origin + Vector2(side - point_size * 0.75, -point_size * 0.25), Vector2.ONE * point_size)
	if ResourceLoader.exists(POINT_ICON_PATH):
		draw_texture_rect(load(POINT_ICON_PATH) as Texture2D, rect, false)
		return
	# A pixel diamond (D-218): shadow outline and a light core on the UI art-pixel grid.
	var pixel := float(UiKit.ART_SCALE)
	var outer := maxi(1, floori(point_size * 0.5 / pixel))
	PixelDraw.diamond(self, rect.get_center(), outer, UiKit.COLOR_SHADOW, pixel)
	PixelDraw.diamond(self, rect.get_center(), roundi(outer * 0.6), POINT_COLOR, pixel)


func _row(origin: Vector2, unit: float, y: int, from: int, to: int, color: Color) -> void:
	if to > from:
		draw_rect(Rect2(origin + Vector2(from, y) * unit, Vector2(to - from, 1) * unit), color)
