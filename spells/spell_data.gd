class_name SpellData
extends Resource
## One spell (KE7, KONZEPT §6.2, D-194): what it does and its numbers. The five spells live in
## spells/data/<id>.tres (SpellBook); the ids are the ones the talent tree unlocks (TalentDef.spell).
## Numbers are TESTWERTE; damage grows with the run multipliers (SpellEffects.damage), cooldowns
## shrink with Konzentration (SpellEffects.cooldown). Texts: SPELL_<ID> and SPELL_<ID>_DESC (D-111).

## What casting does (SpellEffects.apply); the look follows the same kind (SpellLook).
enum Effect {
	## Enemies within radius cannot attack for duration seconds (Lichtblitz).
	BLIND_AREA,
	## amount shield on the caster (Seelenschild), through ShieldComponent (softcap, D-014/D-074).
	SHIELD,
	## amount damage to enemies within radius, pushed away with knockback (Flammenring).
	DAMAGE_AREA,
	## count homing lights of amount damage each (Irrlichter, WillOWisp).
	HOMING_LIGHTS,
	## amount HP for the caster and living players within radius (Heilfunke).
	HEAL_AREA,
}

## px per tile (same as RoomTiles.TILE_WORLD; kept here so the data class loads nothing else).
const TILE_WORLD := 64.0

@export var id: StringName = &""
@export var effect := Effect.BLIND_AREA
## Seconds until the spell can be cast again (before Konzentration).
@export var cooldown := 10.0
## Damage per hit (before the run multipliers), shield or HP, depending on effect.
@export var amount := 0.0
## Reach in px from the caster's body centre (TILE_WORLD px per tile).
@export var radius := 0.0
## Blind time in seconds (BLIND_AREA).
@export var duration := 0.0
## Number of lights (HOMING_LIGHTS).
@export var count := 1
## Push of a damage hit in px/s (DAMAGE_AREA).
@export var knockback := 0.0
## Looks only: tint of placeholders, sparks and the light flash, and the sound (audio/sfx/<name>.wav).
@export var color := Color.WHITE
@export var sound: StringName = &""


## Radius in tiles (texts).
func get_radius_tiles() -> float:
	return radius / TILE_WORLD
