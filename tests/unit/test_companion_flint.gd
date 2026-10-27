extends GutTest
## Flint as companion and light source (WK1, KONZEPT §7.1, D-194): where he hovers (FlintFollow),
## which mood shows (FlintMood), his art with placeholder and anchors (FlintArt), one Flint per player
## and the light circle centred on his flame for gameplay (LightQuery) and drawing (VisionOverlay).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DT := 1.0 / 60.0
const FLAME := Vector2(0.0, -25.0)
const NORMAL_LIT := 225.0

var _old_save_path: String
var _old_phase: GameManager.Phase


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_companion_flint_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_old_phase = GameManager.get_phase()


func after_each() -> void:
	GameManager.set_phase(_old_phase)


func _player(at := Vector2(400, 300)) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = at
	return player


## A Flint driven by hand (no engine frames in between).
func _flint(player: Player) -> FlintCompanion:
	var flint := FlintCompanion.attach_to(player)
	flint.set_process(false)
	return flint


func _walk(player: Player, flint: FlintCompanion, step: Vector2, frames: int) -> void:
	for i in frames:
		player.global_position += step
		flint._process(DT)


# --- FlintFollow (pure) ---

func test_flint_hovers_beside_the_player_away_from_the_aim() -> void:
	var side := FlintFollow.pick_side(1.0, Vector2.RIGHT)
	assert_eq(side, -1.0, "aiming right: FlintCompanion hovers left")
	assert_eq(FlintFollow.pick_side(side, Vector2(0.1, -1.0)), -1.0, "a small aim change keeps the side")
	assert_eq(FlintFollow.pick_side(side, Vector2.LEFT), 1.0)
	var offset := FlintFollow.target_offset(Vector2.ZERO, -1.0, NORMAL_LIT, FLAME)
	assert_lt(offset.x, 0.0, "on the left")
	assert_lt(offset.y, FlintFollow.FEET_Y, "floats over the floor")
	assert_lt(offset.length(), 64.0, "still near the player")


func test_flint_keeps_a_tile_of_distance_at_rest() -> void:
	# Feedback #c849884e: at rest Flint keeps about a tile away, diagonally behind the player.
	for i in 16:
		var aim := Vector2.RIGHT.rotated(TAU * i / 16.0)
		for start_side: float in [-1.0, 1.0]:
			var side := FlintFollow.pick_side(start_side, aim)
			var offset := FlintFollow.target_offset(Vector2.ZERO, side, NORMAL_LIT, FLAME, false, false, aim)
			var body := offset + FlintFollow.BODY_CENTER
			assert_gte(body.length(), FlintFollow.REST_MIN_DISTANCE, "a tile away aiming %s" % aim)
			assert_lte((offset + FLAME).length(), NORMAL_LIT * FlintFollow.LIGHT_REACH_SHARE + 0.01, "light stays fair")
	var level := FlintFollow.target_offset(Vector2.ZERO, 1.0, NORMAL_LIT, FLAME, false, false, Vector2.LEFT)
	assert_lt(level.y, FlintFollow.FEET_Y - FlintFollow.HOVER_HEIGHT, "behind the player (up) when aiming sideways")


func test_flint_rests_out_of_the_swing() -> void:
	# A 100 degree swing reaches 50 degrees to each side of the aim; Flint's body stays well outside.
	for i in 32:
		var aim := Vector2.RIGHT.rotated(TAU * i / 32.0)
		for start_side: float in [-1.0, 1.0]:
			var side := FlintFollow.pick_side(start_side, aim)
			var offset := FlintFollow.target_offset(Vector2.ZERO, side, NORMAL_LIT, FLAME, false, false, aim)
			var body := offset + FlintFollow.BODY_CENTER
			assert_gt(rad_to_deg(absf(aim.angle_to(body))), 55.0, "out of the swing aiming %s" % aim)


