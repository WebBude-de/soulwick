class_name RankBadge
extends Control
## The rank of a danger level as a small badge (KE1, KONZEPT §3.1): main menu next to the level,
## dungeon entrance and run end. Draws art/ui/ranks/rank_<id>.png (32×32; rank_<id>_16.png for small
## badges, SPRITES_V13 §B3) when it exists, else a pixel placeholder: a flame on a dark plate that
## grows and changes colour with the tier (Funke small and pale, Seelenmeister violet) and one to
## three pips for the step. With art the step hangs under the badge: the frame of
## art/ui/ranks/rank_pips.png (3 × 8×8: I, II, III) or, for Seelenmeister, the step number. Only for show.

const TEXTURE_PATH := "res://art/ui/ranks/rank_%s.png"
const SMALL_TEXTURE_PATH := "res://art/ui/ranks/rank_%s_16.png"
## Badge size in mockup pixels; below SMALL_FROM the 16 px art is used.
const DEFAULT_SIZE := 16.0
const SMALL_FROM := 20.0
const PLATE := Color("#2a2340")
## Placeholder flame colour per rank (light motif: pale spark to violet soul master).
const RANK_COLORS := {
	DangerRank.SPARK: Color("#ffe6a3"),
	DangerRank.CANDLE: Color("#f2cf4a"),
	DangerRank.FLAME: Color("#ff8a3c"),
	DangerRank.LANTERN: Color("#ffb347"),
	DangerRank.BEACON: Color("#9fdcff"),
	DangerRank.SOUL_MASTER: Color("#a66ef0"),
}
const CELLS := 16
const PIPS_PATH := "res://art/ui/ranks/rank_pips.png"
## rank_pips.png: one 8x8 frame per step, drawn at the scale of a 16 px badge; rows 1..6 hold the
## marks, so the strip under the badge is 6 art pixels high.
const PIP_FRAME := 8
const PIP_ART_CELLS := 16.0
const PIP_FIRST_ROW := 1
const PIP_ROWS := 6
## Chamfer of the plate per row from the top (mirrored at the bottom).
const CHAMFER: Array[int] = [3, 2, 1]

var danger := 0:
	set(value):
		danger = maxi(0, value)
		_texture = null
		_texture_loaded = false
		_update_minimum_size()
		queue_redraw()

var _spec_size := DEFAULT_SIZE
var _texture: Texture2D = null
var _texture_loaded := false
var _pips: Texture2D = null
var _pips_loaded := false


static func create(start_danger: int, spec_size := DEFAULT_SIZE) -> RankBadge:
	var badge := RankBadge.new()
	badge.name = "RankBadge"
	badge._spec_size = spec_size
	badge.danger = start_danger
	return badge


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_minimum_size()


## The rank shown ({"tier", "step"}).
func get_rank() -> Dictionary:
	return DangerRank.rank_for_danger(danger)


## The delivered art of this rank (null while only the placeholder exists).
func get_texture() -> Texture2D:
	if not _texture_loaded:
		_texture_loaded = true
		var id := String(get_rank()["tier"])
		var paths: Array[String] = [TEXTURE_PATH % id]
		if _spec_size < SMALL_FROM:
			paths.push_front(SMALL_TEXTURE_PATH % id)
		for path in paths:
			if ResourceLoader.exists(path):
				_texture = load(path) as Texture2D
				break
	return _texture


## The pip strip (null while not delivered).
func get_pips_texture() -> Texture2D:
	if not _pips_loaded:
		_pips_loaded = true
		if ResourceLoader.exists(PIPS_PATH):
			_pips = load(PIPS_PATH) as Texture2D
	return _pips


## Height of the step strip under delivered art (0 for the placeholder, which draws its own pips).
func get_step_strip_height() -> float:
	if get_texture() == null:
		return 0.0
	return PIP_ROWS * _pip_unit(UiKit.px(_spec_size))


## The frame of rank_pips.png for a step (I, II, III).
static func pip_region(step: int) -> Rect2:
	var index := clampi(step, 1, DangerRank.STEPS_PER_TIER) - 1
	return Rect2(index * PIP_FRAME, 0, PIP_FRAME, PIP_FRAME)


func _update_minimum_size() -> void:
	var side := UiKit.px(_spec_size)
	custom_minimum_size = Vector2(side, side + get_step_strip_height())


## One pip art pixel on screen for a badge of this side (crisp whole pixels).
func _pip_unit(side: float) -> float:
	return maxf(1.0, roundf(side / PIP_ART_CELLS))


