class_name NetDungeon
extends Node
## The dungeon of a shared run (MP3, D-126), child "NetDungeon" of the DungeonManager on every
## machine (same node path). Host-authoritative: only the host runs enemies, damage, drops, room
## logic and the dungeon RNG; clients send input (NetPlayerState) and show what the host replicates.
##
## Rooms: both build the same dungeon from the seed. For every slot and every built way of a branch
## the host sends the dungeon RNG state the DungeonManager captured before drawing it
## (DungeonManager.slot_rng_captured / get_slot_rng_state, D-135..D-137), the player count and the
## chosen way (prepare_slot_net); a client builds exactly the same room whatever it drew in between
## and builds both ways of a branch room once both states arrived (R5: up to four live rooms, the
## ways dark behind their doors, never started on a client). The host's group chooses the way
## (branch_chosen_net); room_signature checks every slot, every way and the chosen way. The host decides when a room starts
## (exit rule: all living players inside, or 10 s after the first one, stragglers are teleported),
## when it is cleared and when the exit opens; clients follow (activate_slot, room_completed_net,
## exit_opened). Enemies, enemy projectiles, pickups and crates: NetEnemies (online/net_enemies.gd).
## Rooms from plans (R1-R3, D-131-D-133): a client's room never spawns (RoomController.remote_encounter,
## no spawn sources, waves or completion of its own); the host sends the wave state of the running
## fight (room_progress -> RoomController.apply_remote_progress: the client's intro ends, the arena's
## task bar counts, "Welle n/N" comes) and the state of other room goals (objective_state, mirrored
## into a RoomObjective). Room intros play on every machine, but each one locks only its own player.
## Room modes (minigames R4, D-135..D-137): NetModes (online/net_modes.gd).
## Makeover (M2, M4, M5; D-140, D-143, D-144): the gate behind a started room shuts only at the host,
## once every living player is inside, and the clients follow (gate_closed); stragglers the exit rule
## brings in land past the gate; a player who gets up behind a shut gate joins the team. The camera of
## the local player follows the group (CoopRules.camera_group). Side-view segments: NetSide.
##
## Players: HP, shield, weapons, upgrades and dash are per player and live at the host's copy of
## every player. Clients get vitals (player_states, player_hit) and loadouts; their own changes in
## special rooms (weapon pedestal, upgrades, fountain heal) are reported to the host, shop purchases
## are validated there (shared run gold, first come first served). Downed and revive (D-084): at 0 HP
## a player lies on the floor; a teammate standing next to them for 2 s gets them up with 2 HP, a
## cleared room gets everyone up, everyone down ends the run. Upgrade choice: every player picks
## their own (30 s, then the first card); the exit opens when all living players have picked.
## Run end: the host's end_run goes to everybody (run_over), every machine books its own payout.
## Messages are reliable RPCs on channel 0, snapshots unreliable_ordered on channel 2.

const NODE_NAME := &"NetDungeon"
## Host: a client's menu is open (D-085/D-123), its player is protected.
const REMOTE_MENU := &"menu_remote"
## Client: hits on players are resolved by the host only.
const CLIENT_INVULNERABLE := &"net_client"
const STATE_FIELDS := 5
const COUNTDOWN_COLOR := Color(1.0, 0.85, 0.4)
const DOWNED_COLOR := Color(1.0, 0.45, 0.4)
const SHOP_SCRIPT_SUFFIX := "shop_content.gd"
## Slots the DungeonManager prepares in its _ready (from the seed alone, before any message).
const INITIAL_SLOTS := 2

var run: NetRun = null
var dm: DungeonManager = null
var is_host := false
var enemies: NetEnemies = null

## Test and tool counters.
var rooms_activated := 0
var revives := 0
var signature_mismatches := 0
var upgrade_rounds := 0
## Wave states sent (host) or applied (client), room goals mirrored (client).
var progress_events := 0
var objective_events := 0
## Slots / branch ways whose signature was compared (client), branch choices applied (client), RNG
## states that did not match the host's after building (client).
var signatures_checked := 0
var way_signatures_checked := 0
var branch_choices := 0
var rng_mismatches := 0
var modes: NetModes = null
var side: NetSide = null
## Gates shut behind a started room (host: shut, client: mirrored), host: shut while a living player
## was still outside the new room (must stay 0), players brought to the team after getting up behind a
## shut gate, most targets the local group camera had at once.
var gates_closed := 0
var gates_closed_early := 0
var rejoins := 0
var max_camera_targets := 0

## Test aid (net_run_smoke): overrides of the mode table for a networked run, applied on every machine
## before the first slot (keys: chance, from_room, ids). Never set in the game.
static var test_mode_table: Dictionary = {}

var _detached := false
## Host: clients whose dungeon is loaded (client_ready), they get every message from then on.
var _ready_peers: Dictionary[int, bool] = {}
var _start_msec := 0
var _waiting_room: RoomController = null
var _wait_time := 0.0
var _countdown_shown := -1
## Host: signature of every prepared slot and branch way (Vector2i(slot, way), way -1 = the slot's
## room; catch-up for late clients).
var _signatures: Dictionary[Vector2i, String] = {}
## Host: upgrade picks per slot {slot: {peer: true}}.
var _picks: Dictionary[int, Dictionary] = {}
## Revive progress per peer (host computes, clients show).
var _revive: Dictionary[int, float] = {}
var _state_left := 0.0
## Shop offers per slot (host: the real ones; client: the host's copy).
var _shop_offers: Dictionary[int, Array] = {}
## Client.
## Client: the host's RNG state per Vector2i(slot, way) until that slot or way is built, and every
## state the host sent (compared with what the DungeonManager captured).
var _pending_states: Dictionary[Vector2i, int] = {}
var _host_states: Dictionary[Vector2i, int] = {}
## Client: the host's last pot (a client's own finish() may add crystals of a mode for a moment).
var _last_pot := Vector3i(-1, -1, -1)
## Client: the host's last goal state per slot (the room's own mode may attach a fresh goal later).
var _objective_states: Dictionary[int, Array] = {}
var _host_end := false
var _syncing := false
var _applying_loadout := false
var _expected_signatures: Dictionary[Vector2i, String] = {}
var _local_hp := 0.0
var _downed_announced := false
## Per-player upgrades of every player that is not this machine's primary one (instance id ->).
var _managers: Dictionary[int, UpgradeManager] = {}
var _effects: Dictionary[int, UpgradeEffects] = {}
var _revive_labels: Dictionary[int, Label] = {}
var _countdown_layer: CanvasLayer = null
var _countdown_label: Label = null
## Host: last wave state sent per slot (wave, total, alive, alive in the wave).
var _progress_sent: Dictionary[int, Vector4i] = {}


static func create(owner_run: NetRun, dungeon: DungeonManager) -> NetDungeon:
	var net := NetDungeon.new()
	net.name = NODE_NAME
	net.run = owner_run
	net.dm = dungeon
	return net