func test_flint_falls_in_behind_when_walking() -> void:
	# Feedback #7adeacba: walking, Flint flies behind and beside the player, not ahead of him.
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]:
		var side := FlintFollow.pick_side(1.0, direction)
		var beside := Vector2(FlintFollow.WALK_SIDE_DISTANCE * side, FlintFollow.FEET_Y - FlintFollow.HOVER_HEIGHT)
		var offset := FlintFollow.target_offset(direction * 300.0, side, NORMAL_LIT, FLAME, false, false, direction)
		var body := offset + FlintFollow.BODY_CENTER
		assert_lt(body.dot(direction), 0.0, "behind the player walking %s" % direction)
		var behind := -(offset - beside).dot(direction)
		assert_gt(behind, 10.0, "falls back walking %s" % direction)
		assert_lte(behind, FlintFollow.TRAIL_MAX + 0.01, "the spot trails at most TRAIL_MAX (%s)" % direction)


func test_flint_stays_on_the_leash_and_hurries_when_far() -> void:
	var far := FlintFollow.keep_on_leash(Vector2(300, -200))
	assert_almost_eq((far + FlintFollow.BODY_CENTER).length(), FlintFollow.LEASH_DISTANCE, 0.01)
	assert_eq(FlintFollow.keep_on_leash(Vector2(20, 0)), Vector2(20, 0), "near: unchanged")
	assert_lte((FlintFollow.settle(Vector2(0, 150), FLAME, 900.0) + FlintFollow.BODY_CENTER).length(), FlintFollow.LEASH_DISTANCE + 0.01)
	assert_eq(FlintFollow.follow_sharpness(0.0), FlintFollow.FOLLOW_SHARPNESS, "loose near his spot")
	assert_eq(FlintFollow.follow_sharpness(200.0), FlintFollow.CATCH_UP_SHARPNESS, "hurries far behind")
	assert_gt(FlintFollow.follow_sharpness(48.0), FlintFollow.FOLLOW_SHARPNESS)


func test_wall_helpers_keep_flint_on_the_players_side() -> void:
	var offset := Vector2(40, -18)
	var ray := FlintFollow.wall_ray(offset)
	assert_eq(ray[0], Vector2(0, FlintFollow.FEET_Y * 0.5), "from between centre and feet")
	assert_gt(ray[1].x, FlintFollow.ground_of(offset).x, "a margin beyond the floor under him")
	var alternatives := FlintFollow.wall_alternatives(offset)
	assert_eq(alternatives[0], Vector2(-40, -18), "the other side first")
	for alternative in alternatives:
		assert_false(FlintFollow.overlaps_player(alternative), "alternative %s clear of the player" % alternative)
	# A wall 20 px right of the ray start: the spot ends WALL_MARGIN short of it.
	var hit := ray[0] + (ray[1] - ray[0]).normalized() * 20.0
	var short := FlintFollow.short_of_wall(offset, hit)
	var ground := FlintFollow.ground_of(short)
	assert_almost_eq(ground.distance_to(ray[0]), 20.0 - FlintFollow.WALL_MARGIN, 0.01)


# --- FlintRoam (optics) ---

func test_roam_drifts_near_his_spot_and_comes_home() -> void:
	var roam := FlintRoam.new(7)
	var farthest := 0.0
	var moved := false
	for i in 1200:
		roam.update(DT, 1.0, Callable())
		farthest = maxf(farthest, roam.offset.length())
		moved = moved or roam.offset.length() > 4.0
	assert_true(moved, "he hovers about, not glued to his spot")
	assert_lte(farthest, FlintRoam.TRIP_RADIUS + 0.01, "never farther than a trip")
	for i in 30:
		roam.update(DT, 1.0, Callable(), true)
	assert_lt(roam.offset.length(), 1.0, "back at his spot for a cast")
	roam.reset(true)
	assert_eq(roam.offset, Vector2.ZERO)


func test_roam_respects_accept_calm_and_side_view() -> void:
	var stuck := FlintRoam.new(3)
	for i in 600:
		stuck.update(DT, 1.0, func(_goal: Vector2) -> bool: return false)
	assert_eq(stuck.offset, Vector2.ZERO, "nowhere allowed: he stays home")
	var asleep := FlintRoam.new(3)
	for i in 600:
		asleep.update(DT, 0.0, Callable())
	assert_eq(asleep.offset, Vector2.ZERO, "calm 0: no roaming")
	var side := FlintRoam.new(5)
	for i in 1200:
		side.update(DT, 1.0, Callable(), false, true)
		assert_lte(side.goal.y, 0.0, "side view: never down into the floor")


