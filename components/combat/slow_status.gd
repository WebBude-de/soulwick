class_name SlowStatus
extends Node2D
## Slowed (D-151): a status on one player, kept as the child "SlowStatus" of that player (state per
## player, multiplayer guard rails). One slow at a time: a new hit refreshes it (the longer rest
## wins, the stronger factor wins) and never stacks. The speed goes through the existing per-player
## speed modifier (ToxicPuddle.apply_slow: Player.set_speed_modifier once it exists, until then the
## move_speed meta), so puddles, water and this slow combine as "strongest wins".
## Like stun and blind it only comes with effective hits (D-017): dash and hit I-frames block it.
## Look: a pale blue shimmer over the body, a ring at the feet and frost motes rising around it; it
## fades out at the end. Real art replaces the drawing: art/effects/slow_status_6f.png (32 x 32 frames,
## looping, centred on the body) when present.

const NODE_NAME := &"SlowStatus"
const ART_PATH := "res://art/effects/slow_status_6f.png"
const ART_FRAME := Vector2i(32, 32)
const ART_FPS := 8.0
const COLOR := Color(0.55, 0.8, 1.0)
## The look fades out over the last seconds.
const FADE_TIME := 0.3
## Body centre to feet of the player (Player.FEET_OFFSET) and the height the motes rise to.
const FEET_Y := 16.0
const MOTE_HEIGHT := 46.0
const MOTE_COUNT := 8
const RING_RADIUS := Vector2(15.0, 6.0)
## Pale blue shimmer over the body (half width, half height, centre height).
const AURA_RADIUS := Vector2(13.0, 24.0)
const AURA_Y := -4.0

## Move speed factor while slowed (0.65 = -35 %).
var factor := 1.0
var time_left := 0.0

var _target: Node2D = null
var _time := 0.0
var _art: AnimatedSprite2D = null


## Slows target (a Player) for duration seconds to slow_factor of its speed, or refreshes the slow it
## has. Returns the status, null for anything that is not a living player or no slow at all.
static func apply(target: Node, slow_factor: float, duration: float) -> SlowStatus:
	if not (target is Player) or duration <= 0.0 or slow_factor >= 1.0:
		return null
	if not EnemyTargeting.is_alive(target):
		return null
	var status := get_for(target)
	if status == null or status.is_queued_for_deletion():
		status = SlowStatus.new()
		status.name = NODE_NAME
		status._target = target as Node2D
		target.add_child(status)
	status.refresh(slow_factor, duration)
	return status


## The slow a hit carries (DamageData.slow_factor / slow_duration), only for effective hits.
## Player hook (_on_hit_received, next to stun and blind) and network copies of a hit use it.
static func apply_from_damage(target: Node, result: DamageResult, damage: DamageData) -> SlowStatus:
	if result == null or damage == null or not result.is_effective():
		return null
	return apply(target, damage.slow_factor, damage.slow_duration)


## For Hitbox.hit_landed (hurtbox, result) with the slow bound: the hurtbox's owner gets the slow.
static func apply_on_hit(hurtbox: Hurtbox, result: DamageResult, slow_factor: float, duration: float) -> void:
	if hurtbox == null or not is_instance_valid(hurtbox) or result == null or not result.is_effective():
		return
	apply(hurtbox.get_parent(), slow_factor, duration)


static func get_for(target: Node) -> SlowStatus:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NodePath(NODE_NAME)) as SlowStatus


static func is_slowed(target: Node) -> bool:
	var status := get_for(target)
	return status != null and not status.is_queued_for_deletion() and status.time_left > 0.0


## Stronger factor and longer rest win; nothing adds up.
func refresh(slow_factor: float, duration: float) -> void:
	factor = minf(factor, slow_factor) if time_left > 0.0 else slow_factor
	time_left = maxf(time_left, duration)
	_apply_speed(factor)


## Ends the slow at once (speed back, look gone).
func clear() -> void:
	time_left = 0.0
	_apply_speed(1.0)
	queue_free()


func _ready() -> void:
	z_index = 1
	if _target == null:
		_target = get_parent() as Node2D
	if ResourceLoader.exists(ART_PATH):
		_art = AnimatedSprite2D.new()
		_art.sprite_frames = SpriteStrip.make_frames(load(ART_PATH) as Texture2D, ART_FRAME, ART_FPS, true)
		_art.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_art.play(&"default")
		add_child(_art)


func _exit_tree() -> void:
	# Removed with its player or by clear(): the speed modifier must never stay behind.
	if time_left > 0.0:
		time_left = 0.0
		_apply_speed(1.0)


func _physics_process(delta: float) -> void:
	_time += delta
	time_left -= delta
	if time_left <= 0.0 or not EnemyTargeting.is_alive(_target):
		clear()
		return
	queue_redraw()


func _apply_speed(speed_factor: float) -> void:
	var player := _target as Player
	if player == null or not is_instance_valid(player):
		return
	ToxicPuddle.apply_slow(player, get_instance_id(), speed_factor)


func _draw() -> void:
	var alpha := clampf(time_left / FADE_TIME, 0.0, 1.0)
	if _art != null:
		_art.modulate.a = alpha
		return
	# Pixel art (D-218): pulses and the fade-out go in hard steps.
	alpha = PixelDraw.stepped(alpha, 3)
	var pulse := PixelDraw.stepped(0.75 + 0.25 * sin(_time * 9.0), 4)
	# Bluish shimmer over the body.
	PixelDraw.ellipse(self, Vector2(0.0, AURA_Y), AURA_RADIUS, Color(COLOR, (0.1 + 0.06 * pulse) * alpha))
	# Pale ring at the feet: "stuck in frost".
	PixelDraw.ellipse(self, Vector2(0.0, FEET_Y), RING_RADIUS, Color(COLOR, 0.18 * alpha))
	PixelDraw.ellipse_ring(self, Vector2(0.0, FEET_Y), RING_RADIUS, Color(COLOR, 0.7 * alpha * pulse))
	# Frost motes rising around the body, each on its own lane and phase.
	for i in MOTE_COUNT:
		var phase := fmod(_time * 0.9 + float(i) / MOTE_COUNT, 1.0)
		var lane := (float(i) - (MOTE_COUNT - 1) * 0.5) * 5.0
		var spot := Vector2(lane + sin(_time * 3.0 + i) * 2.0, FEET_Y - phase * MOTE_HEIGHT)
		var size := 2 if i % 2 == 0 else 1
		var mote := Color(COLOR.lightened(0.4), PixelDraw.stepped(1.0 - phase * 0.7, 3) * alpha)
		PixelDraw.rect(self, Rect2(spot - Vector2.ONE * size, Vector2.ONE * size * PixelDraw.WORLD_PIXEL), mote)
