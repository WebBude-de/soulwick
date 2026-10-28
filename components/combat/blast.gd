class_name Blast
extends Node2D
## Area explosion with an optional visible warning circle (bomber, volatile elites, boss slams).
## Detonates in _physics_process so the area query is always allowed.
## Variants for bosses (BossPressure, playtest #a8a87397): a lobbed lava ball (lob_from: a ball
## flies in an arc onto the warning circle, which fills up until it lands) that leaves a burning
## LavaPool behind, and a stunning ground wave (look LOOK_STOMP, stun_duration). The pool and the
## ball only show on a network client if the blast_spawned event carries lob_from and pool_time.
## The effect art is scaled to the radius in whole steps (PixelDraw.whole_scale, FS2b), so its pixels
## stay even; the hit area keeps the exact radius.

const EXPLOSION_TEXTURE: Texture2D = preload("res://art/effects/explosion_6f.png")
const EXPLOSION_ART_RADIUS := 45.0
const LOOK_EXPLOSION := &"explosion"
const LOOK_LAVA := &"lava"
const LOOK_STOMP := &"stomp"
## Optional art (SPRITES_V13 part C); without it the explosion strip resp. a PixelRingWave stand in.
const LAVA_IMPACT_PATH := "res://art/effects/lava_impact_6f.png"
## Frames, pivots and fps from art/effects/ember_golem_fx.json; art radii measured on the delivered
## PNGs (widest frame, horizontal, in texels).
const LAVA_IMPACT_FRAME := Vector2i(32, 32)
const LAVA_IMPACT_PIVOT := Vector2(16, 22)
const LAVA_IMPACT_FPS := 12.0
const LAVA_IMPACT_ART_RADIUS := 15.5
const STOMP_RING_PATH := "res://art/effects/stomp_ring_6f.png"
const STOMP_RING_FRAME := Vector2i(96, 96)
const STOMP_RING_FPS := 12.0
const STOMP_RING_ART_RADIUS := 46.5
const STOMP_RING_COLOR := Color(0.85, 0.5, 0.2, 0.9)
## Alpha of the warning circle in the dark half of its blink.
const WARNING_DIM := 0.45
## Share of the blast radius covered by the pool.
const POOL_RADIUS_SHARE := 0.85

var radius := 70.0
var damage := 1.0
var delay := 0.0
var target_mask := PhysicsLayers.PLAYER_HURTBOX
var source: Node = null
var knockback := 220.0
var sound := &"explosion"
var shake := 6.0
var color := Color(1.0, 0.45, 0.15)
## Tags of the hit (DamageData.tags).
var tags: Array[StringName] = [&"explosion"]
## Stun on an effective hit (D-066); dash I-frames avoid it like the damage.
var stun_duration := 0.0
## LOOK_EXPLOSION, LOOK_LAVA or LOOK_STOMP.
var look := LOOK_EXPLOSION
## Lobbed: the ball starts here (global) and lands when the delay is over; INF = not lobbed.
var lob_from := Vector2.INF
## Pool left behind (LavaPool): seconds and damage per tick; 0 = none.
var pool_time := 0.0
var pool_damage := 0.0

var _time := 0.0
var _warning: PlaceholderShape = null
var _fill: PlaceholderShape = null


static func spawn(parent: Node, global_pos: Vector2, blast_radius: float, blast_damage: float, warning_delay := 0.0) -> Blast:
	var blast := Blast.new()
	blast.radius = blast_radius
	blast.damage = blast_damage
	blast.delay = warning_delay
	parent.add_child(blast)
	blast.global_position = global_pos
	return blast


func _ready() -> void:
	z_index = -1
	if delay > 0.0:
		_warning = PlaceholderShape.new()
		_warning.radius = radius
		_warning.color = Color(color, 0.25)
		_warning.outline_color = Color(color, 0.9)
		add_child(_warning)
		LightSource.flash(self, global_position, radius * 1.2, delay + 0.2)
	# Set after spawn() added the blast: wait one frame for lob_from (spawn sets it afterwards).
	_setup_lob.call_deferred()