func test_flint_never_sits_on_the_walking_line() -> void:
	for i in 16:
		var direction := Vector2.RIGHT.rotated(TAU * i / 16.0)
		for side: float in [-1.0, 1.0]:
			for speed: float in [200.0, 80.0, 30.0]:
				var offset := FlintFollow.target_offset(direction * speed, side, NORMAL_LIT, FLAME, false, false, Vector2.DOWN)
				var body := offset + FlintFollow.BODY_CENTER
				assert_gte(absf(body.dot(direction.orthogonal())), FlintFollow.PATH_CLEARANCE - 0.01,
						"off the path walking %s at %s px/s" % [direction, speed])


func test_the_player_always_stands_in_his_own_light() -> void:
	for lit: float in [NORMAL_LIT, 115.0, 35.0]:
		for direction: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.UP, Vector2(-1, 1).normalized()]:
			for huddle: bool in [false, true]:
				var offset := FlintFollow.target_offset(direction * 200.0, 1.0, lit, FLAME, huddle, false, Vector2.LEFT)
				var light := offset + FLAME
				assert_lte(light.length(), maxf(FlintFollow.MIN_REACH, lit * FlintFollow.LIGHT_REACH_SHARE) + 0.01)
				if lit >= FlintFollow.MIN_REACH:
					assert_true(LightQuery.is_in_circles(Vector2.ZERO, [LightQuery.circle(light, lit)] as Array[Vector3]),
							"player inside his light (lit %s, %s)" % [lit, direction])


func test_scared_flint_huddles_closer() -> void:
	var calm := FlintFollow.target_offset(Vector2.RIGHT * 200.0, 1.0, NORMAL_LIT, FLAME)
	var scared := FlintFollow.target_offset(Vector2.RIGHT * 200.0, 1.0, NORMAL_LIT, FLAME, true)
	assert_lt((scared + FLAME).length(), (calm + FLAME).length())


func test_side_view_leads_only_sideways() -> void:
	var still := FlintFollow.target_offset(Vector2.ZERO, 1.0, NORMAL_LIT, FLAME, false, true)
	var falling := FlintFollow.target_offset(Vector2(0, 400), 1.0, NORMAL_LIT, FLAME, false, true)
	assert_eq(falling, still, "a jump or fall does not pull Flint up or down")


func test_flint_trails_and_snaps_after_a_jump() -> void:
	var stepped := FlintFollow.step(Vector2.ZERO, Vector2(40, 0), DT)
	assert_gt(stepped.x, 0.0)
	assert_lt(stepped.x, 40.0, "trails a little")
	assert_eq(FlintFollow.step(Vector2.ZERO, Vector2(1000, 0), DT), Vector2(1000, 0), "a teleport snaps")
	assert_eq(FlintFollow.estimate_velocity(Vector2(100, 0), Vector2(900, 0), DT), Vector2.ZERO)


# --- FlintMood (pure) ---

func test_mood_priorities() -> void:
	var facts := FlintMood.Facts.new()
	assert_eq(FlintMood.decide(facts), FlintMood.Mood.IDLE)
	facts.moving = true
	assert_eq(FlintMood.decide(facts), FlintMood.Mood.MOVE)
	facts.curious = true
	assert_eq(FlintMood.decide(facts), FlintMood.Mood.CURIOUS)
	facts.sleepy = true
	assert_eq(FlintMood.decide(facts), FlintMood.Mood.SLEEP)
	facts.afraid = true
	assert_eq(FlintMood.decide(facts), FlintMood.Mood.SCARED)
	facts.one_shot = FlintMood.Mood.JOY
	assert_eq(FlintMood.decide(facts), FlintMood.Mood.JOY)
	facts.downed = true
	assert_eq(FlintMood.decide(facts), FlintMood.Mood.SAD, "a downed player beats everything")


