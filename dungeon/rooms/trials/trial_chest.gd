class_name TrialChest
extends Node2D
## The chest at the end of a parcours (chest_closed / chest_open_4f, SPRITES_V5 §1): visible from
## the start, glows a little; open() plays the lid animation once. Shows state only, the trial
## content decides when it opens.

const OPEN_FPS := 10.0
const LIGHT_RADIUS := 120.0
const OPEN_LIGHT_RADIUS := 170.0
const GLOW_COLOR := Color(1.0, 0.85, 0.4)

## Where the chest stands (room coordinates); position may be lifted for y-sorting.
var base_position := Vector2.ZERO

var _closed: Sprite2D = null
var _open: AnimatedSprite2D = null
var _light: LightSource = null
var _is_open := false


func build() -> void:
	_closed = TrialArt.make_sprite(TrialArt.CHEST_CLOSED)
	add_child(_closed)
	_open = AnimatedSprite2D.new()
	var size := TrialArt.get_frame_size(TrialArt.CHEST_OPEN)
	_open.sprite_frames = SpriteStrip.make_frames(TrialArt.get_texture(TrialArt.CHEST_OPEN), size, OPEN_FPS, false)
	_open.offset = SpriteStrip.pivot_offset(size, TrialArt.get_pivot(TrialArt.CHEST_OPEN))
	_open.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_open.visible = false
	add_child(_open)
	_light = LightSource.new()
	_light.radius = LIGHT_RADIUS
	_light.intensity = 0.8
	_light.position = Vector2(0.0, -24.0)
	add_child(_light)


func is_open() -> bool:
	return _is_open


## The light point of the chest (light run: the finish is always lit).
func get_light_position() -> Vector2:
	return base_position + Vector2(0.0, -24.0)


func open() -> void:
	if _is_open:
		return
	_is_open = true
	if _closed == null:
		return
	_closed.visible = false
	_open.visible = true
	_open.play(&"default")
	_light.radius = OPEN_LIGHT_RADIUS
	_light.intensity = 1.0
	if is_inside_tree():
		Burst.spawn(get_parent(), global_position + Vector2(0.0, -28.0), GLOW_COLOR, 22, 150.0)
		LightSource.flash(get_parent(), global_position + Vector2(0.0, -28.0), 200.0, 0.5)
		Sfx.play_at(self, &"coin", global_position)
