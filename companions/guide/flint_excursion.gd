class_name FlintExcursion
extends RefCounted
## Flint's flight into the explanation corner and back (KONZEPT §7.2): he grows beside his player,
## flies to where the corner portrait sits on screen (converted into the world, so the flight ends
## exactly there even while the camera moves), and fades into the portrait; at the end he comes out
## of the corner, flies back and shrinks. Optics only (FlintCompanion.set_excursion): his follow spot
## and the light centre stay with the player. FlintGuide calls out()/back() with the flight's
## progress every frame; without a Flint (a player without companion) nothing happens.

## Without a corner on screen (remote player, tests) Flint flies this far up and to the right.
const FALLBACK_OFFSET := Vector2(160.0, -120.0)
## The last share of the flight out fades him into the portrait, the first share back out of it.
const FADE_SHARE := 0.3

var flint: FlintCompanion = null
## Returns the corner's global world point (Vector2.INF: none).
var corner_provider := Callable()


func _init(companion: FlintCompanion = null, provider := Callable()) -> void:
	flint = companion
	corner_provider = provider


## On the way out: progress 0..1 over grow and flight (FlintGuideRules.fly_out_parts).
func out(progress: float) -> void:
	if not _usable():
		return
	var parts := FlintGuideRules.fly_out_parts(progress)
	var grow := _ease_out(parts.x)
	var fly := _ease_in_out(parts.y)
	var scale_factor := lerpf(1.0, FlintGuideRules.GROW_SCALE, grow)
	var alpha := 1.0 - clampf((parts.y - (1.0 - FADE_SHARE)) / FADE_SHARE, 0.0, 1.0)
	flint.set_excursion(_to_corner() * fly, scale_factor, alpha)


## Fully in the corner (the portrait shows him): his world picture is hidden.
func hide_in_corner() -> void:
	if _usable():
		flint.set_excursion(_to_corner(), FlintGuideRules.GROW_SCALE, 0.0)


## On the way back: progress 0..1 from the corner to his spot, shrinking to his normal size.
func back(progress: float) -> void:
	if not _usable():
		return
	var p := clampf(progress, 0.0, 1.0)
	var fly := 1.0 - _ease_in_out(p)
	var alpha := clampf(p / FADE_SHARE, 0.0, 1.0)
	flint.set_excursion(_to_corner() * fly, lerpf(FlintGuideRules.GROW_SCALE, 1.0, _ease_in_out(p)), alpha)


## Back at his spot in his normal size.
func land() -> void:
	if _usable():
		flint.clear_excursion()


## Offset from Flint's spot to the corner (world px).
func _to_corner() -> Vector2:
	var corner := Vector2.INF
	if corner_provider.is_valid():
		corner = corner_provider.call()
	if corner == Vector2.INF:
		return FALLBACK_OFFSET
	return corner - flint.global_position


func _usable() -> bool:
	return flint != null and is_instance_valid(flint) and flint.is_inside_tree()


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


static func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
