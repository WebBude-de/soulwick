extends GutTest
## Player camera M4 (Makeover 3 §9): zoom 1.25× in the dungeon, 1.0× in boss rooms and the village,
## a short pull-out to 1.0× on entering a room (held while a room intro swings the camera), dead
## zone and lead in the walking direction, limits, shake the same on screen at every zoom, and the
## coop hook camera_targets(). The HUD is a CanvasLayer and never scales with the camera.
## Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_camera.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0

var _old_save_path: String


## Stand-in for DungeonManager: announces rooms.
class FakeWorld:
	extends Node2D
	signal room_activated(room: Node)


## Stand-in for a RoomController (type for the zoom, fight state for RoomIntro).
class FakeRoom:
	extends Node2D
	var room_type := RoomSequence.RoomType.COMBAT
	var room_index := 5
	var arena := Rect2()

	func get_arena() -> Rect2:
		return arena

	func is_encounter_started() -> bool:
		return false


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()
	CameraShake.enabled = true


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## A camera on a plain carrier inside world (null: straight under the test), driven by hand.
func _rig(world: Node = null, at := Vector2(1000, 600)) -> CameraRig:
	var carrier := Node2D.new()
	carrier.position = at
	var rig := CameraRig.new()
	rig.name = "Camera2D"
	carrier.add_child(rig)
	if world == null:
		add_child_autofree(carrier)
	else:
		world.add_child(carrier)
	rig.set_process(false)
	rig.make_current()
	return rig


