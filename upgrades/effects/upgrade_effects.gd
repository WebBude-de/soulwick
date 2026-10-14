class_name UpgradeEffects
extends Node2D
## Resolves upgrade effects that react to hits: "Explosiver Treffer" and ON_KILL rewards.
## Rules: secondary hits never trigger secondary effects (D-030); one explosion per attack
## instance / hit ID, so one primary staff AOE causes at most one explosion (D-031, D-056);
## kills by secondary hits still grant ON_KILL rewards (D-032).

const EXPLOSION_TEXTURE: Texture2D = preload("res://art/effects/explosion_6f.png")
## PLATZHALTER: the GDD does not specify the explosion radius of "Explosiver Treffer".
const EXPLOSION_RADIUS := 48.0
const EXPLOSION_KNOCKBACK := 120.0
## Explosion art: the 45 px AOE radius matches the 96 px frame at scale 1.
const EXPLOSION_ART_RADIUS := 45.0
const MAX_REMEMBERED_HIT_IDS := 512
## TESTWERT (D-091): "Schild bei Tötung" only fills the shield up to this value,
## +KILL_SHIELD_CAP_PER_STACK per further stack, at most KILL_SHIELD_CAP_MAX.
const KILL_SHIELD_CAP := 10.0
const KILL_SHIELD_CAP_PER_STACK := 2.0
const KILL_SHIELD_CAP_MAX := 20.0

@export var upgrade_manager: UpgradeManager

var player: Player = null

var _pending_explosions: Array[Dictionary] = []
var _exploded_hit_ids: Dictionary[int, bool] = {}


func _ready() -> void:
	EventBus.enemy_damaged.connect(_on_enemy_damaged)


func _physics_process(_delta: float) -> void:
	# Explosions run here, outside hit callbacks, so area queries are always allowed.
	var explosions := _pending_explosions
	_pending_explosions = []
	for explosion in explosions:
		_explode(explosion)


func _on_enemy_damaged(enemy: Node2D, result: DamageResult, damage: DamageData) -> void:
	if result.killed:
		_grant_kill_rewards()
	if damage.origin != DamageData.Origin.PRIMARY or upgrade_manager == null:
		return
	var ratio := upgrade_manager.get_modifier(UpgradeData.Effect.EXPLOSIVE_HIT, damage.tags)
	if ratio <= 0.0 or _exploded_hit_ids.has(damage.hit_id):
		return
	if _exploded_hit_ids.size() > MAX_REMEMBERED_HIT_IDS:
		_exploded_hit_ids.clear()
	_exploded_hit_ids[damage.hit_id] = true
	var center := damage.impact_position if damage.has_impact_position else enemy.global_position
	_pending_explosions.append({"center": center, "amount": result.amount * ratio})


func _explode(explosion: Dictionary) -> void:
	var damage := DamageData.new()
	damage.amount = explosion["amount"]
	damage.source = player
	damage.origin = DamageData.Origin.SECONDARY
	damage.tags.assign([&"explosion"])
	damage.hit_id = DamageData.next_hit_id()
	var center: Vector2 = explosion["center"]
	AreaDamage.apply(self, center, EXPLOSION_RADIUS, PhysicsLayers.ENEMY_HURTBOX, damage, EXPLOSION_KNOCKBACK)
	var art_scale := EXPLOSION_RADIUS / EXPLOSION_ART_RADIUS
	SpriteStrip.spawn_effect(self, center, EXPLOSION_TEXTURE, Vector2i(96, 96), 14.0, Vector2(48, 48), Vector2(art_scale, art_scale))
	LightSource.flash(self, center, EXPLOSION_RADIUS * 2.2, 0.35)
	Burst.spawn(self, center, Color(1.0, 0.6, 0.2), 14, 160.0)
	Sfx.play_at(self, &"explosion", center, -3.0)
	CameraShake.shake(self, 5.0)


func _grant_kill_rewards() -> void:
	if player == null or upgrade_manager == null or not player.is_alive():
		return
	var heal := upgrade_manager.get_total(UpgradeData.Effect.HEAL_ON_KILL)
	if heal > 0.0:
		player.health.heal(heal)
	var shield := upgrade_manager.get_total(UpgradeData.Effect.SHIELD_ON_KILL)
	if shield > 0.0:
		player.shield.add_shield_up_to(shield, get_kill_shield_cap(upgrade_manager))


static func get_kill_shield_cap(upgrades: UpgradeManager) -> float:
	var stacks := 0
	for upgrade in upgrades.upgrade_pool:
		if upgrade.effect == UpgradeData.Effect.SHIELD_ON_KILL:
			stacks += upgrades.get_stacks(upgrade.id)
	if stacks <= 0:
		return 0.0
	return minf(KILL_SHIELD_CAP_MAX, KILL_SHIELD_CAP + KILL_SHIELD_CAP_PER_STACK * (stacks - 1))
