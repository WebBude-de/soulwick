extends GutTest
## Dying enemies always disappear: a death inside the enemy's own physics frame (bomber
## self-destruct) keeps the death animation, and a death animation that never ends (looping
## foreign art) is cut off after its planned length, so no corpse stays in the room.

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const PLAYER_SCENE_PATH := "res://player/player.tscn"
const TEST_SAVE_PATH := "user://test_enemy_death.cfg"
## Death animation + dissolve must be over by then.
const MAX_CORPSE_TIME := 1.5

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func after_each() -> void:
	for node in get_children():
		if node is Enemy or node is Projectile or node is Blast:
			node.queue_free()


func _spawn(path: String, room := 6) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load(path)
	enemy.apply_scaling(room, false)
	add_child(enemy)
	return enemy


## Seconds until the enemy is freed (or limit when it is still there).
func _time_until_freed(enemy: Enemy, limit: float) -> float:
	var time := 0.0
	while is_instance_valid(enemy) and time < limit:
		await wait_physics_frames(1)
		time += get_physics_process_delta_time()
	return time


func _looping_death_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	frames.add_frame(&"default", texture)
	for animation: StringName in [&"idle", &"walk", &"death"]:
		frames.add_animation(animation)
		frames.set_animation_speed(animation, 8.0)
		for i in 4:
			frames.add_frame(animation, texture)
	frames.set_animation_loop(&"death", true)
	return frames


func test_death_animation_time() -> void:
	assert_eq(Enemy.death_animation_time(null), 0.0)
	var frames := _looping_death_frames()
	assert_almost_eq(Enemy.death_animation_time(frames), 0.5, 0.001, "4 frames at 8 fps")
	frames.set_frame(&"death", 0, frames.get_frame_texture(&"death", 0), 3.0)
	assert_almost_eq(Enemy.death_animation_time(frames), 0.75, 0.001, "frame durations count")
	frames.remove_animation(&"death")
	assert_eq(Enemy.death_animation_time(frames), 0.0, "no death animation")


func test_bomber_self_destruct_disappears() -> void:
	var player: Player = add_child_autofree((load(PLAYER_SCENE_PATH) as PackedScene).instantiate())
	player.health.reset(99999.0)
	var bomber := _spawn("res://enemies/data/bomber.tres")
	bomber.global_position = player.global_position + Vector2(36, 0)
	watch_signals(bomber)
	var died := [false]
	bomber.died.connect(func(_e: Enemy) -> void: died[0] = true)
	var time := 0.0
	while not died[0] and time < 5.0:
		await wait_physics_frames(1)
		time += get_physics_process_delta_time()
	assert_true(died[0], "the bomber blew itself up")
	if not died[0]:
		return
	assert_signal_emitted_with_parameters(bomber, "ability_used", [bomber, &"self_destruct"])
	await wait_physics_frames(2)
	if is_instance_valid(bomber):
		assert_true(bomber.is_dead())
		var sprite := bomber.get_node("Sprite") as AnimatedSprite2D
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"death"):
			assert_eq(sprite.animation, &"death", "idle does not overwrite the death animation")
	var gone := await _time_until_freed(bomber, MAX_CORPSE_TIME + 1.0)
	assert_false(is_instance_valid(bomber), "freed")
	assert_lte(gone, MAX_CORPSE_TIME, "freed after %.2f s" % gone)


func test_looping_death_animation_still_ends() -> void:
	var slime := _spawn("res://enemies/data/slime.tres")
	await wait_physics_frames(1)
	var sprite := slime.get_node("Sprite") as AnimatedSprite2D
	sprite.sprite_frames = _looping_death_frames()
	slime.health.take_damage(INF)
	await wait_physics_frames(3)
	assert_true(is_instance_valid(slime) and slime.is_dead())
	if is_instance_valid(slime):
		assert_eq(sprite.animation, &"death", "still dying, not idle")
	var gone := await _time_until_freed(slime, MAX_CORPSE_TIME + 1.0)
	assert_false(is_instance_valid(slime), "freed although the animation loops")
	assert_lte(gone, MAX_CORPSE_TIME, "freed after %.2f s" % gone)
