class_name EnemyPack
extends RefCounted
## Coordinator of the group tactics of one room (RAEUME §6): one instance per enemy
## container (stored as metadata on it, freed with the room). Every few tenths of a second it plans
## per target (nearest living player or decoy, EnemyTargeting / EnemyDecoy, so coop gets places per
## player): ring places for the close-combat enemies, cutters ahead of a fleeing target, side
## changes of ranged enemies and slime packs (tag "swarm", 3-5 animals) that hop in turn.
## Decisions only: the enemy asks for its goal and its hop turn and does the moving and the effects
## itself. Rules and TESTWERTE: EnemyTactics. Randomness only from a generator derived from the
## dungeon RNG of the room (seed and room number; it never draws from the dungeon RNG itself, so
## the dungeon of a seed stays the same). Bosses and champions do not take part (Enemy.uses_tactics),
## their minions do.

enum Role { DIRECT, RING, CUT_OFF, RANGED, RELOCATE }

const META := &"enemy_pack"
## A walking goal around a target keeps this far off the edges of a plateau (px, M3): body radius
## plus the strip of the edge without navigation. TESTWERT
const GOAL_EDGE_MARGIN := 20.0


## What one enemy should do right now.
class Order:
	extends RefCounted
	var role := Role.DIRECT
	## RING / CUT_OFF / RELOCATE: place angle around the target (radians, world).
	var angle := 0.0
	## Ring radius, cut-off lead or ranged distance (px).
	var radius := 0.0
	## Unit flight direction of the target (CUT_OFF).
	var flee := Vector2.ZERO
	## Engaged inside this distance to the target (ring radius of the enemy).
	var ring := 0.0
	var pack: Pack = null
	var hop_granted := false
	var grant_left := 0.0
	var approach_time := 0.0
	var direct_left := 0.0
	var last_position := Vector2.INF
	## Ranged: seconds until the next side change (negative = not planned yet).
	var switch_left := -1.0
	var relocate_left := 0.0


## One slime pack: its members hop one after another (the beat).
class Pack:
	extends RefCounted
	## Untyped on purpose: may hold freed enemies until the next plan prunes them.
	var members: Array = []
	var target_id := 0
	var next_index := 0
	var next_hop_in := 0.0
	var strength := 0.0
	## Clock time of the last take-off: the next member waits at least HOP_STAGGER after it.
	var last_takeoff := -INF


## Movement estimate of one target.
class Track:
	extends RefCounted
	var last_position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var base_angle := 0.0
	var has_base := false
	var seen := false


## Untyped: may hold freed enemies (never filter a typed Array[Enemy] with freed entries).
var _members: Array = []
## instance id -> Order
var _orders: Dictionary = {}
## target instance id -> Track
var _tracks: Dictionary = {}
var _packs: Array[Pack] = []
var _rng := RandomNumberGenerator.new()
var _rng_ready := false
var _container: Node = null
var _last_frame := -1
var _replan_left := 0.0
var _since_plan := 0.0
var _clock := 0.0


## The coordinator of enemy's container (created on first use) with enemy joined; null without
## a parent.
static func for_enemy(enemy: Enemy) -> EnemyPack:
	if enemy == null or not is_instance_valid(enemy):
		return null
	var parent := enemy.get_parent()
	if parent == null:
		return null
	var pack: EnemyPack = null
	if parent.has_meta(META):
		pack = parent.get_meta(META) as EnemyPack
	if pack == null:
		pack = EnemyPack.new()
		pack._container = parent
		parent.set_meta(META, pack)
	pack.join(enemy)
	return pack


## Coordinator of a container, or null (tools and tests).
static func of(container: Node) -> EnemyPack:
	if container == null or not is_instance_valid(container) or not container.has_meta(META):
		return null
	return container.get_meta(META) as EnemyPack


func join(enemy: Enemy) -> void:
	var id := enemy.get_instance_id()
	if _orders.has(id):
		return
	_members.append(enemy)
	_orders[id] = Order.new()
	# Plan at once on the next tick: a new enemy should not chase blindly for a whole interval.
	_replan_left = 0.0


