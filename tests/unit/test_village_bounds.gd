extends GutTest
## Reports 2026-10-23 #0ef74410 / #7539cc72 ("Hier kann man die Map verlassen", tiles [0,5] and
## [0,18]): the village is closed on every side. A physics flood fill with the player's body from the
## spawn never reaches a cell outside the map, and a real player (local and a guest's remote copy)
## pushed against every border tile, walking and dashing, stays inside. Uses a test folder only.

const ROOT := "user://test_village_bounds"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
## Player body from player.tscn: circle radius 9, 8 px below the origin.
const BODY_RADIUS := 9.0
const BODY_OFFSET := Vector2(0, 8)
const GRID := 16.0
## Frames a player pushes against one border tile (dash every DASH_EVERY frames).
const PUSH_FRAMES := 30
const DASH_EVERY := 7
## Sample distance along the border ring (world px).
const RING_STEP := 2.0

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()


func after_each() -> void:
	GameManager.clear_pause_reasons()
	HitStop.reset()


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root)


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


func _tile(village: Village) -> float:
	return 32.0 * (village.get_node("Ground") as Node2D).scale.x


## The map without its outer ring of tiles (fence, wall): where a player's feet may ever be.
func _inside(village: Village) -> Rect2:
	var tile := _tile(village)
	return Rect2(village.get_camera_limits()).grow(-tile * 0.25)


func test_flood_fill_from_the_spawn_never_leaves_the_map() -> void:
	var village := _village()
	await wait_physics_frames(3)
	var space := village.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var body := CircleShape2D.new()
	body.radius = BODY_RADIUS
	query.shape = body
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.CLIFF
	query.collide_with_areas = false
	var map := Rect2(village.get_camera_limits())
	# Search a margin outside the map too: a gap shows as a reached cell out there.
	var search := map.grow(_tile(village) * 2.0)
	var start := (village.get_node("PlayerSpawn") as Node2D).global_position
	var is_free := func(cell: Vector2i) -> bool:
		var point := Vector2(cell) * GRID
		if not search.has_point(point):
			return false
		query.transform = Transform2D(0.0, point + BODY_OFFSET)
		return space.intersect_shape(query, 1).is_empty()
	var first := Vector2i((start / GRID).round())
	assert_true(is_free.call(first), "spawn is free")
	var reached := {first: true}
	var open: Array[Vector2i] = [first]
	var outside: Array[Vector2] = []
	while not open.is_empty():
		var cell: Vector2i = open.pop_back()
		var point := Vector2(cell) * GRID
		if not map.has_point(point + BODY_OFFSET):
			outside.append(point)
			continue
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if not reached.has(next) and is_free.call(next):
				reached[next] = true
				open.append(next)
	assert_gt(reached.size(), 1500, "a large walkable area")
	assert_eq(outside.size(), 0, "no way out of the village (first escapes: %s)" % str(outside.slice(0, 5)))


## The ring around the map is closed: along each side a line through the fence is solid at every
## RING_STEP px, corners included (the corner gap between the vertical and the horizontal fence bar
## of the tiles let a player out, #7539cc72).
func test_border_ring_is_solid_everywhere() -> void:
	var village := _village()
	await wait_physics_frames(3)
	var space := village.get_world_2d().direct_space_state
	var map := Rect2(village.get_camera_limits())
	var tile := _tile(village)
	var line := tile * 0.5
	var holes: Array[Vector2] = []
	var y := 0.0
	while y <= map.size.y:
		for x in [line, map.size.x - line]:
			if not _solid_point(space, Vector2(x, y)):
				holes.append(Vector2(x, y))
		y += RING_STEP
	var x := 0.0
	while x <= map.size.x:
		for edge in [tile * 0.55, map.size.y - tile * 0.4]:
			if not _solid_point(space, Vector2(x, edge)):
				holes.append(Vector2(x, edge))
		x += RING_STEP
	assert_eq(holes.size(), 0, "holes in the ring (first: %s)" % str(holes.slice(0, 6)))


