class_name EnemyData
extends Resource
## Static enemy definition (.tres). Numbers are TESTWERTE (D-064); behaviour is data-driven:
## a basic attack (MELEE/RANGED) plus optional volley, special attack and summons. Bosses (and
## champions) have a second phase below half health (BossRules), configured in "Phase two".

enum AttackKind { MELEE, RANGED }
enum Special { NONE, SHIELD_CHARGE, LEAP_SLAM, TELEPORT, SELF_DESTRUCT, ERUPTION }

@export var id: StringName
@export var display_name := ""
@export var attack_kind := AttackKind.MELEE
@export var tags: Array[StringName] = []
@export var is_boss := false
## Earliest room in which this type may spawn as a normal enemy (gentle start, D-074).
@export var min_room := 1
## Short hint shown the first time the player meets this enemy.
@export_multiline var hint := ""

@export_group("Stats (TESTWERTE)")
@export var max_health := 20.0
@export var damage := 1.0
@export var move_speed := 60.0
## 0 = full knockback, 1 = immune.
@export_range(0.0, 1.0) var knockback_resistance := 0.0
## Base gold drop before room scaling.
@export var gold_drop := 2

@export_group("Attack")
## Distance to the target at which the telegraph starts.
@export var attack_range := 34.0
## Melee: distance from the enemy centre to the attack hitbox centre.
@export var attack_reach := 22.0
## Melee: radius of the attack hitbox.
@export var attack_radius := 18.0
## Visible warning before the attack lands (D-021).
@export var telegraph_time := 0.6
## Melee: how long the attack hitbox is active.
@export var attack_active_time := 0.15
@export var attack_cooldown := 1.2
@export var knockback_strength := 0.0

@export_group("Ranged")
## Ranged enemies back off while closer than this ...
@export var preferred_min_distance := 0.0
## ... for at most this long before they shoot anyway.
@export var reposition_time := 1.0
@export var projectile_speed := 0.0
@export var projectile_radius := 4.0
@export var projectile_texture: Texture2D
@export var projectile_frame_size := Vector2i(16, 5)
@export var projectile_pivot := Vector2(8, 2)
## Projectiles per ranged attack (spread).
@export var projectile_count := 1

@export_group("Radial volley")
## Every n-th attack is a ring of projectiles instead (0 = never).
@export var volley_every := 0
@export var volley_count := 10
@export var volley_range := 420.0

@export_group("Special attack")
@export var special := Special.NONE
## Every n-th attack is the special (0 = never, 1 = always).
@export var special_every := 0
@export var special_telegraph_time := 0.9
@export var charge_speed := 430.0
@export var charge_time := 0.4
## Leap slam / self destruct / eruption radius.
@export var blast_radius := 80.0
## ERUPTION: delayed blasts around the target (the first one exactly on it).
@export var eruption_count := 3

@export_group("Summon")
@export var summon_data: EnemyData
## Every n-th attack summons instead (0 = never).
@export var summon_every := 0
@export var summon_count := 2

@export_group("Phase two (bosses and champions)")
## Extra specials chained right after the first one in phase two (charge again, jump again ...).
@export var enrage_special_repeats := 1
## Volleys come as a rotating spiral of several rings in phase two.
@export var enrage_spiral := false
## Projectile ring on every leap landing in phase two (0 = none).
@export var enrage_landing_ring := 0
## Delayed eruptions around the player after every special in phase two (0 = none).
@export var enrage_eruptions := 0
## Minion summoned in phase two instead of summon_data (or at all, if there is none).
@export var enrage_summon: EnemyData
## Subtitle of the phase-two banner.
@export var enrage_text := ""

