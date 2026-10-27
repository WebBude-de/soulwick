class_name TutorialArea
extends Node2D
## The hall of the practice run (WK10), built from TutorialPlans.HALL: crypt masonry painted by
## RoomTiles (floor, inner walls, the abyss of station 2; collision and the pit layer like any room),
## torches on the north wall, the station signs with their flags, the straw dummies, the shield
## dummy, the doors between the stations (Door, side doors, shut until the station before is done),
## the door to the side-view stretch with its trigger, the "Kenne ich schon" shortcut and the gate
## "Dungeon" at the end. No logic beyond the build and the questions TutorialRun asks (where things
## are, which door belongs to what); signals pass the triggers on.

signal shortcut_used(player: Player)
signal gate_passed(player: Player)
signal jump_door_entered(player: Player)

const BIOME: StringName = &"crypt"
const DOOR_SCENE: PackedScene = preload("res://dungeon/environment/doors/door.tscn")
const TORCH_SCENE: PackedScene = preload("res://dungeon/environment/decorations/torch.tscn")
const BASE_TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"
const TILE := RoomTiles.TILE_WORLD
## Things standing on a tile stand this far below its centre (their feet).
const FEET_IN_TILE := 16.0
## Floor pattern of the hall (no dungeon RNG).
const FLOOR_SEED := 1010
## The jump door's trigger: the west half of its tile (px).
const JUMP_TRIGGER := Vector2(28, 56)

var tiles: RoomTiles = null
var dummies: Array[TutorialDummy] = []
var shield_dummy: TutorialDummy = null
var signs: Array[TutorialSign] = []
## Doors in the walls, west to east: after the welcome, after station 1, after station 4.
var doors: Array[Door] = []
var jump_door: Door = null
var gate: TutorialGate = null
var shortcut: TutorialShortcut = null

var _jump_trigger: Area2D = null
var _jump_trigger_armed := false


func _ready() -> void:
	name = "TutorialArea"
	y_sort_enabled = true
	_build_tiles()
	_build_torches()
	_build_signs()
	_build_dummies()
	_build_doors()
	_build_gate()
	_build_shortcut()


# --- Where things are (global) ---

## Feet of the player at the start.
func get_start_feet() -> Vector2:
	return to_global(_feet(TutorialPlans.find_one(TutorialPlans.START)))


## Feet where the player comes back out of the side-view stretch.
func get_jump_exit_feet() -> Vector2:
	return to_global(_feet(TutorialPlans.find_one(TutorialPlans.JUMP_EXIT)))


## East edge of the abyss (station 2 is done beyond it).
func get_pit_east_x() -> float:
	var rect := TutorialPlans.pit_rects()[0]
	return to_global(RoomTiles.tile_to_local(Vector2i(rect.end.x, 0))).x


## West edge of the abyss.
func get_pit_west_x() -> float:
	var rect := TutorialPlans.pit_rects()[0]
	return to_global(RoomTiles.tile_to_local(rect.position)).x


## A point to stand on right before the abyss, in the doors' row (tools: the bot dashes from here).
func get_pit_run_up_feet() -> Vector2:
	var rect := TutorialPlans.pit_rects()[0]
	var row := TutorialPlans.door_cells()[0].y
	return to_global(RoomTiles.tile_center(Vector2i(rect.position.x - 1, row)) + Vector2(14, 0))


## x from which a player is in a station's part of the hall: 0..3 the stations, 4 the end.
func get_zone_start_x(zone: int) -> float:
	var walls := TutorialPlans.door_cells()
	var column := 0
	match zone:
		0:
			column = walls[0].x + 1
		1:
			column = walls[1].x + 1
		2:
			column = TutorialPlans.pit_rects()[0].end.x
		3:
			column = TutorialPlans.find_one(TutorialPlans.JUMP_EXIT).x
		_:
			column = walls[walls.size() - 1].x + 1
	return to_global(RoomTiles.tile_to_local(Vector2i(column, 0))).x


## Centre of a station (camera goal of the welcome tour), global.
func get_sign_point(station: int) -> Vector2:
	return to_global(RoomTiles.tile_center(TutorialPlans.sign_cell(station)))


## The middle of the gate's doorway (the bot walks there).
func get_gate_feet() -> Vector2:
	return to_global(RoomTiles.tile_center(TutorialPlans.find_one(TutorialPlans.GATE)) + Vector2(0, -TILE * 0.7))


## The tile in front of a door (west side), global feet.
func get_door_front_feet(door: Door) -> Vector2:
	return door.global_position + Vector2(-TILE * 0.5, TILE * 0.5)


## The flag of a station.
func get_flag(station: int) -> TutorialFlag:
	return signs[station].flag if station < signs.size() else null


## Opens the trigger of the jump door (the dash station is done; the door is open).
func arm_jump_door(armed: bool) -> void:
	_jump_trigger_armed = armed
	if _jump_trigger != null:
		_jump_trigger.set_deferred(&"monitoring", armed)


# --- Build ---

func _feet(cell: Vector2i) -> Vector2:
	return RoomTiles.tile_center(cell) + Vector2(0, FEET_IN_TILE)


