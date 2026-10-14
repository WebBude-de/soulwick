class_name RoomController
extends Node2D
## One room instance: doors, encounter state and completion (D-008).
## PREPARED (instantiated, nothing spawned) -> ACTIVE (player entered) -> CLEARED -> UNLOADED.
## The encounter starts on the first real entry only, exactly once; completion is reported once.
## A campfire (D-103) is a room instance without a room number of its own: no encounter, no
## completion signal, no EventBus room events; its floor blends from the old into the next biome.
## Doors (A10): the entrance and the exit(s) may sit in any wall (RoomTiles.entrance_side/exit_side);
## the DungeonManager sets them with apply_door_plan() before the room enters the tree. A branch room
## (D-105) has two exits; after the fight the group picks one (BranchChoice), the other is sealed.

signal player_entered(room: RoomController)
signal completed(room: RoomController)
signal encounter_started(room: RoomController, enemies: Array[Enemy])
signal wave_started(room: RoomController, wave: int, total: int)
## An arena fight begins (A5): on entry, for an ambush when the entrance door has closed. Hook
## for the arena/ambush banner and the first-time explanation (UX2, D-110; texts in WaveRules).
signal arena_started(room: RoomController, ambush: bool)
## Branch room (D-105): the doors wait for the group (after the fight) / a way was chosen. The
## DungeonManager prepares room n+1 for the chosen way when branch_chosen comes.
signal branch_offered(room: RoomController)
signal branch_chosen(room: RoomController, index: int)

enum State { PREPARED, ACTIVE, CLEARED, UNLOADED }

const DOOR_SCENE: PackedScene = preload("res://dungeon/environment/doors/door.tscn")
## Biome tileset per BiomeData.id (built by tools/build_tilesets.gd); the crypt uses the base set.
const BIOME_TILESET_PATH := "res://dungeon/environment/%s_tileset.tres"
const BIOME_TORCHES := {
	&"slime_grotto": "res://art/environment/props/torch_green_4f.png",
	&"shadow_realm": "res://art/environment/props/torch_purple_4f.png",
}
## Template torches on the north wall give way to a door this close (columns): the branch doors
## bring their own torches (D1, A10).
const DOOR_TORCH_CLEARANCE := 2
## Rows of three tiles in front of each door kept free of ingredients (like IngredientScatter's lanes).
const DOOR_LANE_DEPTH := 3
## Fewest spawn markers the EnemySpawner accepts (D-086). The spawner takes all 5-14 markers of a
## template; more enemies than markers come as an extra wave (WaveRules).
const SPAWNER_MARKER_COUNT := EnemySpawner.MIN_SPAWN_POINTS
const PORTAL_SCENE: PackedScene = preload("res://dungeon/rooms/special/exit_portal.tscn")
const SPECIAL_SCENES := {
	RoomSequence.SpecialType.SHOP: preload("res://dungeon/rooms/special/shop_content.tscn"),
	RoomSequence.SpecialType.WEAPON: preload("res://dungeon/rooms/special/weapon_content.tscn"),
	RoomSequence.SpecialType.FOUNTAIN: preload("res://dungeon/rooms/special/fountain_content.tscn"),
	RoomSequence.SpecialType.UPGRADE: preload("res://dungeon/rooms/special/altar_content.tscn"),
	RoomSequence.SpecialType.TRIAL: preload("res://dungeon/rooms/trials/trial_content.tscn"),
}
## Campfire floor blend (TESTWERTE): rows above the entrance that stay fully in the old biome and
## rows below the exit that are already fully in the new one; in between the dithered blend.
const CAMPFIRE_OLD_ROWS := 1.5
const CAMPFIRE_NEW_ROWS := 2.0

## Kind and size class of a combat template (D-086), written by tools/generate_room_templates.py
## and read by RoomCatalog. Without meaning for special, miniboss and boss rooms.
@export var room_kind: RoomSequence.RoomKind = RoomSequence.RoomKind.NORMAL
@export var room_size_class: RoomSequence.RoomSize = RoomSequence.RoomSize.S

