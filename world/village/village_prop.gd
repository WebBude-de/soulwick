class_name VillageProp
extends StaticBody2D
## Placed village decoration whose art may still be missing (B3, docs/design/sprites/delivered/SPRITES_V4.md): garden fence,
## bench, cart, hay bale, signpost, pond. Takes art/environment/village/<art_name>.png (or the
## VillageArt placeholder) with its pivot at the bottom centre on the node origin. Without art and
## without placeholder the prop removes itself, collision included, so nothing invisible blocks.
## Placed by tools/generate_village.py; SortLift lifts it like every other prop.
## R7: animated strips with any frame count (<art_name>_<frames>f.png, or a drawn placeholder of that
## name, e.g. the soul flame bowl) and an optional light (the bowl's violet glow).

## File name without extension in art/environment/village/.
@export var art_name := ""
## Solid base (world px, centred above the origin); zero = walk through.
@export var solid_size := Vector2.ZERO
@export var flip := false
## Frames of the animated strip <art_name>_<frames>f.png (used when that file or placeholder exists).
@export var frames := 4
## TESTWERT: speed of animated props (e.g. the pond ripples, the flame bowl).
@export var fps := 4.0
## Light of the prop (0 = none): radius (world px), colour (LightPalette) and height above the base.
@export var light_radius := 0.0
@export var light_color := Color(0, 0, 0, 0)
@export var light_height := 0.0

var _sprite: Sprite2D = null
var _animation_time := 0.0


func _ready() -> void:
	collision_mask = 0
	var strip := VillageArt.get_texture("%s_%df" % [art_name, frames]) if frames > 1 else null
	var animated := strip != null
	var texture := strip if animated else VillageArt.get_texture(art_name)
	if texture == null:
		queue_free()
		return
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = texture
	_sprite.scale = Vector2.ONE * VillageArt.SCALE
	_sprite.flip_h = flip
	_sprite.offset = Vector2(0, -texture.get_height() * 0.5)
	if animated:
		_sprite.hframes = frames
	set_process(animated)
	add_child(_sprite)
	if light_radius > 0.0:
		var light := LightSource.new()
		light.name = "PropLight"
		light.radius = light_radius
		light.flicker = 0.05
		light.color = light_color
		light.position = Vector2(0, -light_height)
		light.ground_offset = Vector2(0, light_height)
		add_child(light)
	if solid_size != Vector2.ZERO:
		var shape := RectangleShape2D.new()
		shape.size = solid_size
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		collision.shape = shape
		collision.position = Vector2(0, -solid_size.y * 0.5)
		add_child(collision)


func _process(delta: float) -> void:
	_animation_time += delta
	_sprite.frame = int(_animation_time * fps) % frames


## Ground rectangle (village coordinates) the prop reserves around base, its solid base or a small
## spot without one; base is the generator position (before SortLift).
func get_footprint(base: Vector2) -> Rect2:
	var size := solid_size if solid_size != Vector2.ZERO else Vector2(32, 16)
	return Rect2(base + Vector2(-size.x * 0.5, -size.y), size)
