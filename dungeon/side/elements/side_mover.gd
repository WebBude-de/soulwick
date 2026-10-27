class_name SideMover
extends AnimatableBody2D
## A moving platform of the jump trial (bewegte Plattform, SV2, D-195; plan "M" on a track "-"
## sideways, "V" on a track "|" up and down): a one-way platform that goes back and forth along its
## track with a short rest at each end and carries whoever stands on it (an AnimatableBody2D synced
## to physics, so CharacterBody2D takes its motion along). Its place is a pure function of the clock
## (seconds since the segment began) and a phase from the segment seed and its build index
## (SideElementRules.ping_pong / phase_for): every machine computes the same place. Group game: the
## host's clock is the truth, a client's platforms follow it (apply_clock, hook for NetSide). The
## origin of the node is the plan position's top-left corner plus the travel; the track is drawn
## behind it as a pixel guide line (D-218: dashes of art pixels that move along with the platform,
## so its way and its direction read at a glance, and a small pixel stop at each end).
## Art: moving_platform_<biome>.png (96×16: left, middle, right piece of 32), else a drawn slab. The
## picture is lifted by the rows above its slab (SidePixels.surface_row: the rivets on top), so the
## feet stand on the drawn slab and not on the air above it (FS1: the player seemed to float).

const ART_PATH := "res://art/environment/side/moving_platform_%s.png"
const PIECE := 32
const PLACEHOLDER_COLOR := Color(0.42, 0.38, 0.5)
## TESTWERTE (look, FS1): guide line colour, dash and gap in art pixels.
const TRACK_COLOR := Color(0.85, 0.8, 0.95, 0.35)
const TRACK_DASH_PX := 2
const TRACK_GAP_PX := 3
## Surface row of the delivered art when the picture cannot be read (rivets in rows 0-2).
const SURFACE_ROW_FALLBACK := 3

var mover: SideLayout.Mover = null
var biome_id: StringName = &"crypt"
## Seconds since the segment began (host: its own; client: the host's through apply_clock).
var clock := 0.0
## Start phase in seconds (SideElementRules.phase_for).
var phase := 0.0

var _plan_origin := Vector2.ZERO
var _track: _Track = null


## Before entering the tree: the plan's platform, the biome look, the segment seed and the build
## index (the phase).
func setup(plan_mover: SideLayout.Mover, biome: StringName, segment_seed: int, index: int) -> void:
	mover = plan_mover
	biome_id = biome
	_plan_origin = SideLayout.cell_origin(Vector2i(mover.first, mover.row))
	phase = SideElementRules.phase_for(segment_seed, index, cycle())
	name = "Mover%d_%d" % [mover.first, mover.row]


func _ready() -> void:
	sync_to_physics = true
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	z_index = -4
	var width := mover.width() * SideRules.TILE
	var box := RectangleShape2D.new()
	box.size = Vector2(width, SideElementRules.MOVER_DEPTH)
	var shape := CollisionShape2D.new()
	shape.shape = box
	shape.one_way_collision = true
	shape.position = box.size * 0.5
	add_child(shape)
	_build_look()
	_track = _Track.new()
	_track.name = "Track"
	_track.from = local_offset_at_tiles(mover.low)
	_track.to = local_offset_at_tiles(mover.high)
	_track.width = width
	_track.z_index = -1
	get_parent().add_child.call_deferred(_track)
	_track.position = _plan_origin
	_move_to(clock)


func _physics_process(delta: float) -> void:
	clock += delta
	_move_to(clock)


## The host's clock on a client (NetSide hook): the same place at once.
func apply_clock(time: float) -> void:
	clock = time
	_move_to(clock)


func _move_to(time: float) -> void:
	# The node itself shows the new place only after the physics step (sync_to_physics), so the
	# guide line takes the computed place.
	var place := position_at(time)
	position = place
	if is_instance_valid(_track):
		_track.set_travel(roundi((place - _plan_origin - local_offset_at_tiles(mover.low)).dot(Vector2(mover.axis)) / SidePixels.PIXEL))


## Seconds of one full back-and-forth.
func cycle() -> float:
	return SideElementRules.period(_track_length(), SideElementRules.MOVER_SPEED, SideElementRules.MOVER_PAUSE)


