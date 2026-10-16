class_name DungeonManager
extends Node2D
## Owns the room sequence of one run: template choice, placement and streaming (D-002 .. D-008).
## Rooms are chained: each exit lines up with the next entrance. At most three room instances exist
## at any time (N-1, N, N+1): N-2 is freed immediately, before N+1 is created, so a fourth instance
## never exists, not even until the end of the frame (D-007).
## Way-finding (A10, KONZEPT_RAEUME §7, D-105): a room is left to the north, west or east and the
## next one is entered through the opposite wall; a room that would overlap a live room moves further
## out along a longer corridor (ExitRules). Now and then a cleared room offers two ways to room n+1
## (branch, BranchRules). Some combat rooms hide a niche behind a cracked wall (SecretRules,
## SecretNiche); it is no room of its own.
## Streaming counts slots, not room numbers: after every boss room a campfire takes a slot of its
## own without a room number (D-103, RoomSequence slots), so N-1/N/N+1 include the campfire.
## Nothing pops up (R5, KONZEPT_RAEUME_V2 §1.2/§4): every prepared room lies built and dark behind its
## door (RoomVeil) and lights up when a player walks in; its exit door shows what waits behind it
## (DoorSigns: mode symbol, light cone) and the corridor between gets a style (CorridorDressing). A
## branch room builds both ways when it is entered (one more live room, MAX_LIVE_ROOMS_BRANCH); the
## way not chosen fades out and leaves plain rock behind. A branch whose two ways cannot both be
## placed next to the live rooms is not offered (_ways_fit).
## One gate per transition (M2): two rooms lie at most one corridor tile apart (ExitRules.JOIN_OVERLAP),
## the exit gate of the room being left is the only door, the entrance is an open gap without a leaf.
## Once every living player is inside the new room, that gate shuts behind them for good (GateCloser,
## no way back). Where two joined rooms paint over each other each keeps its own floor and walls
## (PassageSeam); when a room is unloaded its neighbour gets its cells back and blocks its entrance,
## which now leads nowhere (Door.block).
## No hitch on entry (playtest 15.10.2026 #14): entering a room only lights it up and starts it; the
## next room is built one frame later, covered (veil, seam) the frame after, then signed (door signs,
## corridor), then its side way is planned (_pending, one job per frame). The steps keep the order they
## had and nothing draws from the dungeon RNG in between, so the stream stays the same. Whoever asks
## for a room that is still pending (get_room_at_slot, the next entry, the branch choice, the network,
## tests) gets it built at once (finish_preparing). First-time work (the plan catalog, the rock pieces
## of every biome tileset) is done while the dungeon loads (_warm_up).

signal room_activated(room: RoomController)
## Completed rooms left until the next regular heal (HUD detail line).
signal heal_countdown_changed(rooms_left: int)
## Dungeon RNG state right before a slot (way = -1) or a branch way (way >= 0) is drawn; lets a
## co-op client reproduce the same rooms (multiplayer session).
signal slot_rng_captured(slot: int, way: int, state: int)

const MAX_LIVE_ROOMS := 3
## While a branch room is active both ways stand built behind its doors (R5): one more. TESTWERT
const MAX_LIVE_ROOMS_BRANCH := 4
## The way not taken fades out this long before it is freed (R5). TESTWERT
const BRANCH_FADE_TIME := 0.9
## Rock left where a faded way stood: below every room's tiles (-10) and rock ring (-11).
const ROCK_FILL_Z := -12
const HEAL_EVERY_COMPLETED_ROOMS := 5
const HEAL_AMOUNT := 1.0
const DEATH_SCREEN_DELAY := 1.4
## Reward dialogs wait this long after the last kill (D-070).
const REWARD_DIALOG_DELAY := 1.5
## Vision in the dungeon (D-067, TESTWERTE).
const DUNGEON_DARKNESS := 0.97
const VISION_RADIUS := 300.0
const EXTRA_DARK_VISION_RADIUS := 190.0
const SPECIAL_ROOM_DARKNESS := 0.2
const CRYSTALS_PER_BOSS := 3
const CRYSTALS_PER_CHAMPION := 1
## Test aid (ROADMAP_AUSBAU A1): normal combat rooms announce their kind and size in the banner.
const SHOW_ROOM_KIND_BANNER := false
const INPUT_LOCK_BOSS_INTRO := &"boss_intro"
const ROOM_KIND_BANNER_COLOR := Color(0.75, 0.8, 0.9)
## Exit portal at every campfire instead of in the boss room (recommendation D-103, confirmation
## by the team member still open). false = the portal appears in the boss room again (D-073).
const CAMPFIRE_EXIT_PORTAL := true  # TESTWERT
## Darkness at the campfire: calmer than a combat room, the fire is the main light (TESTWERT).
const CAMPFIRE_DARKNESS := 0.9
const CAMPFIRE_TEMPLATE_PATH := "res://dungeon/rooms/campfire/campfire_room.tscn"
const CAMPFIRE_BANNER_COLOR := Color(1.0, 0.7, 0.4)
## Branch banner (D-105) and the once-per-save hint at a cracked wall (A10).
const BRANCH_BANNER_COLOR := Color(0.95, 0.8, 0.45)
const SECRET_HINT_ID := &"hint_secret_wall"
## Elite nest variant (A10); see _prepare_slot why it is loaded at runtime.
const ELITE_NEST_SCRIPT := "res://dungeon/variants/elite_nest_variant.gd"

## Extra combat templates on top of the generated catalog (RoomCatalog.DEFAULT_PATH); duplicates
## are ignored. Kind and size come from the templates themselves (D-086).
@export var combat_templates: Array[PackedScene] = []
@export var special_template: PackedScene
@export var miniboss_template: PackedScene
@export var boss_template: PackedScene
## Campfire between two biomes (D-103); empty = CAMPFIRE_TEMPLATE_PATH.
@export var campfire_template: PackedScene
@export var weapon_pool: Array[WeaponData] = []
## 0 = random run.
@export var seed_value := 0

var context := DungeonContext.new()

## Live room instances by slot (RoomSequence.get_slot_for_room / campfire slots).
var _rooms: Dictionary[int, RoomController] = {}
var _active_slot := 0
var _completed_rooms := 0
var _previous_special := -1
## Weighted special room draw (D-102, A8).
var _special_table: SpecialTable = SpecialTable.load_default()
## Kind of the room prepared last (-1 after a non-combat room): no abyss twice in a row (D-086).
var _previous_kind := -1
## Combat variants and wager altars (A7, D-101, D-104).
var _variant_table: VariantTable = VariantTable.load_default()
## Variant of the room prepared last (&"" otherwise): never two in a row (D-101).
var _previous_variant: StringName = &""
## RNG state before each prepared slot / branch way (see slot_rng_captured).
var _slot_rng_states: Dictionary[Vector2i, int] = {}
var _combat_catalog: RoomCatalog = null
var _run_ending := false
## Cycle (five rooms) of the last branch: at most one per cycle (D-105, BranchRules).
var _branch_cycle := -1
## Worst-case footprint of the next room per entrance wall (ExitRules.reach_footprint over the solo
## combat templates), for choosing turns that need no long corridor.
var _combat_reach: Dictionary[int, ExitRules.Footprint] = {}
## Branch (R5): the branch room whose ways stand built, the ways (index = exit index), the chain
## state each way left behind (the chosen one is kept), ways fading out, rock left behind by slot.
var _branch_room: RoomController = null
var _branch_ways: Array[RoomController] = []
var _way_states: Array[ChainState] = []
var _fading_rooms: Array[RoomController] = []
var _rock_fills: Dictionary[int, Array] = {}
var _rock_root: Node2D = null
## Seed of the run (optics that vary per run without drawing from the dungeon RNG).
var _run_seed := 0
## M5: slot of the room the last side segment led into (never two segments in a row).
var _last_side_slot := -1
## Size and entrance place of special templates (branch fit check), by scene path.
var _layout_cache: Dictionary[String, Vector3i] = {}
## Every player of this run in spawn order (MP1); context.player is the first local one.
var _players: Array[Player] = []
## Preparation left over from the last entry (#14): one job per frame, in order.
var _pending: Array[Callable] = []
var _job_running := false
## Resources warmed up at the start and kept for the run (biome tilesets with their rock pieces).
var _warm: Array[Resource] = []
## Branch ways built over several frames: the chain state they all start from, the state each built
## way left behind.
var _ways_base: ChainState = null
var _ways_built: Array[ChainState] = []
## Shared run over the relay (MP3): the NetDungeon of a relay room, null otherwise. Host: hears about
## every slot before it is prepared and decides when a room starts; client: preparing, starting,
## completing and opening rooms follow the host. Hooks only, the logic is in online/net_dungeon.gd.
var net: Node = null


