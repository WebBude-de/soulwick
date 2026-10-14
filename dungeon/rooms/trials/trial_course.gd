class_name TrialCourse
extends Node2D
## What fills the parcours of one kind of trial (TrialLayout): spikes and blades, torches that go
## out, later crumbling floor. The trial content owns the per-player run state and asks the course
## every frame how much a running player is hurt (get_damage); the course never applies damage
## itself (decision in one place, effects via the content's signals, D-088).
## Children are added to the course node, which sits at the content origin (room coordinates).

## Hit margin around the player's feet (half of the body width, TESTWERT).
const FEET_MARGIN := 10.0

var content: TrialContent = null


func setup(owner_content: TrialContent) -> void:
	content = owner_content


## Override: place hazards/props with the dungeon RNG.
func build(_rng: RandomNumberGenerator) -> void:
	pass


## Override: advance timers by delta seconds (called by the content, also from tests).
func advance(_delta: float) -> void:
	pass


## Override: damage this frame for a running player whose feet are at feet (room coordinates).
## 0 = no mistake.
func get_damage(_player: Player, _feet: Vector2, _delta: float) -> float:
	return 0.0


## Override: a player started (stepped into the parcours) or left it again / reached the finish.
func on_run_started(_player: Player) -> void:
	pass


func on_run_ended(_player: Player) -> void:
	pass


## Room-local light points that stay lit no matter what (chest, safe torches).
func get_permanent_lights() -> PackedVector2Array:
	return PackedVector2Array()
