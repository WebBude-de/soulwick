extends GutTest
## Side enemies for the obstacle run (SV4, D-195, D-216): stomping through the normal damage pipeline
## (kill on the EventBus, tags, no gold), the pop, refusals with contact damage at once, the contact
## holding back only for a stomping player (running into one hurts at any speed: nobody is run over),
## puppets deciding nothing, the remote defeat, the bat's arc, the factory with its plan characters
## and the chain building blocks.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0
const ALL_KINDS: Array[SideEnemy.Kind] = [SideEnemy.Kind.SLIME, SideEnemy.Kind.SKELETON, SideEnemy.Kind.BAT,
		SideEnemy.Kind.SPIKE_HEDGEHOG, SideEnemy.Kind.SHIELD_BEARER]

var _old_save_path: String
var _damaged: Array = []


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_enemies_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_damaged.clear()
	EventBus.enemy_damaged.connect(_on_enemy_damaged)


func after_each() -> void:
	EventBus.enemy_damaged.disconnect(_on_enemy_damaged)
	HitStop.reset()
	await wait_process_frames(1)


func _on_enemy_damaged(enemy: Node2D, result: DamageResult, damage: DamageData) -> void:
	_damaged.append([enemy, result, damage])


func _segment() -> SideSegment:
	var segment := SideSegment.new()
	segment.setup(SidePlans.build(&"crypt_steps"), 1, null, 7)
	add_child_autofree(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	return segment


## A stand cell with stand cells 2 and 4 columns to the right (a floor run).
func _floor_run(layout: SideLayout) -> Vector2i:
	for cell in layout.stand_cells():
		if layout.is_standable(cell + Vector2i(2, 0)) and layout.is_standable(cell + Vector2i(4, 0)):
			return cell
	return Vector2i(-1, -1)


func _spawn(segment: SideSegment, kind: SideEnemy.Kind, seed_value := 3) -> SideEnemy:
	var enemy := SideEnemyKinds.make(kind, 1, segment, seed_value)
	var cell := _floor_run(segment.layout)
	if kind == SideEnemy.Kind.BAT:
		cell += Vector2i(0, -SideEnemyChain.BAT_ROWS_UP)
	enemy.position = SideLayout.feet_of(cell)
	segment.add_child(enemy)
	return enemy


func _player() -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	return player


## Puts the player's feet just into the top of the enemy, falling.
func _falling_onto(player: Player, enemy: SideEnemy) -> void:
	player.global_position = Vector2(enemy.global_position.x, enemy.get_top_y() + 2.0) - Player.FEET_OFFSET
	player.velocity = Vector2(0.0, 420.0)


func _running_into(player: Player, enemy: SideEnemy, speed_factor: float) -> void:
	player.global_position = enemy.global_position + Vector2(-20.0, -enemy.get_body_size().y * 0.5)
	player.velocity = Vector2(player.move_speed * speed_factor, 0.0)


func test_stomp_pops_every_stompable_kind_like_a_normal_kill() -> void:
	var segment := _segment()
	for kind in [SideEnemy.Kind.SLIME, SideEnemy.Kind.SKELETON, SideEnemy.Kind.BAT, SideEnemy.Kind.SHIELD_BEARER]:
		_damaged.clear()
		var enemy := _spawn(segment, kind)
		await wait_physics_frames(1)
		var player := _player()
		_falling_onto(player, enemy)
		watch_signals(enemy)
		assert_true(enemy.on_stomped(player), "%s: stomp accepted" % SideEnemy.Kind.keys()[kind])
		assert_true(enemy.is_dead(), "defeated")
		assert_eq(enemy.defeat_style, SideEnemy.Defeat.POP, "pops flat")
		assert_signal_emitted(enemy, "died", "NetSide sees the death")
		assert_signal_emitted(enemy, "defeated", "combo hook")
		assert_eq(_damaged.size(), 1, "one hit on the EventBus")
		var result: DamageResult = _damaged[0][1]
		var damage: DamageData = _damaged[0][2]
		assert_true(result.killed, "a kill for stats and kill rewards")
		assert_eq(damage.source, player, "the player's kill")
		assert_true(damage.tags.has(&"stomp"))
		assert_false(enemy.on_stomped(player), "dead enemies decide nothing")
	await wait_process_frames(2)
	var gold := 0
	for child in segment.get_children():
		if child is GoldPickup:
			gold += 1
	assert_eq(gold, 0 if SideRules.ENEMY_GOLD <= 0 else 4, "coins like a normal defeat (side enemies drop none)")


func test_running_into_any_kind_at_top_speed_hurts() -> void:
	var segment := _segment()
	for kind in ALL_KINDS:
		var enemy := _spawn(segment, kind)
		await wait_physics_frames(1)
		var player := _player()
		_running_into(player, enemy, SideMomentum.MAX_FACTOR)
		assert_false(enemy.spares_contact(player), "%s: no running over (D-216)" % SideEnemy.Kind.keys()[kind])
		assert_false(enemy.has_method(&"on_rammed"), "no ram hook any more")


func test_hedgehog_refuses_a_stomp_and_strikes_at_once() -> void:
	var segment := _segment()
	var enemy := _spawn(segment, SideEnemy.Kind.SPIKE_HEDGEHOG)
	await wait_physics_frames(1)
	var player := _player()
	_falling_onto(player, enemy)
	enemy._contact_left = 0.3
	assert_false(enemy.on_stomped(player), "spikes on top")
	assert_false(enemy.is_dead())
	assert_eq(enemy._contact_left, SideEnemy.CONTACT_REARM, "a fresh contact attack at once")
	assert_true(enemy._contact.is_active())
	assert_false(enemy.spares_contact(player), "the contact hurts the stomping player")
	_running_into(player, enemy, 2.0)
	assert_false(enemy.spares_contact(player), "running into it hurts")
	assert_eq(_damaged.size(), 0, "no hit on the hedgehog")


func test_shield_bearer_takes_a_stomp_or_a_weapon() -> void:
	var segment := _segment()
	var enemy := _spawn(segment, SideEnemy.Kind.SHIELD_BEARER)
	await wait_physics_frames(1)
	var player := _player()
	_running_into(player, enemy, 2.0)
	assert_false(enemy.spares_contact(player), "the shield hurts a runner")
	assert_false(enemy.is_dead())
	var weapon := DamageData.new()
	weapon.amount = 999.0
	weapon.hit_id = DamageData.next_hit_id()
	enemy.hurtbox.receive_hit(weapon)
	assert_true(enemy.is_dead(), "a weapon beats it")
	var hedgehog := _spawn(segment, SideEnemy.Kind.SPIKE_HEDGEHOG)
	await wait_physics_frames(1)
	var sword := DamageData.new()
	sword.amount = 999.0
	sword.hit_id = DamageData.next_hit_id()
	hedgehog.hurtbox.receive_hit(sword)
	assert_true(hedgehog.is_dead(), "a weapon beats the hedgehog too")


func test_contact_holds_back_only_for_a_successful_stomp() -> void:
	var segment := _segment()
	var enemy := _spawn(segment, SideEnemy.Kind.SLIME)
	await wait_physics_frames(1)
	var player := _player()
	_falling_onto(player, enemy)
	assert_true(enemy.spares_contact(player), "falling onto it: the stomp comes first")
	player.velocity.y = -300.0
	assert_false(enemy.spares_contact(player), "jumping up through it hurts")
	_running_into(player, enemy, 1.3)
	assert_false(enemy.spares_contact(player), "normal running speed hurts")
	_running_into(player, enemy, SideMomentum.MAX_FACTOR)
	assert_false(enemy.spares_contact(player), "top speed hurts too (D-216)")
	# The contact itself: a spared player is not hit (and not marked), a walking one is.
	_falling_onto(player, enemy)
	watch_signals(player.hurtbox)
	enemy._strike()
	enemy._contact._handle_contact(player.hurtbox)
	assert_signal_not_emitted(player.hurtbox, "hit_received", "spared")
	player.velocity = Vector2.ZERO
	enemy._contact._handle_contact(player.hurtbox)
	assert_signal_emitted(player.hurtbox, "hit_received", "the same attack still hurts later")


func test_puppets_decide_nothing_and_follow_the_host_defeat() -> void:
	var segment := _segment()
	var enemy := _spawn(segment, SideEnemy.Kind.SLIME)
	await wait_physics_frames(1)
	var player := _player()
	_falling_onto(player, enemy)
	enemy.set_physics_process(false)
	assert_true(enemy.is_puppet(), "NetSide holds client copies with physics off")
	assert_false(enemy.on_stomped(player), "the host decides")
	assert_false(enemy.is_dead())
	enemy.apply_remote_defeat(SideEnemy.Defeat.POP, -1.0)
	assert_true(enemy.is_dead())
	assert_eq(enemy.defeat_style, SideEnemy.Defeat.POP, "the host's look")
	assert_eq(enemy.get_defeat_direction(), -1.0)
	assert_eq(_damaged.size(), 0, "a client counts no kill")


func test_bat_flies_a_jump_arc_without_gravity() -> void:
	var anchor := Vector2(100, 200)
	assert_eq(SideBat.path_point(anchor, 0.0), anchor + Vector2(-SideBat.RANGE, 0))
	assert_almost_eq(SideBat.path_point(anchor, 0.5), anchor + Vector2(0, -SideBat.ARC_HEIGHT), Vector2.ONE * 0.01, "top of the arc")
	assert_almost_eq(SideBat.path_point(anchor, 1.0), anchor + Vector2(SideBat.RANGE, 0), Vector2.ONE * 0.01)
	assert_almost_eq(SideBat.path_point(anchor, 1.5), anchor + Vector2(0, -SideBat.ARC_HEIGHT), Vector2.ONE * 0.01, "and back")
	assert_eq(SideBat.path_direction(0.2), 1.0)
	assert_eq(SideBat.path_direction(1.2), -1.0)
	var segment := _segment()
	var bat := _spawn(segment, SideEnemy.Kind.BAT, 11) as SideBat
	var twin := _spawn(segment, SideEnemy.Kind.BAT, 11) as SideBat
	var lowest := -INF
	for i in 120:
		bat._physics_process(STEP)
		twin._physics_process(STEP)
		lowest = maxf(lowest, bat.position.y)
	assert_lte(lowest, bat._anchor.y + 0.01, "never sinks below its hover line")
	assert_eq(bat.position, twin.position, "same seed, same flight (host and replays)")
	assert_eq(bat.collision_mask, 0, "flies through the world")


func test_factory_makes_every_kind_with_its_plan_character() -> void:
	var segment := _segment()
	var classes := {SideEnemy.Kind.BAT: "SideBat", SideEnemy.Kind.SPIKE_HEDGEHOG: "SideSpikeHedgehog",
			SideEnemy.Kind.SHIELD_BEARER: "SideShieldBearer"}
	for kind in ALL_KINDS:
		var enemy := _spawn(segment, kind)
		assert_eq(enemy.kind, kind)
		if classes.has(kind):
			assert_eq(enemy.get_script().get_global_name(), StringName(classes[kind]))
		assert_not_null(enemy.health, "%s is set up" % SideEnemy.Kind.keys()[kind])
		assert_lte(enemy.health.get_max_health(), enemy.data.max_health, "weaker than its data")
		assert_eq(enemy.collision_layer, 0, "players walk through it")
		var character := SideEnemyKinds.char_for(kind)
		assert_eq(SideEnemyKinds.kind_for_char(character), kind, "plan character round trip")
	assert_eq(SideEnemyKinds.char_for(SideEnemy.Kind.SLIME), SideLayout.SLIME, "same as the plans today")
	assert_eq(SideEnemyKinds.char_for(SideEnemy.Kind.SKELETON), SideLayout.SKELETON)
	assert_eq(SideEnemyKinds.kind_for_char("#"), -1)
	for character: String in SideEnemyKinds.PLAN_CHARS:
		for taken in [SideLayout.ROCK, SideLayout.LEDGE, SideLayout.CRUMBLE, SideLayout.LADDER, SideLayout.START,
				SideLayout.DOOR, SideLayout.COIN, SideLayout.GOLDEN_COIN, SideLayout.SPIKES, SideLayout.CHEST,
				SideLayout.TORCH, SideLayout.TURRET, SideLayout.POOL, SideLayout.AIR]:
			assert_ne(character, taken, "no clash with the plan legend")


func test_new_kinds_draw_a_placeholder_until_their_art_lies_in_art() -> void:
	var segment := _segment()
	for kind in [SideEnemy.Kind.BAT, SideEnemy.Kind.SPIKE_HEDGEHOG, SideEnemy.Kind.SHIELD_BEARER]:
		var enemy := _spawn(segment, kind)
		var has_stand_in := enemy.get_node_or_null(^"Visual/Placeholder") != null
		assert_true(enemy.has_art != has_stand_in, "%s: art or a drawn stand-in" % SideEnemy.Kind.keys()[kind])


func test_chain_blocks_build_check_and_stamp_into_a_plan() -> void:
	var slimes := SideEnemyChain.row(SideEnemy.Kind.SLIME, 5)
	assert_eq(slimes.size(), 5)
	assert_true(SideEnemyChain.check(slimes).is_empty(), "a row of five slimes is a valid chain")
	assert_true(SideEnemyChain.can_stomp_through(slimes))
	var hurdle := SideEnemyChain.hurdle(2, 3)
	assert_true(SideEnemyChain.can_stomp_through(SideEnemyChain.bat_bridge(3)))
	assert_false(SideEnemyChain.can_stomp_through(hurdle))
	assert_false(SideEnemyChain.check(SideEnemyChain.row(SideEnemy.Kind.SLIME, 3, 1)).is_empty(), "too close")
	assert_false(SideEnemyChain.check(SideEnemyChain.row(SideEnemy.Kind.SLIME, 1)).is_empty(), "too short")

	var plan := SidePlans.build(&"crypt_steps")
	var origin := _floor_run(plan)
	var chain := SideEnemyChain.row(SideEnemy.Kind.SLIME, 3)
	assert_true(SideEnemyChain.fits(plan, chain, origin).is_empty(), "stands on the floor run")
	var errors := PackedStringArray()
	var rows := SideEnemyChain.stamp(plan.rows, chain, origin, errors)
	assert_true(errors.is_empty(), str(errors))
	var stamped := SideLayout.parse(rows, &"stamped")
	for placement in chain:
		assert_true(stamped.slimes.has(origin + placement.offset), "SideLayout reads the stamped slimes")
	assert_eq(plan.rows[origin.y][origin.x], SideLayout.AIR, "the plan itself stays untouched")
	var on_rock := PackedStringArray()
	SideEnemyChain.stamp(plan.rows, chain, Vector2i(0, 0), on_rock)
	assert_false(on_rock.is_empty(), "never onto rock")
	assert_false(SideEnemyChain.fits(plan, SideEnemyChain.bat_bridge(2), Vector2i(1, 1)).is_empty(),
			"a bat path through the ceiling does not fit")
