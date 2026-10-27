class_name CollapseView
extends Node2D
## Look of the breaking floor of "Einsturz" (R4a, design answer 10: cracked plates, glowing cracks,
## holes with glow below): a floor overlay below every character. Shows what CollapseMode decided:
##   marked (plan 'X'):  a cracked plate from the start (crumbling_floor_6f, frame 1),
##   queued (next 3):    thin orange cracks pulse on the field,
##   warned (1 s):       the plates crack open (frames 1-4) over a red glow, a red light,
##   broken:             plates gone - the abyss tiles (RoomTiles.add_pit_tiles) show through.
## Sinkholes under players who stand still (CollapseRules.STILL_TIME) look the same on their own
## tiles: warn_tiles, crumble_tiles, and restore_tiles when the floor closes again.
## Look only, no decisions. Sits at the room origin (room-local tile coordinates).

const ART_PATH := "res://art/environment/trials/crumbling_floor_6f.png"
const FRAMES := 6
const FRAME_CRACKED := 1
const FRAME_BREAKING_LAST := 4
const Z_INDEX := -9
const CRACK_COLOR := Color(1.0, 0.56, 0.3)
const GLOW_COLOR := Color(1.0, 0.24, 0.18)
const PLATE_TINT := Color(1.0, 0.86, 0.82)
const WARN_TINT := Color(1.0, 0.42, 0.36)
const LIGHT_RADIUS := 130.0
## Width of a drawn crack in art pixels (D-218).
const CRACK_PIXELS := 1

enum State { IDLE, QUEUED, WARNED, BROKEN }

var fields: Array = []
var states: Array[State] = []

var _texture: Texture2D = null
## tile -> plate sprite (marked or warned tiles).
var _plates: Dictionary[Vector2i, Sprite2D] = {}
var _warn_left: Dictionary[int, float] = {}
var _lights: Dictionary[int, LightSource] = {}
## Sinkhole tiles cracking open -> seconds of warning left.
var _sink_warn: Dictionary[Vector2i, float] = {}
var _time := 0.0


func setup(field_list: Array, marked: Array[Vector2i]) -> void:
	fields = field_list
	z_index = Z_INDEX
	_texture = load(ART_PATH) as Texture2D if ResourceLoader.exists(ART_PATH) else null
	states.clear()
	for field: Array in fields:
		states.append(State.IDLE)
		for tile: Vector2i in field:
			if marked.has(tile):
				_plate(tile, FRAME_CRACKED)


## Exactly these fields carry the "next" cracks (indices into fields).
func set_queued(indices: Array[int]) -> void:
	for i in states.size():
		if states[i] == State.QUEUED and not indices.has(i):
			states[i] = State.IDLE
	for i in indices:
		if i >= 0 and i < states.size() and states[i] == State.IDLE:
			states[i] = State.QUEUED
	queue_redraw()


## The field cracks open: plates breaking over a red glow for CollapseRules.WARN_TIME.
func warn(index: int) -> void:
	if index < 0 or index >= states.size() or states[index] >= State.WARNED:
		return
	states[index] = State.WARNED
	_warn_left[index] = CollapseRules.WARN_TIME
	for tile: Vector2i in fields[index]:
		_plate(tile, FRAME_CRACKED)
	var light := LightSource.new()
	light.name = "WarnLight%d" % index
	light.radius = LIGHT_RADIUS
	light.intensity = 0.25
	light.color = LightPalette.DANGER
	light.position = CollapseRules.field_center(fields[index])
	add_child(light)
	_lights[index] = light
	light.create_tween().tween_property(light, "intensity", 0.85, CollapseRules.WARN_TIME)
	queue_redraw()


## The field is abyss now: plates and light go, dust rises (the tiles are pits already).
func crumble(index: int) -> void:
	if index < 0 or index >= states.size() or states[index] == State.BROKEN:
		return
	states[index] = State.BROKEN
	_warn_left.erase(index)
	for tile: Vector2i in fields[index]:
		var plate: Sprite2D = _plates.get(tile)
		if plate != null:
			plate.queue_free()
			_plates.erase(tile)
		if is_inside_tree():
			Burst.spawn(self, to_global(RoomTiles.tile_center(tile)), Color(0.55, 0.5, 0.48), 6, 90.0, 0.55, 3.0)
	var light: LightSource = _lights.get(index)
	if light != null:
		_lights.erase(index)
		var tween := light.create_tween()
		tween.tween_property(light, "intensity", 0.0, 0.35)
		tween.tween_callback(light.queue_free)
	queue_redraw()


## A sinkhole cracks open on these tiles: plates breaking over a red glow for CollapseRules.WARN_TIME.
func warn_tiles(tiles: Array[Vector2i]) -> void:
	for tile in tiles:
		_sink_warn[tile] = CollapseRules.WARN_TIME
		_plate(tile, FRAME_CRACKED)
	queue_redraw()


