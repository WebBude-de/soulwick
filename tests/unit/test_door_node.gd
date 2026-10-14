extends GutTest
## D1 doors as nodes: open/closed state, collision and signals behave as before D1; the view
## (frame, torches, sign, glow, threat light) follows configure() without touching the state.

const DOOR_SCENE: PackedScene = preload("res://dungeon/environment/doors/door.tscn")
const TEST_SAVE_PATH := "user://test_door_node_save.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	DoorArt.art_dir = "user://test_door_node_no_art/"
	DoorArt.clear_cache()


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func _door() -> Door:
	var door := DOOR_SCENE.instantiate() as Door
	add_child_autofree(door)
	return door


func _shape(door: Door) -> CollisionShape2D:
	return door.get_node("CollisionShape2D") as CollisionShape2D


func test_starts_closed_and_blocks() -> void:
	var door := _door()
	await wait_physics_frames(1)
	assert_false(door.is_open)
	assert_false(_shape(door).disabled)
	assert_false(door.is_configured, "unconfigured doors leave the sound to the room")
	assert_false(door.view.sounds_enabled)
	assert_eq(door.get_style().biome_id, &"crypt")


func test_open_and_close_toggle_collision_and_signal() -> void:
	var door := _door()
	watch_signals(door)
	door.open()
	assert_true(door.is_open)
	assert_signal_emitted_with_parameters(door, "state_changed", [true, false])
	await wait_physics_frames(1)
	assert_true(_shape(door).disabled, "open door lets the player through")
	door.close()
	assert_false(door.is_open)
	assert_signal_emitted_with_parameters(door, "state_changed", [false, false])
	await wait_physics_frames(1)
	assert_false(_shape(door).disabled)


func test_open_instant_shows_last_leaf_frame() -> void:
	var door := _door()
	watch_signals(door)
	door.set_open_instant(true)
	assert_signal_emitted_with_parameters(door, "state_changed", [true, true])
	var leaf := door.get_node("Sprite") as AnimatedSprite2D
	assert_eq(leaf.animation, &"open")
	assert_eq(leaf.frame, leaf.sprite_frames.get_frame_count(&"open") - 1)
	await wait_physics_frames(1)
	assert_true(_shape(door).disabled)


func test_open_before_ready_is_kept() -> void:
	var door := DOOR_SCENE.instantiate() as Door
	door.set_open_instant(true)
	add_child_autofree(door)
	await wait_physics_frames(1)
	assert_true(door.is_open)
	assert_true(_shape(door).disabled)


func test_configure_builds_the_view() -> void:
	var door := _door()
	door.configure(&"shadow_realm", DoorStyle.KIND_NORMAL, &"shop")
	assert_true(door.is_configured)
	assert_true(door.view.sounds_enabled)
	assert_eq(door.get_style().leaf_kind, DoorStyle.LEAF_VEIL)
	assert_not_null(door.view.get_frame_sprite())
	assert_not_null(door.view.get_symbol_sprite(), "sign over a door to the shop")
	assert_not_null(door.view.get_glow_sprite(), "runes glimmer")
	assert_eq(door.view.get_torches().size(), 2)
	assert_null(door.view.get_threat_light())


func test_entrance_door_is_only_a_leaf_in_the_south_wall() -> void:
	# An arch on the low south wall would face away and reach into the room behind (playtest).
	var door := _door()
	door.configure(&"crypt", DoorStyle.KIND_NORMAL, &"shop", true)
	assert_true(door.is_entrance)
	assert_eq(door.view.get_torches().size(), 0)
	assert_null(door.view.get_symbol_sprite())
	assert_null(door.view.get_frame_sprite())


func test_configure_keeps_state_and_collision() -> void:
	var door := _door()
	door.open()
	await wait_physics_frames(1)
	door.configure(&"ember_forge")
	await wait_physics_frames(1)
	assert_true(door.is_open)
	assert_true(_shape(door).disabled)
	var leaf := door.get_node("Sprite") as AnimatedSprite2D
	assert_eq(leaf.frame, leaf.sprite_frames.get_frame_count(&"open") - 1, "still shown open")


func test_configure_for_room_and_destination() -> void:
	var door := _door()
	door.configure_for_room(&"slime_grotto", RoomSequence.RoomType.BOSS)
	assert_true(door.get_style().is_boss())
	assert_not_null(door.view.get_threat_light(), "closed boss gate pulses")
	door.set_destination(RoomSequence.RoomType.SPECIAL, RoomSequence.SpecialType.FOUNTAIN)
	assert_false(door.get_style().is_boss())
	assert_eq(door.get_style().biome_id, &"slime_grotto", "biome kept")
	assert_eq(door.get_style().symbol, &"fountain")
	assert_not_null(door.view.get_symbol_sprite())


func test_boss_threat_ends_when_open() -> void:
	var door := _door()
	door.configure(&"crypt", DoorStyle.KIND_BOSS)
	await wait_physics_frames(3)
	var light := door.view.get_threat_light()
	assert_gt(light.intensity, 0.0, "threat light pulses while closed")
	door.set_open_instant(true)
	await wait_physics_frames(3)
	assert_eq(light.intensity, 0.0)
	assert_lt(door.view.get_glow_sprite().modulate.a, 0.01)


func test_open_effects_do_not_change_state() -> void:
	var door := _door()
	door.configure(&"ember_forge")
	door.open()
	await wait_physics_frames(2)
	assert_true(door.is_open)
	door.open()
	assert_true(door.is_open, "opening twice is harmless")


func test_frame_sorts_by_its_floor_line_with_a_transparent_passage() -> void:
	# The arch must cover a player walking through, and the corridor shows through the passage.
	var door := _door()
	door.configure(&"slime_grotto")
	var leaf := door.get_node("Sprite") as AnimatedSprite2D
	var frame := door.view.get_frame_sprite()
	assert_eq(frame.z_index, 0, "frame shares the player's z level")
	assert_true(door.y_sort_enabled and door.view.y_sort_enabled, "door children y-sort with the room")
	assert_gt(frame.global_position.y, leaf.global_position.y, "frame sorts below (after) the leaf")
	var image := frame.texture.get_image()
	var centre := Vector2i(image.get_width() / 2, image.get_height() - 2)
	assert_lt(image.get_pixelv(centre).a, 0.1, "passage is transparent")


func test_delivered_boss_gate_brings_its_own_torches() -> void:
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()
	var style := DoorStyle.for_door(&"crypt", DoorStyle.KIND_BOSS)
	if not DoorArt.has_frame_file(style):
		DoorArt.art_dir = "user://test_door_node_no_art/"
		DoorArt.clear_cache()
		pending("door_frame_boss.png not delivered")
		return
	var door := _door()
	door.configure(&"crypt", DoorStyle.KIND_BOSS)
	assert_eq(door.view.get_torches().size(), 0, "torches are painted on the pillars")
	assert_eq(door.view.get_frame_sprite().texture.get_size(), Vector2(64, 56))
	DoorArt.art_dir = "user://test_door_node_no_art/"
	DoorArt.clear_cache()