static func signature_of(room: RoomController) -> String:
	var tiles := room.get_node("Tiles") as RoomTiles
	return "%s|%d|%d|%s|%s|%s|%s|%s" % [room.scene_file_path.get_file(), room.room_type, room.special_type,
			room.position.round(), tiles.get_entrance_door(), tiles.get_exit_doors(), room.get_variant_id(), NetModes.layout_of(room)]


static func serialize_offer(offer: ShopOffer) -> Array:
	return [int(offer.kind), String(offer.upgrade.id) if offer.upgrade != null else "",
			offer.weapon.resource_path if offer.weapon != null else "", offer.price, offer.amount, offer.sold]


func _enter_tree() -> void:
	if dm == null:
		dm = get_parent() as DungeonManager
	if dm == null:
		return
	dm.net = self
	# Trial rooms are not replicated yet (D-126): no trials in a shared run. Done on every machine
	# before the first slot, so the special draw stays the same everywhere.
	var table: Variant = dm.get(&"_special_table")
	if table is SpecialTable and (table as SpecialTable).trial_weight > 0.0:
		var shared := (table as SpecialTable).duplicate() as SpecialTable
		shared.trial_weight = 0.0
		dm.set(&"_special_table", shared)
	_apply_test_mode_table()


## net_run_smoke: every mode from one room on, always a mode where the table allows one (same on
## every machine, before the first slot, so the stream stays the same everywhere).
func _apply_test_mode_table() -> void:
	var table: Variant = dm.get(&"_variant_table")
	if test_mode_table.is_empty() or not (table is VariantTable):
		return
	var modes_table := table as VariantTable
	modes_table.variant_chance = float(test_mode_table.get("chance", modes_table.variant_chance))
	modes_table.from_room = int(test_mode_table.get("from_room", modes_table.from_room))
	var ids: Array = test_mode_table.get("ids", [])
	for i in modes_table.variant_ids.size():
		if i < modes_table.variant_from_rooms.size():
			modes_table.variant_from_rooms[i] = modes_table.from_room
		if not ids.is_empty() and not ids.has(String(modes_table.variant_ids[i])) and i < modes_table.variant_weights.size():
			modes_table.variant_weights[i] = 0.0


func _ready() -> void:
	is_host = multiplayer.is_server()
	_start_msec = Time.get_ticks_msec()
	enemies = NetEnemies.create(self, dm)
	add_child(enemies)
	modes = NetModes.create(self, dm)
	add_child(modes)
	side = NetSide.create(self, dm)
	add_child(side)
	_build_countdown()
	get_tree().node_added.connect(_on_node_added)
	if is_host:
		RunManager.run_gold_changed.connect(_send_pot.unbind(1))
		RunManager.run_crystals_changed.connect(_send_pot.unbind(1))
		multiplayer.peer_disconnected.connect(_on_peer_left)
		dm.slot_rng_captured.connect(_on_slot_rng_captured)
	else:
		GameManager.pause_changed.connect(_on_pause_changed)


func _exit_tree() -> void:
	if dm != null and dm.net == self:
		dm.net = null


## The relay session is gone (host lost): the dungeon runs on alone until the run ends.
func detach() -> void:
	if _detached:
		return
	_detached = true
	if dm != null:
		dm.net = null
		dm.economy.purchase_hook = Callable()
	if enemies != null:
		enemies.detach()
	if modes != null:
		modes.detach()
	if side != null:
		side.detach()
	_show_countdown_text("")
	set_physics_process(false)


func is_detached() -> bool:
	return _detached


## Peers whose dungeon is loaded (host).
func get_ready_peers() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_ready_peers.keys())
	return ids


func get_revive_progress(player: Player) -> float:
	return _revive.get(peer_of(player), 0.0)


# --- Hooks of the DungeonManager ---

## Before a slot (way -1) or a branch way (way >= 0) is prepared. Host: the player count for it
## (the RNG state goes out with DungeonManager.slot_rng_captured). Client: only the slots of the
## dungeon's own _ready (1 and 2, the same everywhere from the seed) and what the host announced; the
## host's RNG state is set here, right before the DungeonManager captures and draws.
func before_prepare_slot(slot: int, _option: BranchOption, way := -1) -> bool:
	if not is_host:
		var key := Vector2i(slot, way)
		if _pending_states.has(key):
			dm.context.rng.state = _pending_states[key]
			_pending_states.erase(key)
			return true
		return way < 0 and slot <= INITIAL_SLOTS
	var mode := GameMode.of(dm)
	var net_players := run.lobby.get_net_players() if run != null and run.lobby != null else null
	if net_players != null and net_players.world == dm and net_players.get_player_count() > 0:
		# A client that left counts no more from the next room on (D-123); downed players do (D-084).
		mode.player_count = clampi(net_players.get_player_count(), 1, GameMode.MAX_PLAYERS)
	return true


## Host: the DungeonManager captured the RNG state of a slot or a branch way (D-135..D-137): it goes
## to every client with the way the group took (a slot behind a branch room built after the choice).
func _on_slot_rng_captured(slot: int, way: int, state: int) -> void:
	var option_index := way
	if way < 0:
		var previous := dm.get_room_at_slot(slot - 1)
		option_index = previous.get_chosen_branch() if previous != null and previous.is_branch_room() else -1
	_send(&"prepare_slot_net", [slot, way, state, option_index, GameMode.of(dm).get_player_count()])


func after_prepare_slot(room: RoomController, way := -1) -> void:
	var slot := room.slot_index
	var key := Vector2i(slot, way)
	if modes != null:
		modes.on_room_prepared(room)
	if is_host:
		if RoomSequence.is_normal_combat(room.room_type):
			room.set_encounter_group(CoopRules.scale_group(room.spawner.encounter_group, GameMode.of(dm).get_player_count()))
		room.completed.connect(_on_room_completed_host)
		if room.is_branch_room():
			room.branch_chosen.connect(_on_branch_chosen_host)
		var niche := SecretNiche.of(room)
		if niche != null:
			niche.opened.connect(func(_niche: SecretNiche) -> void: _send(&"secret_opened", [slot]))
		_signatures[key] = signature_of(room)
		_send(&"room_signature", [slot, way, _signatures[key]])
		return
	room.remote_encounter = true
	var choice := room.get_branch_choice()
	if choice != null:
		# The host's group decides the way (branch_chosen_net).
		choice.set_physics_process(false)
	if _host_states.has(key) and _host_states[key] != dm.get_slot_rng_state(slot, way):
		rng_mismatches += 1
	if _expected_signatures.has(key):
		_check_signature(room, _expected_signatures[key], way)


## Host: the group chose a way of a branch room (D-105, R5). The DungeonManager already made the built
## way room n+1 (or prepared it for the way, sent with prepare_slot_net); the clients take the same way.
func _on_branch_chosen_host(room: RoomController, index: int) -> void:
	if not is_instance_valid(room):
		return
	var slot := room.slot_index
	_send(&"branch_chosen_net", [slot, index])
	var chosen := dm.get_room_at_slot(slot + 1)
	if chosen != null:
		var key := Vector2i(slot + 1, -1)
		_signatures[key] = signature_of(chosen)
		_send(&"room_signature", [slot + 1, -1, _signatures[key]])


