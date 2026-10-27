class_name SideSlopes
extends Node2D
## The slopes and ramps of a side layout (SV3, kept by D-216 in the two-way pieces; plan "(" ")"
## "[[" "]]"): the biome's slope art (art/environment/side/slope_<biome>[_down|_long|_long_down].png,
## 32×32 and 64×32, ×2) and one static body on the world layer with a polygon per slope cell, so the
## player runs up and down them with move_and_slide and keeps the momentum (a slope is a floor, no
## wall). Ramps: running off a slope's high edge into the air throws the runner up (ramp_lift), a
## static rule like the springs, decided for every player this machine moves (never for a copy of
## another machine's player, whose speed comes from there); the ramp a player runs on is kept on the
## player (PlayerSideMotion.ramp_cell, multiplayer rule). Placeholder until the art of a biome
## exists: the slope drawn in the biome's rock colour with a light edge. Child "Slopes" of the
## SideSegment when the layout has slopes. All numbers TESTWERT (D-195).

const NODE_NAME := &"Slopes"
const ART_DIR := "res://art/environment/side/"
const FALLBACK_BIOME := &"crypt"
## Placeholder colours (rock body, edge).
const BODY_COLOR := Color(0.33, 0.3, 0.42)
const EDGE_COLOR := Color(0.62, 0.58, 0.75)

## While a layout with slopes runs, the body counts slopes up to this steepness as floor (the 45°
## slopes sit right at Godot's default of 45° and a rectangle's corner on them reads as a wall now
## and then, which would stop the runner and cost the momentum; the corner at a slope's foot reads
## up to ~55°), keeps its speed up and down slopes and snaps this far down to the ground (fast runs
## down a 45° slope). PlayerSideMotion sets and restores the body.
const FLOOR_MAX_ANGLE_DEGREES := 60.0
const FLOOR_SNAP := 18.0
## Running off the high edge of a ramp throws the runner up: upward speed = running speed × the
## slope's rise per column × RAMP_LIFT (the body keeps no upward speed on a slope by itself; at the
## top speed of 2.0× a 45° ramp lifts about a tile).
const RAMP_LIFT := 1.4
## The body still stands on a ramp's tip this far past its edge (px, half the side body and a bit).
const RAMP_TIP := 14.0

var layout: SideLayout = null
var segment: SideSegment = null
var biome_id: StringName = FALLBACK_BIOME
## Slope cells drawn as placeholder (no art found), for tests.
var placeholder_cells := 0

var _body: StaticBody2D = null
## The ramp cells of the layout (ramps_of).
var _ramps: Dictionary[Vector2i, bool] = {}


static func create(owner_segment: SideSegment) -> SideSlopes:
	var slopes := SideSlopes.new()
	slopes.name = NODE_NAME
	slopes.segment = owner_segment
	slopes.layout = owner_segment.layout
	slopes.biome_id = owner_segment.layout.biome_id
	return slopes


func _ready() -> void:
	z_index = -5
	_body = StaticBody2D.new()
	_body.name = "Body"
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	add_child(_body)
	for cell in layout.slopes:
		var shape := layout.slope_at(cell)
		var polygon := CollisionPolygon2D.new()
		polygon.polygon = cell_polygon(shape)
		polygon.position = SideLayout.cell_origin(cell)
		_body.add_child(polygon)
		_add_art(cell, shape)
	for cell in ramps_of(layout):
		_ramps[cell] = true
	queue_redraw()


func get_body() -> StaticBody2D:
	return _body


# --- Ramps ---

## The ramps of a layout: slope cells whose high side opens into the air (a jump off at speed).
static func ramps_of(of_layout: SideLayout) -> Array[Vector2i]:
	var ramps: Array[Vector2i] = []
	for cell in of_layout.slopes:
		var high_side := high_side_of(of_layout.slope_at(cell))
		if high_side == 0:
			continue
		var beyond := cell + Vector2i(high_side, 0)
		if not of_layout.is_blocking(beyond) and not of_layout.is_slope(beyond):
			ramps.append(cell)
	return ramps


## +1 when a slope's high side is on the right, -1 on the left, 0 for the low half of a long slope.
static func high_side_of(shape: SideLayout.Slope) -> int:
	if shape == SideLayout.Slope.UP or shape == SideLayout.Slope.LONG_UP_HIGH:
		return 1
	if shape == SideLayout.Slope.DOWN or shape == SideLayout.Slope.LONG_DOWN_HIGH:
		return -1
	return 0


## Upward speed (px/s, > 0) for a runner leaving a ramp of shape at speed_x.
static func ramp_lift(shape: SideLayout.Slope, speed_x: float) -> float:
	var heights: Vector2 = SideLayout.SLOPE_HEIGHTS.get(shape, Vector2.ZERO)
	return absf(speed_x) * absf(heights.y - heights.x) * RAMP_LIFT


