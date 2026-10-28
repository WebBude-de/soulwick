extends Node
## P1-2 "Ziel und Weg zum Dungeon": until the first run of a world the village shows the way down.
## - A trail of soul lights (small violet glows like the flame bowl) drifts along the path from the
##   spawn across the square and up the stairs to the ruin. It is drawn on a canvas layer that follows
##   the camera above the darkness (VisionOverlay, layer 2), so the way is visible at night too.
## - An arrow (art/ui/teammate_arrow.png, tinted gold) at the screen edge points to the entrance
##   while it is off screen and bobs above the ruin once it is in view.
## - FS6 (D-220) "Herumirren": when the player has not come closer to the entrance than ever before
##   for STRAY_TIME s (the timer waits while Flint or a dialog holds him, paused_check), trail and
##   arrow grow stronger: brighter, twice as many soul lights, pulsing in whole art pixels; the arrow
##   one art scale larger on every other beat and lighter gold. Getting closer than ever, or
##   RECOVER_STEP px closer than the farthest point since, makes them normal again. No Flint sentence.
## The goal line is VillageGoal's (shown by VillageUI.show_goal); this class decides when the way is
## due (is_active). The chronicler's opening words are gone: Flint's village tour greets now
## (WK9, VillageTour).
## Koop: pure optics at this machine. The state is this player's world (runs, seen flag), the arrow
## follows this machine's camera (get_viewport); the distance comes from the village (its players at
## this machine, distance_source), no player lookup here; nothing is sent.
## No class_name: used through preload (Village.GuideScript), so it works before the class cache
## knows it.

const ARROW_TEXTURE: Texture2D = preload("res://art/ui/teammate_arrow.png")
## Above the darkness (VisionOverlay 2), below the HUD (5) and the village dialogs (20).
const TRAIL_LAYER := 3
const POINTER_LAYER := 4
const TILE := 64.0
## Way between spawn and entrance in tiles of tools/generate_village.py (south path, past the
## fountain across the square, the climb at its north-east corner, the stairs in the ridge).
const WAYPOINT_TILES: Array[Vector2] = [
	Vector2(16.0, 14.4), Vector2(19.4, 10.7), Vector2(21.7, 9.1), Vector2(22.9, 7.7), Vector2(23.0, 6.0),
]
## The trail ends in front of the ruin's stairs (world px from the entrance pivot).
const TRAIL_END_OFFSET := Vector2(0, 30)
## TESTWERT: trail of soul lights (world px, px/s, seconds).
const MOTE_SPACING := 64.0
const MOTE_SPEED := 72.0
## Village art pixel in world px (32 px tiles drawn on 64 px) and the mote's rings from the outside
## in: [radius in art pixels, alpha, core colour]; drawn over each other, so the glow steps.
const MOTE_PIXEL := 2.0
const MOTE_RINGS: Array = [[5, 0.12, false], [3, 0.3, false], [2, 0.6, false], [1, 0.95, true]]
const MOTE_FLOAT := 3.0
const MOTE_EDGE_FADE := 90.0
const SOUL_COLOR := Color(0.72, 0.45, 1.0)
const SOUL_CORE := Color(1.0, 0.93, 1.0)
## TESTWERT: arrow (art scale, screen px kept free at the edges: left, top, right, bottom - the
## goal line and the currencies at the top, the HUD rows at the bottom; world px above the entrance
## pivot, over the ruin's doorway; bob).
const ARROW_SCALE := 4.0
const ARROW_INSETS: Array[float] = [56.0, 104.0, 56.0, 104.0]
const ARROW_ABOVE := 150.0
const ARROW_BOB := 6.0
const ARROW_BOB_SPEED := 3.2
const ARROW_COLOR := Color("#f2cf4a")
## TESTWERT (FS6, D-220): straying. Seconds without getting closer than ever (by APPROACH_STEP world
## px) before the way grows stronger; while strong, this much closer than the farthest point since
## counts as coming back; blend time (s); one pulse beat (s); ring alpha factor; strong arrow colour.
const STRAY_TIME := 45.0
const APPROACH_STEP := 48.0
const RECOVER_STEP := 192.0
const STRONG_BLEND_TIME := 0.4
const STRONG_BEAT := 0.3
const STRONG_ALPHA := 1.7
const STRONG_ARROW_COLOR := Color("#fff1a8")

## Emitted when the way grows stronger (true) or normal again (false).
signal strength_changed(strong: bool)

## Entrance pivot (world px).
var target := Vector2.ZERO
## Hides the arrow while it returns true (the village: a dialog is open).
var hidden_check := Callable()
## FS6: distance of this machine's player to the entrance (world px, INF without one) and the check
## that holds the stray timer (Flint talks, a dialog is open). Set by the village.
var distance_source := Callable()
var paused_check := Callable()

