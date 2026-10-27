class_name WillOWisp
extends Node2D
## One light of the spell Irrlichter (KE7, KONZEPT §6.2): leaves Flint's flame fanned out around the
## aim, then homes in on the nearest enemy no other wisp of the same cast has picked, and hits it
## once. Without a target it drifts on and fades. Steering has no randomness, so the host's wisp
## and a client's look-only wisp (deals_damage false, from the cast event) fly the same way.
## Only the host's wisp hits (D-088: the host decides; on a client enemy hurtboxes are off anyway).
## Art: art/effects/spells/wisp_4f.png (4 × 10×10) with puffs of wisp_trail_3f.png left behind
## when delivered (frames, fps and pivot from SpellArt), else a drawn glowing ball with a drawn tail
## (SPRITES_V13 §B5); light is a LightSource that never counts for LightQuery.

## TESTWERTE
const START_SPEED := 160.0
const MAX_SPEED := 340.0
const ACCELERATION := 520.0
## Turn rate towards the target in radians per second.
const TURN_RATE := 7.0
## Fan of the wisps around the aim at launch (radians between neighbours).
const FAN := 0.6
## Seconds before a wisp looks for a target (the fan opens first).
const SEEK_DELAY := 0.12
const LIFETIME := 3.0
const FADE_TIME := 0.4
## Closer than this to its target a wisp flies straight at it (no circling around it).
const CLOSE_DISTANCE := 72.0
## Distance to the target's body centre that counts as a hit.
const HIT_DISTANCE := 18.0
const DRAW_RADIUS := 4.0
const LIGHT_RADIUS := 56.0
const ART_ID := &"wisp"
const TRAIL_ID := &"wisp_trail"
## Seconds between two trail puffs (optics, TESTWERT).
const TRAIL_INTERVAL := 0.06

## Hit by this wisp (EventBus.enemy_damaged carries it too); tests and tools listen.
signal hit_enemy(enemy: Enemy)

var caster: Player = null
var data: SpellData = null
var damage_amount := 0.0
## Host (or offline): this wisp hits. A client's wisp from the cast event only shows.
var deals_damage := true
## Wisps of the same cast share this list (enemies), so they spread over different enemies.
## Untyped: it may hold enemies that died meanwhile.
var claimed: Array = []

var target: Enemy = null
var velocity := Vector2.ZERO
var _age := 0.0
var _done := false
var _sprite: AnimatedSprite2D = null
var _trail: Dictionary = {}
var _trail_time := 0.0
var _light: LightSource = null


## Launches data.count wisps of one cast from origin around aim into the caster's world; returns
## them. deals_damage false = looks only (a client replaying the host's cast).
static func launch_all(cast_by: Player, spell: SpellData, origin: Vector2, aim: Vector2, amount: float, hits: bool) -> Array:
	var wisps: Array = []
	var parent := cast_by.get_parent() if cast_by != null else null
	if parent == null or spell == null:
		return wisps
	var direction := aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	var claimed_by_cast: Array = []
	for i in spell.count:
		var wisp := WillOWisp.new()
		wisp.caster = cast_by
		wisp.data = spell
		wisp.damage_amount = amount
		wisp.deals_damage = hits
		wisp.claimed = claimed_by_cast
		wisp.velocity = direction.rotated(fan_angle(i, spell.count)) * START_SPEED
		parent.add_child(wisp)
		wisp.global_position = origin
		wisps.append(wisp)
	return wisps


## Launch angle of the index-th of count wisps: fanned evenly around the aim.
static func fan_angle(index: int, count: int) -> float:
	return (index - (count - 1) * 0.5) * FAN


func _ready() -> void:
	z_index = 6
	_light = LightSource.new()
	_light.radius = LIGHT_RADIUS
	_light.color = data.color if data != null else Color.WHITE
	add_child(_light)
	var art := SpellArt.effect(ART_ID)
	if not art.is_empty():
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "Sprite"
		_sprite.sprite_frames = SpriteStrip.make_frames(art["texture"], art["frame"], float(art["fps"]), bool(art["loop"]))
		_sprite.offset = SpriteStrip.pivot_offset(art["frame"], art["pivot"])
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
		_sprite.play(&"default")
	_trail = SpellArt.effect(TRAIL_ID)


func _physics_process(delta: float) -> void:
	step(delta)