@export_group("Lava balls (against kiting, BossPressure)")
## Seconds between lobbed lava balls right after the players left the boss's melee reach
## (BossPressure.NEAR_DISTANCE); 0 = no lava balls ...
@export var lob_interval := 0.0
## ... shrinking to this while nobody came near for lob_ramp_time seconds.
@export var lob_interval_min := 2.0
@export var lob_ramp_time := 10.0
## Balls per throw (more with the boss tier and in phase two).
@export var lob_count := 3
@export var enrage_lob_count := 2
## Wind-up before the throw; the landing circles then warn for lob_flight_time seconds.
@export var lob_windup := 0.5
@export var lob_flight_time := 1.0
## Impact circle radius and distance of the extra balls from the first one.
@export var lob_radius := 44.0
@export var lob_spread := 85.0
## Share of the boss hit per ball.
@export var lob_damage_factor := 0.8
## Seconds the lava pool burns after the impact (phase one, phase two); 0 = no pool.
@export var lob_pool_time := 2.5
@export var enrage_lob_pool_time := 3.5

@export_group("Stomp (against crowding, BossPressure)")
## Radius of the stunning ground wave around the boss; 0 = no stomp. Only used while a player
## stands inside it.
@export var stomp_radius := 0.0
@export var stomp_cooldown := 6.0
@export var stomp_telegraph_time := 0.7
## Share of the boss hit.
@export var stomp_damage_factor := 0.5
## Stun of the stomp in phase one and two (never above BossPressure.MAX_STUN).
@export var stomp_stun := 0.4
@export var enrage_stomp_stun := 0.5

@export_group("On death")
## Enemies that spawn when this one dies (splitting slime).
@export var death_spawn: EnemyData
@export var death_spawn_count := 0

@export_group("Status effects on the player")
## Stun of the special charge (D-066).
@export var stun_duration := 0.0
## Blind on every effective hit (D-067).
@export var blind_duration := 0.0

@export_group("Boss intro")
## First encounter per save (BossIntro story intro): 4-7 short German lines in which the boss tells
## who it was and what the darkness, the souls and the player's light are about. All lines are
## shown, one after the other. Empty = every encounter uses intro_lines.
@export var intro_story: PackedStringArray = []
## Later encounters (short intro): threatening German variants, no rules or numbers. One variant
## per intro, chosen by boss tier and run count (deterministic, BossIntroRules.repeat_lines); a "|"
## splits a variant into two dialog lines (at most BossIntroRules.MAX_REPEAT_LINES).
## Only the voice is babble (see intro_voice). Empty (and no story) = no intro.
@export var intro_lines: PackedStringArray = []
## Typing speed factor (1 = BossIntroRules.CHAR_INTERVAL per letter, below 1 = slower, heavier).
@export_range(0.3, 2.0) var intro_type_speed := 1.0
## Babble voice: one meaningless syllable sound per spoken syllable, in sync with the typed text,
## from audio/sfx/babble_<voice>_<1..n>.wav (empty = silent).
@export var intro_voice: StringName = &""
## Number of babble files of the voice (n above).
@export var intro_voice_variants := 6
@export var intro_voice_db := -3.0
## Name, eyebrow and vignette colour of the intro dialog.
@export var intro_color := Color(0.95, 0.4, 1.0)
## Trembling text (RichTextLabel shake level, 0 = none) and wavering (wave amplitude, 0 = none).
@export var intro_shake := 4.0
@export var intro_wave := 0.0

@export_group("Visuals")
@export var sprite_frames: SpriteFrames
## Body centre inside a sprite frame; this point sits on the node origin.
@export var sprite_origin := Vector2(16, 22)
## Frame of the "attack" animation on which the hit lands; earlier frames are the telegraph.
@export var strike_frame := 2
@export var sprite_scale := 1.0
@export var tint := Color.WHITE
## Transparency while not attacking (shadows phase in and out).
@export_range(0.05, 1.0) var idle_alpha := 1.0
@export var body_radius := 12.0
@export var placeholder_color := Color.WHITE
## Own light in the darkness (0 = none). Bosses glow.
@export var light_radius := 0.0
