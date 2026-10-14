class_name DungeonManager
extends Node2D
## Owns the room sequence of one run: template choice, placement and streaming (D-002 .. D-008).
## Rooms are chained: each exit lines up with the next entrance. At most three room instances exist
## at any time (N-1, N, N+1): N-2 is freed immediately, before N+1 is created, so a fourth instance
## never exists, not even until the end of the frame (D-007).
## Way-finding (A10, KONZEPT_RAEUME §7, D-105): a room is left to the north, west or east and the
## next one is entered through the opposite wall; a room that would overlap a live room moves further
## out along a longer corridor (ExitRules). Now and then a cleared room offers two ways to room n+1
## (branch, BranchRules): room n+1 is prepared only when the group has chosen. Some combat rooms hide
## a niche behind a cracked wall (SecretRules, SecretNiche); it is no room of its own.
## Streaming counts slots, not room numbers: after every boss room a campfire takes a slot of its
## own without a room number (D-103, RoomSequence slots), so N-1/N/N+1 include the campfire.

signal room_activated(room: RoomController)
## Completed rooms left until the next regular heal (HUD detail line).
signal heal_countdown_changed(rooms_left: int)

const MAX_LIVE_ROOMS := 3
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
var _combat_catalog: RoomCatalog = null
var _run_ending := false
## Cycle (five rooms) of the last branch: at most one per cycle (D-105, BranchRules).
var _branch_cycle := -1
## Worst-case footprint of the next room per entrance wall (ExitRules.reach_footprint over the solo
## combat templates), for choosing turns that need no long corridor.
var _combat_reach: Dictionary[int, ExitRules.Footprint] = {}

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
	var first := _prepare_slot(1)
	_player_spawn.global_position = first.get_player_start()
	_prepare_slot(2)


## Called by the WorldController after it created the player for this world (D-041).
func on_player_spawned(player: Player) -> void:
	context.player = player
	upgrade_manager.player = player
	upgrade_effects.player = player
	player.weapon_controller.upgrades = upgrade_manager
	player.died.connect(_on_player_died)
	# Village meta upgrades and Proviant boosts (D-078), summarized in one banner (D-087).
	var applied := MetaProgression.apply_to_run(player, context)
	var summary := MetaProgression.get_run_start_summary(applied)
	if not summary.is_empty():
		ui.show_banner(MetaProgression.RUN_BANNER_TITLE, summary)
	heal_countdown_changed.emit(get_rooms_until_heal())


func get_rooms_until_heal() -> int:
	return HEAL_EVERY_COMPLETED_ROOMS - _completed_rooms % HEAL_EVERY_COMPLETED_ROOMS


## Live room with this room number (null if not prepared or already unloaded).
func get_room(index: int) -> RoomController:
	return _rooms.get(RoomSequence.get_slot_for_room(index))


## Live campfire behind boss room after_room (null if not prepared, unloaded or no boss room).
func get_campfire(after_room: int) -> RoomController:
	var slot := RoomSequence.get_campfire_slot_after(after_room)
	return _rooms.get(slot) if slot > 0 else null


func get_room_at_slot(slot: int) -> RoomController:
	return _rooms.get(slot)


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
	_run_ending = true
	RunManager.end_run(reason)


# --- Streaming ---

## option: the way the group chose in a branch room (D-105) - it decides the special type or the
## variant of this room (safe way: none); the usual draws still happen, so the stream stays in step.
func _prepare_slot(slot: int, option: BranchOption = null) -> RoomController:
	if _rooms.has(slot):
		return _rooms[slot]
	var index := RoomSequence.get_room_for_slot(slot)
	var room_type := RoomSequence.get_slot_type(slot)
	if option != null:
		room_type = option.get_room_type(room_type) as RoomSequence.RoomType
	var previous: RoomController = _rooms.get(slot - 1)
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
	var entrance_side := RoomTiles.opposite_side(previous.get_chosen_exit().x) if previous != null else RoomTiles.DoorSide.SOUTH
	var room := _template_for(room_type, rolled_kind, special, index, entrance_side).instantiate() as RoomController
	var is_campfire := room_type == RoomSequence.RoomType.CAMPFIRE
	room.name = ("Campfire%d" if is_campfire else "Room%d") % index
	room.rolled_kind = rolled_kind
	room.slot_index = slot
	_previous_kind = int(room.room_kind) if rolled_kind >= 0 else -1
	# The campfire draws nothing from the dungeon RNG (no extra-dark roll, no kind, no template).
	var extra_dark := false if is_campfire else RoomSequence.roll_extra_dark(index, room_type, context.rng)
	room.setup(index, room_type, special, portal, context, extra_dark)
	# A10: doors, place, branch and secret niche, decided before the room is built.
	var secret := _plan_links(room, previous, slot, entrance_side, variant_pick.has_variant() or elite_nest)
	room_container.add_child(room)
	_rooms[slot] = room
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
	assert(room_container.get_child_count() <= MAX_LIVE_ROOMS, "More than three live rooms.")

	if previous != null:
		previous.set_next_room(room)
		if is_campfire:
			previous.make_way_for_campfire()

	room.player_entered.connect(_on_player_entered_room, CONNECT_DEFERRED)
	room.completed.connect(_on_room_completed)
	room.encounter_started.connect(_on_encounter_started)
	room.wave_started.connect(_on_wave_started)
	room.branch_offered.connect(_on_branch_offered)
	room.branch_chosen.connect(_on_branch_chosen)
	return room