func _draw() -> void:
	var texture := get_texture()
	if texture != null:
		_draw_art(texture)
		return
	var side := minf(size.x, size.y)
	var origin := ((size - Vector2.ONE * side) * 0.5).floor()
	var unit := floorf(side / CELLS)
	if unit <= 0.0:
		return
	origin += Vector2.ONE * floorf((side - unit * CELLS) * 0.5)
	var rank := get_rank()
	var color: Color = RANK_COLORS.get(rank["tier"], UiKit.COLOR_GOLD)
	_draw_plate(origin, unit, color.darkened(0.45))
	_draw_flame(origin, unit, maxi(0, DangerRank.TIERS.find(rank["tier"])), color)
	if rank["tier"] != DangerRank.SOUL_MASTER:
		_draw_pips(origin, unit, int(rank["step"]), color)


## Delivered badge on top, the step under it.
func _draw_art(texture: Texture2D) -> void:
	var strip := get_step_strip_height()
	var side := minf(size.x, size.y - strip)
	var origin := Vector2(floorf((size.x - side) * 0.5), floorf((size.y - strip - side) * 0.5))
	draw_texture_rect(texture, Rect2(origin, Vector2.ONE * side), false)
	var rank := get_rank()
	var unit := _pip_unit(UiKit.px(_spec_size))
	var strip_top := origin.y + side
	if rank["tier"] == DangerRank.SOUL_MASTER:
		_draw_step_number(DangerRank.step_text(rank), Rect2(0.0, strip_top, size.x, PIP_ROWS * unit))
		return
	var pips := get_pips_texture()
	if pips == null:
		return
	var source := pip_region(int(rank["step"]))
	var target_size := Vector2.ONE * PIP_FRAME * unit
	var target := Rect2(Vector2(floorf((size.x - target_size.x) * 0.5), strip_top - PIP_FIRST_ROW * unit), target_size)
	draw_texture_rect_region(pips, target, source)


## Seelenmeister has no pips: his step number, light violet with a dark outline, centred in the strip.
func _draw_step_number(text: String, area: Rect2) -> void:
	var font := UiKit.get_font()
	var font_size := maxi(1, int(area.size.y * 1.4))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent := font.get_ascent(font_size)
	var baseline := Vector2(floorf(area.get_center().x - width * 0.5), floorf(area.position.y + (area.size.y + ascent) * 0.5 - font.get_descent(font_size) * 0.5))
	var outline := maxi(1, int(area.size.y / float(PIP_ROWS)))
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline * 2, UiKit.COLOR_SHADOW)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, RANK_COLORS[DangerRank.SOUL_MASTER].lightened(0.3))


func _draw_plate(origin: Vector2, unit: float, frame: Color) -> void:
	for y in CELLS:
		var inset := 0
		if y < CHAMFER.size():
			inset = CHAMFER[y]
		elif CELLS - 1 - y < CHAMFER.size():
			inset = CHAMFER[CELLS - 1 - y]
		_row(origin, unit, y, inset, CELLS - inset, UiKit.COLOR_SHADOW)
		if y > 0 and y < CELLS - 1:
			_row(origin, unit, y, inset + 1, CELLS - inset - 1, frame)
			if y > 1 and y < CELLS - 2:
				_row(origin, unit, y, inset + 2, CELLS - inset - 2, PLATE)


## A flame standing on row 11: higher and wider for higher ranks (index 0 = Funke … 5).
func _draw_flame(origin: Vector2, unit: float, index: int, color: Color) -> void:
	var height := 4 + maxi(0, index)
	@warning_ignore("integer_division")
	var max_half := 1 + maxi(0, index) / 2
	var bottom := 11
	for t in height:
		var y := bottom - (height - 1 - t)
		var frac := float(t) / float(maxi(1, height - 1))
		var half := roundi(max_half * pow(frac, 0.6))
		if t == height - 1:
			half = maxi(0, half - 1)
		_row(origin, unit, y, 8 - half - 1, 8 + half, color)
		if half >= 1 and t > 0:
			_row(origin, unit, y, 8 - half, 8 + half - 1, color.lightened(0.45))


## One to three pips for the step under the flame.
func _draw_pips(origin: Vector2, unit: float, step: int, color: Color) -> void:
	var count := clampi(step, 1, DangerRank.STEPS_PER_TIER)
	var width := count * 2 + (count - 1)
	@warning_ignore("integer_division")
	var from := (CELLS - width) / 2
	for i in count:
		_row(origin, unit, 13, from + i * 3, from + i * 3 + 2, color)


func _row(origin: Vector2, unit: float, y: int, from: int, to: int, color: Color) -> void:
	if to > from:
		draw_rect(Rect2(origin + Vector2(from, y) * unit, Vector2(to - from, 1) * unit), color)
