class_name NetEnemies
extends Node
## Enemies, enemy projectiles, pickups and crates of a shared run (MP3, D-126), child "NetEnemies"
## of the NetDungeon. Host-authoritative:
## - Host: every Enemy that enters the dungeon gets a net id, the D-084 HP factor for the session's
##   player count and goes out as enemy_spawned (scene, data id, champion/elite/tier, HP). Hits
##   (EventBus.enemy_damaged) go out as enemy_hit, deaths as enemy_died; positions, animation and
##   telegraphs as snapshots (15/s, unreliable). Enemy projectiles are sent once as an event (start,
##   direction, speed, look; MULTIPLAYER.md §5), area blasts of living enemies (slams, eruptions,
##   with their warning circle) likewise, coins and hearts as pickup events, broken crates as
##   breakable_broken. Bosses: the client plays the boss intro itself (own player held still).
## - Client: puppets of the host's enemies: the real enemy scene without AI (physics off), drawn
##   from the snapshots (smoothed positions, animation, telegraph circle and line). Hit flashes,
##   sparks and sounds play locally from the events; damage numbers only for the own hits. A puppet
##   dies with the normal death animation (no gold, no split children: those come from the host).
##   Hurtboxes on the enemy layer (enemies, crates) are off on a client: its own attacks only show,
##   the host's copy of the player deals the damage. Enemies and pickups the client would create on
##   its own (crates, variants) are removed: everything comes from the host.
## - Spawn sources (R2, D-132): the host's sources warn, open and rest (phase changes, polled in the
##   active room) and its enemies come out of them (Enemy.emerge_started); the client plays the
##   same phases on its own SpawnSource nodes (same names, built from the same plan) and lets the
##   puppet emerge with the time that is left. Slime hops show their landing marker (snapshot).
## - Snapshots (online test 16.10.2026): stamped with the host's clock; only enemies whose encoding
##   changed since the last snapshot travel, every FULL_SNAPSHOT_EVERY-th snapshot carries all of
##   them (a lost unreliable snapshot or a late joiner is caught up). The client draws every puppet
##   NetInterpolator.DELAY_MSEC in the host's past between two snapshots (online/net_interpolator.gd)
##   instead of pulling it towards the newest one: no stepping, no jumps when TCP delivers late.
##   Further off than SNAP_DISTANCE from the newest position = jump. RelayPeer.legacy_sync = as before.

const NODE_NAME := &"NetEnemies"
const META_NET := &"net_id"
## Animations a snapshot can name (index), anything else counts as "keep playing".
const ANIMATIONS: Array[StringName] = [&"idle", &"walk", &"attack", &"attack2", &"summon", &"death", &"hurt", &"fall", &"special", &"roar"]
const FLAG_FLIP := 1
const FLAG_CIRCLE := 2
const FLAG_LINE := 4
const FLAG_PLAYING := 8
const FLAG_HOP := 16
## Floats per enemy in a snapshot: id, x, y, animation, flags, alpha, speed scale, sprite y, hp.
const SNAPSHOT_FIELDS := 9
const CIRCLE_FIELDS := 7
const LINE_FIELDS := 6
## Hop landing marker: x, y, radius, scale.
const HOP_FIELDS := 4
const HOP_MARKER_NAME := ^"HopMarker"
## Hurtbox reason of a puppet: only the host's enemy takes hits.
const PUPPET_INVULNERABLE := &"net_puppet"
## Client smoothing (TESTWERTE): jump when further off, else close this share per second.
const SNAP_DISTANCE := 120.0
const FOLLOW_RATE := 14.0
## TESTWERT: every n-th snapshot carries every enemy.
const FULL_SNAPSHOT_EVERY := 8
## Preloaded: works before the global class cache knows NetInterpolator (new file).
const Interpolator := preload("res://online/net_interpolator.gd")
const HIT_SPARK_TEXTURE: Texture2D = preload("res://art/effects/hit_spark_3f.png")
const DATA_DIR := "res://enemies/data/"
const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"

var net: NetDungeon = null
var dm: DungeonManager = null
var is_host := false

## Test counters: enemies registered (host) or puppets created (client), and their deaths.
var spawned_count := 0
var died_count := 0
var projectile_count := 0
var pickup_count := 0
## Emergences sent (host) or played on puppets (client), spawn source phases sent or played.
var emerge_count := 0
var source_events := 0