## What _prepare_slot reads and writes besides the RNG: kept per branch way, so the chosen way
## continues the chain as if it had been the only one.
class ChainState:
	extends RefCounted
	var previous_special := -1
	var previous_kind := -1
	var previous_variant: StringName = &""
	var branch_cycle := -1

@onready var room_container: Node2D = $RoomContainer
@onready var upgrade_manager: UpgradeManager = $UpgradeManager
@onready var upgrade_effects: UpgradeEffects = $UpgradeEffects
@onready var economy: EconomySystem = $EconomySystem
@onready var ui: DungeonUI = $DungeonUI
@onready var _player_spawn: Marker2D = $PlayerSpawn


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_run_seed = int(rng.seed)
	context.manager = self
	context.rng = rng
	context.upgrade_manager = upgrade_manager
	context.economy = economy
	context.ui = ui
	context.weapon_pool = weapon_pool
	ui.context = context
	SaveManager.content_unlocked.connect(_on_content_unlocked)
	_combat_catalog = RoomCatalog.create(combat_templates)

	RunManager.start_run()
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	upgrade_manager.upgrade_acquired.connect(_on_upgrade_acquired)
	_warm_up()
	var first := _prepare_slot(1)
	_player_spawn.global_position = first.get_player_start()
	_prepare_slot(2)


## First-time work of later rooms done while the dungeon loads (#14, the entry of the first rest room
## and the first room of every biome hitched): the plan catalog (rest, miniboss, boss and campfire
## templates) and the wall, abyss and rock pieces of every biome tileset (kept for the run, so the
## pieces are not built again). No dungeon RNG.
func _warm_up() -> void:
	RoomCatalog.load_plans()
	for biome_id in RoomCatalog.BIOME_IDS:
		var tileset := RoomController._load_biome_tileset(biome_id)
		if tileset == null:
			continue
		WallAutotile.ensure_source(tileset)
		AbyssAutotile.ensure_source(tileset)
		RockTerrain.ensure_sources(tileset)
		_warm.append(tileset)


## Called by the WorldController after it created a player for this world (D-041), once per
## player, the primary (local) player first. MP1: context, upgrade dialogs and upgrade effects serve
## that first player; the others share its weapon modifiers until MP3 gives everyone their own.
func on_player_spawned(player: Player) -> void:
	_players.append(player)
	player.weapon_controller.upgrades = upgrade_manager
	player.died.connect(_on_player_died)
	if net != null:
		net.on_player_spawned(player)
	# A network client may get the host's player first: the local one still becomes the primary.
	if context.player != null and (context.player.is_local or not player.is_local):
		return
	context.player = player
	upgrade_manager.player = player
	upgrade_effects.player = player
	# Village meta upgrades and Proviant boosts (D-078), summarized in one banner (D-087); only
	# from the local save in single player (D-081: quick games start without them).
	if GameMode.of(self).get_meta_source() == GameMode.MetaSource.LOCAL:
		var applied := MetaProgression.apply_to_run(player, context)
		var summary := MetaProgression.get_run_start_summary(applied)
		if not summary.is_empty():
			ui.show_banner(MetaProgression.RUN_BANNER_TITLE, summary)
	heal_countdown_changed.emit(get_rooms_until_heal())


## Every player of this run still in the world (downed ones too), in spawn order.
func get_session_players() -> Array[Player]:
	var result: Array[Player] = []
	for player in _players:
		if is_instance_valid(player) and player.is_inside_tree():
			result.append(player)
	return result


## Living players of this run (MP1), in spawn order.
func get_living_players() -> Array[Player]:
	var living: Array[Player] = []
	for player in _players:
		if is_instance_valid(player) and player.is_alive():
			living.append(player)
	return living


func get_rooms_until_heal() -> int:
	return HEAL_EVERY_COMPLETED_ROOMS - _completed_rooms % HEAL_EVERY_COMPLETED_ROOMS


## Live room with this room number (null if not prepared or already unloaded). Behind a branch
## room: null until the group has chosen its way (both ways: get_branch_ways).
func get_room(index: int) -> RoomController:
	var slot := RoomSequence.get_slot_for_room(index)
	if slot > _active_slot:
		finish_preparing()
	return _rooms.get(slot)


## Both ways of the active branch room, built and dark (index = exit index); empty otherwise.
func get_branch_ways() -> Array[RoomController]:
	finish_preparing()
	return _branch_ways.duplicate()


## Rooms that may live at once right now: one more while a branch shows both ways (R5).
func get_live_room_limit() -> int:
	return MAX_LIVE_ROOMS_BRANCH if not _branch_ways.is_empty() or not _fading_rooms.is_empty() else MAX_LIVE_ROOMS


## Live campfire behind boss room after_room (null if not prepared, unloaded or no boss room).
func get_campfire(after_room: int) -> RoomController:
	var slot := RoomSequence.get_campfire_slot_after(after_room)
	if slot > _active_slot:
		finish_preparing()
	return _rooms.get(slot) if slot > 0 else null


func get_room_at_slot(slot: int) -> RoomController:
	if slot > _active_slot:
		finish_preparing()
	return _rooms.get(slot)


## Is part of the next room's preparation still waiting for a later frame (#14)?
func is_preparing() -> bool:
	return not _pending.is_empty()


## Runs the preparation left over from the last entry right now, in its order. Inside a job it does
## nothing: the job's own steps must not overtake it.
func finish_preparing() -> void:
	if _job_running:
		return
	while not _pending.is_empty():
		_run_job(_pending.pop_front())
	_update_pending_hook()


## One job per frame. SceneTree.process_frame comes while a menu pauses the game too, so the order of
## the dungeon RNG never depends on a pause.
func _run_pending_job() -> void:
	if not _pending.is_empty() and not _job_running:
		_run_job(_pending.pop_front())
	_update_pending_hook()


func _run_job(job: Callable) -> void:
	_job_running = true
	job.call()
	_job_running = false


## A job after everything queued so far.
func _queue_job(job: Callable) -> void:
	_pending.append(job)
	_update_pending_hook()


## The next step of the running job: before everything else queued (keeps the old order).
func _queue_next(job: Callable) -> void:
	_pending.push_front(job)
	_update_pending_hook()


func _update_pending_hook() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	var hooked := tree.process_frame.is_connected(_run_pending_job)
	if _pending.is_empty() and hooked:
		tree.process_frame.disconnect(_run_pending_job)
	elif not _pending.is_empty() and not hooked:
		tree.process_frame.connect(_run_pending_job)


func _exit_tree() -> void:
	if get_tree().process_frame.is_connected(_run_pending_job):
		get_tree().process_frame.disconnect(_run_pending_job)


func get_live_room_count() -> int:
	return room_container.get_child_count()


## Room number of the room the player is in; at a campfire the number of the boss room before it.
func get_active_room_index() -> int:
	return RoomSequence.get_room_for_slot(_active_slot)


func get_active_slot() -> int:
	return _active_slot


func get_combat_catalog() -> RoomCatalog:
	return _combat_catalog


func end_run(reason: RunManager.EndReason) -> void:
	if _run_ending:
		return
	# MP3: on a network client the host ends the run (portal, everyone down).
	if net != null and not net.allow_end_run(reason):
		return
	_run_ending = true
	_pending.clear()
	_update_pending_hook()
	RunManager.end_run(reason)


# --- Streaming ---