# --- Way-finding (A10) ---

## Entrance, place and exit(s) of a prepared room (not yet in the tree), the branch draw and the
## secret niche. Normal combat rooms draw 1 (exit) + BranchRules.DRAWS + SecretRules.DRAWS numbers
## of the dungeon RNG, other rooms none. Returns {"site", "content"} of a niche or {}.
func _plan_links(room: RoomController, previous: RoomController, slot: int, entrance_side: int, has_variant: bool) -> Dictionary:
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
		var exit := previous.get_chosen_exit()
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
		if pair.size() == 2:
			exits = pair
			options = branch.options
			_branch_cycle = BranchRules.get_cycle(index)
	room.apply_door_plan(Vector2i(entrance_side, entrance_place), exits, extra, options)
	# Secret niche (after the doors: their lanes stay free).
	var pick := SecretRules.roll(index, room.room_type, int(room.room_kind), context.rng)
	if not pick.has_secret:
		return {}
	# Behind the north wall, clear of the live rooms (the previous one lies behind another wall).
	var sites: Array[SecretRules.Site] = []
	var others := get_live_footprints(previous)
	for candidate in SecretRules.find_sites(tiles, _secret_forbidden(room, tiles), _torch_columns(room)):
		if not ExitRules.niche_clashes(origin, candidate.get_rect(), others):
			sites.append(candidate)
	var site := SecretRules.choose_site(sites, pick.site_roll)
	if site == null:
		return {}
	SecretNiche.carve(room, site)
	return {"site": site, "content": pick.content}


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


## Worst case over every single-player combat template that can be entered through side.
func _get_combat_reach(side: int) -> ExitRules.Footprint:
	if _combat_reach.has(side):
		return _combat_reach[side]
	var sizes: Array[Vector2i] = []
	var places: Array[int] = []
	for entry in _combat_catalog.get_entries():
		if not RoomSequence.SOLO_ROOM_SIZES.has(entry.size_class) or not entry.allows_entrance(side):
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


## Footprints of the live rooms except one (its predecessor shares a corridor tile).
func get_live_footprints(except: RoomController = null) -> Array[ExitRules.Footprint]:
	var footprints: Array[ExitRules.Footprint] = []
	for room: RoomController in _rooms.values():
		if room != except and is_instance_valid(room):
			footprints.append(get_room_footprint(room))
	return footprints


## Do two live rooms cover each other (tests, tools)? Neighbours share their corridor end only.
static func rooms_clash(first: RoomController, second: RoomController) -> bool:
	return get_room_footprint(first).clashes(get_room_footprint(second))


## The way of a branch decides the variant: none (safe), the hidden one (unknown); the elite nest is
## attached on its own (_prepare_slot).
func _pick_for_way(option: BranchOption) -> VariantTable.Pick:
	var pick := VariantTable.Pick.new()
	if option.kind == BranchOption.Kind.UNKNOWN:
		pick.variant_id = option.variant_id
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


## The group chose a way: room n+1 is prepared for it now (the third live room).
func _on_branch_chosen(room: RoomController, index: int) -> void:
	if not is_instance_valid(room) or _run_ending or index < 0 or index >= room.branch_options.size():
		return
	_prepare_slot(room.slot_index + 1, room.branch_options[index])


func _unload_slot(slot: int) -> void:
	var room: RoomController = _rooms.get(slot)
	if room == null:
		return
	_rooms.erase(slot)
	room.mark_unloaded()
	room_container.remove_child(room)
	# free(), not queue_free(): the instance must be gone before the next one is created.
	room.free()


## Combat rooms: a template of the rolled kind in a single-player size (S or M); kinds without a
## template fall back to a normal room (D-100, RoomCatalog.pick).
func _template_for(room_type: RoomSequence.RoomType, kind: int = RoomSequence.RoomKind.NORMAL, special := -1, room_index := 0, entrance_side := -1) -> PackedScene:
	match room_type:
		RoomSequence.RoomType.SPECIAL:
			# Some special types bring their own floor plan (trial room, A8).
			var own := SpecialTable.get_template_for(special)
			return own if own != null else special_template
		RoomSequence.RoomType.MINIBOSS:
			return miniboss_template
		RoomSequence.RoomType.BOSS:
			return boss_template
		RoomSequence.RoomType.CAMPFIRE:
			return campfire_template if campfire_template != null else load(CAMPFIRE_TEMPLATE_PATH) as PackedScene
	# A room entered from the west or east needs a door place there (A10; not the catacomb).
	var side_filter := entrance_side if entrance_side != RoomTiles.DoorSide.SOUTH else -1
	var template: PackedScene = _combat_catalog.pick(kind, RoomSequence.SOLO_ROOM_SIZES, context.rng, &"", room_index, side_filter)
	assert(template != null, "No combat room templates configured.")
	return template