var room_index := 0
## Place of this instance in the room stack (RoomSequence slots); differs from room_index after the
## first campfire. 0 = not set (tests), then room_index is used.
var slot_index := 0
var room_type := RoomSequence.RoomType.COMBAT
## Kind the room sequence asked for (-1 for non-combat rooms); differs from room_kind when no
## template of that kind exists and the room fell back to an arena.
var rolled_kind := -1
var special_type := -1
var has_portal := false
var is_extra_dark := false
var state := State.PREPARED
var context: DungeonContext = null

var _encounter_started := false
var _completion_reported := false
var _alive_enemies := 0
var _entered := false
var _waves_total := 1
var _waves_spawned := 0
## Arena (A5): waves come out of the walls, the next one at <= 1 enemy left (WaveRules).
var is_arena := false
var is_ambush := false
## -1 = roll the ambush (dungeon RNG), 0/1 = force it (tests, tools, later room data).
var forced_ambush := -1
var _arena: ArenaWaves = null
## Arena gates and wave picks draw from this RNG, seeded once from the dungeon RNG in _ready, so
## the dungeon stream is used the same way however the players move.
var _wave_rng: RandomNumberGenerator = null
## Enemy count per wave, planned when the encounter starts (overflow included, D-086).
var _wave_sizes: Array[int] = []
## Living enemies per wave (index = wave number, summons count to their summoner's wave).
var _wave_alive: Array[int] = []
var _next_wave_queued := false
var _entrance_door: Door = null
## The exit the way leads through: the only one, or the chosen one of a branch room.
var _exit_door: Door = null
## Every exit door, in the order of RoomTiles.get_exit_doors() (two in a branch room).
var _exit_doors: Array[Door] = []
## The two ways of a branch room (BranchOption, same order as the exits); empty otherwise.
var branch_options: Array[BranchOption] = []
var _branch_choice: BranchChoice = null

@onready var tiles: RoomTiles = $Tiles
@onready var enemy_container: Node2D = $EnemyContainer
@onready var spawn_points: Node2D = $SpawnPoints
@onready var content_anchor: Marker2D = $ContentAnchor
@onready var portal_anchor: Marker2D = $PortalAnchor
@onready var spawner: EnemySpawner = $EnemySpawner
@onready var _enter_trigger: Area2D = $EnterTrigger


## Called before the room enters the tree.
func setup(index: int, type: RoomSequence.RoomType, special: int, portal: bool, dungeon_context: DungeonContext, extra_dark := false) -> void:
	is_extra_dark = extra_dark
	room_index = index
	room_type = type
	special_type = special
	has_portal = portal
	context = dungeon_context


func _ready() -> void:
	if slot_index <= 0:
		slot_index = room_index
	# The template's own tileset: the crypt look, which has no biome tileset of its own.
	var base_tileset := tiles.tile_set
	var biome := spawner.get_biome(room_index)
	if biome != null:
		_apply_biome_tiles(biome)
		if is_campfire():
			_apply_campfire_look(get_next_biome(), base_tileset)
		else:
			_apply_biome_torches(biome.id)
	# Crates and barrels sort by their base line against the characters' feet (UX1 finding).
	for prop in get_node("Props").get_children():
		if prop is Breakable:
			SortLift.lift(prop)
	# Own navigation map per room: rooms share one corridor tile, merged maps warn about double
	# edges (A2). Enemies only walk inside their room.
	EnemyNavigation.isolate_room_navigation(tiles)
	_block_prop_navigation()
	_hide_torches_at_doors()
	_entrance_door = _create_door(get_entrance_tile(), tiles.entrance_side)
	for exit in tiles.get_exit_doors():
		_exit_doors.append(_create_door(RoomTiles.door_tile_of(exit.x, exit.y, tiles.room_size), exit.x))
	_exit_door = _exit_doors[0]
	# Doors in the biome's style (D1): the entrance shows this room, the exit the next slot (boss
	# gate before a boss, flame sign before the campfire). A campfire's exit is already in the new biome.
	var door_biome: StringName = biome.id if biome != null else &""
	_entrance_door.configure_for_room(door_biome, room_type, special_type, true)
	var next_biome := get_next_biome() if is_campfire() else null
	var next_type := RoomSequence.get_slot_type(slot_index + 1)
	for i in _exit_doors.size():
		var door := _exit_doors[i]
		if is_branch_room() and i < branch_options.size():
			# Each way shows what waits behind it (D-105): its special sign or a branch sign.
			var option := branch_options[i]
			door.configure_for_room(door_biome, option.get_room_type(next_type), option.special_type)
			if option.is_combat():
				door.set_branch_symbol(option.get_symbol())
		else:
			door.configure_for_room(next_biome.id if next_biome != null else door_biome, next_type)
		door.set_open_instant(false)
	# Room 1 has nothing behind its entrance.
	_entrance_door.set_open_instant(room_index > 1)
	if is_branch_room():
		_branch_choice = BranchChoice.create(self, tiles.get_exit_doors())
		add_child(_branch_choice)
		_branch_choice.decided.connect(_on_branch_decided)
	_setup_enter_trigger()
	_setup_waves()
	if is_campfire():
		# Built right away: the fire already glows through the open door of the boss room.
		_build_campfire_content()


