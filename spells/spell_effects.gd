class_name SpellEffects
extends RefCounted
## What a spell does (KE7, KONZEPT §6.2): its numbers for one caster and the effect itself.
## - damage(): base damage with the same run multipliers as a weapon (D-019: flat and percent
##   upgrades that apply to the tag "spell", the forge bonus, Zauberkraft added to the percent sum,
##   the situational talent factor multiplied in). Weapon-only upgrades (melee, arrow, magic) do not
##   count: a spell is no weapon.
## - cooldown(): base cooldown times Konzentration (TalentEffects.spell_cooldown_multiplier).
## - loadout_of(): the spells a player can cast, slot by slot.
## - apply(): the effect, computed at the caster (body centre); called only where the game is
##   decided (offline or on the host, PlayerSpells). Looks are SpellLook's; the visible origin is
##   Flint's flame (cast_origin), the reach is measured from the player.
## Spell hits are SECONDARY (like the Glutwelle): no "Explosiver Treffer" chains (D-030), kills
## still give on-kill rewards (D-032).

## Tag every spell hit carries (upgrades may name it in applicable_tags), next to the spell id.
const SPELL_TAG: StringName = &"spell"
const SPELL_TAGS: Array[StringName] = [SPELL_TAG]
const ENEMY_GROUP: StringName = &"enemies"
const PLAYER_GROUP: StringName = &"player"


# --- Numbers ---

## Damage of one spell hit of caster (a Player or a node below it) for base_amount.
static func damage(caster: Node, base_amount: float) -> float:
	var upgrades := _upgrades_of(caster)
	var flat := upgrades.get_modifier(UpgradeData.Effect.DAMAGE_FLAT, SPELL_TAGS) if upgrades != null else 0.0
	var percent := upgrades.get_modifier(UpgradeData.Effect.DAMAGE_PERCENT, SPELL_TAGS) if upgrades != null else 0.0
	percent += _forge_bonus(caster) + TalentEffects.spell_damage_bonus(caster)
	return StatCalculator.compute_raw_damage(base_amount, flat, percent, TalentEffects.attack_multiplier(caster))


## Cooldown of data for caster in seconds (Konzentration shortens it).
static func cooldown(caster: Node, data: SpellData) -> float:
	if data == null:
		return 0.0
	return data.cooldown * TalentEffects.spell_cooldown_multiplier(caster)


## Spells of a talent distribution, slot by slot: the equipped ones; while none is equipped (no
## altar visit yet, KE8) the unlocked ones in catalog order, as many as there are slots.
static func loadout_of(stats: TalentStats) -> Array[StringName]:
	var result: Array[StringName] = []
	if stats == null or stats.spell_slots <= 0:
		return result
	var source := stats.equipped_spells if not stats.equipped_spells.is_empty() else stats.unlocked_spells
	for spell in source:
		if result.size() >= stats.spell_slots:
			break
		if SpellBook.has_spell(spell) and not result.has(spell):
			result.append(spell)
	return result


## Where a spell visibly starts: the flame of the caster's Flint (D-194, KONZEPT §6.2), else the
## caster's body centre. Flint's spot follows only synced state, so every machine gets the same point.
static func cast_origin(caster: Node2D) -> Vector2:
	var flint := FlintCompanion.of(caster)
	if flint != null:
		return flint.get_light_center()
	return caster.global_position


# --- The effect ---

## Casts data for caster towards aim (normalised). Returns what it touched: blinded enemies, hit
## hurtboxes' results, healed players, the shield gain or the launched wisps (tests, tools).
## Must run in a physics frame outside collision callbacks (area queries).
static func apply(caster: Player, data: SpellData, aim: Vector2) -> Array:
	if caster == null or data == null or not caster.is_inside_tree():
		return []
	match data.effect:
		SpellData.Effect.BLIND_AREA:
			return blind_enemies(caster, caster.global_position, data.radius, data.duration)
		SpellData.Effect.SHIELD:
			return [caster.shield.add_shield(data.amount)]
		SpellData.Effect.DAMAGE_AREA:
			var hit := make_hit(caster, data, damage(caster, data.amount))
			return AreaDamage.apply(caster, caster.global_position, data.radius, PhysicsLayers.ENEMY_HURTBOX, hit, data.knockback)
		SpellData.Effect.HOMING_LIGHTS:
			return WillOWisp.launch_all(caster, data, cast_origin(caster), aim, damage(caster, data.amount), true)
		SpellData.Effect.HEAL_AREA:
			return heal_players(caster, data.amount, data.radius)
	return []


