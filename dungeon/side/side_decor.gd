class_name SideDecor
extends Node2D
## Biome dressing of a side segment (M5 round 3, team member: "alles, was im Top-down existiert, im
## Jump'n'Run abgebildet"; F9 note: "sieht recht langweilig aus"). Look only, no collision, no
## gameplay:
## - props on free floor cells: the biome's deco groups of the rooms that read from the side too
##   (graves, mushroom beds, crystals, forge corners; not the flat slime puddle) and single props (candles, bones, mushrooms, crystals, anvil, barrel, brazier),
##   the glowing ones with a small light;
## - things hanging from rock: chains (crypt, ember forge), roots and drips (grotto), crystal shards
##   (shadow realm);
## - soft shade under every overhang and ledge, so the platforms stand out from the back wall.
## Placement comes from its own RNG derived from the plan (plan id, mirror): every machine dresses
## the same segment the same way, and the segment's gameplay RNG stays untouched.

const PROPS_DIR := "res://art/environment/props/"
const DECO_DIR := "res://art/environment/deco/"
## [file, glow colour (alpha 0 = none), animated frames (0 = still)] per biome; wide ones (64 px)
## need two free cells.
const PROPS: Dictionary[StringName, Array] = {
	&"crypt": [
		["deco/deco_group_crypt_1.png", Color(1.0, 0.75, 0.4, 0.0), 0],
		["deco/deco_group_crypt_2.png", Color(1.0, 0.75, 0.4, 0.0), 0],
		["deco/deco_group_crypt_3.png", Color(1.0, 0.75, 0.4, 0.0), 0],
		["deco/candles_cluster.png", Color(1.0, 0.75, 0.4, 0.5), 0],
		["props/bones_1.png", Color(0, 0, 0, 0), 0],
		["props/bones_2.png", Color(0, 0, 0, 0), 0],
		["deco/pillar_fallen.png", Color(0, 0, 0, 0), 0],
	],
	&"slime_grotto": [
		["deco/deco_group_slime_grotto_1.png", Color(0.5, 1.0, 0.45, 0.35), 0],
		["deco/deco_group_slime_grotto_2.png", Color(0.5, 1.0, 0.45, 0.35), 0],
		["props/mushrooms.png", Color(0.75, 0.5, 1.0, 0.45), 0],
		["props/mushrooms.png", Color(0.75, 0.5, 1.0, 0.45), 0],
	],
	&"shadow_realm": [
		["deco/deco_group_shadow_realm_1.png", Color(0.6, 0.45, 1.0, 0.35), 0],
		["deco/deco_group_shadow_realm_2.png", Color(0.6, 0.45, 1.0, 0.35), 0],
		["deco/deco_group_shadow_realm_3.png", Color(0.6, 0.45, 1.0, 0.35), 0],
		["props/crystal_cluster.png", Color(0.45, 1.0, 0.8, 0.5), 0],
		["props/bones_1.png", Color(0, 0, 0, 0), 0],
	],
	&"ember_forge": [
		["deco/deco_group_ember_forge_1.png", Color(1.0, 0.5, 0.15, 0.35), 0],
		["deco/deco_group_ember_forge_2.png", Color(1.0, 0.5, 0.15, 0.35), 0],
		["deco/deco_group_ember_forge_3.png", Color(1.0, 0.5, 0.15, 0.35), 0],
		["props/anvil_broken.png", Color(0, 0, 0, 0), 0],
		["props/barrel.png", Color(0, 0, 0, 0), 0],
		["props/brazier_4f.png", Color(1.0, 0.55, 0.2, 0.8), 4],
	],
}
## What hangs from the rock: "chains" (texture), "roots", "crystals" (drawn here), "drips" (strip).
const HANGING: Dictionary[StringName, Array] = {
	&"crypt": ["chains"],
	&"slime_grotto": ["roots", "drips"],
	&"shadow_realm": ["crystals", "chains"],
	&"ember_forge": ["chains"],
}
const CHAINS_TEXTURE := "props/chains.png"
const DRIPS_TEXTURE := "deco/drip_4f.png"
## Delivered art for the drawn hangings (SPRITES_V10 §6): hang_roots.png, hang_crystals.png, 32×48,
## top edge = the rock.
const HANG_ART := "side/hang_%s.png"
## At most this many opaque rows at the top of a hanging count as its strip of rock (rock_rows_of).
const HANG_ROCK_ROWS_MAX := 8
static var _rock_rows: Dictionary = {}
## TESTWERTE (look): share of free floor cells with a prop, columns kept free between two props,
## share of ceiling cells with something hanging, spacing between those.
const PROP_CHANCE := 0.42
const PROP_SPACING := 3
const HANG_CHANCE := 0.3
const HANG_SPACING := 4
## Shade under overhangs and ledges: height (px) and darkness at the rock.
const SHADE_HEIGHT := 46.0
const SHADE_ALPHA := 0.42
const ROOT_COLORS: Dictionary[StringName, Color] = {
	&"slime_grotto": Color("#2c4a2a"),
}
const CRYSTAL_COLOR := Color(0.62, 0.45, 1.0)