## option: the way of a branch room (D-105) - it decides the special type or the variant of this
## room (safe way: none); the usual draws still happen, so the stream stays in step. via_exit >= 0:
## one of the ways of a branch room, built behind that exit before the choice (R5, _branch_ways).
## staged: the dressing (_dress_way, no dungeon RNG) follows in the next frames, then the job then; until
## it is covered the room stays hidden (#14).
func _prepare_slot(slot: int, option: BranchOption = null, via_exit := -1, staged := false, then := Callable()) -> RoomController:
	var is_way := via_exit >= 0
	if _rooms.has(slot) and not is_way:
		return _rooms[slot]
	# MP3: a client prepares only what the host sent and takes the host's RNG state for it (the gate
	# sets it); the host updates the player count. The capture below is what the host shares.
	var way := via_exit if is_way else -1
	if net != null and not net.before_prepare_slot(slot, option, way):
		return null
	_slot_rng_states[Vector2i(slot, way)] = context.rng.state
	slot_rng_captured.emit(slot, way, context.rng.state)
	var index := RoomSequence.get_room_for_slot(slot)
	var room_type := RoomSequence.get_slot_type(slot)
	if option != null:
		room_type = option.get_room_type(room_type) as RoomSequence.RoomType
	var previous: RoomController = _rooms.get(slot - 1)
	var previous_exit := _exit_of(previous, via_exit)
	var special := -1
	var portal := false
	if room_type == RoomSequence.RoomType.SPECIAL:
		special = _special_table.roll(_previous_special, context.rng)
		if option != null and option.special_type >= 0:
			special = option.special_type
		_previous_special = special
		portal = RoomSequence.roll_portal(context.rng)
	elif room_type == RoomSequence.RoomType.CAMPFIRE:
		portal = CAMPFIRE_EXIT_PORTAL

	var rolled_kind := -1
	# A7: variant, wager altar or nothing - three numbers per normal combat room, none otherwise.
	var variant_pick := _variant_table.roll(index, room_type, _previous_variant, context.rng)
	if option != null and option.forces_variant():
		variant_pick = _pick_for_way(option)
	var elite_nest := option != null and option.kind == BranchOption.Kind.ELITE_NEST
	if RoomSequence.is_normal_combat(room_type):
		rolled_kind = RoomSequence.roll_room_kind(index, _previous_kind, context.rng)
		if variant_pick.has_variant() or elite_nest:
			# Variant rooms are fought as normal rooms (no arena, no chasm).
			rolled_kind = RoomSequence.RoomKind.NORMAL
	# A10: the room is entered through the wall opposite the previous room's exit.
	var entrance_side := RoomTiles.opposite_side(previous_exit.x) if previous != null else RoomTiles.DoorSide.SOUTH
	var room := _template_for(room_type, rolled_kind, special, index, entrance_side, variant_pick.plan_mode).instantiate() as RoomController
	var is_campfire := room_type == RoomSequence.RoomType.CAMPFIRE
	room.name = ("Campfire%d" if is_campfire else "Room%d") % index
	room.rolled_kind = rolled_kind
	room.slot_index = slot
	_previous_kind = int(room.room_kind) if rolled_kind >= 0 else -1
	# The campfire draws nothing from the dungeon RNG (no extra-dark roll, no kind, no template).
	var extra_dark := false if is_campfire else RoomSequence.roll_extra_dark(index, room_type, context.rng)
	room.setup(index, room_type, special, portal, context, extra_dark)
	# A10: doors, place, branch and secret niche, decided before the room is built.
	var secret := _plan_links(room, previous, previous_exit, slot, entrance_side, variant_pick.has_variant() or elite_nest,
			ModeRegistry.allows_secret(variant_pick.variant_id))
	room_container.add_child(room)
	if is_way:
		_branch_ways.append(room)
	else:
		_rooms[slot] = room
	# Special contents stand in the room from now on (#9; same RNG place as the room's own draws).
	room.prepare_special_content()
	# Enemy themes and the quiet room (A3) for normal combat rooms; always three RNG draws.
	if RoomSequence.is_normal_combat(room_type):
		var plan := EncounterVariation.roll(index, room_type, context.rng, room.room_kind)
		room.set_encounter_group(EncounterVariation.build_group(plan, index, room.spawner.get_biome(index)))
	if elite_nest:
		# The elite nest comes only through a branch (D-105); one RNG draw like every variant. Loaded
		# here, after the variant scripts: CombatVariant and its subclasses load each other.
		var nest: Node = (load(ELITE_NEST_SCRIPT) as GDScript).call(&"attach", room, context.rng.randi())
		_previous_variant = BranchOption.ELITE_NEST_ID if nest != null else VariantTable.NONE
	else:
		# Combat variant or wager altar (A7); one more RNG draw when something was picked.
		_previous_variant = RoomVariants.attach(room, variant_pick, context.rng)
	if not secret.is_empty():
		_attach_secret(room, secret["site"], secret["content"])
	assert(room_container.get_child_count() <= get_live_room_limit(), "Too many live rooms.")

	if previous != null and not is_way:
		previous.set_next_room(room)
		if is_campfire:
			previous.make_way_for_campfire()
	if staged:
		room.visible = false
		_queue_next(_cover_staged.bind(previous, room, option, via_exit, then))
	else:
		_dress_way(previous, room, previous_exit, option, via_exit)

	room.player_entered.connect(_on_player_entered_room, CONNECT_DEFERRED)
	room.completed.connect(_on_room_completed)
	room.encounter_started.connect(_on_encounter_started)
	room.wave_started.connect(_on_wave_started)
	room.branch_offered.connect(_on_branch_offered)
	room.branch_chosen.connect(_on_branch_chosen)
	if net != null:
		net.after_prepare_slot(room, way)
	return room


## Prepares a slot from outside (MP3: a network client builds the slot the host announced).
func prepare_slot(slot: int, option: BranchOption = null) -> RoomController:
	finish_preparing()
	return _prepare_slot(slot, option)


## Builds both ways of an active branch room from outside (MP3: a network client, once the host's RNG
## state of every way arrived; R5).
func prepare_branch_ways(room: RoomController) -> void:
	finish_preparing()
	if is_instance_valid(room) and room.is_branch_room() and _branch_ways.is_empty():
		_prepare_branch_ways(room)


# --- Way-finding (A10) ---

