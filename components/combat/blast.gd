class_name Blast
extends Node2D
## Area explosion with an optional visible warning circle (bomber, volatile elites, boss slams).
## Detonates in _physics_process so the area query is always allowed.

const EXPLOSION_TEXTURE: Texture2D = preload("res://art/effects/explosion_6f.png")
const EXPLOSION_ART_RADIUS := 45.0

var radius := 70.0
var damage := 1.0
var delay := 0.0
var target_mask := PhysicsLayers.PLAYER_HURTBOX
var source: Node = null
var knockback := 220.0
var sound := &"explosion"
var shake := 6.0
var color := Color(1.0, 0.45, 0.15)

var _time := 0.0
var _warning: PlaceholderShape = null


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


func _physics_process(delta: float) -> void:
	_time += delta
	if _warning != null:
		_warning.modulate.a = 0.5 + 0.5 * sin(_time * 30.0)
	if _time >= delay:
		_detonate()
		queue_free()
		set_physics_process(false)


func _detonate() -> void:
	var hit := DamageData.new()
	hit.amount = damage
	hit.source = source if is_instance_valid(source) else null
	hit.tags.assign([&"explosion"])
	hit.hit_id = DamageData.next_hit_id()
	AreaDamage.apply(self, global_position, radius, target_mask, hit, knockback)
	var parent := get_parent()
	var art_scale := radius / EXPLOSION_ART_RADIUS
	SpriteStrip.spawn_effect(parent, global_position, EXPLOSION_TEXTURE, Vector2i(96, 96), 14.0, Vector2(48, 48), Vector2(art_scale, art_scale))
	LightSource.flash(parent, global_position, radius * 2.2, 0.45)
	Burst.spawn(parent, global_position, color, 22, radius * 3.0, 0.5, 5.0)
	Sfx.play_at(parent, sound, global_position)
	CameraShake.shake(parent, shake)
