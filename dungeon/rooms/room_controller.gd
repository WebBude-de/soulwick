class_name RoomController
extends Node2D
## One room instance: doors, encounter state and completion (D-008).
## PREPARED (instantiated, nothing spawned) -> ACTIVE (player entered) -> CLEARED -> UNLOADED.
## The encounter starts on the first real entry only, exactly once; completion is reported once.
## A campfire (D-103) is a room instance without a room number of its own: no encounter, no
## completion signal, no EventBus room events; its floor blends from the old into the next biome.

signal player_entered(room: RoomController)
signal completed(room: RoomController)
signal encounter_started(room: RoomController, enemies: Array[Enemy])
signal wave_started(room: RoomController, wave: int, total: int)

enum State { PREPARED, ACTIVE, CLEARED, UNLOADED }

const DOOR_SCENE: PackedScene = preload("res://dungeon/environment/doors/door.tscn")
## Biome tileset per BiomeData.id (built by tools/build_tilesets.gd); the crypt uses the base set.
const BIOME_TILESET_PATH := "res://dungeon/environment/%s_tileset.tres"
const BIOME_TORCHES := {
	&"slime_grotto": "res://art/environment/props/torch_green_4f.png",
	&"shadow_realm": "res://art/environment/props/torch_purple_4f.png",
}
## Markers per wave the current EnemySpawner accepts (its REQUIRED_SPAWN_POINTS, D-009).
const SPAWNER_MARKER_COUNT := 5
const PORTAL_SCENE: PackedScene = preload("res://dungeon/rooms/special/exit_portal.tscn")
const SPECIAL_SCENES := {
	RoomSequence.SpecialType.SHOP: preload("res://dungeon/rooms/special/shop_content.tscn"),
	RoomSequence.SpecialType.WEAPON: preload("res://dungeon/rooms/special/weapon_content.tscn"),
	RoomSequence.SpecialType.FOUNTAIN: preload("res://dungeon/rooms/special/fountain_content.tscn"),
	RoomSequence.SpecialType.UPGRADE: preload("res://dungeon/rooms/special/altar_content.tscn"),
}
## Campfire floor blend (TESTWERTE): rows above the entrance that stay fully in the old biome and
## rows below the exit that are already fully in the new one; in between the dithered blend.
const CAMPFIRE_OLD_ROWS := 1.5
const CAMPFIRE_NEW_ROWS := 2.0

## Kind and size class of a combat template (D-086), written by tools/generate_room_templates.py
## and read by RoomCatalog. Without meaning for special, miniboss and boss rooms.
@export var room_kind: RoomSequence.RoomKind = RoomSequence.RoomKind.ARENA
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
var _entrance_door: Door = null
var _exit_door: Door = null

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
	_entrance_door = _create_door(get_entrance_tile())
	_exit_door = _create_door(get_exit_tile())
	# Doors in the biome's style (D1): the entrance shows this room, the exit the next slot (boss
	# gate before a boss, flame sign before the campfire). A campfire's exit is already in the new biome.
	var door_biome: StringName = biome.id if biome != null else &""
	_entrance_door.configure_for_room(door_biome, room_type, special_type, true)
	var next_biome := get_next_biome() if is_campfire() else null
	_exit_door.configure_for_room(next_biome.id if next_biome != null else door_biome, RoomSequence.get_slot_type(slot_index + 1))
	# Room 1 has nothing behind its entrance.
	_entrance_door.set_open_instant(room_index > 1)
	_exit_door.set_open_instant(false)
	_setup_enter_trigger()
	if is_campfire():
		# Built right away: the fire already glows through the open door of the boss room.
		_build_campfire_content()


func get_entrance_tile() -> Vector2i:
	return Vector2i(tiles.entrance_x, tiles.room_size.y)


func get_exit_tile() -> Vector2i:
	return Vector2i(tiles.exit_x, -1)


## Where a freshly spawned player starts in room 1: just inside the entrance.
func get_player_start() -> Vector2:
	return to_global(RoomTiles.tile_center(Vector2i(tiles.entrance_x, tiles.room_size.y - 2)))


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
	else:
		start_encounter()


func start_encounter() -> void:
	if _encounter_started:
		return
	_encounter_started = true
	_waves_total = RoomSequence.get_wave_count(room_index) if RoomSequence.is_normal_combat(room_type) else 1
	_waves_spawned = 1
	var enemies := spawner.spawn_encounter(room_index, room_type, _get_markers(), content_anchor.position, enemy_container, context, get_arena())
	if enemies.is_empty():
		# Broken template: never treat it as a cleared room (ARCHITECTURE 7.1).
		push_error("Room %d: encounter could not be spawned, exit stays closed." % room_index)
		return
	for enemy in enemies:
		_track_enemy(enemy)
	encounter_started.emit(self, enemies)


func check_completion() -> void:
	if not _encounter_started or _alive_enemies > 0:
		return
	if _waves_spawned < _waves_total:
		_spawn_next_wave.call_deferred()
		return
	_complete()


func get_wave_progress() -> Vector2i:
	return Vector2i(_waves_spawned, _waves_total)


func _spawn_next_wave() -> void:
	if state == State.UNLOADED or _waves_spawned >= _waves_total:
		return
	_waves_spawned += 1
	var enemies := spawner.spawn_encounter(room_index, room_type, _get_markers(), content_anchor.position, enemy_container, context, get_arena())
	for enemy in enemies:
		_track_enemy(enemy)
	wave_started.emit(self, _waves_spawned, _waves_total)


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
	if not _exit_door.is_open:
		# The configured door plays its own biome sound (DoorView).
		_exit_door.open()


func mark_unloaded() -> void:
	state = State.UNLOADED


## The room behind the exit door is known: its type and special sign (D1). The special type is only
## rolled when the next room is prepared, while this exit door is still closed.
func set_next_room(next: RoomController) -> void:
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


func _track_enemy(enemy: Enemy) -> void:
	_alive_enemies += 1
	enemy.died.connect(_on_enemy_died)
	# Summoned minions count towards the encounter like any other enemy.
	enemy.summoned.connect(_track_enemy)


func _on_enemy_died(enemy: Enemy) -> void:
	_alive_enemies -= 1
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


## Markers handed to the spawner per wave. EnemySpawner still expects exactly
## SPAWNER_MARKER_COUNT markers (D-009 check), so larger templates hand over a fresh random subset
## per wave (dungeon RNG). Once the spawner accepts 5-14 markers, return get_spawn_markers().
func _get_markers() -> Array[Marker2D]:
	var markers := get_spawn_markers()
	if markers.size() <= SPAWNER_MARKER_COUNT:
		return markers
	var subset: Array[Marker2D] = []
	if context == null or context.rng == null:
		subset.assign(markers.slice(0, SPAWNER_MARKER_COUNT))
		return subset
	for marker_index in EnemySpawner.pick_markers(markers.size(), SPAWNER_MARKER_COUNT, context.rng):
		subset.append(markers[marker_index])
	return subset


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


func _create_door(tile: Vector2i) -> Door:
	var door := DOOR_SCENE.instantiate() as Door
	door.position = RoomTiles.tile_to_local(tile)
	add_child(door)
	return door


func _setup_enter_trigger() -> void:
	# Covers the floor except the row next to the entrance, so the door closes behind the player.
	var floor_rect := tiles.get_floor_rect()
	var rect := Rect2(floor_rect.position, floor_rect.size - Vector2(0.0, RoomTiles.TILE_WORLD))
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