## A player entered a prepared room. Host: the group decides (exit rule, D-126); client: never.
func allow_room_entry(room: RoomController) -> bool:
	if not is_host:
		return false
	if _waiting_room != room:
		_waiting_room = room
		_wait_time = 0.0
		_countdown_shown = -1
	return false


func may_open_exit(room: RoomController) -> bool:
	if not is_host:
		return false
	_send(&"exit_opened", [room.slot_index])
	return true


func allow_end_run(reason: RunManager.EndReason) -> bool:
	if is_host:
		_send(&"run_over", [int(reason), RunManager.get_run_gold(), RunManager.get_run_gold_earned(), RunManager.get_run_crystals(), RunManager.get_current_room()])
		# The dungeon's players leave the clients now: nothing of this world is synced any more
		# while everybody looks at the run end and goes back to the village at their own pace.
		var net_players := run.lobby.get_net_players() if run != null and run.lobby != null else null
		if net_players != null and net_players.world == dm:
			net_players.hide_from_peers()
		_ready_peers.clear()
		if enemies != null:
			enemies.detach()
		return true
	if _host_end:
		return true
	match reason:
		RunManager.EndReason.EXIT:
			# The portal ends the run for everybody: the host decides (D-126).
			_send_host(&"request_end", [int(reason)])
			return false
		RunManager.EndReason.ABORT:
			# A client that gives up leaves the room; the others play on (D-123).
			detach()
			run.lobby.leave.call_deferred()
			return true
	return false


## M2: the gate of previous shuts once every living player is inside room - decided at the host only
## (its positions count), the clients shut theirs when it says so (gate_closed).
func close_gate_behind(previous: RoomController, room: RoomController) -> void:
	if not is_host or _detached:
		return
	var closer := GateCloser.close_behind(previous, room)
	if closer != null and not closer.closed.is_connected(_on_gate_closed_host):
		closer.closed.connect(_on_gate_closed_host.bind(room))


func _on_gate_closed_host(_door: Door, room: RoomController) -> void:
	if not is_instance_valid(room):
		return
	gates_closed += 1
	var inside := room.get_arena().grow(-GateCloser.INSIDE_MARGIN)
	for player in dm.get_living_players():
		if not inside.has_point(player.global_position):
			gates_closed_early += 1
	_send(&"gate_closed", [room.slot_index])


## M5 hooks of the DungeonManager (NetSide).
func after_plan_side_way(room: RoomController, next: RoomController, gate: SideGate) -> void:
	if side != null:
		side.after_plan_side_way(room, next, gate)


func allow_side_transit(gate: SideGate) -> bool:
	return side != null and not _detached and side.allow_side_transit(gate)


## M4: what the camera of the local player keeps in view - itself and the standing teammates near
## it (CameraRig.set_targets_provider).
func camera_targets_of(local: Player) -> Array:
	var group := CoopRules.camera_group(local, _all_players())
	max_camera_targets = maxi(max_camera_targets, group.size())
	return group


func on_player_spawned(player: Player) -> void:
	if player.is_local:
		var rig := player.get_node_or_null(^"Camera2D") as CameraRig
		if rig != null:
			rig.set_targets_provider(camera_targets_of.bind(player))
	if is_host:
		player.hurtbox.hit_received.connect(_on_player_hit_host.bind(player))
		player.weapon_controller.weapon_changed.connect(_on_weapons_changed_host.bind(player).unbind(2))
		player.weapon_controller.active_slot_changed.connect(_on_weapons_changed_host.bind(player).unbind(1))
	else:
		player.hurtbox.set_invulnerable(CLIENT_INVULNERABLE, true)
		if player.is_local:
			_local_hp = player.health.get_health()
			player.health.health_changed.connect(_on_local_health_changed)
			player.weapon_controller.weapon_changed.connect(_on_local_weapon_changed)
			player.died.connect(_on_local_downed)
	_assign_managers.call_deferred()


## Every player picks their own upgrade (D-126): the local one here; the host waits for everybody.
func offer_upgrade(title: String) -> void:
	upgrade_rounds += 1
	var slot := dm.get_active_slot()
	var player := dm.context.player
	var choice: UpgradeData = null
	if player != null and is_instance_valid(player) and player.is_alive():
		var offer := dm.upgrade_manager.roll_offer(dm.context.get_owned_weapons(), dm.context.rng)
		if not offer.is_empty():
			var timer := get_tree().create_timer(CoopRules.UPGRADE_TIMEOUT, false)
			timer.timeout.connect(_auto_pick.bind(offer[0]))
			choice = await dm.ui.choose_upgrade(offer, title)
	if _detached or not is_instance_valid(dm):
		return
	if choice != null:
		# Host: its own manager; client: reported to the host through upgrade_acquired.
		dm.upgrade_manager.acquire_upgrade(choice)
	if not is_host:
		_send_host(&"pick_done", [slot])
		return
	_mark_pick(slot, multiplayer.get_unique_id())
	var deadline := Time.get_ticks_msec() + int((CoopRules.UPGRADE_TIMEOUT + 3.0) * 1000.0)
	while not _detached and Time.get_ticks_msec() < deadline and not _all_picked(slot):
		await get_tree().physics_frame
	_show_countdown_text("")


# --- Host: rooms ---

func _physics_process(delta: float) -> void:
	if _detached:
		return
	if is_host:
		_tick_gate(delta)
		_tick_revive(delta)
		_send_progress()
		_state_left -= delta
		if _state_left <= 0.0:
			_state_left = 1.0 / CoopRules.PLAYER_STATE_RATE
			_send_states()
	_update_revive_labels()
	_update_tunnel_tags()


func _tick_gate(delta: float) -> void:
	var room := _waiting_room
	if room == null:
		return
	if not is_instance_valid(room) or room.state != RoomController.State.PREPARED:
		_waiting_room = null
		_show_countdown(0, 0)
		return
	if not _clients_ready():
		_show_countdown_text(Loc.t(&"NET_WAITING_PLAYERS"))
		return
	var living := dm.get_living_players()
	var rect := room.get_arena()
	var present := 0
	for player in living:
		if player.is_protected() or rect.has_point(player.global_position):
			present += 1
	_wait_time += delta
	if CoopRules.should_start_room(living.size(), present, _wait_time):
		_start_room(room)
		return
	var left := ceili(CoopRules.EXIT_COUNTDOWN - _wait_time)
	if left != _countdown_shown:
		_countdown_shown = left
		_show_countdown(room.slot_index, left)
		_send(&"countdown", [room.slot_index, left])