var layout: SideLayout = null
## Props and hangings placed (tests, tools).
var prop_count := 0
var hang_count := 0

var _rng := RandomNumberGenerator.new()
## Hangings drawn in _draw: [kind, local top-centre, length].
var _drawn: Array[Array] = []


static func create(segment_layout: SideLayout) -> SideDecor:
	var decor := SideDecor.new()
	decor.name = "Decor"
	decor.layout = segment_layout
	return decor


## The placement seed of a layout (the same on every machine).
static func seed_for(segment_layout: SideLayout) -> int:
	return hash([String(segment_layout.plan_id), segment_layout.is_mirrored, String(segment_layout.biome_id), "side_decor"])


func _ready() -> void:
	z_index = -3
	if layout == null:
		return
	_rng.seed = seed_for(layout)
	var shade := _Shade.new()
	shade.name = "Shade"
	shade.layout = layout
	shade.z_index = -3
	add_child(shade)
	_place_props()
	_place_hangings()


## Free floor cells: on rock (not a ledge), nothing of the plan in them or next to start and door.
func free_floor_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var taken: Dictionary[Vector2i, bool] = {}
	for list: Array in [layout.coins, layout.slimes, layout.skeletons, layout.spikes, layout.turrets, layout.torches]:
		for cell: Vector2i in list:
			taken[cell] = true
	for cell in [layout.start, layout.door, layout.chest, layout.golden_coin]:
		for dx in range(-1, 2):
			taken[cell + Vector2i(dx, 0)] = true
	for row in range(1, layout.size.y):
		for column in range(1, layout.size.x - 1):
			var cell := Vector2i(column, row)
			if taken.has(cell) or layout.char_at(cell) != SideLayout.AIR:
				continue
			if not layout.is_rock(cell + Vector2i.DOWN) or layout.ladders.has(column):
				continue
			cells.append(cell)
	return cells


func _place_props() -> void:
	var options: Array = PROPS.get(layout.biome_id, PROPS[&"crypt"])
	var free := free_floor_cells()
	var free_set: Dictionary[Vector2i, bool] = {}
	for cell in free:
		free_set[cell] = true
	var last_column := -100
	var last_row := -1
	for cell in free:
		if cell.y == last_row and cell.x - last_column <= PROP_SPACING:
			continue
		if _rng.randf() >= PROP_CHANCE:
			continue
		var pick: Array = options[_rng.randi_range(0, options.size() - 1)]
		var texture := load(_path(pick[0])) as Texture2D if ResourceLoader.exists(_path(pick[0])) else null
		if texture == null:
			continue
		var frames := int(pick[2])
		var width := texture.get_width() / maxi(1, frames)
		if width > 32 and not free_set.has(cell + Vector2i.RIGHT):
			continue
		_add_prop(cell, texture, frames, width, pick[1])
		last_column = cell.x + (1 if width > 32 else 0)
		last_row = cell.y


