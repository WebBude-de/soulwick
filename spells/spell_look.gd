class_name SpellLook
extends RefCounted
## How a cast looks and sounds (KE7, KONZEPT §6.2: "Flint wirkt den Zauber sichtbar"): Flint plays
## his cast reaction and his flame flares, sparks leave the flame, and the spell's effect shows -
## the area ring around the player (its reach is measured there), the shield bubble, the healing
## sparks flying from the flame to every player in reach. Effect strips from art/effects/spells/
## when delivered (SpellArt), drawn rings and sparks until then. Optics only (D-088): played by
## PlayerSpells on every machine from the decision (host) or the cast event (client); a client also
## gets look-only wisps here because the host's wisps never travel over the network.

## TESTWERTE (optics)
const FLAME_FLASH_RADIUS := 96.0
const FLAME_FLASH_TIME := 0.4
const FLAME_SPARKS := 10
const SHIELD_RING_RADIUS := 30.0
const AREA_FLASH_SHARE := 1.4
const SHAKE_FLAME_RING := 4.0
const SHAKE_LIGHT_FLASH := 2.0
## The shield bubble keeps glowing (soul_shield_loop) this long after it formed, then fades.
const SHIELD_LOOP_TIME := 1.2
const SHIELD_LOOP_FADE := 0.3


## Plays the cast of data by caster towards aim. with_wisps: also launch look-only wisps (a client
## replaying the host's cast; the host's own wisps are real).
static func play(caster: Player, data: SpellData, aim: Vector2, with_wisps: bool) -> void:
	if caster == null or not is_instance_valid(caster) or data == null or not caster.is_inside_tree():
		return
	var parent := caster.get_parent()
	if parent == null:
		return
	var origin := SpellEffects.cast_origin(caster)
	_flare_flint(caster, parent, origin, data)
	if data.sound != &"":
		Sfx.play_at(caster, data.sound, origin, -2.0)
	match data.effect:
		SpellData.Effect.BLIND_AREA:
			_area(parent, caster.global_position, data)
			LightSource.flash(parent, caster.global_position, data.radius * AREA_FLASH_SHARE, 0.45, data.color, 1.0)
			_shake(caster, SHAKE_LIGHT_FLASH)
		SpellData.Effect.DAMAGE_AREA:
			_area(parent, caster.global_position, data)
			Burst.spawn(parent, caster.global_position, data.color, 22, 260.0, 0.5, 5.0)
			LightSource.flash(parent, caster.global_position, data.radius * AREA_FLASH_SHARE, 0.4, data.color)
			_shake(caster, SHAKE_FLAME_RING)
		SpellData.Effect.SHIELD:
			SpellSpark.spawn(parent, origin, caster, caster.global_position, data.color)
			_on_target(caster, data, SHIELD_RING_RADIUS)
		SpellData.Effect.HEAL_AREA:
			for player in SpellEffects.players_within(caster, data.radius):
				SpellSpark.spawn(parent, origin, player, player.global_position, data.color)
				_on_target(player, data, SHIELD_RING_RADIUS)
		SpellData.Effect.HOMING_LIGHTS:
			if with_wisps:
				WillOWisp.launch_all(caster, data, origin, aim, 0.0, false)


## Flint's part: the cast reaction, a flash and sparks at his flame.
static func _flare_flint(caster: Player, parent: Node, origin: Vector2, data: SpellData) -> void:
	var flint := FlintCompanion.of(caster)
	if flint != null:
		flint.react(FlintMood.Mood.CAST)
	LightSource.flash(parent, origin, FLAME_FLASH_RADIUS, FLAME_FLASH_TIME, data.color, 1.0)
	Burst.spawn(parent, origin, data.color, FLAME_SPARKS, 110.0, 0.35, 3.0)


## The area effect around center: the delivered strip scaled to the reach (a whole scale, so its
## pixels stay even; the hit reach itself is exact), else a growing ring.
static func _area(parent: Node, center: Vector2, data: SpellData) -> void:
	var art := SpellArt.effect(data.id)
	if not art.is_empty() and float(art["art_radius"]) > 0.0:
		var frame: Vector2i = art["frame"]
		var art_scale := Vector2.ONE * PixelDraw.whole_scale(data.radius / float(art["art_radius"]))
		SpriteStrip.spawn_effect(parent, center, art["texture"], frame, float(art["fps"]), art["pivot"], art_scale)
		return
	SpellRing.spawn(parent, center, data.color, 12.0, data.radius)


## An effect on one player (shield bubble, heal sparkle) that moves with them: the strip as a
## child, else a small ring. The shield bubble goes on glowing in its loop strip when delivered.
static func _on_target(holder: Node2D, data: SpellData, ring_radius: float) -> void:
	var art := SpellArt.effect(data.id)
	if not art.is_empty():
		var sprite := _spawn_on(holder, art)
		var loop := SpellArt.effect(StringName(String(data.id) + "_loop"))
		if not loop.is_empty():
			sprite.animation_finished.connect(_glow_on.bind(holder, loop))
		return
	var ring := SpellRing.spawn(holder, holder.global_position, data.color, ring_radius * 0.5, ring_radius, 0.5)
	if ring != null:
		ring.position = Vector2.ZERO


## Plays a strip of SpellArt.effect once on holder, at its pivot, moving with it.
static func _spawn_on(holder: Node2D, art: Dictionary) -> AnimatedSprite2D:
	var sprite := SpriteStrip.spawn_effect(holder, holder.global_position, art["texture"], art["frame"], float(art["fps"]),
		art["pivot"], Vector2.ONE * SpriteStrip.PIXEL_SCALE)
	sprite.position = Vector2.ZERO
	return sprite


## The loop strip after the intro (shield bubble): glows SHIELD_LOOP_TIME, then fades and frees itself.
static func _glow_on(holder: Node2D, art: Dictionary) -> AnimatedSprite2D:
	if not is_instance_valid(holder) or not holder.is_inside_tree():
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.name = "SpellGlow"
	sprite.sprite_frames = SpriteStrip.make_frames(art["texture"], art["frame"], float(art["fps"]), true)
	sprite.offset = SpriteStrip.pivot_offset(art["frame"], art["pivot"])
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 5
	holder.add_child(sprite)
	sprite.play(&"default")
	var tween := sprite.create_tween()
	tween.tween_interval(SHIELD_LOOP_TIME)
	tween.tween_property(sprite, "modulate:a", 0.0, SHIELD_LOOP_FADE)
	tween.tween_callback(sprite.queue_free)
	return sprite


static func _shake(caster: Player, strength: float) -> void:
	if caster.is_local:
		CameraShake.shake(caster, strength)