var _detached := false
var _ready_peers: Dictionary[int, bool] = {}
var _next_id := 1
## Host: live enemies, projectiles and pickups by net id.
var _enemies: Dictionary[int, Enemy] = {}
var _projectiles: Dictionary[int, Node] = {}
var _pickups: Dictionary[int, Node] = {}
var _snapshot_left := 0.0
## Host: begin_emerge of enemies (instance id -> [msec, wait, rise time, style]), and the last phase
## of every spawn source of the active room (instance id -> SpawnSource.Phase).
var _emerges: Dictionary[int, Array] = {}
var _source_phases: Dictionary[int, int] = {}
var _sources_slot := -1
## Host: the last encoding sent per enemy (delta snapshots).
var _full_left := 0
var _last_encoded: Dictionary[int, PackedFloat32Array] = {}
## Test counters: enemy entries sent (host) or applied (client).
var snapshot_entries := 0
## Client: puppets by host id and where the host last saw them.
var _puppets: Dictionary[int, Enemy] = {}
var _targets: Dictionary[int, Vector2] = {}
## Client: positions of the puppets over the host's time (drawn a little in the past).
var interpolator: Interpolator = Interpolator.new()
var _client_projectiles: Dictionary[int, Node] = {}
var _client_pickups: Dictionary[int, Node] = {}
static var _data_by_id: Dictionary = {}


static func create(owner_net: NetDungeon, dungeon: DungeonManager) -> NetEnemies:
	var node := NetEnemies.new()
	node.name = NODE_NAME
	node.net = owner_net
	node.dm = dungeon
	return node


## EnemyData by id from enemies/data (the host sends ids, champions carry modified copies).
static func data_for(id: StringName) -> EnemyData:
	if _data_by_id.is_empty():
		var dir := DirAccess.open(DATA_DIR)
		if dir != null:
			for file in dir.get_files():
				var name := file.trim_suffix(".remap")
				if not name.ends_with(".tres"):
					continue
				var data := load(DATA_DIR + name) as EnemyData
				if data != null and data.id != &"":
					_data_by_id[data.id] = data
	return _data_by_id.get(id, null)


func _ready() -> void:
	is_host = multiplayer.is_server()
	get_tree().node_added.connect(_on_node_added)
	if is_host:
		EventBus.enemy_damaged.connect(_on_enemy_damaged)


func detach() -> void:
	_detached = true
	set_physics_process(false)
	set_process(false)


func add_peer(peer: int) -> void:
	_ready_peers[peer] = true
	# Catch-up: enemies that already live (a client that loaded late).
	for id in _enemies:
		var enemy := _enemies[id]
		if is_instance_valid(enemy) and not enemy.is_dead():
			callv(&"rpc_id", [peer, &"enemy_spawned"] + _spawn_args(id, enemy))


func remove_peer(peer: int) -> void:
	_ready_peers.erase(peer)


func get_puppet(id: int) -> Enemy:
	var enemy: Enemy = _puppets.get(id, null)
	return enemy if enemy != null and is_instance_valid(enemy) else null


## Living enemies this machine knows: the host's real ones or the client's puppets.
func get_live_count() -> int:
	var count := 0
	for enemy: Variant in (_enemies.values() if is_host else _puppets.values()):
		if is_instance_valid(enemy) and not (enemy as Enemy).is_dead():
			count += 1
	return count


func _on_node_added(node: Node) -> void:
	if _detached or dm == null or not dm.is_ancestor_of(node):
		return
	if is_host:
		if node is Enemy:
			# Connected now: the source starts the emergence in this frame, before the registration.
			if not (node as Enemy).emerge_started.is_connected(_on_emerge_started):
				(node as Enemy).emerge_started.connect(_on_emerge_started)
			_register_enemy.call_deferred(node)
		elif node is Projectile:
			_register_projectile(node as Projectile)
		elif node is GoldPickup:
			_register_pickup.call_deferred(node)
		elif node is Breakable:
			_watch_breakable(node as Breakable)
		elif node is Blast:
			_register_blast.call_deferred(node)
		return
	# Client: the host decides every hit on the enemy layer, every enemy and every pickup.
	if node is Hurtbox and ((node as Hurtbox).collision_layer & PhysicsLayers.ENEMY_HURTBOX) != 0:
		node.set_deferred(&"monitorable", false)
	elif (node is Enemy or node is GoldPickup) and not node.has_meta(META_NET):
		node.queue_free.call_deferred()


