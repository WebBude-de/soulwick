class_name VillageDecor
extends Node2D
## Decoration scatter for the village (B3): flowers, grass tufts, stones, small bushes and flower
## beds along the path edges and beside the house walls, a few more on the open grass. Rules: never
## on a path, a door, the dungeon entrance, the spawn or another prop; inside the fence. Fixed seed,
## so the village always looks the same (for the same set of art files). Nothing here collides, so
## the decoration can never block a way. Art via VillageArt (placeholders until SPRITES_V4 arrives).
## Village calls populate() once in _ready, after the props were lifted (SortLift).
## R7: the square, the stairs and the stone slabs count as paths, the ridge (rock face) as a blocker;
## a little denser than in B3 (the village felt empty).

## Fixed seed: same village on every start.
const SEED := 20261014
## Candidate grid and jitter (world px).
const STEP := 32.0
const JITTER := 10.0
## TESTWERT: chance per candidate next to a path, next to a wall and on open grass.
const PATH_DENSITY := 0.6
const WALL_DENSITY := 0.8
const FIELD_DENSITY := 0.17
## A candidate is "at the path" up to this distance from a path (world px).
const PATH_BAND := 40.0
## Beside a wall: within this distance left/right/below a building and in the lower WALL_SHARE of it.
const WALL_BAND := 44.0
const WALL_SHARE := 0.5
## Keep-out distances (world px): path edge, doors and entrance (added to their radius), spawn.
const PATH_MARGIN := 4.0
const DOOR_MARGIN := 24.0
const SPAWN_CLEAR := 120.0
## Minimum distance between two decoration items (base points).
const MIN_SPACING := 36.0
## Buildings (for the wall rule) are props at least this wide (world px).
const BUILDING_MIN_WIDTH := 120.0

const PATH_KINDS := {"grass_tuft": 4, "stones": 2, "flowers_1": 2, "flowers_2": 2, "bush_small": 1}
const WALL_KINDS := {"flowers_1": 2, "flowers_2": 2, "flowers_3": 2, "flower_bed": 2, "bush_small": 2, "grass_tuft": 1}
const FIELD_KINDS := {"grass_tuft": 4, "flowers_3": 2, "stones": 1}

## Placed items: [{"art": String, "position": Vector2 (base), "rect": Rect2, "flip": bool}].
var placements: Array[Dictionary] = []


## Collects the rules from a village scene (Ground, Buildings, PlayerSpawn), see plan().
static func collect_rules(village: Node2D) -> Dictionary:
	var ground := village.get_node("Ground") as VillageTiles
	var tile := 32.0 * ground.scale.x
	var paths: Array[Rect2] = []
	for rect in ground.get_paved_rects():
		paths.append(Rect2(Vector2(rect.position) * tile, Vector2(rect.size) * tile))
	var blockers: Array[Rect2] = []
	for rect in ground.cliff_rects:
		blockers.append(Rect2(Vector2(rect.position) * tile, Vector2(rect.size) * tile))
	var walls: Array[Rect2] = []
	var clear: Array[Vector3] = []
	for prop in village.get_node("Buildings").get_children():
		if not prop is Node2D or prop.is_queued_for_deletion():
			continue
		var sprite_rect := sprite_rect_of(prop)
		if sprite_rect.has_area():
			blockers.append(sprite_rect)
			if sprite_rect.size.x >= BUILDING_MIN_WIDTH and prop is StaticBody2D:
				walls.append(sprite_rect)
		for area in prop.find_children("*", "Interactable", true, false):
			var circle := _circle_of(area as Area2D)
			if circle.z > 0.0:
				clear.append(Vector3(circle.x, circle.y, circle.z + DOOR_MARGIN))
	for cell in ground.bush_tiles + ground.stump_tiles:
		blockers.append(Rect2(Vector2(cell) * tile, Vector2.ONE * tile))
	var spawn := village.get_node_or_null("PlayerSpawn") as Node2D
	if spawn != null:
		clear.append(Vector3(spawn.global_position.x, spawn.global_position.y, SPAWN_CLEAR))
	var map := Rect2(Vector2.ZERO, Vector2(ground.map_size) * tile)
	return {
		"map": map.grow(-tile),
		"paths": paths,
		"blockers": blockers,
		"walls": walls,
		"clear": clear,
	}


## Global rectangle of the prop's "Sprite" child (Sprite2D or AnimatedSprite2D); empty without one.
static func sprite_rect_of(prop: Node) -> Rect2:
	var sprite := prop.get_node_or_null("Sprite")
	var local := Rect2()
	if sprite is Sprite2D:
		local = (sprite as Sprite2D).get_rect()
	elif sprite is AnimatedSprite2D:
		var animated := sprite as AnimatedSprite2D
		if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return Rect2()
		var frame := animated.sprite_frames.get_frame_texture(animated.animation, 0)
		if frame == null:
			return Rect2()
		var size := frame.get_size()
		local = Rect2(animated.offset - size * 0.5 if animated.centered else animated.offset, size)
	else:
		return Rect2()
	var xform := (sprite as Node2D).global_transform
	return Rect2(xform * local.position, xform.basis_xform(local.size)).abs()


