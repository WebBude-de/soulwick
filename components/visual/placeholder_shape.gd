@tool
class_name PlaceholderShape
extends Node2D
## Geometric stand-in graphic until sprite/asset packs are decided (TECHSTACK §6); also the circle of
## enemy telegraphs, warning circles and short flashes. Drawn in pixel art (D-218, PixelDraw): a
## filled pixel disc with a one art pixel rim on the world's art-pixel grid. Scale (tweens that grow
## a circle) and moves only change the radius and the place: the picture is always redrawn in whole
## world art pixels, never stretched.

enum Kind { CIRCLE, RECT }

const FLASH_DURATION := 0.25
## Rim width in art pixels.
const OUTLINE_PIXELS := 1

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


func _init() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	# The pixels sit on the world grid: a move or a scale tween redraws (hidden ones redraw when shown).
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var world := get_global_transform()
	var world_scale := world.get_scale().abs()
	if world_scale.x < 0.001 or world_scale.y < 0.001:
		return
	# Draw in a frame without rotation and scale whose origin is the nearest world art-pixel corner.
	draw_set_transform_matrix(world.affine_inverse() * Transform2D(0.0, PixelDraw.snap(world.origin)))
	match kind:
		Kind.CIRCLE:
			paint_circle(self, radius * world_scale.x, color, outline_color)
		Kind.RECT:
			paint_rect(self, size * world_scale, color, outline_color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The circle around item's origin (world px): a pixel disc with a rim of OUTLINE_PIXELS.
static func paint_circle(item: Object, circle_radius: float, fill: Color, outline: Color) -> void:
	if outline.a <= 0.0:
		PixelDraw.disc(item, Vector2.ZERO, circle_radius, fill)
		return
	PixelDraw.disc(item, Vector2.ZERO, circle_radius - OUTLINE_PIXELS * PixelDraw.WORLD_PIXEL, fill)
	PixelDraw.ring(item, Vector2.ZERO, circle_radius, outline, OUTLINE_PIXELS)


## The rectangle centred on item's origin (world px) with a rim of OUTLINE_PIXELS.
static func paint_rect(item: Object, rect_size: Vector2, fill: Color, outline: Color) -> void:
	var area := Rect2(-rect_size * 0.5, rect_size)
	PixelDraw.rect(item, area, fill)
	if outline.a > 0.0:
		PixelDraw.rect_outline(item, area, outline, OUTLINE_PIXELS)
