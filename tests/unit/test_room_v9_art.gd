extends GutTest
## Delivered V9 art in the rooms (M1, SPRITES_V9): decoration groups per biome, the soft niche, the
## cave breach and crack fitted to the room rock, the soft abyss sets, fog wisps as mood only.

const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_v9_art_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


## Every template of both catalogs once.
func _entries() -> Array[RoomTemplate]:
	var result: Array[RoomTemplate] = []
	var seen := {}
	for catalog: RoomCatalog in [RoomCatalog.create(), RoomCatalog.load_plans()]:
		for entry in catalog.get_entries():
			if entry.scene != null and not seen.has(entry.scene.resource_path):
				seen[entry.scene.resource_path] = true
				result.append(entry)
	return result


func test_decoration_groups_use_the_biome_art_and_block_their_tiles() -> void:
	var groups := 0
	for entry in _entries():
		var room := entry.scene.instantiate()
		for prop in room.get_node("Props").get_children():
			var deco := prop as DecoProp
			if deco == null or not String(deco.item).begins_with("group_"):
				continue
			groups += 1
			assert_true(entry.allows_biome(deco.biome), "%s: group in the room's biome (%s)" % [entry.id, deco.biome])
			var size := 3 if String(deco.item).begins_with("group_large") else 2
			assert_eq(deco.blocked_tiles.size(), size, "%s: %s stands on %d tiles" % [entry.id, deco.item, size])
		room.free()
	assert_gt(groups, 100, "groups in the plans")
	# The picture is the delivered file of the biome, no placeholder.
	for biome in BIOMES:
		var deco := DecoProp.new()
		deco.item = &"group_large_2"
		deco.biome = biome
		add_child_autofree(deco)
		var sprite := deco.sprite as Sprite2D
		assert_not_null(sprite)
		assert_eq(sprite.texture.resource_path, "res://art/environment/deco/deco_group_large_%s_2.png" % biome)
		assert_null(deco.get_node_or_null("Shadow"), "groups bring their own shadow")


func test_soft_pieces_take_the_room_rock_colours() -> void:
	for biome in BIOMES:
		var room := SoftPalette.room_anchors(biome)
		var delivered := SoftPalette.delivered_anchors(biome)
		assert_eq(room.size(), SoftPalette.Anchor.size(), "%s: room anchors" % biome)
		assert_eq(delivered.size(), SoftPalette.Anchor.size(), "%s: V9 anchors" % biome)
		var crack := SoftPalette.texture("res://art/environment/tiles/wall_cracked_%s_soft.png" % biome, biome).get_image()
		# The crown row of the crack (V9 rock top) now has the room's rock top colour.
		var top := crack.get_pixel(16, 4)
		var expected: Color = room[SoftPalette.Anchor.TOP]
		assert_almost_eq(Vector3(top.r, top.g, top.b), Vector3(expected.r, expected.g, expected.b), Vector3.ONE * 0.02, "%s: crack crown in rock colour" % biome)
	# The one niche (crypt colours) moves into every biome.
	var niche_crypt := SoftPalette.texture("res://art/environment/tiles/wall_niche_soft.png", &"crypt", &"crypt").get_image()
	var niche_ember := SoftPalette.texture("res://art/environment/tiles/wall_niche_soft.png", &"crypt", &"ember_forge").get_image()
	assert_ne(niche_crypt.get_pixel(16, 4), niche_ember.get_pixel(16, 4), "niche recoloured per biome")


func test_cave_rooms_break_open_rock_fronts() -> void:
	var breach := WallBreach.new()
	add_child_autofree(breach)
	breach.setup(WallBreach.Mode.BREACH, Vector2.DOWN, 3, &"slime_grotto")
	assert_true(breach.is_cave_breach())
	var masonry := WallBreach.new()
	add_child_autofree(masonry)
	masonry.setup(WallBreach.Mode.BREACH, Vector2.DOWN, 3)
	assert_false(masonry.is_cave_breach(), "masonry rooms keep the brick frame")
	var gate := WallBreach.new()
	add_child_autofree(gate)
	gate.setup(WallBreach.Mode.GATE, Vector2.DOWN, 3, &"slime_grotto")
	assert_false(gate.is_cave_breach(), "gates stay gates")


func test_abyss_uses_the_soft_sets() -> void:
	for path: String in ["res://dungeon/environment/dungeon_tileset.tres", "res://dungeon/environment/slime_grotto_tileset.tres", "res://dungeon/environment/shadow_realm_tileset.tres", "res://dungeon/environment/ember_forge_tileset.tres"]:
		var tileset := load(path) as TileSet
		var texture := (tileset.get_source(2) as TileSetAtlasSource).texture
		assert_true(texture.resource_path.ends_with("_soft.png"), "%s: %s" % [path, texture.resource_path])


func test_fog_wisps_are_mood_not_objects() -> void:
	var wisps := 0
	for entry in _entries():
		var room := entry.scene.instantiate()
		for prop in room.get_node("Props").get_children():
			assert_false(prop is DecoProp and (prop as DecoProp).item == &"mist", "%s: fog among the props" % entry.id)
		var ambience := room.get_node_or_null("Ambience")
		if ambience != null:
			wisps += ambience.get_child_count()
		room.free()
	assert_gt(wisps, 20, "fog wisps in the caves")
