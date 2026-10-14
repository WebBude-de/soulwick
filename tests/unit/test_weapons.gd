extends GutTest
## Weapon controller rules beyond damage math: sword combo counting, special cooldowns per slot,
## wind-up attacks, the new weapons' data and tag applicability, dagger backstab detection.

const CONTROLLER_SCENE: PackedScene = preload("res://player/weapon_controller.tscn")
const WEAPON_DIR := "res://weapons/data/"
const TEST_SAVE_PATH := "user://test_weapons.cfg"

var _old_save_path: String
var _sword: WeaponData
var _bow: WeaponData
var _staff: WeaponData
var _dagger: WeaponData
var _hammer: WeaponData


## Meta upgrades from the real save (e.g. sharpness) would change the damage math.
func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func before_each() -> void:
	_sword = load(WEAPON_DIR + "sword.tres")
	_bow = load(WEAPON_DIR + "bow.tres")
	_staff = load(WEAPON_DIR + "staff.tres")
	_dagger = load(WEAPON_DIR + "dagger.tres")
	_hammer = load(WEAPON_DIR + "hammer.tres")


## Let fire-and-forget sounds, effects and projectiles finish so nothing is still playing at exit.
func after_all() -> void:
	await wait_seconds(1.5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _make_controller(first: WeaponData = null) -> WeaponController:
	var controller := CONTROLLER_SCENE.instantiate() as WeaponController
	controller.handle_special_input = false
	add_child_autofree(controller)
	if first != null:
		controller.equip_weapon(first, 0)
	return controller


## Advances the controller's timers without waiting for real frames.
func _advance(controller: WeaponController, seconds: float) -> void:
	controller._physics_process(seconds)


# --- Combo ---

func test_every_third_sword_swing_is_a_finisher() -> void:
	var controller := _make_controller(_sword)
	var finishers: Array[WeaponData] = []
	controller.combo_finisher.connect(func(weapon: WeaponData) -> void: finishers.append(weapon))
	var interval := 1.0 / _sword.attack_rate + 0.05

	assert_true(controller.request_attack())
	assert_eq(controller.get_combo_count(), 1)
	_advance(controller, interval)
	assert_true(controller.request_attack())
	assert_eq(controller.get_combo_count(), 2)
	assert_true(controller.is_next_swing_finisher())
	_advance(controller, interval)
	assert_true(controller.request_attack())
	assert_eq(finishers.size(), 1, "third swing is the finisher")
	assert_eq(controller.get_combo_count(), 0, "combo restarts after the finisher")

	# Finisher recovery is longer than a normal swing.
	_advance(controller, interval)
	assert_false(controller.request_attack(), "finisher has extra recovery")
	_advance(controller, WeaponController.FINISHER_RECOVERY)
	assert_true(controller.request_attack())
	assert_eq(controller.get_combo_count(), 1)


func test_combo_resets_after_a_pause() -> void:
	var controller := _make_controller(_sword)
	var finishers := [0]
	controller.combo_finisher.connect(func(_weapon: WeaponData) -> void: finishers[0] += 1)
	var interval := 1.0 / _sword.attack_rate + 0.05
	controller.request_attack()
	_advance(controller, interval)
	controller.request_attack()
	assert_eq(controller.get_combo_count(), 2)
	_advance(controller, 2.0)
	assert_eq(controller.get_combo_count(), 0, "pause breaks the combo")
	controller.request_attack()
	assert_eq(controller.get_combo_count(), 1)
	assert_eq(finishers[0], 0)


func test_combo_resets_on_weapon_switch() -> void:
	var controller := _make_controller(_sword)
	controller.equip_weapon(_bow, 1)
	controller.request_attack()
	assert_eq(controller.get_combo_count(), 1)
	assert_true(controller.switch_weapon())
	assert_eq(controller.get_combo_count(), 0)


func test_weapons_without_combo_never_count() -> void:
	var controller := _make_controller(_dagger)
	controller.request_attack()
	assert_eq(controller.get_combo_count(), 0)
	assert_false(controller.is_next_swing_finisher())


func test_finisher_damage_uses_context_multiplier() -> void:
	var controller := _make_controller(_sword)
	assert_almost_eq(controller.get_effective_damage(_sword, _sword.combo_damage_multiplier), _sword.base_damage * _sword.combo_damage_multiplier, 0.001)


# --- Specials ---

func test_special_has_a_cooldown() -> void:
	var controller := _make_controller(_sword)
	var ready_slots: Array[int] = []
	controller.special_ready.connect(func(slot: int) -> void: ready_slots.append(slot))
	assert_true(controller.is_special_ready(0))
	assert_true(controller.request_special())
	assert_almost_eq(controller.get_special_cooldown_left(0), _sword.special_cooldown, 0.001)
	assert_almost_eq(controller.get_special_charge(0), 0.0, 0.001)
	assert_false(controller.request_special(), "on cooldown")
	_advance(controller, _sword.special_cooldown - 0.1)
	assert_false(controller.request_special(), "still on cooldown")
	assert_true(ready_slots.is_empty())
	_advance(controller, 0.2)
	assert_eq(ready_slots, [0] as Array[int])
	assert_true(controller.request_special())


func test_special_blocks_regular_attacks_briefly() -> void:
	var controller := _make_controller(_bow)
	assert_true(controller.request_special())
	assert_false(controller.request_attack())
	_advance(controller, WeaponController.SPECIAL_RECOVERY + 0.01)
	assert_true(controller.request_attack())


func test_special_cooldowns_are_per_slot() -> void:
	var controller := _make_controller(_sword)
	controller.equip_weapon(_bow, 1)
	assert_true(controller.request_special())
	_advance(controller, 0.5)
	assert_true(controller.switch_weapon())
	assert_true(controller.is_special_ready(1))
	assert_true(controller.request_special(), "bow special is independent")
	assert_false(controller.is_special_ready(0), "sword special keeps cooling down in the other slot")


func test_equipping_a_new_weapon_resets_the_slot_cooldown() -> void:
	var controller := _make_controller(_sword)
	controller.request_special()
	assert_false(controller.is_special_ready(0))
	controller.equip_weapon(_dagger, 0)
	assert_true(controller.is_special_ready(0))


func test_every_weapon_has_a_working_special() -> void:
	for weapon in [_sword, _bow, _staff, _dagger, _hammer]:
		var controller := _make_controller(weapon)
		var used: Array[WeaponData] = []
		controller.special_performed.connect(func(w: WeaponData) -> void: used.append(w))
		assert_true(controller.request_special(), "%s special" % weapon.id)
		assert_eq(used.size(), 1)
		assert_ne(weapon.special_name, "", "%s has a special name" % weapon.id)
		assert_gt(weapon.special_cooldown, 0.0)
		# Resolve queued area hits (nova, quake) inside a tick.
		_advance(controller, 1.0)
		assert_false(controller.is_attacking(), "%s special finished" % weapon.id)


func test_nova_radius_grows_with_aoe_bonus() -> void:
	var controller := _make_controller(_staff)
	assert_almost_eq(controller.get_nova_radius(_staff), _staff.aoe_radius * WeaponController.NOVA_RADIUS_MULTIPLIER, 0.001)
	assert_almost_eq(controller.get_effective_special_damage(_staff), _staff.base_damage * _staff.special_damage_multiplier, 0.001)


# --- New weapons ---

func test_hammer_slam_winds_up() -> void:
	var controller := _make_controller(_hammer)
	assert_true(controller.request_attack())
	assert_true(controller.is_attacking(), "slam is pending during the wind-up")
	_advance(controller, _hammer.windup_time + 0.01)
	assert_false(controller.is_attacking())


func test_cancel_aborts_the_hammer_wind_up() -> void:
	var controller := _make_controller(_hammer)
	controller.request_attack()
	controller.cancel_attack()
	assert_false(controller.is_attacking())


func test_all_weapon_types_are_unique() -> void:
	var seen := {}
	for path in DirAccess.get_files_at(WEAPON_DIR):
		if not path.ends_with(".tres"):
			continue
		var weapon := load(WEAPON_DIR + path) as WeaponData
		assert_false(seen.has(weapon.weapon_type), "duplicate weapon type in %s" % path)
		seen[weapon.weapon_type] = true
	assert_eq(seen.size(), 5)


func test_new_weapons_cannot_be_doubled() -> void:
	var controller := _make_controller(_dagger)
	assert_false(controller.can_equip(_dagger, 1))
	assert_true(controller.can_equip(_hammer, 1))


func test_upgrade_tags_fit_the_new_weapons() -> void:
	var wide_swing := load("res://upgrades/data/wide_swing.tres") as UpgradeData
	var big_explosion := load("res://upgrades/data/big_explosion.tres") as UpgradeData
	var strength := load("res://upgrades/data/strength_training.tres") as UpgradeData
	var precise := load("res://upgrades/data/precise_arrows.tres") as UpgradeData
	assert_true(wide_swing.applies_to(_sword.tags))
	assert_true(wide_swing.applies_to(_dagger.tags))
	assert_false(wide_swing.applies_to(_hammer.tags), "hammer has no swing arc")
	assert_true(big_explosion.applies_to(_hammer.tags))
	assert_true(big_explosion.applies_to(_staff.tags))
	assert_true(strength.applies_to(_dagger.tags))
	assert_true(strength.applies_to(_hammer.tags))
	assert_false(precise.applies_to(_dagger.tags))


func test_backstab_detects_targets_moving_away() -> void:
	var body := CharacterBody2D.new()
	var hurtbox := Hurtbox.new()
	body.add_child(hurtbox)
	add_child_autofree(body)
	body.global_position = Vector2.ZERO
	body.velocity = Vector2.RIGHT * 100.0
	assert_true(MeleeHitbox.is_behind(hurtbox, Vector2(-50, 0)), "attacker behind a target walking away")
	assert_false(MeleeHitbox.is_behind(hurtbox, Vector2(50, 0)), "attacker in front")
	body.velocity = Vector2.ZERO
	assert_false(MeleeHitbox.is_behind(hurtbox, Vector2(-50, 0)), "standing targets have no back")
