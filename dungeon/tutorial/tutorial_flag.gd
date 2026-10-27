class_name TutorialFlag
extends Node2D
## The flag of a station (WK10): hangs limp (frame 0 of station_flag_2f.png) until the station is
## done, then pops up and flies (frame 1), swaying in the wind. Optics only; TutorialRun raises it.

## Sway of the flying flag: skew (rad) and one swing (s); the pop when it goes up.
const SWAY_SKEW := 0.12
const SWAY_TIME := 0.7
const POP_SCALE := 1.35
const POP_TIME := 0.25

var is_raised := false

var _sprite: Sprite2D = null
var _sway := 0.0


func _ready() -> void:
	_sprite = TutorialArt.sprite(&"flag")
	_sprite.name = "Sprite"
	_sprite.frame = 1 if is_raised else 0
	add_child(_sprite)
	set_process(is_raised)


## The station is done: up it goes (once).
func raise() -> void:
	if is_raised:
		return
	is_raised = true
	if _sprite == null:
		return
	_sprite.frame = 1
	set_process(true)
	var base := _sprite.scale
	var tween := create_tween()
	tween.tween_property(_sprite, ^"scale", base * POP_SCALE, POP_TIME * 0.4)
	tween.tween_property(_sprite, ^"scale", base, POP_TIME * 0.6).set_trans(Tween.TRANS_BACK)
	Sfx.play_at(self, &"wager_won", global_position, -6.0)


func _process(delta: float) -> void:
	_sway += delta
	_sprite.skew = sin(_sway * TAU / SWAY_TIME) * SWAY_SKEW
