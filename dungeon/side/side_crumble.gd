class_name SideCrumble
extends Node2D
## A crumbling ledge of a side segment (M5 round 2, plan "~"): a one-way ledge with cracks. A player
## standing on it starts the timer (SideSegment.touch_crumbles): it shakes for CRUMBLE_DELAY, falls
## (no collision, the pieces drop and fade) and is back after CRUMBLE_RESPAWN once nobody is in the
## way. The origin is the top-left corner of its first cell; it covers cells first..last of one row.
## SideSegment calls update() every physics frame (decisions there, so tests can step it by hand).
## Group game: the host decides (state_changed goes to the clients, NetSide); a client's ledge is
## remote_controlled - it only shakes, drops and fades, and changes state when the host says so
## (apply_remote_state), so it falls and comes back on every machine at the same moment.

## The ledge started shaking, fell or came back (the decision; looks follow in step()).
signal state_changed(crumble: SideCrumble, state: State)

enum State { SOLID, SHAKING, FALLEN }

const SHAKE_PX := 2.5
const DROP_SPEED := 520.0
const CRACK_COLOR := Color(0.08, 0.06, 0.1, 0.85)

var cells := 1
var biome_id: StringName = &"crypt"
var state := State.SOLID
## Crumbles during this segment (tests, tools).
var crumble_count := 0
## Client of a group game: the host decides when it shakes, falls and comes back.
var remote_controlled := false

var _time_left := 0.0
var _body: StaticBody2D = null
var _shape: CollisionShape2D = null
var _pieces: Node2D = null
var _fall_offset := 0.0


func _ready() -> void:
	z_index = -5
	_pieces = Node2D.new()
	_pieces.name = "Pieces"
	add_child(_pieces)
	for i in cells:
		var piece := "front_mid"
		if cells == 1:
			piece = "front_single"
		elif i == 0:
			piece = "front_left"
		elif i == cells - 1:
			piece = "front_right"
		var sprite := Sprite2D.new()
		sprite.texture = SideTiles.piece_texture(biome_id, piece)
		sprite.centered = false
		sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		sprite.position = Vector2(i * SideRules.TILE, 0.0)
		_pieces.add_child(sprite)
	var cracks := _Cracks.new()
	cracks.cells = cells
	_pieces.add_child(cracks)
	_body = StaticBody2D.new()
	_body.name = "Body"
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	var box := RectangleShape2D.new()
	box.size = Vector2(cells * SideRules.TILE, SideTiles.LEDGE_DEPTH * SpriteStrip.PIXEL_SCALE)
	_shape = CollisionShape2D.new()
	_shape.shape = box
	_shape.one_way_collision = true
	_shape.position = box.size * 0.5
	_body.add_child(_shape)
	add_child(_body)


## The standing area (global): the top edge of the ledge.
func get_top_rect() -> Rect2:
	return Rect2(global_position + Vector2(0, -6), Vector2(cells * SideRules.TILE, 12))


func is_solid() -> bool:
	return state != State.FALLEN


## A player stands on it: starts the shaking (once per cycle).
func touch() -> void:
	if state != State.SOLID:
		return
	state = State.SHAKING
	_time_left = SideRules.CRUMBLE_DELAY
	if is_inside_tree():
		Sfx.play_at(self, &"stone_grind", global_position + Vector2(cells * SideRules.TILE * 0.5, 0), -12.0)
	state_changed.emit(self, state)


## The host's state on a client (NetSide): shaking, fallen or back, with the same looks.
func apply_remote_state(new_state: State) -> void:
	if new_state == state:
		return
	match new_state:
		State.SHAKING:
			touch()
		State.FALLEN:
			_collapse()
		State.SOLID:
			_restore()


## One step; blocked_by_player: someone stands where the ledge would come back.
func step(delta: float, blocked_by_player := false) -> void:
	match state:
		State.SHAKING:
			_time_left -= delta
			_pieces.position = Vector2(sin(_time_left * 70.0) * SHAKE_PX, 0.0)
			if _time_left <= 0.0 and not remote_controlled:
				_collapse()
		State.FALLEN:
			_time_left -= delta
			_fall_offset += DROP_SPEED * delta
			_pieces.position = Vector2(0.0, _fall_offset)
			_pieces.modulate.a = maxf(0.0, 1.0 - _fall_offset / 160.0)
			if _time_left <= 0.0 and not blocked_by_player and not remote_controlled:
				_restore()


## One physics step with the segment's players (SideSegment._physics_process): someone standing on
## the ledge starts it, someone in the way keeps it from coming back.
func update(players: Array[Player], delta: float) -> void:
	var top := get_top_rect()
	var in_way := false
	for player in players:
		if not is_instance_valid(player) or player.side_motion == null:
			continue
		var feet := player.get_feet_position()
		if top.has_point(feet):
			in_way = true
			if state == State.SOLID and player.side_motion.is_on_floor() and not player.side_motion.is_climbing():
				touch()
	step(delta, in_way)


func _collapse() -> void:
	state = State.FALLEN
	crumble_count += 1
	_time_left = SideRules.CRUMBLE_RESPAWN
	_fall_offset = 0.0
	_shape.disabled = true
	if is_inside_tree():
		Sfx.play_at(self, SideRules.sound_or(SideRules.SOUND_CRUMBLE, &"collapse_crack"), global_position + Vector2(cells * SideRules.TILE * 0.5, 0), -4.0)
		SideDust.spawn(get_parent(), global_position + Vector2(cells * SideRules.TILE * 0.5, 8.0), SideDust.Kind.CLOUD, 0.6)
	state_changed.emit(self, state)


func _restore() -> void:
	state = State.SOLID
	_shape.disabled = false
	_pieces.position = Vector2.ZERO
	_pieces.modulate.a = 0.0
	if is_inside_tree():
		create_tween().tween_property(_pieces, "modulate:a", 1.0, 0.3)
	else:
		_pieces.modulate.a = 1.0
	state_changed.emit(self, state)


## Cracks over the pieces, so the ledge reads as brittle before it is stood on.
class _Cracks:
	extends Node2D
	var cells := 1

	func _draw() -> void:
		var tile := SideRules.TILE
		for i in cells:
			var x := i * tile
			draw_polyline(PackedVector2Array([Vector2(x + 14, 2), Vector2(x + 22, 12), Vector2(x + 18, 20), Vector2(x + 28, 30)]), SideCrumble.CRACK_COLOR, 2.0)
			draw_polyline(PackedVector2Array([Vector2(x + 44, 4), Vector2(x + 38, 14), Vector2(x + 48, 22)]), SideCrumble.CRACK_COLOR, 2.0)
