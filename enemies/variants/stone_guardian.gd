class_name StoneGuardian
extends Enemy
## Stone guardian of "Lichtfeuer" (KONZEPT_RAEUME_V2 §3.9; before the variant "Steinwächter", A9): a
## knight statue that only moves outside every light circle. In the light (LightQuery: the fires,
## crystals, torches; the players' own circles only if player_light_counts) it freezes - eyes out, a
## puff of stone dust - and takes damage; in
## the dark it is stone (invulnerable), its eyes glow and it advances. Its only attack is a leap
## slam with the usual yellow circle on the target (EnemyData LEAP_SLAM, D-021): from the edge of a
## light circle it jumps in, lands in the light and freezes there - that is the moment to strike.
## A started leap or strike is finished even if it ends in the light (readable, never cut halfway).
## As an Enemy it counts for the room like any other enemy.
## Decision per frame in LightfireRules.guardian_frozen; this class only applies it.
## Before the fight it stands as a dormant statue (active = false, set by the mode).

signal froze(guardian: StoneGuardian)
signal thawed(guardian: StoneGuardian)

const DARK_INVULNERABILITY := &"stone_dark"
const DORMANT_INVULNERABILITY := &"stone_dormant"
const DUST_COLOR := Color(0.72, 0.7, 0.78)
const EYE_LIGHT_RADIUS := 36.0
const EYE_LIGHT_HEIGHT := -34.0
## Feedback on a hit that bounces off the stone, at most this often.
const CLANK_INTERVAL := 0.2

## Statue until the fight starts (the mode calls activate()).
var active := false
## Do the players' own light circles hold it (LightQuery include_players)? Lichtfeuer: only the fires
## (LightfireRules.PLAYER_LIGHT_HOLDS_GUARDIANS).
var player_light_counts := true
var frozen := true

var _dark_time := 0.0
var _clank_cooldown := 0.0
var _eyes: LightSource = null

static var _frames: SpriteFrames = null


func _ready() -> void:
	# The frames are 32x48 (feet at y 46); stone_guardian.tres sets sprite_origin (16, 30), so the
	# base class's 32x32 placement puts the body centre 8 art px above the feet like every enemy.
	if data != null and data.sprite_frames == null and EnemyArt.get_art(data) == null:
		# Art of the variant folder (SPRITES_V5 §3); a copy, the shared .tres stays untouched.
		data = data.duplicate() as EnemyData
		data.sprite_frames = get_frames()
	super._ready()
	if data == null:
		return
	hurtbox.set_invulnerable(DORMANT_INVULNERABILITY, not active)
	var stone_hurtbox := hurtbox as StoneGuardianHurtbox
	if stone_hurtbox != null:
		stone_hurtbox.deflected.connect(_on_deflected)
	_eyes = LightSource.new()
	_eyes.name = "Eyes"
	_eyes.radius = EYE_LIGHT_RADIUS
	_eyes.intensity = 0.7
	_eyes.flicker = 0.05
	_eyes.position = Vector2(0.0, EYE_LIGHT_HEIGHT)
	add_child(_eyes)
	_show_frozen(true)


## Frames shared by every guardian (idle, walk, attack, frozen).
static func get_frames() -> SpriteFrames:
	if _frames == null:
		_frames = VariantArt.make_stone_guardian_frames()
	return _frames


## The fight began: from now on the light decides.
func activate() -> void:
	active = true
	if is_node_ready():
		hurtbox.set_invulnerable(DORMANT_INVULNERABILITY, false)
		# Starts as a frozen statue; the dark wakes it after the thaw delay.
		_dark_time = 0.0
		_apply_frozen(true, true)


func is_frozen() -> bool:
	return frozen


## The shared light decision at the guardian's feet.
func is_in_light() -> bool:
	if not is_inside_tree():
		return false
	return LightQuery.is_lit(get_tree(), global_position, player_light_counts)


func _physics_process(delta: float) -> void:
	if is_dead():
		return
	_clank_cooldown = maxf(0.0, _clank_cooldown - delta)
	if not active:
		velocity = Vector2.ZERO
		return
	step_light(delta, is_in_light())
	if frozen:
		velocity = Vector2.ZERO
		return
	super._physics_process(delta)


## One light step (public for tests): lit or not this frame. A started leap or strike goes on.
func step_light(delta: float, lit: bool) -> void:
	_dark_time = 0.0 if lit else _dark_time + delta
	if _is_committed():
		return
	_apply_frozen(LightfireRules.guardian_frozen(lit, frozen, _dark_time))


## The guardian is a light puzzle with its own rules: no ring places or packs (EnemyPack).
func uses_tactics() -> bool:
	return false


func _is_committed() -> bool:
	return _state in [State.LEAP, State.ATTACK, State.CHARGE]


func _apply_frozen(value: bool, force := false) -> void:
	if value == frozen and not force:
		return
	frozen = value
	hurtbox.set_invulnerable(DARK_INVULNERABILITY, not LightfireRules.guardian_vulnerable(value))
	if value:
		# A wind-up in the dark is cut off by the light: no strike comes.
		_attack_hitbox.end_attack()
		if _state != State.DEAD:
			_enter_state(State.IDLE)
		velocity = Vector2.ZERO
		_show_frozen(true)
		if is_inside_tree() and not force:
			Burst.spawn(get_parent(), global_position + Vector2(0.0, -20.0), DUST_COLOR, 8, 60.0, 0.5, 3.0)
		froze.emit(self)
	else:
		_show_frozen(false)
		if is_inside_tree() and not force:
			Sfx.play_at(self, &"slam", global_position, -18.0)
		thawed.emit(self)


## Look: frozen sprite and dark eyes, or the glowing eyes of a moving statue.
func _show_frozen(value: bool) -> void:
	if _eyes != null:
		_eyes.visible = not value and active
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var animation := &"frozen" if value else &"idle"
	if _sprite.sprite_frames.has_animation(animation):
		_sprite.speed_scale = 1.0
		_sprite.play(animation)


## A hit bounced off the stone: spark and a dull clank, so the player sees why nothing happened.
func _on_deflected(_damage: DamageData) -> void:
	if _clank_cooldown > 0.0 or not is_inside_tree():
		return
	_clank_cooldown = CLANK_INTERVAL
	Burst.spawn(get_parent(), global_position + Vector2(0.0, -16.0), DUST_COLOR.lightened(0.2), 5, 90.0, 0.25, 2.0)
	SpriteFx.flash(_sprite, Color(0.8, 0.8, 0.9), 0.08)
	Sfx.play_at(self, &"hit_enemy", global_position, -10.0)
