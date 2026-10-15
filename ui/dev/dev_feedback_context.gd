class_name DevFeedbackContext
extends RefCounted
## Context of a dev feedback note (DevFeedback, F9): where the game was (scene, phase, room, biome,
## mode, template, seed, players, camera) and which UI and world nodes lie under each marked
## rectangle. Everything is read defensively (get(), has_method(), class names looked up at run
## time): game classes may be half finished by other agents and a missing value is simply left out,
## it never stops a note from being saved. Rectangles are in view coordinates (the canvas of the
## root viewport, the same space the overlay draws in).

const MAX_NODES := 15
## TileMapLayer sampling: at most this many cells per layer and rectangle, at most this many layers.
const MAX_TILE_CELLS := 6000
const MAX_TILE_LAYERS := 4
const MAX_TILES_PER_LAYER := 6
const MAX_TEXT := 120
## Pure layout controls (without script, text or texture) come after everything that draws.
const LAYOUT_CLASSES: Array[String] = ["Control", "Container", "BoxContainer", "HBoxContainer", "VBoxContainer",
	"GridContainer", "MarginContainer", "CenterContainer", "AspectRatioContainer", "FlowContainer",
	"HFlowContainer", "VFlowContainer", "ScrollContainer", "HSplitContainer", "VSplitContainer"]
## Fallback world tile size when RoomTiles cannot be read.
const TILE_WORLD_FALLBACK := 64.0


## Scene, phase, window, camera, pause reasons, run, dungeon room and players.
static func collect(tree: SceneTree, exclude: Node = null) -> Dictionary:
	var context := {}
	if tree == null:
		return context
	var scene := tree.current_scene
	context["scene"] = scene.scene_file_path if scene != null else ""
	context["scene_name"] = str(scene.name) if scene != null else ""
	context["phase"] = _phase_name(tree)
	context["window"] = _window_info(tree)
	context["camera"] = _camera_info(tree)
	context["pause_reasons"] = _pause_reasons(tree)
	var run_manager := tree.root.get_node_or_null(^"RunManager")
	if run_manager != null and run_manager.has_method(&"is_run_active"):
		context["run"] = {"active": run_manager.call(&"is_run_active"), "room": run_manager.call(&"get_current_room")}
	var dungeon := find_by_class(scene, &"DungeonManager", exclude)
	var room: Node = null
	if dungeon != null:
		var info := _dungeon_info(dungeon)
		room = info.get("_room") as Node
		info.erase("_room")
		context["dungeon"] = info
	context["players"] = _players_info(tree, room)
	context["location"] = describe_location(context)
	return context


## Visible Controls whose rectangle meets rect, smallest first (then deepest), at most MAX_NODES.
static func ui_nodes_in(root: Node, rect: Rect2, exclude: Node = null) -> Array:
	var found: Array[Dictionary] = []
	_walk_ui(root, rect, exclude, 0, found)
	found.sort_custom(_by_area_then_depth)
	return _strip(found.slice(0, MAX_NODES))


## Visible sprites, lights, scripted Node2D and TileMapLayers under rect, at most MAX_NODES; tile
## layers (with the tiles under the rect) first, then the rest smallest first.
static func world_nodes_in(root: Node, rect: Rect2, exclude: Node = null) -> Array:
	var tiles: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	_walk_world(root, rect, exclude, 0, tiles, others)
	others.sort_custom(_by_area_then_depth)
	var result := tiles.slice(0, MAX_TILE_LAYERS)
	result.append_array(others.slice(0, MAX_NODES - result.size()))
	return _strip(result)


