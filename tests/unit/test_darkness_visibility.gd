extends GutTest
## Enemies in the dark (DarknessVisibility): outside the local player's drawn light they fade to
## alpha 0, inside to 1, soft over a band; Finsternis draws a smaller circle; telegraphs show where
## they lie; bosses never hide. Optics only: nothing here touches AI or hits.

const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const BOSS: EnemyData = preload("res://enemies/data/boss_bone_king.tres")
const CRYPT: BiomeData = preload("res://dungeon/biomes/crypt.tres")
const EDGE := 200.0

var _old_save_path: String
var _old_phase: GameManager.Phase


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_darkness_visibility_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_old_phase = GameManager.get_phase()


func after_each() -> void:
	GameManager.set_phase(_old_phase)


# --- Pure decision ---

func _viewer() -> Array[Vector3]:
	var circles: Array[Vector3] = [LightQuery.circle(Vector2.ZERO, EDGE)]
	return circles


func test_inside_is_visible_outside_is_hidden() -> void:
	var circles := _viewer()
	assert_eq(DarknessVisibility.alpha_in_circles(Vector2(50, 0), circles), 1.0, "well inside")
	assert_eq(DarknessVisibility.alpha_in_circles(Vector2(600, 0), circles), 0.0, "far outside")
	assert_almost_eq(DarknessVisibility.alpha_in_circles(Vector2(EDGE, 0), circles), 0.5, 0.01, "half on the edge")
	var half_band := DarknessVisibility.FADE_BAND * 0.5
	assert_eq(DarknessVisibility.alpha_in_circles(Vector2(EDGE + half_band + 1.0, 0), circles), 0.0, "past the band")
	assert_eq(DarknessVisibility.alpha_in_circles(Vector2(EDGE - half_band - 1.0, 0), circles), 1.0, "before the band")


func test_any_light_shows() -> void:
	var circles := _viewer()
	circles.append(LightQuery.circle(Vector2(800, 0), 100.0))
	assert_eq(DarknessVisibility.alpha_in_circles(Vector2(820, 0), circles), 1.0, "a torch shows it")
	assert_eq(DarknessVisibility.alpha_in_circles(Vector2(500, 0), circles), 0.0, "between the lights stays dark")


func test_dim_lights_show_nothing() -> void:
	assert_eq(DarknessVisibility.source_edge(200.0, 0.1), 0.0, "a fading flash")
	assert_almost_eq(DarknessVisibility.source_edge(200.0, 1.0), 200.0 * DarknessVisibility.SOURCE_EDGE_SHARE, 0.01)


func test_player_edge_lies_at_half_light() -> void:
	var normal := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.COMBAT)
	var drawn := DungeonManager.VISION_RADIUS * normal.player_radius_scale
	var edge := DarknessVisibility.player_edge(drawn, normal.get_softness())
	assert_between(edge, 4.5 * 64.0, 5.5 * 64.0, "about five tiles, where the drawn light is half")


func test_finsternis_circle_is_smaller() -> void:
	var normal := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.COMBAT)
	var dark := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.COMBAT, 0, &"", true)
	var normal_edge := DarknessVisibility.player_edge(DungeonManager.VISION_RADIUS * normal.player_radius_scale, normal.get_softness())
	var dark_edge := DarknessVisibility.player_edge(DungeonManager.EXTRA_DARK_VISION_RADIUS * dark.player_radius_scale, dark.get_softness())
	assert_lt(dark_edge, normal_edge * 0.5, "Finsternis shows less than half as far")
	assert_gt(dark_edge, LightQuery.player_lit_radius(DungeonManager.EXTRA_DARK_VISION_RADIUS), "never less than the gameplay light")
	assert_gt(dark.ambient, normal.ambient, "and the outside is darker")


func test_bosses_and_objectives_never_hide() -> void:
	var boss := ENEMY_SCENE.instantiate() as Enemy
	boss.data = BOSS
	var normal := ENEMY_SCENE.instantiate() as Enemy
	normal.data = SKELETON
	var marked := ENEMY_SCENE.instantiate() as Enemy
	marked.data = SKELETON
	marked.set_meta(DarknessVisibility.ALWAYS_VISIBLE_META, true)
	assert_false(DarknessVisibility.can_hide(boss), "boss fight stays readable")
	assert_true(DarknessVisibility.can_hide(normal))
	assert_false(DarknessVisibility.can_hide(marked))
	for node in [boss, normal, marked]:
		node.free()


func test_champion_of_a_miniboss_room_never_hides() -> void:
	# Built outside the tree: only the room type above the enemy and its champion flag count.
	var duel := RoomController.new()
	duel.room_type = RoomSequence.RoomType.MINIBOSS
	var nest := RoomController.new()
	nest.room_type = RoomSequence.RoomType.COMBAT
	var duel_enemies := Node2D.new()
	duel.add_child(duel_enemies)
	var champion := ENEMY_SCENE.instantiate() as Enemy
	champion.data = SKELETON
	champion.apply_scaling(3, true)
	duel_enemies.add_child(champion)
	var escort := ENEMY_SCENE.instantiate() as Enemy
	escort.data = SKELETON
	escort.apply_scaling(3, false)
	duel_enemies.add_child(escort)
	var nest_champion := ENEMY_SCENE.instantiate() as Enemy
	nest_champion.data = SKELETON
	nest_champion.apply_scaling(3, true)
	nest.add_child(nest_champion)
	assert_true(champion.is_champion())
	assert_true(DarknessVisibility.is_in_miniboss_room(champion))
	assert_false(DarknessVisibility.can_hide(champion), "the staged duel stays readable, like a boss fight")
	assert_true(DarknessVisibility.can_hide(escort), "its escorts still hide")
	assert_true(DarknessVisibility.can_hide(nest_champion), "a champion of an elite nest in a combat room hides")
	duel.free()
	nest.free()