## The sinkhole gives way: plates go, dust rises (the tiles are pits already).
func crumble_tiles(tiles: Array[Vector2i]) -> void:
	for tile in tiles:
		_sink_warn.erase(tile)
		var plate: Sprite2D = _plates.get(tile)
		if plate != null:
			plate.queue_free()
			_plates.erase(tile)
		if is_inside_tree():
			Burst.spawn(self, to_global(RoomTiles.tile_center(tile)), Color(0.55, 0.5, 0.48), 6, 90.0, 0.55, 3.0)
	queue_redraw()


## The sinkhole closes: the floor is back (RoomTiles repaints it), a little dust settles.
func restore_tiles(tiles: Array[Vector2i]) -> void:
	for tile in tiles:
		_sink_warn.erase(tile)
		if is_inside_tree():
			Burst.spawn(self, to_global(RoomTiles.tile_center(tile)), Color(0.62, 0.58, 0.52), 4, 50.0, 0.4, 2.0)
	queue_redraw()


func is_sink_warned(tile: Vector2i) -> bool:
	return _sink_warn.has(tile)


func get_state(index: int) -> State:
	return states[index] if index >= 0 and index < states.size() else State.IDLE


func has_plate(tile: Vector2i) -> bool:
	return _plates.has(tile)


func _process(delta: float) -> void:
	_time += delta
	for index: int in _warn_left.keys():
		_warn_left[index] = maxf(0.0, _warn_left[index] - delta)
		var progress := 1.0 - _warn_left[index] / CollapseRules.WARN_TIME
		var frame := FRAME_CRACKED + mini(FRAME_BREAKING_LAST - FRAME_CRACKED, floori(progress * (FRAME_BREAKING_LAST - FRAME_CRACKED + 1)))
		var glow := 0.5 + 0.5 * sin(_time * 14.0)
		for tile: Vector2i in fields[index]:
			var plate: Sprite2D = _plates.get(tile)
			if plate == null:
				continue
			if plate.hframes > 1:
				plate.frame = frame
			plate.modulate = PLATE_TINT.lerp(WARN_TINT, glow)
	for tile: Vector2i in _sink_warn.keys():
		_sink_warn[tile] = maxf(0.0, _sink_warn[tile] - delta)
		var plate: Sprite2D = _plates.get(tile)
		if plate == null:
			continue
		var progress := 1.0 - _sink_warn[tile] / CollapseRules.WARN_TIME
		if plate.hframes > 1:
			plate.frame = FRAME_CRACKED + mini(FRAME_BREAKING_LAST - FRAME_CRACKED, floori(progress * (FRAME_BREAKING_LAST - FRAME_CRACKED + 1)))
		plate.modulate = PLATE_TINT.lerp(WARN_TINT, 0.5 + 0.5 * sin(_time * 14.0))
	if not _warn_left.is_empty() or not _sink_warn.is_empty() or states.has(State.QUEUED):
		queue_redraw()


func _draw() -> void:
	for i in states.size():
		match states[i]:
			State.QUEUED:
				var alpha := 0.35 + 0.2 * PixelDraw.stepped(0.5 + 0.5 * sin(_time * 3.0 + i), 2)
				for tile: Vector2i in fields[i]:
					_draw_cracks(tile, Color(CRACK_COLOR, alpha))
			State.WARNED:
				var pulse := 0.1 + 0.4 * PixelDraw.stepped(0.5 + 0.5 * sin(_time * 14.0), 2)
				for tile: Vector2i in fields[i]:
					draw_rect(Rect2(RoomTiles.tile_to_local(tile), Vector2.ONE * RoomTiles.TILE_WORLD), Color(GLOW_COLOR, pulse))
	var sink_pulse := 0.1 + 0.4 * PixelDraw.stepped(0.5 + 0.5 * sin(_time * 14.0), 2)
	for tile: Vector2i in _sink_warn:
		draw_rect(Rect2(RoomTiles.tile_to_local(tile), Vector2.ONE * RoomTiles.TILE_WORLD), Color(GLOW_COLOR, sink_pulse))


## Two thin zig-zag pixel cracks per tile (D-218), the same for a tile every time.
func _draw_cracks(tile: Vector2i, color: Color) -> void:
	var origin := RoomTiles.tile_to_local(tile)
	var seed_value := absi(hash(tile))
	for crack in 2:
		var points := PackedVector2Array()
		var horizontal := ((seed_value >> crack) & 1) == 0
		var offset := 14.0 + float((seed_value >> (crack * 3 + 2)) % 36)
		for step in 5:
			var along := 6.0 + step * 13.0
			var wiggle := 5.0 if step % 2 == 0 else -5.0
			points.append(origin + (Vector2(along, offset + wiggle) if horizontal else Vector2(offset + wiggle, along)))
		PixelDraw.polyline(self, points, color, CRACK_PIXELS)


func _plate(tile: Vector2i, frame: int) -> void:
	if _plates.has(tile):
		return
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	sprite.position = RoomTiles.tile_to_local(tile)
	sprite.modulate = PLATE_TINT
	if _texture != null:
		sprite.texture = _texture
		sprite.hframes = FRAMES
		sprite.frame = frame
	add_child(sprite)
	_plates[tile] = sprite