## The wave state of the running fight in the active room, whenever it changes (R3: the clients'
## intro ends with the first one, their arena task bar counts with it).
func _send_progress() -> void:
	if _ready_peers.is_empty():
		return
	var room := dm.get_room_at_slot(dm.get_active_slot())
	if room == null or not room.is_encounter_started() or room.state == RoomController.State.UNLOADED:
		return
	var waves := room.get_wave_progress()
	var state := Vector4i(waves.x, waves.y, room.get_alive_enemy_count(), room.get_wave_alive(waves.x))
	if _progress_sent.get(room.slot_index, Vector4i(-1, -1, -1, -1)) == state:
		return
	_progress_sent[room.slot_index] = state
	progress_events += 1
	_send(&"room_progress", [room.slot_index, state.x, state.y, state.z, state.w])


func _on_node_added(node: Node) -> void:
	if _detached or dm == null or not dm.is_ancestor_of(node):
		return
	if node is SideSegment or node is SideEnemy:
		if side != null:
			side.on_node_added(node)
	elif node is RoomIntro:
		_release_remote_players.call_deferred()
	elif node is RoomObjective and is_host:
		var objective := node as RoomObjective
		objective.changed.connect(_send_objective.bind(objective))
		_send_objective.call_deferred(objective)
	elif node is RoomObjective:
		# Client: the room's own mode attached a fresh goal (intro); the host's state goes on it.
		_reapply_objective.call_deferred(node)


## A room intro locks the players of its machine only (D-133 lock per player): the copies of the
## others follow their own machine's intro (the full version is per save and may differ).
func _release_remote_players() -> void:
	for player in _all_players():
		if not player.is_local:
			player.set_input_locked(RoomIntro.INPUT_LOCK, false)


func _reapply_objective(objective: RoomObjective) -> void:
	if not is_instance_valid(objective) or not (objective.room is RoomController):
		return
	var room := objective.room as RoomController
	var state: Array = _objective_states.get(room.slot_index, [])
	if not state.is_empty() and RoomObjective.of_room(room) == objective and objective.mode_id == StringName(str(state[0])):
		apply_objective_state(room, state)


## Room goals other than the arena (its task bar follows room_progress on the clients).
func _send_objective(objective: RoomObjective) -> void:
	if not is_instance_valid(objective) or objective is ArenaObjective or not (objective.room is RoomController):
		return
	_send(&"objective_state", [(objective.room as RoomController).slot_index, objective_state_of(objective)])


## Everything the task bar shows of a goal, for objective_state.
static func objective_state_of(objective: RoomObjective) -> Array:
	return [String(objective.mode_id), objective.label_text, objective.status_text, int(objective.progress_kind),
			objective.value, objective.max_value, objective.time_left, objective.count_down, objective.danger,
			objective.is_finished(), objective.success, objective.goal_args,
			String(objective.title_key), String(objective.goal_key), String(objective.rule_key), objective.rule_args]


## Client: the host's goal of a room shown in the room's own RoomObjective (created when missing or
## of another mode; an arena goal is left alone). Returns the goal (null for an arena or bad data).
static func apply_objective_state(target_room: Node2D, state: Array) -> RoomObjective:
	if target_room == null or state.size() < 12:
		return null
	var objective := RoomObjective.of_room(target_room)
	if objective is ArenaObjective:
		return null
	var mode := StringName(str(state[0]))
	if objective == null or objective.mode_id != mode:
		objective = RoomObjective.attach(target_room, RoomObjective.create(mode))
	if state[11] is Array:
		objective.goal_args = state[11]
	if state.size() >= 16:
		# Texts of the intro and the bar per mode variant (escort: the chicken's goal).
		objective.title_key = StringName(str(state[12]))
		objective.goal_key = StringName(str(state[13]))
		objective.rule_key = StringName(str(state[14]))
		if state[15] is Array:
			objective.rule_args = state[15]
	# The host decides danger (flame below 30 %): no own guess here.
	objective.auto_danger = false
	match int(state[3]):
		RoomObjective.Progress.COUNT:
			objective.set_count(int(state[4]), int(state[5]))
		RoomObjective.Progress.RATIO:
			objective.set_ratio(float(state[4]) / maxf(0.0001, float(state[5])))
		_:
			objective.clear_progress()
	if float(state[6]) >= 0.0:
		objective.set_time(float(state[6]), bool(state[7]))
	else:
		objective.clear_time()
	objective.set_danger(bool(state[8]))
	objective.set_label(str(state[1]))
	objective.set_status(str(state[2]))
	if bool(state[9]):
		objective.finish(bool(state[10]))
	return objective


## Every client has loaded the dungeon and has its player, or the wait is over (TESTWERT).
func _clients_ready() -> bool:
	if Time.get_ticks_msec() - _start_msec > int(CoopRules.CLIENT_READY_TIMEOUT * 1000.0):
		return true
	var net_players := run.lobby.get_net_players() if run != null and run.lobby != null else null
	for peer in multiplayer.get_peers():
		if not _ready_peers.has(peer):
			return false
		if net_players == null or net_players.get_player_for_peer(peer) == null:
			return false
	return true


func _start_room(room: RoomController) -> void:
	_waiting_room = null
	_wait_time = 0.0
	_countdown_shown = -1
	_show_countdown(0, 0)
	_send(&"countdown", [room.slot_index, 0])
	_gather_players(room)
	_send(&"activate_slot", [room.slot_index, room.room_index])
	rooms_activated += 1
	dm.enter_room(room)
	_share_shop(room)


## Stragglers (and downed players) come along into the room that starts.
func _gather_players(room: RoomController) -> void:
	# M2: past the gate, so it can shut behind them at once (GateCloser counts INSIDE_MARGIN in).
	var inside := room.get_arena().grow(-GateCloser.INSIDE_MARGIN)
	var start := room.get_player_start()
	var index := 0
	for player in _all_players():
		if not inside.has_point(player.global_position):
			player.global_position = gather_point(room, start + WorldController.get_spawn_offset(index), start)
			index += 1


## Where a straggler lands: point if it is walkable floor well inside the room, else the room's start.
static func gather_point(room: RoomController, point: Vector2, start: Vector2) -> Vector2:
	var inside := room.get_arena().grow(-GateCloser.INSIDE_MARGIN)
	if not inside.has_point(point):
		return start
	var tiles := room.get_node_or_null(^"Tiles") as RoomTiles
	if tiles == null:
		return point
	# Tile coordinates are room coordinates (RoomController.get_player_start, get_arena).
	var tile := RoomTiles.local_to_tile(room.to_local(point))
	return point if tiles.is_walkable(tile) and not tiles.is_pit(tile) else start


func _on_room_completed_host(room: RoomController) -> void:
	_send(&"room_completed_net", [room.slot_index])
	# D-084: a cleared room gets every downed player up.
	for player in _all_players():
		if player.is_downed():
			_revive_player(player)


func _share_shop(room: RoomController) -> void:
	if room.room_type != RoomSequence.RoomType.SPECIAL:
		return
	var offers := _find_shop_offers(room)
	if offers.is_empty():
		return
	_shop_offers[room.slot_index] = offers
	var data: Array = []
	for offer: ShopOffer in offers:
		data.append(serialize_offer(offer))
	_send(&"shop_offers", [room.slot_index, data])


