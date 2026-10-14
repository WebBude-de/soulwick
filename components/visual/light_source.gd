class_name LightSource
extends Node2D
## A point that cuts a light circle into the dungeon darkness (torches, projectiles, explosions,
## pickups, elites). VisionOverlay collects all nodes of the group every frame.
## Lights that matter for gameplay (torches, crystals, lanterns - not flashes, projectiles or enemy
## glows) set counts_as_light: LightQuery then treats their circle as "lit" (A9, KONZEPT_RAEUME §4.3).
## The colour of the light (R6: warm = safe, cold = goal, red = danger) is pure optics: set color, or
## leave it transparent and LightPalette derives it from the owner once.

const GROUP := &"light_sources"
## Lights that count for LightQuery ("is this point in the light?").
const GAMEPLAY_GROUP := &"gameplay_lights"
## Share of the drawn radius that counts as lit: the soft outer edge of the circle does not.
const DEFAULT_LIT_SHARE := 0.8

@export var radius := 140.0
@export_range(0.0, 1.0) var intensity := 1.0
## Random flicker of the radius (0 = steady), e.g. for torches.
@export var flicker := 0.0
## Counts for LightQuery (stone guardians freeze in it, A9). Effects stay out.
@export var counts_as_light := false:
	set(value):
		counts_as_light = value
		_update_gameplay_group()
## Share of radius that counts as lit for LightQuery.
@export_range(0.0, 1.0) var lit_share := DEFAULT_LIT_SHARE
## From the light to the floor point under it: a torch flame hangs above its stand, the lit circle
## on the floor is centred at the stand's foot.
@export var ground_offset := Vector2.ZERO
## Colour of the light as drawn (LightPalette.WARM, COLD, DANGER ...). Transparent = derived from the
## owner (LightPalette.resolve). Optics only.
@export var color := Color(0, 0, 0, 0):
	set(value):
		color = value
		_draw_color_resolved = false

var _seed := randf() * 100.0
var _draw_color := LightPalette.NEUTRAL
var _draw_color_resolved := false


## Short light flash that fades out and frees itself (explosions).
static func flash(parent: Node, global_pos: Vector2, flash_radius: float, duration := 0.35) -> void:
	var light := LightSource.new()
	light.radius = flash_radius
	light.color = LightPalette.NEUTRAL
	light.intensity *= GameOptions.get_flash_strength()
	parent.add_child(light)
	light.global_position = global_pos
	var tween := light.create_tween()
	tween.tween_property(light, "intensity", 0.0, duration)
	tween.tween_callback(light.queue_free)


func _enter_tree() -> void:
	add_to_group(GROUP)
	_update_gameplay_group()


func get_current_radius() -> float:
	if flicker <= 0.0:
		return radius
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	return radius * (1.0 + flicker * (0.6 * sin(t * 9.0) + 0.4 * sin(t * 23.0)))


## Colour the VisionOverlay draws this light in (cached; the owner does not change).
func get_draw_color() -> Color:
	if not _draw_color_resolved:
		_draw_color = LightPalette.resolve(self)
		_draw_color_resolved = true
	return _draw_color


func is_lit() -> bool:
	return visible and intensity > 0.01 and is_visible_in_tree()


## Floor point in the middle of the lit circle (LightQuery). No flicker: the decision is steady.
func get_lit_center() -> Vector2:
	return global_position + ground_offset


## Radius of the circle that counts as lit (LightQuery).
func get_lit_radius() -> float:
	return radius * lit_share


func _update_gameplay_group() -> void:
	if not is_inside_tree():
		return
	if counts_as_light:
		add_to_group(GAMEPLAY_GROUP)
	elif is_in_group(GAMEPLAY_GROUP):
		remove_from_group(GAMEPLAY_GROUP)
