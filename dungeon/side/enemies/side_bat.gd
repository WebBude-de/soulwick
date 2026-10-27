class_name SideBat
extends SideEnemy
## Bat of a side segment (SV4, D-195): flies back and forth on a jump-shaped arc (a hump of
## ARC_HEIGHT over 2 x RANGE) above its plan cell, through the air a player jumps in. No gravity,
## no world collision; the path is a pure function of time, so it is the same for every seed
## phase and easy to plan (path_cells). Stompable and rammable like a slime. Placed only where its
## whole path is air (plan rule for SV2/SV3: path_cells).

const DATA: EnemyData = preload("res://dungeon/side/enemies/data/side_bat.tres")
## TESTWERTE (SV4): half the flight width, arc height, time for one arc, hover over the cell bottom.
const RANGE := 96.0
const ARC_HEIGHT := 80.0
const HALF_TRIP_TIME := 1.4
const HOVER := 16.0
const BODY := Vector2(24, 16)

var _anchor := Vector2.ZERO
## 0..2: [0, 1) flies right, [1, 2) flies left.
var _phase := 0.0


func setup(enemy_kind: Kind, index: int, owner_segment: SideSegment, rng_seed: int) -> void:
	super.setup(enemy_kind, index, owner_segment, rng_seed)
	_phase = _rng.randf() * 2.0


func _ready() -> void:
	super._ready()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_mask = 0
	_anchor = position + Vector2(0, -HOVER)
	position = path_point(_anchor, _phase)
	_facing = path_direction(_phase)
	_play(&"walk")


## Position on the arc for a phase in [0, 2) around anchor (feet of the hover point).
static func path_point(anchor: Vector2, phase: float) -> Vector2:
	var wrapped := fposmod(phase, 2.0)
	var t := wrapped if wrapped < 1.0 else wrapped - 1.0
	var x := lerpf(-RANGE, RANGE, t) if wrapped < 1.0 else lerpf(RANGE, -RANGE, t)
	return anchor + Vector2(x, -ARC_HEIGHT * sin(PI * t))


static func path_direction(phase: float) -> float:
	return 1.0 if fposmod(phase, 2.0) < 1.0 else -1.0


## Plan cells the bat's body passes through when placed on cell (all must be air).
static func path_cells(cell: Vector2i) -> Array[Vector2i]:
	var columns := ceili((RANGE + BODY.x * 0.5) / SideRules.TILE)
	var rows := ceili((ARC_HEIGHT + HOVER + BODY.y) / SideRules.TILE)
	var cells: Array[Vector2i] = []
	for row in range(cell.y - rows, cell.y + 1):
		for column in range(cell.x - columns, cell.x + columns + 1):
			cells.append(Vector2i(column, row))
	return cells


func get_body_size() -> Vector2:
	return BODY


func _default_data() -> EnemyData:
	return DATA


func _uses_side_art() -> bool:
	return true


func _move(delta: float) -> void:
	var before := position
	_phase = fposmod(_phase + delta / HALF_TRIP_TIME, 2.0)
	position = path_point(_anchor, _phase)
	_facing = path_direction(_phase)
	velocity = (position - before) / delta if delta > 0.0 else Vector2.ZERO
	_play(&"walk")


func _placeholder_look() -> int:
	return SideEnemyPlaceholder.Look.BAT
