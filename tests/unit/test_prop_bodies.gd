extends GutTest
## Solid props at any depth (PropBodies, RoomController.is_solid_prop): a plan crystal or torch
## stand is a DecoProp holding a LightIsland holding the Blocker, two levels below the prop. The old
## check looked one level deep only, so tools clearing the floor (boss_sim, combat_sim) and the
## escort path kept those props.

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_prop_bodies_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prop_bodies_save.cfg"))
	SaveManager.save_path = _old_save_path


func _deco(item: StringName, blocked: Array[Vector2i] = []) -> DecoProp:
	var deco := DecoProp.new()
	deco.item = item
	deco.biome = &"crypt"
	deco.blocked_tiles = blocked
	add_child_autofree(deco)
	return deco


func test_light_crystal_and_torch_stand_are_solid_two_levels_deep() -> void:
	for item: StringName in [&"light_crystal", &"torch_stand"]:
		var deco := _deco(item, [Vector2i(1, 1)] as Array[Vector2i])
		var body := PropBodies.find_solid_body(deco)
		assert_not_null(body, "%s: blocker found" % item)
		if body != null:
			assert_eq(String(body.name), "Blocker")
			assert_eq(body.get_parent().get_parent(), deco, "%s: DecoProp -> LightIsland -> Blocker" % item)
		assert_true(RoomController.is_solid_prop(deco), "%s blocks walking" % item)


func test_direct_bodies_still_count() -> void:
	var group := _deco(&"group_1", [Vector2i(0, 0)] as Array[Vector2i])
	assert_true(RoomController.is_solid_prop(group), "decoration group: Body as direct child")
	var body := StaticBody2D.new()
	add_child_autofree(body)
	assert_true(RoomController.is_solid_prop(body), "a crate or rubble is a body itself")
	var island := LightIsland.create(IngredientSet.LightStyle.CRYSTAL, Color.WHITE)
	add_child_autofree(island)
	assert_true(RoomController.is_solid_prop(island), "ingredient light island: Blocker as direct child")


func test_flat_decoration_and_empty_nodes_are_not_solid() -> void:
	var bones := _deco(&"bones_1")
	assert_false(RoomController.is_solid_prop(bones), "bones lie flat")
	var holder := Node2D.new()
	var area := Area2D.new()
	holder.add_child(area)
	add_child_autofree(holder)
	assert_false(RoomController.is_solid_prop(holder), "an area is no body")


func test_depth_is_limited() -> void:
	var top := Node2D.new()
	var node: Node = top
	for i in PropBodies.MAX_DEPTH:
		var child := Node2D.new()
		node.add_child(child)
		node = child
	var deep := StaticBody2D.new()
	node.add_child(deep)
	add_child_autofree(top)
	assert_null(PropBodies.find_solid_body(top), "deeper than MAX_DEPTH levels is no part of the prop")
	assert_eq(PropBodies.find_solid_body(top, PropBodies.MAX_DEPTH + 1), deep)
