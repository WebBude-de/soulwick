extends GutTest
## The decoration catalog (WK5, WK7, SPRITES_V13 Teil E): loaded from the delivered JSON files only
## (furniture in three styles with _front/_side, village decoration, wallpaper and floor), rotations
## and footprints, prices (TESTWERT: soul costs more), names in German, pictures and strips.

const FURNITURE_GROUPS := ["beds", "seating", "tables", "storage", "light", "rugs", "wall", "plants", "cozy", "fun"]
const DECO_GROUPS := ["garden", "paths", "lights", "fences", "water", "fun"]

var _old_locale: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	DecorCatalog.clear_cache()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)


func test_every_furniture_group_is_there_in_three_styles() -> void:
	var groups := DecorCatalog.groups_for(DecorCatalog.HOME)
	for group in FURNITURE_GROUPS:
		assert_has(groups, group, "group %s" % group)
		for style in DecorCatalog.STYLES:
			var found := DecorCatalog.items_for(DecorCatalog.HOME, group).filter(func(item: DecorItem) -> bool: return item.style == style)
			assert_gt(found.size(), 0, "%s in %s" % [group, style])
	assert_has(groups, DecorCatalog.SURFACE_GROUP, "wallpaper and floor")


func test_every_village_group_is_there() -> void:
	var groups := DecorCatalog.groups_for(DecorCatalog.VILLAGE)
	for group in DECO_GROUPS:
		assert_has(groups, group)
	for item in DecorCatalog.items_for(DecorCatalog.VILLAGE):
		assert_eq(item.style, "", "village decoration has no style")
		assert_false(item.is_wall(), "nothing hangs on a wall outside")


func test_furniture_views_are_one_item() -> void:
	var armchair := DecorCatalog.get_item("armchair_cozy")
	assert_not_null(armchair)
	assert_true(armchair.has_side(), "front and side")
	assert_eq(armchair.rotation_count(), 4)
	var cushion := DecorCatalog.get_item("floor_cushion_rustic")
	assert_false(cushion.has_side(), "symmetric: front only")
	assert_eq(cushion.rotation_count(), 2)
	assert_eq(cushion.next_rotation(0), 2, "the other side is the mirrored picture")
	assert_eq(cushion.next_rotation(2), 0)


func test_rotation_uses_the_side_view_and_mirrors() -> void:
	var bed := DecorCatalog.get_item("bed_single_soul")
	assert_eq(bed.footprint(0), Vector2i(2, 3), "front 2 wide, 3 deep")
	assert_eq(bed.footprint(1), Vector2i(3, 2), "side view turns it")
	assert_eq(bed.view_for(1), DecorItem.SIDE)
	assert_false(bed.is_flipped(1))
	assert_true(bed.is_flipped(3), "the far side is mirrored")
	assert_eq(bed.view_for(2), DecorItem.FRONT)
	assert_true(bed.is_flipped(2))
	for rot in 4:
		assert_eq(bed.next_rotation(rot), (rot + 1) % 4)


func test_wall_pieces_and_flat_pieces() -> void:
	var picture := DecorCatalog.get_item("picture_flint_cozy")
	assert_true(picture.is_wall(), "footprint [1, 0] hangs on the wall")
	assert_false(picture.blocks())
	var rug := DecorCatalog.get_item("rug_large_rustic")
	assert_true(rug.is_flat())
	assert_false(rug.blocks())
	var paving := DecorCatalog.get_item("paving_1")
	assert_true(paving.is_flat(), "JSON flat: true")
	var bed := DecorCatalog.get_item("bed_double_cozy")
	assert_true(bed.blocks())
	assert_false(bed.is_flat())


func test_lights_and_animations_come_from_the_json() -> void:
	var fireplace := DecorCatalog.get_item("fireplace_soul")
	assert_false(fireplace.light().is_empty(), "the fireplace glows")
	assert_eq(fireplace.anim_file(), "fireplace_fire_soul_6f.png")
	assert_not_null(DecorCatalog.strip_texture(fireplace), "fire strip over the picture")
	assert_false(DecorCatalog.uses_strip_as_picture(fireplace))
	assert_almost_eq(DecorCatalog.light_radius_tiles(fireplace), 5.0, 0.01, "main light of the room")
	var well := DecorCatalog.get_item("well_small")
	assert_true(DecorCatalog.uses_strip_as_picture(well), "the delivery has only the strip")
	assert_eq(DecorItem.frames_of(well.anim_file()), 4)
	assert_not_null(DecorCatalog.preview_texture(well))
	assert_eq(Vector2i(DecorCatalog.preview_texture(well).get_size()), well.frame_size(), "one frame in the shop")


func test_prices_soul_costs_more_and_bigger_costs_more() -> void:
	var cozy := DecorCatalog.get_item("armchair_cozy")
	var soul := DecorCatalog.get_item("armchair_soul")
	assert_gt(cozy.price, 0)
	assert_gt(soul.price, cozy.price, "soul is the collector's style")
	assert_gt(DecorCatalog.get_item("sofa_cozy").price, cozy.price, "3 tiles cost more than 1")
	for item in DecorCatalog.all_items():
		assert_gt(item.price, 0, "%s has a price" % item.id)
		assert_eq(item.price % 5, 0, "%s: round prices" % item.id)


func test_surfaces_are_wallpaper_and_floor_per_style() -> void:
	for style in DecorCatalog.STYLES:
		for surface in [DecorCatalog.SURFACE_WALL, DecorCatalog.SURFACE_FLOOR]:
			var item := DecorCatalog.get_item(DecorCatalog.surface_id(surface, style))
			assert_not_null(item, "%s %s" % [surface, style])
			assert_true(item.is_surface())
			assert_eq(item.rotation_count(), 1)
			assert_not_null(DecorCatalog.texture_for(item))


func test_names_are_translated() -> void:
	assert_eq(DecorCatalog.display_name(DecorCatalog.get_item("armchair_cozy")), "Sessel · Gemütlich")
	assert_eq(DecorCatalog.display_name(DecorCatalog.get_item("flower_bed_red")), "Blumenbeet rot")
	assert_eq(DecorCatalog.display_name(DecorCatalog.get_item("home_wall_soul")), "Tapete · Seele")
	for item in DecorCatalog.all_items():
		assert_true(Loc.has_key(StringName("DECOR_%s" % item.kind.to_upper()), &"de"), "%s has a German name" % item.kind)
		assert_true(Loc.has_key(StringName("DECOR_%s" % item.kind.to_upper()), &"en"), "%s has an English name" % item.kind)
	for group in DecorCatalog.GROUP_ORDER:
		assert_true(Loc.has_key(StringName("DECOR_GROUP_%s" % group.to_upper()), &"de"), "group %s" % group)


func test_every_picture_loads() -> void:
	for item in DecorCatalog.all_items():
		for rot in item.rotation_count():
			var texture := DecorCatalog.texture_for(item, rot)
			assert_not_null(texture, "%s rot %d" % [item.id, rot])
