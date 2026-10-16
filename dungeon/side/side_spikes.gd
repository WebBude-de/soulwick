class_name SideSpikes
extends Node2D
## Floor spikes of a side segment (M5), timed like the room spike trap (D-069): rest, a visible
## warning, spikes out (hurt the player, shield first), back in. Enemies are never hurt. The node
## origin is the floor line in the middle of its tile. Drawn as a placeholder until
## art/environment/side/spikes_side_3f.png (SPRITES_V9) exists.
## Round 3: neighbouring traps of a run fire one after the other (SideSegment gives each a later
## start, SideRules.SPIKE_WAVE_STEP). Group game: the host's traps decide (phase_changed goes to the
## clients through NetSide); a client's trap is remote_controlled and changes phase when the host's
## does, so a wave runs at the same moment on every machine. A client whose message is late keeps
## going on its own clock after REMOTE_GRACE seconds.

## The trap changed phase (the decision; the look follows in _draw).
signal phase_changed(spikes: SideSpikes, phase: Phase)

enum Phase { IDLE, WARN, ACTIVE }

## TESTWERTE
const IDLE_TIME := 1.6
const WARN_TIME := 0.5
const ACTIVE_TIME := 0.9
const DAMAGE := 1.0
const WIDTH := 56.0
const HEIGHT := 24.0
const ART_PATH := "res://art/environment/side/spikes_side_3f.png"
const BASE_COLOR := Color(0.2, 0.18, 0.24)
const SPIKE_COLOR := Color(0.82, 0.82, 0.9)
const WARN_COLOR := Color(1.0, 0.35, 0.25)
const SPIKES := 5
## A remote-controlled trap waits this long past its own clock for the host before going on alone.
const REMOTE_GRACE := 0.75

var phase := Phase.IDLE
## Client of a group game: the host decides the phases (NetSide).
var remote_controlled := false

var _time_left := IDLE_TIME
var _hitbox: Hitbox = null
var _sprite: Sprite2D = null


## Start offset in seconds (first rest): traps of different runs do not fire together, traps of one
## run fire as a wave (up to one cycle late).
func setup(offset: float) -> void:
	_time_left = clampf(offset, 0.1, IDLE_TIME + WARN_TIME + ACTIVE_TIME)


func _ready() -> void:
	z_index = -1
	if ResourceLoader.exists(ART_PATH):
		_sprite = Sprite2D.new()
		_sprite.texture = load(ART_PATH)
		_sprite.hframes = 3
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() * 0.5)
		add_child(_sprite)
	_hitbox = Hitbox.new()
	_hitbox.name = "Hitbox"
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = PhysicsLayers.PLAYER_HURTBOX
	var shape := RectangleShape2D.new()
	shape.size = Vector2(WIDTH, HEIGHT)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -HEIGHT * 0.5)
	_hitbox.add_child(collision)
	add_child(_hitbox)


func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left > (-REMOTE_GRACE if remote_controlled else 0.0):
		return
	match phase:
		Phase.IDLE:
			_enter(Phase.WARN)
		Phase.WARN:
			_enter(Phase.ACTIVE)
		Phase.ACTIVE:
			_enter(Phase.IDLE)


## The host's trap changed phase: the same here, at once.
func apply_remote_phase(new_phase: Phase) -> void:
	if new_phase != phase:
		_enter(new_phase)


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	match phase:
		Phase.WARN:
			_time_left = WARN_TIME
		Phase.ACTIVE:
			_time_left = ACTIVE_TIME
			var damage := DamageData.new()
			damage.amount = DAMAGE
			damage.tags.assign([&"trap"])
			if _hitbox != null:
				_hitbox.begin_attack(damage)
			if is_inside_tree():
				Sfx.play_at(self, &"trap", global_position, -6.0)
		Phase.IDLE:
			_time_left = IDLE_TIME
			if _hitbox != null:
				_hitbox.end_attack()
	queue_redraw()
	phase_changed.emit(self, phase)


func is_active() -> bool:
	return phase == Phase.ACTIVE


func _draw() -> void:
	if _sprite != null:
		_sprite.frame = phase
		return
	var half := WIDTH * 0.5
	draw_rect(Rect2(-half, -5.0, WIDTH, 5.0), BASE_COLOR)
	var height := 5.0
	var color := SPIKE_COLOR
	if phase == Phase.WARN:
		height = 9.0
		color = WARN_COLOR
	elif phase == Phase.ACTIVE:
		height = HEIGHT
	var step := WIDTH / SPIKES
	for i in SPIKES:
		var x := -half + step * (i + 0.5)
		draw_colored_polygon(PackedVector2Array([Vector2(x - step * 0.4, -4.0), Vector2(x + step * 0.4, -4.0), Vector2(x, -4.0 - height)]), color)
