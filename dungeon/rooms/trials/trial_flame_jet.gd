class_name TrialFlameJet
extends TrialHazard
## Flame nozzle in the floor of one tile (flame_jet_6f, SPRITES_V5 §4): sparks as warning, then a
## burst of fire, then a dying puff. Two jets share a lane column with opposite beats, so the
## player picks the row that is quiet.

## Timing (TESTWERTE).
const IDLE_RANGE := Vector2(0.9, 1.7)
const WARN_TIME := 0.5
const ACTIVE_TIME := 0.8
const FLAME_FPS := 12.0
const PUFF_TIME := 0.15
## The nozzle sits in the lower part of its tile; the flame rises above it.
const BASE_OFFSET := 22.0
const LIGHT_RADIUS := 95.0

var _sprite: Sprite2D = null
var _light: LightSource = null
var _flame_time := 0.0
var _puff_left := 0.0


## rect: content-local tile of the nozzle.
func build(rect: Rect2) -> void:
	hit_rect = rect
	# Sorted by the nozzle's base like the characters (the content y-sorts its children).
	position = rect.get_center() + Vector2(0.0, BASE_OFFSET)
	_sprite = TrialArt.make_sprite(TrialArt.FLAME_JET)
	add_child(_sprite)
	_light = LightSource.new()
	_light.radius = LIGHT_RADIUS
	_light.flicker = 0.1
	_light.position = Vector2(0.0, -40.0)
	_light.visible = false
	add_child(_light)


func _on_phase_changed() -> void:
	if _sprite == null:
		return
	match phase:
		Phase.IDLE:
			_puff_left = PUFF_TIME if _light.visible else 0.0
			_sprite.frame = 5 if _puff_left > 0.0 else 0
			_light.visible = false
		Phase.WARN:
			_sprite.frame = 1
		Phase.ACTIVE:
			_flame_time = 0.0
			_sprite.frame = 2
			_light.visible = true
			if is_inside_tree():
				Sfx.play_at(self, &"fuse", global_position, -10.0)


func _on_advance(delta: float) -> void:
	if _sprite == null:
		return
	if phase == Phase.ACTIVE:
		_flame_time += delta
		_sprite.frame = 2 + int(_flame_time * FLAME_FPS) % 3
	elif _puff_left > 0.0:
		_puff_left -= delta
		if _puff_left <= 0.0:
			_sprite.frame = 0
