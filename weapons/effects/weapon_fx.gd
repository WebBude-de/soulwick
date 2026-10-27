class_name WeaponFx
extends Node2D
## Presentation of the weapon specials and area hits: sprites, particles, light, sound, shake.
## Lives as a child of a WeaponController and only listens to its signals; the controller decides
## and deals damage, this node never touches gameplay (D-088). A remote player's controller that
## replays the same signals gets the same effects.
## Art: art/effects/*_v3 (see art/effects/effects_v3.json, SPRITES_V3 §1). Every ground effect is
## scaled towards the real hit radius (including the AOE upgrade bonus), rounded to a whole scale so
## the art's pixels stay even (FS2b, D-218); a thin pixel ring (PixelRingWave) shows the exact hit area.

const SPARK_TEXTURE: Texture2D = preload("res://art/effects/hit_spark_3f.png")
const MUZZLE_PUFF_TEXTURE: Texture2D = preload("res://art/effects/muzzle_puff_3f.png")
const SPIN_SLASH_TEXTURE: Texture2D = preload("res://art/effects/spin_slash_4f.png")
const HAMMER_SLAM_TEXTURE: Texture2D = preload("res://art/effects/hammer_slam_6f.png")
const QUAKE_RING_TEXTURE: Texture2D = preload("res://art/effects/quake_ring_6f.png")
const NOVA_RING_TEXTURE: Texture2D = preload("res://art/effects/nova_ring_6f.png")

## Frame sizes, pivots (= frame centre) and fps from effects_v3.json.
const PUFF_FRAME := Vector2i(16, 16)
const PUFF_FPS := 15.0
const SPIN_FRAME := Vector2i(96, 96)
const SLAM_FRAME := Vector2i(96, 96)
const SLAM_FPS := 12.0
const RING_FRAME := Vector2i(128, 128)
const QUAKE_FPS := 10.0
const NOVA_FPS := 12.0
## Radius of the outermost visible ring in frame pixels (last frame, horizontal; the hammer art is
## drawn in perspective, so it is flatter than the circular hit area). Measured on the delivered PNGs.
const SPIN_ART_RADIUS := 36.0
const SLAM_ART_RADIUS := 33.0
const QUAKE_ART_RADIUS := 62.0
const NOVA_ART_RADIUS := 60.0

## Ground effects lie on the floor: above tiles (-10) and below drop shadows (-2) and bodies.
const GROUND_Z := -3
const AIR_Z := 5
## Thin circle that marks the exact (circular) hit area under the flattened hammer art.
const AREA_OUTLINE_ALPHA := 0.5
const AREA_OUTLINE_WIDTH := 3.0
const SLAM_DUST_COLOR := Color(0.75, 0.62, 0.45)
## How much the muzzle puff takes on the projectile colour (0 = neutral smoke, 1 = full colour).
const PUFF_TINT := 0.35
## The staff's puff is a burst of magic rather than smoke.
const PUFF_TINT_MAGIC := 0.8
const SPIN_FADE_TIME := 0.08

var _controller: WeaponController = null
var _spin_sprite: AnimatedSprite2D = null
## Nova strip without the black export haze (see without_black_haze), prepared once per node.
var _nova_texture: Texture2D = NOVA_RING_TEXTURE


func _ready() -> void:
	_controller = get_parent() as WeaponController
	if _controller == null:
		push_warning("WeaponFx needs a WeaponController parent")
		return
	_controller.muzzle_flashed.connect(_on_muzzle_flashed)
	_controller.spin_started.connect(_on_spin_started)
	_controller.area_resolved.connect(_on_area_resolved)
	_controller.attack_cancelled.connect(_stop_spin)
	# Clean the nova strip now (~10 ms), not with a hitch on the first cast.
	_nova_texture = without_black_haze(NOVA_RING_TEXTURE)


## Strip of a ground/area effect for kind, with the art radius it was measured at (raw texture).
static func get_area_art(kind: StringName) -> Dictionary:
	match kind:
		&"slam":
			return {"texture": HAMMER_SLAM_TEXTURE, "frame": SLAM_FRAME, "fps": SLAM_FPS, "art_radius": SLAM_ART_RADIUS}
		&"quake":
			return {"texture": QUAKE_RING_TEXTURE, "frame": RING_FRAME, "fps": QUAKE_FPS, "art_radius": QUAKE_ART_RADIUS}
		&"nova":
			return {"texture": NOVA_RING_TEXTURE, "frame": RING_FRAME, "fps": NOVA_FPS, "art_radius": NOVA_ART_RADIUS}
	return {}


## Uniform sprite scale that brings the outermost ring of the art closest to the hit radius in
## whole steps (PixelDraw.whole_scale: nearest whole number, at least 1).
static func art_scale(hit_radius: float, art_radius: float) -> float:
	return PixelDraw.whole_scale(hit_radius / art_radius) if art_radius > 0.0 else 1.0


func _effect_parent() -> Node:
	var parent := _controller.get_effect_parent() if _controller != null else null
	if parent == null or not parent.is_inside_tree():
		return null
	return parent


# --- Muzzle (bow, staff, thrown knives, nova cast) ---

