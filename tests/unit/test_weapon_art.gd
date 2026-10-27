extends GutTest
## Weapon art (SPRITES_V3 §1, ROADMAP C2): every weapon uses its own sprite, icon and
## projectile art, and the special effects (WeaponFx) are scaled towards the real hit radius in whole
## steps (FS2b).

const CONTROLLER_SCENE: PackedScene = preload("res://player/weapon_controller.tscn")
const WEAPON_DIR := "res://weapons/data/"
const TEST_SAVE_PATH := "user://test_weapon_art.cfg"
const WEAPON_IDS: Array[StringName] = [&"sword", &"bow", &"staff", &"dagger", &"hammer"]
const ICON_SIZE := Vector2(16, 16)

var _old_save_path: String


## Meta upgrades from the real save would change the radii.
func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


## Let one-shot effects finish so nothing is still playing at exit.
func after_all() -> void:
	await wait_seconds(1.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _weapon(id: StringName) -> WeaponData:
	return load(WEAPON_DIR + String(id) + ".tres") as WeaponData


func _make_controller(weapon: WeaponData) -> WeaponController:
	var controller := CONTROLLER_SCENE.instantiate() as WeaponController
	controller.handle_special_input = false
	add_child_autofree(controller)
	controller.equip_weapon(weapon, 0)
	return controller


func _fx(controller: WeaponController) -> WeaponFx:
	return controller.get_node("WeaponFx") as WeaponFx


# --- Data: sprites, icons, projectiles ---

func test_every_weapon_has_its_own_sprite_and_icon() -> void:
	var sprites := {}
	var icons := {}
	for id in WEAPON_IDS:
		var weapon := _weapon(id)
		assert_not_null(weapon.sprite, "%s sprite" % id)
		assert_not_null(weapon.icon, "%s icon" % id)
		assert_eq(weapon.sprite.resource_path, "res://art/weapons/%s.png" % id, "%s uses its delivered art" % id)
		assert_eq(weapon.icon.resource_path, "res://art/ui/icon_%s.png" % id)
		assert_eq(weapon.icon.get_size(), ICON_SIZE, "%s icon is 16x16" % id)
		sprites[weapon.sprite.resource_path] = true
		icons[weapon.icon.resource_path] = true
	assert_eq(sprites.size(), WEAPON_IDS.size(), "no shared placeholder sprites")
	assert_eq(icons.size(), WEAPON_IDS.size(), "no shared placeholder icons")


func test_real_art_is_not_recoloured_or_rescaled() -> void:
	for id in WEAPON_IDS:
		var weapon := _weapon(id)
		assert_eq(weapon.tint, Color.WHITE, "%s keeps its art colours" % id)
		assert_eq(weapon.sprite_scale, 1.0, "%s stays on the pixel grid" % id)


func test_grip_pivots_match_the_art() -> void:
	var dagger := _weapon(&"dagger")
	var hammer := _weapon(&"hammer")
	assert_eq(dagger.sprite.get_size(), Vector2(32, 32))
	assert_eq(hammer.sprite.get_size(), Vector2(48, 32))
	# art/weapons/weapons_v3.json
	assert_eq(dagger.sprite_pivot, Vector2(6, 16))
	assert_eq(hammer.sprite_pivot, Vector2(8, 16))
	for id in WEAPON_IDS:
		var weapon := _weapon(id)
		assert_true(Rect2(Vector2.ZERO, weapon.sprite.get_size()).has_point(weapon.sprite_pivot), "%s pivot inside the sprite" % id)


func test_dagger_throws_the_knife_sprite() -> void:
	var dagger := _weapon(&"dagger")
	assert_eq(dagger.projectile_texture.resource_path, "res://art/projectiles/throwing_knife.png")
	assert_eq(Vector2(dagger.projectile_frame_size), dagger.projectile_texture.get_size(), "single 16x5 frame")
	assert_eq(dagger.projectile_pivot, Vector2(8, 2))


# --- Effects: scale to the hit radius ---

func test_area_art_scales_onto_the_hit_radius() -> void:
	for kind in [&"slam", &"quake", &"nova"]:
		var art := WeaponFx.get_area_art(kind)
		assert_false(art.is_empty(), "%s has art" % kind)
		var frame: Vector2i = art["frame"]
		var texture: Texture2D = art["texture"]
		assert_eq(texture.get_height(), frame.y, "%s is one row" % kind)
		assert_eq(texture.get_width() % frame.x, 0, "%s has whole frames" % kind)
		var art_radius: float = art["art_radius"]
		assert_lt(art_radius, frame.x * 0.5 + 0.01, "%s ring fits into the frame" % kind)
		for hit_radius in [40.0, 55.0, 108.0]:
			var art_scale := WeaponFx.art_scale(hit_radius, art_radius)
			assert_eq(art_scale, roundf(art_scale), "%s: a whole scale keeps the pixels even (FS2b)" % kind)
			assert_gte(art_scale, 1.0)
			# The nearest whole scale: the drawn ring is at most half an art radius off the hit radius.
			if hit_radius >= art_radius:
				assert_lte(absf(art_radius * art_scale - hit_radius), art_radius * 0.5 + 0.001, "%s near %s" % [kind, hit_radius])


func test_area_hits_report_their_real_radius() -> void:
	var hammer := _weapon(&"hammer")
	var controller := _make_controller(hammer)
	var areas: Array[Dictionary] = []
	controller.area_resolved.connect(func(kind: StringName, _center: Vector2, radius: float, _color: Color) -> void:
		areas.append({"kind": kind, "radius": radius}))
	controller.request_attack()
	controller._physics_process(hammer.windup_time + 0.01)
	assert_eq(areas.size(), 1)
	assert_eq(areas[0]["kind"], &"slam")
	assert_almost_eq(float(areas[0]["radius"]), controller.get_effective_aoe_radius(hammer), 0.001)

	areas.clear()
	controller._physics_process(2.0)
	assert_true(controller.request_special())
	controller._physics_process(1.0)
	assert_eq(areas.size(), WeaponController.QUAKE_SLAMS, "one wave per quake slam")
	for area in areas:
		assert_eq(area["kind"], &"quake")
		assert_almost_eq(float(area["radius"]), controller.get_effective_aoe_radius(hammer) * WeaponController.QUAKE_RADIUS_MULTIPLIER, 0.001)


func test_effect_radius_follows_the_aoe_bonus() -> void:
	var staff := _weapon(&"staff")
	var controller := _make_controller(staff)
	var upgrades := autofree(UpgradeManager.new()) as UpgradeManager
	var big_explosion := load("res://upgrades/data/big_explosion.tres") as UpgradeData
	upgrades.upgrade_pool.append(big_explosion)
	controller.upgrades = upgrades
	var base_radius := controller.get_nova_radius(staff)
	assert_true(upgrades.acquire_upgrade(big_explosion))
	var radii: Array[float] = []
	controller.area_resolved.connect(func(_kind: StringName, _center: Vector2, radius: float, _color: Color) -> void: radii.append(radius))
	assert_true(controller.request_special())
	controller._physics_process(0.02)
	assert_eq(radii.size(), 1)
	assert_gt(radii[0], base_radius, "bigger explosion grows the nova")
	assert_almost_eq(radii[0], controller.get_nova_radius(staff), 0.001)


func test_spin_art_matches_the_spin_hitbox() -> void:
	var sword := _weapon(&"sword")
	var controller := _make_controller(sword)
	var fx := _fx(controller)
	assert_not_null(fx, "controller scene contains WeaponFx")
	assert_true(controller.request_special())
	var spin := fx.get_child(fx.get_child_count() - 1) as AnimatedSprite2D
	assert_not_null(spin, "spin art follows the player")
	var radius := sword.attack_range * WeaponController.SPIN_RANGE_MULTIPLIER
	assert_almost_eq(spin.scale.x, PixelDraw.whole_scale(radius / WeaponFx.SPIN_ART_RADIUS), 0.001)
	controller.cancel_attack()
	assert_true(spin.is_queued_for_deletion(), "dash/cancel removes the spin art")


func test_nova_export_haze_is_removed() -> void:
	var cleaned := WeaponFx.without_black_haze(WeaponFx.NOVA_RING_TEXTURE)
	var image := cleaned.get_image()
	image.decompress()
	var haze := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and pixel.a < 1.0 and pixel.r + pixel.g + pixel.b < 0.02:
				haze += 1
	assert_eq(haze, 0)
	# The ring itself survives: the last frame still has visible pixels.
	var last := image.get_region(Rect2i(image.get_width() - 128, 0, 128, 128))
	assert_false(last.is_invisible(), "last nova frame keeps its ring")
