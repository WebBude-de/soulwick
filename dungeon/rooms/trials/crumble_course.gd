class_name CrumbleCourse
extends TrialCourse
## Bröckelboden (KONZEPT_RAEUME §6.1, A4): cracked plates in the lanes of the parcours break
## CRUMBLE_DELAY after a player stepped on them and become abyss (RoomTiles.add_pit_tiles); one
## column per lane is an open gap from the start, one tile wide, to dash over. Some plates in each
## column stay solid (plain floor): the way to choose. Broken plates grow back after REGROW_TIME,
## so the course never closes for good (also for a second player, Koop).
## Falling follows the A4 rule (PlayerFall): the course deals no damage itself (get_damage stays 0),
## a fall counts as a mistake (TrialContent.register_fall), lands on the last solid tile the player
## stood on in the course and is capped like every trial mistake, so it never ends the run.
## Layout and timing come from the dungeon RNG; the state per player (last solid tile) lives here
## only for the length of the room.

enum Plate { INTACT, CRACKING, BROKEN }

## Seconds from the first step on a plate until it breaks (TESTWERT).
const CRUMBLE_DELAY := 0.6
## Seconds until a broken plate is floor again (TESTWERT).
const REGROW_TIME := 5.0
## Chance per lane column that one of its two plates is solid floor (TESTWERT).
const SOLID_CHANCE := 0.4
## Open gap columns per lane (one tile wide: a dash crosses it, D-086).
const GAPS_PER_LANE := 1
## Art: crumbling_floor_6f (SPRITES_V5 §4): 0 intact, 1 cracked (shown while waiting), 2-4 breaking,
## 5 empty (the abyss shows through).
const ART := "crumbling_floor_6f"
const ART_PATH := "res://art/environment/trials/crumbling_floor_6f.png"
const FRAME_WAITING := 1
const FRAME_BREAKING_FIRST := 2
const FRAME_BREAKING_LAST := 4
const FRAME_GONE := 5

## Tiles of the permanent gaps (pits from the start).
var gap_tiles: Array[Vector2i] = []
## Plate state and timer per crumbling tile.
var plates: Dictionary[Vector2i, Plate] = {}

var _timers: Dictionary[Vector2i, float] = {}
var _sprites: Dictionary[Vector2i, Sprite2D] = {}
## Room-local feet position of the last solid course tile per player (instance id).
var _last_solid: Dictionary[int, Vector2] = {}


static func is_available() -> bool:
	return true


func build(rng: RandomNumberGenerator) -> void:
	_build_lane(TrialLayout.LANE_A, TrialLayout.LANE_A_HAZARD_COLUMNS, rng)
	_build_lane(TrialLayout.LANE_B, TrialLayout.LANE_B_HAZARD_COLUMNS, rng)
	var tiles := _get_tiles()
	if tiles != null:
		tiles.add_pit_tiles(gap_tiles)


func advance(delta: float) -> void:
	var broken: Array[Vector2i] = []
	var regrown: Array[Vector2i] = []
	for tile in plates:
		match plates[tile]:
			Plate.CRACKING:
				_timers[tile] -= delta
				if _timers[tile] <= 0.0:
					plates[tile] = Plate.BROKEN
					_timers[tile] = REGROW_TIME
					broken.append(tile)
				else:
					_show_frame(tile, _breaking_frame(_timers[tile]))
			Plate.BROKEN:
				_timers[tile] -= delta
				if _timers[tile] <= 0.0:
					plates[tile] = Plate.INTACT
					regrown.append(tile)
	var tiles := _get_tiles()
	for tile in broken:
		_show_frame(tile, FRAME_GONE)
	if not broken.is_empty() and is_inside_tree():
		Sfx.play_at(self, &"plate_break", to_global(RoomTiles.tile_center(broken[0])), -8.0)
	for tile in regrown:
		_show_frame(tile, FRAME_WAITING)
	if tiles != null:
		tiles.add_pit_tiles(broken)
		tiles.remove_pit_tiles(regrown)


## Never damage: a step starts the crumbling, solid tiles are remembered as landing spots.
func get_damage(player: Player, feet: Vector2, _delta: float) -> float:
	step_on(player, RoomTiles.local_to_tile(feet))
	return 0.0


