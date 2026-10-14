class_name TrialTorch
extends Node2D
## Free-standing torch of the light run (torch_stand_4f lit / torch_stand_unlit, SPRITES_V5 §1, §3).
## Only shows its state; the light run decides when it goes out (LightRunCourse).

const FPS := 8.0
const FLAME_HEIGHT := 70.0
const OUT_SMOKE_COLOR := Color(0.55, 0.52, 0.6)

## Where the stand touches the floor (room coordinates); position may be lifted for y-sorting.
var base_position := Vector2.ZERO

var _lit_sprite: AnimatedProp = null
var _unlit_sprite: Sprite2D = null
var _light: LightSource = null
var _lit := true


func build(light_radius: float) -> void:
	_lit_sprite = AnimatedProp.new()
	_lit_sprite.frame_size = TrialArt.get_frame_size(TrialArt.TORCH_STAND)
	_lit_sprite.fps = FPS
	_lit_sprite.pivot = TrialArt.get_pivot(TrialArt.TORCH_STAND)
	_lit_sprite.strip = TrialArt.get_texture(TrialArt.TORCH_STAND)
	_lit_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	add_child(_lit_sprite)
	_unlit_sprite = TrialArt.make_sprite(TrialArt.TORCH_UNLIT)
	_unlit_sprite.visible = false
	add_child(_unlit_sprite)
	_light = LightSource.new()
	_light.radius = light_radius
	_light.flicker = 0.06
	_light.position = Vector2(0.0, -FLAME_HEIGHT)
	add_child(_light)


func is_lit() -> bool:
	return _lit


func set_lit(lit: bool) -> void:
	if lit == _lit:
		return
	_lit = lit
	if _lit_sprite == null:
		return
	_lit_sprite.visible = lit
	_unlit_sprite.visible = not lit
	_light.visible = lit
	if not is_inside_tree():
		return
	if lit:
		Burst.spawn(get_parent(), global_position + Vector2(0.0, -FLAME_HEIGHT), TrialArt.FLAME_OUTER, 8, 70.0)
	else:
		Burst.spawn(get_parent(), global_position + Vector2(0.0, -FLAME_HEIGHT), OUT_SMOKE_COLOR, 10, 50.0, 0.7, 3.0)