## Entrance, place and exit(s) of a prepared room (not yet in the tree), the branch draw and the
## secret niche. Normal combat rooms draw 1 (exit) + BranchRules.DRAWS + SecretRules.DRAWS numbers
## of the dungeon RNG, other rooms none. previous_exit: the exit of the previous room this room joins.
## allow_secret: false for modes that change the floor (Einsturz, R4): the draw happens, no niche.
## Returns {"site", "content"} of a niche or {}.
func _plan_links(room: RoomController, previous: RoomController, previous_exit: Vector2i, slot: int, entrance_side: int, has_variant: bool, allow_secret := true) -> Dictionary:
	var tiles := room.get_node("Tiles") as RoomTiles
	var index := room.room_index
	var combat := RoomSequence.is_normal_combat(room.room_type)
	if not tiles.allows_door(entrance_side):
		push_warning("Room %d: template has no door on side %d, entering from the south." % [index, entrance_side])
		entrance_side = RoomTiles.DoorSide.SOUTH
	var entrance_place := tiles.entrance_x if entrance_side == RoomTiles.DoorSide.SOUTH \
			else ExitRules.pick_place(tiles.get_door_slots(entrance_side), ExitRules.wall_length(entrance_side, tiles.room_size))
	# Place: the entrance corridor ends where the previous exit corridor ends; longer if a live
	# room is in the way.
	var origin := Vector2i.ZERO
	var extra := 0
	var previous_footprint: ExitRules.Footprint = null
	if previous != null:
		var exit := previous_exit
		var corridor_end := ExitRules.exit_corridor_end(get_room_origin(previous), previous.tiles.room_size, exit.x, exit.y)
		extra = ExitRules.extra_needed(corridor_end, tiles.room_size, Vector2i(entrance_side, entrance_place), get_live_footprints(previous))
		if extra < 0:
			push_warning("Room %d: no free place found, it overlaps another room." % index)
			extra = 0
		origin = ExitRules.origin_for(corridor_end, tiles.room_size, entrance_side, entrance_place, extra)
		previous_footprint = get_room_footprint(previous)
	room.position = Vector2(origin) * RoomTiles.TILE_WORLD
	# Exit wall: north before rooms that are entered from the south only, else north/west/east.
	var next_type := RoomSequence.get_slot_type(slot + 1)
	var template_sides: Array[int] = []
	for side: int in [RoomTiles.DoorSide.NORTH, RoomTiles.DoorSide.EAST, RoomTiles.DoorSide.WEST]:
		if tiles.allows_door(side):
			template_sides.append(side)
	var sides: Array[int] = [RoomTiles.DoorSide.NORTH]
	if combat:
		sides = ExitRules.allowed_exit_sides(entrance_side, next_type, template_sides)
	var estimates: Array[int] = []
	for side in sides:
		estimates.append(_estimate_extra(origin, tiles, side, next_type, previous_footprint))
	var exit_side := ExitRules.roll_exit(sides, estimates, context.rng.randf()) if combat else RoomTiles.DoorSide.NORTH
	var exits: Array[Vector2i] = [Vector2i(exit_side, _exit_place(tiles, exit_side))]
	# Branch (D-105).
	var options: Array[BranchOption] = []
	var branch := BranchRules.roll(index, room.room_type, next_type, has_variant, _branch_cycle, _previous_special, _special_table, _variant_table, context.rng)
	if branch.is_branch():
		var pair := BranchRules.pick_exit_pair(tiles, branch.options, sides, estimates)
		# Both ways are built before the choice (R5): only a branch whose two rooms fit is offered.
		if pair.size() == 2 and _ways_fit(origin, tiles, pair, branch.options, index + 1, previous_footprint):
			exits = pair
			options = branch.options
			_branch_cycle = BranchRules.get_cycle(index)
	var entrance := Vector2i(entrance_side, entrance_place)
	room.apply_door_plan(entrance, exits, extra, options)
	# Secret niche (after the doors: their lanes stay free).
	var pick := SecretRules.roll(index, room.room_type, int(room.room_kind), context.rng)
	if not pick.has_secret or not allow_secret:
		return {}
	var sites := _niche_sites(room, tiles, origin, previous, next_type)
	# M2: a niche behind the north wall and a way north exclude each other (the next room's floor
	# starts two rows above this floor). When only the north wall offers a niche, a plain fight leaves
	# through a side wall that needs no longer corridor instead; the niche's own roll picks it (no RNG).
	if sites.is_empty() and combat and options.is_empty() and exits[0].x == RoomTiles.DoorSide.NORTH:
		var side := _side_exit_for_niche(sides, estimates, pick.site_roll)
		if side >= 0:
			room.apply_door_plan(entrance, [Vector2i(side, _exit_place(tiles, side))] as Array[Vector2i], extra, options)
			sites = _niche_sites(room, tiles, origin, previous, next_type)
			if sites.is_empty():
				room.apply_door_plan(entrance, exits, extra, options)
	var site := SecretRules.choose_site(sites, pick.site_roll)
	if site == null:
		return {}
	SecretNiche.carve(room, site)
	return {"site": site, "content": pick.content}


## Places for a secret niche in a planned room: clear of the live rooms (the previous one lies
## behind another wall) and, when it reaches into the rock north of the room (behind the north wall or
## behind rock in the first floor row), clear of the room a north exit leads to (M2).
func _niche_sites(room: RoomController, tiles: RoomTiles, origin: Vector2i, previous: RoomController, next_type: int) -> Array[SecretRules.Site]:
	var sites: Array[SecretRules.Site] = []
	var others := get_live_footprints(previous)
	var north := _has_north_exit(tiles)
	var next_bodies := _next_bodies_north(origin, tiles, next_type) if north else []
	for candidate in SecretRules.find_sites(tiles, _secret_forbidden(room, tiles), _torch_columns(room)):
		if ExitRules.niche_clashes(origin, candidate.get_rect(), others):
			continue
		if north and not _niche_clear(origin, candidate, next_bodies):
			continue
		sites.append(candidate)
	return sites


## A side exit (no longer corridor needed) for a room whose niche must sit behind its north wall;
## roll in [0, 1) picks among them. -1 if there is none.
static func _side_exit_for_niche(sides: Array[int], estimates: Array[int], roll: float) -> int:
	var options: Array[int] = []
	for i in sides.size():
		var estimate := estimates[i] if i < estimates.size() else 0
		if sides[i] != RoomTiles.DoorSide.NORTH and estimate <= ExitRules.MAX_TURN_EXTRA:
			options.append(sides[i])
	if options.is_empty():
		return -1
	return options[mini(options.size() - 1, floori(roll * options.size()))]


static func _has_north_exit(tiles: RoomTiles) -> bool:
	for exit in tiles.get_exit_doors():
		if exit.x == RoomTiles.DoorSide.NORTH:
			return true
	return false


## World body rectangles the room behind each north exit may cover (worst case over the combat
## templates); empty before a room that is no normal combat room (special, boss and campfire rooms
## are wider and drawn later: no niche behind the north wall then).
func _next_bodies_north(origin: Vector2i, tiles: RoomTiles, next_type: int) -> Array:
	if not RoomSequence.is_normal_combat(next_type as RoomSequence.RoomType):
		return []
	var reach := _get_combat_reach(RoomTiles.DoorSide.SOUTH)
	var bodies: Array = []
	for exit in tiles.get_exit_doors():
		if exit.x == RoomTiles.DoorSide.NORTH:
			var end := ExitRules.exit_corridor_end(origin, tiles.room_size, exit.x, exit.y)
			bodies.append(Rect2i(reach.body.position + end, reach.body.size))
	return bodies


## A niche (with the rock around it) clear of every possible room behind a north exit: one that stays
## below the wall crown always is; above it, it must miss the bodies (none known: not clear).
static func _niche_clear(origin: Vector2i, site: SecretRules.Site, bodies: Array) -> bool:
	var rect := site.get_rect()
	if rect.position.y - 1 >= -1:
		return true
	if bodies.is_empty():
		return false
	var world := Rect2i(origin + rect.position - Vector2i.ONE, rect.size + Vector2i(2, 2))
	for body: Rect2i in bodies:
		if world.intersects(body):
			return false
	return true


## Place of an exit on a wall: the template's own north exit, else the place nearest the middle.
func _exit_place(tiles: RoomTiles, side: int) -> int:
	if side == RoomTiles.DoorSide.NORTH:
		return tiles.exit_x
	return ExitRules.pick_place(tiles.get_door_slots(side), ExitRules.wall_length(side, tiles.room_size))


## Estimated extra corridor tiles the next room needs behind this exit wall to keep clear of the
## previous room (worst case over the combat templates); 0 before rooms that are no combat room
## (they are always entered from the south, the exact place is found later).
func _estimate_extra(origin: Vector2i, tiles: RoomTiles, side: int, next_type: int, previous_footprint: ExitRules.Footprint) -> int:
	if previous_footprint == null or not RoomSequence.is_normal_combat(next_type as RoomSequence.RoomType):
		return 0
	var corridor_end := ExitRules.exit_corridor_end(origin, tiles.room_size, side, _exit_place(tiles, side))
	var others: Array[ExitRules.Footprint] = [previous_footprint]
	var needed := ExitRules.extra_needed_reach(corridor_end, _get_combat_reach(RoomTiles.opposite_side(side)), side, others)
	return needed if needed >= 0 else RoomTiles.MAX_CORRIDOR_EXTRA + 1


## Worst case over every combat template of the session's size classes (S/M for one or two
## players, D-084) that can be entered through side.
func _get_combat_reach(side: int) -> ExitRules.Footprint:
	if _combat_reach.has(side):
		return _combat_reach[side]
	var sizes: Array[Vector2i] = []
	var places: Array[int] = []
	for entry in _combat_catalog.get_entries():
		if not get_room_sizes().has(entry.size_class) or not entry.allows_entrance(side):
			continue
		var slots: Array[int] = []
		for slot in entry.door_slots:
			if slot.x == side:
				slots.append(slot.y)
		if slots.is_empty():
			continue
		sizes.append(entry.room_size)
		places.append(ExitRules.pick_place(slots, ExitRules.wall_length(side, entry.room_size)))
	_combat_reach[side] = ExitRules.reach_footprint(sizes, side, places)
	return _combat_reach[side]


## World tile of a room's tile (0, 0).
static func get_room_origin(room: RoomController) -> Vector2i:
	return Vector2i((room.position / RoomTiles.TILE_WORLD).round())


## World rectangle a live room paints (ring and corridors included).
static func get_room_rect(room: RoomController) -> Rect2i:
	var tiles := room.get_node("Tiles") as RoomTiles
	return ExitRules.world_rect(get_room_origin(room), tiles.room_size, tiles.entrance_side, tiles.entrance_corridor_extra)


