class_name DungeonManager
extends Node2D
## Owns the room sequence of one run: template choice, placement and streaming (D-002 .. D-008).
## Rooms are stacked northwards; each exit lines up with the next entrance. At most three room
## instances exist at any time (N-1, N, N+1): N-2 is freed immediately, before N+1 is created,
## so a fourth instance never exists, not even until the end of the frame (D-007).
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
## Kind of the room prepared last (-1 after a non-combat room): no abyss twice in a row (D-086).
var _previous_kind := -1
var _combat_catalog: RoomCatalog = null
var _run_ending := false

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

func _prepare_slot(slot: int) -> RoomController:
	if _rooms.has(slot):
		return _rooms[slot]
	var index := RoomSequence.get_room_for_slot(slot)
	var room_type := RoomSequence.get_slot_type(slot)
	var special := -1
	var portal := false
	if room_type == RoomSequence.RoomType.SPECIAL:
		special = RoomSequence.roll_special_type(_previous_special, context.rng)
		_previous_special = special
		portal = RoomSequence.roll_portal(context.rng)
	elif room_type == RoomSequence.RoomType.CAMPFIRE:
		portal = CAMPFIRE_EXIT_PORTAL

	var rolled_kind := -1
	if RoomSequence.is_normal_combat(room_type):
		rolled_kind = RoomSequence.roll_room_kind(index, _previous_kind, context.rng)
	var room := _template_for(room_type, rolled_kind).instantiate() as RoomController
	var is_campfire := room_type == RoomSequence.RoomType.CAMPFIRE
	room.name = ("Campfire%d" if is_campfire else "Room%d") % index
	room.rolled_kind = rolled_kind
	room.slot_index = slot
	_previous_kind = int(room.room_kind) if rolled_kind >= 0 else -1
	# The campfire draws nothing from the dungeon RNG (no extra-dark roll, no kind, no template).
	var extra_dark := false if is_campfire else RoomSequence.roll_extra_dark(index, room_type, context.rng)
	room.setup(index, room_type, special, portal, context, extra_dark)
	room_container.add_child(room)
	_rooms[slot] = room
	assert(room_container.get_child_count() <= MAX_LIVE_ROOMS, "More than three live rooms.")

	var previous: RoomController = _rooms.get(slot - 1)
	if previous != null:
		previous.set_next_room(room)
		var exit_tile := previous.get_exit_tile()
		var entrance_tile := room.get_entrance_tile()
		# The next room's lowest ring row (entrance + 1) overlaps the previous room's row -3.
		var offset := Vector2(exit_tile.x - entrance_tile.x, -3 - (entrance_tile.y + 1)) * RoomTiles.TILE_WORLD
		room.position = previous.position + offset
		if is_campfire:
			previous.make_way_for_campfire()

	room.player_entered.connect(_on_player_entered_room, CONNECT_DEFERRED)
	room.completed.connect(_on_room_completed)
	room.encounter_started.connect(_on_encounter_started)
	room.wave_started.connect(_on_wave_started)
	return room


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
## template fall back to an arena (D-086, RoomCatalog.pick).
func _template_for(room_type: RoomSequence.RoomType, kind: int = RoomSequence.RoomKind.ARENA) -> PackedScene:
	match room_type:
		RoomSequence.RoomType.SPECIAL:
			return special_template
		RoomSequence.RoomType.MINIBOSS:
			return miniboss_template
		RoomSequence.RoomType.BOSS:
			return boss_template
		RoomSequence.RoomType.CAMPFIRE:
			return campfire_template if campfire_template != null else load(CAMPFIRE_TEMPLATE_PATH) as PackedScene
	var template: PackedScene = _combat_catalog.pick(kind, RoomSequence.SOLO_ROOM_SIZES, context.rng)
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
	var vision_factor := biome.vision_factor if biome != null else 1.0
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null:
		overlay.set_biome(biome, room.room_index == 1)
		if room.room_type == RoomSequence.RoomType.SPECIAL:
			# Special rooms are safe and lit (shop, weapons, fountain, altar).
			overlay.set_vision(SPECIAL_ROOM_DARKNESS, VISION_RADIUS)
		elif room.is_campfire():
			# Calm and dim; the colour follows the player through the blend (CampfireContent).
			overlay.set_vision(CAMPFIRE_DARKNESS, VISION_RADIUS)
		else:
			var radius := EXTRA_DARK_VISION_RADIUS if room.is_extra_dark else VISION_RADIUS
			overlay.set_vision(DUNGEON_DARKNESS, radius * vision_factor, room.room_index == 1)
	_announce_room(room, biome)


func _announce_room(room: RoomController, biome: BiomeData) -> void:
	if room.is_campfire():
		var next := room.get_next_biome()
		var subtitle := "Rast, bevor es weitergeht" if next == null else "Rast vor: %s" % next.display_name
		ui.show_banner("Lagerfeuer", subtitle, CAMPFIRE_BANNER_COLOR)
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


## "Arena · M" for normal combat rooms, empty otherwise. Marks a fallback ("Arena · S (statt Abgrund)").
static func get_room_kind_label(room: RoomController) -> String:
	if not room.has_room_kind():
		return ""
	var label := "%s · %s" % [RoomSequence.get_kind_name(room.room_kind), RoomSequence.get_size_name(room.room_size_class)]
	if room.rolled_kind >= 0 and room.rolled_kind != room.room_kind:
		label += " (statt %s)" % RoomSequence.get_kind_name(room.rolled_kind)
	return label


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
