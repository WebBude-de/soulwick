class_name VillageProp
extends StaticBody2D
## Placed village decoration whose art may still be missing (B3, docs/SPRITES_V4.md): garden fence,
## bench, cart, hay bale, signpost, pond. Takes art/environment/village/<art_name>.png (or the
## VillageArt placeholder) with its pivot at the bottom centre on the node origin. Without art and
## without placeholder the prop removes itself, collision included, so nothing invisible blocks.
## Placed by tools/generate_village.py; SortLift lifts it like every other prop.

## File name without extension in art/environment/village/.
@export var art_name := ""
## Solid base (world px, centred above the origin); zero = walk through.
@export var solid_size := Vector2.ZERO
@export var flip := false

var _sprite: Sprite2D = null


func _ready() -> void:
	collision_mask = 0
	var texture := VillageArt.get_texture(art_name)
	if texture == null:
		queue_free()
		return
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = texture
	_sprite.scale = Vector2.ONE * VillageArt.SCALE
	_sprite.flip_h = flip
	_sprite.offset = Vector2(0, -texture.get_height() * 0.5)
	add_child(_sprite)
	if solid_size != Vector2.ZERO:
		var shape := RectangleShape2D.new()
		shape.size = solid_size
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		collision.shape = shape
		collision.position = Vector2(0, -solid_size.y * 0.5)
		add_child(collision)


## Ground rectangle (village coordinates) the prop reserves around base, its solid base or a small
## spot without one; base is the generator position (before SortLift).
func get_footprint(base: Vector2) -> Rect2:
	var size := solid_size if solid_size != Vector2.ZERO else Vector2(32, 16)
	return Rect2(base + Vector2(-size.x * 0.5, -size.y), size)