## Seed of the tactics generator (tests). Otherwise derived from the room's dungeon RNG.
func set_seed(value: int) -> void:
	_rng.seed = value
	_rng_ready = true


## Called by every member each physics frame; the plan advances once per frame.
func tick(_enemy: Enemy, delta: float) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _last_frame:
		return
	_last_frame = frame
	advance(delta)


## One step of the coordinator (public for tests): grants, the pack beat and, every
## REPLAN_INTERVAL, a new plan.
func advance(delta: float) -> void:
	_clock += delta
	_since_plan += delta
	_replan_left -= delta
	if _replan_left <= 0.0:
		_replan_left = EnemyTactics.REPLAN_INTERVAL
		_plan(_since_plan)
		_since_plan = 0.0
	for id: int in _orders:
		var order: Order = _orders[id]
		if order.hop_granted:
			order.grant_left -= delta
			if order.grant_left <= 0.0:
				order.hop_granted = false
	for pack in _packs:
		_beat(pack, delta)


func get_order(enemy: Enemy) -> Order:
	if enemy == null:
		return null
	return _orders.get(enemy.get_instance_id()) as Order


func get_role(enemy: Enemy) -> Role:
	var order := get_order(enemy)
	return order.role if order != null else Role.DIRECT


## Where enemy walks now: its target (DIRECT, RANGED, engaged) or the next point on the way to
## its place, kept inside the room.
func walk_goal(enemy: Enemy) -> Vector2:
	var target := enemy.get_target_node()
	if target == null:
		return enemy.global_position
	var center := target.global_position
	var order := get_order(enemy)
	if order == null:
		return center
	# Target on the other level of a plateau (M3): straight for it, the navigation finds the stairs
	# (a ring place below the cliff would only end in front of the rock). On the stairs too.
	if is_changing_level(enemy, target):
		return center
	var goal := center
	match order.role:
		Role.RING:
			goal = EnemyTactics.approach_point(enemy.global_position, center, order.angle, order.radius)
		Role.CUT_OFF:
			goal = EnemyTactics.cut_off_point(enemy.global_position, center, order.flee, order.ring, order.radius)
		Role.RELOCATE:
			goal = EnemyTactics.orbit_point(enemy.global_position, center, order.angle, order.radius)
		_:
			return center
	return _on_target_level(target, _inside_room(enemy, goal))


func is_relocating(enemy: Enemy) -> bool:
	return get_role(enemy) == Role.RELOCATE


func is_pack_member(enemy: Enemy) -> bool:
	var order := get_order(enemy)
	return order != null and order.pack != null


## Share of its speed a pack member walks with between its hops (1 when it is no pack member,
## engaged, or walks straight at its target).
func creep_factor(enemy: Enemy, target_distance: float) -> float:
	var order := get_order(enemy)
	if order == null or order.pack == null or order.role == Role.DIRECT:
		return 1.0
	if target_distance <= order.ring + EnemyTactics.HOP_TARGET_MARGIN:
		return 1.0
	return EnemyTactics.HOP_CREEP_FACTOR


## Is it enemy's turn to hop (and is the hop worth it)?
func wants_hop(enemy: Enemy) -> bool:
	var order := get_order(enemy)
	if order == null or order.pack == null or not order.hop_granted:
		return false
	if order.role != Role.RING and order.role != Role.CUT_OFF:
		return false
	var target := enemy.get_target_node()
	if target == null or is_changing_level(enemy, target):
		# Target on the other level of a plateau (M3): a hop only ends at the edge (feedback
		# #690502d9: slimes hopped back to the cliff instead of walking round to the stairs).
		return false
	return enemy.global_position.distance_to(target.global_position) > order.ring + EnemyTactics.HOP_TARGET_MARGIN


## Landing point of enemy's hop (pure geometry, the enemy checks walls and abysses).
func hop_landing(enemy: Enemy) -> Vector2:
	var order := get_order(enemy)
	var target := enemy.get_target_node()
	if order == null or target == null:
		return enemy.global_position
	var track := _tracks.get(target.get_instance_id()) as Track
	var velocity := track.velocity if track != null else Vector2.ZERO
	var angle := order.angle if order.role == Role.RING else order.flee.angle()
	var landing := EnemyTactics.hop_landing(enemy.global_position, target.global_position, velocity, angle, order.ring, order.pack.strength if order.pack != null else 0.0)
	return _on_target_level(target, _inside_room(enemy, landing))


