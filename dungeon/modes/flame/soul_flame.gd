class_name SoulFlame
extends Node2D
## The soul flame of "Flamme hüten" (KONZEPT_RAEUME_V2 §3.4; before KONZEPT_RAEUME §4.1): a candle
## flame with its own health bar. Its light follows its health (FlameRules.light_radius). Enemies
## that chose it as their target (EnemyDecoy) attack it with their normal, telegraphed attacks; its
## hurtbox only takes enemy damage (SoulFlameHurtbox). Players cannot hurt it and walk around it.
## The origin is the "body centre" like a character's (base line + Player.FEET_OFFSET), so it sorts
## against the feet of players and enemies and enemies aim at its middle.
## Logic (health, extinguished) and look (sprite, light, bar, dying animation) stay apart: the look
## follows the signals.

signal damaged(flame: SoulFlame, result: DamageResult)
signal extinguished(flame: SoulFlame)

const HURT_RADIUS := 24.0
const BLOCKER_SIZE := Vector2(18, 10)
const OUT_LIGHT_RADIUS := 50.0
const BAR_SIZE := Vector2(44.0, 6.0)
const BAR_FILL := Color("#a66ef0")
const BAR_BACKGROUND := Color("#1c1a2b")
const COLOR := Color("#a66ef0")

var health: HealthComponent = null
var hurtbox: SoulFlameHurtbox = null

var _sprite: AnimatedSprite2D = null
var _light: LightSource = null
var _bar: ProgressBar = null
var _timer_label: Label = null


## Builds children and health; call before or after entering the tree, once.
func build(max_health: float) -> void:
	var base := Player.FEET_OFFSET
	DropShadow.attach(self, 14.0, base.y - 2.0)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	VariantArt.add_animation(frames, &"burn", VariantArt.SOUL_FLAME, true)
	VariantArt.add_animation(frames, &"dying", VariantArt.SOUL_FLAME_DYING, false)
	_sprite.sprite_frames = frames
	_sprite.offset = SpriteStrip.pivot_offset(VariantArt.get_frame_size(VariantArt.SOUL_FLAME), VariantArt.get_pivot(VariantArt.SOUL_FLAME))
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_sprite.position = base
	add_child(_sprite)
	_sprite.play(&"burn")
	_light = LightSource.new()
	_light.name = "Light"
	_light.radius = FlameRules.LIGHT_RADIUS
	_light.intensity = 0.9
	_light.flicker = 0.08
	_light.position = Vector2(0, -24)
	add_child(_light)
	var blocker := StaticBody2D.new()
	blocker.name = "Blocker"
	blocker.collision_layer = PhysicsLayers.WORLD
	blocker.collision_mask = 0
	var block_shape := RectangleShape2D.new()
	block_shape.size = BLOCKER_SIZE
	var block_collision := CollisionShape2D.new()
	block_collision.shape = block_shape
	block_collision.position = base - Vector2(0, BLOCKER_SIZE.y * 0.5)
	blocker.add_child(block_collision)
	add_child(blocker)
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = max_health
	add_child(health)
	health.reset(max_health)
	hurtbox = SoulFlameHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.health = health
	var hurt_shape := CircleShape2D.new()
	hurt_shape.radius = HURT_RADIUS
	var hurt_collision := CollisionShape2D.new()
	hurt_collision.shape = hurt_shape
	hurt_collision.position = Vector2(0, -6)
	hurtbox.add_child(hurt_collision)
	add_child(hurtbox)
	_build_bar()
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	hurtbox.hit_received.connect(_on_hit_received)


## Decoy contract (EnemyDecoy, EnemyTargeting.is_alive).
func is_alive() -> bool:
	return health != null and not health.is_dead()


func get_health_ratio() -> float:
	if health == null or health.get_max_health() <= 0.0:
		return 0.0
	return health.get_health() / health.get_max_health()


## Seconds of raid left above the flame (negative = hide). The task bar shows the time now; kept for
## tools.
func show_time_left(seconds: float) -> void:
	if _timer_label == null:
		return
	_timer_label.visible = seconds >= 0.0 and is_alive()
	if _timer_label.visible:
		_timer_label.text = "%d" % ceili(seconds)


func _build_bar() -> void:
	_bar = ProgressBar.new()
	_bar.name = "HealthBar"
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = BAR_BACKGROUND
	var fill := StyleBoxFlat.new()
	fill.bg_color = BAR_FILL
	_bar.add_theme_stylebox_override("background", background)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.size = BAR_SIZE
	_bar.position = Vector2(-BAR_SIZE.x * 0.5, -86.0)
	_bar.z_index = 20
	_bar.max_value = health.get_max_health()
	_bar.value = health.get_health()
	add_child(_bar)
	_timer_label = UiKit.text_label("", UiKit.SIZE_BODY, Color("#dcbcff"), true)
	_timer_label.name = "TimeLeft"
	_timer_label.z_index = 20
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_label.add_theme_font_size_override("font_size", 14)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.size = Vector2(60, 18)
	_timer_label.position = Vector2(-30, -108)
	_timer_label.visible = false
	add_child(_timer_label)


func _on_health_changed(current: float, maximum: float) -> void:
	if _bar != null:
		_bar.max_value = maximum
		_bar.value = current
	# The flame grows darker with every hit (Claude Design: "Lichtradius = HP").
	if _light != null and current > 0.0 and maximum > 0.0:
		_light.radius = FlameRules.light_radius(current / maximum)


func _on_hit_received(result: DamageResult, _damage: DamageData) -> void:
	damaged.emit(self, result)
	if not is_inside_tree():
		return
	DamageNumber.spawn_for_result(get_parent(), global_position + Vector2(0, -60), result)
	SpriteFx.flash(_sprite, Color(1.0, 0.5, 0.5), 0.12)
	Burst.spawn(get_parent(), global_position + Vector2(0, -30), COLOR, 6, 90.0)
	Sfx.play_at(self, &"soul_flame_hit", global_position, -6.0)


func _on_died() -> void:
	hurtbox.set_deferred("monitorable", false)
	if _bar != null:
		_bar.visible = false
	if _timer_label != null:
		_timer_label.visible = false
	_sprite.play(&"dying")
	_light.radius = OUT_LIGHT_RADIUS
	_light.intensity = 0.4
	extinguished.emit(self)
	if is_inside_tree():
		Burst.spawn(get_parent(), global_position + Vector2(0, -30), COLOR, 26, 160.0, 0.7)
		Sfx.play_at(self, &"soul_flame_out", global_position)
		CameraShake.shake(self, 4.0)