func _build_tiles() -> void:
	tiles = RoomTiles.new()
	tiles.name = "Tiles"
	tiles.z_index = -10
	tiles.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	var tileset := RoomController._load_biome_tileset(BIOME)
	tiles.tile_set = tileset if tileset != null else load(BASE_TILESET_PATH) as TileSet
	var gate_cell := TutorialPlans.find_one(TutorialPlans.GATE)
	tiles.room_size = TutorialPlans.hall_size()
	# One opening only: the gate in the north wall (the hall is entered by a fade, not a door).
	tiles.entrance_side = RoomTiles.DoorSide.NORTH
	tiles.entrance_x = gate_cell.x
	tiles.exit_side = RoomTiles.DoorSide.NORTH
	tiles.exit_x = gate_cell.x
	tiles.rock_style = RoomTiles.RockStyle.WALL
	tiles.floor_seed = FLOOR_SEED
	tiles.wall_rects = TutorialPlans.wall_rects()
	tiles.pit_rects = TutorialPlans.pit_rects()
	add_child(tiles)


## One torch above the middle of every part of the hall between two walls (not over the abyss or the
## gate).
func _build_torches() -> void:
	var size := TutorialPlans.hall_size()
	var walls: Array[int] = [-1]
	for rect in TutorialPlans.wall_rects():
		if not walls.has(rect.position.x):
			walls.append(rect.position.x)
	walls.append(size.x)
	walls.sort()
	var blocked: Array[int] = [TutorialPlans.find_one(TutorialPlans.GATE).x]
	for rect in TutorialPlans.pit_rects():
		blocked.append(rect.position.x)
	for i in walls.size() - 1:
		var column := floori((walls[i] + walls[i + 1]) / 2.0)
		while blocked.has(column) and column > walls[i] + 1:
			column -= 1
		if column <= walls[i] or blocked.has(column):
			continue
		var torch := TORCH_SCENE.instantiate() as Node2D
		torch.name = "Torch%d" % i
		torch.position = RoomTiles.tile_to_local(Vector2i(column, -1))
		add_child(torch)


func _build_signs() -> void:
	for station in TutorialRules.STATIONS:
		var sign := TutorialSign.new(station)
		sign.position = _feet(TutorialPlans.sign_cell(station))
		add_child(sign)
		signs.append(sign)


func _build_dummies() -> void:
	for cell in TutorialPlans.find(TutorialPlans.DUMMY):
		var dummy := TutorialDummy.new()
		dummy.name = "Dummy%d" % (dummies.size() + 1)
		dummy.position = _feet(cell)
		add_child(dummy)
		dummies.append(dummy)
	shield_dummy = TutorialDummy.new()
	shield_dummy.name = "ShieldDummy"
	shield_dummy.shielded = true
	shield_dummy.position = _feet(TutorialPlans.find_one(TutorialPlans.SHIELD_DUMMY))
	add_child(shield_dummy)


func _build_doors() -> void:
	for cell in TutorialPlans.door_cells():
		doors.append(_door(cell, "Door%d" % (doors.size() + 1)))
	jump_door = _door(TutorialPlans.find_one(TutorialPlans.JUMP_DOOR), "JumpDoor")
	_jump_trigger = Area2D.new()
	_jump_trigger.name = "JumpTrigger"
	_jump_trigger.collision_layer = 0
	_jump_trigger.collision_mask = PhysicsLayers.PLAYER
	_jump_trigger.monitorable = false
	_jump_trigger.monitoring = _jump_trigger_armed
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = JUMP_TRIGGER
	shape.shape = rect
	_jump_trigger.add_child(shape)
	_jump_trigger.position = RoomTiles.tile_to_local(TutorialPlans.find_one(TutorialPlans.JUMP_DOOR)) + Vector2(JUMP_TRIGGER.x * 0.5, TILE * 0.5)
	_jump_trigger.body_entered.connect(_on_jump_trigger_entered)
	add_child(_jump_trigger)


func _door(cell: Vector2i, door_name: String) -> Door:
	var door := DOOR_SCENE.instantiate() as Door
	door.name = door_name
	door.position = RoomTiles.tile_to_local(cell)
	door.configure(BIOME)
	door.set_side(RoomTiles.DoorSide.EAST)
	add_child(door)
	door.set_open_instant(false)
	return door


func _build_gate() -> void:
	gate = TutorialGate.new()
	gate.name = "Gate"
	gate.position = RoomTiles.tile_to_local(TutorialPlans.find_one(TutorialPlans.GATE)) + Vector2(TILE * 0.5, 0)
	gate.passed.connect(func(player: Player) -> void: gate_passed.emit(player))
	add_child(gate)


func _build_shortcut() -> void:
	shortcut = TutorialShortcut.new()
	shortcut.position = _feet(TutorialPlans.find_one(TutorialPlans.SHORTCUT))
	shortcut.interacted.connect(func(player: Player) -> void: shortcut_used.emit(player))
	add_child(shortcut)


func _on_jump_trigger_entered(body: Node2D) -> void:
	var player := body as Player
	if not _jump_trigger_armed or player == null or not player.is_alive():
		return
	arm_jump_door(false)
	jump_door_entered.emit(player)