## Centre and radius of a circle-shaped area (z = 0 if none).
static func _circle_of(area: Area2D) -> Vector3:
	for child in area.get_children():
		var shape := child as CollisionShape2D
		if shape != null and shape.shape is CircleShape2D:
			var centre := shape.global_position
			return Vector3(centre.x, centre.y, (shape.shape as CircleShape2D).radius)
	return Vector3.ZERO


## Deterministic placement list for the given rules (see collect_rules).
static func plan(rules: Dictionary, seed_value: int = SEED) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array[Dictionary] = []
	var map: Rect2 = rules["map"]
	var y := map.position.y + STEP * 0.5
	while y < map.end.y:
		var x := map.position.x + STEP * 0.5
		while x < map.end.x:
			# Always draw the same numbers per candidate, so one rule never shifts the others.
			var jitter := Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
			var roll := rng.randf()
			var pick := rng.randf()
			var flip := rng.randf() < 0.5
			var base := Vector2(x, y) + jitter
			x += STEP
			var kinds := {}
			if _near_wall(base, rules["walls"]):
				kinds = WALL_KINDS if roll < WALL_DENSITY else {}
			elif _near_path(base, rules["paths"]):
				kinds = PATH_KINDS if roll < PATH_DENSITY else {}
			elif roll < FIELD_DENSITY:
				kinds = FIELD_KINDS
			if kinds.is_empty():
				continue
			var art := _weighted(kinds, pick)
			var texture := VillageArt.get_texture(art)
			if texture == null:
				continue
			var size := texture.get_size() * VillageArt.SCALE
			var rect := Rect2(base - Vector2(size.x * 0.5, size.y), size)
			if not is_allowed(rect, rules) or _too_close(base, result):
				continue
			result.append({"art": art, "position": base, "rect": rect, "flip": flip})
		y += STEP
	return result


## True if a decoration rectangle keeps every rule: inside the fence, off paths, props, doors, spawn.
static func is_allowed(rect: Rect2, rules: Dictionary) -> bool:
	if not (rules["map"] as Rect2).encloses(rect):
		return false
	for path: Rect2 in rules["paths"]:
		if path.grow(PATH_MARGIN).intersects(rect):
			return false
	for blocker: Rect2 in rules["blockers"]:
		if blocker.intersects(rect):
			return false
	for circle: Vector3 in rules["clear"]:
		if rect_circle_distance(rect, Vector2(circle.x, circle.y)) < circle.z:
			return false
	return true


static func rect_circle_distance(rect: Rect2, centre: Vector2) -> float:
	var closest := Vector2(clampf(centre.x, rect.position.x, rect.end.x), clampf(centre.y, rect.position.y, rect.end.y))
	return closest.distance_to(centre)


static func _near_path(point: Vector2, paths: Array) -> bool:
	for path: Rect2 in paths:
		if path.has_point(point):
			return false
	for path: Rect2 in paths:
		if rect_circle_distance(path, point) <= PATH_BAND:
			return true
	return false


static func _near_wall(point: Vector2, walls: Array) -> bool:
	for wall: Rect2 in walls:
		var zone := Rect2(wall.position.x - WALL_BAND, wall.end.y - wall.size.y * WALL_SHARE, wall.size.x + WALL_BAND * 2.0, wall.size.y * WALL_SHARE + WALL_BAND * 0.5)
		if zone.has_point(point):
			return true
	return false


static func _too_close(point: Vector2, placed: Array[Dictionary]) -> bool:
	for item in placed:
		if (item["position"] as Vector2).distance_to(point) < MIN_SPACING:
			return true
	return false


static func _weighted(kinds: Dictionary, pick: float) -> String:
	var total := 0
	for kind in kinds:
		total += int(kinds[kind])
	var target := pick * total
	for kind in kinds:
		target -= int(kinds[kind])
		if target < 0.0:
			return kind
	return kinds.keys().back()


## Plans and places the decoration for village (once).
func populate(village: Node2D) -> void:
	for child in get_children():
		child.queue_free()
	placements = plan(collect_rules(village))
	for i in placements.size():
		var item := placements[i]
		var holder := Node2D.new()
		holder.name = "Deco%d" % i
		holder.position = item["position"]
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = VillageArt.get_texture(item["art"])
		sprite.scale = Vector2.ONE * VillageArt.SCALE
		sprite.offset = Vector2(0, -sprite.texture.get_height() * 0.5)
		sprite.flip_h = item["flip"]
		holder.add_child(sprite)
		add_child(holder)
		SortLift.lift(holder)
