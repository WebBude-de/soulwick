class_name FlintShine
extends RefCounted
## Flint's warm glow and the sparks rising from his flame (D-217), as on the website (wick.css:
## `.wick-glow` is a soft warm pool that breathes with the flame, `.wick-sparks` are five tiny sparks
## that rise from the flame and fade). One look for the companion (FlintAura behind his sprite,
## FlintSparks over it) and the explanation portrait (FlintPortrait, inside the ring).
## Pure optics: a time goes in, what to draw comes out; no randomness, nothing is synced, nothing is
## decided (Koop-Check: every machine draws its own players' Flints the same way). No light is painted
## into the pixels (D-174): the glow is a soft gradient drawn behind the figure.
## Option "Lichteffekte: Niedrig" (LightingQuality) draws no sparks; the glow stays.

## TESTWERTE (wick.css): the glow breathes 2.4 s up and 2.4 s down (wick-pulse, alternate) between
## 75 % and 100 % strength and 94 % and 104 % size.
const BREATH_TIME := 2.4
const GLOW_ALPHA_MIN := 0.75
const GLOW_SCALE_MIN := 0.94
const GLOW_SCALE_MAX := 1.04
## The glow's gradient (radial-gradient of .wick-glow on its round clip): strength at the centre, at
## GLOW_MID of the radius, gone at the edge. Colour --color-candle #ffb54a.
const GLOW_COLOR := Color("#ffb54a")
const GLOW_CENTER_ALPHA := 0.5
const GLOW_MID := 0.55
const GLOW_MID_ALPHA := 0.16
## Large enough to stay smooth where it is drawn with nearest filtering (the portrait).
const GLOW_TEXTURE_SIZE := 128
## TESTWERTE (wick.css wick-spark): five sparks, each living 2.2 s, started 0.45 s apart; they fade
## in over the first 15 % and out until the end. Per spark where it leaves the flame and how far it
## drifts sideways (shares of the rise), and a small flutter on the way up.
const SPARK_COUNT := 5
const SPARK_LIFE := 2.2
const SPARK_STAGGER := 0.45
const SPARK_FADE_IN := 0.15
const SPARK_START: Array[float] = [-0.06, 0.06, 0.0, 0.03, -0.03]
const SPARK_DRIFT: Array[float] = [-0.36, 0.3, -0.14, 0.42, 0.08]
const SPARK_FLUTTER := 0.05
## Spark colours as they cool on the way up: flame core, --color-candle-light, flame rim.
const SPARK_HOT := Color("#fff3c4")
const SPARK_WARM := Color("#ffe2a8")
const SPARK_COOL := Color("#ff8a3c")

static var _glow_texture: GradientTexture2D = null


## 0..1..0 over 2 * BREATH_TIME, eased like CSS ease-in-out (0 at time 0, 1 at BREATH_TIME).
static func breath(time: float) -> float:
	return 0.5 - 0.5 * cos(PI * time / BREATH_TIME)


static func glow_alpha(time: float) -> float:
	return lerpf(GLOW_ALPHA_MIN, 1.0, breath(time))


static func glow_scale(time: float) -> float:
	return lerpf(GLOW_SCALE_MIN, GLOW_SCALE_MAX, breath(time))


## True when sparks are drawn (option "Lichteffekte" on "Hoch").
static func sparks_on() -> bool:
	return LightingQuality.is_high()


## The sparks at time: Vector4(x, y, alpha, age) per spark, x and y as offsets from the flame in units
## of rise (y up is negative), so 1 rise = the full height a spark climbs; age 0..1 of its life.
## Invisible sparks have alpha 0.
static func sparks(time: float) -> Array[Vector4]:
	var result: Array[Vector4] = []
	for i in SPARK_COUNT:
		var age := fposmod(time + i * SPARK_STAGGER, SPARK_LIFE) / SPARK_LIFE
		var alpha := age / SPARK_FADE_IN if age < SPARK_FADE_IN else 1.0 - (age - SPARK_FADE_IN) / (1.0 - SPARK_FADE_IN)
		var x := SPARK_START[i % SPARK_START.size()] + SPARK_DRIFT[i % SPARK_DRIFT.size()] * age \
				+ SPARK_FLUTTER * sin(age * TAU * 1.5 + i)
		result.append(Vector4(x, -age, clampf(alpha, 0.0, 1.0), age))
	return result