func test_stronger_one_shots_win() -> void:
	assert_true(FlintMood.replaces(-1, FlintMood.Mood.JOY))
	assert_true(FlintMood.replaces(FlintMood.Mood.JOY, FlintMood.Mood.PULSE))
	assert_false(FlintMood.replaces(FlintMood.Mood.PULSE, FlintMood.Mood.JOY))
	assert_true(FlintMood.replaces(FlintMood.Mood.JOY, FlintMood.Mood.JOY), "the same again restarts")
	assert_false(FlintMood.replaces(-1, FlintMood.Mood.SCARED), "held moods are no one-shots")


# --- FlintArt ---

func test_placeholder_is_the_same_figure_from_code() -> void:
	var art := FlintArt.placeholder()
	assert_true(art.is_placeholder)
	assert_eq(art.frame_size, Vector2i(32, 32))
	assert_eq(art.pivot, Vector2(16, 30))
	assert_true(art.faces_left, "the website figure looks to the left")
	for animation: StringName in FlintPlaceholder.ANIMATIONS:
		var spec: Array = FlintPlaceholder.ANIMATIONS[animation]
		assert_true(art.frames.has_animation(animation), String(animation))
		assert_eq(art.frames.get_frame_count(animation), int(spec[0]), "%s frames" % animation)
		assert_eq(art.frames.get_animation_speed(animation), float(spec[1]), "%s fps" % animation)
		assert_eq(art.frames.get_animation_loop(animation), bool(spec[2]), "%s loop" % animation)
		var texture := art.frames.get_frame_texture(animation, 0)
		assert_eq(Vector2i(texture.get_size()), Vector2i(32, 32))


func test_placeholder_flame_sits_above_the_head() -> void:
	var art := FlintArt.placeholder()
	var flame := art.get_anchor(FlintArt.ANCHOR_FLAME)
	var head := art.get_anchor(FlintArt.ANCHOR_HEAD)
	assert_true(Rect2(0, 0, 32, 32).has_point(flame), "flame inside the frame")
	assert_lt(flame.y, head.y, "flame above the wax")
	var image := art.frames.get_frame_texture(&"idle", 0).get_image()
	var flame_point := Vector2i(flame.floor())
	assert_gt(image.get_pixelv(flame_point).a, 0.5, "the flame anchor is on flame pixels")
	assert_eq(image.get_pixel(12, 24), FlintPlaceholder.OUTLINE, "outlined in #1c1a2b")


func test_anchor_offset_mirrors_and_scales() -> void:
	var art := FlintArt.placeholder()
	art._fixed_anchors[&"test"] = Vector2(12, 5)
	assert_eq(art.anchor_offset(&"test", &"idle", 0, true), Vector2(-8, -50), "the art looks left: as drawn")
	assert_eq(art.anchor_offset(&"test"), Vector2(8, -50), "looking right mirrors it")


func test_json_anchors_per_frame_and_fixed() -> void:
	var art := FlintArt.new()
	art._read_frame_anchors(&"idle", {"flame": [[8, 2], [9, 3]]})
	art._fixed_anchors[&"head"] = Vector2(8, 6)
	assert_eq(art.get_anchor(&"flame", &"idle", 1), Vector2(9, 3))
	assert_eq(art.get_anchor(&"flame", &"move", 0), Vector2(8, 2), "unknown animation uses idle")
	assert_eq(art.get_anchor(&"head", &"joy", 3), Vector2(8, 6), "fixed anchor for every frame")


func test_missing_art_folder_gives_the_placeholder() -> void:
	assert_true(FlintArt.load_from("res://art/companions/does_not_exist/").is_placeholder)
	var settings := FlintArt.read_settings("res://art/characters/npcs/chicken.json")
	assert_eq(settings.get("pivot"), [8.0, 14.0], "reads the shared JSON format")


# --- Node ---

func test_one_flint_per_player_as_child() -> void:
	var a := _player()
	var b := _player(Vector2(900, 300))
	var flint_a := FlintCompanion.attach_to(a)
	assert_eq(FlintCompanion.attach_to(a), flint_a, "attach_to is idempotent")
	var flint_b := FlintCompanion.attach_to(b)
	assert_ne(flint_a, flint_b)
	assert_eq(flint_a.get_parent(), a)
	assert_eq(FlintCompanion.of(b), flint_b)
	assert_eq(a.get_children().filter(func(n: Node) -> bool: return n is FlintCompanion).size(), 1)
	assert_null(FlintCompanion.of(_player(Vector2(0, 900))), "no Flint until attached")


