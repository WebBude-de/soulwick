class_name CoopRules
extends RefCounted
## Numbers and pure rules of the shared dungeon run (MP3, D-084, D-123, D-126). No nodes, unit-
## tested in tests/unit/test_coop_rules.gd. n = players of the session (GameMode.get_player_count,
## downed players included); n = 1 changes nothing.

## D-084 TESTWERTE: enemy count per wave x (1 + 0.6 (n - 1)), HP of normal enemies
## x (1 + 0.2 (n - 1)), HP of champions, minibosses and bosses x (1 + 0.7 (n - 1)).
const COUNT_PER_PLAYER := 0.6
const HEALTH_PER_PLAYER := 0.2
const BOSS_HEALTH_PER_PLAYER := 0.7
## D-084 TESTWERTE: stand this long next to a downed player to revive them; they get up with
## this much HP. REVIVE_RADIUS (px, D-126 TESTWERT): "next to".
const REVIVE_TIME := 2.0
const REVIVE_HEALTH := 2.0
const REVIVE_RADIUS := 56.0
## D-126 TESTWERTE: the next room starts when all living players stand in it, or this many seconds
## after the first one entered (stragglers are teleported in).
const EXIT_COUNTDOWN := 10.0
## D-126 TESTWERT: seconds every player has for the upgrade choice; then the first card is taken.
const UPGRADE_TIMEOUT := 30.0
## D-126 TESTWERT: the host starts room 1 at the latest this long after the run began, even if a
## client has not loaded the dungeon yet.
const CLIENT_READY_TIMEOUT := 30.0
## D-126 TESTWERTE: enemy snapshots per second (positions, animation, telegraphs) and player
## state snapshots (HP, shield, revive) per second.
const ENEMY_SNAPSHOT_RATE := 15.0
const PLAYER_STATE_RATE := 10.0
## A player counts as in a tunnel this far inside a passage tile (px, like DoorView).
const PASSAGE_INSET := 4.0


static func count_factor(players: int) -> float:
	return 1.0 + COUNT_PER_PLAYER * float(maxi(1, players) - 1)


## HP factor of an enemy: champions, minibosses and bosses scale harder (D-084).
static func health_factor(players: int, boss_like: bool) -> float:
	var per_player := BOSS_HEALTH_PER_PLAYER if boss_like else HEALTH_PER_PLAYER
	return 1.0 + per_player * float(maxi(1, players) - 1)


## Encounter group for a room of n players: the room's own group with the count factor on top, or a
## plain group that only scales the count. null when nothing changes (one player).
static func scale_group(group: EncounterGroup, players: int) -> EncounterGroup:
	var factor := count_factor(players)
	if is_equal_approx(factor, 1.0):
		return group
	var scaled: EncounterGroup = group.duplicate() if group != null else EncounterGroup.new()
	if group == null:
		scaled.id = &"coop"
	scaled.count_factor *= factor
	return scaled


## The room may start: every living player stands in it (protected ones count as present), or the
## countdown since the first entry ran out.
static func should_start_room(living: int, present: int, waited: float) -> bool:
	return present >= living or waited >= EXIT_COUNTDOWN


## Revive progress after delta seconds: grows while a teammate is near, falls back to 0 otherwise.
static func revive_progress(progress: float, helper_near: bool, delta: float) -> float:
	return progress + delta if helper_near else 0.0


## Gold and crystal payout of every player at the run end (D-081/D-123/D-126): the portal pays
## 100 %, death, abort and a lost host 50 % (RunManager rounding).
static func payout_ratio(reason: int) -> float:
	return RunManager.EXIT_PAYOUT_RATIO if reason == RunManager.EndReason.EXIT else RunManager.LOSS_PAYOUT_RATIO


# --- Makeover (M2, M4; D-140, D-143) ---

## M4 TESTWERT: the group camera follows the middle of the local player and every standing teammate
## no further than this (world px per axis) from them: the middle then never leaves the local player
## more than this far, so with the dead zone (64×48) and the lead (48×36) he stays in view at 1.25×
## (half view 512×288 world px). Teammates further away drop out of the middle until they come back.
const CAMERA_KEEP := Vector2(380.0, 200.0)


## Nodes the group camera of local keeps in view (CameraRig.set_targets_provider): local itself
## (also while down) and every living teammate within CAMERA_KEEP of it. players: the session's
## players (any order, freed or downed ones are skipped).
static func camera_group(local: Node2D, players: Array, keep := CAMERA_KEEP) -> Array[Node2D]:
	var group: Array[Node2D] = []
	if local == null or not is_instance_valid(local):
		return group
	group.append(local)
	for node: Variant in players:
		if not is_instance_valid(node) or node == local:
			continue
		var mate := node as Node2D
		if mate == null or not mate.is_inside_tree() or not EnemyTargeting.is_alive(mate):
			continue
		var offset := mate.global_position - local.global_position
		if absf(offset.x) <= keep.x and absf(offset.y) <= keep.y:
			group.append(mate)
	return group


## D-143 (open co-op point, proposal: "sie erscheinen beim Team"): where a player who got up lands.
## Outside the active room's floor and the way back shut (gate closed or no gate any more) ->
## at the nearest standing teammate (the reviver); otherwise where he lies (he walks himself).
## Returns Vector2.INF for "stay".
static func rejoin_point(player_position: Vector2, room_floor: Rect2, gate_open: bool, mates: Array[Vector2]) -> Vector2:
	if room_floor.has_point(player_position) or gate_open or mates.is_empty():
		return Vector2.INF
	var best := mates[0]
	for mate in mates:
		if mate.distance_squared_to(player_position) < best.distance_squared_to(player_position):
			best = mate
	return best


## M2 tunnels (PassageCover): is point (world px, a player's position) inside the passage of one of
## views (DoorView or anything with get_passage_rects(): view-local rects of the passage tiles)? The
## same test DoorView makes for its tunnel shade. The rock lies above the characters on every
## machine, so a player in there is hidden everywhere; NetDungeon hides his name tag with it.
static func in_passage(point: Vector2, views: Array) -> bool:
	for node: Variant in views:
		if not is_instance_valid(node):
			continue
		var view := node as Node2D
		if view == null or not view.is_inside_tree() or not view.has_method(&"get_passage_rects"):
			continue
		var local := view.to_local(point)
		for rect: Rect2 in view.call(&"get_passage_rects"):
			if rect.grow(-PASSAGE_INSET).has_point(local):
				return true
	return false
