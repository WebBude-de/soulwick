class_name SummoningRift
extends Enemy
## Rift of "Risse schließen" (RAEUME §3.7; before the variant "Beschwörungsrisse"): stands
## still, has health and a bar. In a plan room it sits in a wall rift of the room's sources and the
## mode sends the enemies through that source (pulse() shows the summon); elsewhere it calls one enemy
## every RiftRules.PUSH_INTERVAL seconds itself while the room allows it (fewer than
## RiftRules.MAX_ALIVE living enemies). A closed (killed) rift stops. As an Enemy
## it counts for the room like any other enemy, and its minions arrive through the summoned signal,
## so the room is done when all rifts and all enemies are gone.
## Readable: before every summon the rift glows and a green circle marks the spot for RIFT_WIND_UP s.
## The rift decides when to summon; who comes is decided by the variant (summoner callable).

const SUMMON_COLOR := Color(0.45, 1.0, 0.8, 0.35)
## The new enemy appears this far in front (south) of the rift.
const SUMMON_OFFSET := Vector2(0.0, 56.0)
const RIFT_FRAME := Vector2i(32, 48)
## Body centre in frame pixels: the rift's base (pivot y 46) sits 8 art px below the origin, like the
## feet of every enemy.
const RIFT_ORIGIN := Vector2(16, 38)
## In a wall: the 48 px art as tall as the brick front (64 px) and lifted into it.
const WALL_ART_SCALE := 2.0 / 3.0
const WALL_ART_RAISE := 26.0

## Checks whether a summon may start now: func(rift: SummoningRift) -> bool.
var may_summon: Callable
## Spawns the enemies of one summon at a global position: func(rift, spot: Vector2) -> Array[Enemy].
var summoner: Callable
## Colour of the (biome-neutral) rift art, set before the rift enters the tree.
var rift_color := Color.WHITE
## The rift only works once the fight started (set by the variant).
var active := false
## Sits in a wall rift of the room (Risse schließen in its plan): the art is drawn smaller and higher,
## inside the brick front, while body and hurtbox stay at the floor edge where they can be hit.
var in_wall := false

var _cooldown := RiftRules.FIRST_DELAY
var _wind_up_left := -1.0
var _summon_spot := Vector2.ZERO


func _ready() -> void:
	super._ready()
	if data == null:
		return
	_sprite.sprite_frames = VariantArt.make_rift_frames()
	_sprite.offset = SpriteStrip.pivot_offset(RIFT_FRAME, RIFT_ORIGIN)
	_sprite.modulate = rift_color
	_sprite.play(&"idle")
	# The bar above the tall rift, not in its middle.
	_health_bar.position.y = -RIFT_FRAME.y * SpriteStrip.PIXEL_SCALE + 8.0
	if in_wall:
		_sprite.scale *= WALL_ART_SCALE
		_sprite.position.y -= WALL_ART_RAISE


## Starts the summon timer; first_delay staggers several rifts.
func activate(first_delay: float) -> void:
	active = true
	_cooldown = first_delay


func is_winding_up() -> bool:
	return _wind_up_left >= 0.0


func get_summon_spot() -> Vector2:
	var spot := global_position + SUMMON_OFFSET
	return get_navigation().snap_to_navigation(spot) if get_navigation() != null else spot


## Seconds until the next summon may start (for tests and tools).
func get_cooldown() -> float:
	return _cooldown


func _physics_process(delta: float) -> void:
	if is_dead() or not active:
		return
	step(delta)


## One step of the summon cycle (public for tests): cooldown -> wind-up -> summon.
func step(delta: float) -> void:
	if is_dead():
		return
	if _wind_up_left >= 0.0:
		_wind_up_left -= delta
		if _wind_up_left < 0.0:
			_finish_summon()
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if may_summon.is_valid() and not bool(may_summon.call(self)):
		# Room full: check again a moment later.
		_cooldown = 0.5
		return
	_begin_summon()


func _begin_summon() -> void:
	_wind_up_left = RiftRules.WIND_UP
	_summon_spot = get_summon_spot()
	_telegraph_circle.global_position = _summon_spot
	_telegraph_circle.radius = 22.0
	_telegraph_circle.color = SUMMON_COLOR
	_telegraph_circle.visible = true
	SpriteFx.flash(_sprite, Color(0.6, 1.0, 0.9), RiftRules.WIND_UP)
	Sfx.play_at(self, &"rift_summon", global_position, -8.0)


## The summon look without the rift's own timer (the mode sends the enemy through a wall source).
func pulse() -> void:
	if is_dead() or _sprite == null:
		return
	SpriteFx.flash(_sprite, Color(0.6, 1.0, 0.9), RiftRules.WIND_UP)
	Sfx.play_at(self, &"rift_summon", global_position, -8.0)
	ability_used.emit(self, &"summon")


func _finish_summon() -> void:
	_wind_up_left = -1.0
	_telegraph_circle.visible = false
	_cooldown = RiftRules.PUSH_INTERVAL
	if not summoner.is_valid():
		return
	var minions: Array = summoner.call(self, _summon_spot)
	for minion: Variant in minions:
		if minion is Enemy and is_instance_valid(minion):
			Burst.spawn(get_parent(), (minion as Enemy).global_position, rift_color, 14, 130.0)
			summoned.emit(minion as Enemy)
	ability_used.emit(self, &"summon")