func test_light_center_sits_at_the_player_even_with_flint() -> void:
	var player := _player()
	LightQuery.set_player_radius(player, 300.0)
	assert_eq(LightQuery.get_player_light_center(player), player.global_position, "without Flint: the player")
	var flint := _flint(player)
	var center := LightQuery.get_player_light_center(player)
	assert_eq(center, player.global_position, "D-212: the circle sits at the figure, not at Flint's flame")
	assert_ne(flint.get_light_center(), center, "Flint's flame hovers beside the player")
	var circles := LightQuery.player_circles(get_tree())
	assert_eq(Vector2(circles[0].x, circles[0].y), center, "gameplay counts the same circle")
	assert_true(LightQuery.is_lit(get_tree(), player.global_position), "the player stands in his light")


func test_flints_glow_is_optics_only() -> void:
	var player := _player()
	var flint := _flint(player)
	var glow := flint.get_glow()
	assert_not_null(glow, "his flame glows")
	assert_false(glow.counts_as_light, "the glow never counts as light (D-212)")
	assert_false(glow.is_in_group(LightSource.GAMEPLAY_GROUP))
	assert_true(glow.is_in_group(LightSource.GROUP), "drawn by the VisionOverlay")
	assert_almost_eq(glow.global_position.distance_to(flint.get_light_center()), 0.0, FlintCompanion.BOB_AMPLITUDE + 0.5, "at the flame")
	assert_eq(LightQuery.source_circles(get_tree()).size(), 0, "no gameplay circle from Flint")


func test_flint_trails_behind_when_the_player_walks() -> void:
	var player := _player()
	LightQuery.set_player_radius(player, 300.0)
	var flint := _flint(player)
	var still := flint.get_follow_position() - player.global_position
	_walk(player, flint, Vector2(3, 0), 90)
	var walking := flint.get_follow_position() - player.global_position
	assert_lt(walking.x, still.x - 10.0, "falls back against the walking direction")
	assert_lte(walking.x, 0.5, "never ahead of the player")
	assert_lte((walking + FlintFollow.BODY_CENTER).length(), FlintFollow.LEASH_DISTANCE + 0.5, "on the leash")
	assert_eq(flint.get_mood(), FlintMood.Mood.MOVE)
	player.global_position += Vector2(2000, 0)
	flint._process(DT)
	assert_lt(flint.get_follow_position().distance_to(player.global_position), 120.0, "teleport: FlintCompanion comes along")


func test_reactions_from_existing_events() -> void:
	var player := _player()
	var flint := _flint(player)
	flint._on_room_completed(2)
	flint._process(DT)
	assert_eq(flint.get_mood(), FlintMood.Mood.JOY, "room done: joy")
	for i in 60:
		flint._process(DT)
	assert_eq(flint.get_mood(), FlintMood.Mood.IDLE, "joy plays once")
	flint._on_blinded(1.0)
	flint._process(DT)
	assert_eq(flint.get_mood(), FlintMood.Mood.SCARED, "blinded: afraid")
	# He follows loosely (#7adeacba): give him a moment to come close.
	for i in 45:
		flint._process(DT)
	assert_lte((flint.get_light_center() - player.global_position).length(), FlintFollow.MIN_REACH + 20.0, "huddles close")


func test_flint_is_sad_while_his_player_is_down() -> void:
	var player := _player()
	var flint := _flint(player)
	player.health.take_damage(999.0)
	HitStop.reset()
	flint._process(DT)
	assert_eq(flint.get_mood(), FlintMood.Mood.SAD)


func test_flint_sleeps_in_the_village_when_the_player_rests() -> void:
	GameManager.set_phase(GameManager.Phase.VILLAGE)
	var player := _player()
	var flint := _flint(player)
	for i in int((FlintCompanion.SLEEP_DELAY + 0.5) / DT):
		flint._process(DT)
	assert_eq(flint.get_mood(), FlintMood.Mood.SLEEP)
	_walk(player, flint, Vector2(3, 0), 2)
	assert_ne(flint.get_mood(), FlintMood.Mood.SLEEP, "wakes up when the player moves")