## One step: age, pick a target, steer, move, hit. Public for tests and tools.
func step(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= LIFETIME:
		_finish(false)
		return
	if _age >= SEEK_DELAY and not _has_target():
		target = pick_target()
	var speed := minf(MAX_SPEED, velocity.length() + ACCELERATION * delta)
	var heading := velocity.normalized() if velocity != Vector2.ZERO else Vector2.RIGHT
	if _has_target():
		var to_target := SpellEffects.body_center(target) - global_position
		var wanted := to_target.normalized()
		if to_target.length() <= CLOSE_DISTANCE:
			heading = wanted
		else:
			heading = heading.rotated(clampf(heading.angle_to(wanted), -TURN_RATE * delta, TURN_RATE * delta))
	velocity = heading * speed
	_leave_trail(delta)
	global_position += velocity * delta
	if _has_target() and global_position.distance_to(SpellEffects.body_center(target)) <= HIT_DISTANCE:
		_hit(target)
	queue_redraw()


## Nearest valid enemy within data.radius that no other wisp of this cast has picked; when all are
## picked, the nearest one anyway. null without enemies in reach.
## Puffs of wisp_trail behind the wisp (delivered art only; the placeholder draws its tail).
func _leave_trail(delta: float) -> void:
	if _trail.is_empty() or not is_inside_tree() or get_parent() == null:
		return
	_trail_time += delta
	if _trail_time < TRAIL_INTERVAL:
		return
	_trail_time -= TRAIL_INTERVAL
	var puff := SpriteStrip.spawn_effect(get_parent(), global_position, _trail["texture"], _trail["frame"], float(_trail["fps"]),
		_trail["pivot"], Vector2.ONE * SpriteStrip.PIXEL_SCALE)
	puff.name = "WispTrail"
	puff.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func pick_target() -> Enemy:
	var reach := data.radius if data != null and data.radius > 0.0 else 512.0
	var best: Enemy = null
	var best_free: Enemy = null
	var best_distance := INF
	var best_free_distance := INF
	for enemy in SpellEffects.enemies_within(self, global_position, reach):
		var distance := global_position.distance_squared_to(SpellEffects.body_center(enemy))
		if distance < best_distance:
			best_distance = distance
			best = enemy
		if not claimed.has(enemy) and distance < best_free_distance:
			best_free_distance = distance
			best_free = enemy
	var chosen := best_free if best_free != null else best
	if chosen != null and not claimed.has(chosen):
		claimed.append(chosen)
	return chosen


func is_done() -> bool:
	return _done


func _has_target() -> bool:
	return target != null and is_instance_valid(target) and SpellEffects.is_valid_target(target)


func _hit(enemy: Enemy) -> void:
	if deals_damage and caster != null and is_instance_valid(caster) and enemy.hurtbox != null:
		enemy.hurtbox.receive_hit(SpellEffects.make_hit(caster, data, damage_amount))
	hit_enemy.emit(enemy)
	Burst.spawn(get_parent(), global_position, data.color, 8, 120.0, 0.3, 3.0)
	_finish(true)


func _finish(hit: bool) -> void:
	_done = true
	set_physics_process(false)
	if hit or not is_inside_tree():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)


## Drawn ball while the art is missing, in pixel art (PixelDraw, D-218): a bright core with a
## see-through rim in the spell colour and two pixel puffs behind it, on the world grid.
func _draw() -> void:
	if _sprite != null:
		return
	PixelDraw.align_to_world_grid(self)
	paint(self)


## The drawn ball around item's origin (a CanvasItem in _draw, or a PixelDraw.Raster).
func paint(item: Object) -> void:
	var color := data.color if data != null else Color.WHITE
	if velocity != Vector2.ZERO:
		var back := -velocity.normalized()
		PixelDraw.disc(item, back * 11.0, DRAW_RADIUS * 0.35, Color(color, 0.25))
		PixelDraw.disc(item, back * 6.0, DRAW_RADIUS * 0.6, Color(color, 0.5))
	PixelDraw.disc(item, Vector2.ZERO, DRAW_RADIUS + PixelDraw.WORLD_PIXEL, Color(color, 0.35))
	PixelDraw.disc(item, Vector2.ZERO, DRAW_RADIUS, color)
	PixelDraw.rect(item, Rect2(-Vector2.ONE * PixelDraw.WORLD_PIXEL, Vector2.ONE * PixelDraw.WORLD_PIXEL), Color(1, 1, 1, 0.9))
