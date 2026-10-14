class_name BranchChoice
extends Node2D
## The choice of a branch room (D-105): one zone in front of each exit door. Once the room is
## cleared (offer()), the group decides by walking up to a door: all living players at one door ->
## that way at once; split over both doors -> after BranchRules.VOTE_TIMEOUT the door with more
## players, a tie drawn with the dungeon RNG (BranchRules.resolve_vote). The choice holds for the
## whole group. Only the decision lives here (decided signal); the room opens and seals the doors.

signal offered(choice: BranchChoice)
signal decided(choice: BranchChoice, index: int)

const NODE_NAME := &"BranchChoice"
## Zone in front of a door: this many rows of three tiles straight in from it.
const ZONE_DEPTH := 2

var room: RoomController = null
## Room-local door places (Vector2i(side, place)), same order as the room's exits.
var doors: Array[Vector2i] = []
var is_offered := false
var chosen := -1

var _zones: Array[Area2D] = []
var _waited := 0.0


static func create(target: RoomController, exit_doors: Array[Vector2i]) -> BranchChoice:
	var choice := BranchChoice.new()
	choice.name = NODE_NAME
	choice.room = target
	choice.doors = exit_doors.duplicate()
	return choice


func _ready() -> void:
	for i in doors.size():
		var zone := Area2D.new()
		zone.name = "Zone%d" % i
		zone.collision_layer = 0
		zone.collision_mask = PhysicsLayers.PLAYER
		zone.monitorable = false
		zone.monitoring = false
		var lane := RoomTiles.door_lane_of(doors[i].x, doors[i].y, room.tiles.room_size, ZONE_DEPTH)
		var rect := Rect2(RoomTiles.tile_to_local(lane[0]), Vector2.ZERO)
		for tile in lane:
			rect = rect.merge(Rect2(RoomTiles.tile_to_local(tile), Vector2.ONE * RoomTiles.TILE_WORLD))
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = rect.get_center()
		zone.add_child(collision)
		add_child(zone)
		_zones.append(zone)


## The room is cleared: the doors wait for the group.
func offer() -> void:
	if is_offered or chosen >= 0:
		return
	is_offered = true
	for zone in _zones:
		zone.monitoring = true
	offered.emit(self)


## Decision for door index (players, the vote, tests). Once.
func choose(index: int) -> bool:
	if chosen >= 0 or index < 0 or index >= doors.size():
		return false
	chosen = index
	for zone in _zones:
		zone.set_deferred("monitoring", false)
	decided.emit(self, index)
	return true


## Living players standing in each zone (coop-ready: every player of the group, D-088).
func get_counts() -> Array[int]:
	var counts: Array[int] = []
	for zone in _zones:
		var count := 0
		if zone.monitoring:
			for body in zone.get_overlapping_bodies():
				if body is Player and EnemyTargeting.is_alive(body):
					count += 1
		counts.append(count)
	return counts


func _physics_process(delta: float) -> void:
	if not is_offered or chosen >= 0:
		return
	var players := EnemyTargeting.living_players(get_tree()).size()
	var counts := get_counts()
	var standing := 0
	for count in counts:
		standing += count
	_waited = _waited + delta if standing >= players and players > 0 else 0.0
	var tie_roll := 0.0
	if _waited >= BranchRules.VOTE_TIMEOUT and room != null and room.context != null and room.context.rng != null:
		# Only a split group that waited the full time draws (dungeon RNG).
		tie_roll = room.context.rng.randf()
	var index := BranchRules.resolve_vote(counts, players, _waited, tie_roll)
	if index >= 0:
		choose(index)