func test_flint_is_afraid_in_dark_rooms() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var player := _player()
	LightQuery.set_player_radius(player, 190.0)
	var flint := _flint(player)
	flint._process(DT)
	assert_eq(flint.get_mood(), FlintMood.Mood.SCARED)


func test_flint_fades_while_covering_an_enemy() -> void:
	var player := _player()
	var flint := _flint(player)
	var enemy := Node2D.new()
	enemy.add_to_group(FlintCompanion.ENEMY_GROUP)
	add_child_autofree(enemy)
	enemy.global_position = flint.global_position + FlintFollow.BODY_CENTER
	for i in 30:
		flint._process(DT)
	var sprite := flint.get_sprite() as CanvasItem
	assert_almost_eq(sprite.modulate.a, FlintCompanion.COVERING_ALPHA, 0.01, "see-through over an enemy")


func test_overlay_draws_the_circle_around_the_player() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var overlay := VisionOverlay.new()
	add_child_autofree(overlay)
	var player := _player()
	var flint := _flint(player)
	overlay.bind_player(player)
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, DungeonManager.VISION_RADIUS, true)
	await wait_process_frames(2)
	var material := (overlay.get_child(0) as ColorRect).material as ShaderMaterial
	var drawn: Vector2 = material.get_shader_parameter(&"player_pos")
	var canvas := overlay.get_viewport().get_canvas_transform()
	assert_almost_eq(drawn.distance_to(canvas * player.global_position), 0.0, 2.0, "drawn where gameplay counts it: at the figure")
	assert_gt(drawn.distance_to(canvas * flint.get_light_center()), 2.0, "not at Flint's flame (D-212)")


func test_the_light_never_lags_behind_the_player() -> void:
	var player := _player()
	LightQuery.set_player_radius(player, 110.0)
	var flint := _flint(player)
	var lit := LightQuery.player_lit_radius(110.0)
	# A dash: 450 px/s for a while; the trailing candle keeps the player in his light.
	for i in 12:
		player.global_position += Vector2(7.5, 0)
		flint._process(DT)
		assert_lte(LightQuery.get_player_light_center(player).distance_to(player.global_position), lit, "dash frame %d" % i)
	# A fall reset or teleport, far or near: the light is there before Flint's next frame.
	for jump: Vector2 in [Vector2(-900, 300), Vector2(0, 150)]:
		player.global_position += jump
		assert_lte(LightQuery.get_player_light_center(player).distance_to(player.global_position), lit, "after a jump of %s" % jump)


# --- Picture clear of the player, drawn over the world (feedback #6f0d0ebf, #704b64b1) ---

## Gap between Flint's picture at offset and the player's picture (negative: they overlap).
func _picture_gap(offset: Vector2) -> float:
	var flint := Rect2(FlintFollow.FLINT_PICTURE.position + offset, FlintFollow.FLINT_PICTURE.size)
	var body := FlintFollow.PLAYER_PICTURE
	var gap_x := maxf(body.position.x - flint.end.x, flint.position.x - body.end.x)
	var gap_y := maxf(body.position.y - flint.end.y, flint.position.y - body.end.y)
	return maxf(gap_x, gap_y)


func test_the_rest_and_walking_spots_never_overlap_the_player() -> void:
	for lit: float in [NORMAL_LIT, 115.0, 35.0]:
		for huddle: bool in [false, true]:
			for i in 16:
				var direction := Vector2.RIGHT.rotated(TAU * i / 16.0)
				for speed: float in [0.0, 30.0, 60.0, 90.0, 120.0, 200.0]:
					for side: float in [-1.0, 1.0]:
						for aim: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1, -1).normalized()]:
							var offset := FlintFollow.target_offset(direction * speed, side, lit, FLAME, huddle, false, aim)
							assert_gte(_picture_gap(offset), FlintFollow.PICTURE_GAP - 0.01,
									"clear walking %s at %s (side %s, lit %s, huddle %s)" % [direction, speed, side, lit, huddle])
							assert_lte((offset + FLAME).length(), FlintFollow.light_reach(lit) + 0.01, "light stays in reach")