func _physics_process(_delta: float) -> void:
	if segment == null or segment.is_finished or _ramps.is_empty():
		return
	for player in segment.get_players():
		_update_ramp(player)


## Remembers the ramp under a player on the ground; leaving its high edge in the air throws them up
## (a jump of their own that rises faster stays).
func _update_ramp(player: Player) -> void:
	var motion := player.side_motion
	if motion == null or not motion.is_active() or motion.moves_from_remote:
		return
	var feet := segment.to_local(player.get_feet_position())
	if motion.is_on_floor():
		# Near the ramp's top the feet touch the cell above it; past its edge the body still rides
		# the tip for a few px (RAMP_TIP).
		var previous := motion.ramp_cell
		motion.ramp_cell = Vector2i(-1, -1)
		for probe in [Vector2(0, -4), Vector2(0, 4)]:
			var cell := SideLayout.cell_at(feet + probe)
			if _ramps.has(cell):
				motion.ramp_cell = cell
		if motion.ramp_cell.x < 0 and previous.x >= 0 and absf(feet.x - SideLayout.cell_center(previous).x) < SideRules.TILE * 0.5 + RAMP_TIP:
			motion.ramp_cell = previous
		return
	if motion.ramp_cell.x < 0:
		return
	var ramp := motion.ramp_cell
	motion.ramp_cell = Vector2i(-1, -1)
	var shape := layout.slope_at(ramp)
	if player.velocity.x * high_side_of(shape) <= 0.0:
		# Off the low side (backwards): no throw.
		return
	var lift := ramp_lift(shape, player.velocity.x)
	if player.velocity.y > -lift and lift > 1.0:
		motion.launch(-lift)
		motion.ramp_launches += 1


# --- Looks ---

## The solid part of a slope cell (local to the cell's top-left corner, px).
static func cell_polygon(shape: SideLayout.Slope) -> PackedVector2Array:
	var tile := SideRules.TILE
	var heights: Vector2 = SideLayout.SLOPE_HEIGHTS.get(shape, Vector2.ZERO)
	var left := tile - heights.x * tile
	var right := tile - heights.y * tile
	var points := PackedVector2Array([Vector2(0, left), Vector2(tile, right), Vector2(tile, tile), Vector2(0, tile)])
	# A corner at the bottom (height 0) collapses into a triangle.
	if is_equal_approx(left, tile):
		points = PackedVector2Array([Vector2(0, tile), Vector2(tile, right), Vector2(tile, tile)])
	elif is_equal_approx(right, tile):
		points = PackedVector2Array([Vector2(0, left), Vector2(tile, tile), Vector2(0, tile)])
	return points


## Art file pattern drawn at a slope cell; "" for the second half of a long slope (the first half
## draws both).
static func art_name(shape: SideLayout.Slope) -> String:
	match shape:
		SideLayout.Slope.UP:
			return "slope_%s.png"
		SideLayout.Slope.DOWN:
			return "slope_%s_down.png"
		SideLayout.Slope.LONG_UP_LOW:
			return "slope_%s_long.png"
		SideLayout.Slope.LONG_DOWN_HIGH:
			return "slope_%s_long_down.png"
	return ""


## The art that covers a slope cell (the second half of a long slope: its first half's).
static func covering_art_name(shape: SideLayout.Slope) -> String:
	match shape:
		SideLayout.Slope.LONG_UP_HIGH:
			return art_name(SideLayout.Slope.LONG_UP_LOW)
		SideLayout.Slope.LONG_DOWN_LOW:
			return art_name(SideLayout.Slope.LONG_DOWN_HIGH)
	return art_name(shape)


func _add_art(cell: Vector2i, shape: SideLayout.Slope) -> void:
	var pattern := art_name(shape)
	if pattern.is_empty():
		return
	var texture := _texture(pattern)
	if texture == null:
		placeholder_cells += 1
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	sprite.position = SideLayout.cell_origin(cell)
	add_child(sprite)


func _texture(pattern: String) -> Texture2D:
	for biome in [biome_id, FALLBACK_BIOME]:
		var path := ART_DIR + pattern % biome
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## Placeholder for slopes without art: the solid part and a light edge along the line, in pixels
## (D-218).
func _draw() -> void:
	if placeholder_cells == 0:
		return
	var tile := SideRules.TILE
	for cell in layout.slopes:
		var shape := layout.slope_at(cell)
		if _texture(covering_art_name(shape)) != null:
			continue
		var origin := SideLayout.cell_origin(cell)
		var moved := PackedVector2Array()
		for point in cell_polygon(shape):
			moved.append(point + origin)
		SidePixels.polygon(self, moved, BODY_COLOR)
		var heights: Vector2 = SideLayout.SLOPE_HEIGHTS[shape]
		SidePixels.line(self, origin + Vector2(0, tile - heights.x * tile), origin + Vector2(tile - SidePixels.PIXEL, tile - heights.y * tile), EDGE_COLOR, 2)