## Wall tile of the entrance door (any wall, A10).
func get_entrance_tile() -> Vector2i:
	return RoomTiles.door_tile_of(tiles.entrance_side, tiles.entrance_x, tiles.room_size)


## Wall tile of the exit the way leads through (the chosen one in a branch room).
func get_exit_tile() -> Vector2i:
	var exit := get_chosen_exit()
	return RoomTiles.door_tile_of(exit.x, exit.y, tiles.room_size)


## Wall tiles of every exit door.
func get_exit_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for exit in tiles.get_exit_doors():
		result.append(RoomTiles.door_tile_of(exit.x, exit.y, tiles.room_size))
	return result


## The exit the next room joins: Vector2i(side, place). A branch room answers with its chosen way
## (the first one before the choice).
func get_chosen_exit() -> Vector2i:
	var exits := tiles.get_exit_doors()
	var index := _branch_choice.chosen if _branch_choice != null and _branch_choice.chosen >= 0 else 0
	return exits[clampi(index, 0, exits.size() - 1)]


## Where a freshly spawned player starts in room 1: just inside the entrance.
func get_player_start() -> Vector2:
	var inward := -RoomTiles.SIDE_DIRECTIONS[tiles.entrance_side]
	return to_global(RoomTiles.tile_center(tiles.get_entrance_inside_tile() + inward))


## Doors of this room before it enters the tree (A10, DungeonManager): entrance as
## Vector2i(side, place), exits likewise (two for a branch room, with their ways in options), the
## extra entrance corridor. The ingredient scatter keeps every door lane free.
func apply_door_plan(entrance: Vector2i, exits: Array[Vector2i], corridor_extra := 0, options: Array[BranchOption] = []) -> void:
	var room_tiles := get_node("Tiles") as RoomTiles
	room_tiles.entrance_side = entrance.x as RoomTiles.DoorSide
	room_tiles.entrance_x = entrance.y
	room_tiles.entrance_corridor_extra = corridor_extra
	if not exits.is_empty():
		room_tiles.exit_side = exits[0].x as RoomTiles.DoorSide
		room_tiles.exit_x = exits[0].y
	room_tiles.branch_exit = exits[1] if exits.size() > 1 else Vector2i(RoomTiles.NO_DOOR, 0)
	branch_options.clear()
	if exits.size() > 1 and options.size() == exits.size():
		branch_options.assign(options)
	var scatter := get_node_or_null("Ingredients") as IngredientScatter
	if scatter == null:
		return
	var reserved: Array[Vector2i] = scatter.reserved_tiles.duplicate()
	var doors: Array[Vector2i] = [entrance]
	doors.append_array(exits)
	for door in doors:
		reserved.append_array(RoomTiles.door_lane_of(door.x, door.y, room_tiles.room_size, DOOR_LANE_DEPTH))
	scatter.reserved_tiles = reserved


