extends Node2D
## P1-3: the "!" over a building where something is affordable (VillageAffordable decides when).
## A round gold badge with a dark "!" in the style of the info marker (icon_info.png, 16x16 art px,
## x2 like the village), pulsing softly with a warm glow behind it. The art is drawn in code until
## art/ui/icon_affordable.png exists (same size; it is used automatically then).
## Lives on Village's marker layer above the darkness, so it reads at night too.
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
## TESTWERT: pulse (scale amount, speed in rad/s) and the glow behind the badge (world px, alpha).
const PULSE := 0.12
const PULSE_SPEED := 4.0
const GLOW_RADIUS := 22.0
const GLOW_ALPHA := 0.28
const GLOW_COLOR := Color("#f2cf4a")

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
	var pulse := get_pulse()
	var glow := GLOW_ALPHA * (0.6 + 0.4 * sin(_time * PULSE_SPEED))
	draw_circle(Vector2.ZERO, GLOW_RADIUS * pulse, Color(GLOW_COLOR, glow * 0.5))
	draw_circle(Vector2.ZERO, GLOW_RADIUS * 0.6 * pulse, Color(GLOW_COLOR, glow))
	var art := get_texture()
	var size := art.get_size() * ART_SCALE * pulse
	draw_texture_rect(art, Rect2(-size * 0.5, size), false)