## A player's feet are on tile.
func step_on(player: Player, tile: Vector2i) -> void:
	if plates.has(tile):
		if plates[tile] == Plate.INTACT:
			plates[tile] = Plate.CRACKING
			_timers[tile] = CRUMBLE_DELAY
			_show_frame(tile, FRAME_BREAKING_FIRST)
			if is_inside_tree():
				Sfx.play_at(self, &"plate_crack", to_global(RoomTiles.tile_center(tile)), -10.0)
		return
	if gap_tiles.has(tile) or player == null:
		return
	# Solid course floor (start, turn, solid plates in the lanes): the next fall lands here.
	_last_solid[player.get_instance_id()] = RoomTiles.tile_center(tile)


func on_run_started(player: Player) -> void:
	if player == null or player.fall == null:
		return
	if not _last_solid.has(player.get_instance_id()):
		_last_solid[player.get_instance_id()] = _start_feet()
	if not player.fall.fall_started.is_connected(_on_player_fall_started):
		player.fall.fall_started.connect(_on_player_fall_started)


## Room-local feet position a fall of player lands on: the last solid course tile, else the start.
func get_landing(player: Player) -> Vector2:
	if player == null:
		return _start_feet()
	return _last_solid.get(player.get_instance_id(), _start_feet())


func is_crumbling_tile(tile: Vector2i) -> bool:
	return plates.has(tile)


func get_plate(tile: Vector2i) -> Plate:
	return plates.get(tile, Plate.INTACT)


# --- Fall (decision: TrialContent.register_fall; effect: PlayerFall) ---

func _on_player_fall_started(player: Player) -> void:
	if content == null or content.get_run_state(player) != TrialContent.RunState.RUNNING:
		return
	content.register_fall(player)
	var landing := get_landing(player)
	var global_landing := content.room.to_global(landing) if content.room != null else landing
	var damage := TrialRules.capped_damage(ChasmRules.fall_damage(), player.health.get_health(), 0.0)
	player.fall.set_landing(global_landing, damage)


# --- Layout ---

## One gap column, the rest of the hazard columns crumbling plates (some solid).
func _build_lane(lane: Rect2i, columns: Vector2i, rng: RandomNumberGenerator) -> void:
	var gap_columns: Array[int] = []
	for i in GAPS_PER_LANE:
		# Never at the ends: a solid or plate column on both sides to jump from and land on.
		var column := rng.randi_range(columns.x + 1, columns.y - 1)
		if not gap_columns.has(column):
			gap_columns.append(column)
	for column in range(columns.x, columns.y + 1):
		if gap_columns.has(column):
			for row in lane.size.y:
				gap_tiles.append(Vector2i(column, lane.position.y + row))
			continue
		var solid_row := rng.randi_range(0, lane.size.y - 1) if rng.randf() < SOLID_CHANCE else -1
		for row in lane.size.y:
			if row == solid_row:
				continue
			var tile := Vector2i(column, lane.position.y + row)
			plates[tile] = Plate.INTACT
			_add_plate_sprite(tile)


func _add_plate_sprite(tile: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(ART_PATH) as Texture2D if ResourceLoader.exists(ART_PATH) else null
	if sprite.texture == null:
		sprite.texture = TrialArt.get_texture(TrialArt.PLATE)
		sprite.hframes = 1
	else:
		sprite.hframes = 6
		sprite.frame = FRAME_WAITING
	sprite.centered = false
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	sprite.position = RoomTiles.tile_to_local(tile)
	# Floor overlay: below every character, above the floor tiles.
	sprite.z_index = -9
	add_child(sprite)
	_sprites[tile] = sprite


func _show_frame(tile: Vector2i, frame: int) -> void:
	var sprite: Sprite2D = _sprites.get(tile)
	if sprite == null or sprite.hframes <= 1:
		if sprite != null:
			sprite.visible = frame != FRAME_GONE
		return
	sprite.frame = frame


static func _breaking_frame(time_left: float) -> int:
	var progress := 1.0 - clampf(time_left / CRUMBLE_DELAY, 0.0, 1.0)
	return FRAME_BREAKING_FIRST + mini(FRAME_BREAKING_LAST - FRAME_BREAKING_FIRST, floori(progress * 3.0))


func _start_feet() -> Vector2:
	return RoomTiles.tile_center(Vector2i(TrialLayout.START.position.x, TrialLayout.START.end.y - 1))


func _get_tiles() -> RoomTiles:
	if content == null or content.room == null or not is_instance_valid(content.room):
		return null
	return content.room.tiles
