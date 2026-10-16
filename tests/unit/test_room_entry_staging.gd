extends GutTest
## Playtest 15.10.2026 #9 and #14 (G4). #9: the contents of a special room (merchant, weapons,
## fountain, altar, portal) stand in the room as soon as it is prepared and wake up on entry (offers,
## usable interactables); nothing pops up. #14: entering a room only starts it; the next room is built
## in the following frames (DungeonManager._pending), in the same order and with the same dungeon RNG
## as all at once; asking for it builds the rest right away (finish_preparing). The veil texture is
## built with a separable blur that gives the same values as the plain 2D mean.
## Feedback 16.10.2026 (still a hitch on entering): the room's tiles are painted a frame after it was
## built (RoomTiles.hold_paint), the veil and the seam get a frame each; the painted cells are the
## same as when everything happens at once.

const DUNGEON: PackedScene = preload("res://dungeon/dungeon.tscn")
const ROOM_BASE := "res://dungeon/rooms/room_base.tscn"
const SEEDS: Array[int] = [4247586090614500065, 777]
const SLOTS := 12

var _old_save_path: String
var _old_phase := 0


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_entry_staging_save.cfg"
	_old_phase = GameManager.get_phase()


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.DEATH)
	GameManager.set_phase(_old_phase as GameManager.Phase)
	SaveManager.save_path = _old_save_path


func _dungeon(seed_value: int) -> DungeonManager:
	var dungeon := DUNGEON.instantiate() as DungeonManager
	dungeon.seed_value = seed_value
	add_child(dungeon)
	await wait_physics_frames(2)
	return dungeon


func _drop(dungeon: DungeonManager) -> void:
	remove_child(dungeon)
	dungeon.free()
	await wait_physics_frames(1)


func _contents(room: RoomController) -> Array[SpecialContent]:
	var found: Array[SpecialContent] = []
	for child in room.get_children():
		if child is SpecialContent:
			found.append(child)
	return found


func _interactables(node: Node) -> Array[Interactable]:
	var found: Array[Interactable] = []
	for child in node.find_children("*", "Interactable", true, false):
		found.append(child as Interactable)
	return found


## Rooms 2 and 3 entered; slot 4 prepared as a special room of the given type.
func _special_room(dungeon: DungeonManager, special_type: int) -> RoomController:
	dungeon.enter_room(dungeon.get_room_at_slot(2))
	dungeon.enter_room(dungeon.get_room_at_slot(3))
	return dungeon._prepare_slot(4, BranchOption.create(BranchOption.Kind.SPECIAL, special_type))


# --- #9: special contents stand there before anyone enters ---

func test_special_contents_stand_in_the_prepared_room() -> void:
	for special_type: int in [RoomSequence.SpecialType.SHOP, RoomSequence.SpecialType.WEAPON,
			RoomSequence.SpecialType.FOUNTAIN, RoomSequence.SpecialType.UPGRADE]:
		var dungeon: DungeonManager = await _dungeon(SEEDS[0])
		var room := _special_room(dungeon, special_type)
		assert_eq(room.special_type, special_type)
		var contents := _contents(room)
		assert_eq(contents.size(), 1, "type %d: the content is built with the room" % special_type)
		var content := contents[0]
		assert_true(content.is_prepared(), "type %d: prepared" % special_type)
		assert_false(content.is_set_up(), "type %d: not usable before the room is entered" % special_type)
		assert_gt(content.get_child_count(), 0, "type %d: sprites and lights are there" % special_type)
		assert_eq(room.state, RoomController.State.PREPARED, "type %d: preparing starts nothing" % special_type)
		for interactable in _interactables(content):
			assert_false(interactable.is_available(), "type %d: %s waits for the entry" % [special_type, interactable.prompt])
		if special_type == RoomSequence.SpecialType.SHOP:
			assert_true((content.get(&"_offers") as Array).is_empty(), "shop: offers only on entry (D-036)")
		dungeon.finish_preparing()
		dungeon.enter_room(room)
		assert_true(content.is_set_up(), "type %d: usable after the entry" % special_type)
		assert_same(_contents(room)[0], content, "type %d: the same content, nothing built again" % special_type)
		var available := 0
		for interactable in _interactables(content):
			available += int(interactable.is_available())
		assert_gt(available, 0, "type %d: something to use" % special_type)
		if special_type == RoomSequence.SpecialType.SHOP:
			assert_false((content.get(&"_offers") as Array).is_empty(), "shop: offers rolled on entry")
		await _drop(dungeon)