func hop_started(enemy: Enemy) -> void:
	var order := get_order(enemy)
	if order == null:
		return
	order.hop_granted = false
	if order.pack != null:
		order.pack.last_takeoff = _clock


## The hop was not possible (wall, abyss): the turn goes on to the next member.
func hop_refused(enemy: Enemy) -> void:
	var order := get_order(enemy)
	if order != null:
		order.hop_granted = false


## Estimated velocity of a target (px/s), zero for unknown targets.
func get_target_velocity(target: Node2D) -> Vector2:
	if target == null:
		return Vector2.ZERO
	var track := _tracks.get(target.get_instance_id()) as Track
	return track.velocity if track != null else Vector2.ZERO


## Living members of enemy's pack (empty for non-members). For tools and tests.
func get_pack_mates(enemy: Enemy) -> Array[Enemy]:
	var result: Array[Enemy] = []
	var order := get_order(enemy)
	if order == null or order.pack == null:
		return result
	for i in order.pack.members.size():
		var member: Variant = order.pack.members[i]
		if is_instance_valid(member):
			result.append(member as Enemy)
	return result


func get_pack_count() -> int:
	return _packs.size()


# --- Planning ---

func _plan(elapsed: float) -> void:
	_ensure_rng()
	var groups := {}
	var targets := {}
	var alive: Array = []
	for i in _members.size():
		var member: Variant = _members[i]
		if not is_instance_valid(member):
			continue
		var enemy := member as Enemy
		if enemy.is_dead():
			continue
		alive.append(enemy)
		if not enemy.is_tactical():
			_reset(_orders[enemy.get_instance_id()])
			continue
		var target := enemy.get_target_node()
		if target == null:
			continue
		var target_id := target.get_instance_id()
		if not groups.has(target_id):
			groups[target_id] = []
			targets[target_id] = target
		(groups[target_id] as Array).append(enemy)
	_members = alive
	var known := {}
	for member: Enemy in alive:
		known[member.get_instance_id()] = true
	for id: int in _orders.keys():
		if not known.has(id):
			_orders.erase(id)
	for target_id: int in _tracks.keys():
		if not targets.has(target_id):
			_tracks.erase(target_id)
	for target_id: int in groups:
		_plan_target(targets[target_id], groups[target_id], elapsed)
	_plan_packs(groups, targets)


func _plan_target(target: Node2D, enemies: Array, elapsed: float) -> void:
	var center := target.global_position
	var track := _update_track(target, elapsed)
	var room := (enemies[0] as Enemy).get_room_index()
	var strength := EnemyTactics.intensity(room)
	var close: Array[Enemy] = []
	var ranged: Array[Enemy] = []
	for member: Enemy in enemies:
		if member.data.attack_kind == EnemyData.AttackKind.RANGED:
			ranged.append(member)
		elif is_changing_level(member, target):
			# Other level of a plateau or on the stairs (M3): straight for the target at full speed,
			# the navigation finds the stairs; no ring place below the cliff, no slow creep, no hop.
			get_order(member).role = Role.DIRECT
		else:
			close.append(member)
	_plan_close(close, center, track, room, strength, elapsed)
	for member in ranged:
		_plan_ranged(member, ranged, center, strength, elapsed)


