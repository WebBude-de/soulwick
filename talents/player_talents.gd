class_name PlayerTalents
extends Node
## The talents of one player in this run (KE6, D-088: state per player, child "Talents" of the
## Player). Holds the distribution and its numbers (TalentStats), puts the run-start values on the
## player (max HP, move speed, dash cooldown and charges; taken back on a new distribution) and runs
## the talents that react during play: Ausweichkunst after a dash, Windläufer trail, Glutherz wave,
## Zweites Herz. Decisions live in functions (claim_second_heart, should_trigger_ember_wave);
## signals drive the look. Created by TalentEffects.apply_to(); the host runs it for every player.

## Zweites Herz caught a lethal hit; the player stands with hp HP.
signal second_heart_used(hp: float)
## Glutherz went off at center (damage is dealt in the next physics frame).
signal ember_wave_triggered(center: Vector2)
## A dash ended; Ausweichkunst is active for TalentEffects.EVASION_TIME seconds.
signal evasion_started(duration: float)
## Windläufer left a trail from start to end of a dash.
signal wind_trail_spawned(trail: WindRunnerTrail)

const NODE_NAME := &"Talents"
const EMBER_COLOR := Color(1.0, 0.45, 0.15)
## Glutherz art (SPRITES_V13 Teil C, V13c talents_fx.json): 6 frames of 128 px, pivot in the middle,
## 12 fps; the ring ends at EMBER_WAVE_ART_RADIUS (measured: the last frame reaches the frame edge).
const EMBER_WAVE_ART_PATH := "res://art/effects/talents/ember_wave_6f.png"
const EMBER_WAVE_ART_FRAME := Vector2i(128, 128)
const EMBER_WAVE_ART_RADIUS := 64.0
const EMBER_WAVE_ART_FPS := 12.0

var state: TalentState = TalentState.new()
var stats: TalentStats = TalentStats.new()

var _player: Player = null
## Run-start values put on the player, to take them back: {"health": float, "speed": float,
## "dash_cooldown": float, "dash_charges": int} (what was added or the value before).
var _applied: Dictionary = {}
var _second_heart_used := false
var _ember_cooldown_left := 0.0
var _evasion_left := 0.0
var _was_dashing := false
var _dash_start := Vector2.ZERO
var _pending_waves: Array[Vector2] = []


## Talents of player (or of the player above node), null without.
static func of(node: Node) -> PlayerTalents:
	var player := _find_player(node)
	if player == null:
		return null
	return player.get_node_or_null(NodePath(NODE_NAME)) as PlayerTalents


static func _find_player(node: Node) -> Player:
	var current := node
	while current != null and is_instance_valid(current):
		if current is Player:
			return current as Player
		current = current.get_parent()
	return null


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("PlayerTalents must be a child of a Player (TalentEffects.apply_to).")
		return
	if not _player.is_node_ready():
		await _player.ready
	_player.hurtbox.hit_received.connect(_on_hit_received)
	_install_death_guard()
	_apply_run_values()
	ember_wave_triggered.connect(_play_ember_wave_look)


## Sets a new distribution; on a player already in the run the old run-start values are taken back
## and the new ones put on.
func set_distribution(new_state: TalentState, tree: TalentTree = null) -> void:
	if is_node_ready() and _player != null:
		_revert_run_values()
	state = new_state.duplicate_state() if new_state != null else TalentState.new()
	stats = TalentEffects.resolve(state, tree)
	if is_node_ready() and _player != null and _player.is_node_ready():
		_apply_run_values()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_ember_cooldown_left = maxf(0.0, _ember_cooldown_left - delta)
	_evasion_left = maxf(0.0, _evasion_left - delta)
	_track_dash()
	# Area hits only outside hit callbacks (AreaDamage needs an unlocked physics space).
	var waves := _pending_waves
	_pending_waves = []
	for center in waves:
		_deal_ember_wave(center)


# --- Ausweichkunst and Windläufer ---

func is_evasion_active() -> bool:
	return _evasion_left > 0.0


## Situational damage factor of this player's attacks right now (D-019: multiplies).
func get_attack_multiplier() -> float:
	if stats.evasion_damage_percent <= 0.0 or not is_evasion_active():
		return 1.0
	return 1.0 + stats.evasion_damage_percent


func _track_dash() -> void:
	var dashing := _player.is_dashing()
	if dashing and not _was_dashing:
		_dash_start = _player.get_feet_position()
	elif not dashing and _was_dashing:
		_on_dash_ended(_dash_start, _player.get_feet_position())
	_was_dashing = dashing


func _on_dash_ended(from: Vector2, to: Vector2) -> void:
	if stats.evasion_damage_percent > 0.0:
		_evasion_left = TalentEffects.EVASION_TIME
		evasion_started.emit(TalentEffects.EVASION_TIME)
	if stats.wind_runner and from.distance_to(to) > 1.0:
		var trail := WindRunnerTrail.create(from, to, _player)
		var parent := _player.get_parent()
		if parent != null:
			parent.add_child(trail)
			wind_trail_spawned.emit(trail)


# --- Zweites Herz ---