## What a live room covers (painted ring, body, corridors), see ExitRules.Footprint.
static func get_room_footprint(room: RoomController) -> ExitRules.Footprint:
	var tiles := room.get_node("Tiles") as RoomTiles
	return ExitRules.footprint_of(get_room_origin(room), tiles.room_size, tiles.get_entrance_door(), tiles.entrance_corridor_extra,
			tiles.get_exit_doors(), tiles.niche_rect)


## Footprints of the live rooms except one (its predecessor shares a corridor tile), the built ways
## of a branch included.
func get_live_footprints(except: RoomController = null) -> Array[ExitRules.Footprint]:
	var footprints: Array[ExitRules.Footprint] = []
	var live: Array[RoomController] = []
	live.assign(_rooms.values())
	live.append_array(_branch_ways)
	for room in live:
		if room != except and is_instance_valid(room):
			footprints.append(get_room_footprint(room))
	return footprints


# --- Ways, veils and the branch (R5) ---

## The exit of previous a room joins: exit via_exit of a branch room, else its chosen exit.
static func _exit_of(previous: RoomController, via_exit: int) -> Vector2i:
	if previous == null:
		return Vector2i(RoomTiles.DoorSide.NORTH, 0)
	if via_exit >= 0:
		var exits := previous.tiles.get_exit_doors()
		return exits[clampi(via_exit, 0, exits.size() - 1)]
	return previous.get_chosen_exit()


## A prepared room lies dark behind its door (RoomVeil, not the first room), the door of the room
## before it shows the way (DoorSigns) and the corridor between gets its style (CorridorDressing).
## Where the two rooms overlap each keeps its own floor and walls (PassageSeam, M2).
func _dress_way(previous: RoomController, room: RoomController, _previous_exit: Vector2i, option: BranchOption, via_exit: int) -> void:
	_cover_way(previous, room)
	_sign_way(previous, room, option, via_exit)


## The veil over the room and the seam to the room before (what the eye needs first).
func _cover_way(previous: RoomController, room: RoomController) -> void:
	if room.slot_index > 1:
		RoomVeil.attach(room)
	if previous != null:
		PassageSeam.join(previous, room)


## The door of the room before shows the way (DoorSigns), the corridor between gets its style.
func _sign_way(previous: RoomController, room: RoomController, option: BranchOption, via_exit: int) -> void:
	if previous == null:
		return
	var previous_exit := _exit_of(previous, via_exit)
	var doors := previous.get_exit_doors()
	var door_index := via_exit if via_exit >= 0 else maxi(0, previous.get_chosen_branch())
	if door_index < doors.size():
		DoorSigns.show_way(doors[door_index], room, option)
	var exit_tile := RoomTiles.door_tile_of(previous_exit.x, previous_exit.y, previous.tiles.room_size)
	var other_door := get_room_origin(previous) + exit_tile - get_room_origin(room)
	var biome := room.spawner.get_biome(room.room_index)
	CorridorDressing.attach(room, other_door, _run_seed, room.room_index, biome.id if biome != null else &"")


## Staged dressing (#14), step 1: veil and seam; the room shows from now on.
func _cover_staged(previous: RoomController, room: RoomController, option: BranchOption, via_exit: int, then: Callable) -> void:
	if not is_instance_valid(room) or room.state == RoomController.State.UNLOADED:
		return
	_cover_way(previous if is_instance_valid(previous) else null, room)
	room.visible = true
	_queue_next(_sign_staged.bind(previous, room, option, via_exit, then))


## Step 2: door sign and corridor, then the job that follows the room (its side way).
func _sign_staged(previous: RoomController, room: RoomController, option: BranchOption, via_exit: int, then: Callable) -> void:
	if not is_instance_valid(room) or room.state == RoomController.State.UNLOADED:
		return
	if is_instance_valid(previous):
		_sign_way(previous, room, option, via_exit)
	if then.is_valid():
		_queue_next(then)


## A branch room was entered: both ways are built now, dark behind the shut doors (R5). Each way
## starts from the same chain state; the state each one leaves is kept for the choice.
## Dungeon RNG state before the slot (way -1) or branch way was drawn; -1 if never prepared.
func get_slot_rng_state(slot: int, way := -1) -> int:
	return _slot_rng_states.get(Vector2i(slot, way), -1)


func _prepare_branch_ways(room: RoomController, staged := false) -> void:
	if _run_ending:
		return
	_ways_base = _capture_chain()
	_ways_built = []
	_branch_room = room
	for i in room.branch_options.size():
		if staged:
			# One way per frame (#14), in the same order.
			_queue_job(_prepare_way.bind(room, i, true))
		else:
			_prepare_way(room, i, false)


## Way index of a branch room, from the common chain state. After the last way the states are kept
## for the choice and the chain is back where it was before the ways.
func _prepare_way(room: RoomController, index: int, staged: bool) -> void:
	if _run_ending or not is_instance_valid(room) or room != _branch_room or _ways_base == null:
		return
	_restore_chain(_ways_base)
	_prepare_slot(room.slot_index + 1, room.branch_options[index], index, staged)
	_ways_built.append(_capture_chain())
	if _ways_built.size() >= room.branch_options.size():
		_way_states = _ways_built
		_restore_chain(_ways_base)
		_ways_base = null
		_ways_built = []


## The way not chosen fades out and is freed; plain rock stays where it stood.
func _fade_out_way(way: RoomController) -> void:
	if not is_instance_valid(way):
		return
	_fading_rooms.append(way)
	way.mark_unloaded()
	for node in way.find_children("*", "", true, false):
		if node is LightSource:
			(node as LightSource).visible = false
	if _branch_room != null:
		_leave_rock(way, _branch_room.slot_index)
	var tween := way.create_tween()
	tween.tween_property(way, "modulate:a", 0.0, BRANCH_FADE_TIME)
	tween.tween_callback(_free_faded.bind(way))


func _free_faded(way: RoomController) -> void:
	if not _fading_rooms.has(way):
		return
	_fading_rooms.erase(way)
	if is_instance_valid(way):
		# The branch room gets back the wall it shared with this way (M2).
		PassageSeam.release(way, room_container.get_children())
		room_container.remove_child(way)
		way.free()


## Ways still fading go at once (before the next room is prepared, so it never has to avoid them).
func _drop_fading_rooms() -> void:
	for way in _fading_rooms.duplicate():
		_free_faded(way)


## Rock where a faded way stood, below every room: the dungeon never shows a hole there. Freed with
## the branch room (owner_slot).
func _leave_rock(way: RoomController, owner_slot: int) -> void:
	var tiles := way.tiles
	if tiles == null or tiles.tile_set == null:
		return
	if _rock_root == null:
		_rock_root = Node2D.new()
		_rock_root.name = "RockFills"
		add_child(_rock_root)
	var fill := TileMapLayer.new()
	fill.name = "RockFill%d" % way.slot_index
	fill.tile_set = tiles.tile_set
	fill.material = tiles.material
	fill.scale = tiles.scale
	fill.z_index = ROCK_FILL_Z
	fill.collision_enabled = false
	fill.navigation_enabled = false
	fill.occlusion_enabled = false
	fill.position = way.position + tiles.position
	var rect := tiles.get_backdrop_rect()
	# M1: the room's own rock fill (soft terrain), so the rooms around draw their round edges over it.
	var cell := tiles.get_rock_fill_cell()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			fill.set_cell(Vector2i(x, y), cell.z, Vector2i(cell.x, cell.y))
	_rock_root.add_child(fill)
	var fills: Array = _rock_fills.get(owner_slot, [])
	fills.append(fill)
	_rock_fills[owner_slot] = fills


func _free_rock_fills(slot: int) -> void:
	for fill: Node in _rock_fills.get(slot, []):
		if is_instance_valid(fill):
			fill.queue_free()
	_rock_fills.erase(slot)


func _capture_chain() -> ChainState:
	var state := ChainState.new()
	state.previous_special = _previous_special
	state.previous_kind = _previous_kind
	state.previous_variant = _previous_variant
	state.branch_cycle = _branch_cycle
	return state


func _restore_chain(state: ChainState) -> void:
	_previous_special = state.previous_special
	_previous_kind = state.previous_kind
	_previous_variant = state.previous_variant
	_branch_cycle = state.branch_cycle


