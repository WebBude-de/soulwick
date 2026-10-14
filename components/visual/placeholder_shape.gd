@tool
class_name PlaceholderShape
extends Node2D
## Geometric stand-in graphic until sprite/asset packs are decided (TECHSTACK §6).

enum Kind { CIRCLE, RECT }

const FLASH_DURATION := 0.25

@export var kind := Kind.CIRCLE:
	set(value):
		kind = value
		queue_redraw()
@export var radius := 12.0:
	set(value):
		radius = value
		queue_redraw()
@export var size := Vector2(24.0, 24.0):
	set(value):
		size = value
		queue_redraw()
@export var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()
@export var outline_color := Color(0.0, 0.0, 0.0, 0.6):
	set(value):
		outline_color = value
		queue_redraw()


## Short fading circle, e.g. for AOE impacts.
static func spawn_flash(parent: Node, global_center: Vector2, flash_radius: float, flash_color: Color) -> void:
	var flash := PlaceholderShape.new()
	flash.radius = flash_radius
	flash.color = Color(flash_color, 0.45)
	flash.outline_color = flash_color
	parent.add_child(flash)
	flash.global_position = global_center
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, FLASH_DURATION)
	tween.tween_callback(flash.queue_free)


func _draw() -> void:
	match kind:
		Kind.CIRCLE:
			draw_circle(Vector2.ZERO, radius, color)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, outline_color, 1.5)
		Kind.RECT:
			var rect := Rect2(-size * 0.5, size)
			draw_rect(rect, color)
			draw_rect(rect, outline_color, false, 1.5)