func _run(rig: CameraRig, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		rig._process(STEP)


func _carrier(rig: CameraRig) -> Node2D:
	return rig.get_parent() as Node2D


## Centre of the view as Camera2D computes it (limits, offset).
func _view(rig: CameraRig) -> Vector2:
	rig.force_update_scroll()
	return rig.get_screen_center_position()


# --- CameraFollow: dead zone and lead ---

func test_dead_zone_keeps_the_view_still() -> void:
	var follow := CameraFollow.new()
	follow.reset(Vector2.ZERO)
	var inside := CameraFollow.DEAD_ZONE * 0.5 - Vector2(4, 4)
	for i in roundi((CameraFollow.RECENTER_DELAY - 0.05) / STEP):
		follow.step(inside, STEP, Vector2.ZERO)
	assert_eq(follow.anchor, Vector2.ZERO, "inside the dead zone the anchor stays")
	assert_almost_eq(follow.center, Vector2.ZERO, Vector2(0.5, 0.5), "the view does not move")
	for i in roundi(5.0 / STEP):
		follow.step(inside, STEP, Vector2.ZERO)
	assert_almost_eq(follow.center, inside, Vector2(2, 2), "standing still it slowly centres again")
	follow.step(Vector2(300, 0), STEP, Vector2(300, 0))
	assert_almost_eq(follow.anchor.x, 300.0 - CameraFollow.DEAD_ZONE.x * 0.5, 0.01, "past the edge the box is pushed")


func test_dead_zone_maths() -> void:
	var half := Vector2(32, 24)
	assert_eq(CameraFollow.follow_dead_zone(Vector2.ZERO, Vector2(20, -20), half), Vector2.ZERO)
	assert_eq(CameraFollow.follow_dead_zone(Vector2.ZERO, Vector2(50, -50), half), Vector2(18, -26))


func test_values_follow_the_design() -> void:
	assert_eq(CameraFollow.DEAD_ZONE, Vector2(64, 48), "Makeover 3 §9: dead zone 64x48")
	assert_lte(CameraFollow.LEAD.x, 48.0, "lead at most about 48 px")
	assert_lte(CameraFollow.LEAD.y, 48.0)


func test_lead_builds_slowly_and_never_overshoots() -> void:
	var follow := CameraFollow.new()
	follow.reset(Vector2.ZERO)
	var point := Vector2.ZERO
	var velocity := Vector2(220, 0)
	var previous := 0.0
	var monotonic := true
	for i in roundi(1.0 / STEP):
		point += velocity * STEP
		follow.step(point, STEP, velocity)
		monotonic = monotonic and follow.lead.x >= previous - 0.0001
		previous = follow.lead.x
	assert_almost_eq(follow.lead.x, CameraFollow.LEAD_RATE * 1.0, 0.5, "slowly: after 1 s only half the lead")
	for i in roundi(3.0 / STEP):
		point += velocity * STEP
		follow.step(point, STEP, velocity)
		monotonic = monotonic and follow.lead.x >= previous - 0.0001
		previous = follow.lead.x
	assert_true(monotonic, "the lead only grows while walking one way")
	assert_almost_eq(follow.lead.x, CameraFollow.LEAD.x, 0.01, "full lead, never more")
	assert_almost_eq(follow.lead.y, 0.0, 0.01)
	assert_gt(follow.center.x, point.x - CameraFollow.DEAD_ZONE.x, "the view stays close to the player")
	# A short stop changes nothing, a longer one glides the view onto the player.
	for i in roundi((CameraFollow.RECENTER_DELAY - 0.1) / STEP):
		follow.step(point, STEP, Vector2.ZERO)
	assert_almost_eq(follow.lead.x, CameraFollow.LEAD.x, 0.01, "short stop: lead kept")
	for i in roundi(8.0 / STEP):
		follow.step(point, STEP, Vector2.ZERO)
	assert_almost_eq(follow.lead.length(), 0.0, 0.5, "long stop: lead gone")
	assert_almost_eq(follow.center, point, Vector2(1, 1), "and the view is on the player")


func test_turning_does_not_swing_the_view_back() -> void:
	var follow := CameraFollow.new()
	follow.reset(Vector2.ZERO)
	var point := Vector2.ZERO
	for i in roundi(3.0 / STEP):
		point += Vector2(220, 0) * STEP
		follow.step(point, STEP, Vector2(220, 0))
	# Turn around: the view must only ever move with the player (left), never back to the right.
	var previous := follow.center.x
	var swung_back := 0.0
	for i in roundi(3.0 / STEP):
		point += Vector2(-220, 0) * STEP
		follow.step(point, STEP, Vector2(-220, 0))
		swung_back = maxf(swung_back, follow.center.x - previous)
		previous = follow.center.x
	assert_lt(swung_back, 0.01, "no swing back on a turn")


## Playtest: strafing back and forth must keep the picture calm. The player swings 88 px (0.4 s
## each way); once settled, the view swings less than half of that.
func test_back_and_forth_keeps_the_view_calm() -> void:
	var follow := CameraFollow.new()
	follow.reset(Vector2.ZERO)
	var point := Vector2.ZERO
	var lowest := INF
	var highest := -INF
	for leg in 16:
		var velocity := Vector2(220 if leg % 2 == 0 else -220, 0)
		for i in roundi(0.4 / STEP):
			point += velocity * STEP
			follow.step(point, STEP, velocity)
			if leg >= 2:
				lowest = minf(lowest, follow.center.x)
				highest = maxf(highest, follow.center.x)
			assert_almost_eq(follow.center.y, 0.0, 0.01)
	assert_lt(highest - lowest, 40.0, "back and forth: at most 40 px camera swing (player: 88 px)")


func test_lead_derived_from_positions_without_velocity() -> void:
	var follow := CameraFollow.new()
	follow.reset(Vector2.ZERO)
	var point := Vector2.ZERO
	for i in roundi(3.0 / STEP):
		point += Vector2(0, 200) * STEP
		follow.step(point, STEP)
	assert_almost_eq(follow.lead.y, CameraFollow.LEAD.y, 0.5, "vertical lead from the movement")


func test_big_jump_snaps() -> void:
	var follow := CameraFollow.new()
	follow.reset(Vector2.ZERO)
	follow.step(Vector2(5000, 2000), STEP, Vector2.ZERO)
	assert_eq(follow.center, Vector2(5000, 2000), "teleport: no gliding across the map")
	assert_eq(follow.lead, Vector2.ZERO)


func test_centred_lets_go_of_dead_zone_and_lead() -> void:
	var follow := CameraFollow.new()
	follow.reset(Vector2.ZERO)
	var point := Vector2.ZERO
	for i in 120:
		point += Vector2(200, 0) * STEP
		follow.step(point, STEP, Vector2(200, 0))
	for i in 90:
		follow.step(point, STEP, Vector2.ZERO, true)
	assert_almost_eq(follow.center, point, Vector2(1, 1), "aimed by someone else: back on the point")


# --- CameraZoom ---

func test_zoom_per_room_type() -> void:
	assert_eq(CameraZoom.DUNGEON, 1.45, "TESTWERT D-205")
	assert_eq(CameraZoom.for_room_type(RoomSequence.RoomType.COMBAT), CameraZoom.DUNGEON)
	assert_eq(CameraZoom.for_room_type(RoomSequence.RoomType.SPECIAL), CameraZoom.DUNGEON)
	assert_eq(CameraZoom.for_room_type(RoomSequence.RoomType.BOSS), 1.0, "boss rooms 1.0")
	assert_eq(CameraZoom.for_room_type(RoomSequence.RoomType.CAMPFIRE), CameraZoom.CAMPFIRE)


func test_pull_out_and_back() -> void:
	var zoom := CameraZoom.new()
	zoom.set_base(CameraZoom.DUNGEON, true)
	zoom.pull_out()
	var lowest := INF
	var t := 0.0
	var previous := zoom.value
	var biggest_step := 0.0
	while t < CameraZoom.PULL_OUT_TIME + CameraZoom.PULL_OUT_HOLD:
		var value := zoom.step(STEP)
		biggest_step = maxf(biggest_step, absf(value - previous))
		previous = value
		lowest = minf(lowest, value)
		t += STEP
	assert_almost_eq(lowest, CameraZoom.OVERVIEW, 0.001, "out to 1.0×")
	assert_almost_eq(zoom.value, CameraZoom.OVERVIEW, 0.001, "held about one second")
	for i in roundi((CameraZoom.PULL_IN_TIME + 0.1) / STEP):
		var value := zoom.step(STEP)
		biggest_step = maxf(biggest_step, absf(value - previous))
		previous = value
	assert_almost_eq(zoom.value, CameraZoom.DUNGEON, 0.001, "back to the dungeon zoom")
	# At most 8 % of the way per frame step (was 0.02 for the old 1.0 -> 1.25 range).
	assert_lt(biggest_step, 0.08 * (CameraZoom.DUNGEON - CameraZoom.OVERVIEW), "soft, never a jump")


func test_pull_out_waits_for_hold_but_not_forever() -> void:
	var zoom := CameraZoom.new()
	zoom.set_base(CameraZoom.DUNGEON, true)
	zoom.pull_out()
	for i in roundi(2.5 / STEP):
		zoom.step(STEP, true)
	assert_true(zoom.is_pulled_out(), "an intro still swinging keeps the overview")
	for i in roundi(CameraZoom.PULL_OUT_MAX / STEP):
		zoom.step(STEP, true)
	assert_false(zoom.is_pulled_out(), "never longer than PULL_OUT_MAX")


func test_no_pull_out_in_boss_rooms() -> void:
	var zoom := CameraZoom.new()
	zoom.set_base(CameraZoom.BOSS, true)
	zoom.pull_out()
	assert_false(zoom.is_pulled_out())
	zoom.step(STEP)
	assert_eq(zoom.value, 1.0)


# --- CameraRig ---

func test_rig_rests_at_village_zoom_outside_the_dungeon() -> void:
	var rig := _rig()
	_run(rig, 0.1)
	assert_eq(rig.zoom, Vector2.ONE * CameraZoom.VILLAGE)
	assert_false(rig.position_smoothing_enabled, "the rig smooths itself")


func test_rig_follows_rooms_of_the_dungeon() -> void:
	var world: FakeWorld = add_child_autofree(FakeWorld.new())
	var rig := _rig(world)
	_run(rig, 0.1)
	assert_eq(rig.zoom, Vector2.ONE * CameraZoom.DUNGEON, "dungeon: 1.25× from the start")
	var room: FakeRoom = autofree(FakeRoom.new())
	world.room_activated.emit(room)
	_run(rig, CameraZoom.PULL_OUT_TIME + 0.2)
	assert_almost_eq(rig.zoom.x, CameraZoom.OVERVIEW, 0.001, "entering: overview")
	_run(rig, CameraZoom.PULL_OUT_HOLD + CameraZoom.PULL_IN_TIME + 0.2)
	assert_almost_eq(rig.zoom.x, CameraZoom.DUNGEON, 0.001, "then close again")
	var boss: FakeRoom = autofree(FakeRoom.new())
	boss.room_type = RoomSequence.RoomType.BOSS
	world.room_activated.emit(boss)
	_run(rig, CameraZoom.CHANGE_TIME + 0.1)
	assert_almost_eq(rig.zoom.x, CameraZoom.BOSS, 0.001, "boss room 1.0×")
	_run(rig, 3.0)
	assert_almost_eq(rig.zoom.x, CameraZoom.BOSS, 0.001, "and it stays there")


func test_view_follows_carrier() -> void:
	var rig := _rig()
	_run(rig, 0.05)
	assert_almost_eq(_view(rig), Vector2(1000, 600), Vector2(0.5, 0.5), "starts on the carrier")
	_carrier(rig).position += Vector2(400, 0)
	_run(rig, 0.1)
	var view := _view(rig)
	assert_between(view.x, 1000.5, 1399.0, "glides, no jump")
	_run(rig, 8.0)
	assert_almost_eq(_view(rig), Vector2(1400, 600), Vector2(2, 2), "standing, the view settles on the carrier")


func test_overview_leans_into_the_room() -> void:
	var world: FakeWorld = add_child_autofree(FakeWorld.new())
	var rig := _rig(world, Vector2(1000, 600))
	_run(rig, 0.1)
	var room: FakeRoom = autofree(FakeRoom.new())
	room.arena = Rect2(Vector2(1000, 200), Vector2(1200, 800))
	world.room_activated.emit(room)
	_run(rig, CameraZoom.PULL_OUT_TIME + 0.6)
	var view := _view(rig)
	assert_gt(view.x, 1000.0 + CameraRig.OVERVIEW_LEAN * 0.7, "the overview looks into the room")
	assert_lte((view - Vector2(1000, 600)).length(), CameraRig.OVERVIEW_LEAN + 1.0, "but only a bit")
	_run(rig, CameraZoom.PULL_OUT_HOLD + CameraZoom.PULL_IN_TIME + 2.0)
	assert_almost_eq(_view(rig), Vector2(1000, 600), Vector2(2, 2), "back on the player")


func test_view_respects_limits() -> void:
	var rig := _rig(null, Vector2(100, 100))
	rig.limit_left = 0
	rig.limit_top = 0
	rig.limit_right = 2000
	rig.limit_bottom = 1200
	_run(rig, 0.5)
	var half := rig.get_viewport_rect().size / rig.zoom * 0.5
	# A view larger than the map (test window taller than 16:9, aspect "expand") is centred.
	half = Vector2(minf(half.x, 1000.0), minf(half.y, 600.0))
	assert_almost_eq(_view(rig), half, Vector2(0.5, 0.5), "never outside the map")
	assert_almost_eq(rig.clamp_to_limits(Vector2(100, 100)), half, Vector2(0.01, 0.01), "same clamp as Camera2D")


func test_room_intro_swing_still_reaches_the_goal() -> void:
	var world: FakeWorld = add_child_autofree(FakeWorld.new())
	var rig := _rig(world)
	_run(rig, 0.1)
	# The player walked in from the left: dead zone and lead are off the player.
	for i in 60:
		_carrier(rig).position += Vector2(4, 0)
		rig._process(STEP)
	var player_at := _carrier(rig).global_position
	# RoomIntro moves the node's position (PAN), the rig lets go of dead zone and lead meanwhile.
	rig.position = Vector2(220, 0)
	_run(rig, 1.0)
	assert_almost_eq(_view(rig), player_at + Vector2(220, 0), Vector2(1, 1), "the swing shows the goal exactly")
	rig.position = Vector2.ZERO
	_run(rig, 1.0)
	assert_almost_eq(_view(rig), player_at, Vector2(1, 1), "and comes home")


func test_overview_held_during_full_intro() -> void:
	var world: FakeWorld = add_child_autofree(FakeWorld.new())
	var player: Player = PLAYER_SCENE.instantiate()
	world.add_child(player)
	var rig := player.get_node("Camera2D") as CameraRig
	rig.make_current()
	var room := FakeRoom.new()
	world.add_child(room)
	var goal := RoomObjective.attach(room, RoomObjective.create(RoomObjective.FLAME))
	goal.goal_args = [40]
	var intro := RoomIntro.start(room, goal, player.global_position + Vector2(300, 0), RoomIntro.Style.FULL)
	world.room_activated.emit(room)
	await _until_phase(intro, RoomIntro.Phase.PAN)
	await wait_seconds(RoomIntro.PAN_MOVE_TIME + 0.1)
	assert_almost_eq(rig.zoom.x, CameraZoom.OVERVIEW, 0.001, "overview while the camera shows the goal")
	assert_gt(rig.position.x, 100.0, "the intro swing still moves the camera")
	await _until_phase(intro, RoomIntro.Phase.BANNER)
	assert_almost_eq(rig.zoom.x, CameraZoom.OVERVIEW, 0.001, "still out with the banner")
	await _until_phase(intro, RoomIntro.Phase.COUNTDOWN)
	await wait_seconds(CameraZoom.PULL_IN_TIME + 0.2)
	assert_eq(intro.phase, RoomIntro.Phase.COUNTDOWN)
	assert_almost_eq(rig.zoom.x, CameraZoom.DUNGEON, 0.001, "close again with the countdown")
	intro.skip()
	await wait_seconds(RoomIntro.CAMERA_RETURN_TIME + 0.1)
	assert_eq(rig.position, Vector2.ZERO, "intro camera home")
	player.queue_free()


func _until_phase(intro: RoomIntro, phase: RoomIntro.Phase) -> void:
	for i in 600:
		if not is_instance_valid(intro) or intro.phase >= phase:
			return
		await get_tree().process_frame


func test_shake_same_on_screen_at_every_zoom() -> void:
	var world: FakeWorld = add_child_autofree(FakeWorld.new())
	var rig := _rig(world)
	_run(rig, 0.1)
	var base_offset := rig.offset
	var biggest := 0.0
	for i in 30:
		rig.add_trauma(1.0)
		rig._process(STEP)
		biggest = maxf(biggest, (rig.offset - base_offset).length())
	assert_gt(biggest, 0.0, "it shakes")
	assert_lt(biggest, CameraRig.MAX_OFFSET * sqrt(2.0) / rig.zoom.x + 0.01, "world shake divided by the zoom")


func test_coop_hook_targets() -> void:
	var rig := _rig()
	var targets := rig.camera_targets()
	assert_eq(targets.size(), 1)
	assert_eq(targets[0], _carrier(rig), "today: the player carrying the camera")
	var a: Node2D = add_child_autofree(Node2D.new())
	var b: Node2D = add_child_autofree(Node2D.new())
	a.global_position = Vector2(0, 0)
	b.global_position = Vector2(400, 200)
	rig.set_targets_provider(func() -> Array: return [a, b])
	assert_eq(rig.camera_targets().size(), 2)
	rig.snap_to_targets()
	assert_eq(rig.get_follow().center, Vector2(200, 100), "group middle")
	rig.set_targets_provider(Callable())
	assert_eq(rig.camera_targets()[0], _carrier(rig))


func test_hud_is_not_scaled() -> void:
	var world: FakeWorld = add_child_autofree(FakeWorld.new())
	var rig := _rig(world)
	var layer: CanvasLayer = add_child_autofree(CanvasLayer.new())
	_run(rig, 0.1)
	assert_almost_eq(rig.zoom.x, CameraZoom.DUNGEON, 0.0001)
	assert_eq(layer.get_final_transform().get_scale(), Vector2.ONE, "CanvasLayers ignore the camera zoom")
