class_name ChampionRules
extends RefCounted
## Champions (miniboss rooms, D-077) are a standard enemy type turned into a small boss: on top of
## the miniboss scaling and an elite trait they get a type-specific special, a faster rhythm and a
## second phase (BossRules). Pure: returns a modified copy, the shared .tres stays untouched.

const COOLDOWN_FACTOR := 0.8
const MIN_KNOCKBACK_RESISTANCE := 0.6
const LEAP_BLAST_RADIUS := 72.0
const BOMB_BLAST_RADIUS := 58.0


static func make_champion_data(base: EnemyData) -> EnemyData:
	var data := base.duplicate() as EnemyData
	data.attack_cooldown *= COOLDOWN_FACTOR
	data.knockback_resistance = maxf(data.knockback_resistance, MIN_KNOCKBACK_RESISTANCE)
	data.enrage_special_repeats = 1
	match base.special:
		EnemyData.Special.SHIELD_CHARGE:
			# Skeleton: charges twice as often, chains a second charge when enraged.
			data.special_every = 2
		EnemyData.Special.LEAP_SLAM:
			# Golem: jumps more often, the landing throws a ring of debris when enraged.
			data.special_every = 2
			data.enrage_landing_ring = 8
		EnemyData.Special.TELEPORT:
			data.special_every = 2
		EnemyData.Special.SELF_DESTRUCT:
			# A champion bomber would blow itself up at once: it throws bombs instead.
			data.special = EnemyData.Special.ERUPTION
			data.special_every = 2
			data.special_telegraph_time = 0.7
			data.eruption_count = 3
			data.blast_radius = BOMB_BLAST_RADIUS
		EnemyData.Special.ERUPTION:
			data.special_every = 2
			data.eruption_count += 1
		_:
			_add_special(data, base)
	if base.summon_data != null:
		data.summon_count += 1
	if base.death_spawn != null:
		data.death_spawn_count += 2
	return data


static func _add_special(data: EnemyData, base: EnemyData) -> void:
	if base.attack_kind == EnemyData.AttackKind.RANGED:
		# Archer, necromancer: wider spreads and a ring volley that becomes a spiral when enraged.
		data.projectile_count = base.projectile_count + 2
		data.volley_every = 3
		data.volley_count = 12
		data.volley_range = maxf(base.volley_range, base.attack_range + 60.0)
		data.enrage_spiral = true
	elif base.blind_duration > 0.0:
		# Shadow: blinks next to the player and throws blinding orbs.
		data.special = EnemyData.Special.TELEPORT
		data.special_every = 3
		data.special_telegraph_time = 0.6
	else:
		# Slimes and other brawlers: a telegraphed leap slam.
		data.special = EnemyData.Special.LEAP_SLAM
		data.special_every = 3
		data.special_telegraph_time = 0.9
		data.blast_radius = LEAP_BLAST_RADIUS
		data.enrage_landing_ring = 6