func _plan_close(close: Array[Enemy], center: Vector2, track: Track, room: int, strength: float, elapsed: float) -> void:
	var ring: Array[Enemy] = []
	for member in close:
		var order := get_order(member)
		order.ring = EnemyTactics.ring_radius(member.data)
		_update_patience(order, member, center, elapsed)
		if order.direct_left > 0.0:
			order.role = Role.DIRECT
		else:
			ring.append(member)
	var speed := track.velocity.length()
	var cutters := EnemyTactics.cut_off_count(ring.size(), room, speed)
	if cutters > 0:
		var flee := track.velocity / speed
		# The members most ahead of the target are the ones that can block its way.
		ring.sort_custom(func(a: Enemy, b: Enemy) -> bool:
			return (a.global_position - center).normalized().dot(flee) > (b.global_position - center).normalized().dot(flee))
		for i in cutters:
			var order := get_order(ring[i])
			order.role = Role.CUT_OFF
			order.flee = flee
			order.angle = flee.angle()
			order.radius = EnemyTactics.cut_off_lead(room, order.ring)
		ring = ring.slice(cutters)
	if ring.size() == 1 and cutters == 0:
		# A lone enemy keeps its old, straight chase.
		get_order(ring[0]).role = Role.DIRECT
		return
	if ring.is_empty():
		return
	var angles := PackedFloat32Array()
	for member in ring:
		angles.append((member.global_position - center).angle())
	var base := EnemyTactics.circular_mean(angles)
	if track.has_base:
		base = EnemyTactics.turn_towards(track.base_angle, base, EnemyTactics.BASE_TURN)
	track.base_angle = base
	track.has_base = true
	var slots := EnemyTactics.ring_angles(ring.size(), base, EnemyTactics.ring_spread(strength))
	var assignment := EnemyTactics.assign_by_angle(angles, slots, base)
	for i in ring.size():
		var order := get_order(ring[i])
		order.role = Role.RING
		order.angle = slots[assignment[i]]
		order.radius = order.ring


## Hanging on the way to the ring place (wall, corner, crowd: hardly moving while it chases):
## straight at the target for a moment.
func _update_patience(order: Order, member: Enemy, center: Vector2, elapsed: float) -> void:
	var moved := member.global_position.distance_to(order.last_position)
	order.last_position = member.global_position
	if order.direct_left > 0.0:
		order.direct_left -= elapsed
		order.approach_time = 0.0
		return
	var placed := order.role == Role.RING or order.role == Role.CUT_OFF
	var hanging := member.is_chasing() and moved < EnemyTactics.STUCK_SPEED * elapsed
	if placed and hanging and member.global_position.distance_to(center) > order.ring * 1.15:
		order.approach_time += elapsed
	elif not placed or member.global_position.distance_to(center) <= order.ring * 1.15:
		order.approach_time = 0.0
	if order.approach_time >= EnemyTactics.SLOT_PATIENCE:
		order.approach_time = 0.0
		order.direct_left = EnemyTactics.DIRECT_TIME


func _plan_ranged(member: Enemy, ranged: Array[Enemy], center: Vector2, strength: float, elapsed: float) -> void:
	var order := get_order(member)
	if strength < EnemyTactics.RANGED_SWITCH_FROM or holds_high_ground(member):
		order.role = Role.RANGED
		return
	var current := (member.global_position - center).angle()
	if order.role == Role.RELOCATE:
		# Only walking time counts: a shot that was already under way does not eat the change.
		if member.is_chasing():
			order.relocate_left -= elapsed
		if absf(angle_difference(current, order.angle)) <= EnemyTactics.RELOCATE_TOLERANCE or order.relocate_left <= 0.0:
			order.role = Role.RANGED
			order.switch_left = _switch_interval(strength)
		return
	order.role = Role.RANGED
	if order.switch_left < 0.0:
		order.switch_left = _switch_interval(strength)
		return
	order.switch_left -= elapsed
	if order.switch_left > 0.0:
		return
	# Change sides: away from the nearest other ranged enemy of this target (else a random side).
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var nearest := INF
	for other in ranged:
		if other == member:
			continue
		var difference := angle_difference(current, (other.global_position - center).angle())
		if absf(difference) < nearest:
			nearest = absf(difference)
			side = -signf(difference) if difference != 0.0 else side
	order.role = Role.RELOCATE
	order.angle = current + side * _rng.randf_range(EnemyTactics.SIDE_SWITCH_ANGLE.x, EnemyTactics.SIDE_SWITCH_ANGLE.y)
	order.radius = EnemyTactics.ranged_radius(member.data)
	order.relocate_left = EnemyTactics.RELOCATE_TIME


