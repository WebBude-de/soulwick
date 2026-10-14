class_name ShallowWater
extends Node2D
## Shallow water or mud of a room plan (R1, plan cell 'w'): ordinary floor under a glittering
## overlay (shallow_water_4f) that slows every player wading through it. Enemies wade at full
## speed (their home; no speed modifier on enemies yet). Built by RoomTiles from water_rects, in
## the layer's space (one art tile per floor tile). Per-player state: the slow lives on the player
## (ToxicPuddle.apply_slow, one source per water area), so any number of players works (D-088).

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
	for tile in water_tiles:
		var sprite := AnimatedProp.new()
		sprite.frame_size = FRAME
		sprite.fps = FPS
		sprite.pivot = Vector2.ZERO
		sprite.strip = ART
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