# --- Host ---

func _register_enemy(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree() or enemy.has_meta(META_NET) or enemy.data == null:
		return
	var id := _next_id
	_next_id += 1
	enemy.set_meta(META_NET, id)
	_enemies[id] = enemy
	spawned_count += 1
	# D-084: HP by player count (downed players included), after spawner, elite and room group.
	var factor := CoopRules.health_factor(GameMode.of(dm).get_player_count(), enemy.data.is_boss or enemy.is_miniboss)
	if not is_equal_approx(factor, 1.0):
		enemy.health.reset(enemy.health.get_max_health() * factor)
	enemy.died.connect(_on_enemy_died.bind(id))
	enemy.phase_changed.connect(_on_phase_changed.bind(id))
	enemy.tree_exiting.connect(_on_enemy_exiting.bind(id), CONNECT_ONE_SHOT)
	_send(&"enemy_spawned", _spawn_args(id, enemy))
	if _emerges.has(enemy.get_instance_id()):
		_send_emerge(enemy)


## R2: an enemy comes out of its spawn source (Enemy.begin_emerge). Registered enemies go out at
## once, new ones right after their enemy_spawned.
func _on_emerge_started(enemy: Enemy, wait: float, rise_time: float, style: Enemy.Emerge) -> void:
	if _detached or not is_instance_valid(enemy):
		return
	_emerges[enemy.get_instance_id()] = [Time.get_ticks_msec(), wait, rise_time, int(style)]
	if enemy.has_meta(META_NET):
		_send_emerge(enemy)


func _send_emerge(enemy: Enemy) -> void:
	var info: Array = _emerges.get(enemy.get_instance_id(), [])
	_emerges.erase(enemy.get_instance_id())
	if info.is_empty() or not enemy.is_emerging():
		return
	var left := maxf(0.0, float(info[1]) - float(Time.get_ticks_msec() - int(info[0])) / 1000.0)
	emerge_count += 1
	_send(&"enemy_emerge", [int(enemy.get_meta(META_NET)), left, float(info[2]), int(info[3])])


func _spawn_args(id: int, enemy: Enemy) -> Array:
	var room := _room_of(enemy)
	var flags := (1 if enemy.is_miniboss else 0) | (int(enemy.elite) << 1)
	return [id, room.slot_index if room != null else 0, enemy.scene_file_path, String(enemy.data.id), enemy.global_position,
			flags, enemy.get_boss_tier(), enemy.health.get_health(), enemy.health.get_max_health(), room.room_index if room != null else 1]


func _on_enemy_damaged(enemy: Node2D, result: DamageResult, damage: DamageData) -> void:
	if _detached or enemy == null or not enemy.has_meta(META_NET):
		return
	var health := (enemy as Enemy).health.get_health() if enemy is Enemy else 0.0
	_send(&"enemy_hit", [int(enemy.get_meta(META_NET)), result.health_damage + result.shield_damage, health, NetDungeon.peer_of(damage.source)])


func _on_enemy_died(enemy: Enemy, id: int) -> void:
	_enemies.erase(id)
	_last_encoded.erase(id)
	died_count += 1
	_send(&"enemy_died", [id, enemy.has_fallen_into_pit()])


func _on_phase_changed(_enemy: Enemy, phase: int, id: int) -> void:
	_send(&"enemy_phase", [id, phase])


func _on_enemy_exiting(id: int) -> void:
	var enemy: Enemy = _enemies.get(id, null)
	if enemy != null and is_instance_valid(enemy):
		_emerges.erase(enemy.get_instance_id())
	_enemies.erase(id)
	_last_encoded.erase(id)


func _register_projectile(projectile: Projectile) -> void:
	if (projectile.collision_mask & PhysicsLayers.PLAYER_HURTBOX) == 0:
		return
	var id := _next_id
	_next_id += 1
	_projectiles[id] = projectile
	projectile.tree_exiting.connect(_on_projectile_exiting.bind(id), CONNECT_ONE_SHOT)
	var texture_path := projectile.texture.resource_path if projectile.texture != null else ""
	_send(&"projectile_spawned", [id, projectile.global_position, projectile.direction, projectile.speed, projectile.max_distance,
			texture_path, projectile.frame_size, projectile.pivot, projectile.fps, projectile.color, projectile.collision_radius, projectile.light_radius])


func _on_projectile_exiting(id: int) -> void:
	_projectiles.erase(id)
	_send(&"projectile_gone", [id])


func _register_pickup(pickup: GoldPickup) -> void:
	if not is_instance_valid(pickup) or not pickup.is_inside_tree():
		return
	var id := _next_id
	_next_id += 1
	_pickups[id] = pickup
	pickup.tree_exiting.connect(_on_pickup_exiting.bind(id), CONNECT_ONE_SHOT)
	_send(&"pickup_spawned", [id, pickup.global_position, pickup.amount, int(pickup.kind)])


func _on_pickup_exiting(id: int) -> void:
	_pickups.erase(id)
	_send(&"pickup_gone", [id])


## Slams, eruptions and self-destructs of living enemies (their death blasts come with the puppet's
## own death). Read one frame later: colour and place are set after the blast entered the tree.
func _register_blast(blast: Blast) -> void:
	if not is_instance_valid(blast) or not blast.is_inside_tree():
		return
	var enemy := blast.source as Enemy
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
		return
	_send(&"blast_spawned", [blast.global_position, blast.radius, maxf(0.0, blast.delay), blast.color, blast.sound, blast.shake])


func _watch_breakable(crate: Breakable) -> void:
	var health := crate.get_node_or_null(^"HealthComponent") as HealthComponent
	if health != null:
		health.died.connect(_on_breakable_broken.bind(crate), CONNECT_ONE_SHOT)


func _on_breakable_broken(crate: Breakable) -> void:
	var room := _room_of(crate)
	if room != null:
		_send(&"breakable_broken", [room.slot_index, room.to_local(crate.global_position)])


func _physics_process(delta: float) -> void:
	if _detached:
		return
	if not is_host:
		return
	_watch_sources()
	_snapshot_left -= delta
	if _snapshot_left > 0.0 or _ready_peers.is_empty():
		return
	_snapshot_left = 1.0 / CoopRules.ENEMY_SNAPSHOT_RATE
	_full_left -= 1
	var full := _full_left <= 0 or RelayPeer.legacy_sync
	if full:
		_full_left = FULL_SNAPSHOT_EVERY
	var data := PackedFloat32Array()
	for id in _enemies:
		var enemy := _enemies[id]
		if is_instance_valid(enemy) and not enemy.is_dead():
			var encoded := encode_enemy(id, enemy)
			if not full and _last_encoded.get(id, PackedFloat32Array()) == encoded:
				continue
			_last_encoded[id] = encoded
			data.append_array(encoded)
			snapshot_entries += 1
	if not data.is_empty():
		_send(&"enemy_snapshot", [Time.get_ticks_msec(), data])


## R2: phase changes of the active room's spawn sources (warning, opening, rest) go to the clients.
func _watch_sources() -> void:
	if _ready_peers.is_empty() or dm == null:
		return
	var slot := dm.get_active_slot()
	if slot != _sources_slot:
		_sources_slot = slot
		_source_phases.clear()
	var room := dm.get_room_at_slot(slot)
	var sources := SpawnSources.of(room) if room != null else null
	if sources == null or not sources.is_built():
		return
	for child in sources.get_children():
		var source := child as SpawnSource
		if source == null or not is_instance_valid(source):
			continue
		var key := source.get_instance_id()
		if int(_source_phases.get(key, SpawnSource.Phase.IDLE)) == int(source.phase):
			continue
		_source_phases[key] = int(source.phase)
		source_events += 1
		_send(&"source_phase", [slot, String(source.name), int(source.phase), source.kind, source.spot, source.scale.x])


## One enemy of a snapshot: core fields, then the telegraph circle and line if shown.
static func encode_enemy(id: int, enemy: Enemy) -> PackedFloat32Array:
	var sprite := enemy.get_node(^"Sprite") as AnimatedSprite2D
	var circle := enemy.get_node_or_null(^"TelegraphCircle") as Node2D
	var line := enemy.get_node_or_null(^"TelegraphLine") as Line2D
	var flags := 0
	if sprite.flip_h:
		flags |= FLAG_FLIP
	if sprite.is_playing():
		flags |= FLAG_PLAYING
	var show_circle := circle != null and circle.visible
	var show_line := line != null and line.visible and line.points.size() >= 2
	var hop := enemy.get_node_or_null(HOP_MARKER_NAME) as Node2D
	var show_hop := hop != null and hop.visible
	if show_circle:
		flags |= FLAG_CIRCLE
	if show_line:
		flags |= FLAG_LINE
	if show_hop:
		flags |= FLAG_HOP
	var data := PackedFloat32Array([float(id), enemy.global_position.x, enemy.global_position.y, float(ANIMATIONS.find(sprite.animation)),
			float(flags), sprite.modulate.a, sprite.speed_scale, sprite.position.y, enemy.health.get_health()])
	if show_circle:
		var color: Color = circle.get(&"color")
		data.append_array([circle.global_position.x, circle.global_position.y, float(circle.get(&"radius")), color.r, color.g, color.b, color.a])
	if show_line:
		var end := line.points[line.points.size() - 1]
		var line_color := line.default_color
		data.append_array([end.x, end.y, line_color.r, line_color.g, line_color.b, line_color.a])
	if show_hop:
		data.append_array([hop.global_position.x, hop.global_position.y, float(hop.get(&"radius")), hop.scale.x])
	return data


# --- Client ---

@rpc("authority", "call_remote", "reliable")
func enemy_spawned(id: int, slot: int, scene_path: String, data_id: String, at: Vector2, flags: int, tier: int, health: float, max_health: float, room_index: int) -> void:
	if is_host or _detached or _puppets.has(id):
		return
	var room := dm.get_room_at_slot(slot) if slot > 0 else null
	var container: Node2D = room.enemy_container if room != null else dm
	var path := scene_path if not scene_path.is_empty() and ResourceLoader.exists(scene_path) else ENEMY_SCENE_PATH
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	if enemy == null:
		return
	var data := data_for(StringName(data_id))
	if data == null:
		data = enemy.data
	if data == null:
		enemy.free()
		return
	# No split children and no summons of its own: those come from the host.
	var copy := data.duplicate() as EnemyData
	copy.death_spawn = null
	enemy.data = copy
	enemy.set_meta(META_NET, id)
	enemy.apply_scaling(maxi(1, room_index), (flags & 1) != 0)
	var elite := (flags >> 1) & 3
	if elite != 0:
		enemy.make_elite(elite as Enemy.Elite)
	enemy.set_boss_tier(tier)
	enemy.gold_drop = 0
	enemy.position = container.to_local(at)
	container.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.hurtbox.set_invulnerable(PUPPET_INVULNERABLE, true)
	enemy.health.reset(max_health)
	enemy.health.set_current(health)
	_puppets[id] = enemy
	_targets[id] = at
	spawned_count += 1
	enemy.tree_exiting.connect(_on_puppet_exiting.bind(id), CONNECT_ONE_SHOT)
	if enemy.data.is_boss:
		_announce_boss(enemy)
	elif enemy.is_miniboss:
		dm.ui.show_boss_bar(enemy)


## The boss intro on a client (as DungeonManager._announce_boss on the host): the own player stands
## still while the boss speaks, then the boss bar.
func _announce_boss(enemy: Enemy) -> void:
	var local := dm.context.player
	if BossIntro.has_intro_for(enemy):
		if local != null and is_instance_valid(local):
			local.set_input_locked(DungeonManager.INPUT_LOCK_BOSS_INTRO, true)
		await BossIntro.play(enemy, dm.ui)
		if local != null and is_instance_valid(local):
			local.set_input_locked(DungeonManager.INPUT_LOCK_BOSS_INTRO, false)
	else:
		dm.ui.show_banner(enemy.get_display_name(), "Boss", Color(0.95, 0.4, 1.0))
		Sfx.play_ui(self, &"boss_roar")
	if is_instance_valid(enemy) and not enemy.is_dead():
		dm.ui.show_boss_bar(enemy)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func enemy_snapshot(host_msec: int, data: PackedFloat32Array) -> void:
	if is_host or _detached:
		return
	interpolator.begin_snapshot(float(host_msec), float(Time.get_ticks_msec()))
	var i := 0
	while i + SNAPSHOT_FIELDS <= data.size():
		var id := int(data[i])
		var flags := int(data[i + 4])
		var extra := (CIRCLE_FIELDS if flags & FLAG_CIRCLE else 0) + (LINE_FIELDS if flags & FLAG_LINE else 0) + (HOP_FIELDS if flags & FLAG_HOP else 0)
		var enemy := get_puppet(id)
		if enemy != null and not enemy.is_dead():
			var at := Vector2(data[i + 1], data[i + 2])
			_targets[id] = at
			interpolator.push(id, float(host_msec), at)
			_apply_snapshot(enemy, id, data, i)
			snapshot_entries += 1
		i += SNAPSHOT_FIELDS + extra


## Client: where puppet id is drawn now (interpolated; the newest position without samples or in
## legacy mode).
func drawn_position(id: int, now_msec: int) -> Vector2:
	if not RelayPeer.legacy_sync:
		var at := interpolator.position_at(id, float(now_msec))
		if at != Vector2.INF:
			return at
	return _targets.get(id, Vector2.INF)


func _apply_snapshot(enemy: Enemy, id: int, data: PackedFloat32Array, i: int) -> void:
	if enemy.is_emerging():
		# Its own emergence draws the sprite until it is out (enemy_emerge).
		return
	var flags := int(data[i + 4])
	var sprite := enemy.get_node(^"Sprite") as AnimatedSprite2D
	var animation_index := int(data[i + 3])
	if animation_index >= 0 and animation_index < ANIMATIONS.size():
		var animation := ANIMATIONS[animation_index]
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation) and (sprite.animation != animation or (flags & FLAG_PLAYING and not sprite.is_playing())):
			sprite.play(animation)
	sprite.flip_h = (flags & FLAG_FLIP) != 0
	sprite.modulate.a = data[i + 5]
	sprite.speed_scale = data[i + 6]
	sprite.position.y = data[i + 7]
	if not is_equal_approx(enemy.health.get_health(), data[i + 8]) and data[i + 8] > 0.0:
		enemy.health.set_current(data[i + 8])
	var circle := enemy.get_node_or_null(^"TelegraphCircle") as Node2D
	var line := enemy.get_node_or_null(^"TelegraphLine") as Line2D
	var at := i + SNAPSHOT_FIELDS
	if circle != null:
		circle.visible = (flags & FLAG_CIRCLE) != 0
		if circle.visible:
			circle.global_position = Vector2(data[at], data[at + 1])
			circle.set(&"radius", data[at + 2])
			circle.set(&"color", Color(data[at + 3], data[at + 4], data[at + 5], data[at + 6]))
	if flags & FLAG_CIRCLE:
		at += CIRCLE_FIELDS
	if line != null:
		line.visible = (flags & FLAG_LINE) != 0
		if line.visible:
			line.points = PackedVector2Array([Vector2.ZERO, Vector2(data[at], data[at + 1])])
			line.default_color = Color(data[at + 2], data[at + 3], data[at + 4], data[at + 5])
	if flags & FLAG_LINE:
		at += LINE_FIELDS
	_apply_hop_marker(enemy, data, at, (flags & FLAG_HOP) != 0)