func is_branch_room() -> bool:
	return branch_options.size() >= 2


func get_branch_choice() -> BranchChoice:
	return _branch_choice


## Index of the chosen way (-1 before the choice or without a branch).
func get_chosen_branch() -> int:
	return _branch_choice.chosen if _branch_choice != null else -1


## The way of the chosen door (null before the choice or without a branch).
func get_chosen_option() -> BranchOption:
	var index := get_chosen_branch()
	return branch_options[index] if index >= 0 and index < branch_options.size() else null


## Decision for a way (tests, tools; players decide through BranchChoice).
func choose_branch(index: int) -> bool:
	return _branch_choice != null and _branch_choice.choose(index)


func get_exit_doors() -> Array[Door]:
	return _exit_doors.duplicate()


func get_alive_enemy_count() -> int:
	return _alive_enemies


func is_encounter_started() -> bool:
	return _encounter_started


func activate() -> void:
	if state != State.PREPARED:
		return
	state = State.ACTIVE
	_entrance_door.close()
	if is_campfire():
		# No room of its own (D-103): nothing to clear, no completion, the way on is open.
		_completion_reported = true
		state = State.CLEARED
		open_exit()
		return
	EventBus.room_entered.emit(room_index)
	if room_type == RoomSequence.RoomType.SPECIAL:
		_build_special_content()
		_complete()
	elif is_ambush and not _encounter_started:
		# The door has just closed and sprung the ambush (_on_entrance_door_changed). Should it
		# not have reported, the fight still starts: a room must never stay locked without enemies.
		start_encounter()
	elif not is_ambush:
		start_encounter()


func start_encounter() -> void:
	if _encounter_started:
		return
	_encounter_started = true
	_waves_spawned = 1
	var enemies: Array[Enemy] = []
	if RoomSequence.is_normal_combat(room_type):
		# Entered within the frame the room was built: the gates must exist before the first wave.
		_build_arena_gates()
		_wave_sizes = _plan_wave_sizes()
		_waves_total = maxi(1, _wave_sizes.size())
		enemies = _spawn_wave(1, ArenaWaves.AMBUSH_DELAY if is_ambush else 0.0)
	else:
		_waves_total = 1
		enemies = spawner.spawn_encounter(room_index, room_type, _get_markers(), content_anchor.position, enemy_container, context, get_arena())
		for enemy in enemies:
			_track_enemy(enemy, 1)
	if enemies.is_empty():
		# Broken template: never treat it as a cleared room (ARCHITECTURE 7.1).
		push_error("Room %d: encounter could not be spawned, exit stays closed." % room_index)
		return
	if is_arena:
		arena_started.emit(self, is_ambush)
	encounter_started.emit(self, enemies)


## The next wave comes when the running one is down to WaveRules.should_start_next_wave (arena:
## at most one left, otherwise cleared); the room is done after the last wave, with nobody left.
func check_completion() -> void:
	if not _encounter_started or state == State.UNLOADED:
		return
	if _waves_spawned < _waves_total:
		if not _next_wave_queued and WaveRules.should_start_next_wave(get_wave_alive(_waves_spawned), is_arena):
			_next_wave_queued = true
			_spawn_next_wave.call_deferred()
		return
	if _alive_enemies > 0:
		return
	# A combat variant may keep the room shut (soul flame raid time, A7); it calls
	# check_completion() again when it lets go.
	if RoomVariants.holds_completion(self):
		return
	_complete()


func get_wave_progress() -> Vector2i:
	return Vector2i(_waves_spawned, _waves_total)


## Living enemies of one wave (1-based), summoned minions included.
func get_wave_alive(wave: int) -> int:
	return _wave_alive[wave] if wave >= 0 and wave < _wave_alive.size() else 0


## Planned enemy count per wave (after the encounter started).
func get_wave_sizes() -> Array[int]:
	return _wave_sizes.duplicate()