## Can both ways of a branch be built at once (R5)? Each way room (worst case over the combat
## templates, the exact template for a special room) is placed behind its exit with the shortest
## entrance corridor that keeps it clear of the previous room and of the other way. No RNG.
func _ways_fit(origin: Vector2i, tiles: RoomTiles, exits: Array[Vector2i], options: Array[BranchOption], next_index: int, previous_footprint: ExitRules.Footprint) -> bool:
	var others: Array[ExitRules.Footprint] = []
	if previous_footprint != null:
		others.append(previous_footprint)
	for i in mini(exits.size(), options.size()):
		var exit := exits[i]
		var reach := _way_reach(options[i], next_index, RoomTiles.opposite_side(exit.x))
		if reach == null:
			return false
		var corridor_end := ExitRules.exit_corridor_end(origin, tiles.room_size, exit.x, exit.y)
		var extra := ExitRules.extra_needed_reach(corridor_end, reach, exit.x, others)
		if extra < 0:
			return false
		others.append(ExitRules.extend_reach(reach, corridor_end, exit.x, extra))
	return true


## Footprint of the room behind a branch way relative to its corridor end: the special room's own
## template (no RNG: the first plan of the type and biome), else the combat worst case.
func _way_reach(option: BranchOption, next_index: int, entrance_side: int) -> ExitRules.Footprint:
	if option.kind != BranchOption.Kind.SPECIAL:
		return _get_combat_reach(entrance_side)
	var scene := _template_for(RoomSequence.RoomType.SPECIAL, RoomSequence.RoomKind.NORMAL, option.special_type, next_index, RoomTiles.DoorSide.SOUTH)
	if scene == null:
		return null
	var layout := _scene_layout(scene)
	var sizes: Array[Vector2i] = [Vector2i(layout.x, layout.y)]
	var places: Array[int] = [layout.z]
	return ExitRules.reach_footprint(sizes, entrance_side, places)


## Room size (x, y) and south entrance place (z) of a template scene, cached by path.
func _scene_layout(scene: PackedScene) -> Vector3i:
	var key := scene.resource_path
	if not _layout_cache.has(key):
		var instance := scene.instantiate()
		var tiles := instance.get_node_or_null("Tiles") as RoomTiles
		_layout_cache[key] = Vector3i(tiles.room_size.x, tiles.room_size.y, tiles.entrance_x) if tiles != null else Vector3i(15, 9, 7)
		instance.free()
	return _layout_cache[key]


## Do two live rooms cover each other (tests, tools)? Neighbours share their corridor end only.
static func rooms_clash(first: RoomController, second: RoomController) -> bool:
	return get_room_footprint(first).clashes(get_room_footprint(second))


## The way of a branch decides the variant: none (safe), the hidden one (unknown); the elite nest is
## attached on its own (_prepare_slot).
func _pick_for_way(option: BranchOption) -> VariantTable.Pick:
	var pick := VariantTable.Pick.new()
	if option.kind == BranchOption.Kind.UNKNOWN:
		pick = VariantTable.pick_for(option.variant_id)
	return pick


## Tiles a secret niche must leave alone: spawn markers, template props, door lanes.
func _secret_forbidden(room: RoomController, tiles: RoomTiles) -> Dictionary:
	var forbidden := {}
	for marker in IngredientScatter.get_marker_tiles(room):
		forbidden[marker] = true
	for prop in room.get_node("Props").get_children():
		var node := prop as Node2D
		if node != null and not String(node.name).begins_with("Torch"):
			forbidden[RoomTiles.local_to_tile(node.position)] = true
			forbidden[RoomTiles.local_to_tile(node.position + Vector2(0, -8))] = true
	var doors: Array[Vector2i] = [tiles.get_entrance_door()]
	doors.append_array(tiles.get_exit_doors())
	for door in doors:
		for tile in RoomTiles.door_lane_of(door.x, door.y, tiles.room_size, RoomController.DOOR_LANE_DEPTH):
			forbidden[tile] = true
	return forbidden


## Columns of the north wall torches of a template (a niche in row 0 keeps clear of them).
func _torch_columns(room: RoomController) -> Array[int]:
	var columns: Array[int] = []
	for prop in room.get_node("Props").get_children():
		var node := prop as Node2D
		if node != null and String(node.name).begins_with("Torch"):
			columns.append(floori(node.position.x / RoomTiles.TILE_WORLD))
			columns.append(floori(node.position.x / RoomTiles.TILE_WORLD) - 1)
	return columns


func _attach_secret(room: RoomController, site: SecretRules.Site, content: SecretRules.Content) -> void:
	var niche := SecretNiche.attach(room, site, content)
	niche.opened.connect(_on_secret_opened)
	niche.tapped.connect(_on_secret_tapped)
	niche.content_used.connect(_on_secret_used)


## A cracked wall broke (A10): the genre banner "Geheimnis" (explained the first time per save).
func _on_secret_opened(niche: SecretNiche) -> void:
	ui.show_genre(RoomGenre.SECRET, niche.room)


## Struck without an explosion: once per save the hint how cracked walls open.
func _on_secret_tapped(_niche: SecretNiche) -> void:
	if SaveManager.has_seen(SECRET_HINT_ID):
		return
	SaveManager.mark_seen(SECRET_HINT_ID)
	ui.show_hint(DungeonTexts.t(&"SECRET_HINT_TITLE"), DungeonTexts.t(&"SECRET_HINT_TEXT"))


func _on_secret_used(niche: SecretNiche) -> void:
	if niche.content_kind == SecretRules.Content.CRYSTAL:
		ui.show_banner(DungeonTexts.t(&"SECRET_CRYSTALS_TITLE"), DungeonTexts.t(&"SECRET_CRYSTALS_SUB", [SecretRules.CRYSTALS]), UiKit.COLOR_GOLD)


## Branch room cleared: the doors wait (D-105).
func _on_branch_offered(_room: RoomController) -> void:
	ui.show_banner(DungeonTexts.t(&"BRANCH_TITLE"), DungeonTexts.t(&"BRANCH_SUB"), BRANCH_BANNER_COLOR)


## The group chose a way: its room stands built behind the door and becomes room n+1; the other way
## fades out (R5). Without built ways (not entered yet) room n+1 is prepared for the way now.
func _on_branch_chosen(room: RoomController, index: int) -> void:
	if not is_instance_valid(room) or _run_ending or index < 0 or index >= room.branch_options.size():
		return
	finish_preparing()
	if room != _branch_room or index >= _branch_ways.size():
		_prepare_slot(room.slot_index + 1, room.branch_options[index])
		return
	var chosen := _branch_ways[index]
	_restore_chain(_way_states[index])
	_rooms[room.slot_index + 1] = chosen
	for i in _branch_ways.size():
		if i != index:
			_fade_out_way(_branch_ways[i])
	_branch_ways.clear()
	_way_states.clear()
	_branch_room = null


func _unload_slot(slot: int) -> void:
	_free_rock_fills(slot)
	var room: RoomController = _rooms.get(slot)
	if room == null:
		return
	_rooms.erase(slot)
	room.mark_unloaded()
	# M2: the room after it gets back the wall they shared, and its open entrance leads nowhere now.
	PassageSeam.release(room, room_container.get_children())
	var entrance := Door.entrance_of(_rooms.get(slot + 1))
	if entrance != null:
		entrance.block()
	room_container.remove_child(room)
	# free(), not queue_free(): the instance must be gone before the next one is created.
	room.free()