var _points := PackedVector2Array()
var _length := 0.0
var _time := 0.0
var _trail_layer: CanvasLayer = null
var _trail: Node2D = null
var _pointer_layer: CanvasLayer = null
var _pointer: Control = null
## Last arrow placement: screen position, angle, on screen (tests and tools).
var _pointer_position := Vector2.ZERO
var _pointer_angle := 0.0
var _pointer_on_screen := false
## Straying (FS6): closest distance so far, seconds since, strong state, farthest distance since it
## became strong, the drawn strength (0 normal .. 1 strong).
var _best := INF
var _stray := 0.0
var _strong := false
var _far := 0.0
var _strength := 0.0


## Until the first run of the world (the stat counts started runs).
static func is_active() -> bool:
	return int(SaveManager.get_stat(StatsTracker.RUNS)) <= 0


## start: the player spawn, entrance: the ruin's pivot (world px). Call before adding it.
func setup(start: Vector2, entrance: Vector2) -> void:
	name = "VillageGuide"
	target = entrance
	_points = build_points(start, entrance)
	_length = path_length(_points)


## Spawn, the waypoints, the foot of the stairs.
static func build_points(start: Vector2, entrance: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([start])
	for tile in WAYPOINT_TILES:
		points.append(tile * TILE)
	points.append(entrance + TRAIL_END_OFFSET)
	return points


static func path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## Point at distance along the polyline (clamped to its ends).
static func point_at(points: PackedVector2Array, distance: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var left := maxf(distance, 0.0)
	for i in range(1, points.size()):
		var segment := points[i - 1].distance_to(points[i])
		if left <= segment and segment > 0.0:
			return points[i - 1].lerp(points[i], left / segment)
		left -= segment
	return points[points.size() - 1]


## The part of a view the arrow stays in (ARROW_INSETS kept free).
static func inner_rect(view: Vector2) -> Rect2:
	var top_left := Vector2(ARROW_INSETS[0], ARROW_INSETS[1])
	var bottom_right := view - Vector2(ARROW_INSETS[2], ARROW_INSETS[3])
	return Rect2(top_left, (bottom_right - top_left).max(Vector2.ONE))


## Where the arrow goes: [screen position, angle (rad, 0 = right), on screen]. While the target is
## inside inner it hangs `above` px over it pointing down (kept inside inner); otherwise it sits on
## the edge of inner on the line from its centre to the target, pointing at the target.
static func place_pointer(target_screen: Vector2, inner: Rect2, above := 0.0) -> Array:
	if inner.has_point(target_screen):
		var spot := (target_screen - Vector2(0, above)).clamp(inner.position, inner.end)
		return [spot, PI * 0.5, true]
	var center := inner.get_center()
	var direction := target_screen - center
	var half := inner.size * 0.5
	var factor := INF
	if absf(direction.x) > 0.001:
		factor = minf(factor, half.x / absf(direction.x))
	if absf(direction.y) > 0.001:
		factor = minf(factor, half.y / absf(direction.y))
	if is_inf(factor):
		factor = 0.0
	return [center + direction * factor, direction.angle(), false]


func _ready() -> void:
	# Also while a dialog pauses the village (single player): the arrow has to hide then.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_trail_layer = CanvasLayer.new()
	_trail_layer.name = "TrailLayer"
	_trail_layer.layer = TRAIL_LAYER
	_trail_layer.follow_viewport_enabled = true
	add_child(_trail_layer)
	_trail = Node2D.new()
	_trail.name = "Trail"
	_trail.draw.connect(_draw_trail)
	_trail_layer.add_child(_trail)

	_pointer_layer = CanvasLayer.new()
	_pointer_layer.name = "PointerLayer"
	_pointer_layer.layer = POINTER_LAYER
	add_child(_pointer_layer)
	_pointer = Control.new()
	_pointer.name = "Pointer"
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer.draw.connect(_draw_pointer)
	_pointer_layer.add_child(_pointer)
	_update_pointer()


func _process(delta: float) -> void:
	_time += delta
	if distance_source.is_valid() and not (paused_check.is_valid() and bool(paused_check.call())):
		track(float(distance_source.call()), delta)
	_strength = move_toward(_strength, 1.0 if _strong else 0.0, delta / STRONG_BLEND_TIME)
	_update_pointer()
	_trail.queue_redraw()
	_pointer.queue_redraw()


## One step of the stray rule with the player's distance to the entrance (INF: nobody, ignored).
func track(distance: float, delta: float) -> void:
	if is_inf(distance) or is_nan(distance):
		return
	if distance < _best - APPROACH_STEP or is_inf(_best):
		_best = distance
		_stray = 0.0
		_set_strong(false)
		return
	if _strong:
		_far = maxf(_far, distance)
		if distance <= _far - RECOVER_STEP:
			_stray = 0.0
			_set_strong(false)
		return
	_stray += delta
	if _stray >= STRAY_TIME:
		_far = distance
		_set_strong(true)


func is_strong() -> bool:
	return _strong


## Seconds without getting closer (tests and tools).
func get_stray_time() -> float:
	return _stray


## 0 = normal, 1 = strong (blended over STRONG_BLEND_TIME).
func get_strength() -> float:
	return _strength


func _set_strong(value: bool) -> void:
	if value == _strong:
		return
	_strong = value
	strength_changed.emit(value)


## 1 on every other STRONG_BEAT while the way is strong (whole art pixels: rings one larger, the
## arrow one scale step larger), else 0.
func strong_beat() -> int:
	if _strength < 0.5:
		return 0
	return int(floorf(_time / STRONG_BEAT)) % 2


func get_points() -> PackedVector2Array:
	return _points


## Screen position, angle and on-screen flag of the arrow, for tests and tools.
func get_pointer_position() -> Vector2:
	return _pointer_position


func get_pointer_angle() -> float:
	return _pointer_angle


func is_pointer_on_screen() -> bool:
	return _pointer_on_screen


func is_pointer_shown() -> bool:
	return _pointer != null and _pointer.visible


func _update_pointer() -> void:
	if _pointer == null:
		return
	_pointer.visible = not (hidden_check.is_valid() and bool(hidden_check.call()))
	var view := _pointer.get_viewport_rect().size
	var screen := _pointer.get_viewport().get_canvas_transform() * target
	var placed := place_pointer(screen, inner_rect(view), ARROW_ABOVE)
	_pointer_position = placed[0]
	_pointer_angle = placed[1]
	_pointer_on_screen = placed[2]


## Soul lights along the way; each fades in at the spawn and out at the stairs. Strong (FS6): a
## second light between every two, all brighter and pulsing a pixel larger on every other beat.
func _draw_trail() -> void:
	if _length <= 0.0:
		return
	var count := maxi(1, floori(_length / MOTE_SPACING))
	var bright := lerpf(1.0, STRONG_ALPHA, _strength)
	var grow := strong_beat()
	for i in count:
		_draw_trail_mote(_time * MOTE_SPEED + i * MOTE_SPACING, i, bright, grow, 1.0)
		if _strength > 0.0:
			_draw_trail_mote(_time * MOTE_SPEED + (i + 0.5) * MOTE_SPACING, i + 7, bright, 1 - grow, _strength)


func _draw_trail_mote(along: float, index: int, bright: float, grow: int, weight: float) -> void:
	var distance := fposmod(along, _length)
	var fade := clampf(minf(distance, _length - distance) / MOTE_EDGE_FADE, 0.0, 1.0)
	var twinkle := 0.75 + 0.25 * sin(_time * 3.0 + index * 1.7)
	var spot := point_at(_points, distance) + Vector2(0, sin(_time * 2.0 + index) * MOTE_FLOAT)
	_draw_mote(spot.snapped(Vector2.ONE * MOTE_PIXEL), fade * twinkle * weight, bright, grow)


## One soul light in pixel art (feedback #e5d0f6c6, #6ce10692 "Mach Pixel Grafik"): stepped
## squares on the village's art pixel grid instead of soft circles, glow from the rings. bright
## scales the ring alpha (strong way), grow adds whole art pixels to the outer rings (pulse).
func _draw_mote(center: Vector2, alpha: float, bright := 1.0, grow := 0) -> void:
	for ring: Array in MOTE_RINGS:
		var color := Color(SOUL_CORE if ring[2] else SOUL_COLOR, minf(1.0, float(ring[1]) * bright) * alpha)
		var radius := int(ring[0]) + (grow if not ring[2] else 0)
		for rect: Rect2 in _mote_rects(radius):
			_trail.draw_rect(Rect2(center + rect.position * MOTE_PIXEL, rect.size * MOTE_PIXEL), color)


## A pixel diamond of radius art pixels around the centre (radius 1 = the 2x2 core).
static func _mote_rects(radius: int) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for row in range(-radius, radius):
		var half := radius - (-row - 1 if row < 0 else row)
		rects.append(Rect2(-half, row, half * 2, 1))
	return rects


func _draw_pointer() -> void:
	var size := ARROW_TEXTURE.get_size()
	var bob := sin(_time * ARROW_BOB_SPEED) * ARROW_BOB
	var offset := Vector2.from_angle(_pointer_angle) * bob
	var pulse := lerpf(0.85 + 0.15 * sin(_time * ARROW_BOB_SPEED * 1.3), 1.0, _strength)
	# Strong (FS6): one whole scale step larger on every other beat (pixel art), lighter gold.
	var arrow_scale := ARROW_SCALE + float(strong_beat())
	_pointer.draw_set_transform(_pointer_position + offset, _pointer_angle, Vector2.ONE * arrow_scale)
	# Dark outline first (offset copies), then the gold arrow.
	for shift: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_pointer.draw_texture(ARROW_TEXTURE, -size * 0.5 + shift * 0.5, Color(0.08, 0.06, 0.12, 0.85))
	_pointer.draw_texture(ARROW_TEXTURE, -size * 0.5, Color(ARROW_COLOR.lerp(STRONG_ARROW_COLOR, _strength), pulse))
	_pointer.draw_set_transform(Vector2.ZERO)