## A3/D-084 hook: theme group, quiet room or player scaling for this room's normal enemies.
## Call before the encounter starts.
func set_encounter_group(group: EncounterGroup) -> void:
	spawner.encounter_group = group


## Combat variant of this room (A7): &"soul_flame", &"rifts", &"gravedigger", &"bounty" or &"".
func get_variant_id() -> StringName:
	return RoomVariants.get_variant_id(self)


## A wager altar stands behind the entrance (A7, D-104).
func has_wager_altar() -> bool:
	return RoomVariants.has_wager_altar(self)


## Hook for combat variants (A7): an enemy that joins the fight later (rifts, raid waves).
func track_enemy(enemy: Enemy) -> void:
	_track_enemy(enemy, 0)


func get_arena_waves() -> ArenaWaves:
	return _arena


## Is this room fought as an arena (waves out of the walls)? Known once the room is prepared.
func is_arena_room() -> bool:
	return is_arena


## Is this arena an ambush (looks empty, breaks open when the door closes)?
func is_ambush_room() -> bool:
	return is_arena and is_ambush


func _spawn_next_wave() -> void:
	_next_wave_queued = false
	if state == State.UNLOADED or _waves_spawned >= _waves_total:
		return
	_waves_spawned += 1
	_spawn_wave(_waves_spawned)
	wave_started.emit(self, _waves_spawned, _waves_total)
	# An empty wave (no markers, no gates) must not keep the room locked.
	check_completion()


## Enemy counts of all waves: one roll per wave (D-074, arena WaveRules), then split so no wave
## has more enemies than spawn places (overflow -> extra wave, D-086).
func _plan_wave_sizes() -> Array[int]:
	var rolled: Array[int] = []
	for i in WaveRules.get_wave_count(room_index, is_arena):
		rolled.append(_roll_wave_size())
	var capacity: int = _arena.get_capacity() if _arena != null else get_spawn_markers().size()
	return WaveRules.plan_wave_sizes(rolled, capacity)


## Enemy count of one wave: the room's roll (D-074, encounter group), shaped for an arena.
func _roll_wave_size() -> int:
	var group := spawner.encounter_group
	var fixed_count := group != null and group.has_fixed_count()
	var smallest := RoomSequence.get_enemy_count_range(room_index).x
	return WaveRules.get_wave_size(spawner.roll_enemy_count(room_index, context.rng), is_arena, smallest, fixed_count)


## Spawns wave (1-based) of a normal combat room: out of the walls in an arena, at the markers
## otherwise. Waves past the plan (tools raise _waves_total) roll their count on the spot.
func _spawn_wave(wave: int, delay := 0.0) -> Array[Enemy]:
	var size: int = _wave_sizes[wave - 1] if wave <= _wave_sizes.size() else _roll_wave_size()
	var enemies: Array[Enemy] = []
	if _arena != null and _arena.get_capacity() > 0:
		var gates := _arena.choose_gates(size, wave, WaveRules.get_player_positions(self))
		var positions: Array[Vector2] = []
		for gate in gates:
			positions.append(gate.get_floor_position())
		enemies = spawner.spawn_enemies(room_index, positions, enemy_container, context, get_arena())
		_arena.release(enemies, gates, delay)
	else:
		var markers := _get_markers()
		if markers.size() < EnemySpawner.MIN_SPAWN_POINTS:
			push_error("Room %d: expected at least %d spawn markers, found %d." % [room_index, EnemySpawner.MIN_SPAWN_POINTS, markers.size()])
			return enemies
		enemies = spawner.spawn_enemies(room_index, EnemySpawner.pick_marker_positions(markers, size, context.rng), enemy_container, context, get_arena())
	for enemy in enemies:
		_track_enemy(enemy, wave)
	return enemies


## Global rectangle of the floor, used for teleport targets.
func get_arena() -> Rect2:
	var rect := tiles.get_floor_rect()
	return Rect2(to_global(rect.position), rect.size)


func spawn_exit_portal() -> void:
	if has_portal:
		return
	has_portal = true
	var portal := PORTAL_SCENE.instantiate() as SpecialContent
	portal.position = portal_anchor.position
	add_child(portal)
	portal.setup(context, self)
	Sfx.play_at(self, &"portal", portal.global_position)


