class_name PlayerFall
extends Node
## Falling into an abyss for one player (A4, D-086). The state lives here, at the player (D-088):
## the last safe spot, the time over a pit and the running fall. Every physics frame Player calls
## update(): over an abyss on foot (a dash is in the air) longer than the grace time -> the player
## falls: input locked, the fall animation for FALL_TIME, then a whole heart of damage past the
## shield, back to the last safe spot and briefly invulnerable. The decisions are ChasmRules'; this
## node applies them and tells the world through signals (fall_started, landed).
## A room may change where the current fall lands and what it costs (set_landing, e.g. a trial that
## never ends the run and puts the player back to the start of its course).

signal fall_started(player: Player)
## After the landing: the damage the fall dealt (0 if a room waived it).
signal landed(player: Player, damage: float)

enum State { GROUNDED, FALLING }

const INPUT_LOCK := &"fall"
const INVULNERABLE_FALL := &"fall"
const FALL_TEXTURE: Texture2D = preload("res://art/characters/player/player_fall_4f.png")
const FALL_FRAMES := 4
const FALL_FRAME := Vector2i(32, 32)

## Callable(point: Vector2) -> bool, "is there a pit at this global point?". Default: the pit
## physics layer of the player's world (PitProbe); tests may replace it.
var pit_probe: Callable
var state := State.GROUNDED
## Number of falls of this player (tools, tests).
var falls := 0

var _player: Player = null
var _over_pit_time := 0.0
var _fall_left := 0.0
var _has_safe_spot := false
## Global position of the feet at the last safe spot.
var _safe_feet := Vector2.ZERO
var _landing_override := Vector2.INF
var _damage_override := -1.0
var _sprite: Sprite2D = null


func setup(player: Player) -> void:
	_player = player
	if not pit_probe.is_valid():
		pit_probe = PitProbe.probe_for(player)


func is_falling() -> bool:
	return state == State.FALLING


func has_safe_spot() -> bool:
	return _has_safe_spot


## Feet position the next fall returns to (global).
func get_safe_feet_position() -> Vector2:
	return _safe_feet if _has_safe_spot else _player.get_feet_position()


## Sets the safe spot explicitly (spawn, teleports into a room).
func remember_safe_spot(feet: Vector2) -> void:
	_safe_feet = feet
	_has_safe_spot = true


## While falling: land at feet (global) instead of the last safe spot and deal damage instead of
## ChasmRules.FALL_DAMAGE (negative = keep the rule). Only for the running fall.
func set_landing(feet: Vector2, damage := -1.0) -> void:
	_landing_override = feet
	_damage_override = damage


## One physics step (called by Player._physics_process).
func update(delta: float) -> void:
	if _player == null or not _player.is_alive():
		return
	if state == State.FALLING:
		_fall_left -= delta
		_update_sprite()
		if _fall_left <= 0.0:
			land()
		return
	var feet := _player.get_feet_position()
	var dashing := _player.is_dashing()
	var over_pit := ChasmRules.is_over_pit(feet, pit_probe)
	_over_pit_time = ChasmRules.tick_over_pit(_over_pit_time, delta, over_pit, dashing)
	if ChasmRules.should_fall(over_pit, dashing, _over_pit_time):
		start_fall()
	elif not over_pit and not dashing and ChasmRules.is_safe_spot(feet, pit_probe):
		remember_safe_spot(feet)


# --- Decisions ---

## The player loses the ground: input locked, the fall animation starts.
func start_fall() -> bool:
	if state == State.FALLING or _player == null or not _player.is_alive():
		return false
	state = State.FALLING
	falls += 1
	_fall_left = ChasmRules.FALL_TIME
	_over_pit_time = 0.0
	_landing_override = Vector2.INF
	_damage_override = -1.0
	_player.set_input_locked(INPUT_LOCK, true)
	_player.hurtbox.set_invulnerable(INVULNERABLE_FALL, true)
	_show_fall(true)
	fall_started.emit(_player)
	return true


## End of the fall: back at the safe spot (or the room's landing), then the damage, then the short
## invulnerability. The damage may kill (D-086).
func land() -> void:
	if state != State.FALLING:
		return
	state = State.GROUNDED
	var feet := _landing_override if _landing_override != Vector2.INF else get_safe_feet_position()
	# The safe spot may have crumbled meanwhile: the nearest solid ground instead.
	feet = PitProbe.nearest_safe_point(feet, pit_probe, ChasmRules.SAFE_MARGIN)
	_player.global_position = feet - Player.FEET_OFFSET
	_player.velocity = Vector2.ZERO
	remember_safe_spot(feet)
	_show_fall(false)
	_player.hurtbox.set_invulnerable(INVULNERABLE_FALL, false)
	_player.set_input_locked(INPUT_LOCK, false)
	var damage := _damage_override if _damage_override >= 0.0 else ChasmRules.fall_damage()
	var dealt := apply_fall_damage(_player, damage)
	if _player.is_alive():
		_player.grant_invulnerability(ChasmRules.RESPAWN_INVULNERABILITY)
	landed.emit(_player, dealt)


## Health damage past the shield (D-086). The hit is announced on the hurtbox first (flash, camera,
## run recap cause "pit"), so listeners see it before a possible death. Returns the HP removed.
static func apply_fall_damage(player: Player, amount: float) -> float:
	if player == null or amount <= 0.0 or not player.is_alive():
		return 0.0
	var damage := DamageData.new()
	damage.amount = amount
	damage.tags.assign([ChasmRules.DAMAGE_TAG])
	damage.hit_id = DamageData.next_hit_id()
	var result := DamageResult.new()
	result.amount = amount
	result.health_damage = minf(amount, player.health.get_health())
	result.killed = result.health_damage >= player.health.get_health()
	player.hurtbox.hit_received.emit(result, damage)
	return player.health.take_damage(amount)


# --- Look ---

func _show_fall(falling: bool) -> void:
	_player.set_body_visible(not falling)
	if falling:
		if _sprite == null:
			_sprite = Sprite2D.new()
			_sprite.name = "FallSprite"
			_sprite.texture = FALL_TEXTURE
			_sprite.hframes = FALL_FRAMES
			_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
			_sprite.offset = SpriteStrip.pivot_offset(FALL_FRAME, Player.SPRITE_ORIGIN)
			_player.add_child(_sprite)
		_sprite.flip_h = _player.get_aim_direction().x < 0.0
		_sprite.frame = 0
		_sprite.visible = true
		Sfx.play_at(_player, ChasmRules.fall_sound(), _player.global_position, -4.0)
	elif _sprite != null:
		_sprite.visible = false


func _update_sprite() -> void:
	if _sprite == null:
		return
	var progress := 1.0 - _fall_left / ChasmRules.FALL_TIME
	_sprite.frame = clampi(floori(progress * FALL_FRAMES), 0, FALL_FRAMES - 1)