## Is member on its way to the target's level (M3): on the other level of a plateau, or on the
## stairs (both levels) while the target is not. Such members walk straight at full speed: a pack
## slime that crept and hopped on the one tile wide stairs held up everyone behind it (#56d68b40,
## "Nahkämpfer kommen nur einzeln auf die Flammen-Empore").
static func is_changing_level(member: Node, target: Node) -> bool:
	if not HeightRules.has_height():
		return false
	if not HeightRules.same_level(member, target):
		return true
	return HeightRules.level_of(member) == HeightRules.BOTH and HeightRules.level_of(target) != HeightRules.BOTH


## Height (M3b, D-189, "Druck von oben"): a ranged enemy on a plateau whose target stands below
## keeps its place up there - no side change that would walk it down the stairs. It still chases a
## target out of range like every ranged enemy.
static func holds_high_ground(member: Enemy) -> bool:
	if member == null or not HeightRules.has_height():
		return false
	var target := member.get_target_node()
	if target == null or not is_instance_valid(target):
		return false
	return HeightRules.level_of(member) == HeightRules.PLATEAU and HeightRules.level_of(target) == HeightRules.GROUND


func _switch_interval(strength: float) -> float:
	var t := inverse_lerp(EnemyTactics.RANGED_SWITCH_FROM, 1.0, clampf(strength, EnemyTactics.RANGED_SWITCH_FROM, 1.0))
	return lerpf(EnemyTactics.SIDE_SWITCH_INTERVAL.x, EnemyTactics.SIDE_SWITCH_INTERVAL.y, t) + _rng.randf() * EnemyTactics.SIDE_SWITCH_JITTER


func _update_track(target: Node2D, elapsed: float) -> Track:
	var target_id := target.get_instance_id()
	var track := _tracks.get(target_id) as Track
	if track == null:
		track = Track.new()
		_tracks[target_id] = track
	var position := target.global_position
	if track.seen and elapsed > 0.0:
		var measured := (position - track.last_position) / elapsed
		# Teleports (room change, respawn) are no flight.
		if measured.length() > 1200.0:
			measured = Vector2.ZERO
		track.velocity = track.velocity.lerp(measured, 0.6)
	track.last_position = position
	track.seen = true
	return track


# --- Slime packs ---

func _plan_packs(groups: Dictionary, targets: Dictionary) -> void:
	# Swarm members per target.
	var swarm := {}
	for target_id: int in groups:
		var list: Array[Enemy] = []
		for member: Enemy in groups[target_id]:
			if member.is_swarm():
				list.append(member)
		swarm[target_id] = list
	# Keep existing packs: drop dead, non-tactical or retargeted members, break up small packs.
	var kept: Array[Pack] = []
	var in_pack := {}
	for pack in _packs:
		var list: Array[Enemy] = swarm.get(pack.target_id, [] as Array[Enemy])
		var members: Array = []
		for i in pack.members.size():
			var member: Variant = pack.members[i]
			if not is_instance_valid(member):
				continue
			if list.has(member):
				members.append(member)
			else:
				var dropped := get_order(member as Enemy)
				if dropped != null and dropped.pack == pack:
					dropped.pack = null
		if members.size() < EnemyTactics.PACK_KEEP:
			for member: Enemy in members:
				get_order(member).pack = null
			continue
		pack.members = members
		pack.next_index = mini(pack.next_index, members.size() - 1)
		kept.append(pack)
		for member: Enemy in members:
			in_pack[member.get_instance_id()] = true
	_packs = kept
	for target_id: int in swarm:
		var center: Vector2 = (targets[target_id] as Node2D).global_position
		var free: Array[Enemy] = []
		for member: Enemy in swarm[target_id]:
			if not in_pack.has(member.get_instance_id()):
				free.append(member)
		if free.is_empty():
			continue
		# Newcomers (split slimes, summons) join a pack of their target with room nearby.
		var rest: Array[Enemy] = []
		for member in free:
			var joined := _join_nearest_pack(member, target_id)
			if not joined:
				rest.append(member)
		var sizes := EnemyTactics.pack_sizes(rest.size())
		if sizes.is_empty():
			for member in rest:
				get_order(member).pack = null
			continue
		# Neighbours around the target form one pack (sorted by angle, cut into runs).
		rest.sort_custom(func(a: Enemy, b: Enemy) -> bool:
			return (a.global_position - center).angle() < (b.global_position - center).angle())
		var start := 0
		for size in sizes:
			var pack := Pack.new()
			pack.target_id = target_id
			pack.members.assign(rest.slice(start, start + size))
			pack.strength = EnemyTactics.intensity((rest[start] as Enemy).get_room_index())
			pack.next_hop_in = _rng.randf() * EnemyTactics.HOP_STAGGER * 2.0
			start += size
			for member: Enemy in pack.members:
				get_order(member).pack = pack
			_packs.append(pack)


