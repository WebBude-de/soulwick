class_name SideBackdrop
extends Node2D
## Background of a side segment (M5). With art/environment/side/bg_<biome>_parallax.png (SPRITES_V9)
## that picture repeats slowly behind the rock; until then a drawn placeholder: the dark back wall in
## the biome's colour with faint stone courses (moves with the rock) and darker distant pillars
## (Parallax2D, half speed), so jumps read against a calm, dark background.
## Round 3 (16.10.2026, "schöner gestalten"): in front of that a middle layer at three quarters of
## the speed with the biome's silhouettes (crypt: arches with chains and candle niches; grotto:
## roots, stalagmites and glowing mushroom caps; shadow realm: floating shards with runes; ember
## forge: chains with hanging cages and the glow of distant furnaces), and a coloured mist rising
## from below. Delivered art art/environment/side/mid_<biome>_parallax.png (SPRITES_V10 §6, 480×270,
## transparent) replaces the drawn middle layer.

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
const PARALLAX_MID := 0.75
const MID_ART_PATH := "res://art/environment/side/mid_%s_parallax.png"
## Silhouette tone of the middle layer (lightened back wall) and the glow colours per biome.
const MID_LIGHTEN := 0.07
const GLOW_COLORS: Dictionary[StringName, Color] = {
	&"crypt": Color(1.0, 0.72, 0.38),
	&"slime_grotto": Color(0.55, 1.0, 0.45),
	&"shadow_realm": Color(0.7, 0.5, 1.0),
	&"ember_forge": Color(1.0, 0.45, 0.12),
}
## Mist rising from below: height (px) and strength.
const MIST_HEIGHT := 260.0
const MIST_ALPHA := 0.32
const MID_SPACING := 520.0

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
	else:
		_add_far_pillars()
	_add_middle()
	var mist := _Mist.new()
	mist.name = "Mist"
	mist.color = GLOW_COLORS.get(biome_id, GLOW_COLORS[&"crypt"])
	mist.world_size = world_size
	mist.z_index = 3
	add_child(mist)


func _add_far_pillars() -> void:
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


## The middle layer: delivered art or the drawn silhouettes.
func _add_middle() -> void:
	var middle := Parallax2D.new()
	middle.name = "Middle"
	middle.scroll_scale = Vector2(PARALLAX_MID, 1.0)
	middle.z_index = 2
	add_child(middle)
	var art_path := MID_ART_PATH % biome_id
	if ResourceLoader.exists(art_path):
		var texture := load(art_path) as Texture2D
		var art_scale := (world_size.y + MARGIN) / float(texture.get_height())
		middle.repeat_size = Vector2(texture.get_width() * art_scale, 0.0)
		middle.repeat_times = 3
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE * art_scale
		sprite.position = Vector2(0, -MARGIN * 0.5)
		middle.add_child(sprite)
		return
	var shapes := _Middle.new()
	shapes.name = "Shapes"
	shapes.biome_id = biome_id
	shapes.color = _wall_color().lightened(MID_LIGHTEN)
	shapes.glow = GLOW_COLORS.get(biome_id, GLOW_COLORS[&"crypt"])
	shapes.world_size = world_size
	middle.add_child(shapes)


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


## Coloured mist rising from below the segment (the pits fall into it).
class _Mist:
	extends Node2D
	var color := Color.WHITE
	var world_size := Vector2.ZERO

	func _draw() -> void:
		var bottom := world_size.y + SideBackdrop.MARGIN * 0.5
		var top := world_size.y - SideBackdrop.MIST_HEIGHT
		var clear := Color(color, 0.0)
		var thick := Color(color.darkened(0.4), SideBackdrop.MIST_ALPHA)
		draw_polygon(PackedVector2Array([Vector2(-SideBackdrop.MARGIN, top), Vector2(world_size.x + SideBackdrop.MARGIN, top),
				Vector2(world_size.x + SideBackdrop.MARGIN, bottom), Vector2(-SideBackdrop.MARGIN, bottom)]),
				PackedColorArray([clear, clear, thick, thick]))


