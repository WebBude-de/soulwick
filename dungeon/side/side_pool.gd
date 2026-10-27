class_name SidePool
extends Node2D
## A pool of a side segment (M5 round 3, plan "w"): water in the crypt, slime in the grotto, dark
## void water in the shadow realm, glowing slag in the ember forge, sunk into the floor. Feet in it
## slow the running (SideRules.POOL_SLOW_FACTOR through the player's speed modifier, the same way as
## the shallow water and puddles of the rooms); jumping stays the same, the plans keep jumps out of
## a pool short (SideLayout: SideRules.POOL_REACH). A splash at every way in and out.
## Every machine decides this for every player itself (static water, predicted movement stays in
## step with the host's copy); the slow is per player and goes when the feet leave or the segment
## lets the players go (release_all).
## The origin is the top-left corner of the first cell; it covers cells first..last of one row.

const SURFACE_OFFSET := 26.0
const WAVE_HEIGHT := 2.5
const WAVE_SPEED := 2.4
## [water, surface line, glint, light] per biome.
const COLORS: Dictionary[StringName, Array] = {
	&"crypt": [Color(0.22, 0.34, 0.55, 0.72), Color(0.55, 0.72, 0.95, 0.9), Color(0.85, 0.95, 1.0, 0.8), Color(0.45, 0.6, 1.0)],
	&"slime_grotto": [Color(0.28, 0.62, 0.22, 0.78), Color(0.6, 0.95, 0.4, 0.95), Color(0.85, 1.0, 0.6, 0.8), Color(0.45, 0.95, 0.35)],
	&"shadow_realm": [Color(0.24, 0.14, 0.38, 0.8), Color(0.6, 0.45, 0.95, 0.9), Color(0.85, 0.75, 1.0, 0.8), Color(0.6, 0.4, 1.0)],
	&"ember_forge": [Color(0.5, 0.16, 0.05, 0.85), Color(1.0, 0.55, 0.15, 0.95), Color(1.0, 0.85, 0.4, 0.9), Color(1.0, 0.45, 0.1)],
}
## Delivered art (SPRITES_V10 §6): 4 frames of 32×32, one cell of liquid with its surface, tiled.
const ART_PATH := "res://art/environment/side/pool_%s_4f.png"
const ART_FRAME := Vector2i(32, 32)
const ART_FPS := 6.0

var cells := 1
var biome_id: StringName = &"crypt"
var segment: SideSegment = null

var _time := 0.0
## Player -> true while their feet are in the water (instance ids, freed players drop out).
var _inside: Dictionary[int, Player] = {}
var _has_art := false


func _ready() -> void:
	z_index = 1
	_time = position.x * 0.01
	var light := LightSource.new()
	light.name = "Glow"
	light.radius = 60.0 + cells * 24.0
	light.intensity = 0.45 if biome_id in [&"slime_grotto", &"ember_forge"] else 0.25
	light.flicker = 0.06
	light.color = _palette()[3]
	light.position = Vector2(cells * SideRules.TILE * 0.5, SURFACE_OFFSET + 10.0)
	add_child(light)
	var art_path := ART_PATH % biome_id
	if ResourceLoader.exists(art_path):
		_has_art = true
		var frames := SpriteStrip.make_frames(load(art_path) as Texture2D, ART_FRAME, ART_FPS, true)
		for i in cells:
			var sprite := AnimatedSprite2D.new()
			sprite.sprite_frames = frames
			sprite.centered = false
			sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
			sprite.position = Vector2(i * SideRules.TILE, 0.0)
			sprite.play(&"default")
			sprite.frame = i % 4
			add_child(sprite)


func _exit_tree() -> void:
	release_all()


## The water area (global): from the surface line to the bottom of the cells.
func get_rect() -> Rect2:
	return Rect2(global_position + Vector2(0, SURFACE_OFFSET - 6.0), Vector2(cells * SideRules.TILE, SideRules.TILE - SURFACE_OFFSET + 8.0))


func is_slowing(player: Player) -> bool:
	return is_instance_valid(player) and _inside.has(player.get_instance_id())