func test_walking_towards_his_side_flint_goes_round_the_player() -> void:
	# The bug of #704b64b1: aiming right Flint rests left; walking right his lead crossed the player.
	for walk: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var aim := Vector2.RIGHT
		var side := FlintFollow.pick_side(1.0, aim)
		var follow := FlintFollow.target_offset(Vector2.ZERO, side, NORMAL_LIT, FLAME, false, false, aim)
		var velocity := Vector2.ZERO
		var largest_step := 0.0
		# Start, walk 1.5 s, stop, turn round and walk back.
		for frame in 270:
			var moving := walk * 150.0 if frame < 90 else (Vector2.ZERO if frame < 150 else -walk * 150.0)
			# The player moves: Flint's offset falls behind by the same distance.
			follow -= moving * DT
			velocity = FlintFollow.estimate_velocity(velocity, moving * DT, DT)
			var target := FlintFollow.target_offset(velocity, side, NORMAL_LIT, FLAME, false, false, aim)
			var before := follow
			follow = FlintFollow.settle(FlintFollow.step_around(follow, target, DT), FLAME, NORMAL_LIT)
			largest_step = maxf(largest_step, follow.distance_to(before))
			assert_gte(_picture_gap(follow), FlintFollow.PICTURE_GAP - 0.01, "frame %d walking %s: off the player" % [frame, walk])
		assert_lt(largest_step, 16.0, "walking %s: he glides, he does not jump" % walk)


func test_flint_never_ends_up_on_his_player_in_the_game() -> void:
	var player := _player()
	LightQuery.set_player_radius(player, 300.0)
	var flint := _flint(player)
	for step: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3), Vector2(2, -2)]:
		for frame in 40:
			player.global_position += step
			flint._process(DT)
			assert_gte(_picture_gap(flint.get_follow_position() - player.global_position), FlintFollow.PICTURE_GAP - 0.01,
					"walking %s frame %d" % [step, frame])
		for frame in 30:
			flint._process(DT)
			assert_gte(_picture_gap(flint.get_follow_position() - player.global_position), FlintFollow.PICTURE_GAP - 0.01, "stopping")
	LightQuery.set_player_radius(player, 110.0)
	for frame in 30:
		flint._process(DT)
	assert_gte(_picture_gap(flint.get_follow_position() - player.global_position), FlintFollow.PICTURE_GAP - 0.01, "huddling in the dark")


func test_flint_is_drawn_over_props_but_under_what_covers_his_player() -> void:
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child_autofree(world)
	var player := PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector2(400, 300)
	var flint := _flint(player)
	flint._process(DT)
	var picture := flint.get_picture()
	assert_eq(picture.get_parent(), world, "his picture sorts in the player's world")
	assert_eq(flint.get_sprite().get_parent(), picture)
	# A grave stone standing a tile below the player (its base sorts there) no longer covers him.
	var grave_base := player.global_position.y + Player.FEET_OFFSET.y + 26.0
	assert_gt(picture.global_position.y, grave_base, "over a grave stone beside the player")
	assert_gt(picture.global_position.y, player.global_position.y, "over his player and figures beside him")
	# A house the player stands behind (its base at least two tiles below his feet) still covers him.
	assert_lt(picture.global_position.y, player.global_position.y + Player.FEET_OFFSET.y + 64.0, "under a house in front")
	# The rock over a gate's passage lies over the player and over Flint.
	assert_lt(picture.z_index, DoorView.LINTEL_Z)
	assert_almost_eq(flint.get_picture_position().distance_to(flint.get_follow_position()), 0.0, FlintCompanion.BOB_AMPLITUDE + 0.01,
			"drawn at his spot")


func test_flint_flies_over_the_world_into_the_corner() -> void:
	var player := _player()
	var flint := _flint(player)
	flint.set_excursion(Vector2(100, -80), 2.0, 0.5)
	assert_eq(flint.get_sprite().z_index, FlintCompanion.EXCURSION_Z)
	flint.clear_excursion()
	assert_eq(flint.get_sprite().z_index, 0)