func open_exit() -> void:
	if _branch_choice != null and _branch_choice.chosen < 0:
		# Branch room: the doors stay shut until the group walks up to one (D-105).
		if not _branch_choice.is_offered:
			_branch_choice.offer()
			branch_offered.emit(self)
		return
	if not _exit_door.is_open:
		# The configured door plays its own biome sound (DoorView).
		_exit_door.open()


## The group picked a way: that door becomes the exit, the other is sealed for good; the manager
## prepares room n+1 for the way (branch_chosen), then the door opens.
func _on_branch_decided(_choice: BranchChoice, index: int) -> void:
	_exit_door = _exit_doors[index]
	for i in _exit_doors.size():
		if i != index:
			_exit_doors[i].seal()
	branch_chosen.emit(self, index)
	if state == State.CLEARED:
		open_exit()


func mark_unloaded() -> void:
	state = State.UNLOADED


## The room behind the exit door is known: its type and special sign (D1). The special type is only
## rolled when the next room is prepared, while this exit door is still closed.
func set_next_room(next: RoomController) -> void:
	if is_branch_room():
		# The chosen door already shows its way (sign of the branch, D-105).
		return
	_exit_door.set_destination(next.room_type, next.special_type)


func is_campfire() -> bool:
	return room_type == RoomSequence.RoomType.CAMPFIRE


## Biome of the room after this one: the new biome behind a campfire.
func get_next_biome() -> BiomeData:
	return spawner.get_biome(room_index + 1)


## A campfire was placed north of this room: rooms are y-sorted, so this room's rock ring would
## cover the campfire's blended rock beside it. The ring then ends at the room's north wall.
func make_way_for_campfire() -> void:
	tiles.set_backdrop_north_rows(0)


func get_campfire_content() -> CampfireContent:
	for child in get_children():
		if child is CampfireContent:
			return child
	return null


func _complete() -> void:
	if _completion_reported:
		return
	_completion_reported = true
	state = State.CLEARED
	completed.emit(self)


## wave 0 = the running wave (tools add enemies this way).
func _track_enemy(enemy: Enemy, wave := 0) -> void:
	if wave <= 0:
		wave = maxi(1, _waves_spawned)
	_alive_enemies += 1
	if _wave_alive.size() <= wave:
		_wave_alive.resize(wave + 1)
	_wave_alive[wave] += 1
	enemy.died.connect(_on_enemy_died.bind(wave))
	# Summoned minions count towards the encounter and their summoner's wave.
	enemy.summoned.connect(_track_enemy.bind(wave))


func _on_enemy_died(enemy: Enemy, wave := 0) -> void:
	_alive_enemies -= 1
	if wave > 0 and wave < _wave_alive.size():
		_wave_alive[wave] -= 1
	if enemy.data != null and enemy.data.is_boss:
		# The boss takes its minions with it.
		for child in enemy_container.get_children():
			var minion := child as Enemy
			if minion != null and minion != enemy and not minion.is_dead():
				minion.health.take_damage(INF)
	check_completion()


## Is this a normal combat room with a room kind (D-086)?
func has_room_kind() -> bool:
	return RoomSequence.is_normal_combat(room_type)


## All spawn markers of the template (5-14 for combat templates, D-086).
func get_spawn_markers() -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for child in spawn_points.get_children():
		if child is Marker2D:
			markers.append(child)
	return markers


## Markers handed to the spawner: all of them (5-14, D-086). The spawner picks distinct markers
## per wave with the dungeon RNG; more enemies than markers become an extra wave.
func _get_markers() -> Array[Marker2D]:
	return get_spawn_markers()