# Deferred: runs outside physics callbacks, so freeing rooms is safe here.
func _on_player_entered_room(room: RoomController) -> void:
	if not is_instance_valid(room) or room.slot_index <= _active_slot or _run_ending:
		return
	_active_slot = room.slot_index
	# The campfire is no room (D-103): room number, scaling and heals stay where they are.
	if room.room_index > 1 and not room.is_campfire():
		RunManager.advance_room()
	_unload_slot(room.slot_index - 2)
	_apply_vision(room)
	room.activate()
	# A branch room prepares room n+1 when the group has chosen its way (D-105).
	if not room.is_branch_room():
		_prepare_slot(room.slot_index + 1)
	if room.is_campfire():
		_begin_campfire(room)
	room_activated.emit(room)


## Campfire entered: the boss music has faded, the next biome's ambient bed comes in (C3 hook);
## the next room then starts with the biome entry (stinger, loop).
func _begin_campfire(room: RoomController) -> void:
	get_tree().call_group(MusicPlayer.GROUP, &"begin_interlude", room.get_next_biome())


func _on_room_completed(room: RoomController) -> void:
	_completed_rooms += 1
	EventBus.room_completed.emit(room.room_index)
	if _completed_rooms % HEAL_EVERY_COMPLETED_ROOMS == 0 and context.player != null and context.player.is_alive():
		context.player.health.heal(HEAL_AMOUNT)
		Sfx.play_ui(self, &"heal")
	heal_countdown_changed.emit(get_rooms_until_heal())

	if room.room_type != RoomSequence.RoomType.SPECIAL:
		ui.hide_boss_bar()
		var is_boss := room.room_type == RoomSequence.RoomType.BOSS
		ui.show_banner("Boss besiegt!" if is_boss else "Raum geschafft!", "Der Weg ist frei", Color(1.0, 0.85, 0.4))
		Sfx.play_ui(self, &"room_clear")
		# Let the death animation play and the gold fly in before any dialog opens (D-070).
		await get_tree().create_timer(REWARD_DIALOG_DELAY, false).timeout
		if not is_instance_valid(room) or _run_ending:
			return

	if room.room_type == RoomSequence.RoomType.COMBAT_UPGRADE:
		await _offer_upgrade("Kampf gewonnen!")
	elif room.room_type == RoomSequence.RoomType.BOSS:
		if CAMPFIRE_EXIT_PORTAL:
			# The portal waits at the campfire behind the door (D-103).
			ui.show_banner("Ein Lagerfeuer wartet", "Rast und Ausgang hinter der Tür", CAMPFIRE_BANNER_COLOR)
		else:
			# Checkpoint: after every boss an exit portal appears (D-073).
			room.spawn_exit_portal()
			ui.show_banner("Ein Portal ist erschienen", "Gold sichern oder tiefer hinab?", Color(0.6, 0.85, 1.0))
	if is_instance_valid(room):
		room.open_exit()


func _offer_upgrade(title: String) -> void:
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
		ui.show_banner(biome.display_name, _with_kind("Ein neues Gebiet", kind_text), biome.tile_tint)
		Sfx.play_ui(self, &"portal", -6.0)
	elif room.is_extra_dark and room.room_index > 1 and RoomSequence.get_biome(room.room_index) != RoomSequence.Biome.SHADOW_REALM:
		ui.show_banner("Finsternis", _with_kind("Hier ist es noch dunkler …", kind_text), Color(0.7, 0.6, 1.0))
	elif not kind_text.is_empty() and room.room_index > 1:
		# Room 1 keeps the run start banner (Proviant).
		ui.show_banner(kind_text, "Raum %d" % room.room_index, ROOM_KIND_BANNER_COLOR)
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
		# The player stands still while the boss speaks (per-player lock, no global pause).
		var player := context.player
		var unlock := func(_boss: Enemy = null) -> void:
			if is_instance_valid(player):
				player.set_input_locked(INPUT_LOCK_BOSS_INTRO, false)
		if player != null:
			player.set_input_locked(INPUT_LOCK_BOSS_INTRO, true)
			# Also released by the boss's safety timeout or its death, so the lock can never stick.
			enemy.intro_ended.connect(unlock, CONNECT_ONE_SHOT)
		await BossIntro.play(enemy, ui)
		unlock.call()
		if not is_instance_valid(enemy) or enemy.is_dead():
			return
	else:
		ui.show_banner(enemy.data.display_name, "Boss", Color(0.95, 0.4, 1.0))
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


func _on_wave_started(_room: RoomController, wave: int, total: int) -> void:
	ui.show_banner("Welle %d/%d" % [wave, total], "Sie kommen …", Color(1.0, 0.5, 0.4))
	Sfx.play_ui(self, &"boss_roar", -10.0)
	CameraShake.shake(self, 4.0)


func _on_upgrade_acquired(_upgrade: UpgradeData, _stacks: int) -> void:
	Sfx.play_ui(self, &"upgrade")


func _on_player_died() -> void:
	await get_tree().create_timer(DEATH_SCREEN_DELAY, false).timeout
	end_run(RunManager.EndReason.DEATH)
