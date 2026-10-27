class_name WindRunnerTrail
extends Node2D
## Windläufer (KE6, KONZEPT §6.1): the light trail a dash leaves for TalentEffects.WIND_TRAIL_LIFETIME
## seconds. Enemies on it are slowed through their slow hook: apply_slow(factor, duration) on the
## enemy (enemies-dev builds it; until then the trail is only light). Art: wind_trail_4f.png
## (SPRITES_V13 Teil C, V13c talents_fx.json: 4 x 32x16, 10 fps, tiled along the dash), without it
## a drawn placeholder in pixel art (PixelDraw on the world grid, D-218). Fades in FADE_STEPS hard
## steps.

## An enemy stood on the trail (asked to slow down if it can; tests, effects).
signal enemy_on_trail(enemy: Node)

const SLOW_METHOD := &"apply_slow"
## How often the trail looks for enemies on it.
const CHECK_INTERVAL := 0.1
const COLOR := Color(0.75, 1.0, 0.95, 0.55)
const CORE_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const FADE_TIME := 0.4
const FADE_STEPS := 3
const ART_PATH := "res://art/effects/talents/wind_trail_4f.png"
const ART_FRAME := Vector2i(32, 16)
const ART_FRAMES := 4
const ART_FPS := 10.0

var from := Vector2.ZERO
var to := Vector2.ZERO
## The dashing player; its own body is never slowed.
var source: Node = null

var _time_left := TalentEffects.WIND_TRAIL_LIFETIME
var _check_left := 0.0
var _art: Texture2D = null


func _ready() -> void:
	if ResourceLoader.exists(ART_PATH):
		_art = load(ART_PATH) as Texture2D


static func create(start: Vector2, end: Vector2, owner_player: Node) -> WindRunnerTrail:
	var trail := WindRunnerTrail.new()
	trail.from = start
	trail.to = end
	trail.source = owner_player
	trail.z_index = -1
	return trail


func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()
		return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_INTERVAL
		_slow_enemies_on_trail()
	queue_redraw()


func get_time_left() -> float:
	return _time_left


## Enemies whose hurtbox touches the trail (a capsule from from to to).
func find_enemies() -> Array[Node]:
	var found: Array[Node] = []
	if not is_inside_tree():
		return found
	var shape := CapsuleShape2D.new()
	shape.radius = TalentEffects.WIND_TRAIL_HALF_WIDTH
	shape.height = from.distance_to(to) + TalentEffects.WIND_TRAIL_HALF_WIDTH * 2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	# The capsule stands along local y: turn it onto the dash direction.
	query.transform = Transform2D((to - from).angle() - PI * 0.5, (from + to) * 0.5)
	query.collision_mask = PhysicsLayers.ENEMY_HURTBOX
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(query, AreaDamage.MAX_TARGETS):
		var hurtbox := hit["collider"] as Node
		var enemy := hurtbox.get_parent() if hurtbox != null else null
		if enemy != null and enemy != source and not found.has(enemy):
			found.append(enemy)
	return found


func _slow_enemies_on_trail() -> void:
	for enemy in find_enemies():
		if enemy.has_method(SLOW_METHOD):
			enemy.call(SLOW_METHOD, TalentEffects.WIND_TRAIL_SLOW_FACTOR, TalentEffects.WIND_TRAIL_SLOW_TIME)
		enemy_on_trail.emit(enemy)


func _draw() -> void:
	var alpha := PixelDraw.stepped(_time_left / FADE_TIME, FADE_STEPS)
	if _art != null:
		_draw_art(to_local(from), to_local(to), alpha)
		return
	# World frame: the pixels sit on the world art-pixel grid.
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	paint(self, alpha)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The drawn placeholder in world coordinates into item (a CanvasItem drawing in the world frame, or
## a PixelDraw.Raster): a band as wide as the slowing capsule's core and a bright line in the middle.
func paint(item: Object, alpha: float) -> void:
	# The wide band as a filled pixel polygon (a thick brush line would cost thousands of cells).
	var side := (to - from).orthogonal().normalized() * TalentEffects.WIND_TRAIL_HALF_WIDTH * 0.6
	if side != Vector2.ZERO:
		PixelDraw.polygon(item, PackedVector2Array([from + side, to + side, to - side, from - side]), Color(COLOR, COLOR.a * alpha))
	PixelDraw.line(item, from, to, Color(CORE_COLOR, CORE_COLOR.a * alpha), 1)


## The delivered strip, one frame tiled from the start to the end of the dash.
func _draw_art(local_from: Vector2, local_to: Vector2, alpha: float) -> void:
	var elapsed := TalentEffects.WIND_TRAIL_LIFETIME - _time_left
	var frame := int(elapsed * ART_FPS) % ART_FRAMES
	var length := local_from.distance_to(local_to)
	var height := ART_FRAME.y * SpriteStrip.PIXEL_SCALE
	draw_set_transform(local_from, (local_to - local_from).angle())
	var region := Rect2(frame * ART_FRAME.x, 0, ART_FRAME.x, ART_FRAME.y)
	var tile_length := ART_FRAME.x * SpriteStrip.PIXEL_SCALE
	var x := 0.0
	while x < length:
		var piece := minf(tile_length, length - x)
		var source := Rect2(region.position, Vector2(region.size.x * piece / tile_length, region.size.y))
		draw_texture_rect_region(_art, Rect2(x, -height * 0.5, piece, height), source, Color(1, 1, 1, alpha))
		x += tile_length
	draw_set_transform(Vector2.ZERO)