## Arena rooms (A5): the ambush is rolled and the wave RNG seeded from the dungeon RNG right now,
## while the room is prepared (two draws, fixed order). The gates follow one frame later, after
## anything that still changes the floor while the room is built (ingredient scatter, A3).
func _setup_waves() -> void:
	is_arena = WaveRules.is_arena(room_type, room_kind, room_index)
	if not is_arena:
		return
	var dungeon_rng: RandomNumberGenerator = context.rng if context != null else null
	is_ambush = forced_ambush == 1 if forced_ambush >= 0 else (dungeon_rng != null and WaveRules.roll_ambush(dungeon_rng))
	_wave_rng = RandomNumberGenerator.new()
	_wave_rng.seed = dungeon_rng.randi() if dungeon_rng != null else room_index
	_arena = ArenaWaves.new()
	add_child(_arena)
	if is_ambush:
		_entrance_door.state_changed.connect(_on_entrance_door_changed)
	_build_arena_gates.call_deferred()


## Solid props of the template and the ingredient scatter (built in its _ready, before ours) take
## the navigation off their tile until they break or go.
func _block_prop_navigation() -> void:
	var prop_nodes: Array[Node] = get_node("Props").get_children()
	for child in get_children():
		if child.has_method(&"get_built_nodes"):
			prop_nodes.append_array(child.call(&"get_built_nodes"))
	for prop in prop_nodes:
		if not is_instance_valid(prop) or not is_solid_prop(prop):
			continue
		var tile := tiles.local_to_map(tiles.to_local((prop as Node2D).global_position))
		tiles.set_navigation_blocked(tile, true)
		prop.tree_exiting.connect(_on_prop_removed.bind(tile), CONNECT_ONE_SHOT)


## A prop that blocks walking: a body itself (crate, barrel, rubble) or one carried as a direct child
## (light pedestal, A3).
static func is_solid_prop(prop: Node) -> bool:
	if prop is StaticBody2D:
		return true
	for child in prop.get_children():
		if child is StaticBody2D:
			return true
	return false


func _on_prop_removed(tile: Vector2i) -> void:
	if is_instance_valid(tiles) and not tiles.is_queued_for_deletion():
		tiles.set_navigation_blocked(tile, false)


func _build_arena_gates() -> void:
	if _arena == null or not is_instance_valid(_arena) or _arena.is_built():
		return
	# Template props plus whatever the ingredient scatter built (traps, cover, light pedestals).
	var prop_nodes: Array[Node] = get_node("Props").get_children()
	for child in get_children():
		if child.has_method(&"get_built_nodes"):
			prop_nodes.append_array(child.call(&"get_built_nodes"))
	var props: Array[Vector2] = []
	for prop in prop_nodes:
		var node := prop as Node2D
		if node != null and is_instance_valid(node):
			props.append(to_local(node.global_position) if node.is_inside_tree() else node.position)
	var doors: Array[Vector2i] = [get_entrance_tile()]
	doors.append_array(get_exit_tiles())
	var gates := WallGates.find_gates(tiles.get_reachable_tiles(), tiles.room_size, doors, props)
	_arena.setup(gates, is_ambush, _wave_rng)


## Ambush: the fight starts when the entrance door closes behind the players (KONZEPT_RAEUME 3.1).
func _on_entrance_door_changed(open: bool, instant: bool) -> void:
	if open or instant or state != State.ACTIVE:
		return
	start_encounter()


## Torches matching the biome (art/environment/props/torch_<colour>_4f.png).
func _apply_biome_torches(biome_id: StringName) -> void:
	var strip_path: String = BIOME_TORCHES.get(biome_id, "")
	if strip_path.is_empty() or not ResourceLoader.exists(strip_path):
		return
	var strip := load(strip_path) as Texture2D
	for prop in get_node("Props").get_children():
		var torch := prop as AnimatedProp
		if torch != null and String(torch.name).begins_with("Torch"):
			torch.strip = strip


## Dedicated biome art replaces the tinted crypt tiles.
func _apply_biome_tiles(biome: BiomeData) -> void:
	var biome_tileset := _load_biome_tileset(biome.id)
	if biome_tileset != null:
		tiles.use_tileset(biome_tileset)
	else:
		tiles.modulate = biome.tile_tint


