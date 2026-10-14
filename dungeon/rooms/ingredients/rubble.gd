class_name Rubble
extends StaticBody2D
## Heap of rubble (ingredient "Deckung", SPRITES_V5 §1): low, solid cover that cannot be broken.
## Origin = base line. Which of the two heaps is drawn is optics only.

const FRAME := Vector2i(32, 24)
const PIVOT := Vector2(16, 23)
const FILES: Array[String] = ["rubble_1", "rubble_2"]


func _ready() -> void:
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = IngredientArt.get_texture(FILES[randi() % FILES.size()])
	sprite.offset = SpriteStrip.pivot_offset(FRAME, PIVOT)
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	sprite.flip_h = randf() < 0.5
	add_child(sprite)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(46, 18)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -9)
	add_child(collision)
	DropShadow.attach(self, 22.0, -2.0)