func _find_shop_offers(room: RoomController) -> Array:
	for child in room.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with(SHOP_SCRIPT_SUFFIX):
			var offers: Variant = child.get(&"_offers")
			return offers if offers is Array else []
	return []


func _find_shop_content(room: RoomController) -> Node:
	for child in room.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with(SHOP_SCRIPT_SUFFIX):
			return child
	return null


# --- Host: players ---

func _tick_revive(delta: float) -> void:
	var living := dm.get_living_players()
	for player in _all_players():
		var peer := peer_of(player)
		if not player.is_downed():
			_revive.erase(peer)
			continue
		var near := false
		for other in living:
			if other != player and other.global_position.distance_to(player.global_position) <= CoopRules.REVIVE_RADIUS:
				near = true
				break
		var progress := CoopRules.revive_progress(_revive.get(peer, 0.0), near, delta)
		if progress >= CoopRules.REVIVE_TIME:
			_revive.erase(peer)
			_revive_player(player)
		else:
			_revive[peer] = progress


func _revive_player(player: Player) -> void:
	if not player.is_downed():
		return
	player.revive(CoopRules.REVIVE_HEALTH)
	revives += 1
	_bring_to_team(player)
	_send(&"player_revived", [peer_of(player), CoopRules.REVIVE_HEALTH])


## D-143 (proposal for the open co-op point): up again behind a gate that shut since (or in a room
## that is gone) -> at the nearest standing teammate. The position reaches the clients by the sync.
func _bring_to_team(player: Player) -> void:
	var room := dm.get_room_at_slot(dm.get_active_slot())
	if room == null or not is_instance_valid(player):
		return
	var gate := GateCloser.gate_between(dm.get_room_at_slot(room.slot_index - 1))
	var mates: Array[Vector2] = []
	for other in dm.get_living_players():
		if other != player:
			mates.append(other.global_position)
	var point := CoopRules.rejoin_point(player.global_position, room.get_arena(), gate != null and gate.is_open, mates)
	if point != Vector2.INF:
		player.global_position = point
		player.velocity = Vector2.ZERO
		rejoins += 1


func _send_states() -> void:
	if _ready_peers.is_empty():
		return
	var data := PackedFloat32Array()
	for player in _all_players():
		data.append_array([float(peer_of(player)), player.health.get_health(), player.health.get_max_health(),
				player.shield.get_shield(), float(_revive.get(peer_of(player), 0.0))])
	_send(&"player_states", [data])


func _send_pot() -> void:
	_send(&"pot", [RunManager.get_run_gold(), RunManager.get_run_gold_earned(), RunManager.get_run_crystals()])


func _on_player_hit_host(result: DamageResult, damage: DamageData, player: Player) -> void:
	_send(&"player_hit", [peer_of(player), result.shield_damage, result.health_damage, damage.stun_duration,
			damage.blind_duration, player.health.get_health(), player.shield.get_shield()])


func _on_weapons_changed_host(player: Player) -> void:
	_broadcast_loadout.call_deferred(player)


func _broadcast_loadout(player: Player) -> void:
	if not is_instance_valid(player) or _detached:
		return
	var controller := player.weapon_controller
	var weapons: Array = []
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var weapon := controller.get_weapon(slot)
		weapons.append(weapon.resource_path if weapon != null else "")
	_send(&"loadout", [peer_of(player), weapons, controller.get_active_slot(), manager_for(player).get_all_stacks()])


func _on_peer_left(peer: int) -> void:
	_ready_peers.erase(peer)
	_revive.erase(peer)
	if enemies != null:
		enemies.remove_peer(peer)


func _mark_pick(slot: int, peer: int) -> void:
	if not _picks.has(slot):
		_picks[slot] = {}
	_picks[slot][peer] = true


## Every living player of the room has picked (players that left or lie on the floor do not count).
func _all_picked(slot: int) -> bool:
	var picked: Dictionary = _picks.get(slot, {})
	for player in _all_players():
		var peer := peer_of(player)
		if player.is_alive() and not picked.has(peer):
			_show_countdown_text(Loc.t(&"NET_WAITING_UPGRADES"))
			return false
	return true


# --- Client: ready and requests ---

## Host: a client has this dungeon loaded (its profile for it arrived, NetRun._deliver_profile); it
## gets every message from now on, first what it missed.
func on_client_ready(peer: int) -> void:
	if not is_host or _detached or _ready_peers.has(peer):
		return
	_ready_peers[peer] = true
	if enemies != null:
		enemies.add_peer(peer)
	for key in _signatures:
		if _room_for(key) != null:
			room_signature.rpc_id(peer, key.x, key.y, _signatures[key])
	pot.rpc_id(peer, RunManager.get_run_gold(), RunManager.get_run_gold_earned(), RunManager.get_run_crystals())
	for player in _all_players():
		_broadcast_loadout(player)
	if dm.get_active_slot() > 0:
		push_warning("NetDungeon: peer %d became ready after the run started (room %d)." % [peer, dm.get_active_room_index()])


