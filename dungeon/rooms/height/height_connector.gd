class_name HeightConnector
extends Area2D
## Switch area on one stairs or ladder tile (M3, Makeover 3 §8): whoever leaves it onto a level has
## changed level (signal level_changed for effects; the level itself follows from the position,
## HeightRules). A ladder slows every player on it (the slow lives on the player, one source per
## ladder tile, like ShallowWater); enemies never get onto a ladder (PhysicsLayers.LADDER).

signal level_changed(body: Node2D, level: int)
signal climbing_changed(player: Player, climbing: bool)

var tile := Vector2i.ZERO
var is_ladder := false
## Bodies on the tile right now: instance id -> body (no typed keys, freed bodies must not crash).
var _inside := {}
## Level each of them came from (its shape touches the area before its centre is on the tile).
var _came_from := {}


## Area over tile (layer cell) of a layer with art_tile px per tile.
func setup(cell: Vector2i, ladder: bool, art_tile: float) -> void:
	tile = cell
	is_ladder = ladder
	name = "%s_%d_%d" % ["Ladder" if ladder else "Stairs", cell.x, cell.y]
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER | PhysicsLayers.ENEMIES
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * art_tile * 0.8
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	position = (Vector2(cell) + Vector2(0.5, 0.5)) * art_tile
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func is_climbing(player: Player) -> bool:
	return is_ladder and player != null and _inside.has(player.get_instance_id())


func _exit_tree() -> void:
	for body in _inside.values():
		if is_ladder and is_instance_valid(body) and body is Player:
			ToxicPuddle.apply_slow(body as Player, get_instance_id(), 1.0)
	_inside.clear()
	_came_from.clear()


func _on_body_entered(body: Node2D) -> void:
	if _inside.has(body.get_instance_id()):
		return
	_inside[body.get_instance_id()] = body
	_came_from[body.get_instance_id()] = HeightRules.level_of(body)
	var player := body as Player
	if is_ladder and player != null:
		ToxicPuddle.apply_slow(player, get_instance_id(), HeightRules.LADDER_SLOW)
		climbing_changed.emit(player, true)


func _on_body_exited(body: Node2D) -> void:
	if not _inside.has(body.get_instance_id()):
		return
	_inside.erase(body.get_instance_id())
	var came_from: int = _came_from.get(body.get_instance_id(), HeightRules.BOTH)
	_came_from.erase(body.get_instance_id())
	if not is_instance_valid(body):
		return
	var player := body as Player
	if is_ladder and player != null:
		ToxicPuddle.apply_slow(player, get_instance_id(), 1.0)
		climbing_changed.emit(player, false)
	var level := HeightRules.level_of(body)
	if level != HeightRules.BOTH and level != came_from:
		level_changed.emit(body, level)