## Enemies whose body is within radius of center: no attacks for duration seconds. Uses the
## enemy's own blind (Enemy.apply_blind, enemies-dev hook) and until it exists holds it in place
## (apply_slow to zero) as a stand-in.
static func blind_enemies(context: Node, center: Vector2, radius: float, duration: float) -> Array:
	var blinded: Array = []
	for enemy in enemies_within(context, center, radius):
		blind_enemy(enemy, duration)
		blinded.append(enemy)
	return blinded


static func blind_enemy(enemy: Enemy, duration: float) -> void:
	if enemy.has_method(&"apply_blind"):
		enemy.call(&"apply_blind", duration)
	else:
		enemy.apply_slow(0.0, duration)


## Living, visible enemies whose hurtbox (else origin) lies within radius of center.
static func enemies_within(context: Node, center: Vector2, radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	if context == null or not context.is_inside_tree():
		return result
	for node in context.get_tree().get_nodes_in_group(ENEMY_GROUP):
		var enemy := node as Enemy
		if enemy == null or not is_valid_target(enemy):
			continue
		if body_center(enemy).distance_to(center) <= radius:
			result.append(enemy)
	return result


## Alive, out of its spawn source and in the tree.
static func is_valid_target(enemy: Enemy) -> bool:
	return is_instance_valid(enemy) and enemy.is_inside_tree() and not enemy.is_queued_for_deletion() \
		and not enemy.is_dead() and not enemy.is_hidden_in_source()


## Where spells aim at an enemy: its hurtbox, else its origin.
static func body_center(enemy: Enemy) -> Vector2:
	if enemy.hurtbox != null and is_instance_valid(enemy.hurtbox):
		return enemy.hurtbox.global_position
	return enemy.global_position


## Heals the caster and every other standing player within radius of the caster (downed players
## need a revive instead). Returns the healed players.
static func heal_players(caster: Player, amount: float, radius: float) -> Array:
	var healed: Array = []
	for player in players_within(caster, radius):
		if player.health.heal(amount) > 0.0:
			healed.append(player)
	return healed


## The caster and every standing player whose body centre is within radius of the caster.
static func players_within(caster: Player, radius: float) -> Array[Player]:
	var result: Array[Player] = []
	if caster.is_alive():
		result.append(caster)
	if not caster.is_inside_tree():
		return result
	for node in caster.get_tree().get_nodes_in_group(PLAYER_GROUP):
		var player := node as Player
		if player == null or player == caster or not player.is_alive():
			continue
		if player.global_position.distance_to(caster.global_position) <= radius:
			result.append(player)
	return result


## The hit of a spell (one attack instance: one hit id).
static func make_hit(caster: Node, data: SpellData, amount: float) -> DamageData:
	var hit := DamageData.new()
	hit.amount = amount
	hit.source = caster
	hit.origin = DamageData.Origin.SECONDARY
	hit.tags.assign([SPELL_TAG, data.id])
	hit.hit_id = DamageData.next_hit_id()
	return hit


static func _upgrades_of(caster: Node) -> UpgradeManager:
	var player := _player_of(caster)
	if player == null or player.weapon_controller == null:
		return null
	return player.weapon_controller.upgrades


## The forge's damage bonus of this run, exactly as the weapons get it.
static func _forge_bonus(caster: Node) -> float:
	var player := _player_of(caster)
	if player == null or player.weapon_controller == null:
		return 0.0
	return player.weapon_controller.get_meta_damage_bonus()


static func _player_of(node: Node) -> Player:
	var current := node
	while current != null and is_instance_valid(current):
		if current is Player:
			return current as Player
		current = current.get_parent()
	return null
