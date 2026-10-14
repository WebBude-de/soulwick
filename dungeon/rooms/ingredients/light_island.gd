class_name LightIsland
extends Node2D
## Free-standing light in a combat room (ingredient "Lichtinseln", KONZEPT_RAEUME §3.3): a crystal
## on a pedestal or an iron torch stand. Its LightSource cuts a circle into the darkness like a wall
## torch (VisionOverlay collects every LightSource, so it works for any number of players).
## Its light counts for LightQuery (A9): stone guardians freeze in it like in a player's circle.
## The origin is the base line of the prop; the pedestal blocks like a crate.

## Light circle (TESTWERTE): a bit smaller than the player's own vision, bigger than a wall torch.
const CRYSTAL_RADIUS := 170.0
const TORCH_RADIUS := 160.0
const INTENSITY := 0.9
const CRYSTAL_FLICKER := 0.03
const TORCH_FLICKER := 0.08
const FOOTPRINT := Vector2(30, 16)

var style: IngredientSet.LightStyle = IngredientSet.LightStyle.CRYSTAL
var light: LightSource = null


## A light island of style tinted with color (built right away, so SortLift can lift it).
static func create(light_style: IngredientSet.LightStyle, color: Color) -> LightIsland:
	var island := LightIsland.new()
	island.name = "LightIsland"
	island.style = light_style
	island._build(color)
	return island


func _build(color: Color) -> void:
	var crystal := style == IngredientSet.LightStyle.CRYSTAL
	var prop := AnimatedProp.new()
	prop.name = "Sprite"
	if crystal:
		prop.frame_size = IngredientArt.CRYSTAL_FRAME
		prop.pivot = Vector2(16, 31)
		prop.fps = 4.0
		prop.strip = IngredientArt.get_texture("light_crystal_4f")
		prop.modulate = color
	else:
		prop.frame_size = IngredientArt.TORCH_STAND_FRAME
		prop.pivot = Vector2(8, 39)
		prop.fps = 8.0
		prop.strip = IngredientArt.get_texture("torch_stand_4f")
		# Only the flame takes the biome colour; a full tint would dye the iron.
		prop.modulate = Color.WHITE.lerp(color, 0.35)
	prop.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	add_child(prop)
	light = LightSource.new()
	light.name = "Light"
	light.radius = CRYSTAL_RADIUS if crystal else TORCH_RADIUS
	light.intensity = INTENSITY
	light.flicker = CRYSTAL_FLICKER if crystal else TORCH_FLICKER
	light.position = Vector2(0, -36 if crystal else -64)
	light.counts_as_light = true
	light.ground_offset = -light.position
	add_child(light)
	var body := StaticBody2D.new()
	body.name = "Blocker"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = FOOTPRINT
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -FOOTPRINT.y * 0.5)
	body.add_child(collision)
	add_child(body)


func _ready() -> void:
	DropShadow.attach(self, 14.0, -2.0)
