class_name SideSaw
extends Node2D
## A saw on a rail of the jump trial (Säge auf Schiene, SV2, D-195, plan "X" on a rail of "+"): a
## spinning blade going back and forth along its rail; touching it costs what the spikes cost (one
## heart, shield first, SideElementRules.SAW_DAMAGE) and the hit comes again after SAW_REARM. Its
## place is a pure function of the clock (seconds since the segment began) and a phase from the
## segment seed and its build index, like the moving platforms: every machine shows it at the same
## place; the host's clock is the truth (apply_clock, hook for NetSide), damage counts like the
## spikes'. The origin of the node is the middle of its plan cell; the rail is drawn under the blade.
## Art: saw_8f.png (8 × 32×32, spinning) and saw_rail.png (32×8, tiled), else drawn.

const SAW_ART := "res://art/environment/side/saw_8f.png"
const RAIL_ART := "res://art/environment/side/saw_rail.png"
const SAW_FRAME := Vector2i(32, 32)
const SAW_FPS := 16.0
const BLADE_COLOR := Color(0.82, 0.84, 0.9)
const HUB_COLOR := Color(0.3, 0.28, 0.34)
const RAIL_COLOR := Color(0.28, 0.25, 0.3)

var saw: SideLayout.Saw = null
## Seconds since the segment began (host: its own; client: the host's through apply_clock).
var clock := 0.0
## Start phase in seconds (SideElementRules.phase_for).
var phase := 0.0
## Hits landed on players during this segment (tools, tests).
var hits := 0

var _blade: Node2D = null
var _hitbox: Hitbox = null
var _rearm_left := 0.0


## Before entering the tree: the plan's saw, the segment seed and the build index (the phase).
func setup(plan_saw: SideLayout.Saw, segment_seed: int, index: int) -> void:
	saw = plan_saw
	phase = SideElementRules.phase_for(segment_seed, index, cycle())
	name = "Saw%d_%d" % [saw.cell.x, saw.cell.y]


func _ready() -> void:
	z_index = 1
	_build_rail()
	_blade = Node2D.new()
	_blade.name = "Blade"
	add_child(_blade)
	if ResourceLoader.exists(SAW_ART):
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = SpriteStrip.make_frames(load(SAW_ART) as Texture2D, SAW_FRAME, SAW_FPS, true)
		sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		sprite.play(&"default")
		_blade.add_child(sprite)
	else:
		var drawn := _Blade.new()
		drawn.name = "Drawn"
		_blade.add_child(drawn)
	_hitbox = Hitbox.new()
	_hitbox.name = "Hitbox"
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = PhysicsLayers.PLAYER_HURTBOX
	var circle := CircleShape2D.new()
	circle.radius = SideElementRules.SAW_RADIUS
	var shape := CollisionShape2D.new()
	shape.shape = circle
	_hitbox.add_child(shape)
	_hitbox.hit_landed.connect(_on_hit_landed.unbind(2))
	_blade.add_child(_hitbox)
	_blade.position = local_center_at(clock)
	_arm()


func _physics_process(delta: float) -> void:
	clock += delta
	_blade.position = local_center_at(clock)
	_rearm_left -= delta
	if _rearm_left <= 0.0:
		_arm()


## The host's clock on a client (NetSide hook).
func apply_clock(time: float) -> void:
	clock = time
	_blade.position = local_center_at(clock)


## Seconds of one full back-and-forth.
func cycle() -> float:
	return SideElementRules.period(_rail_length(), SideElementRules.SAW_SPEED, SideElementRules.SAW_PAUSE)


## Middle of the blade relative to the node at a clock time.
func local_center_at(time: float) -> Vector2:
	var travel := SideElementRules.ping_pong(time + phase, _rail_length(), SideElementRules.SAW_SPEED, SideElementRules.SAW_PAUSE)
	return Vector2(saw.axis) * (saw.low * SideRules.TILE + travel)


## Middle of the blade (global) at a clock time (the bot looks ahead with it).
func center_at(time: float) -> Vector2:
	return global_position + local_center_at(time)


## A new attack instance: the same player can be hit again (after their invulnerability).
func _arm() -> void:
	_rearm_left = SideElementRules.SAW_REARM
	var damage := DamageData.new()
	damage.amount = SideElementRules.SAW_DAMAGE
	damage.tags.assign([&"trap"])
	_hitbox.begin_attack(damage)


func _on_hit_landed() -> void:
	hits += 1


func _rail_length() -> float:
	return (saw.high - saw.low) * SideRules.TILE


## The rail from end to end, tiled (rotated for an upright rail).
func _build_rail() -> void:
	var start := Vector2(saw.axis) * saw.low * SideRules.TILE
	var length := _rail_length()
	var texture := load(RAIL_ART) as Texture2D if ResourceLoader.exists(RAIL_ART) else null
	if texture == null:
		var line := Line2D.new()
		line.name = "Rail"
		line.width = 8.0
		line.default_color = RAIL_COLOR
		line.points = PackedVector2Array([start, start + Vector2(saw.axis) * length])
		line.z_index = -2
		add_child(line)
		return
	var vertical := saw.axis == Vector2i.DOWN
	var pieces := maxi(1, roundi(length / SideRules.TILE)) + 1
	for i in pieces:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		sprite.rotation = PI * 0.5 if vertical else 0.0
		sprite.position = start + Vector2(saw.axis) * (i * SideRules.TILE)
		sprite.z_index = -2
		add_child(sprite)


## Placeholder blade until saw_8f.png: a toothed disc spinning, filled on the art-pixel grid (the
## node never turns, the teeth do; D-218).
class _Blade:
	extends Node2D
	var _turn := 0.0

	func _process(delta: float) -> void:
		_turn += delta * 14.0
		queue_redraw()

	func _draw() -> void:
		var points := PackedVector2Array()
		for i in 24:
			var angle := _turn + TAU * i / 24.0
			points.append(Vector2.from_angle(angle) * (30.0 if i % 2 == 0 else 22.0))
		SidePixels.polygon(self, points, SideSaw.BLADE_COLOR)
		SidePixels.disc(self, Vector2.ZERO, 8.0, SideSaw.HUB_COLOR)