func _solid_point(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = PhysicsLayers.WORLD
	query.collide_with_areas = false
	return not space.intersect_point(query, 1).is_empty()


## Start points one tile inside every border tile with the push direction outwards.
func _border_starts(village: Village) -> Array[Dictionary]:
	var tile := _tile(village)
	var size := Vector2(village.get_camera_limits().size)
	var cols := int(size.x / tile)
	var rows := int(size.y / tile)
	var starts: Array[Dictionary] = []
	for row in rows:
		var y := (row + 0.5) * tile
		starts.append({"at": Vector2(tile * 1.4, y), "dir": Vector2.LEFT, "name": "left %d" % row})
		starts.append({"at": Vector2(size.x - tile * 1.4, y), "dir": Vector2.RIGHT, "name": "right %d" % row})
	for col in cols:
		var x := (col + 0.5) * tile
		starts.append({"at": Vector2(x, tile * 1.4), "dir": Vector2.UP, "name": "top %d" % col})
		starts.append({"at": Vector2(x, size.y - tile * 1.6), "dir": Vector2.DOWN, "name": "bottom %d" % col})
	# Into the corners diagonally and sliding along both fences there.
	var corner_inset := tile * 1.2
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var at := Vector2(lerpf(corner_inset, size.x - corner_inset, corner.x), lerpf(corner_inset, size.y - corner_inset, corner.y))
		var out := Vector2(-1.0 if corner.x == 0 else 1.0, -1.0 if corner.y == 0 else 1.0)
		for dir: Vector2 in [out.normalized(), Vector2(out.x, 0), Vector2(0, out.y)]:
			starts.append({"at": at, "dir": dir, "name": "corner %s %s" % [corner, dir]})
	return starts


func _player(village: Village, local: bool) -> Array:
	var player := PLAYER_SCENE.instantiate() as Player
	var input := RemoteInput.new()
	player.input = input
	player.is_local = local
	village.add_child(player)
	village.on_player_spawned(player)
	return [player, input]


## Pushes the player (walking and dashing) against every border tile; returns the escapes.
func _walk_the_border(village: Village, player: Player, input: RemoteInput) -> Array[String]:
	var inside := _inside(village)
	var space := village.get_world_2d().direct_space_state
	var escapes: Array[String] = []
	for start: Dictionary in _border_starts(village):
		var at: Vector2 = start["at"]
		# A start inside something solid (a tree at the edge) cannot be pushed from: skip it.
		if not _free(space, at):
			continue
		player.global_position = at
		player.velocity = Vector2.ZERO
		input.set_move(start["dir"])
		for frame in PUSH_FRAMES:
			if frame % DASH_EVERY == 0:
				input.tap(&"dash")
			await wait_physics_frames(1)
		input.set_move(Vector2.ZERO)
		var feet := player.global_position + Player.FEET_OFFSET
		if not inside.has_point(feet):
			escapes.append("%s -> %s" % [start["name"], feet])
	return escapes


func _free(space: PhysicsDirectSpaceState2D, at: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var body := CircleShape2D.new()
	body.radius = BODY_RADIUS
	query.shape = body
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.CLIFF
	query.transform = Transform2D(0.0, at + BODY_OFFSET)
	return space.intersect_shape(query, 1).is_empty()


func test_local_player_walking_and_dashing_stays_inside() -> void:
	var village := _village()
	var made := _player(village, true)
	await wait_physics_frames(3)
	var escapes := await _walk_the_border(village, made[0], made[1])
	assert_eq(escapes.size(), 0, "escapes: %s" % ", ".join(escapes.slice(0, 6)))


func test_guest_copy_walking_and_dashing_stays_inside() -> void:
	var village := _village()
	var made := _player(village, false)
	await wait_physics_frames(3)
	var escapes := await _walk_the_border(village, made[0], made[1])
	assert_eq(escapes.size(), 0, "escapes: %s" % ", ".join(escapes.slice(0, 6)))