func test_flints_picture_leaves_with_him() -> void:
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child_autofree(world)
	var player := PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	var flint := _flint(player)
	flint._process(DT)
	var picture := flint.get_picture()
	var other := Node2D.new()
	add_child_autofree(other)
	player.reparent(other)
	assert_false(picture.visible, "hidden while his player changes worlds")
	flint._process(DT)
	assert_eq(picture.get_parent(), other, "follows his player into the next world")
	assert_true(picture.visible)
	player.free()
	await wait_process_frames(1)
	assert_false(is_instance_valid(picture), "freed with Flint")


# --- Roaming, walls and the glow under tunnel rock (feedback 23.10.2026) ---

func test_roaming_flint_is_never_drawn_on_his_player() -> void:
	var player := _player()
	LightQuery.set_player_radius(player, 300.0)
	var flint := _flint(player)
	var lit := FlintFollow.light_reach(LightQuery.player_lit_radius(300.0))
	var roamed := 0.0
	for frame in 900:
		if frame % 300 < 120:
			player.global_position += Vector2(2, 1)
		flint._process(DT)
		var drawn := flint.position
		roamed = maxf(roamed, drawn.distance_to(flint.get_follow_position() - player.global_position))
		assert_gte(_picture_gap(drawn), FlintFollow.PICTURE_GAP - 0.01, "frame %d: drawn off the player" % frame)
		assert_lte((drawn + FlintFollow.BODY_CENTER).length(), FlintFollow.LEASH_DISTANCE + FlintRoam.TRIP_RADIUS, "frame %d" % frame)
		assert_lte((drawn + FLAME).length(), lit + FlintRoam.TRIP_RADIUS + 1.0, "frame %d: in sight" % frame)
	assert_gt(roamed, 3.0, "he roams about his spot")


func test_flint_stays_on_the_players_side_of_a_wall() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var player := PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector2(400, 300)
	LightQuery.set_player_radius(player, 300.0)
	# A wall right beside the player, on both sides (a narrow north-south tunnel).
	for x: float in [400.0 + 22.0, 400.0 - 22.0]:
		var wall := StaticBody2D.new()
		wall.collision_layer = PhysicsLayers.WORLD
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(8, 400)
		shape.shape = box
		wall.add_child(shape)
		world.add_child(wall)
		wall.global_position = Vector2(x + signf(x - 400.0) * 4.0, 300)
	await wait_physics_frames(2)
	var flint := _flint(player)
	flint.snap()
	for frame in 120:
		flint._process(DT)
	var spot := flint.get_follow_position() - player.global_position
	assert_lt(absf(FlintFollow.ground_of(spot).x), 22.0, "between the walls, not inside or behind them (%s)" % spot)


func test_flints_glow_goes_out_under_tunnel_rock() -> void:
	var player := _player()
	var flint := _flint(player)
	flint._process(DT)
	var glow := flint.get_glow()
	# Full strength at the aura's breath (D-217: the glow breathes); the breath stands still here.
	var full := FlintCompanion.GLOW_INTENSITY * lerpf(FlintCompanion.GLOW_BREATH_LOW, 1.0, FlintShine.breath(flint.get_aura().time))
	assert_almost_eq(glow.intensity, full, 0.01, "in the open: full glow")
	var view := DoorView.new()
	add_child_autofree(view)
	# The passage's hidden stretch right where Flint's flame is.
	view.global_position = glow.global_position - Vector2(32, 96)
	view._passage_rects.append(Rect2(Vector2.ZERO, Vector2(64, 64)))
	view._passage_rects.append(Rect2(Vector2(0, 64), Vector2(64, 64)))
	view.add_to_group(DoorView.TUNNEL_GROUP)
	assert_eq(FlintCompanion.roof_distance(get_tree(), glow.global_position), 0.0, "under the rock")
	for i in 30:
		flint._process(DT)
	assert_almost_eq(glow.intensity, 0.0, 0.01, "no glow through the tunnel rock (#118a38da)")
	view.remove_from_group(DoorView.TUNNEL_GROUP)
	for i in 30:
		flint._process(DT)
	assert_almost_eq(glow.intensity, full, 0.01, "back in the open")
	assert_eq(FlintCompanion.roof_distance(get_tree(), Vector2.ZERO), INF, "no tunnel: no roof")
