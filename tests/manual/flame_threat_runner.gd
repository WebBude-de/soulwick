extends Node
## Body of tests/manual/flame_threat.gd (loaded after the first frame, when the autoloads exist).

const PLAYER_SCENE := "res://player/player.tscn"
const SAVE_PATH := "user://flame_threat_save.cfg"
const COMBAT_DIR := "res://dungeon/rooms/combat/"

var _runs := 3
var _room_index := 6
var _template := "flamme_schrein_crypt"
var _players := 1
## defender=1: the players stand beside the flame and hit the nearest enemy out of its source within
## MELEE_REACH every HIT_TIME s for dps * HIT_TIME (an attentive sword player who guards the flame and
## never leaves it); 0: they stand far away idle.
var _defender := false
var _dps := 15.0
## guard=<px>: how far beside the flame the defenders stand.
var _guard := 64.0
const HIT_TIME := 0.75
const MELEE_REACH := 110.0
var _lowest_sum := 0.0


## The session owner (WorldController stand-in): GameMode.of answers its game_mode (co-op runs).
class ModeOwner:
	extends Node
	var game_mode: GameMode = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"runs":
				_runs = int(parts[1])
			"room":
				_room_index = int(parts[1])
			"template":
				_template = parts[1]
			"players":
				_players = int(parts[1])
			"defender":
				_defender = parts[1] == "1"
			"guard":
				_guard = float(parts[1])
			"dps":
				_dps = float(parts[1])
	_main.call_deferred()


func _main() -> void:
	SaveManager.save_path = SAVE_PATH
	var lost := 0
	for run in _runs:
		var result: Dictionary = await _play(run)
		if result["out_at"] >= 0.0:
			lost += 1
		_lowest_sum += result["lowest"]
		print("FLAME run %d %s room %d players %d defender %s: lowest %.0f %%, out at %s, raiders %d of %d enemies, flame hits %d %s" % [
				run, _template, _room_index, _players, _defender, result["lowest"] * 100.0,
				("%.1f s" % result["out_at"]) if result["out_at"] >= 0.0 else "-",
				result["raiders"], result["enemies"], result["hits"], result["types"]])
	print("FLAME summary %s room %d players %d defender %s: flame lost in %d of %d runs, lowest mean %.0f %%" % [_template, _room_index, _players, _defender, lost, _runs, _lowest_sum / maxi(1, _runs) * 100.0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	get_tree().quit()


func _play(run: int) -> Dictionary:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	var room := (load(COMBAT_DIR + _template + ".tscn") as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 1000 + run
	room.setup(_room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	get_tree().root.add_child(room)
	if _players > 1:
		var owner := ModeOwner.new()
		owner.game_mode = GameMode.quick(_players)
		owner.add_to_group(GameMode.OWNER_GROUP)
		room.add_child(owner)
		room.spawner.encounter_group = CoopRules.scale_group(room.spawner.encounter_group, _players)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + run
	RoomVariants.attach(room, VariantTable.pick_for(&"flame"), rng)
	var mode := CombatVariant.of(room) as FlameMode
	if mode == null:
		push_error("flame_threat: %s cannot host the flame" % _template)
		get_tree().quit(1)
		return {}
	var spots := [room.tiles.get_entrance_inside_tile(), room.tiles.get_exit_inside_tile()]
	var players: Array[Player] = []
	for i in _players:
		var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
		get_tree().root.add_child(player)
		player.global_position = room.to_global(RoomTiles.tile_center(spots[i % spots.size()])) - Player.FEET_OFFSET
		if _defender:
			var side := Vector2(_guard * (1.0 if i % 2 == 0 else -1.0), _guard * 0.5)
			player.global_position = mode.flame.global_position + side
		player.health.reset(99999.0)
		players.append(player)
	context.player = players[0]
	await get_tree().physics_frame
	room.start_encounter()
	var flame := mode.flame
	var result := {"lowest": 1.0, "out_at": -1.0, "raiders": 0, "enemies": 0, "hits": 0, "types": {}}
	flame.damaged.connect(func(_f: SoulFlame, _r: DamageResult) -> void: result["hits"] += 1)
	flame.hurtbox.hit_received.connect(func(_r: DamageResult, damage: DamageData) -> void:
		var source := damage.source as Enemy if damage != null and is_instance_valid(damage.source) else null
		var kind := "hit_" + (String(source.data.id) if source != null and source.data != null else "?")
		result["types"][kind] = int(result["types"].get(kind, 0)) + 1)
	var seen: Dictionary = {}
	var time := 0.0
	var cooldowns: Array[float] = []
	for player in players:
		cooldowns.append(HIT_TIME)
	while time < FlameRules.DURATION + 1.0:
		await get_tree().physics_frame
		time += 1.0 / 60.0
		if _defender:
			for i in players.size():
				cooldowns[i] -= 1.0 / 60.0
				if cooldowns[i] <= 0.0 and _defend(players[i], room):
					cooldowns[i] = HIT_TIME
		for child in room.enemy_container.get_children():
			if child is Enemy and not seen.has(child):
				seen[child] = true
				result["enemies"] += 1
				if EnemyDecoy.has_decoy(child):
					result["raiders"] += 1
				var kind := String((child as Enemy).data.id) if (child as Enemy).data != null else "?"
				result["types"][kind] = int(result["types"].get(kind, 0)) + 1
		if is_instance_valid(flame):
			result["lowest"] = minf(result["lowest"], flame.get_health_ratio())
			if not flame.is_alive() and result["out_at"] < 0.0:
				result["out_at"] = time
	for player in players:
		player.queue_free()
	room.queue_free()
	await get_tree().process_frame
	return result


## The defender's hit: the nearest enemy out of its source within MELEE_REACH. True if one was hit.
func _defend(player: Player, room: RoomController) -> bool:
	var best: Enemy = null
	var best_distance := MELEE_REACH
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy == null or enemy.is_dead() or enemy.is_hidden_in_source() or enemy.is_emerging():
			continue
		var distance := enemy.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	if best == null:
		return false
	best.health.take_damage(_dps * HIT_TIME)
	return true
