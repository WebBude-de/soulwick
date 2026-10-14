class_name WeaponData
extends Resource
## Static weapon definition (.tres). Runtime state lives in WeaponController.
## Numeric values are TESTWERTE from DECISIONS §4.

## Attack behaviour. DAGGER and HAMMER are post-MVP additions; append new types at the end only,
## the .tres files store the index.
enum WeaponType { SWORD, BOW, STAFF, DAGGER, HAMMER }
## Prepared for later; has no gameplay effect in the MVP (D-035).
enum Rarity { COMMON, UNCOMMON, RARE }

@export var id: StringName
@export var display_name := ""
@export var weapon_type := WeaponType.SWORD
## Used by upgrade applicability (OR match, D-028).
@export var tags: Array[StringName] = []
@export var rarity := Rarity.COMMON

@export_group("Stats")
@export var base_damage := 0.0
## Attacks per second, not a delay (D-025).
@export var attack_rate := 1.0
## Swing weapons: swing radius. Hammer: distance of the slam centre. Projectiles: max travel distance.
@export var attack_range := 0.0
@export var projectile_speed := 0.0
@export var swing_angle_degrees := 0.0
## Staff: radius of the single primary AOE hit (D-024). Hammer: radius of the ground slam.
@export var aoe_radius := 0.0
## PLATZHALTER: not specified in the GDD.
@export var knockback_strength := 120.0
@export var projectile_radius := 4.0
## Hammer: delay between button press and the slam landing (wind-up).
@export var windup_time := 0.0
## Dagger: damage multiplier for hits from behind or right after a dash (1 = off).
@export var backstab_multiplier := 1.0

@export_group("Combo (TESTWERTE)")
## Every combo_length-th consecutive swing is a heavier finisher (0 = no combo).
@export var combo_length := 0
@export var combo_damage_multiplier := 1.0
@export var combo_angle_multiplier := 1.0
@export var combo_range_multiplier := 1.0
@export var combo_knockback_multiplier := 1.0

@export_group("Special (TESTWERTE)")
## Right mouse button ability. The behaviour is chosen by weapon_type.
@export var special_name := ""
@export_multiline var special_description := ""
@export var special_cooldown := 5.0
## Situational multiplier on the effective damage (D-019: multiplies).
@export var special_damage_multiplier := 1.0
@export var special_knockback_multiplier := 1.0

@export_group("Visuals")
## Held weapon, pointing right; sprite_pivot (grip) sits in the player's hand.
@export var sprite: Texture2D
@export var sprite_pivot := Vector2(16, 16)
## Placeholder recolouring/scaling until dedicated art exists (applied to sprite and icon).
@export var tint := Color.WHITE
@export var sprite_scale := 1.0
@export var icon: Texture2D
@export var projectile_texture: Texture2D
@export var projectile_frame_size := Vector2i(16, 16)
@export var projectile_pivot := Vector2(8, 8)
@export var projectile_fps := 10.0
@export var projectile_color := Color.WHITE
## Colour of swing/slam/special effects.
@export var effect_color := Color.WHITE


func is_melee() -> bool:
	return weapon_type == WeaponType.SWORD or weapon_type == WeaponType.DAGGER or weapon_type == WeaponType.HAMMER


## Sword and dagger attack with a swing arc; the hammer slams an area instead.
func uses_swing() -> bool:
	return weapon_type == WeaponType.SWORD or weapon_type == WeaponType.DAGGER