## One line for index.md and the overview: "Dungeon · Raum 12 · Krypta · COMBAT · arena".
static func describe_location(context: Dictionary) -> String:
	var parts: PackedStringArray = []
	var phase := str(context.get("phase", ""))
	match phase:
		"menu":
			parts.append("Menü")
		"village":
			parts.append("Dorf")
		"dungeon":
			parts.append("Dungeon")
		_:
			parts.append(str(context.get("scene_name", "?")))
	var dungeon: Dictionary = context.get("dungeon", {})
	if not dungeon.is_empty():
		if dungeon.has("room_index"):
			parts.append("Raum %d" % int(dungeon["room_index"]))
		for key in ["biome_name", "room_type", "mode", "variant"]:
			var value := str(dungeon.get(key, ""))
			if not value.is_empty() and value != "<null>":
				parts.append(value)
		if bool(dungeon.get("side_view", false)):
			parts.append("Seitenansicht")
	elif phase != "dungeon" and context.get("scene", "") != "":
		parts.append(str(context["scene"]).get_file())
	return " · ".join(parts)


## First node below from whose script (or a base script) has the given class_name.
static func find_by_class(from: Node, global_name: StringName, exclude: Node = null) -> Node:
	if from == null or from == exclude:
		return null
	if has_class(from, global_name):
		return from
	for child in from.get_children():
		var hit := find_by_class(child, global_name, exclude)
		if hit != null:
			return hit
	return null


static func has_class(node: Object, global_name: StringName) -> bool:
	var script := node.get_script() as Script
	while script != null:
		if script.get_global_name() == global_name:
			return true
		script = script.get_base_script()
	return false


## Constant of a global script class (e.g. RoomTiles.TILE_WORLD), or fallback.
static func class_constant(global_name: StringName, constant: StringName, fallback: Variant) -> Variant:
	var script := class_script(global_name)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(constant, fallback)


static func class_script(global_name: StringName) -> Script:
	for entry in ProjectSettings.get_global_class_list():
		if StringName(entry.get("class", "")) == global_name:
			return load(str(entry.get("path", ""))) as Script
	return null


static func enum_key(global_name: StringName, enum_name: StringName, value: Variant) -> String:
	var values: Variant = class_constant(global_name, enum_name, {})
	if values is Dictionary:
		var key: Variant = (values as Dictionary).find_key(int(value)) if typeof(value) == TYPE_INT else null
		if key != null:
			return str(key)
	return str(value)


static func _phase_name(tree: SceneTree) -> String:
	var manager := tree.root.get_node_or_null(^"GameManager")
	if manager == null or not manager.has_method(&"get_phase"):
		return ""
	var phase: int = manager.call(&"get_phase")
	var phases: Variant = manager.get_script().get_script_constant_map().get(&"Phase", {})
	if phases is Dictionary:
		var key: Variant = (phases as Dictionary).find_key(phase)
		if key != null:
			return str(key).to_lower()
	return str(phase)


static func _pause_reasons(tree: SceneTree) -> Array:
	var reasons: Array = []
	var manager := tree.root.get_node_or_null(^"GameManager")
	if manager == null:
		return reasons
	var active: Variant = manager.get(&"_pause_reasons")
	if active is Dictionary:
		for reason: Variant in (active as Dictionary).keys():
			if StringName(reason) != DevFeedback.PAUSE_REASON:
				reasons.append(str(reason))
	return reasons


static func _window_info(tree: SceneTree) -> Dictionary:
	var info := {
		"view_size": _vec(tree.root.get_visible_rect().size),
		"content_scale": tree.root.content_scale_factor,
	}
	if DisplayServer.get_name() != "headless":
		info["window_size"] = _vec(DisplayServer.window_get_size())
		info["mode"] = DisplayServer.window_get_mode()
	return info


static func _camera_info(tree: SceneTree) -> Dictionary:
	var camera := tree.root.get_camera_2d()
	if camera == null:
		return {}
	return {
		"path": str(camera.get_path()),
		"zoom": _vec(camera.zoom),
		"position": _vec(camera.get_screen_center_position()),
	}


