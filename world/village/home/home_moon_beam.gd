class_name HomeMoonBeam
extends Node2D
## Light through the window of the home (Antwort 20 §1): a slanted shaft from the window down onto
## the planks (#c8beff at about 12 % by night, warm and fainter by day) with 3–5 slow dust motes in
## it. Pure optics, additive, under the furniture. The light circle on the floor is a LightSource of
## HomeInterior; this only draws the shaft. Art px (parent scales by HomeLayout.SCALE).
## Pixel art (D-218): the shaft is filled art pixel by art pixel (PixelDraw.polygon with a 1 art px
## grid), so its slanted edges step like the room's art instead of cutting through the pixels; the
## motes are single art pixels.

const ALPHA_NIGHT := 0.12
const ALPHA_DAY := 0.08
const DUST_COUNT := 4
const DUST_SPEED := 0.05
const DUST_ALPHA := 0.55
## Window bottom edge and the lit patch on the floor (art px).
const TOP_LEFT := Vector2(66, 62)
const TOP_RIGHT := Vector2(126, 62)
const BOTTOM_RIGHT := Vector2(176, 206)
const BOTTOM_LEFT := Vector2(96, 206)
const Z := -5
## The parent scales art px up to the world: one grid cell is one art pixel here.
const ART_PIXEL := 1.0

var colour := HomeLayout.MOON_COLOR
var alpha := ALPHA_NIGHT
var _time := 0.0
## Fixed seeds of the motes (optics only, never the dungeon RNG).
var _seeds := PackedFloat32Array([0.13, 0.41, 0.67, 0.89])


func _ready() -> void:
	z_index = Z
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


## 1 = night (moon), 0 = day (sun, fainter).
func set_night(amount: float) -> void:
	var night := clampf(amount, 0.0, 1.0)
	colour = HomeLayout.SUN_COLOR.lerp(HomeLayout.MOON_COLOR, night)
	alpha = lerpf(ALPHA_DAY, ALPHA_NIGHT, night)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	paint_shaft(self)
	for index in mini(DUST_COUNT, _seeds.size()):
		draw_rect(Rect2(dust_position(index, _time), Vector2.ONE * ART_PIXEL), Color(colour, DUST_ALPHA))


## The shaft in art px into item (a CanvasItem in _draw, or a PixelDraw.Raster in tests).
func paint_shaft(item: Object) -> void:
	var shaft := PackedVector2Array([TOP_LEFT, TOP_RIGHT, BOTTOM_RIGHT, BOTTOM_LEFT])
	PixelDraw.polygon(item, shaft, Color(colour, alpha), ART_PIXEL)


## Where mote index floats at time t: slowly down the shaft, swaying (pure, for tests).
func dust_position(index: int, t: float) -> Vector2:
	var mote_seed := _seeds[index]
	var along := fposmod(mote_seed + t * DUST_SPEED * (0.6 + mote_seed), 1.0)
	var left := TOP_LEFT.lerp(BOTTOM_LEFT, along)
	var right := TOP_RIGHT.lerp(BOTTOM_RIGHT, along)
	var across := 0.5 + 0.35 * sin(t * 0.7 + mote_seed * TAU)
	return left.lerp(right, across).round()
