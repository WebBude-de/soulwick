extends GutTest
## Playtest 15.10.2026 (notes 17, 21-24): what stands sorts at its foot line, what lies flat stays
## under the characters, solid parts collide only where something stands.
##   - a lip (rock with floor north of it) collides only from RockTerrain.LIP_WALK down and is drawn
##     again in the room's y-sort at the foot of its block, so a character behind it is hidden;
##   - a grave sorts at the foot of its stone (the mound in front of it is flat), standing sources
##     sort with the characters' feet offset, flat sources lie below everything;
##   - decoration groups block only under their standing parts (solid_span) and sort at the back of
##     their solid foot.

const HALL := preload("res://dungeon/rooms/combat/katakombengang_mirror_crypt.tscn")
const TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_sorting_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func test_lips_collide_lower_and_hide_who_stands_behind() -> void:
	# A block two tiles tall in open floor: its crown is a lip, its front is none.
	var floor_mask: Dictionary[Vector2i, bool] = {}
	for y in range(-2, 4):
		for x in range(-2, 3):
			floor_mask[Vector2i(x, y)] = true
	floor_mask.erase(Vector2i(0, 0))
	floor_mask.erase(Vector2i(0, 1))
	assert_true(RockTerrain.is_lip(Vector2i(0, 0), floor_mask), "the crown with floor north of it")
	assert_false(RockTerrain.is_lip(Vector2i(0, 1), floor_mask), "the front is no lip")
	var blocked: Dictionary[Vector2i, bool] = {Vector2i(0, -1): true}
	assert_false(RockTerrain.is_lip(Vector2i(0, 0), floor_mask, blocked), "no lip below a door corridor")
	var lip := RockTerrain.solid_polygon(0, true)
	var top := INF
	for point in lip:
		top = minf(top, point.y)
	assert_eq(top, -RockTerrain.TILE / 2.0 + RockTerrain.LIP_WALK, "the lip collides from LIP_WALK down")
	assert_true(RockTerrain.is_solid_cell(RockTerrain.SOURCE_GROUND, RockTerrain.solid_coords(0, true)))
	# A room: every lip cell has the lip collision and a sprite in the room's y-sort.
	var room := HALL.instantiate() as Node2D
	add_child_autofree(room)
	var tiles := room.get_node("Tiles") as RoomTiles
	tiles.use_tileset(load(TILESET_PATH))
	tiles.paint()
	await get_tree().process_frame
	if not tiles.is_terrain_drawn():
		pending("no terrain art")
		return
	var mask := tiles.get_floor_mask()
	var lips := 0
	for cell in tiles.get_used_cells():
		if RockTerrain.is_solid_cell(tiles.get_cell_source_id(cell), tiles.get_cell_atlas_coords(cell)) and tiles.get_cell_atlas_coords(cell).y == RockTerrain.SOLID_LIP_ROW:
			lips += 1
			assert_true(mask.has(cell + Vector2i.UP), "%s: lip below floor" % cell)
	assert_gt(lips, 5, "the room has lips")
	var node := tiles.get_lips()
	assert_not_null(node)
	if node == null:
		return
	assert_eq(node.get_parent(), room, "the lips sort with the room's characters")
	assert_true(node.y_sort_enabled)
	assert_gt(node.get_child_count(), 5)
	assert_lte(node.get_child_count(), lips, "a sprite per lip (none next to doors)")
	for sprite: Sprite2D in node.get_children():
		# Drawn where the rock is, sorted further down (at its block's foot line).
		var drawn := sprite.position.y + sprite.offset.y * sprite.scale.y
		assert_gt(sprite.position.y, drawn, "sorted below its top")


func test_graves_sort_at_the_stone_and_flat_sources_lie_low() -> void:
	var grave := SpawnSource.create_floor(SpawnSourceRules.Kind.GRAVE, Vector2(100, 200))
	add_child_autofree(grave)
	assert_eq(grave.position.y, 200.0 - grave.sort_lift(), "sorts above its pivot")
	assert_gt(grave.sort_lift(), Player.FEET_OFFSET.y + 10.0, "at the foot of the stone, not the front of the mound")
	assert_almost_eq(grave.get_pivot_global().y, 200.0, 0.01, "effects stay at the pivot")
	var art := grave.get_node_or_null("Art") as Node2D
	if art != null:
		assert_eq(art.position.y, grave.sort_lift(), "the art stays where it was")
	var sarcophagus := SpawnSource.create_floor(SpawnSourceRules.Kind.SARCOPHAGUS, Vector2(100, 200))
	add_child_autofree(sarcophagus)
	assert_almost_eq(sarcophagus.sort_lift(), Player.FEET_OFFSET.y + SpawnSource.STAND_SORT_LIFT, 0.01, "a sarcophagus sorts at its foot line")
	var puddle := SpawnSource.create_floor(SpawnSourceRules.Kind.PUDDLE, Vector2(100, 200))
	add_child_autofree(puddle)
	assert_eq(puddle.sort_lift(), 0.0)
	assert_eq(puddle.z_index, -1, "flat: below everything standing")


func test_groups_block_only_under_their_standing_parts() -> void:
	var group := DecoProp.new()
	group.item = &"group_1"
	group.biome = &"crypt"
	group.solid_span = Vector2(-54, 20)
	group.blocked_tiles = [Vector2i(0, 0)] as Array[Vector2i]
	add_child_autofree(group)
	var shape := group.get_node("Body").get_child(0) as CollisionShape2D
	assert_eq((shape.shape as RectangleShape2D).size.x, 74.0, "only the standing part")
	assert_eq(shape.position.x, -17.0, "centred on it")
	var flipped := DecoProp.new()
	flipped.item = &"group_1"
	flipped.biome = &"crypt"
	flipped.flip = true
	flipped.solid_span = Vector2(-54, 20)
	add_child_autofree(flipped)
	assert_eq((flipped.get_node("Body").get_child(0) as CollisionShape2D).position.x, 17.0, "mirrored with the picture")
	# Sorted at the back of the solid foot: lifted by the feet offset plus the foot's depth.
	var footprint: Vector2 = DecoProp.ITEMS[&"group_1"]["solid"]
	var plain := DecoProp.new()
	plain.item = &"group_1"
	plain.biome = &"crypt"
	add_child_autofree(plain)
	assert_eq(plain.position.y, -(Player.FEET_OFFSET.y + footprint.y))
	# Every generated group carries its span (the generator measures the art).
	var room := load("res://dungeon/rooms/combat/kreuzgang_mirror_crypt.tscn").instantiate() as Node2D
	var spans := 0
	for prop in room.get_node("Props").get_children():
		if prop is DecoProp and String((prop as DecoProp).item).begins_with("group_"):
			assert_ne((prop as DecoProp).solid_span, Vector2.ZERO, "%s: span measured" % prop.name)
			spans += 1
	room.free()
	assert_gt(spans, 0)
