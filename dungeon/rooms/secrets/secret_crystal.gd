class_name SecretCrystal
extends Node2D
## Soul crystals lying in a secret niche (A10, D-109): walking over them takes them for the group
## (run crystals, paid out at the run end like every crystal). Decision (collect) and effects
## (burst, sound, light) are separate; the niche shows the banner through collected.

signal collected(crystal: SecretCrystal, player: Player)

const TEXTURE: Texture2D = preload("res://art/environment/props/crystal_cluster.png")
const PICKUP_RADIUS := 30.0
const GLOW_RADIUS := 70.0
const GLOW_COLOR := Color(0.7, 0.6, 1.0)

var amount := SecretRules.CRYSTALS
var is_taken := false


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = TEXTURE
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	sprite.offset = SpriteStrip.pivot_offset(Vector2i(TEXTURE.get_size()), Vector2(16, 30))
	add_child(sprite)
	SortLift.lift(self)
	var glow := LightSource.new()
	glow.name = "Glow"
	glow.radius = GLOW_RADIUS
	glow.intensity = 0.7
	glow.flicker = 0.05
	glow.position = Vector2(0, -24)
	add_child(glow)
	var area := Area2D.new()
	area.name = "Pickup"
	area.collision_layer = 0
	area.collision_mask = PhysicsLayers.PLAYER
	var circle := CircleShape2D.new()
	circle.radius = PICKUP_RADIUS
	var shape := CollisionShape2D.new()
	shape.shape = circle
	area.add_child(shape)
	area.position = Vector2(0, -12)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		collect(body as Player)


## Takes the crystals once.
func collect(player: Player) -> bool:
	if is_taken:
		return false
	is_taken = true
	RunManager.add_run_crystals(amount)
	collected.emit(self, player)
	if is_inside_tree():
		Burst.spawn(get_parent(), global_position + Vector2(0, -20), GLOW_COLOR, 20, 150.0, 0.55, 4.0)
		LightSource.flash(get_parent(), global_position + Vector2(0, -20), 160.0, 0.5)
		Sfx.play_at(self, &"upgrade", global_position, -4.0)
	queue_free.call_deferred()
	return true
