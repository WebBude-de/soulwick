class_name ShallowWater
extends Node2D
## Shallow water or mud of a room plan (R1, plan cell 'w'): ordinary floor under a glittering
## overlay (shallow_water_4f) that slows every player wading through it. Enemies wade at full
## speed (their home; no speed modifier on enemies yet). Built by RoomTiles from water_rects, in
## the layer's space (one art tile per floor tile). Per-player state: the slow lives on the player
## (ToxicPuddle.apply_slow, one source per water area), so any number of players works (D-088).
## The water has a soft outline (M1, playtest 14.10.2026: no square pools): every tile's strip is cut
## to a rounded shape from its neighbours - open sides inset a little, a corner whose two sides are
## open rounded - until shallow_water_edge art comes (SPRITES_V8).

## Speed while wading (TESTWERT).
const SLOW_FACTOR := 0.7
const ART: Texture2D = preload("res://art/environment/deco/shallow_water_4f.png")
const FRAME := Vector2i(32, 32)
const FPS := 3.0
## Overlay colour per biome: clear water, green slime water, dark ink, ash mud. Optics only.
const BIOME_TINTS := {
	&"crypt": Color(0.75, 0.82, 1.0, 0.85),
	&"slime_grotto": Color(0.72, 1.0, 0.72, 0.9),
	&"shadow_realm": Color(0.72, 0.6, 1.0, 0.85),
	&"ember_forge": Color(1.0, 0.62, 0.42, 0.8),
}
const Z := 1
## Rounded outline (art px, TESTWERTE, look): inset of an open side, radius of an open corner.
const EDGE_INSET := 2
const CORNER_RADIUS := 11
## Cut strips per outline mask (4 bits open side N=1 E=2 S=4 W=8), shared by every pool.
static var _strips: Dictionary[int, Texture2D] = {}

var _area: Area2D = null
## Players wading right now: instance id -> player (no typed keys, a freed player must not crash).
var _slowed := {}


## Overlay and slow area over water_tiles (layer cells) of a layer with tiles of art_tile px.
func build(water_tiles: Array[Vector2i], art_tile: float, biome_id: StringName) -> void:
	name = "ShallowWater"
	z_index = Z
	var tint: Color = BIOME_TINTS.get(biome_id, BIOME_TINTS[&"crypt"])
	_area = Area2D.new()
	_area.name = "Area"
	_area.collision_layer = 0
	_area.collision_mask = PhysicsLayers.PLAYER
	_area.monitorable = false
	add_child(_area)
	var water: Dictionary[Vector2i, bool] = {}
	for tile in water_tiles:
		water[tile] = true
	for tile in water_tiles:
		var sprite := AnimatedProp.new()
		sprite.frame_size = FRAME
		sprite.fps = FPS
		sprite.pivot = Vector2.ZERO
		sprite.strip = strip_for(open_sides(tile, water))
		sprite.position = Vector2(tile) * art_tile
		sprite.modulate = tint
		add_child(sprite)
		sprite.frame = absi(tile.x * 7 + tile.y * 3) % 4
		var shape := RectangleShape2D.new()
		shape.size = Vector2.ONE * art_tile
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = (Vector2(tile) + Vector2(0.5, 0.5)) * art_tile
		_area.add_child(collision)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


## Open sides of a water tile (no water there): N=1 E=2 S=4 W=8.
static func open_sides(tile: Vector2i, water: Dictionary[Vector2i, bool]) -> int:
	var mask := 0
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i in directions.size():
		if not water.has(tile + directions[i]):
			mask |= 1 << i
	return mask


## The water strip cut to the outline of a tile with these open sides (cached).
static func strip_for(open: int) -> Texture2D:
	if open == 0:
		return ART
	if _strips.has(open):
		return _strips[open]
	var image := ART.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var frames := image.get_width() / FRAME.x
	for f in frames:
		for y in FRAME.y:
			for x in FRAME.x:
				if not inside_outline(x, y, open):
					image.set_pixel(f * FRAME.x + x, y, Color(0, 0, 0, 0))
	var texture := ImageTexture.create_from_image(image)
	_strips[open] = texture
	return texture


## Is art pixel (x, y) of a tile inside its rounded outline?
static func inside_outline(x: int, y: int, open: int) -> bool:
	var left := EDGE_INSET if open & 8 else 0
	var right := FRAME.x - 1 - (EDGE_INSET if open & 2 else 0)
	var top := EDGE_INSET if open & 1 else 0
	var bottom := FRAME.y - 1 - (EDGE_INSET if open & 4 else 0)
	if x < left or x > right or y < top or y > bottom:
		return false
	var corners: Array = [[open & 1 and open & 8, left + CORNER_RADIUS, top + CORNER_RADIUS], [open & 1 and open & 2, right - CORNER_RADIUS, top + CORNER_RADIUS], [open & 4 and open & 8, left + CORNER_RADIUS, bottom - CORNER_RADIUS], [open & 4 and open & 2, right - CORNER_RADIUS, bottom - CORNER_RADIUS]]
	for corner: Array in corners:
		if not corner[0]:
			continue
		var cx: int = corner[1]
		var cy: int = corner[2]
		var beyond_x := (x < cx) if cx == left + CORNER_RADIUS else (x > cx)
		var beyond_y := (y < cy) if cy == top + CORNER_RADIUS else (y > cy)
		if beyond_x and beyond_y and Vector2(x - cx, y - cy).length() > CORNER_RADIUS + 0.5:
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