## The landing marker of a slime hop (as Enemy._show_hop_marker draws it on the host).
func _apply_hop_marker(enemy: Enemy, data: PackedFloat32Array, at: int, shown: bool) -> void:
	var marker := enemy.get_node_or_null(HOP_MARKER_NAME) as PlaceholderShape
	if not shown:
		if marker != null:
			marker.visible = false
		return
	if marker == null:
		marker = PlaceholderShape.new()
		marker.name = HOP_MARKER_NAME.get_name(0)
		marker.top_level = true
		marker.z_index = -1
		marker.color = Enemy.HOP_MARKER_COLOR
		marker.outline_color = Enemy.HOP_MARKER_OUTLINE
		enemy.add_child(marker)
	marker.global_position = Vector2(data[at], data[at + 1])
	marker.radius = data[at + 2]
	marker.scale = Vector2.ONE * data[at + 3]
	marker.visible = true


func _process(delta: float) -> void:
	if is_host or _detached:
		return
	var now := Time.get_ticks_msec()
	for id in _puppets:
		var enemy := _puppets[id]
		if not is_instance_valid(enemy) or enemy.is_dead() or not _targets.has(id):
			continue
		if enemy.hurtbox.monitorable:
			# Coming out of a source switches the hurtbox back on (Enemy._start_rise): off again,
			# the client's attacks only show (the host's copy of the player hits).
			enemy.hurtbox.monitorable = false
		if not RelayPeer.legacy_sync and interpolator.has(id):
			enemy.global_position = drawn_position(id, now)
			continue
		var error: Vector2 = _targets[id] - enemy.global_position
		if error.length() > SNAP_DISTANCE:
			enemy.global_position = _targets[id]
		else:
			enemy.global_position += error * minf(1.0, FOLLOW_RATE * delta)


