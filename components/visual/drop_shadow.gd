class_name DropShadow
extends Sprite2D
## Soft pixel-art ellipse under a character or prop, drawn below everything that stands on the
## floor (z -2). The texture is generated once per size and shared. Usage:
##   DropShadow.attach(self, 13.0, 16.0)   # half width 13 world px, 16 px below the node origin

## Drawn in art pixels and scaled up like every sprite.
const PIXEL_SCALE := 2.0
const Z := -2
## Height of the ellipse relative to its width.
const FLATTEN := 0.38
const CORE_ALPHA := 0.5
const RIM_ALPHA := 0.26
const CORE_FRACTION := 0.62
const COLOR := Color(0.02, 0.0, 0.05)

static var _cache: Dictionary = {}

var radius := 0.0


## Adds a shadow to parent. radius = half width in world px, y_offset = where the feet are.
static func attach(parent: Node2D, shadow_radius: float, y_offset := 0.0) -> DropShadow:
	var shadow := DropShadow.new()
	shadow.name = "DropShadow"
	shadow.configure(shadow_radius, y_offset)
	parent.add_child(shadow)
	return shadow


## Pixel ellipse texture with a darker core and a lighter rim, half size in art pixels.
static func make_texture(half_size: Vector2i) -> ImageTexture:
	var key := half_size
	if _cache.has(key):
		return _cache[key]
	var size := half_size * 2
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size) * 0.5
	for y in size.y:
		for x in size.x:
			var d := ((Vector2(x, y) + Vector2(0.5, 0.5) - center) / Vector2(half_size)).length()
			if d <= 1.0:
				image.set_pixel(x, y, Color(COLOR, CORE_ALPHA if d < CORE_FRACTION else RIM_ALPHA))
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


func _init() -> void:
	z_index = Z
	centered = true
	scale = Vector2.ONE * PIXEL_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Resizes the shadow, e.g. after an enemy changed its visual scale.
func configure(shadow_radius: float, y_offset: float) -> void:
	radius = shadow_radius
	var half_x := maxi(2, roundi(shadow_radius / PIXEL_SCALE))
	var half_y := maxi(1, roundi(half_x * FLATTEN))
	texture = make_texture(Vector2i(half_x, half_y))
	position = Vector2(0.0, y_offset)


## Fades the shadow out (death dissolve), the node stays.
func fade_out(duration: float) -> void:
	create_tween().tween_property(self, "modulate:a", 0.0, duration)