## Combat rooms: a template of the rolled kind in a size for the player count (S or M, L for 3-4
## players, D-084); kinds without a template fall back to a normal room (D-100, RoomCatalog.pick).
func _template_for(room_type: RoomSequence.RoomType, kind: int = RoomSequence.RoomKind.NORMAL, special := -1, room_index := 0, entrance_side := -1, plan_mode: StringName = &"") -> PackedScene:
	match room_type:
		RoomSequence.RoomType.SPECIAL:
			# Some special types bring their own floor plan (trial room, A8).
			var own := SpecialTable.get_template_for(special)
			if own == null:
				# R1: rest plan of the special type in the room's biome (first plan, no RNG draw).
				var rest := RoomCatalog.pick_plan(RoomTemplate.ROLE_REST, RoomCatalog.biome_id_for_room(room_index), special)
				own = rest.scene if rest != null else null
			return own if own != null else special_template
		RoomSequence.RoomType.MINIBOSS:
			var miniboss := RoomCatalog.pick_plan(RoomTemplate.ROLE_MINIBOSS, RoomCatalog.biome_id_for_room(room_index))
			return miniboss.scene if miniboss != null else miniboss_template
		RoomSequence.RoomType.BOSS:
			var boss := RoomCatalog.find_boss_scene(RoomCatalog.biome_id_for_room(room_index))
			return boss if boss != null else boss_template
		RoomSequence.RoomType.CAMPFIRE:
			return campfire_template if campfire_template != null else load(CAMPFIRE_TEMPLATE_PATH) as PackedScene
	# A room entered from the west or east needs a door place there (A10; not the catacomb).
	var side_filter := entrance_side if entrance_side != RoomTiles.DoorSide.SOUTH else -1
	# R4: a minigame draws a plan made for it when one fits the room (else any combat plan).
	var mode := RoomVariants.plan_mode_for(plan_mode, _combat_catalog, kind, room_index, side_filter)
	var template: PackedScene = _combat_catalog.pick(kind, get_room_sizes(), context.rng, &"", room_index, side_filter, mode)
	assert(template != null, "No combat room templates configured.")
	return template


## Combat room size classes for the session's player count (D-084: 1-2 players S/M, 3-4 L). The
## rooms from plans (R1, D-131) have no L templates yet: a group then gets S/M like a solo run.
func get_room_sizes() -> Array[RoomSequence.RoomSize]:
	var sizes := RoomSequence.room_sizes_for(GameMode.of(self).get_player_count())
	if sizes == RoomSequence.SOLO_ROOM_SIZES or _combat_catalog == null:
		return sizes
	for entry in _combat_catalog.get_entries():
		if sizes.has(entry.size_class):
			return sizes
	return RoomSequence.SOLO_ROOM_SIZES


# Deferred: runs outside physics callbacks, so freeing rooms is safe here.
func _on_player_entered_room(room: RoomController) -> void:
	finish_preparing()
	if not is_instance_valid(room) or room.slot_index <= _active_slot or _run_ending:
		return
	# A way of a branch before the choice: its door is shut, nobody gets in (R5).
	if _branch_ways.has(room):
		return
	# MP3: the host waits for the group (exit rule D-126), a client waits for the host.
	if net != null and not net.allow_room_entry(room):
		return
	enter_room(room)


## The group moves into room: it becomes the active room, N-2 goes, N+1 (or both ways of a branch
## room) is prepared - unless prepare_next is false: a network client gets them from the host (MP3).
func enter_room(room: RoomController, prepare_next := true) -> void:
	finish_preparing()
	if not is_instance_valid(room) or room.slot_index <= _active_slot or _run_ending or _branch_ways.has(room):
		return
	_active_slot = room.slot_index
	# The campfire is no room (D-103): room number, scaling and heals stay where they are.
	if room.room_index > 1 and not room.is_campfire():
		RunManager.advance_room()
	_drop_fading_rooms()
	_unload_slot(room.slot_index - 2)
	# The room lights up (R5; usually the corridor lifted the veil already).
	RoomVeil.lift_room(room)
	_apply_vision(room)
	room.activate()
	# No way back (M2): the gate of the room before shuts once everyone is inside this one. MP: only
	# the host watches the group and tells the clients (NetDungeon.close_gate_behind).
	if net == null:
		GateCloser.close_behind(_rooms.get(room.slot_index - 1), room)
	else:
		net.close_gate_behind(_rooms.get(room.slot_index - 1), room)
	# A branch room builds both ways, dark behind its doors (D-105, R5), any other room the next one;
	# from the next frame on (#14), in the same order as before.
	if room.is_branch_room():
		if prepare_next:
			_prepare_branch_ways(room, true)
	elif prepare_next:
		_queue_job(_prepare_next_of.bind(room))
	if room.is_campfire():
		_begin_campfire(room)
	room_activated.emit(room)


## The room after room (#14): built now, dressed in the next frames, then its side way is planned.
func _prepare_next_of(room: RoomController) -> void:
	if _run_ending or not is_instance_valid(room) or room.state == RoomController.State.UNLOADED:
		return
	var built_before := _rooms.has(room.slot_index + 1)
	var next := _prepare_slot(room.slot_index + 1, null, -1, true, _plan_side_way_of.bind(room))
	if next == null or built_before:
		# Nothing new was built (a network client waits for the host, or it stood already): the side
		# way right away, as before.
		_plan_side_way_of(room)


func _plan_side_way_of(room: RoomController) -> void:
	if _run_ending or not is_instance_valid(room) or room.state == RoomController.State.UNLOADED:
		return
	_plan_side_way(room, _rooms.get(room.slot_index + 1))


## M5: the way from room to next may run through a side segment (SideRules: after the campfire,
## the ladder way, 10 % after a rest room; never before the boss, never twice in a row).
## MP: the host plans with its own "skip" option and tells the clients (NetDungeon), a client plans
## only the ways the host announced (plan_side_way, same seed and slot = same segment).
func _plan_side_way(room: RoomController, next: RoomController, ladder_way := false, forced := false) -> SideGate:
	var skip := false if forced else SideWays.is_skipped()
	var gate := SideWays.plan(room, next, _run_seed, _last_side_slot == room.slot_index, ladder_way, skip)
	if gate != null:
		gate.passed.connect(_on_side_gate_passed)
	if net != null and not forced:
		net.after_plan_side_way(room, next, gate)
	return gate


## Plans the side way from room to next from outside (MP: a client, after the host announced it).
func plan_side_way(room: RoomController, next: RoomController) -> SideGate:
	if not is_instance_valid(room) or not is_instance_valid(next):
		return null
	var existing := room.get_node_or_null(^"SideGate") as SideGate
	return existing if existing != null else _plan_side_way(room, next, false, true)


func _on_side_gate_passed(gate: SideGate, _player: Player) -> void:
	if _run_ending or not is_instance_valid(gate.next_room):
		return
	# MP: the host takes the group into the segment and tells the clients (they wait for it).
	if net != null and not net.allow_side_transit(gate):
		return
	start_side_transit(gate)


## Takes every player of the session through the side segment of gate (M5; MP: also from outside).
func start_side_transit(gate: SideGate) -> SideTransit:
	if _run_ending or gate == null or not is_instance_valid(gate.next_room):
		return null
	gate.is_used = true
	_last_side_slot = gate.next_room.slot_index
	return SideTransit.start(self, get_session_players(), gate.layout, gate.next_room.room_index, context, gate.rng_seed, gate.place_players)


## Campfire entered: the boss music has faded, the next biome's ambient bed comes in (C3 hook);
## the next room then starts with the biome entry (stinger, loop).
func _begin_campfire(room: RoomController) -> void:
	get_tree().call_group(MusicPlayer.GROUP, &"begin_interlude", room.get_next_biome())


func _on_room_completed(room: RoomController) -> void:
	_completed_rooms += 1
	EventBus.room_completed.emit(room.room_index)
	if _completed_rooms % HEAL_EVERY_COMPLETED_ROOMS == 0 and not get_living_players().is_empty():
		for player in get_living_players():
			player.health.heal(HEAL_AMOUNT)
		Sfx.play_ui(self, &"heal")
	heal_countdown_changed.emit(get_rooms_until_heal())

	if room.room_type != RoomSequence.RoomType.SPECIAL:
		ui.hide_boss_bar()
		var is_boss := room.room_type == RoomSequence.RoomType.BOSS
		ui.show_banner(DungeonTexts.t(&"BOSS_DEFEATED_TITLE" if is_boss else &"ROOM_CLEARED_TITLE"), DungeonTexts.t(&"ROOM_CLEARED_SUB"), Color(1.0, 0.85, 0.4))
		Sfx.play_ui(self, &"room_clear")
		# Let the death animation play and the gold fly in before any dialog opens (D-070).
		await get_tree().create_timer(REWARD_DIALOG_DELAY, false).timeout
		if not is_instance_valid(room) or _run_ending:
			return

	if room.room_type == RoomSequence.RoomType.COMBAT_UPGRADE:
		await _offer_upgrade(DungeonTexts.t(&"UPGRADE_TITLE_COMBAT"))
	elif room.room_type == RoomSequence.RoomType.BOSS:
		if CAMPFIRE_EXIT_PORTAL:
			# The portal waits at the campfire behind the door (D-103).
			ui.show_banner(DungeonTexts.t(&"CAMPFIRE_AHEAD_TITLE"), DungeonTexts.t(&"CAMPFIRE_AHEAD_SUB"), CAMPFIRE_BANNER_COLOR)
		else:
			# Checkpoint: after every boss an exit portal appears (D-073).
			room.spawn_exit_portal()
			ui.show_banner(DungeonTexts.t(&"PORTAL_APPEARED_TITLE"), DungeonTexts.t(&"PORTAL_APPEARED_SUB"), Color(0.6, 0.85, 1.0))
	# MP3: a network client opens the exit when the host does.
	if is_instance_valid(room) and (net == null or net.may_open_exit(room)):
		room.open_exit()