static func _dungeon_info(dungeon: Node) -> Dictionary:
	var info := {"path": str(dungeon.get_path())}
	var seed_value: Variant = dungeon.call(&"get_run_seed") if dungeon.has_method(&"get_run_seed") else dungeon.get(&"_run_seed")
	if seed_value != null:
		# As text: 64-bit seeds do not survive JSON readers that use doubles.
		info["seed"] = str(seed_value)
	if dungeon.has_method(&"get_active_slot"):
		info["slot"] = dungeon.call(&"get_active_slot")
	if dungeon.has_method(&"get_active_room_index"):
		info["room_index"] = dungeon.call(&"get_active_room_index")
	var room: Node = null
	if dungeon.has_method(&"get_room_at_slot") and info.has("slot"):
		room = dungeon.call(&"get_room_at_slot", info["slot"]) as Node
	if room == null and dungeon.has_method(&"get_room") and info.has("room_index"):
		room = dungeon.call(&"get_room", info["room_index"]) as Node
	var room_index := int(info.get("room_index", 0))
	if room_index > 0:
		# Same count as the HUD line "Zyklus n" (RoomSequence.CYCLE_LENGTH).
		var cycle_length := int(class_constant(&"RoomSequence", &"CYCLE_LENGTH", 5))
		info["cycle"] = floori(float(room_index - 1) / maxi(1, cycle_length)) + 1
		var sequence := class_script(&"RoomSequence")
		if sequence != null:
			info["biome_name"] = str(sequence.call(&"get_biome_name", sequence.call(&"get_biome", room_index)))
	if room == null:
		return info
	info["_room"] = room
	info["room_path"] = str(room.get_path())
	info["template"] = room.scene_file_path
	for key: StringName in [&"slot_index", &"is_arena", &"is_ambush", &"is_extra_dark", &"has_portal"]:
		var value: Variant = room.get(key)
		if value != null:
			info[str(key)] = value
	var type_value: Variant = room.get(&"room_type")
	if type_value != null:
		info["room_type"] = enum_key(&"RoomSequence", &"RoomType", type_value)
	var kind_value: Variant = room.get(&"room_kind")
	if kind_value != null:
		info["room_kind"] = enum_key(&"RoomSequence", &"RoomKind", kind_value)
	var size_value: Variant = room.get(&"room_size_class")
	if size_value != null:
		info["room_size"] = enum_key(&"RoomSequence", &"RoomSize", size_value)
	var special: Variant = room.get(&"special_type")
	if special != null and int(special) >= 0:
		info["special_type"] = enum_key(&"RoomSequence", &"SpecialType", special)
	if room.has_method(&"is_campfire") and room.call(&"is_campfire"):
		info["campfire"] = true
	if room.has_method(&"get_variant_id"):
		info["variant"] = str(room.call(&"get_variant_id"))
	var signs := class_script(&"DoorSigns")
	if signs != null:
		info["mode"] = str(signs.call(&"mode_of", room))
	if dungeon.has_method(&"get_room_kind_label"):
		info["kind_label"] = str(dungeon.call(&"get_room_kind_label", room))
	var spawner: Variant = room.get(&"spawner")
	if spawner is Object and is_instance_valid(spawner) and (spawner as Object).has_method(&"get_biome"):
		var biome: Variant = (spawner as Object).call(&"get_biome", room_index)
		if biome is Object and biome != null:
			info["biome"] = str((biome as Object).get(&"id"))
			var display: Variant = (biome as Object).get(&"display_name")
			if display != null and str(display) != "":
				info["biome_name"] = str(display)
	return info