func _join_nearest_pack(member: Enemy, target_id: int) -> bool:
	var best: Pack = null
	var best_distance := EnemyTactics.PACK_JOIN_DISTANCE
	for pack in _packs:
		if pack.target_id != target_id or pack.members.size() >= EnemyTactics.PACK_MAX:
			continue
		var distance := member.global_position.distance_to(_pack_center(pack))
		if distance < best_distance:
			best_distance = distance
			best = pack
	if best == null:
		return false
	best.members.append(member)
	get_order(member).pack = best
	return true


func _pack_center(pack: Pack) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for i in pack.members.size():
		var member: Variant = pack.members[i]
		if is_instance_valid(member):
			sum += (member as Node2D).global_position
			count += 1
	return sum / count if count > 0 else Vector2.INF


## The beat: members get their hop turn one after another (only while they chase, never sooner
## than HOP_STAGGER after the last take-off), then the pack rests.
func _beat(pack: Pack, delta: float) -> void:
	if pack.members.is_empty():
		return
	pack.next_hop_in -= delta
	if pack.next_hop_in > 0.0 or _clock - pack.last_takeoff < EnemyTactics.HOP_STAGGER:
		return
	if pack.next_index >= pack.members.size():
		pack.next_index = 0
	var member: Variant = pack.members[pack.next_index]
	if is_instance_valid(member) and (member as Enemy).is_chasing():
		var order := get_order(member as Enemy)
		if order != null and order.pack == pack:
			order.hop_granted = true
			order.grant_left = EnemyTactics.HOP_GRANT_TIME
	pack.next_index += 1
	if pack.next_index >= pack.members.size():
		pack.next_index = 0
		pack.next_hop_in = EnemyTactics.HOP_STAGGER + EnemyTactics.hop_round_pause(pack.strength)
	else:
		pack.next_hop_in = EnemyTactics.HOP_STAGGER


func _reset(order: Order) -> void:
	order.role = Role.DIRECT
	order.hop_granted = false


## A ring place, cut-off point or hop landing around a target on a plateau may lie off its edge,
## on the ground below or beside it, or on the edge itself, where the navigation of the ground is
## nearer than the plateau's (M3, feedback #690502d9): walking there leads down the stairs and round
## to the rock under the target. Such a point becomes the target itself (the navigation walks the
## level); the same for a point on the plateau or its edge around a target on the ground.
static func _on_target_level(target: Node2D, point: Vector2) -> Vector2:
	if not HeightRules.has_height():
		return point
	var feet := HeightRules.body_point(target)
	return point if HeightRules.is_level_goal(feet, point, GOAL_EDGE_MARGIN) else target.global_position


func _inside_room(enemy: Enemy, point: Vector2) -> Vector2:
	if enemy.arena.size == Vector2.ZERO:
		return point
	var inner := enemy.arena.grow(-40.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return point
	return point.clamp(inner.position, inner.end)


## Derived from the dungeon RNG of the room without drawing from it: its seed and the room number
## (the dungeon of a seed stays the same). Without a room (tests, tools): the room number alone.
func _ensure_rng() -> void:
	if _rng_ready:
		return
	_rng_ready = true
	var room_index := 0
	var dungeon_seed := 0
	var node: Node = _container
	while node != null:
		var context: Variant = node.get(&"context")
		if context is DungeonContext and (context as DungeonContext).rng != null:
			dungeon_seed = (context as DungeonContext).rng.seed
			room_index = int(node.get(&"room_index"))
			break
		node = node.get_parent()
	if room_index == 0:
		for i in _members.size():
			var member: Variant = _members[i]
			if is_instance_valid(member):
				room_index = (member as Enemy).get_room_index()
				break
	_rng.seed = hash([dungeon_seed, room_index, "enemy_pack"])
