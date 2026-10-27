class_name TalentEffects
extends RefCounted
## Talents as one source of player values ("Talente", next to the forge's MetaProgression; KONZEPT
## §6.1, D-194). resolve() is a pure function from a distribution to numbers (TalentStats); apply_to()
## puts a distribution on a player for this run (PlayerTalents child, state per player, D-088); the
## static getters are the hooks the player, the weapons, the hit rules, the revive and the spells
## (KE7) ask. A player without talents gets neutral answers, so every hook is safe in every mode.
## Where the distribution comes from is the caller's business (account for the solo character,
## server for the guild character, MP8b; the host takes the clients' from the lobby message).
## All values are TESTWERTE.

## Ausweichkunst: the damage bonus lasts this long after a dash ends.
const EVASION_TIME := 1.0
## The dash cooldown never goes below this (same floor as the forge, MetaProgression.MIN_DASH_COOLDOWN).
const MIN_DASH_COOLDOWN := 0.3
## Standfest never takes more than this off knockback and stun.
const MAX_STAGGER_REDUCTION := 0.75
## Konzentration never takes the spell cooldown below this factor.
const MIN_SPELL_COOLDOWN_FACTOR := 0.5
## Zweites Herz: alone, get up once per run with this many HP …
const SECOND_HEART_HEALTH := 2.0
## … in a group game, be revived this many times as fast instead.
const SECOND_HEART_REVIVE_SPEED := 2.0
## Glutherz: a hit that leaves the player below this many HP sets off an ember wave …
const EMBER_HEART_BELOW_HEALTH := 2.0
## … at most once in this many seconds.
const EMBER_HEART_COOLDOWN := 10.0
const EMBER_WAVE_DAMAGE := 3.0
## 2.5 tiles (RoomTiles.TILE_WORLD = 64 px).
const EMBER_WAVE_RADIUS := 160.0
const EMBER_WAVE_KNOCKBACK := 260.0
const EMBER_WAVE_TAG: StringName = &"ember_wave"
## Windläufer: the light trail of a dash stays this long …
const WIND_TRAIL_LIFETIME := 2.0
## … and slows enemies on it to this factor of their speed for WIND_TRAIL_SLOW_TIME seconds.
const WIND_TRAIL_SLOW_FACTOR := 0.6
const WIND_TRAIL_SLOW_TIME := 1.0
const WIND_TRAIL_HALF_WIDTH := 22.0


# --- Pure resolution ---

## Numbers of a distribution. Levels above max_level count as max_level, unknown talents not at all.
static func resolve(state: TalentState, tree: TalentTree = null) -> TalentStats:
	var catalog := tree if tree != null else TalentTree.get_default()
	var stats := TalentStats.new()
	if state == null or catalog == null:
		return stats
	for talent in catalog.talents:
		if talent == null:
			continue
		var level := mini(state.get_level(talent.id), talent.max_level)
		if level > 0:
			_add(stats, talent, level)
	stats.unlocked_spells = state.get_unlocked_spells(catalog)
	stats.spell_slots = state.get_spell_slots(catalog)
	for spell in state.equipped_spells:
		if spell != &"" and stats.unlocked_spells.has(spell) and stats.equipped_spells.size() < stats.spell_slots:
			stats.equipped_spells.append(spell)
	return stats


static func _add(stats: TalentStats, talent: TalentDef, level: int) -> void:
	var total := talent.value * level
	match talent.effect:
		TalentDef.Effect.MOVE_SPEED_PERCENT:
			stats.move_speed_percent += total
		TalentDef.Effect.DASH_COOLDOWN_REDUCTION:
			stats.dash_cooldown_reduction += total
		TalentDef.Effect.ATTACK_RATE_PERCENT, TalentDef.Effect.DAMAGE_PERCENT:
			stats.add_weapon_entry(talent, total)
		TalentDef.Effect.EVASION_DAMAGE_PERCENT:
			stats.evasion_damage_percent += total
		TalentDef.Effect.DASH_CHARGES:
			stats.dash_charges += roundi(total)
		TalentDef.Effect.WIND_RUNNER:
			stats.wind_runner = true
		TalentDef.Effect.MAX_HEALTH:
			stats.max_health_bonus += total
		TalentDef.Effect.STAGGER_REDUCTION:
			stats.stagger_reduction += total
		TalentDef.Effect.BREAKER_DAMAGE_PERCENT:
			stats.breaker_damage_percent += total
		TalentDef.Effect.SECOND_HEART:
			stats.second_heart = true
		TalentDef.Effect.EMBER_HEART:
			stats.ember_heart = true
		TalentDef.Effect.SPELL_DAMAGE_PERCENT:
			stats.spell_damage_percent += total
		TalentDef.Effect.SPELL_COOLDOWN_PERCENT:
			stats.spell_cooldown_percent += total
		TalentDef.Effect.UNLOCK_SPELL, TalentDef.Effect.SPELL_SLOTS:
			pass # read from the state (unlocked spells, slots)


