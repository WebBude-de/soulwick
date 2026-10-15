class_name CombatVariant
extends Node2D
## Common interface of the room modes (KONZEPT_RAEUME_V2 §2-§4, D-120; before: the combat variants of
## KONZEPT_RAEUME §4, D-101): a child node of a normal combat room. Minigames extend RoomMode, which
## adds the goal, the intro and the helpers for guards and enemy sources; the elite nest (A10)
## extends this class directly. The DungeonManager treats the room like any combat room; the variant follows
## the room's own signals:
##   start()  on RoomController.encounter_started (the fight begins, the door is shut),
##   finish() on RoomController.completed (all enemies beaten - the room is done as always).
## In between the variant decides whether its bonus is met (set_bonus); a variant that has its
## own failure (flame out, crowned one escaped) decides that early. Failure never costs the run, success
## puts a bonus chest with an upgrade choice into the room (D-109, TreasureChest).
## holds_completion() lets a variant keep the room shut for a while (flame raid time); the
## RoomController asks it through RoomVariants.holds_completion (hook).
## Decisions emit signals (started, bonus_changed, finished); effects (banner, chest, darkness)
## follow them (D-088). Randomness: a variant RNG seeded once from the dungeon RNG on attach, so
## the dungeon stream is used the same way however the players move (like the arena waves).

signal started(variant: CombatVariant)
signal bonus_changed(variant: CombatVariant, state: Bonus)
signal finished(variant: CombatVariant, bonus: bool)

enum Bonus { OPEN, ACHIEVED, LOST }

const NODE_NAME := &"CombatVariant"
## Loaded when a chest is placed, never preloaded: TreasureChest -> RoomController -> RoomVariants ->
## RoomMode -> CombatVariant would close a load cycle and leave the scene empty (SecretNiche too).
const CHEST_SCENE_PATH := "res://dungeon/rooms/ingredients/treasure_chest.tscn"
const BANNER_COLOR := Color("#dcbcff")
const BONUS_COLOR := Color("#f2cf4a")
const LOST_COLOR := Color("#e0463a")

var variant_id: StringName = &""
var room: RoomController = null
var context: DungeonContext = null
var bonus := Bonus.OPEN
## Bonus chests placed by finish() (tests, tools).
var chests: Array[TreasureChest] = []

var _rng := RandomNumberGenerator.new()
var _started := false
var _finished := false
var _free: Dictionary[Vector2i, bool] = {}


# --- Creation (RoomVariants.attach) ---

## The mode node for an id, not yet attached (null for unknown ids). Modes live in ModeRegistry
## (one line each, scripts loaded by path, so the modes never load each other).
static func create(id: StringName) -> CombatVariant:
	return ModeRegistry.create(id)


## Attaches the variant id to a prepared normal combat room. seed: one number of the dungeon RNG,
## drawn by the caller in any case. Returns null if the id is unknown, the room is no normal
## combat room, already has a variant, or the room cannot host this variant (e.g. no open floor
## for the flame in a catacomb) - the room then stays a normal combat room.
static func attach_to(target: RoomController, id: StringName, seed: int) -> CombatVariant:
	if target == null or not is_instance_valid(target) or not target.has_room_kind() or of(target) != null:
		return null
	var variant := create(id)
	if variant == null:
		return null
	variant.variant_id = id
	variant.room = target
	variant.context = target.context
	variant._rng.seed = seed
	variant._free = VariantSpots.free_tiles(target)
	if not variant.can_host():
		variant.free()
		return null
	variant.name = NODE_NAME
	variant.y_sort_enabled = true
	target.add_child(variant)
	variant._connect_room()
	variant._on_attach()
	return variant


## The variant of a room or null.
static func of(target: Node) -> CombatVariant:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NodePath(NODE_NAME)) as CombatVariant


# --- Interface ---

## The fight began (RoomController.encounter_started). Once.
func start() -> void:
	if _started or _finished:
		return
	_started = true
	_on_start()
	started.emit(self)


## The room is cleared (RoomController.completed): an open bonus is decided now, then the result.
func finish() -> void:
	if _finished:
		return
	_finished = true
	if bonus == Bonus.OPEN:
		set_bonus(_is_bonus_met())
	_on_finish()
	finished.emit(self, bonus == Bonus.ACHIEVED)


## Decision: bonus met (true) or lost for good (false). A decided bonus does not change again.
func set_bonus(achieved: bool) -> bool:
	if bonus != Bonus.OPEN:
		return false
	bonus = Bonus.ACHIEVED if achieved else Bonus.LOST
	bonus_changed.emit(self, bonus)
	return true


func is_started() -> bool:
	return _started


func is_finished() -> bool:
	return _finished


func is_bonus_achieved() -> bool:
	return bonus == Bonus.ACHIEVED


## Keeps the room from completing although no enemy is left (RoomController hook).
func holds_completion() -> bool:
	return false


## Advances the variant's own clock by delta seconds (raid time, bone heaps). Runs every physics
## frame where a variant has a clock; tools and tests call it to fast-forward (smoke test: step the
## soul flame past its raid time before clearing the room).
func step(_delta: float) -> void:
	pass


# --- Overrides ---

## Can the prepared room host this variant (free floor, spots)? _free is filled.
func can_host() -> bool:
	return true


## Built right after attaching (room prepared, nothing spawned): static objects, group changes.
func _on_attach() -> void:
	pass


func _on_start() -> void:
	pass


func _on_finish() -> void:
	pass


