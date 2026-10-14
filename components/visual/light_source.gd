class_name LightSource
extends Node2D
## A point that cuts a light circle into the dungeon darkness (torches, projectiles, explosions,
## pickups, elites). VisionOverlay collects all nodes of the group every frame.

const GROUP := &"light_sources"

@export var radius := 140.0
@export_range(0.0, 1.0) var intensity := 1.0
## Random flicker of the radius (0 = steady), e.g. for torches.
@export var flicker := 0.0

var _seed := randf() * 100.0


## Short light flash that fades out and frees itself (explosions).
static func flash(parent: Node, global_pos: Vector2, flash_radius: float, duration := 0.35) -> void:
	var light := LightSource.new()
	light.radius = flash_radius
	parent.add_child(light)
	light.global_position = global_pos
	var tween := light.create_tween()
	tween.tween_property(light, "intensity", 0.0, duration)
	tween.tween_callback(light.queue_free)


func _enter_tree() -> void:
	add_to_group(GROUP)


func get_current_radius() -> float:
	if flicker <= 0.0:
		return radius
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	return radius * (1.0 + flicker * (0.6 * sin(t * 9.0) + 0.4 * sin(t * 23.0)))


func is_lit() -> bool:
	return visible and intensity > 0.01 and is_visible_in_tree()