static func _players_info(tree: SceneTree, room: Node) -> Array:
	var players: Array = []
	var tile_world := float(class_constant(&"RoomTiles", &"TILE_WORLD", TILE_WORLD_FALLBACK))
	var origin := Vector2i.ZERO
	var has_origin := false
	if room is Node2D:
		origin = Vector2i(((room as Node2D).position / tile_world).round())
		has_origin = true
	for node in tree.get_nodes_in_group(&"player"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var player := node as Node2D
		var tile := Vector2i((player.global_position / tile_world).floor())
		var entry := {
			"path": str(player.get_path()),
			"position": _vec(player.global_position),
			"tile": _vec(tile),
		}
		if has_origin:
			entry["room_tile"] = _vec(tile - origin)
		if player.has_method(&"is_side_view"):
			entry["side_view"] = player.call(&"is_side_view")
		players.append(entry)
	return players


static func _walk_ui(node: Node, rect: Rect2, exclude: Node, depth: int, found: Array[Dictionary]) -> void:
	if node == exclude or _skips_subtree(node, depth):
		return
	if node is Control:
		var control := node as Control
		var bounds := control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
		bounds = bounds.abs()
		if bounds.get_area() > 0.0 and bounds.intersects(rect):
			var entry := _base_entry(control, bounds, depth)
			var text := _text_of(control)
			if not text.is_empty():
				entry["text"] = text
			var texture := _texture_of(control)
			if not texture.is_empty():
				entry["texture"] = texture
			entry["plain"] = text.is_empty() and texture.is_empty() and control.get_script() == null \
					and LAYOUT_CLASSES.has(control.get_class())
			found.append(entry)
	for child in node.get_children():
		_walk_ui(child, rect, exclude, depth + 1, found)


static func _walk_world(node: Node, rect: Rect2, exclude: Node, depth: int,
		tiles: Array[Dictionary], others: Array[Dictionary]) -> void:
	if node == exclude or _skips_subtree(node, depth):
		return
	if node is TileMapLayer:
		var layer_entry := _tile_layer_entry(node as TileMapLayer, rect, depth)
		if not layer_entry.is_empty():
			tiles.append(layer_entry)
	elif node is Node2D:
		var item := node as Node2D
		var xform := item.get_global_transform_with_canvas()
		var local := _local_rect(item)
		var entry := {}
		if local.size != Vector2.ZERO:
			var bounds := (xform * local).abs()
			if bounds.intersects(rect):
				entry = _base_entry(item, bounds, depth)
		elif item.get_script() != null and not _has_node2d_child(item) and rect.has_point(xform.origin):
			# Scripted leaf without a texture (drawn in _draw, particles): its origin counts.
			entry = _base_entry(item, Rect2(xform.origin, Vector2.ZERO), depth)
			entry["area"] = rect.get_area()
		if not entry.is_empty():
			var texture := _texture_of(item)
			if not texture.is_empty():
				entry["texture"] = texture
			entry["z_index"] = item.z_index
			var holder := _scripted_ancestor(item)
			if holder != null and holder != item:
				entry["holder"] = str(holder.get_path())
				entry["holder_script"] = (holder.get_script() as Script).resource_path
			if item.owner != null and item.owner.scene_file_path != "":
				entry["scene"] = item.owner.scene_file_path
			others.append(entry)
	for child in node.get_children():
		_walk_world(child, rect, exclude, depth + 1, tiles, others)


## Hidden canvas items and layers hide their subtree; nested viewports and windows draw elsewhere.
static func _skips_subtree(node: Node, depth: int) -> bool:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return true
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return true
	return depth > 0 and (node is Viewport)


static func _base_entry(node: Node, bounds: Rect2, depth: int) -> Dictionary:
	var script := node.get_script() as Script
	return {
		"path": str(node.get_path()),
		"class": node.get_class(),
		"script": script.resource_path if script != null else "",
		"rect": _rect_dict(bounds),
		"area": bounds.get_area(),
		"depth": depth,
	}


static func _local_rect(item: Node2D) -> Rect2:
	if item is Sprite2D:
		var sprite := item as Sprite2D
		return sprite.get_rect() if sprite.texture != null else Rect2()
	if item is AnimatedSprite2D:
		var animated := item as AnimatedSprite2D
		if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return Rect2()
		if animated.sprite_frames.get_frame_count(animated.animation) <= animated.frame:
			return Rect2()
		var frame_texture := animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		if frame_texture == null:
			return Rect2()
		var size := frame_texture.get_size()
		var top_left := animated.offset - (size / 2.0 if animated.centered else Vector2.ZERO)
		return Rect2(top_left, size)
	if item is PointLight2D:
		var light := item as PointLight2D
		if light.texture == null:
			return Rect2()
		var light_size := light.texture.get_size() * light.texture_scale
		return Rect2(light.offset - light_size / 2.0, light_size)
	if item is Polygon2D:
		var polygon := (item as Polygon2D).polygon
		if polygon.size() < 3:
			return Rect2()
		var poly_rect := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			poly_rect = poly_rect.expand(point)
		return poly_rect
	return Rect2()


static func _tile_layer_entry(layer: TileMapLayer, rect: Rect2, depth: int) -> Dictionary:
	if layer.tile_set == null:
		return {}
	var local := (layer.get_global_transform_with_canvas().affine_inverse() * rect).abs()
	var from := layer.local_to_map(local.position)
	var to := layer.local_to_map(local.end)
	var counts := {}
	var cells := 0
	var used := 0
	for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			cells += 1
			if cells > MAX_TILE_CELLS:
				break
			var cell := Vector2i(x, y)
			var source := layer.get_cell_source_id(cell)
			if source < 0:
				continue
			used += 1
			var key := "%d:%d,%d" % [source, layer.get_cell_atlas_coords(cell).x, layer.get_cell_atlas_coords(cell).y]
			counts[key] = int(counts.get(key, 0)) + 1
	if used == 0:
		return {}
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	var top: Array = []
	for key: String in keys.slice(0, MAX_TILES_PER_LAYER):
		top.append({"tile": key, "cells": counts[key]})
	var entry := _base_entry(layer, rect, depth)
	entry["tile_set"] = layer.tile_set.resource_path
	entry["cells_in_rect"] = used
	entry["cell_range"] = {"from": _vec(from), "to": _vec(to)}
	entry["tiles"] = top
	entry["z_index"] = layer.z_index
	if layer.owner != null and layer.owner.scene_file_path != "":
		entry["scene"] = layer.owner.scene_file_path
	return entry


static func _has_node2d_child(node: Node) -> bool:
	for child in node.get_children():
		if child is Node2D:
			return true
	return false


static func _scripted_ancestor(node: Node) -> Node:
	var current := node
	while current != null:
		if current.get_script() != null:
			return current
		current = current.get_parent()
	return null


static func _text_of(control: Control) -> String:
	var text := ""
	if control is RichTextLabel:
		text = (control as RichTextLabel).get_parsed_text()
	else:
		var value: Variant = control.get(&"text")
		if value is String or value is StringName:
			text = str(value)
	text = text.strip_edges()
	if text.length() > MAX_TEXT:
		text = text.substr(0, MAX_TEXT - 1) + "…"
	return text


static func _texture_of(node: Node) -> String:
	for property: StringName in [&"texture", &"texture_normal", &"sprite_frames"]:
		var value: Variant = node.get(property)
		if value is Resource and value != null:
			var path := (value as Resource).resource_path
			return path if path != "" else (value as Resource).get_class()
	return ""


static func _by_area_then_depth(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.get("plain", false)) != bool(b.get("plain", false)):
		return not bool(a.get("plain", false))
	if not is_equal_approx(float(a["area"]), float(b["area"])):
		return float(a["area"]) < float(b["area"])
	return int(a["depth"]) > int(b["depth"])


## Drops the sort helpers from the entries.
static func _strip(entries: Array) -> Array:
	for entry: Dictionary in entries:
		entry.erase("area")
		entry.erase("depth")
		entry.erase("plain")
	return entries


static func _rect_dict(rect: Rect2) -> Dictionary:
	return {"x": snappedf(rect.position.x, 0.1), "y": snappedf(rect.position.y, 0.1),
			"w": snappedf(rect.size.x, 0.1), "h": snappedf(rect.size.y, 0.1)}


static func _vec(value: Variant) -> Array:
	if value is Vector2i:
		return [value.x, value.y]
	if value is Vector2:
		return [snappedf(value.x, 0.1), snappedf(value.y, 0.1)]
	return []