func _offer_upgrade(title: String) -> void:
	if net != null:
		# MP3: every player picks their own upgrade; the host waits for all (D-126).
		await net.offer_upgrade(title)
		return
	if context.player == null:
		return
	var offer := upgrade_manager.roll_offer(context.get_owned_weapons(), context.rng)
	if offer.is_empty():
		return
	var choice: UpgradeData = await ui.choose_upgrade(offer, title)
	if choice != null:
		upgrade_manager.acquire_upgrade(choice)


func _apply_vision(room: RoomController) -> void:
	var biome := room.spawner.get_biome(room.room_index)
	# Pact curse "Lichtkreis -20 %" (D-112) applies on top of the biome factor.
	var curse_factor := PlayerCurses.vision_factor(context.player)
	var vision_factor := (biome.vision_factor if biome != null else 1.0) * curse_factor
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null:
		overlay.set_biome(biome, room.room_index == 1)
		if room.room_type == RoomSequence.RoomType.SPECIAL:
			# Special rooms are safe and lit (shop, weapons, fountain, altar).
			overlay.set_vision(SPECIAL_ROOM_DARKNESS, VISION_RADIUS * curse_factor)
		elif room.is_campfire():
			# Calm and dim; the colour follows the player through the blend (CampfireContent).
			overlay.set_vision(CAMPFIRE_DARKNESS, VISION_RADIUS * curse_factor)
		else:
			var radius := EXTRA_DARK_VISION_RADIUS if room.is_extra_dark else VISION_RADIUS
			overlay.set_vision(DUNGEON_DARKNESS, radius * vision_factor, room.room_index == 1)
	_announce_room(room, biome)


func _announce_room(room: RoomController, biome: BiomeData) -> void:
	if room.is_campfire():
		# Genre plaque "Lagerfeuer" with "Rast vor: <Biom>" (UX2).
		ui.show_room_genre(room)
		return
	var kind_text := get_room_kind_label(room) if SHOW_ROOM_KIND_BANNER else ""
	var entering_biome := room.room_index > 1 and (room.room_index - 1) % RoomSequence.BOSS_INTERVAL == 0
	if entering_biome and biome != null:
		ui.show_banner(biome.display_name, _with_kind(DungeonTexts.t(&"BIOME_NEW_SUB"), kind_text), biome.tile_tint)
		Sfx.play_ui(self, &"portal", -6.0)
	elif room.is_extra_dark and room.room_index > 1 and RoomSequence.get_biome(room.room_index) != RoomSequence.Biome.SHADOW_REALM:
		ui.show_banner(DungeonTexts.t(&"DARKNESS_TITLE"), _with_kind(DungeonTexts.t(&"DARKNESS_SUB"), kind_text), Color(0.7, 0.6, 1.0))
	elif not kind_text.is_empty() and room.room_index > 1:
		# Room 1 keeps the run start banner (Proviant).
		ui.show_banner(kind_text, Loc.t(&"HUD_ROOM", [room.room_index]), ROOM_KIND_BANNER_COLOR)
	# Arena, catacomb, special rooms, trials: named banner, explained once per save (UX2). Normal
	# combat rooms stay unnamed; banners queue behind each other.
	var genre := ui.show_room_genre(room)
	# Small holes outside a chasm room: the dash hint once per save (A4).
	var hint := ChasmRules.get_hint_entry(room.tiles.has_pits(), genre == RoomGenre.CHASM,
			SaveManager.has_seen(RoomGenre.get_seen_id(RoomGenre.CHASM)), SaveManager.has_seen(ChasmRules.HINT_ID))
	if not hint.is_empty():
		SaveManager.mark_seen(hint["id"])
		ui.show_hint(hint["title"], hint["text"], hint["badge"])


## Name of a combat room with gameplay of its own (D-110): "Arena", "Abgrund", "Katakombe"; empty for
## normal combat rooms and all other rooms. Kind and shape: RoomTemplate.of(room).
static func get_room_kind_label(room: RoomController) -> String:
	if not room.has_room_kind():
		return ""
	return RoomTemplate.get_room_name(room.room_kind, RoomTemplate.of(room))


static func _with_kind(subtitle: String, kind_text: String) -> String:
	return subtitle if kind_text.is_empty() else "%s · %s" % [subtitle, kind_text]


func _on_encounter_started(_room: RoomController, enemies: Array[Enemy]) -> void:
	for enemy in enemies:
		if enemy.data.is_boss or enemy.is_miniboss:
			# Soul crystals for bosses and champions (D-078, TESTWERTE).
			var crystals := CRYSTALS_PER_BOSS if enemy.data.is_boss else CRYSTALS_PER_CHAMPION
			enemy.died.connect(func(_e: Enemy) -> void: RunManager.add_run_crystals(crystals))
		if enemy.data.is_boss:
			# Not awaited: the intro must start in this frame, the rest of the encounter goes on.
			_announce_boss(enemy)
		elif enemy.is_miniboss:
			ui.show_boss_bar(enemy)


## Boss intro (roars and shakes itself) or, without intro data, the plain banner; then the boss bar.
func _announce_boss(enemy: Enemy) -> void:
	if BossIntro.has_intro_for(enemy):
		# The players stand still while the boss speaks (per-player lock, no global pause).
		var players := get_living_players()
		var unlock := func(_boss: Enemy = null) -> void:
			for player in players:
				if is_instance_valid(player):
					player.set_input_locked(INPUT_LOCK_BOSS_INTRO, false)
		for player in players:
			player.set_input_locked(INPUT_LOCK_BOSS_INTRO, true)
		if not players.is_empty():
			# Also released by the boss's safety timeout or its death, so the lock can never stick.
			enemy.intro_ended.connect(unlock, CONNECT_ONE_SHOT)
		await BossIntro.play(enemy, ui)
		unlock.call()
		if not is_instance_valid(enemy) or enemy.is_dead():
			return
	else:
		ui.show_banner(enemy.data.display_name, DungeonTexts.t(&"BOSS_BAR_KIND_BOSS"), Color(0.95, 0.4, 1.0))
		Sfx.play_ui(self, &"boss_roar")
		CameraShake.shake(self, 9.0)
	ui.show_boss_bar(enemy)


## First boss beaten in this save (B2, D-087): announce the new village upgrades right away; marking
## it seen keeps the village from showing the same notice again.
func _on_content_unlocked(id: StringName) -> void:
	if id != MetaUnlocks.EVENT_FIRST_BOSS:
		return
	ui.show_banner(MetaUnlocks.ANNOUNCE_TITLE, MetaUnlocks.describe_event(id), UiKit.COLOR_GOLD)
	SaveManager.mark_seen(MetaUnlocks.get_announce_key(id))


func _on_wave_started(_room: RoomController, _wave: int, _total: int) -> void:
	# Banner "Welle n/N" and gong come from ArenaObjective (R3); here only the shake.
	CameraShake.shake(self, 4.0)


func _on_upgrade_acquired(_upgrade: UpgradeData, _stacks: int) -> void:
	Sfx.play_ui(self, &"upgrade")


func _on_player_died() -> void:
	# A group run ends when nobody stands any more (D-084; reviving follows in MP5).
	if not get_living_players().is_empty():
		return
	await get_tree().create_timer(DEATH_SCREEN_DELAY, false).timeout
	end_run(RunManager.EndReason.DEATH)
