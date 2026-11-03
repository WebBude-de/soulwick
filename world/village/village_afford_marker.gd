extends Node2D
## P1-3: the "!" over a building where something is affordable (VillageAffordable decides when).
## A round gold badge with a dark "!" in the style of the info marker (icon_info.png, 16x16 art px,
## x2 like the village), pulsing with a warm glow behind it. The art is drawn in code until
## art/ui/icon_affordable.png exists (same size; it is used automatically then).
## Lives on Village's marker layer above the darkness, so it reads at night too.
## Pixel art (D-218, feedback #e5d0f6c6): the badge keeps its whole scale and hops one art pixel on
## the beat instead of scaling smoothly; the glow is a stepped pixel disc on the world grid that
## grows by whole art pixels and fades in GLOW_STEPS hard steps (off at LightingQuality low).
## No class_name: used through preload (Village.AffordMarkerScript).

const ART_PATH := "res://art/ui/icon_affordable.png"
const ART_SCALE := 2.0
## 16x16 badge: a = outline, b = gold, c = light, e = shade, d = the "!".
const PIXELS: Array[String] = [
	"................",
	".....aaaaaa.....",
	"....abbbbbba....",
	"...abccddbbba...",
	"..abccbddbbbba..",
	".abccbbddbbbbba.",
	".abcbbbddbbbbba.",
	".abbbbbddbbbbea.",
	".abbbbbddbbbbea.",
	".abbbbbbbbbbbea.",
	".abbbbbddbbbbea.",
	"..abbbbddbbbea..",
	"...abbbbbbbea...",
	"....aeeeeeea....",
	".....aaaaaa.....",
	"................",
]
const PALETTE := {
	"a": Color("#1c1a2b"),
	"b": Color("#f2cf4a"),
	"c": Color("#fff1a8"),
	"d": Color("#1c1a2b"),
	"e": Color("#b8862a"),
}
## TESTWERT: pulse (range of get_pulse, speed in rad/s) and the glow behind the badge (world px, alpha).
const PULSE := 0.12
const PULSE_SPEED := 4.0
const GLOW_RADIUS := 22.0
const GLOW_ALPHA := 0.28
const GLOW_COLOR := Color("#f2cf4a")
## Hard alpha steps of the glow and of its breathing.
const GLOW_STEPS := 3
## Art pixels the badge hops up on the beat and the glow grows by at the peak of the pulse.
const HOP_PIXELS := 1
const GLOW_GROW_PIXELS := 2

static var _texture: Texture2D = null

var _time := 0.0


## The badge art: the file if it exists, else the code-drawn one.
static func get_texture() -> Texture2D:
	if _texture != null:
		return _texture
	if ResourceLoader.exists(ART_PATH):
		_texture = load(ART_PATH) as Texture2D
	if _texture == null:
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in PIXELS.size():
			for x in PIXELS[y].length():
				var key := PIXELS[y][x]
				if PALETTE.has(key):
					image.set_pixel(x, y, PALETTE[key])
		_texture = ImageTexture.create_from_image(image)
	return _texture


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Also while a dialog pauses the village: it keeps pulsing under the overlay.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Current pulse factor (1 = rest), for tests.
func get_pulse() -> float:
	return 1.0 + PULSE * (0.5 + 0.5 * sin(_time * PULSE_SPEED))


func _draw() -> void:
	PixelDraw.align_to_world_grid(self)
	var beat := pulse_share()
	if LightingQuality.is_high():
		paint_glow(self, beat)
	var art := get_texture()
	var size := art.get_size() * ART_SCALE
	var hop := Vector2(0.0, -PixelDraw.WORLD_PIXEL * HOP_PIXELS) if beat >= 1.0 else Vector2.ZERO
	draw_texture_rect(art, Rect2(PixelDraw.snap(-size * 0.5) + hop, size), false)


## Pulse now from 0 (rest) to 1 (peak), stepped into GLOW_STEPS hard steps.
func pulse_share() -> float:
	return PixelDraw.stepped((get_pulse() - 1.0) / PULSE, GLOW_STEPS)


## Warm pixel glow behind the badge around item's origin (a CanvasItem in _draw, or a
## PixelDraw.Raster in tests): grows by whole art pixels with the beat (0..1), alpha in hard steps.
static func paint_glow(item: Object, beat: float) -> void:
	var alpha := GLOW_ALPHA * (0.6 + 0.4 * beat)
	var radius := GLOW_RADIUS + roundf(beat * GLOW_GROW_PIXELS) * PixelDraw.WORLD_PIXEL
	PixelDraw.glow(item, Vector2.ZERO, radius, Color(GLOW_COLOR, alpha), 2)