func test_the_portal_of_a_special_room_stands_there_too() -> void:
	var dungeon: DungeonManager = await _dungeon(SEEDS[0])
	dungeon.enter_room(dungeon.get_room_at_slot(2))
	dungeon.enter_room(dungeon.get_room_at_slot(3))
	# Slot 4 is a special room (room 4 of the cycle).
	var room := dungeon.get_room_at_slot(4)
	assert_not_null(room)
	var before := _contents(room).size()
	assert_gte(before, 1, "content prepared with the room")
	if room.has_portal:
		assert_eq(before, 2, "the portal stands there as well")
	dungeon.enter_room(room)
	assert_eq(_contents(room).size(), before, "entering builds nothing new")
	for content in _contents(room):
		assert_true(content.is_set_up())
	await _drop(dungeon)


func test_the_trial_course_stands_there_before_the_entry() -> void:
	var dungeon: DungeonManager = await _dungeon(SEEDS[0])
	var room := _special_room(dungeon, RoomSequence.SpecialType.TRIAL)
	var contents := _contents(room)
	assert_eq(contents.size(), 1)
	var trial := contents[0] as TrialContent
	assert_not_null(trial, "the trial content is built with the room")
	assert_not_null(trial.course, "the parcours stands there under the veil")
	assert_gt(trial.course.get_child_count(), 0, "its hazards or torches are built")
	assert_not_null(trial.chest, "the chest is visible from the entrance")
	assert_false(trial.is_set_up(), "runs count only after the entry")
	var course := trial.course
	dungeon.finish_preparing()
	dungeon.enter_room(room)
	assert_true(trial.is_set_up())
	assert_same(trial.course, course, "the same course, nothing built again")
	await _drop(dungeon)


func test_a_content_without_prepare_still_works_in_one_step() -> void:
	# Tests, the secret niche's merchant and the trial build in one step (setup only).
	var content: SpecialContent = add_child_autofree(SpecialContent.new())
	content.setup(DungeonContext.new(), null)
	var interactable := content.add_interactable("Benutzen")
	assert_true(interactable.is_available(), "set up: usable at once")
	assert_true(content.is_prepared() and content.is_set_up())


# --- #14: the next room follows in later frames ---

func test_entering_builds_the_next_room_in_the_following_frames() -> void:
	var dungeon: DungeonManager = await _dungeon(SEEDS[0])
	var room := dungeon.get_room_at_slot(2)
	dungeon.enter_room(room)
	assert_true(dungeon.is_preparing(), "the entry frame only starts the room")
	assert_false(dungeon._rooms.has(3), "room 3 not built in the entry frame")
	assert_eq(dungeon.get_live_room_count(), 2)
	var built_hidden := false
	var built_unpainted := false
	var frames := 0
	while dungeon.is_preparing() and frames < 16:
		await get_tree().process_frame
		frames += 1
		var next: RoomController = dungeon._rooms.get(3)
		if next == null:
			continue
		if not next.visible:
			built_hidden = true
		else:
			assert_not_null(RoomVeil.of(next), "shown only with its veil on")
			assert_false(next.tiles.is_paint_held(), "shown only once painted")
		if next.tiles.is_paint_held():
			built_unpainted = true
			assert_eq(next.tiles.get_used_cells().size(), 0, "no cells while the paint is held")
	assert_false(dungeon.is_preparing(), "done after a few frames (%d)" % frames)
	assert_gte(frames, 5, "built, painted, veiled, joined and signed in separate frames")
	assert_true(built_hidden, "the room stayed hidden until it was covered")
	assert_true(built_unpainted, "its tiles came a frame after the room")
	var next := dungeon.get_room_at_slot(3)
	assert_not_null(next)
	assert_true(next.visible)
	assert_not_null(RoomVeil.of(next), "dark behind its door (R5)")
	assert_false(RoomVeil.of(next).is_lifted())
	await _drop(dungeon)