## Every slow of this pool off (players leaving the segment).
func release_all() -> void:
	for id in _inside.keys():
		var player := _inside[id]
		if is_instance_valid(player):
			ToxicPuddle.apply_slow(player, get_instance_id(), 1.0)
	_inside.clear()


func _physics_process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if segment == null:
		return
	var rect := get_rect()
	var seen: Dictionary[int, bool] = {}
	for player in segment.get_players():
		if not player.is_alive() or player.side_motion == null or not player.side_motion.is_active():
			continue
		var id := player.get_instance_id()
		if rect.has_point(player.get_feet_position()):
			seen[id] = true
			if not _inside.has(id):
				_inside[id] = player
				ToxicPuddle.apply_slow(player, get_instance_id(), SideRules.POOL_SLOW_FACTOR)
				_splash(player.get_feet_position())
	for id in _inside.keys():
		if seen.has(id):
			continue
		var player := _inside[id]
		_inside.erase(id)
		if is_instance_valid(player):
			ToxicPuddle.apply_slow(player, get_instance_id(), 1.0)
			_splash(player.get_feet_position())


func _splash(at: Vector2) -> void:
	if not is_inside_tree():
		return
	var palette := _palette()
	# Pixel drops thrown up and falling back (D-218).
	SideDust.spawn(get_parent(), Vector2(at.x, global_position.y + SURFACE_OFFSET), SideDust.Kind.CHIPS, 0.3, 0.0, palette[1])
	Sfx.play_at(self, &"slime_land", at, -10.0)


func _palette() -> Array:
	return COLORS.get(biome_id, COLORS[&"crypt"])


func _draw() -> void:
	if _has_art:
		return
	# Placeholder in pixels (D-218): columns of two art pixels, each with its surface pixel on the
	# wave, the liquid in two hard bands (lighter on top, deeper below).
	var palette := _palette()
	var width := cells * SideRules.TILE
	var bottom := SideRules.TILE
	var deep: Color = (palette[0] as Color).darkened(0.45)
	var column := SidePixels.PIXEL * 2.0
	var middle := roundf((SURFACE_OFFSET + bottom) * 0.5 / SidePixels.PIXEL) * SidePixels.PIXEL + SidePixels.PIXEL * 2.0
	var x := 0.0
	while x < width:
		var wave := SURFACE_OFFSET + sin(_time * WAVE_SPEED + (x + column * 0.5) * 0.06) * WAVE_HEIGHT
		var surface := roundf(wave / SidePixels.PIXEL) * SidePixels.PIXEL
		draw_rect(Rect2(x, surface, column, middle - surface), palette[0])
		draw_rect(Rect2(x, middle, column, bottom - middle), deep)
		draw_rect(Rect2(x, surface, column, SidePixels.PIXEL), palette[1])
		x += column
	# Glints drifting along the surface.
	for i in cells * 2:
		var glint_x := fposmod(i * 37.0 + _time * (14.0 + i * 3.0), width - 6.0)
		var y := SURFACE_OFFSET + 8.0 + float((i * 13) % 20)
		var glint: Color = palette[2]
		glint.a *= 0.4 + 0.4 * sin(_time * 3.0 + i)
		glint.a = roundf(glint.a * 3.0) / 3.0
		SidePixels.rect(self, Rect2(glint_x, y, 6.0, 2.0), glint)
	if biome_id in [&"slime_grotto", &"ember_forge"]:
		# Bubbles rising to the surface: pixel rings that grow by whole pixels.
		for i in cells + 1:
			var phase := fposmod(_time * 0.6 + i * 0.37, 1.0)
			var bubble_x := fposmod(i * 53.0 + 17.0, width)
			var y := lerpf(bottom - 6.0, SURFACE_OFFSET + 4.0, phase)
			var tint := Color(palette[2], SidePixels.fade(0.7, phase))
			SidePixels.ring(self, Vector2(bubble_x, y), SidePixels.PIXEL * (1.0 + roundf(phase)), tint)