@rpc("authority", "call_remote", "reliable")
func enemy_hit(id: int, amount: float, health: float, attacker_peer: int) -> void:
	var enemy := get_puppet(id)
	if is_host or enemy == null or enemy.is_dead():
		return
	if health > 0.0:
		enemy.health.set_current(health)
	var sprite := enemy.get_node(^"Sprite") as AnimatedSprite2D
	SpriteFx.flash(sprite)
	SpriteStrip.spawn_effect(enemy.get_parent(), enemy.global_position, HIT_SPARK_TEXTURE, Vector2i(16, 16), 15.0, Vector2(8, 8), Vector2.ONE * SpriteStrip.PIXEL_SCALE)
	Sfx.play_at(enemy, &"hit_enemy", enemy.global_position)
	if attacker_peer > 0 and attacker_peer == multiplayer.get_unique_id() and amount > 0.0:
		var result := DamageResult.new()
		result.health_damage = amount
		result.amount = amount
		var top := enemy.global_position + Vector2(0.0, -enemy.data.body_radius * enemy.data.sprite_scale - 22.0)
		DamageNumber.spawn_for_result(enemy.get_parent(), top, result)


@rpc("authority", "call_remote", "reliable")
func enemy_died(id: int, fell: bool) -> void:
	var enemy := get_puppet(id)
	if is_host or enemy == null or enemy.is_dead():
		return
	died_count += 1
	_forget_target(id)
	if fell:
		enemy.fall_into_pit()
	else:
		enemy.health.take_damage(INF)