func _on_muzzle_flashed(weapon: WeaponData, origin: Vector2, direction: Vector2, strength: float) -> void:
	var parent := _effect_parent()
	if parent == null:
		return
	var color := weapon.projectile_color
	var magic := weapon.weapon_type == WeaponData.WeaponType.STAFF
	var puff_scale := SpriteStrip.PIXEL_SCALE * clampf(0.75 + 0.25 * strength, 1.0, 1.5)
	var puff := SpriteStrip.spawn_effect(parent, origin, MUZZLE_PUFF_TEXTURE, PUFF_FRAME, PUFF_FPS, Vector2(PUFF_FRAME) * 0.5,
		Vector2.ONE * puff_scale, direction.angle())
	puff.modulate = Color.WHITE.lerp(color, PUFF_TINT_MAGIC if magic else PUFF_TINT)
	if magic:
		# Magic keeps its coloured spark on top of the puff.
		var spark := SpriteStrip.spawn_effect(parent, origin, SPARK_TEXTURE, Vector2i(16, 16), 20.0, Vector2(8, 8),
			Vector2.ONE * SpriteStrip.PIXEL_SCALE * (0.8 + 0.4 * strength), direction.angle())
		spark.modulate = color
	Burst.spawn(parent, origin, color, roundi(5 * strength), 90.0 * strength, 0.2, 3.0)
	LightSource.flash(parent, origin, 60.0 * strength, 0.12)


# --- Sword "Wirbelschlag" ---

## The spin art follows the player (child of this node) and runs exactly as long as the hit window.
func _on_spin_started(weapon: WeaponData, radius: float, duration: float) -> void:
	_stop_spin()
	var frames := SpriteStrip.make_frames(SPIN_SLASH_TEXTURE, SPIN_FRAME, 1.0, false)
	frames.set_animation_speed(&"default", frames.get_frame_count(&"default") / maxf(duration, 0.05))
	_spin_sprite = AnimatedSprite2D.new()
	_spin_sprite.sprite_frames = frames
	_spin_sprite.offset = SpriteStrip.pivot_offset(SPIN_FRAME, Vector2(SPIN_FRAME) * 0.5)
	_spin_sprite.scale = Vector2.ONE * art_scale(radius, SPIN_ART_RADIUS)
	# Frame 0 starts the arc at the right; the hitbox sweeps clockwise from the aim direction.
	_spin_sprite.rotation = _controller.aim_direction.angle()
	_spin_sprite.z_index = AIR_Z
	add_child(_spin_sprite)
	var sprite := _spin_sprite
	sprite.animation_finished.connect(func() -> void: _fade_out(sprite, SPIN_FADE_TIME))
	sprite.play(&"default")

	var parent := _effect_parent()
	if parent != null:
		Burst.spawn(parent, global_position, weapon.effect_color, 18, radius * 2.5, 0.35, 4.0)
		LightSource.flash(parent, global_position, radius * 1.8, 0.25)
	Sfx.play_at(self, &"sword_swing", global_position, 2.0)
	Sfx.play_at(self, &"charge", global_position, -6.0)
	CameraShake.shake(self, 4.0)


func _stop_spin() -> void:
	if _spin_sprite != null and is_instance_valid(_spin_sprite):
		_spin_sprite.queue_free()
	_spin_sprite = null


# --- Slam, quake, nova ---

func _on_area_resolved(kind: StringName, center: Vector2, radius: float, color: Color) -> void:
	var parent := _effect_parent()
	if parent == null:
		return
	var art := get_area_art(kind)
	if not art.is_empty():
		var frame: Vector2i = art["frame"]
		var texture: Texture2D = _nova_texture if kind == &"nova" else art["texture"]
		var sprite := SpriteStrip.spawn_effect(parent, center, texture, frame, art["fps"], Vector2(frame) * 0.5,
			Vector2.ONE * art_scale(radius, art["art_radius"]))
		sprite.z_index = GROUND_Z
	match kind:
		&"nova":
			# The art is a whole scale; the thin ring shows the exact hit area.
			PixelRingWave.spawn(parent, center, radius, Color(color, AREA_OUTLINE_ALPHA), 0.3, AREA_OUTLINE_WIDTH, 0.3)
			Burst.spawn(parent, center, color, 28, radius * 3.0, 0.5, 4.0)
			LightSource.flash(parent, center, radius * 2.2, 0.4)
			Sfx.play_at(self, &"explosion", center, -2.0)
			CameraShake.shake(self, 6.0)
		_:
			# The hammer art is flattened (3/4 view); the thin circle shows the real hit area.
			PixelRingWave.spawn(parent, center, radius, Color(color, AREA_OUTLINE_ALPHA), 0.3, AREA_OUTLINE_WIDTH, 0.3)
			Burst.spawn(parent, center, SLAM_DUST_COLOR, 18, radius * 2.5, 0.4, 4.0)
			LightSource.flash(parent, center, radius * 1.4, 0.2)
			Sfx.play_at(self, &"slam", center)
			CameraShake.shake(self, 5.0)


static func _fade_out(item: CanvasItem, duration: float) -> void:
	if not is_instance_valid(item):
		return
	var tween := item.create_tween()
	tween.tween_property(item, "modulate:a", 0.0, duration)
	tween.tween_callback(item.queue_free)


## nova_ring_6f.png fades its last two frames by filling the whole disc with translucent pure black
## (an export artefact, reported to art in ROADMAP C2). Effects have no outlines, so
## translucent pure-black pixels are never intended and are dropped. A corrected PNG passes through
## unchanged. Not cached statically on purpose: a static ImageTexture outlives the RenderingServer at exit.
static func without_black_haze(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	if image == null:
		return texture
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var changed := false
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and pixel.a < 1.0 and pixel.r + pixel.g + pixel.b < 0.02:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				changed = true
	return ImageTexture.create_from_image(image) if changed else texture