## Decides a lethal hit: alone, once per run, the player stays up with SECOND_HEART_HEALTH HP
## (returns it); otherwise 0 (the player falls). In a group game the talent speeds up the revive
## instead (TalentEffects.revive_speed). Hook for HealthComponent.death_guard.
func claim_second_heart() -> float:
	if not can_use_second_heart():
		return 0.0
	_second_heart_used = true
	second_heart_used.emit(TalentEffects.SECOND_HEART_HEALTH)
	if _player != null:
		_player.call_deferred(&"grant_invulnerability", Player.REVIVE_INVULNERABILITY)
	return TalentEffects.SECOND_HEART_HEALTH


func can_use_second_heart() -> bool:
	return stats.second_heart and not _second_heart_used and not _in_group_game()


func is_second_heart_used() -> bool:
	return _second_heart_used


func _in_group_game() -> bool:
	return _player != null and GameMode.of(_player).get_player_count() > 1


## HealthComponent asks death_guard before a player dies (integrator hook); without the property
## Zweites Herz waits for that hook.
func _install_death_guard() -> void:
	if &"death_guard" in _player.health:
		_player.health.set(&"death_guard", claim_second_heart)


# --- Glutherz ---

## A hit that leaves the living player below EMBER_HEART_BELOW_HEALTH HP sets off a wave, at most
## once per EMBER_HEART_COOLDOWN.
func should_trigger_ember_wave(health_after_hit: float, effective: bool) -> bool:
	return stats.ember_heart and effective and health_after_hit > 0.0 \
		and health_after_hit < TalentEffects.EMBER_HEART_BELOW_HEALTH and _ember_cooldown_left <= 0.0


func get_ember_cooldown_left() -> float:
	return _ember_cooldown_left


func _on_hit_received(result: DamageResult, _damage: DamageData) -> void:
	if not should_trigger_ember_wave(_player.health.get_health(), result.is_effective()):
		return
	_ember_cooldown_left = TalentEffects.EMBER_HEART_COOLDOWN
	var center := _player.global_position
	_pending_waves.append(center)
	ember_wave_triggered.emit(center)


func _deal_ember_wave(center: Vector2) -> void:
	var damage := DamageData.new()
	damage.amount = TalentEffects.EMBER_WAVE_DAMAGE
	damage.source = _player
	# A talent effect, not a weapon hit: no upgrade chains (D-030).
	damage.origin = DamageData.Origin.SECONDARY
	damage.tags.assign([TalentEffects.EMBER_WAVE_TAG])
	damage.hit_id = DamageData.next_hit_id()
	AreaDamage.apply(_player, center, TalentEffects.EMBER_WAVE_RADIUS, PhysicsLayers.ENEMY_HURTBOX,
		damage, TalentEffects.EMBER_WAVE_KNOCKBACK)


## The wave's art when delivered (SPRITES_V13 Teil C), sparks and light either way.
func _play_ember_wave_look(center: Vector2) -> void:
	var parent := _player.get_parent() if _player != null else null
	if parent == null:
		return
	if ResourceLoader.exists(EMBER_WAVE_ART_PATH):
		# A whole scale keeps the art's pixels even (FS2b); the hit radius stays exact.
		var art_scale := Vector2.ONE * PixelDraw.whole_scale(TalentEffects.EMBER_WAVE_RADIUS / EMBER_WAVE_ART_RADIUS)
		SpriteStrip.spawn_effect(parent, center, load(EMBER_WAVE_ART_PATH) as Texture2D, EMBER_WAVE_ART_FRAME, EMBER_WAVE_ART_FPS,
			Vector2(EMBER_WAVE_ART_FRAME) * 0.5, art_scale)
	Burst.spawn(parent, center, EMBER_COLOR, 22, 260.0, 0.5, 5.0)
	LightSource.flash(parent, center, TalentEffects.EMBER_WAVE_RADIUS * 1.8, 0.4)
	Sfx.play_at(_player, &"explosion", center, -4.0)
	if _player.is_local:
		CameraShake.shake(_player, 5.0)


# --- Run-start values ---

func _apply_run_values() -> void:
	_applied.clear()
	if stats.max_health_bonus > 0.0:
		_player.health.reset(_player.health.get_max_health() + stats.max_health_bonus)
		_applied["health"] = stats.max_health_bonus
	if stats.move_speed_percent != 0.0:
		_applied["speed"] = _player.move_speed
		_player.move_speed = TalentEffects.move_speed(_player.move_speed, stats)
	if stats.dash_cooldown_reduction > 0.0:
		_applied["dash_cooldown"] = _player.dash_cooldown
		_player.dash_cooldown = TalentEffects.dash_cooldown(_player.dash_cooldown, stats)
	# Doppel-Dash: Player.dash_charges is the integrator hook (KE6 report); without it, one charge.
	if stats.dash_charges > 1 and &"dash_charges" in _player:
		_applied["dash_charges"] = _player.get(&"dash_charges")
		_player.set(&"dash_charges", stats.dash_charges)


func _revert_run_values() -> void:
	if _applied.has("health"):
		_player.health.reset(maxf(1.0, _player.health.get_max_health() - float(_applied["health"])))
	if _applied.has("speed"):
		_player.move_speed = float(_applied["speed"])
	if _applied.has("dash_cooldown"):
		_player.dash_cooldown = float(_applied["dash_cooldown"])
	if _applied.has("dash_charges"):
		_player.set(&"dash_charges", _applied["dash_charges"])
	_applied.clear()