## R2: the host's enemy comes out of its spawn source: the puppet hides and emerges the same way
## (wait_left: seconds of the source's warning that are still to come).
@rpc("authority", "call_remote", "reliable")
func enemy_emerge(id: int, wait_left: float, rise_time: float, style: int) -> void:
	var enemy := get_puppet(id)
	if is_host or enemy == null or enemy.is_dead():
		return
	emerge_count += 1
	enemy.begin_emerge(wait_left, rise_time, style as Enemy.Emerge)


## R2: a spawn source of the host changed its phase (warning, opening, rest). The client's source
## of the same name plays it; a champion's own source (made where the champion stands) is created.
@rpc("authority", "call_remote", "reliable")
func source_phase(slot: int, source_name: String, phase: int, kind: int, spot: Vector2, source_scale: float) -> void:
	if is_host or _detached:
		return
	var sources := SpawnSources.of(dm.get_room_at_slot(slot))
	if sources == null:
		return
	sources.build()
	var source := sources.get_node_or_null(NodePath(source_name)) as SpawnSource
	if source == null:
		if SpawnSourceRules.is_wall_kind(kind):
			return
		source = SpawnSource.create_floor(kind, spot)
		source.scale = Vector2.ONE * source_scale
		sources.add_child(source)
	source_events += 1
	match phase:
		SpawnSource.Phase.WARN:
			source.warn()
		SpawnSource.Phase.OPEN:
			source.open(source.phase == SpawnSource.Phase.WARN)
		SpawnSource.Phase.REST:
			source.settle()


