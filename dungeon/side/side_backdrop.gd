class_name SideBackdrop
extends Node2D
## Background of a side segment (M5). With art/environment/side/bg_<biome>_parallax.png (SPRITES_V9)
## that picture repeats slowly behind the rock; until then a drawn placeholder: the dark back wall in
## the biome's colour with faint stone courses (moves with the rock) and darker distant pillars
## (Parallax2D, half speed), so jumps read against a calm, dark background.

const ART_PATH := "res://art/environment/side/bg_%s_parallax.png"
const WALL_COLORS: Dictionary[StringName, Color] = {
	&"crypt": Color("#1d1a2b"),
	&"slime_grotto": Color("#14231e"),
	&"shadow_realm": Color("#1d1429"),
	&"ember_forge": Color("#26170f"),
}
const LINE_SHADE := 0.82
const PILLAR_SHADE := 0.6
## Margin around the segment so a zoomed-out view never shows the void.
const MARGIN := 640.0
const COURSE_HEIGHT := 32.0
const STONE_WIDTH := 64.0
const PILLAR_SPACING := 420.0
const PILLAR_WIDTH := 90.0
const PARALLAX_FAR := 0.5

var biome_id: StringName = &"crypt"
var world_size := Vector2(3200, 704)


func setup(biome: StringName, size: Vector2) -> void:
	biome_id = biome
	world_size = size


func _ready() -> void:
	z_index = -30
	var art_path := ART_PATH % biome_id
	if ResourceLoader.exists(art_path):
		_add_picture(load(art_path) as Texture2D)
		return
	var far := Parallax2D.new()
	far.name = "Far"
	far.scroll_scale = Vector2(PARALLAX_FAR, 1.0)
	far.z_index = 1
	add_child(far)
	var pillars := _Pillars.new()
	pillars.color = _wall_color() * Color(PILLAR_SHADE, PILLAR_SHADE, PILLAR_SHADE)
	pillars.world_size = world_size
	far.add_child(pillars)


func _draw() -> void:
	if ResourceLoader.exists(ART_PATH % biome_id):
		return
	var wall := _wall_color()
	draw_rect(Rect2(-Vector2.ONE * MARGIN, world_size + Vector2.ONE * MARGIN * 2.0), wall)
	var line := wall * Color(LINE_SHADE, LINE_SHADE, LINE_SHADE)
	var rows := ceili(world_size.y / COURSE_HEIGHT)
	for row in rows:
		var y := row * COURSE_HEIGHT
		draw_line(Vector2(0, y), Vector2(world_size.x, y), line, 2.0)
		var shift := STONE_WIDTH * 0.5 if row % 2 == 1 else 0.0
		var x := shift
		while x < world_size.x:
			draw_line(Vector2(x, y), Vector2(x, y + COURSE_HEIGHT), line, 2.0)
			x += STONE_WIDTH


func _wall_color() -> Color:
	return WALL_COLORS.get(biome_id, WALL_COLORS[&"crypt"])


func _add_picture(texture: Texture2D) -> void:
	var parallax := Parallax2D.new()
	parallax.name = "Picture"
	parallax.scroll_scale = Vector2(PARALLAX_FAR, 1.0)
	var art_scale := (world_size.y + MARGIN) / float(texture.get_height())
	parallax.repeat_size = Vector2(texture.get_width() * art_scale, 0.0)
	parallax.repeat_times = 3
	add_child(parallax)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * art_scale
	sprite.position = Vector2(0, -MARGIN * 0.5)
	parallax.add_child(sprite)


## Distant pillars of the placeholder (drawn once, moved by the parallax).
class _Pillars:
	extends Node2D
	var color := Color.BLACK
	var world_size := Vector2.ZERO

	func _draw() -> void:
		var x := 120.0
		var index := 0
		while x < world_size.x * 0.75 + 600.0:
			var width := PILLAR_WIDTH * (0.8 + 0.4 * float(index % 3) / 2.0)
			draw_rect(Rect2(x, -MARGIN, width, world_size.y + MARGIN * 2.0), color)
			draw_rect(Rect2(x - 10.0, world_size.y * 0.2, width + 20.0, 24.0), color.darkened(0.15))
			x += PILLAR_SPACING + 60.0 * float(index % 2)
			index += 1