## Campfire: the next biome's tiles blend in from the entrance (south) to the exit (north). The
## torches hang on the north wall, so they already burn in the next biome's colour. A biome
## without its own tileset (crypt) blends in with the template's base tileset and its tint.
func _apply_campfire_look(next_biome: BiomeData, base_tileset: TileSet) -> void:
	if next_biome == null:
		return
	var next_tileset := _load_biome_tileset(next_biome.id)
	var next_tint := Color.WHITE if next_tileset != null else next_biome.tile_tint
	var from_row := float(tiles.room_size.y) - CAMPFIRE_OLD_ROWS
	tiles.set_biome_blend(next_tileset if next_tileset != null else base_tileset, next_tint, from_row, CAMPFIRE_NEW_ROWS)
	_apply_biome_torches(next_biome.id)


static func _load_biome_tileset(biome_id: StringName) -> TileSet:
	var path := BIOME_TILESET_PATH % biome_id
	return load(path) as TileSet if ResourceLoader.exists(path) else null


func _create_door(tile: Vector2i, side: int = RoomTiles.DoorSide.NORTH) -> Door:
	var door := DOOR_SCENE.instantiate() as Door
	door.position = RoomTiles.tile_to_local(tile)
	door.set_side(side)
	add_child(door)
	return door


## Template torches on the north wall right beside a north door of this run (a branch door or an
## alternative exit place) give way: the door brings its own (D1).
func _hide_torches_at_doors() -> void:
	var columns: Array[int] = []
	for exit in tiles.get_exit_doors():
		if exit.x == RoomTiles.DoorSide.NORTH:
			columns.append(exit.y)
	if columns.is_empty():
		return
	for prop in get_node("Props").get_children():
		var torch := prop as Node2D
		if torch == null or not String(torch.name).begins_with("Torch"):
			continue
		var column := floori(torch.position.x / RoomTiles.TILE_WORLD)
		for door_column in columns:
			if absi(column - door_column) <= DOOR_TORCH_CLEARANCE:
				torch.visible = false
				torch.process_mode = Node.PROCESS_MODE_DISABLED


func _setup_enter_trigger() -> void:
	# Covers the floor except the strip next to the entrance, so the door closes behind the player.
	var floor_rect := tiles.get_floor_rect()
	var rect := floor_rect
	match tiles.entrance_side:
		RoomTiles.DoorSide.NORTH:
			rect = floor_rect.grow_individual(0.0, -RoomTiles.TILE_WORLD, 0.0, 0.0)
		RoomTiles.DoorSide.WEST:
			rect = floor_rect.grow_individual(-RoomTiles.TILE_WORLD, 0.0, 0.0, 0.0)
		RoomTiles.DoorSide.EAST:
			rect = floor_rect.grow_individual(0.0, 0.0, -RoomTiles.TILE_WORLD, 0.0)
		_:
			rect = floor_rect.grow_individual(0.0, 0.0, 0.0, -RoomTiles.TILE_WORLD)
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = rect.get_center()
	_enter_trigger.add_child(collision)
	_enter_trigger.collision_layer = 0
	_enter_trigger.collision_mask = PhysicsLayers.PLAYER
	_enter_trigger.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _entered or not body is Player:
		return
	_entered = true
	player_entered.emit(self)


func _build_campfire_content() -> void:
	var content := CampfireContent.new()
	content.name = "CampfireContent"
	content.y_sort_enabled = true
	content.position = content_anchor.position
	add_child(content)
	content.setup(context, self)
	if has_portal:
		var portal := PORTAL_SCENE.instantiate() as SpecialContent
		portal.position = portal_anchor.position
		add_child(portal)
		portal.setup(context, self)


func _build_special_content() -> void:
	var scene: PackedScene = SPECIAL_SCENES.get(special_type)
	if scene != null:
		var content := scene.instantiate() as SpecialContent
		content.position = content_anchor.position
		add_child(content)
		content.setup(context, self)
	if has_portal:
		var portal := PORTAL_SCENE.instantiate() as SpecialContent
		portal.position = portal_anchor.position
		add_child(portal)
		portal.setup(context, self)