func test_asking_for_a_pending_room_builds_it_at_once() -> void:
	var dungeon: DungeonManager = await _dungeon(SEEDS[0])
	dungeon.enter_room(dungeon.get_room_at_slot(2))
	var next := dungeon.get_room_at_slot(3)
	assert_not_null(next, "built when asked for")
	assert_false(dungeon.is_preparing(), "nothing left")
	assert_true(next.visible)
	assert_not_null(RoomVeil.of(next))
	assert_true(next.player_entered.is_connected(dungeon._on_player_entered_room), "ready to be entered")
	await _drop(dungeon)


func test_staged_preparation_draws_the_same_rooms_as_at_once() -> void:
	for seed_value in SEEDS:
		var at_once: Array[String] = await _chain(seed_value, false)
		var staged: Array[String] = await _chain(seed_value, true)
		assert_eq(staged.size(), at_once.size(), "seed %d: same number of slots" % seed_value)
		assert_eq(staged, at_once, "seed %d: same templates, doors and RNG states" % seed_value)


## Templates, doors and RNG state of slots 2..SLOTS, entering each room in turn: with staged = false
## the next room is asked for at once, otherwise the frames run until it is built.
func _chain(seed_value: int, staged: bool) -> Array[String]:
	var dungeon: DungeonManager = await _dungeon(seed_value)
	var lines: Array[String] = []
	for slot in range(2, SLOTS + 1):
		var before: RoomController = dungeon._rooms.get(slot - 1)
		if before != null and before.is_branch_room() and before.get_chosen_branch() < 0:
			dungeon.finish_preparing()
			before.choose_branch(0)
		if staged:
			var frames := 0
			while dungeon.is_preparing() and frames < 20:
				await get_tree().process_frame
				frames += 1
		var room := dungeon.get_room_at_slot(slot)
		if room == null:
			break
		lines.append("%d %s %s %s %d cells %d" % [slot, room.scene_file_path.get_file(), room.tiles.get_entrance_door(),
				room.tiles.get_exit_doors(), dungeon.get_slot_rng_state(slot), _cells_signature(room.tiles)])
		dungeon.enter_room(room)
	await _drop(dungeon)
	return lines


## Hash of every painted cell of the room layer and its backdrop (source, atlas piece, flips).
static func _cells_signature(tiles: RoomTiles) -> int:
	var parts: PackedStringArray = []
	for layer: TileMapLayer in [tiles, tiles.get_backdrop()]:
		if layer == null:
			continue
		var cells := layer.get_used_cells()
		cells.sort()
		for cell in cells:
			parts.append("%s:%d:%s:%d" % [cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)])
	return "|".join(parts).hash()


func test_a_held_paint_draws_the_same_cells() -> void:
	var base := (load(ROOM_BASE) as PackedScene).instantiate()
	var at_once := base.get_node(^"Tiles").duplicate() as RoomTiles
	var held := at_once.duplicate() as RoomTiles
	base.free()
	held.hold_paint()
	add_child_autofree(at_once)
	add_child_autofree(held)
	assert_gt(at_once.get_used_cells().size(), 0, "painted on entering the tree")
	assert_eq(held.get_used_cells().size(), 0, "held: nothing painted yet")
	held.release_paint()
	assert_false(held.is_paint_held())
	assert_eq(_cells_signature(held), _cells_signature(at_once), "the same cells after the release")


# --- Veil texture (#14: built without a per-pixel 2D loop) ---

func test_veil_blur_matches_the_plain_mean() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var size := Vector2i(23, 17)
	var values := PackedFloat32Array()
	values.resize(size.x * size.y)
	for i in values.size():
		values[i] = 1.0 if rng.randf() < 0.55 else 0.0
	var fast := RoomVeil._blur(values, size, 2)
	for y in size.y:
		for x in size.x:
			var total := 0.0
			var count := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < size.x and yy < size.y:
						total += values[yy * size.x + xx]
						count += 1
			assert_almost_eq(fast[y * size.x + x], total / count, 0.0001, "pixel %d,%d" % [x, y])
			if absf(fast[y * size.x + x] - total / count) > 0.0001:
				return