## Bonus decided at the end when the variant has not decided it earlier. Default: room cleared.
func _is_bonus_met() -> bool:
	return true


## Every enemy that enters the room's enemy container (before its _ready; also before start()
## for the first wave).
func _on_enemy_added(_enemy: Enemy) -> void:
	pass


## Shapes the room's encounter group before the fight is planned (count factor, type weights).
func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return group


# --- Helpers for the variants ---

## Living players of the run (coop-ready: every player of the group, no first-node lookup).
func get_players() -> Array[Player]:
	var players: Array[Player] = []
	if not is_inside_tree():
		return players
	for node in EnemyTargeting.living_players(get_tree()):
		var player := node as Player
		if player != null:
			players.append(player)
	return players


func get_player_count() -> int:
	return maxi(1, get_players().size())


## A late enemy joins the room's encounter (rifts, raid waves): RoomController tracks it like its
## own. Uses the public hook track_enemy() once the integrator added it, the tools' way before.
func track_enemy(enemy: Enemy) -> void:
	if room == null or enemy == null:
		return
	if room.has_method(&"track_enemy"):
		room.call(&"track_enemy", enemy)
	else:
		room.call(&"_track_enemy", enemy, 0)


## Normal enemies the variant spawns itself: the room's spawner with the variant RNG.
func spawn_enemies(local_positions: Array[Vector2]) -> Array[Enemy]:
	if room == null or local_positions.is_empty():
		return []
	return room.spawner.spawn_enemies(room.room_index, local_positions, room.enemy_container, _spawn_context(), room.get_arena())


## Living enemies of the room's container (summons and late arrivals included).
func get_living_enemies() -> Array[Enemy]:
	var living: Array[Enemy] = []
	if room == null:
		return living
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dead() and not enemy.is_queued_for_deletion():
			living.append(enemy)
	return living


## Free floor tiles of the room (VariantSpots), read once on attach.
func get_free_tiles() -> Dictionary[Vector2i, bool]:
	return _free


## Room-local positions of the living players.
func get_player_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for player in get_players():
		tiles.append(RoomTiles.local_to_tile(room.to_local(player.get_feet_position())))
	return tiles


## Bonus chest(s) near a room-local point, on a free tile (D-109: upgrade choice). Unlocked right
## away when the room is already cleared (TreasureChest.locked_until_cleared).
func spawn_bonus_chests(near_local: Vector2) -> Array[TreasureChest]:
	var placed: Array[TreasureChest] = []
	# Never on or right beside a player: a chest that lands on someone locks them in (playtest 15.10.2026).
	var taken := _tiles_around_players()
	for i in VariantRules.chest_count(get_player_count()):
		var tile := VariantSpots.nearest_free(_free, RoomTiles.local_to_tile(near_local), taken)
		var spot := RoomTiles.tile_center(tile) + Vector2(0, 22) if tile != VariantSpots.INVALID else near_local
		taken.append(tile)
		var chest := (load(CHEST_SCENE_PATH) as PackedScene).instantiate() as TreasureChest
		chest.name = "BonusChest%d" % i
		chest.upgrade_choices = VariantRules.CHEST_UPGRADE_CHOICES
		chest.per_player = VariantRules.CHESTS_PER_PLAYER
		chest.position = spot
		add_child(chest)
		placed.append(chest)
		chests.append(chest)
		if is_inside_tree():
			Burst.spawn(self, chest.global_position + Vector2(0, -24), BONUS_COLOR, 20, 140.0)
			LightSource.flash(self, chest.global_position + Vector2(0, -24), 180.0, 0.5)
	return placed


## Tiles of the living players and their eight neighbours (the chest sits a bit below its tile).
func _tiles_around_players() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile in get_player_tiles():
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				tiles.append(tile + Vector2i(dx, dy))
	return tiles


func show_banner(title: String, subtitle: String, color := BANNER_COLOR) -> void:
	if context != null and context.ui != null and is_instance_valid(context.ui):
		context.ui.show_banner(title, subtitle, color)


# --- Internals ---

func _connect_room() -> void:
	room.encounter_started.connect(_on_room_encounter_started)
	room.completed.connect(_on_room_completed)
	room.player_entered.connect(_on_room_player_entered)
	room.enemy_container.child_entered_tree.connect(_on_container_child_entered)
	_apply_group()


func _on_room_encounter_started(_room: RoomController, _enemies: Array[Enemy]) -> void:
	start()


func _on_room_completed(_room: RoomController) -> void:
	finish()


## The room's group may have been set after attaching (EncounterVariation): shape it again before
## the fight is planned (player_entered comes before the deferred activation).
func _on_room_player_entered(_room: RoomController) -> void:
	_apply_group()


func _apply_group() -> void:
	var current := room.spawner.encounter_group
	if current is VariantEncounterGroup and (current as VariantEncounterGroup).owner_id == get_instance_id():
		return
	var shaped := _shape_group(current)
	if shaped != current:
		room.spawner.encounter_group = shaped


func _on_container_child_entered(node: Node) -> void:
	var enemy := node as Enemy
	if enemy != null:
		_on_enemy_added(enemy)


## A copy of the room context with the variant RNG (types and elites of the variant's own spawns).
func _spawn_context() -> DungeonContext:
	var copy := DungeonContext.new()
	if context != null:
		copy.manager = context.manager
		copy.player = context.player
		copy.upgrade_manager = context.upgrade_manager
		copy.economy = context.economy
		copy.ui = context.ui
		copy.weapon_pool = context.weapon_pool
	copy.rng = _rng
	return copy
