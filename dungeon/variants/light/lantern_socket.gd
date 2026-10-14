class_name LanternSocket
extends Node2D
## Stone socket in front of the exit of the variant "Laternenträger" (KONZEPT_RAEUME §4.4, A9).
## Empty it waits and shows the seconds left for the bonus; with the lantern set in it lights up.
## Pure look: the variant decides (LightVariantRules), the lantern sets it in (SoulLantern.insert).

const LIGHT_RADIUS := 150.0
const LIT_LIGHT_RADIUS := 240.0
const LABEL_Y := -84.0
const FOOTPRINT := Vector2(36, 14)

var lit := false

var _sprite: AnimatedSprite2D = null
var _light: LightSource = null
var _label: Label = null


func build() -> void:
	DropShadow.attach(self, 14.0, -2.0)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = VariantArt.make_socket_frames()
	_sprite.offset = SpriteStrip.pivot_offset(VariantArt.get_frame_size(VariantArt.LANTERN_SOCKET), VariantArt.get_pivot(VariantArt.LANTERN_SOCKET))
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	add_child(_sprite)
	_sprite.play(&"empty")
	_light = LightSource.new()
	_light.name = "Light"
	_light.radius = LIGHT_RADIUS
	_light.intensity = 0.45
	_light.position = Vector2(0.0, -30.0)
	add_child(_light)
	var body := StaticBody2D.new()
	body.name = "Blocker"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = FOOTPRINT
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0.0, -FOOTPRINT.y * 0.5)
	body.add_child(collision)
	add_child(body)
	_label = Label.new()
	_label.name = "TimeLeft"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(80.0, 20.0)
	_label.position = Vector2(-40.0, LABEL_Y)
	_label.z_index = 30
	UiKit.apply_prompt_style(_label)
	_label.visible = false
	add_child(_label)


## Seconds left for the bonus above the socket (< 0 hides it).
func show_time_left(seconds: float) -> void:
	if _label == null:
		return
	_label.visible = seconds >= 0.0 and not lit
	if _label.visible:
		_label.text = DungeonTexts.t(&"VARIANT_LANTERN_TIME", [ceili(seconds)])


func set_lit(value: bool) -> void:
	if lit == value:
		return
	lit = value
	if _sprite == null:
		return
	_sprite.play(&"lit" if value else &"empty")
	_light.radius = LIT_LIGHT_RADIUS if value else LIGHT_RADIUS
	_light.intensity = 1.0 if value else 0.45
	_light.counts_as_light = value
	show_time_left(-1.0)
	if value and is_inside_tree():
		Burst.spawn(get_parent(), global_position + Vector2(0.0, -30.0), SoulLantern.COLOR, 20, 150.0)
		LightSource.flash(get_parent(), global_position + Vector2(0.0, -30.0), 260.0, 0.6)
		Sfx.play_at(self, &"portal", global_position, -6.0)
