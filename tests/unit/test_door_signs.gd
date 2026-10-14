extends GutTest
## Door recognition (R5, 05_tueren.md): what an exit door shows of the room behind it (DoorSigns:
## mode, light colour) and how the door draws it (DoorView: mode symbol over the arch or the
## corridor, light cone pointing into the room, kept across configure, dimmed when sealed).

const DOOR_SCENE: PackedScene = preload("res://dungeon/environment/doors/door.tscn")
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_door_signs_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _door(side := RoomTiles.DoorSide.NORTH, entrance := false) -> Door:
	var door := DOOR_SCENE.instantiate() as Door
	door.set_side(side)
	door.configure(&"crypt", DoorStyle.KIND_NORMAL, &"", entrance)
	add_child_autofree(door)
	return door


## A node standing in for a prepared room: arena flag and mode metadata as needed.
func _room_stub(arena := false, mode: StringName = &"") -> Node2D:
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar arena := false\nfunc is_arena_room() -> bool:\n\treturn arena\n"
	script.reload()
	var room := Node2D.new()
	room.set_script(script)
	room.set(&"arena", arena)
	if mode != &"":
		room.set_meta(DoorSigns.META_MODE, mode)
	add_child_autofree(room)
	return room


# --- Decision ---

func test_mode_of_a_room() -> void:
	assert_eq(DoorSigns.mode_of(_room_stub()), &"", "plain clearing room: no mode")
	assert_eq(DoorSigns.mode_of(_room_stub(true)), RoomObjective.ARENA, "arena flag")
	assert_eq(DoorSigns.mode_of(_room_stub(true, RoomObjective.ESCORT)), RoomObjective.ESCORT, "the mode tag wins")
	assert_eq(DoorSigns.mode_of(null), &"")


func test_old_variants_map_onto_v2_modes() -> void:
	for variant: StringName in DoorSigns.VARIANT_MODES:
		assert_true(RoomObjective.has_mode(DoorSigns.VARIANT_MODES[variant]), "%s maps onto a mode" % variant)
	assert_false(DoorSigns.VARIANT_MODES.has(&"gravedigger"), "the gravedigger is a plain clearing room")


func test_mode_of_an_attached_objective() -> void:
	var room := _room_stub()
	RoomObjective.attach(room, RoomObjective.create(RoomObjective.SOULS))
	assert_eq(DoorSigns.mode_of(room), RoomObjective.SOULS)


func test_way_colours() -> void:
	var plain := DoorStyle.for_door(&"shadow_realm")
	assert_eq(DoorSigns.way_color(plain, &""), DoorSigns.BIOME_COLORS[&"shadow_realm"], "clearing room: biome colour")
	assert_eq(DoorSigns.way_color(plain, RoomObjective.ARENA), RoomObjective.get_mode_color(RoomObjective.ARENA))
	assert_eq(DoorSigns.way_color(DoorStyle.for_door(&"crypt", DoorStyle.KIND_NORMAL, &"shop"), &""), DoorSigns.SPECIAL_COLOR, "rest rooms: gold")
	assert_eq(DoorSigns.way_color(DoorStyle.for_door(&"crypt", DoorStyle.KIND_NORMAL, &"campfire"), &""), DoorSigns.SPECIAL_COLOR)
	assert_eq(DoorSigns.way_color(DoorStyle.for_door(&"crypt", DoorStyle.KIND_NORMAL, &"miniboss"), &""), DoorSigns.DANGER_COLOR)
	assert_eq(DoorSigns.way_color(DoorStyle.for_door(&"ember_forge", DoorStyle.KIND_BOSS), RoomObjective.ARENA), DoorSigns.DANGER_COLOR, "the boss gate stays red")
	for biome in DoorStyle.BIOMES:
		assert_true(DoorSigns.BIOME_COLORS.has(biome), "biome colour for %s" % biome)


func test_safe_way_stays_a_plain_fight() -> void:
	var room := _room_stub(true)
	assert_eq(DoorSigns.mode_for_way(room, BranchOption.create(BranchOption.Kind.SAFE)), &"")
	assert_eq(DoorSigns.mode_for_way(room, BranchOption.create(BranchOption.Kind.UNKNOWN)), RoomObjective.ARENA, "the hidden way shows its mode")
	assert_eq(DoorSigns.mode_for_way(room), RoomObjective.ARENA)


# --- Door view ---

