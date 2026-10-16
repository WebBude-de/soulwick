class_name SideGate
extends Area2D
## The doorway into a side segment (M5): a trigger over the corridor between a room's exit door and
## the next room's entrance. The first player who walks in starts the way (passed); the layout, the
## seed and where the players come out are decided already (SideWays.plan). It lives under the room
## it leads out of, so it goes with that room.

signal passed(gate: SideGate, player: Player)

## How far the trigger reaches to both sides of the corridor's middle line.
const HALF_WIDTH := 30.0

var layout: SideLayout = null
var reason := SideRules.Reason.NONE
var from_room: RoomController = null
var next_room: RoomController = null
var rng_seed := 0
var is_used := false
## The covered way (global), see cover().
var _rect := Rect2()


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	monitorable = false
	body_entered.connect(_on_body_entered)


## Covers the way from one global point to another (door tile centres), HALF_WIDTH to each side.
func cover(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, Vector2.ZERO).expand(to).grow(HALF_WIDTH)
	_rect = rect
	global_position = rect.get_center()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.name = "Shape"
	collision.shape = shape
	add_child(collision)


## Does the gate's way cover point (global)? Co-op: who stands here waits for the others
## (NetSide; the way starts once every living player is here or its time is up).
## margin: px around the way (a body touches the trigger before its origin is inside).
func covers(point: Vector2, margin := 0.0) -> bool:
	return _rect.has_area() and _rect.grow(margin).has_point(point)


## Puts every player just inside the next room's entrance (SideTransit's on_finished): the room's
## enter trigger sees them and the room starts as if they had walked in.
func place_players(players: Array) -> void:
	if not is_instance_valid(next_room):
		return
	var start := next_room.get_player_start()
	var spread := 0
	for player: Player in players:
		if not is_instance_valid(player):
			continue
		player.global_position = start + Vector2(spread * 24.0, 0.0)
		player.velocity = Vector2.ZERO
		spread += 1


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if is_used or player == null or not player.is_alive():
		return
	is_used = true
	passed.emit(self, player)
