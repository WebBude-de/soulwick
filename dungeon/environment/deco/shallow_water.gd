class_name ShallowWater
extends Node2D
## Shallow water or mud of a room plan (R1, plan cell 'w'): ordinary floor under organic water
## (WaterArt: pixel outline without the tile grid, biome water palette, slow shimmer, M1 playtest
## 15.10.2026) that slows every player wading through it. Enemies wade at full speed (their home; no
## speed modifier on enemies yet). Built by RoomTiles from water_rects, in the layer's space (one
## art tile per floor tile): one picture per connected pool, the slow area stays on the tile grid.
## Per-player state: the slow lives on the player (ToxicPuddle.apply_slow, one source per water
## area), so any number of players works (D-088).
## The pictures are built on a worker thread (WaterArt.request_pool) and fade in when ready, so
## preparing a room costs no frame time for them; the slow area is there at once.

## Speed while wading (TESTWERT).
const SLOW_FACTOR := 0.7
## A pool picture that arrives later fades in over this time (s).
const FADE_IN := 0.25
const Z := 1

var _area: Area2D = null
## Players wading right now: instance id -> player (no typed keys, a freed player must not crash).
var _slowed := {}


## Pictures and slow area over water_tiles (layer cells) of a layer with tiles of art_tile px.
func build(water_tiles: Array[Vector2i], art_tile: float, biome_id: StringName) -> void:
	name = "ShallowWater"
	z_index = Z
	_area = Area2D.new()
	_area.name = "Area"
	_area.collision_layer = 0
	_area.collision_mask = PhysicsLayers.PLAYER
	_area.monitorable = false
	add_child(_area)
	for pool in pools(water_tiles):
		var box := WaterArt.bounds(pool)
		var sprite := AnimatedProp.new()
		sprite.name = "Pool"
		sprite.frame_size = box.size * WaterArt.TILE
		sprite.fps = WaterArt.FPS
		sprite.pivot = Vector2.ZERO
		sprite.position = Vector2(box.position) * art_tile
		sprite.scale = Vector2.ONE * art_tile / float(WaterArt.TILE)
		add_child(sprite)
		var strip := WaterArt.request_pool(pool, biome_id, _show_pool.bind(sprite))
		if strip != null:
			sprite.strip = strip
		else:
			sprite.modulate.a = 0.0
	for tile in water_tiles:
		var shape := RectangleShape2D.new()
		shape.size = Vector2.ONE * art_tile
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = (Vector2(tile) + Vector2(0.5, 0.5)) * art_tile
		_area.add_child(collision)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


## Connected pools (4-neighbours) of the water tiles, each sorted (stable shapes).
static func pools(water_tiles: Array[Vector2i]) -> Array[Array]:
	var left: Dictionary[Vector2i, bool] = {}
	for tile in water_tiles:
		left[tile] = true
	var result: Array[Array] = []
	var sorted := water_tiles.duplicate()
	sorted.sort()
	for start: Vector2i in sorted:
		if not left.has(start):
			continue
		var pool: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		left.erase(start)
		while not queue.is_empty():
			var tile: Vector2i = queue.pop_back()
			pool.append(tile)
			for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if left.has(tile + direction):
					left.erase(tile + direction)
					queue.append(tile + direction)
		pool.sort()
		result.append(pool)
	return result


## A pool picture built on a worker thread arrived (main thread).
func _show_pool(strip: Texture2D, sprite: AnimatedProp) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.strip = strip
	if sprite.is_inside_tree():
		sprite.create_tween().tween_property(sprite, "modulate:a", 1.0, FADE_IN)
	else:
		sprite.modulate.a = 1.0


## Are all pool pictures shown?
func is_ready() -> bool:
	for child in get_children():
		if child is AnimatedProp and (child as AnimatedProp).strip == null:
			return false
	return true


func is_slowing(player: Player) -> bool:
	return player != null and _slowed.has(player.get_instance_id())


func _exit_tree() -> void:
	for player in _slowed.values():
		if is_instance_valid(player):
			ToxicPuddle.apply_slow(player as Player, get_instance_id(), 1.0)
	_slowed.clear()


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or _slowed.has(player.get_instance_id()):
		return
	_slowed[player.get_instance_id()] = player
	ToxicPuddle.apply_slow(player, get_instance_id(), SLOW_FACTOR)


func _on_body_exited(body: Node2D) -> void:
	var player := body as Player
	if player == null or not _slowed.has(player.get_instance_id()):
		return
	_slowed.erase(player.get_instance_id())
	if is_instance_valid(player):
		ToxicPuddle.apply_slow(player, get_instance_id(), 1.0)