## Local position (in the segment) of the platform at a clock time.
func position_at(time: float) -> Vector2:
	var travel := SideElementRules.ping_pong(time + phase, _track_length(), SideElementRules.MOVER_SPEED,
			SideElementRules.MOVER_PAUSE, true)
	return _plan_origin + local_offset_at_tiles(mover.low) + Vector2(mover.axis) * travel


## Offset of the platform from its plan position at a whole number of tiles along the track.
func local_offset_at_tiles(tiles: int) -> Vector2:
	return Vector2(mover.axis) * tiles * SideRules.TILE


## Offset in tiles along the track (low..high, fractional) at a clock time (the bot plans with it).
func offset_tiles_at(time: float) -> float:
	return (position_at(time) - _plan_origin).dot(Vector2(mover.axis)) / SideRules.TILE


## The stand cells on the platform at a clock time (rounded to the nearest whole offset).
func stand_cells_at(time: float) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in mover.cells_at(roundi(offset_tiles_at(time))):
		cells.append(cell + Vector2i.UP)
	return cells


## The standing strip on top (global).
func get_top_rect() -> Rect2:
	return Rect2(global_position + Vector2(0, -8), Vector2(mover.width() * SideRules.TILE, 14))


## Whether feet (global) stand on the platform.
func carries(feet: Vector2) -> bool:
	return get_top_rect().has_point(feet)


## Middle of the top edge (global) at a clock time.
func top_center_at(time: float) -> Vector2:
	var local := position_at(time) + Vector2(mover.width() * SideRules.TILE * 0.5, 0.0)
	var segment := get_parent() as Node2D
	return segment.to_global(local) if segment != null else local


func _track_length() -> float:
	return (mover.high - mover.low) * SideRules.TILE


func _build_look() -> void:
	var path := ART_PATH % biome_id
	if not ResourceLoader.exists(path):
		path = ART_PATH % SideTiles.FALLBACK_BIOME
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	var cells := mover.width()
	var lift := 0.0
	if texture != null:
		lift = SidePixels.surface_row(texture, Rect2i(PIECE, 0, PIECE, texture.get_height()), SURFACE_ROW_FALLBACK) * SpriteStrip.PIXEL_SCALE
	for i in cells:
		if texture == null:
			var slab := ColorRect.new()
			slab.color = PLACEHOLDER_COLOR
			slab.position = Vector2(i * SideRules.TILE + 1.0, 0.0)
			slab.size = Vector2(SideRules.TILE - 2.0, SideElementRules.MOVER_ART_HEIGHT)
			slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(slab)
			continue
		var piece := 1
		if cells > 1 and i == 0:
			piece = 0
		elif cells > 1 and i == cells - 1:
			piece = 2
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = Rect2(piece * PIECE, 0, PIECE, texture.get_height())
		sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		sprite.position = Vector2(i * SideRules.TILE, -lift)
		add_child(sprite)


## Pixels the picture is lifted by (tests: the drawn slab starts at the collision top).
func get_art_lift() -> float:
	for child in get_children():
		if child is Sprite2D:
			return -(child as Sprite2D).position.y
	return 0.0


## The track behind the platform (D-218): a pixel guide line from end to end whose dashes travel with
## the platform (its direction reads from them) and a small pixel stop at each end.
class _Track:
	extends Node2D
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var width := 64.0
	## Art pixels the platform has travelled from its low end (moves the dashes).
	var travel_px := 0

	func set_travel(pixels: int) -> void:
		if pixels == travel_px:
			return
		travel_px = pixels
		queue_redraw()

	func _draw() -> void:
		var middle := SidePixels.snap(Vector2(width * 0.5, 10.0))
		var a := from + middle
		var b := to + middle
		var color := SideMover.TRACK_COLOR
		SidePixels.dashed(self, a, b, color, SideMover.TRACK_DASH_PX, SideMover.TRACK_GAP_PX, 1, -travel_px)
		for end in [a, b]:
			SidePixels.frame(self, Rect2(end - Vector2.ONE * SidePixels.PIXEL * 2.0, Vector2.ONE * SidePixels.PIXEL * 5.0), color)