## Move speed with talents (Leichtfuß, additive percent).
static func move_speed(base_speed: float, stats: TalentStats) -> float:
	return base_speed * (1.0 + stats.move_speed_percent)


## Dash cooldown with talents (Dash-Training), never below MIN_DASH_COOLDOWN.
static func dash_cooldown(base_cooldown: float, stats: TalentStats) -> float:
	if stats.dash_cooldown_reduction <= 0.0:
		return base_cooldown
	return maxf(MIN_DASH_COOLDOWN, base_cooldown - stats.dash_cooldown_reduction)


## Champions and shield bearers (Schildbrecher); the enemy decides (Enemy.is_shield_breaker_target).
## Asked by method, not by the Enemy type: that reference made a load cycle with gold_pickup.tscn.
static func is_breaker_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return target.has_method(&"is_shield_breaker_target") and bool(target.call(&"is_shield_breaker_target"))


# --- Putting talents on a player ---

## Gives player this distribution for the run: max HP, move speed, dash cooldown and charges now,
## everything else through the hooks below. Call once per spawned dungeon player, for every player
## the host runs (D-088); a second call replaces the first (the old values are taken back).
static func apply_to(player: Player, state: TalentState, tree: TalentTree = null) -> PlayerTalents:
	if player == null:
		return null
	var talents := PlayerTalents.of(player)
	if talents == null:
		talents = PlayerTalents.new()
		talents.name = PlayerTalents.NODE_NAME
		talents.set_distribution(state, tree)
		player.add_child(talents)
	else:
		talents.set_distribution(state, tree)
	return talents


## Talent numbers of owner (a Player or anything below it); neutral without talents.
static func stats_of(owner: Node) -> TalentStats:
	var talents := PlayerTalents.of(owner)
	return talents.stats if talents != null else TalentStats.new()


# --- Hooks (ask with the attacking or hit player) ---

## Additive damage percent of the talents for an attack with these weapon tags. Add to the
## DAMAGE_PERCENT sum next to the forge bonus (WeaponController.get_effective_damage).
static func damage_bonus(owner: Node, weapon_tags: Array[StringName]) -> float:
	return stats_of(owner).damage_percent(weapon_tags)


## Additive attack-rate percent (WeaponController.get_effective_attack_rate).
static func attack_rate_bonus(owner: Node, weapon_tags: Array[StringName]) -> float:
	return stats_of(owner).attack_rate_percent(weapon_tags)


## Situational damage factor of the attacker right now (Ausweichkunst after a dash), D-019: multiply
## into the context multiplier of the attack.
static func attack_multiplier(owner: Node) -> float:
	var talents := PlayerTalents.of(owner)
	return talents.get_attack_multiplier() if talents != null else 1.0


## Situational damage factor of a hit by source on target (Schildbrecher): multiply the damage before
## it is processed (Hurtbox.receive_hit of the target).
static func target_multiplier(source: Node, target: Node) -> float:
	if source == null or not is_instance_valid(source):
		return 1.0
	var bonus := stats_of(source).breaker_damage_percent
	if bonus <= 0.0 or not is_breaker_target(target):
		return 1.0
	return 1.0 + bonus


## Factor for knockback and stun the player receives (Standfest).
static func stagger_multiplier(player: Node) -> float:
	return stats_of(player).stagger_multiplier()


## Revive speed factor of a downed player in a group game (Zweites Herz: twice as fast).
static func revive_speed(player: Node) -> float:
	return SECOND_HEART_REVIVE_SPEED if stats_of(player).second_heart else 1.0


## Additive spell damage percent (KE7: next to the run multipliers).
static func spell_damage_bonus(owner: Node) -> float:
	return stats_of(owner).spell_damage_percent


## Factor for spell cooldowns (KE7).
static func spell_cooldown_multiplier(owner: Node) -> float:
	return stats_of(owner).spell_cooldown_multiplier()