@rpc("authority", "call_remote", "reliable")
func enemy_phase(id: int, phase: int) -> void:
	var enemy := get_puppet(id)
	if is_host or enemy == null:
		return
	enemy.phase = phase
	SpriteFx.outline(enemy.get_node(^"Sprite") as AnimatedSprite2D, Enemy.ENRAGE_COLOR, 0.9)
	enemy.phase_changed.emit(enemy, phase)


@rpc("authority", "call_remote", "reliable")
func projectile_spawned(id: int, at: Vector2, direction: Vector2, speed: float, distance: float, texture_path: String,
		frame_size: Vector2i, pivot: Vector2, fps: float, color: Color, radius: float, light: float) -> void:
	if is_host or _detached:
		return
	var damage := DamageData.new()
	var projectile := Projectile.create(damage, direction, speed, distance, 0)
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		projectile.texture = load(texture_path) as Texture2D
	projectile.frame_size = frame_size
	projectile.pivot = pivot
	projectile.fps = fps
	projectile.color = color
	projectile.collision_radius = radius
	projectile.light_radius = light
	var room := dm.get_room_at_slot(dm.get_active_slot())
	var parent: Node = room.enemy_container if room != null else dm
	projectile.launch(parent, at)
	_client_projectiles[id] = projectile
	projectile_count += 1
	projectile.tree_exiting.connect(func() -> void: _client_projectiles.erase(id), CONNECT_ONE_SHOT)