func _add_prop(cell: Vector2i, texture: Texture2D, frames: int, width: int, glow: Color) -> void:
	var feet := SideLayout.feet_of(cell)
	if width > 32:
		feet.x += SideRules.TILE * 0.5
	var flip := _rng.randf() < 0.5
	var node: Node2D
	if frames > 1:
		var animated := AnimatedSprite2D.new()
		animated.sprite_frames = SpriteStrip.make_frames(texture, Vector2i(width, texture.get_height()), 8.0, true)
		animated.play(&"default")
		animated.frame = _rng.randi_range(0, frames - 1)
		animated.flip_h = flip
		node = animated
	else:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.flip_h = flip
		node = sprite
	node.set(&"centered", false)
	node.set(&"offset", Vector2(-width * 0.5, -texture.get_height()))
	node.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	node.position = feet + Vector2(0, 2)
	add_child(node)
	prop_count += 1
	if glow.a > 0.0:
		var light := LightSource.new()
		light.radius = 70.0 + 40.0 * glow.a
		light.intensity = glow.a
		light.flicker = 0.06
		light.color = Color(glow, 1.0)
		light.position = feet + Vector2(0, -24)
		add_child(light)


## Rock cells with air below (ceiling and overhangs), spaced out.
func ceiling_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in range(0, layout.size.y - 2):
		for column in range(1, layout.size.x - 1):
			var cell := Vector2i(column, row)
			var below := cell + Vector2i.DOWN
			if layout.is_rock(cell) and layout.char_at(below) == SideLayout.AIR and layout.char_at(below + Vector2i.DOWN) in [SideLayout.AIR, SideLayout.COIN, SideLayout.TORCH]:
				cells.append(cell)
	return cells


func _place_hangings() -> void:
	var kinds: Array = HANGING.get(layout.biome_id, HANGING[&"crypt"])
	var last := -100
	for cell in ceiling_cells():
		if cell.x - last <= HANG_SPACING or _rng.randf() >= HANG_CHANCE:
			continue
		last = cell.x
		var kind: String = kinds[_rng.randi_range(0, kinds.size() - 1)]
		var top := Vector2((cell.x + 0.5) * SideRules.TILE, (cell.y + 1) * SideRules.TILE)
		match kind:
			"chains":
				var path := _path(CHAINS_TEXTURE)
				if not ResourceLoader.exists(path):
					continue
				var texture := load(path) as Texture2D
				for i in _rng.randi_range(1, 2):
					var sprite := Sprite2D.new()
					sprite.texture = texture
					sprite.centered = false
					sprite.offset = Vector2(-texture.get_width() * 0.5, 0)
					sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
					sprite.position = top + Vector2(0, i * texture.get_height() * SpriteStrip.PIXEL_SCALE - 4.0)
					sprite.modulate = Color(0.8, 0.8, 0.85)
					add_child(sprite)
			"drips":
				var drips := _path(DRIPS_TEXTURE)
				if not ResourceLoader.exists(drips):
					continue
				var strip := load(drips) as Texture2D
				var animated := AnimatedSprite2D.new()
				animated.sprite_frames = SpriteStrip.make_frames(strip, Vector2i(strip.get_width() / 4, strip.get_height()), 5.0, true)
				animated.centered = false
				animated.offset = Vector2(-strip.get_width() / 8.0, 0)
				animated.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
				animated.position = top
				animated.play(&"default")
				animated.frame = _rng.randi_range(0, 3)
				add_child(animated)
			_:
				var length := _rng.randf_range(28.0, 70.0)
				var wobble := _rng.randf()
				var art := _path(HANG_ART % kind)
				if ResourceLoader.exists(art):
					var hanging := Sprite2D.new()
					hanging.texture = load(art) as Texture2D
					hanging.centered = false
					# The delivered art starts with a strip of its own rock (opaque rows): left out, the
					# hanging grows out of the segment's ceiling (bug report 17.10.2026 #a1bd7c42: a dark
					# box under the ceiling).
					var rock_rows := rock_rows_of(hanging.texture)
					if rock_rows > 0:
						hanging.region_enabled = true
						hanging.region_rect = Rect2(0, rock_rows, hanging.texture.get_width(), hanging.texture.get_height() - rock_rows)
					hanging.offset = Vector2(-hanging.texture.get_width() * 0.5, 0)
					hanging.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
					hanging.flip_h = wobble < 0.5
					hanging.position = top
					add_child(hanging)
				else:
					_drawn.append([kind, top, length, wobble])
		hang_count += 1
	queue_redraw()


