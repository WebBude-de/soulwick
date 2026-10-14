class_name VillageEntrance
extends StaticBody2D
## The dungeon entrance of the village (R7, 06_dorf.md): a ruin with stairs leading down, two
## torches, chains and a soul rune (art/environment/village/dungeon_entrance_v2.png; drawn by
## VillagePlaceholders from the old entrance until the file exists). The torches get a warm light
## and sparks, two ravens sit on the lintel and fly up when a player comes near (VillageRavens).
## The stone slabs, the soul flame bowl and the stairs through the ridge come from the generator,
## like the Interactable ("Dungeon betreten") and the caption. Pure optics.

const ART := "dungeon_entrance_v2"
## Ruin art (art px): 96×80, pivot bottom centre (the foot of the stairs).
const ART_SIZE := Vector2(96, 80)
## Torch flames in the ruin art, art px from the pivot (also the anchors for the delivered file).
const TORCH_ANCHORS: Array[Vector2] = [Vector2(-13, -29), Vector2(13, -29)]
## TESTWERT: torch light (world px) and flicker.
const TORCH_RADIUS := 150.0
const TORCH_FLICKER := 0.08
## Where the ravens sit on the lintel (art px from the pivot).
const RAVEN_PERCH := Vector2(0, -62)
const SPARK_COLOR := Color("#ffb347")

var _ravens: VillageRavens = null


func _ready() -> void:
	var sprite := get_node_or_null(^"Sprite") as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		sprite.scale = Vector2.ONE * VillageArt.SCALE
		sprite.offset = Vector2(0, -ART_SIZE.y * 0.5)
		add_child(sprite)
		move_child(sprite, 0)
	sprite.texture = VillageArt.get_texture(ART)
	for i in TORCH_ANCHORS.size():
		var anchor := TORCH_ANCHORS[i] * VillageArt.SCALE
		var light := LightSource.new()
		light.name = "TorchLight%d" % (i + 1)
		light.radius = TORCH_RADIUS
		light.flicker = TORCH_FLICKER
		light.color = LightPalette.WARM
		light.position = anchor
		light.ground_offset = Vector2(0, -anchor.y)
		add_child(light)
		var sparks := _sparks()
		sparks.name = "Sparks%d" % (i + 1)
		sparks.position = anchor + Vector2(0, -6)
		add_child(sparks)
	_ravens = VillageRavens.new()
	_ravens.name = "Ravens"
	_ravens.position = RAVEN_PERCH * VillageArt.SCALE
	add_child(_ravens)


func get_ravens() -> VillageRavens:
	return _ravens


## A few sparks rising from a torch flame.
static func _sparks() -> CPUParticles2D:
	var sparks := CPUParticles2D.new()
	sparks.amount = 5
	sparks.lifetime = 0.9
	sparks.local_coords = false
	sparks.z_index = 3
	sparks.texture = ChimneySmoke.puff_texture()
	sparks.direction = Vector2.UP
	sparks.spread = 25.0
	sparks.gravity = Vector2(0, -12)
	sparks.initial_velocity_min = 10.0
	sparks.initial_velocity_max = 28.0
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 0.7
	var ramp := Gradient.new()
	ramp.set_color(0, SPARK_COLOR)
	ramp.set_color(1, Color(SPARK_COLOR, 0.0))
	sparks.color_ramp = ramp
	sparks.emitting = true
	return sparks