@rpc("any_peer", "call_remote", "reliable")
func pick_done(slot: int) -> void:
	if is_host:
		_mark_pick(slot, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func submit_upgrade(upgrade_id: String) -> void:
	var player := _sender_player()
	if not is_host or player == null:
		return
	var manager := manager_for(player)
	var upgrade := manager.find_upgrade(StringName(upgrade_id))
	if upgrade != null:
		manager.acquire_upgrade(upgrade)
		_broadcast_loadout(player)


@rpc("any_peer", "call_remote", "reliable")
func submit_weapon(slot: int, path: String) -> void:
	var player := _sender_player()
	if not is_host or player == null or path.is_empty() or not ResourceLoader.exists(path):
		return
	var weapon := load(path) as WeaponData
	if weapon != null and player.weapon_controller.get_weapon(slot) != weapon:
		player.weapon_controller.equip_weapon(weapon, slot)


@rpc("any_peer", "call_remote", "reliable")
func request_heal(amount: float) -> void:
	var player := _sender_player()
	if is_host and player != null and player.is_alive():
		player.health.heal(clampf(amount, 0.0, player.health.get_max_health()))


@rpc("any_peer", "call_remote", "reliable")
func submit_protected(protected: bool) -> void:
	var player := _sender_player()
	if is_host and player != null:
		player.set_protected(REMOTE_MENU, protected)


@rpc("any_peer", "call_remote", "reliable")
func request_end(reason: int) -> void:
	if is_host and _sender_player() != null and reason == RunManager.EndReason.EXIT:
		dm.end_run(RunManager.EndReason.EXIT)


@rpc("any_peer", "call_remote", "reliable")
func request_purchase(room_slot: int, index: int, weapon_slot: int) -> void:
	var player := _sender_player()
	if not is_host or player == null:
		return
	var offers: Array = _shop_offers.get(room_slot, [])
	var ok := false
	if index >= 0 and index < offers.size():
		ok = dm.economy.purchase(offers[index], player, manager_for(player), weapon_slot)
	if ok:
		_send(&"offer_sold", [room_slot, index])
	purchase_result.rpc_id(multiplayer.get_remote_sender_id(), room_slot, index, ok)


# --- Client: what the host sends ---

## The host's dungeon RNG state of a slot (way -1) or a built branch way (way >= 0), the way the
## group took (option_index, for a slot behind a branch room built after the choice) and the player
## count. A slot is built at once; the ways of a branch room once the states of all of them arrived.
@rpc("authority", "call_remote", "reliable")
func prepare_slot_net(slot: int, way: int, rng_state: int, option_index: int, count: int) -> void:
	if is_host or _detached:
		return
	GameMode.of(dm).player_count = clampi(count, 1, GameMode.MAX_PLAYERS)
	var key := Vector2i(slot, way)
	_host_states[key] = rng_state
	var previous := dm.get_room_at_slot(slot - 1)
	if way >= 0:
		_pending_states[key] = rng_state
		if previous == null or not previous.is_branch_room():
			push_warning("NetDungeon: branch way %d of slot %d without its branch room." % [way, slot])
			return
		for i in previous.branch_options.size():
			if not _pending_states.has(Vector2i(slot, i)):
				return
		dm.prepare_branch_ways(previous)
		return
	if dm.get_room_at_slot(slot) != null:
		return
	var option: BranchOption = null
	if option_index >= 0 and previous != null and option_index < previous.branch_options.size():
		option = previous.branch_options[option_index]
	_pending_states[key] = rng_state
	if option != null and previous.get_chosen_branch() < 0:
		# The choice prepares room n+1 for the way (DungeonManager._on_branch_chosen).
		previous.choose_branch(option_index)
	if dm.get_room_at_slot(slot) == null:
		dm.prepare_slot(slot, option)
	_pending_states.erase(key)


## The host's group took a way of a branch room: the built way becomes room n+1 here too.
@rpc("authority", "call_remote", "reliable")
func branch_chosen_net(slot: int, index: int) -> void:
	var room := dm.get_room_at_slot(slot)
	if is_host or _detached or room == null:
		return
	if room.get_chosen_branch() < 0 and room.choose_branch(index):
		branch_choices += 1
	var key := Vector2i(slot + 1, -1)
	var chosen := dm.get_room_at_slot(slot + 1)
	if chosen != null and _expected_signatures.has(key):
		_check_signature(chosen, _expected_signatures[key], -1)


@rpc("authority", "call_remote", "reliable")
func room_signature(slot: int, way: int, signature: String) -> void:
	if is_host:
		return
	var key := Vector2i(slot, way)
	_expected_signatures[key] = signature
	var room := _room_for(key)
	if room != null:
		_check_signature(room, signature, way)


@rpc("authority", "call_remote", "reliable")
func activate_slot(slot: int, room_number: int) -> void:
	if is_host or _detached:
		return
	var room := dm.get_room_at_slot(slot)
	if room == null:
		push_warning("NetDungeon: slot %d to activate is not prepared." % slot)
		return
	rooms_activated += 1
	dm.enter_room(room, false)
	RunManager.sync_room(room_number)


@rpc("authority", "call_remote", "reliable")
func room_completed_net(slot: int) -> void:
	var room := dm.get_room_at_slot(slot)
	if is_host or room == null:
		return
	# The room's heal is the host's too: it comes with the next vitals, not as a heal request.
	_syncing = true
	room.complete_remotely()
	_syncing = false
	# A mode's finish() may book crystals here for a moment: the pot is the host's.
	if _last_pot.x >= 0:
		RunManager.sync_from_host(_last_pot.x, _last_pot.y, _last_pot.z)


## The host's fight in a room: wave of total, living enemies, living enemies of that wave.
@rpc("authority", "call_remote", "reliable")
func room_progress(slot: int, wave: int, total: int, alive: int, wave_alive: int) -> void:
	var room := dm.get_room_at_slot(slot)
	if is_host or _detached or room == null:
		return
	progress_events += 1
	room.apply_remote_progress(wave, total, alive, wave_alive)


@rpc("authority", "call_remote", "reliable")
func objective_state(slot: int, state: Array) -> void:
	var room := dm.get_room_at_slot(slot)
	if is_host or _detached or room == null:
		return
	_objective_states[slot] = state
	if apply_objective_state(room, state) != null:
		objective_events += 1


@rpc("authority", "call_remote", "reliable")
func secret_opened(slot: int) -> void:
	var niche := SecretNiche.of(dm.get_room_at_slot(slot))
	if not is_host and niche != null:
		niche.break_open()


## The host shut the gate behind the room of slot (all living players inside it, M2).
@rpc("authority", "call_remote", "reliable")
func gate_closed(slot: int) -> void:
	if is_host or _detached:
		return
	var gate := GateCloser.gate_between(dm.get_room_at_slot(slot - 1))
	if gate != null and gate.is_open:
		gate.close()
		gates_closed += 1


@rpc("authority", "call_remote", "reliable")
func exit_opened(slot: int) -> void:
	var room := dm.get_room_at_slot(slot)
	if not is_host and room != null:
		room.open_exit()


@rpc("authority", "call_remote", "reliable")
func countdown(slot: int, seconds_left: int) -> void:
	if not is_host:
		_show_countdown(slot, seconds_left)


@rpc("authority", "call_remote", "reliable")
func pot(gold: int, earned: int, crystals: int) -> void:
	if not is_host:
		_last_pot = Vector3i(gold, earned, crystals)
		RunManager.sync_from_host(gold, earned, crystals)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func player_states(data: PackedFloat32Array) -> void:
	if is_host or _detached:
		return
	for i in range(0, data.size() - STATE_FIELDS + 1, STATE_FIELDS):
		var peer := int(data[i])
		var player := _player_of(peer)
		_revive[peer] = data[i + 4]
		if player != null:
			_apply_vitals(player, data[i + 1], data[i + 2], data[i + 3])


@rpc("authority", "call_remote", "reliable")
func player_hit(peer: int, shield_damage: float, health_damage: float, stun: float, blind: float, health: float, shield: float) -> void:
	var player := _player_of(peer)
	if is_host or player == null or _detached:
		return
	var result := DamageResult.new()
	result.shield_damage = shield_damage
	result.health_damage = health_damage
	result.amount = shield_damage + health_damage
	result.killed = health <= 0.0
	var damage := DamageData.new()
	damage.stun_duration = stun
	damage.blind_duration = blind
	if not player.is_downed():
		player.hurtbox.hit_received.emit(result, damage)
	if player.is_local:
		DamageNumber.spawn_for_result(player.get_parent(), player.global_position + Vector2(0, -56), result)
	_apply_vitals(player, health, player.health.get_max_health(), shield)


@rpc("authority", "call_remote", "reliable")
func player_revived(peer: int, health: float) -> void:
	var player := _player_of(peer)
	if is_host or player == null:
		return
	_revive.erase(peer)
	_syncing = true
	player.revive(health)
	if player.is_local:
		_local_hp = player.health.get_health()
		_downed_announced = false
	_syncing = false


@rpc("authority", "call_remote", "reliable")
func loadout(peer: int, weapons: Array, active_slot: int, stacks: Dictionary) -> void:
	var player := _player_of(peer)
	if is_host or player == null:
		return
	_applying_loadout = true
	var manager := manager_for(player)
	var before := manager.get_all_stacks()
	manager.set_all_stacks(stacks)
	var controller := player.weapon_controller
	for slot in mini(weapons.size(), WeaponController.MAX_WEAPON_SLOTS):
		var path := str(weapons[slot])
		var current := controller.get_weapon(slot)
		if path.is_empty() or (current != null and current.resource_path == path) or not ResourceLoader.exists(path):
			continue
		controller.equip_weapon(load(path) as WeaponData, slot)
	if not player.is_local and controller.get_active_slot() != active_slot and controller.get_weapon(active_slot) != null:
		controller.switch_weapon()
	if player.is_local:
		# New stacks from the host (shop): the usual signals for HUD and statistics.
		for id: Variant in stacks:
			var count := int(stacks[id])
			if count > int(before.get(id, 0)):
				var upgrade := manager.find_upgrade(StringName(str(id)))
				if upgrade != null:
					manager.upgrade_acquired.emit(upgrade, count)
					EventBus.upgrade_acquired.emit(upgrade.id, count)
	_applying_loadout = false


@rpc("authority", "call_remote", "reliable")
func shop_offers(slot: int, data: Array) -> void:
	if is_host:
		return
	var offers: Array[ShopOffer] = []
	for entry: Variant in data:
		if not (entry is Array) or (entry as Array).size() < 6:
			continue
		var offer := ShopOffer.new()
		offer.kind = int(entry[0]) as ShopOffer.Kind
		offer.upgrade = dm.upgrade_manager.find_upgrade(StringName(str(entry[1]))) if not str(entry[1]).is_empty() else null
		var path := str(entry[2])
		offer.weapon = load(path) as WeaponData if not path.is_empty() and ResourceLoader.exists(path) else null
		offer.price = int(entry[3])
		offer.amount = float(entry[4])
		offer.sold = bool(entry[5])
		offers.append(offer)
	_shop_offers[slot] = offers
	var room := dm.get_room_at_slot(slot)
	var content := _find_shop_content(room) if room != null else null
	if content != null:
		content.set(&"_offers", offers)
	dm.economy.purchase_hook = _client_purchase


@rpc("authority", "call_remote", "reliable")
func offer_sold(slot: int, index: int) -> void:
	if is_host:
		return
	var offers: Array = _shop_offers.get(slot, [])
	if index >= 0 and index < offers.size():
		(offers[index] as ShopOffer).sold = true
	_refresh_shop()


@rpc("authority", "call_remote", "reliable")
func purchase_result(_slot: int, _index: int, ok: bool) -> void:
	if not ok:
		Sfx.play_ui(self, &"ui_error")
	_refresh_shop.call_deferred()


@rpc("authority", "call_remote", "reliable")
func run_over(reason: int, gold: int, earned: int, crystals: int, room_number: int) -> void:
	if is_host or _detached:
		return
	RunManager.sync_from_host(gold, earned, crystals)
	RunManager.sync_room(room_number)
	_host_end = true
	_show_countdown_text("")
	dm.end_run(reason as RunManager.EndReason)


# --- Client: local reports ---

func _client_purchase(offer: ShopOffer, player: Player, upgrades: UpgradeManager, weapon_slot: int) -> bool:
	if not dm.economy.can_purchase(offer, player, upgrades, weapon_slot):
		return false
	for slot in _shop_offers:
		var index: int = (_shop_offers[slot] as Array).find(offer)
		if index >= 0:
			_send_host(&"request_purchase", [slot, index, weapon_slot])
			return false
	return false


func _refresh_shop() -> void:
	if dm == null or dm.ui == null:
		return
	for child in dm.ui.get_children():
		if child is Modal and child.has_meta(&"refresh"):
			(child.get_meta(&"refresh") as Callable).call()


func _on_local_health_changed(current: float, _maximum: float) -> void:
	if _syncing or _detached:
		_local_hp = current
		return
	if current > _local_hp + 0.01 and dm.context.player != null and dm.context.player.is_alive():
		# A heal at this machine (fountain, campfire): the host's copy heals.
		_send_host(&"request_heal", [current - _local_hp])
	_local_hp = current


func _on_local_weapon_changed(slot: int, weapon: WeaponData) -> void:
	if _applying_loadout or _detached or weapon == null:
		return
	_send_host(&"submit_weapon", [slot, weapon.resource_path])


func _on_local_upgrade(upgrade: UpgradeData, _stacks: int) -> void:
	if _applying_loadout or _detached or is_host:
		return
	_send_host(&"submit_upgrade", [String(upgrade.id)])


func _on_pause_changed(menus_open: bool) -> void:
	if not _detached:
		_send_host(&"submit_protected", [menus_open])


func _on_local_downed() -> void:
	if _downed_announced or _detached:
		return
	_downed_announced = true
	if dm.get_living_players().size() > 0:
		dm.ui.show_banner(Loc.t(&"NET_DOWNED_TITLE"), Loc.t(&"NET_DOWNED_SUB"), DOWNED_COLOR)


func _check_signature(room: RoomController, expected: String, way := -1) -> void:
	var own := signature_of(room)
	signatures_checked += 1
	if way >= 0:
		way_signatures_checked += 1
	if own != expected:
		signature_mismatches += 1
		push_warning("NetDungeon: slot %d (way %d) differs from the host.\n  host:   %s\n  client: %s" % [room.slot_index, way, expected, own])


## The live room of a slot (way -1) or a built branch way (way >= 0), null if not there (any more).
func _room_for(key: Vector2i) -> RoomController:
	if key.y < 0:
		return dm.get_room_at_slot(key.x)
	var ways := dm.get_branch_ways()
	if key.y < ways.size() and is_instance_valid(ways[key.y]) and ways[key.y].slot_index == key.x:
		return ways[key.y]
	return null


func _apply_vitals(player: Player, health: float, maximum: float, shield: float) -> void:
	_syncing = true
	if maximum > 0.0 and not is_equal_approx(player.health.max_health, maximum):
		player.health.max_health = maximum
	if health <= 0.0:
		if not player.health.is_dead():
			player.health.take_damage(player.health.get_health() + 1.0)
	elif player.health.is_dead():
		player.revive(health)
	else:
		player.health.set_current(health)
	player.shield.set_current(shield)
	if player.is_local:
		_local_hp = player.health.get_health()
	_syncing = false


# --- Shared ---

## Upgrades of a player: the dungeon's own manager for this machine's primary player, an own one
## for everybody else (per player, D-081).
func manager_for(player: Player) -> UpgradeManager:
	if player == null or player == dm.context.player:
		return dm.upgrade_manager
	var key := player.get_instance_id()
	if not _managers.has(key):
		var manager := UpgradeManager.new()
		manager.name = "Upgrades%s" % player.name
		manager.upgrade_pool = dm.upgrade_manager.upgrade_pool
		manager.player = player
		add_child(manager)
		_managers[key] = manager
		if is_host:
			manager.upgrade_acquired.connect(func(_upgrade: UpgradeData, _stacks: int) -> void: _broadcast_loadout(player))
			var effects := UpgradeEffects.new()
			effects.name = "Effects%s" % player.name
			effects.upgrade_manager = manager
			effects.player = player
			effects.only_own_hits = true
			add_child(effects)
			_effects[key] = effects
	return _managers[key]


func _assign_managers() -> void:
	if _detached or dm == null:
		return
	dm.upgrade_effects.only_own_hits = true
	if not dm.upgrade_manager.upgrade_acquired.is_connected(_on_primary_upgrade):
		dm.upgrade_manager.upgrade_acquired.connect(_on_primary_upgrade)
	for player in _all_players():
		player.weapon_controller.upgrades = manager_for(player)


func _on_primary_upgrade(upgrade: UpgradeData, stacks: int) -> void:
	if is_host:
		_broadcast_loadout(dm.context.player)
	else:
		_on_local_upgrade(upgrade, stacks)


func _auto_pick(upgrade: UpgradeData) -> void:
	if dm == null or dm.ui == null:
		return
	for child in dm.ui.get_children():
		var modal := child as Modal
		if modal != null and modal.pause_reason == GameManager.PAUSE_UPGRADE_CHOICE:
			modal.finish(upgrade)


## M2 tunnels (PassageCover): the rock over a passage lies above the characters, so every player
## in it - local or remote - is hidden on every machine; his name tag (z 30) goes with him. The
## revive label stays (a downed mate must be found). Runs on host and clients.
func _update_tunnel_tags() -> void:
	var views := _passage_views()
	for player in _all_players():
		NetPlayers.set_tag_hidden(player, CoopRules.in_passage(player.global_position, views))


## Is node (a player) in a passage under the rock right now? Tools and tests.
func in_tunnel(node: Node2D) -> bool:
	return node != null and is_instance_valid(node) and CoopRules.in_passage(node.global_position, _passage_views())


## Door views with rock over their passage at the exits of the active room and the room before it
## (every branch exit included): the only passages a player can stand in.
func _passage_views() -> Array[DoorView]:
	var views: Array[DoorView] = []
	if dm == null or not is_instance_valid(dm):
		return views
	var slot := dm.get_active_slot()
	for at in [slot - 1, slot]:
		var room := dm.get_room_at_slot(at)
		if room == null or not is_instance_valid(room):
			continue
		for door in room.get_exit_doors():
			if is_instance_valid(door) and door.view != null and not door.view.get_lintel().is_empty():
				views.append(door.view)
	return views


func _all_players() -> Array[Player]:
	var result: Array[Player] = []
	var controller := run.lobby.get_world_controller() if run != null and run.lobby != null else null
	if controller == null:
		return result
	for player in controller.players:
		if is_instance_valid(player) and player.is_inside_tree():
			result.append(player)
	return result


static func peer_of(player: Node) -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var state := player.get_node_or_null(NodePath(NetPlayerState.NODE_NAME)) as NetPlayerState
	return state.peer_id if state != null else 0


func _player_of(peer: int) -> Player:
	var net_players := run.lobby.get_net_players() if run != null and run.lobby != null else null
	return net_players.get_player_for_peer(peer) if net_players != null else null


func _sender_player() -> Player:
	return _player_of(multiplayer.get_remote_sender_id())


func _has_session() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Host -> every client whose dungeon is loaded.
func _send(method: StringName, args: Array = []) -> void:
	if not is_host or _detached or not _has_session():
		return
	for peer in _ready_peers:
		callv(&"rpc_id", [peer, method] + args)


## Host -> every ready client, an RPC of another node of the shared run (NetModes).
func send_to_clients(node: Node, method: StringName, args: Array = []) -> void:
	if not is_host or _detached or not _has_session():
		return
	for peer in _ready_peers:
		node.callv(&"rpc_id", [peer, method] + args)


## Client -> host, an RPC of another node of the shared run (NetModes).
func send_to_host(node: Node, method: StringName, args: Array = []) -> void:
	if is_host or _detached or _host_end or not RunManager.is_run_active() or not _has_session():
		return
	node.callv(&"rpc_id", [RelayProtocol.HOST_PEER_ID, method] + args)


func _send_host(method: StringName, args: Array = []) -> void:
	# After the run end the host may already be back in the village.
	if is_host or _detached or _host_end or not RunManager.is_run_active() or not _has_session():
		return
	callv(&"rpc_id", [RelayProtocol.HOST_PEER_ID, method] + args)


# --- Presentation ---

func _build_countdown() -> void:
	_countdown_layer = CanvasLayer.new()
	_countdown_layer.name = "NetCountdown"
	_countdown_layer.layer = 20
	add_child(_countdown_layer)
	_countdown_label = UiKit.text_label("", UiKit.SIZE_VALUE, COUNTDOWN_COLOR, true)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_countdown_label.position.y = UiKit.px(34.0)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.visible = false
	_countdown_layer.add_child(_countdown_label)


func _show_countdown(_slot: int, seconds_left: int) -> void:
	_show_countdown_text(Loc.t(&"NET_EXIT_COUNTDOWN", [seconds_left]) if seconds_left > 0 else "")


func _show_countdown_text(text: String) -> void:
	if _countdown_label == null:
		return
	_countdown_label.text = text
	_countdown_label.visible = not text.is_empty()
	if not text.is_empty():
		_countdown_label.reset_size()
		_countdown_label.position.x = -_countdown_label.size.x * 0.5


## "Revive 40 %" over every downed player.
func _update_revive_labels() -> void:
	for player in _all_players():
		var key := player.get_instance_id()
		var label: Label = _revive_labels.get(key, null)
		if not player.is_downed():
			if label != null and is_instance_valid(label):
				label.visible = false
			continue
		if label == null or not is_instance_valid(label):
			label = UiKit.text_label("", UiKit.SIZE_BODY, DOWNED_COLOR, true)
			label.name = "ReviveLabel"
			label.z_index = 40
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			player.add_child(label)
			_revive_labels[key] = label
		var progress := float(_revive.get(peer_of(player), 0.0))
		label.text = Loc.t(&"NET_REVIVE", [roundi(100.0 * progress / CoopRules.REVIVE_TIME)]) if progress > 0.0 else Loc.t(&"NET_DOWNED")
		label.visible = true
		label.reset_size()
		label.position = Vector2(-label.size.x * 0.5, -78.0)