func _draw() -> void:
	for entry in _drawn:
		var kind: String = entry[0]
		var top: Vector2 = entry[1]
		var length: float = entry[2]
		var wobble: float = entry[3]
		if kind == "roots":
			var color: Color = ROOT_COLORS.get(layout.biome_id, Color("#2c4a2a"))
			for strand in 3:
				var points := PackedVector2Array()
				var x0 := top.x + (strand - 1) * 9.0
				for i in 7:
					var t := i / 6.0
					points.append(Vector2(x0 + sin(t * 5.0 + wobble * 6.0 + strand) * 4.0 * t, top.y - 2.0 + length * t * (0.7 + 0.15 * strand)))
				draw_polyline(points, color, 3.0 - strand * 0.6)
				# A glowing bead at the tip.
				draw_circle(points[points.size() - 1], 2.0, Color(0.6, 1.0, 0.5, 0.7))
		elif kind == "crystals":
			for shard in 3:
				var x := top.x + (shard - 1) * 12.0
				var h := length * (0.5 + 0.25 * ((shard + int(wobble * 3.0)) % 3))
				var tip := Vector2(x, top.y + h)
				draw_colored_polygon(PackedVector2Array([Vector2(x - 5, top.y - 2), Vector2(x + 5, top.y - 2), tip]), CRYSTAL_COLOR.darkened(0.35))
				draw_colored_polygon(PackedVector2Array([Vector2(x - 1, top.y), Vector2(x + 4, top.y), tip]), Color(CRYSTAL_COLOR, 0.85))


## Leading rows of a hanging's art that are opaque all across (its strip of rock), cached per path.
static func rock_rows_of(texture: Texture2D) -> int:
	if texture == null:
		return 0
	var key := texture.resource_path
	if _rock_rows.has(key):
		return _rock_rows[key]
	var image := texture.get_image()
	var rows := 0
	if image != null:
		if image.is_compressed():
			image.decompress()
		for y in mini(image.get_height() / 2, HANG_ROCK_ROWS_MAX):
			var solid := true
			for x in image.get_width():
				if image.get_pixel(x, y).a < 0.9:
					solid = false
					break
			if not solid:
				break
			rows += 1
	_rock_rows[key] = rows
	return rows


func _path(relative: String) -> String:
	return ("res://art/environment/" + relative)


## Soft shade under every overhang and ledge (drawn over the back wall, behind the rock).
class _Shade:
	extends Node2D
	var layout: SideLayout = null

	func _draw() -> void:
		var tile := SideRules.TILE
		var dark := Color(0.0, 0.0, 0.02, SideDecor.SHADE_ALPHA)
		var clear := Color(0.0, 0.0, 0.02, 0.0)
		for row in range(0, layout.size.y - 1):
			for column in range(1, layout.size.x - 1):
				var cell := Vector2i(column, row)
				if not layout.is_blocking(cell) or layout.is_blocking(cell + Vector2i.DOWN):
					continue
				var top := (row + 1) * tile
				var x := column * tile
				draw_polygon(PackedVector2Array([Vector2(x, top), Vector2(x + tile, top), Vector2(x + tile, top + SideDecor.SHADE_HEIGHT), Vector2(x, top + SideDecor.SHADE_HEIGHT)]),
						PackedColorArray([dark, dark, clear, clear]))
