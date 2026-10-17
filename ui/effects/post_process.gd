class_name PostProcess
extends CanvasLayer
## Full-screen post-process pass (post_process.gdshader) between the vision overlay (layer 2) and
## the HUD (layer 5): chromatic aberration on hits, wobble while stunned, blur/fog while blinded,
## desaturation + heartbeat at low HP, grey-out on death, subtle film grain in the dark.
## Driven by player signals; VisionOverlay creates and binds one automatically.
## The pass is switched off completely while no effect is active.

const SHADER: Shader = preload("res://components/visual/post_process.gdshader")
const LAYER := 3
const GROUP := &"post_process"
const CHROMA_DECAY := 3.0
## Stun / blind effects fade in and out over this time (seconds).
const FADE_IN := 0.12
const FADE_OUT := 0.35
const DEATH_DESATURATE := 0.85
const DEATH_FADE := 1.2
const ACTIVE_EPSILON := 0.002

## Film grain strength (0 = off). VisionOverlay sets it from the dungeon darkness.
var grain := 0.0

var _material: ShaderMaterial
var _rect: ColorRect
var _player: Player = null
var _chroma := 0.0
var _stun_left := 0.0
var _stun_total := 0.0
var _blind_left := 0.0
var _blind_total := 0.0
var _low_hp := 0.0
var _desaturate := 0.0
var _desaturate_target := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)


func bind_player(player: Player) -> void:
	if _player != null and is_instance_valid(_player):
		_disconnect_player(_player)
	_player = player
	reset()
	if player == null:
		return
	player.hurtbox.hit_received.connect(_on_player_hit)
	player.blinded.connect(blind)
	player.stunned.connect(stun)
	player.died.connect(_on_player_died)
	player.revived.connect(_on_player_revived)


## Clears every effect (new player, world change).
func reset() -> void:
	_chroma = 0.0
	_stun_left = 0.0
	_blind_left = 0.0
	_low_hp = 0.0
	_desaturate = 0.0
	_desaturate_target = 0.0


func hit_pulse(strength := 1.0) -> void:
	_chroma = maxf(_chroma, clampf(strength * GameOptions.get_flash_strength(), 0.0, 1.0))


func stun(duration: float) -> void:
	if duration <= 0.0:
		return
	_stun_left = maxf(_stun_left, duration)
	_stun_total = maxf(_stun_left, 0.001)


func blind(duration: float) -> void:
	if duration <= 0.0:
		return
	_blind_left = maxf(_blind_left, duration)
	_blind_total = maxf(_blind_left, 0.001)


func get_stun_amount() -> float:
	return envelope(_stun_left, _stun_total)


func get_blind_amount() -> float:
	return envelope(_blind_left, _blind_total)


func get_chroma() -> float:
	return _chroma


func is_active() -> bool:
	return _rect != null and _rect.visible


## 0..1 strength of a timed effect: quick fade in, fade out over the last FADE_OUT seconds.
static func envelope(time_left: float, total: float) -> float:
	if time_left <= 0.0 or total <= 0.0:
		return 0.0
	var elapsed := total - time_left
	var fade_in := clampf(elapsed / FADE_IN, 0.0, 1.0) if total > FADE_IN * 2.0 else 1.0
	var fade_out := clampf(time_left / FADE_OUT, 0.0, 1.0)
	return minf(fade_in, fade_out)


func _process(delta: float) -> void:
	if not get_tree().paused:
		_tick(delta)
	var stun_amount := get_stun_amount()
	var blind_amount := get_blind_amount()
	var active := _chroma > ACTIVE_EPSILON or stun_amount > ACTIVE_EPSILON or blind_amount > ACTIVE_EPSILON \
			or _low_hp > ACTIVE_EPSILON or _desaturate > ACTIVE_EPSILON or grain > ACTIVE_EPSILON
	_rect.visible = active
	if not active:
		return
	# Portrait mode (D-182) scales and shifts the whole canvas: the game picture is the visible
	# rect, so screen size and focus are taken in its units (identity in landscape).
	var xf := get_viewport().get_final_transform()
	var screen := Vector2(get_viewport().size) / xf.get_scale()
	var focus := screen * 0.5
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		focus = get_viewport().get_canvas_transform() * _player.global_position
		focus += Vector2(0.0, xf.origin.y / xf.get_scale().y)
	_material.set_shader_parameter(&"screen_size", screen)
	_material.set_shader_parameter(&"focus", focus)
	_material.set_shader_parameter(&"chroma", _chroma)
	_material.set_shader_parameter(&"stun", stun_amount)
	_material.set_shader_parameter(&"blind", blind_amount)
	_material.set_shader_parameter(&"low_hp", _low_hp)
	_material.set_shader_parameter(&"desaturate", _desaturate)
	_material.set_shader_parameter(&"grain", grain)


func _tick(delta: float) -> void:
	_chroma = maxf(0.0, _chroma - CHROMA_DECAY * delta)
	_stun_left = maxf(0.0, _stun_left - delta)
	_blind_left = maxf(0.0, _blind_left - delta)
	_desaturate = move_toward(_desaturate, _desaturate_target, delta / DEATH_FADE)
	var target_low_hp := 0.0
	if _player != null and is_instance_valid(_player) and _player.is_alive():
		var hp := _player.health.get_health()
		target_low_hp = 1.0 if hp <= 1.0 else (0.5 if hp <= 2.0 else 0.0)
	_low_hp = move_toward(_low_hp, target_low_hp, delta * 2.0)


func _disconnect_player(player: Player) -> void:
	if player.hurtbox.hit_received.is_connected(_on_player_hit):
		player.hurtbox.hit_received.disconnect(_on_player_hit)
	if player.blinded.is_connected(blind):
		player.blinded.disconnect(blind)
	if player.stunned.is_connected(stun):
		player.stunned.disconnect(stun)
	if player.died.is_connected(_on_player_died):
		player.died.disconnect(_on_player_died)
	if player.revived.is_connected(_on_player_revived):
		player.revived.disconnect(_on_player_revived)


func _on_player_hit(result: DamageResult, _damage: DamageData) -> void:
	if result.is_effective():
		hit_pulse(1.0)


## Up again after being downed (MP3): the colour comes back.
func _on_player_revived() -> void:
	_desaturate_target = 0.0


func _on_player_died() -> void:
	_stun_left = 0.0
	_blind_left = 0.0
	_desaturate_target = DEATH_DESATURATE