func test_show_way_builds_symbol_cone_and_light() -> void:
	var door := _door()
	assert_null(door.view.get_cone_sprite(), "no way, no cone")
	DoorSigns.show_way(door, _room_stub(true))
	assert_eq(door.get_way_mode(), RoomObjective.ARENA)
	assert_eq(door.get_style().mode, RoomObjective.ARENA)
	var cone := door.view.get_cone_sprite()
	assert_not_null(cone, "light cone in front of the door")
	assert_almost_eq(cone.rotation, 0.0, 0.001, "north door: the cone points south into the room")
	assert_gt(cone.position.y, door.view.TILE * 0.9, "cone starts at the door's inner edge")
	assert_eq(Color(cone.modulate, 1.0), RoomObjective.get_mode_color(RoomObjective.ARENA))
	assert_not_null(door.view.get_way_light())
	var symbol := door.view.get_symbol_sprite()
	assert_not_null(symbol, "mode symbol")
	var arch_top := -float(door.get_style().leaf_offset.y) * DoorView.PIXEL_SCALE
	assert_lt(symbol.position.y, arch_top, "the mode symbol floats over the arch")
	assert_eq(symbol.texture, RoomObjective.get_mode_icon(RoomObjective.ARENA))


func test_side_doors_point_their_cone_into_the_room() -> void:
	var west := _door(RoomTiles.DoorSide.WEST)
	west.show_way(&"", DoorSigns.SPECIAL_COLOR)
	assert_almost_eq(west.view.get_cone_sprite().rotation, -PI * 0.5, 0.001, "west door: east into the room")
	assert_gt(west.view.get_cone_sprite().position.x, DoorView.TILE * 0.9)
	var east := _door(RoomTiles.DoorSide.EAST)
	east.show_way(RoomObjective.HUNT, RoomObjective.get_mode_color(RoomObjective.HUNT))
	assert_almost_eq(east.view.get_cone_sprite().rotation, PI * 0.5, 0.001, "east door: west into the room")
	assert_lt(east.view.get_cone_sprite().position.x, DoorView.TILE * 0.1)
	assert_lt(east.view.get_symbol_sprite().position.y, 0.0, "symbol on the wall over the corridor")


func test_entrance_doors_show_no_way() -> void:
	var door := _door(RoomTiles.DoorSide.SOUTH, true)
	DoorSigns.show_way(door, _room_stub(true))
	assert_eq(door.get_way_mode(), &"")
	assert_null(door.view.get_cone_sprite())
	assert_null(door.view.get_symbol_sprite())


func test_way_survives_a_new_destination() -> void:
	var door := _door()
	door.show_way(RoomObjective.FLAME, RoomObjective.get_mode_color(RoomObjective.FLAME))
	door.set_destination(RoomSequence.RoomType.COMBAT)
	assert_eq(door.get_style().mode, RoomObjective.FLAME)
	assert_not_null(door.view.get_cone_sprite())


func test_sealed_door_puts_its_light_out() -> void:
	var door := _door()
	door.show_way(RoomObjective.ELITE_NEST, RoomObjective.get_mode_color(RoomObjective.ELITE_NEST))
	door.seal()
	assert_eq(door.view.get_way_light().intensity, 0.0)
	await wait_seconds(DoorView.CONE_FADE_TIME + 0.2)
	assert_lt(door.view.get_cone_sprite().modulate.a, 0.05, "the cone fades out")


func test_branch_doors_of_a_room_show_their_ways() -> void:
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(7, RoomSequence.RoomType.COMBAT, -1, false, context)
	var tiles := room.get_node("Tiles") as RoomTiles
	var exits: Array[Vector2i] = [Vector2i(RoomTiles.DoorSide.WEST, tiles.get_door_slots(RoomTiles.DoorSide.WEST)[0]),
			Vector2i(RoomTiles.DoorSide.EAST, tiles.get_door_slots(RoomTiles.DoorSide.EAST)[0])]
	var options: Array[BranchOption] = [BranchOption.create(BranchOption.Kind.ELITE_NEST, -1, BranchOption.ELITE_NEST_ID), BranchOption.create(BranchOption.Kind.SAFE)]
	room.apply_door_plan(Vector2i(RoomTiles.DoorSide.SOUTH, tiles.entrance_x), exits, 0, options)
	add_child_autofree(room)
	var doors := room.get_exit_doors()
	DoorSigns.show_way(doors[0], _room_stub(false, RoomObjective.ELITE_NEST), options[0])
	DoorSigns.show_way(doors[1], _room_stub(true), options[1])
	assert_eq(doors[0].get_way_mode(), RoomObjective.ELITE_NEST)
	assert_eq(doors[1].get_way_mode(), &"", "safe way")
	assert_eq(doors[1].get_style().symbol, &"safe", "the safe way keeps its heart")
	assert_true(doors[1].get_style().has_way_light(), "and its light in the biome colour")