func is_lobbed() -> bool:
	return lob_from.is_finite()


## The ball in flight and an inner circle that fills the warning until it lands (readable timing).
func _setup_lob() -> void:
	if not is_lobbed() or delay <= 0.0 or not is_inside_tree():
		return
	_fill = PlaceholderShape.new()
	_fill.radius = radius
	_fill.color = Color(color, 0.3)
	_fill.outline_color = Color(color, 0.0)
	_fill.scale = Vector2.ONE * 0.05
	add_child(_fill)
	var left := maxf(0.05, delay - _time)
	_fill.create_tween().tween_property(_fill, "scale", Vector2.ONE, left)
	LobShell.launch(self, lob_from, global_position, left)


func _physics_process(delta: float) -> void:
	_time += delta
	if _warning != null:
		# Blinks in two hard steps (D-218), not a smooth pulse.
		_warning.modulate.a = 1.0 if sin(_time * 30.0) >= 0.0 else WARNING_DIM
	if _time >= delay:
		_detonate()
		queue_free()
		set_physics_process(false)


func _detonate() -> void:
	if target_mask != 0:
		var hit := DamageData.new()
		hit.amount = damage
		hit.source = source if is_instance_valid(source) else null
		hit.tags.assign(tags)
		hit.stun_duration = stun_duration
		hit.hit_id = DamageData.next_hit_id()
		AreaDamage.apply(self, global_position, radius, target_mask, hit, knockback)
	var parent := get_parent()
	match look:
		LOOK_STOMP:
			_show_stomp(parent)
		LOOK_LAVA:
			_show_lava(parent)
		_:
			var art_scale := PixelDraw.whole_scale(radius / EXPLOSION_ART_RADIUS)
			SpriteStrip.spawn_effect(parent, global_position, EXPLOSION_TEXTURE, Vector2i(96, 96), 14.0, Vector2(48, 48), Vector2(art_scale, art_scale))
	LightSource.flash(parent, global_position, radius * 2.2, 0.45)
	Burst.spawn(parent, global_position, color, 22, radius * 3.0, 0.5, 5.0)
	Sfx.play_at(parent, sound, global_position)
	CameraShake.shake(parent, shake)
	if pool_time > 0.0:
		LavaPool.spawn(parent, global_position, radius * POOL_RADIUS_SHARE, pool_time, pool_damage, target_mask, source)


func _show_lava(parent: Node) -> void:
	if ResourceLoader.exists(LAVA_IMPACT_PATH):
		var art_scale := PixelDraw.whole_scale(radius / LAVA_IMPACT_ART_RADIUS)
		SpriteStrip.spawn_effect(parent, global_position, load(LAVA_IMPACT_PATH) as Texture2D, LAVA_IMPACT_FRAME, LAVA_IMPACT_FPS, LAVA_IMPACT_PIVOT, Vector2(art_scale, art_scale))
		return
	var fallback_scale := PixelDraw.whole_scale(radius / EXPLOSION_ART_RADIUS)
	var sprite := SpriteStrip.spawn_effect(parent, global_position, EXPLOSION_TEXTURE, Vector2i(96, 96), 14.0, Vector2(48, 48), Vector2(fallback_scale, fallback_scale))
	if sprite != null:
		sprite.modulate = Color(1.0, 0.6, 0.3)


func _show_stomp(parent: Node) -> void:
	if ResourceLoader.exists(STOMP_RING_PATH):
		var art_scale := PixelDraw.whole_scale(radius / STOMP_RING_ART_RADIUS)
		SpriteStrip.spawn_effect(parent, global_position, load(STOMP_RING_PATH) as Texture2D, STOMP_RING_FRAME, STOMP_RING_FPS, Vector2(STOMP_RING_FRAME) * 0.5, Vector2(art_scale, art_scale))
		return
	PixelRingWave.spawn(parent, global_position, radius, STOMP_RING_COLOR, 0.4, 7.0, 0.15)
	PixelRingWave.spawn(parent, global_position, radius * 0.7, Color(STOMP_RING_COLOR, 0.6), 0.3, 4.0, 0.1)
