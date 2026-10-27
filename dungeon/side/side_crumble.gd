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
## The jump trial's tilting platforms and collapsing bridge pieces (SV2, dungeon/side/elements/) are
## crumbles with their own timing (shake_time, respawn_time) and look (_build_look, _look_step), so
## they share the decision, the co-op sync (SideSegment.get_crumbles, NetSide) and the tests.

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
## The fade-in of a ledge coming back (killed when it falls again before the fade ends).
var _restore_tween: Tween = null


func _ready() -> void:
	z_index = -5
	_pieces = Node2D.new()
	_pieces.name = "Pieces"
	add_child(_pieces)
	_build_look()
	_build_body()


## Seconds from the first touch to the fall.
func shake_time() -> float:
	return SideRules.CRUMBLE_DELAY


## Seconds from the fall until it may come back.
func respawn_time() -> float:
	return SideRules.CRUMBLE_RESPAWN


## The pieces under _pieces (the ledge's front pieces with cracks).
func _build_look() -> void:
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


## The one-way collision strip over all cells.
func _build_body() -> void:
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
	_time_left = shake_time()
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
			# The shake moves in whole art pixels (D-218).
			_pieces.position = Vector2(roundf(sin(_time_left * 70.0) * SHAKE_PX / SidePixels.PIXEL) * SidePixels.PIXEL, 0.0)
			if _time_left <= 0.0 and not remote_controlled:
				_collapse()
		State.FALLEN:
			_time_left -= delta
			_fall_offset += DROP_SPEED * delta
			_pieces.position = Vector2(0.0, _fall_offset)
			_pieces.modulate.a = maxf(0.0, 1.0 - _fall_offset / 160.0)
			# Gone for good once faded (no ghost left in the air, feedback #e0486234).
			_pieces.visible = _pieces.modulate.a > 0.0
			if _time_left <= 0.0 and not blocked_by_player and not remote_controlled:
				_restore()
	_look_step()


## Extra look per step (frames of delivered art); the base ledge only shakes and drops.
func _look_step() -> void:
	pass


## Share of the shaking time gone (0 at the touch, 1 at the fall).
func shake_progress() -> float:
	return clampf(1.0 - _time_left / maxf(shake_time(), 0.001), 0.0, 1.0) if state == State.SHAKING else (1.0 if state == State.FALLEN else 0.0)


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
	_time_left = respawn_time()
	_fall_offset = 0.0
	_shape.disabled = true
	if _restore_tween != null and _restore_tween.is_valid():
		_restore_tween.kill()
	if is_inside_tree():
		Sfx.play_at(self, SideRules.sound_or(SideRules.SOUND_CRUMBLE, &"collapse_crack"), global_position + Vector2(cells * SideRules.TILE * 0.5, 0), -4.0)
		SideDust.spawn(get_parent(), global_position + Vector2(cells * SideRules.TILE * 0.5, 8.0), SideDust.Kind.CLOUD, 0.6)
	state_changed.emit(self, state)


func _restore() -> void:
	state = State.SOLID
	_shape.disabled = false
	_pieces.position = Vector2.ZERO
	_pieces.modulate.a = 0.0
	_pieces.visible = true
	if is_inside_tree():
		_restore_tween = create_tween()
		_restore_tween.tween_property(_pieces, "modulate:a", 1.0, 0.3)
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
			SidePixels.polyline(self, PackedVector2Array([Vector2(x + 14, 2), Vector2(x + 22, 12), Vector2(x + 18, 20), Vector2(x + 28, 30)]), SideCrumble.CRACK_COLOR)
			SidePixels.polyline(self, PackedVector2Array([Vector2(x + 44, 4), Vector2(x + 38, 14), Vector2(x + 48, 22)]), SideCrumble.CRACK_COLOR)