## Drawn middle layer: the biome's silhouettes every MID_SPACING px, a little lighter than the back
## wall, with small glows (candles, mushroom caps, runes, furnaces). Drawn once.
class _Middle:
	extends Node2D
	var biome_id: StringName = &"crypt"
	var color := Color.BLACK
	var glow := Color.WHITE
	var world_size := Vector2.ZERO

	func _draw() -> void:
		var h := world_size.y
		var x := 200.0
		var index := 0
		while x < world_size.x + 600.0:
			match biome_id:
				&"slime_grotto":
					_grotto(x, h, index)
				&"shadow_realm":
					_shadow(x, h, index)
				&"ember_forge":
					_ember(x, h, index)
				_:
					_crypt(x, h, index)
			x += SideBackdrop.MID_SPACING + 70.0 * float(index % 3)
			index += 1

	func _crypt(x: float, h: float, index: int) -> void:
		# An arch on two pillars, a chain in it, a niche with a candle beside it.
		var width := 180.0
		var top := h * 0.28
		draw_rect(Rect2(x, top, 34, h - top + 200), color)
		draw_rect(Rect2(x + width - 34, top, 34, h - top + 200), color)
		var arch := PackedVector2Array()
		for i in 17:
			var angle := PI + PI * i / 16.0
			arch.append(Vector2(x + width * 0.5 + cos(angle) * (width * 0.5 - 17.0), top + sin(angle) * 60.0))
		draw_polyline(arch, color, 34.0)
		draw_rect(Rect2(x - 6, top - 8, 46, 14), color.lightened(0.04))
		draw_rect(Rect2(x + width - 40, top - 8, 46, 14), color.lightened(0.04))
		var chain_x := x + width * 0.5
		for link in 5 + index % 3:
			draw_rect(Rect2(chain_x - 3, top - 50 + link * 16, 6, 11), color.lightened(0.06), false, 2.0)
		var niche := Vector2(x + width + 110, h * 0.45)
		draw_rect(Rect2(niche.x - 18, niche.y - 30, 36, 44), color.darkened(0.35))
		_glow_at(niche + Vector2(0, 6), 5.0)

	func _grotto(x: float, h: float, index: int) -> void:
		# Roots hanging from the top, a stalagmite, a big mushroom with glowing dots on its cap.
		for strand in 4:
			var points := PackedVector2Array()
			var x0 := x + strand * 26.0
			var length := h * (0.22 + 0.08 * ((strand + index) % 3))
			for i in 9:
				var t := i / 8.0
				points.append(Vector2(x0 + sin(t * 4.0 + strand + index) * 10.0 * t, -60.0 + (length + 60.0) * t))
			draw_polyline(points, color, 7.0 - strand)
		var base := Vector2(x + 230, h + 40)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-60, 0), base + Vector2(60, 0), base + Vector2(8, -h * 0.42), base + Vector2(-6, -h * 0.44)]), color)
		var stem := Vector2(x + 380, h + 20)
		var cap_y := h * (0.5 + 0.06 * (index % 2))
		draw_rect(Rect2(stem.x - 12, cap_y, 24, stem.y - cap_y), color)
		var cap := PackedVector2Array()
		for i in 13:
			var angle := PI + PI * i / 12.0
			cap.append(Vector2(stem.x + cos(angle) * 70.0, cap_y + sin(angle) * 34.0))
		draw_colored_polygon(cap, color.lightened(0.03))
		for dot in 4:
			_glow_at(Vector2(stem.x - 40 + dot * 26, cap_y - 12 - (dot % 2) * 10), 3.0)

	func _shadow(x: float, h: float, index: int) -> void:
		# Floating shards, a rune glowing on the biggest one.
		for shard in 3:
			var center := Vector2(x + shard * 110.0, h * (0.25 + 0.18 * ((shard + index) % 3)))
			var size := 26.0 + 16.0 * ((shard + index) % 2)
			draw_colored_polygon(PackedVector2Array([center + Vector2(0, -size * 1.6), center + Vector2(size, 0),
					center + Vector2(size * 0.3, size * 1.3), center + Vector2(-size * 0.8, size * 0.2)]), color)
			if shard == 1:
				_glow_at(center, 4.0)
				draw_line(center + Vector2(-6, -8), center + Vector2(6, 8), Color(glow, 0.55), 2.0)
				draw_line(center + Vector2(6, -8), center + Vector2(-6, 8), Color(glow, 0.55), 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x + 300, h + 60), Vector2(x + 360, h * 0.35), Vector2(x + 420, h + 60)]), color)

	func _ember(x: float, h: float, index: int) -> void:
		# Two chains with a hanging cage, a furnace mouth glowing low on the wall, a pipe.
		var cage := Vector2(x + 90, h * (0.3 + 0.05 * (index % 2)))
		for side in [-1.0, 1.0]:
			draw_line(Vector2(cage.x + side * 20, -40), Vector2(cage.x + side * 10, cage.y - 30), color.lightened(0.05), 4.0)
		draw_rect(Rect2(cage.x - 22, cage.y - 30, 44, 54), color, false, 5.0)
		for bar in 3:
			draw_line(Vector2(cage.x - 11 + bar * 11, cage.y - 30), Vector2(cage.x - 11 + bar * 11, cage.y + 24), color, 3.0)
		var furnace := Vector2(x + 300, h * 0.72)
		draw_rect(Rect2(furnace.x - 70, furnace.y - 60, 140, h - furnace.y + 260), color)
		var mouth := PackedVector2Array()
		for i in 13:
			var angle := PI + PI * i / 12.0
			mouth.append(Vector2(furnace.x + cos(angle) * 34.0, furnace.y + sin(angle) * 30.0))
		mouth.append(Vector2(furnace.x + 34, furnace.y + 24))
		mouth.append(Vector2(furnace.x - 34, furnace.y + 24))
		draw_colored_polygon(mouth, Color(glow, 0.35))
		_glow_at(furnace + Vector2(0, 6), 10.0)
		draw_rect(Rect2(x + 420, -40, 20, h * 0.55), color.lightened(0.03))

	## A small light point with a soft halo.
	func _glow_at(at: Vector2, radius: float) -> void:
		for ring in 4:
			draw_circle(at, radius * (4.0 - ring), Color(glow, 0.05 + 0.05 * ring))
		draw_circle(at, radius * 0.6, Color(glow.lightened(0.4), 0.9))