## Colour of a spark at age 0..1: hot at the flame, cooling to the flame's rim colour.
static func spark_color(age: float) -> Color:
	if age < 0.4:
		return SPARK_HOT.lerp(SPARK_WARM, age / 0.4)
	return SPARK_WARM.lerp(SPARK_COOL, (age - 0.4) / 0.6)


## The soft round gradient of the glow (white alpha ramp tinted by the draw colour; built once).
static func glow_texture() -> GradientTexture2D:
	if _glow_texture != null:
		return _glow_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, GLOW_MID, 1.0])
	gradient.colors = PackedColorArray([
		Color(GLOW_COLOR, GLOW_CENTER_ALPHA),
		Color(GLOW_COLOR, GLOW_MID_ALPHA),
		Color(GLOW_COLOR, 0.0),
	])
	_glow_texture = GradientTexture2D.new()
	_glow_texture.gradient = gradient
	_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	_glow_texture.fill_from = Vector2(0.5, 0.5)
	_glow_texture.fill_to = Vector2(1.0, 0.5)
	_glow_texture.width = GLOW_TEXTURE_SIZE
	_glow_texture.height = GLOW_TEXTURE_SIZE
	return _glow_texture


## Draws the breathing glow centred at center with radius (canvas units) at time; strength scales it.
static func draw_glow(canvas: CanvasItem, center: Vector2, radius: float, time: float, strength := 1.0) -> void:
	var size := radius * glow_scale(time)
	var rect := Rect2(center - Vector2(size, size), Vector2(size, size) * 2.0)
	canvas.draw_texture_rect(glow_texture(), rect, false, Color(1, 1, 1, glow_alpha(time) * strength))


## The sparks to draw: Vector4(x, y, alpha, age) per visible spark, x and y the top left corner of a
## pixel-sized cell (canvas units) snapped to the pixel grid around flame, climbing rise. clip_radius
## > 0 fades sparks out towards that distance from clip_center (the portrait ring). Empty while
## sparks are off (sparks_on).
static func spark_cells(flame: Vector2, pixel: float, rise: float, time: float,
		clip_center := Vector2.ZERO, clip_radius := 0.0) -> Array[Vector4]:
	var cells: Array[Vector4] = []
	if not sparks_on():
		return cells
	var cell := Vector2(pixel, pixel)
	for spark in sparks(time):
		var alpha := spark.z
		# Snapped to the pixel grid: the sparks stay crisp pixels like the figure.
		var offset := Vector2(roundf(spark.x * rise / pixel), roundf(spark.y * rise / pixel)) * pixel
		var corner := flame - cell * 0.5 + offset
		if clip_radius > 0.0:
			alpha *= clampf((clip_radius - (corner + cell * 0.5).distance_to(clip_center)) / (pixel * 3.0), 0.0, 1.0)
		if alpha > 0.0:
			cells.append(Vector4(corner.x, corner.y, alpha, spark.w))
	return cells


## Draws spark_cells: each one crisp pixel, cooling from flame core to rim colour as it rises.
static func draw_sparks(canvas: CanvasItem, flame: Vector2, pixel: float, rise: float, time: float,
		clip_center := Vector2.ZERO, clip_radius := 0.0) -> void:
	var cell := Vector2(pixel, pixel)
	for spark in spark_cells(flame, pixel, rise, time, clip_center, clip_radius):
		canvas.draw_rect(Rect2(Vector2(spark.x, spark.y), cell), Color(spark_color(spark.w), spark.z))