@rpc("authority", "call_remote", "reliable")
func projectile_gone(id: int) -> void:
	var projectile: Node = _client_projectiles.get(id, null)
	_client_projectiles.erase(id)
	if not is_host and projectile != null and is_instance_valid(projectile):
		projectile.queue_free()


@rpc("authority", "call_remote", "reliable")
func blast_spawned(at: Vector2, radius: float, delay: float, color: Color, sound: StringName, shake: float) -> void:
	if is_host or _detached:
		return
	# Only the picture and the warning: the host's blast deals the damage.
	var blast := Blast.new()
	blast.radius = radius
	blast.damage = 0.0
	blast.delay = delay
	blast.target_mask = 0
	blast.color = color
	blast.sound = sound
	blast.shake = shake
	var room := dm.get_room_at_slot(dm.get_active_slot())
	var parent: Node = room.enemy_container if room != null else dm
	parent.add_child(blast)
	blast.global_position = at


@rpc("authority", "call_remote", "reliable")
func pickup_spawned(id: int, at: Vector2, amount: int, kind: int) -> void:
	if is_host or _detached:
		return
	var pickup := Enemy.GOLD_PICKUP_SCENE.instantiate() as GoldPickup
	pickup.amount = amount
	pickup.kind = kind as GoldPickup.Kind
	pickup.visual_only = true
	pickup.set_meta(META_NET, id)
	var room := dm.get_room_at_slot(dm.get_active_slot())
	var parent: Node2D = room.enemy_container if room != null else dm
	pickup.position = parent.to_local(at)
	parent.add_child(pickup)
	_client_pickups[id] = pickup
	pickup_count += 1
	pickup.tree_exiting.connect(func() -> void: _client_pickups.erase(id), CONNECT_ONE_SHOT)


@rpc("authority", "call_remote", "reliable")
func pickup_gone(id: int) -> void:
	var pickup: Node = _client_pickups.get(id, null)
	_client_pickups.erase(id)
	if not is_host and pickup != null and is_instance_valid(pickup):
		pickup.queue_free()


@rpc("authority", "call_remote", "reliable")
func breakable_broken(slot: int, local_position: Vector2) -> void:
	var room := dm.get_room_at_slot(slot)
	if is_host or room == null:
		return
	var best: Breakable = null
	var best_distance := 24.0
	for node in room.find_children("*", "Breakable", true, false):
		var crate := node as Breakable
		var distance := room.to_local(crate.global_position).distance_to(local_position)
		if distance < best_distance:
			best = crate
			best_distance = distance
	if best != null:
		var health := best.get_node_or_null(^"HealthComponent") as HealthComponent
		if health != null:
			health.take_damage(INF)


func _on_puppet_exiting(id: int) -> void:
	_puppets.erase(id)
	_forget_target(id)


func _forget_target(id: int) -> void:
	_targets.erase(id)
	interpolator.erase(id)


# --- Helpers ---

static func _room_of(node: Node) -> RoomController:
	var current := node.get_parent()
	while current != null:
		if current is RoomController:
			return current
		current = current.get_parent()
	return null


func _send(method: StringName, args: Array) -> void:
	if not is_host or _detached or _ready_peers.is_empty():
		return
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	for id in _ready_peers:
		callv(&"rpc_id", [id, method] + args)
