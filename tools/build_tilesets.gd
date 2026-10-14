extends SceneTree
## Builds the TileSet resources from the tileset PNGs and their tile lists (art/index.json).
## Usage: godot --headless -s tools/build_tilesets.gd
## Re-run after the tileset images change. Output: dungeon/environment/dungeon_tileset.tres,
## world/village/village_tileset.tres

const TILE := 32
const HALF := TILE / 2.0
const FULL_BOX := [Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(HALF, HALF), Vector2(-HALF, HALF)]


func _init() -> void:
	_build(
		"res://art/environment/tiles/dungeon_tileset.png",
		"res://dungeon/environment/dungeon_tileset.tres",
		8, 3,
		# Everything except the four floor tiles blocks movement.
		func(coords: Vector2i) -> Array: return [] if coords.y == 0 and coords.x < 4 else FULL_BOX)
	# Biome tilesets share the dungeon layout (docs/SPRITES_V2.md §1).
	for biome in ["slime_grotto", "shadow_realm", "ember_forge"]:
		_build(
			"res://art/environment/tiles/%s_tileset.png" % biome,
			"res://dungeon/environment/%s_tileset.tres" % biome,
			8, 3,
			func(coords: Vector2i) -> Array: return [] if coords.y == 0 and coords.x < 4 else FULL_BOX)
	_build(
		"res://art/environment/tiles/village_tileset.png",
		"res://world/village/village_tileset.tres",
		8, 3,
		_village_collision)
	quit()


func _village_collision(coords: Vector2i) -> Array:
	match coords:
		Vector2i(7, 1):  # fence_h
			return [Vector2(-HALF, -4), Vector2(HALF, -4), Vector2(HALF, 6), Vector2(-HALF, 6)]
		Vector2i(0, 2):  # fence_v
			return [Vector2(-5, -HALF), Vector2(5, -HALF), Vector2(5, HALF), Vector2(-5, HALF)]
		Vector2i(1, 2), Vector2i(2, 2):  # bush, stump
			return [Vector2(-12, -6), Vector2(12, -6), Vector2(12, 12), Vector2(-12, 12)]
	return []


func _build(texture_path: String, out_path: String, cols: int, rows: int, collision: Callable) -> void:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 0)

	var source := TileSetAtlasSource.new()
	source.texture = load(texture_path)
	source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(source, 0)

	var width := source.texture.get_width() / TILE
	var height := source.texture.get_height() / TILE
	for y in mini(rows, height):
		for x in mini(cols, width):
			var coords := Vector2i(x, y)
			source.create_tile(coords)
			var points: Array = collision.call(coords)
			if points.is_empty():
				continue
			var tile_data := source.get_tile_data(coords, 0)
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, PackedVector2Array(points))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var err := ResourceSaver.save(tileset, out_path)
	print("saved ", out_path, " -> ", error_string(err))