# --- Node: fading enemies ---

func _visibility(darkness := 1.0) -> DarknessVisibility:
	var node := DarknessVisibility.new()
	node.set_viewer(_viewer(), darkness)
	add_child_autofree(node)
	return node


func _enemy(data: EnemyData, pos: Vector2) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = data
	enemy.position = pos
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	return enemy


func _sprite_alpha(enemy: Enemy) -> float:
	return (enemy.get_node(^"Sprite") as CanvasItem).self_modulate.a


func test_enemy_outside_fades_to_zero_inside_stays() -> void:
	var visibility := _visibility()
	var near := _enemy(SKELETON, Vector2(80, 0))
	var far := _enemy(SKELETON, Vector2(600, 0))
	visibility.refresh(true)
	assert_eq(_sprite_alpha(near), 1.0, "inside: fully visible")
	assert_eq(_sprite_alpha(far), 0.0, "outside: unseen")
	assert_eq((far.get_node(^"HealthBar") as CanvasItem).modulate.a, 0.0, "health bar hides too")
	assert_eq(far.get_node(^"Sprite").modulate.a, SKELETON.idle_alpha, "the enemy's own sprite modulate stays untouched")


func test_fade_in_takes_about_fade_time() -> void:
	var visibility := _visibility()
	var enemy := _enemy(SKELETON, Vector2(600, 0))
	visibility.refresh(true)
	enemy.position = Vector2(60, 0)
	visibility.refresh(false)
	visibility._process(DarknessVisibility.FADE_TIME * 0.5)
	assert_almost_eq(visibility.get_enemy_alpha(enemy), 0.5, 0.05, "half way")
	visibility._process(DarknessVisibility.FADE_TIME * 0.6)
	assert_eq(visibility.get_enemy_alpha(enemy), 1.0, "in after the fade time")


func test_boss_stays_visible_in_the_dark() -> void:
	var visibility := _visibility()
	var boss := _enemy(BOSS, Vector2(900, 0))
	visibility.refresh(true)
	assert_eq(_sprite_alpha(boss), 1.0)
	assert_eq(visibility.get_enemy_alpha(boss), 1.0)


func test_bright_rooms_hide_nothing() -> void:
	var visibility := _visibility(DarknessVisibility.MIN_DARKNESS - 0.1)
	var far := _enemy(SKELETON, Vector2(900, 0))
	visibility.refresh(true)
	assert_eq(_sprite_alpha(far), 1.0, "special rooms and the village show everything")


func test_telegraph_in_the_light_shows_while_its_enemy_hides() -> void:
	var visibility := _visibility()
	var enemy := _enemy(SKELETON, Vector2(600, 0))
	visibility.refresh(true)
	var circle := enemy.get_node(^"TelegraphCircle") as Node2D
	circle.visible = true
	circle.global_position = Vector2(40, 0)
	visibility._process(0.01)
	assert_eq(circle.self_modulate.a, 1.0, "a leap circle on the lit floor is readable")
	circle.global_position = Vector2(620, 0)
	visibility._process(0.01)
	assert_eq(circle.self_modulate.a, 0.0, "in the dark it hides with its enemy")


func test_damage_numbers_only_where_visible() -> void:
	_visibility()
	assert_true(DarknessVisibility.shows_number_at(Vector2(30, 0)))
	assert_false(DarknessVisibility.shows_number_at(Vector2(700, 0)))


# --- With the overlay: the drawn light of the local player decides ---

func test_overlay_light_and_torch_show_enemies() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var overlay := VisionOverlay.new()
	add_child_autofree(overlay)
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = Vector2.ZERO
	overlay.bind_player(player)
	overlay.set_biome(CRYPT, true)
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, DungeonManager.VISION_RADIUS, true)
	await wait_process_frames(2)
	var visibility := overlay.get_darkness_visibility()
	var near := _enemy(SKELETON, Vector2(150, 0))
	var far := _enemy(SKELETON, Vector2(700, 0))
	visibility.refresh(true)
	assert_eq(visibility.get_enemy_alpha(near), 1.0, "in the player's circle")
	assert_eq(visibility.get_enemy_alpha(far), 0.0, "outside it")
	var torch := LightSource.new()
	torch.radius = 160.0
	add_child_autofree(torch)
	torch.global_position = Vector2(720, 0)
	visibility.refresh(true)
	assert_eq(visibility.get_enemy_alpha(far), 1.0, "a torch shows it")
	# Finsternis: the same spot near the player edge goes dark.
	var mid := _enemy(SKELETON, Vector2(250, 0))
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, DungeonManager.EXTRA_DARK_VISION_RADIUS, true)
	overlay.set_lighting(LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.COMBAT, 0, &"", true), true)
	await wait_process_frames(1)
	visibility.refresh(true)
	assert_eq(visibility.get_enemy_alpha(mid), 0.0, "Finsternis: smaller circle")


func test_enemy_glow_fades_with_the_enemy_and_shows_nothing() -> void:
	var visibility := _visibility()
	var elite := ENEMY_SCENE.instantiate() as Enemy
	elite.data = SKELETON
	elite.make_elite(Enemy.Elite.SWIFT)
	elite.position = Vector2(600, 0)
	add_child_autofree(elite)
	elite.set_physics_process(false)
	visibility.refresh(true)
	var glow := elite.get_node_or_null(^"Glow") as LightSource
	assert_not_null(glow, "elites carry a glow")
	assert_eq(glow.draw_factor, 0.0, "the glow is not drawn while the elite hides")
	assert_eq(visibility.get_enemy_alpha(elite), 0.0, "its own glow does not show it")
