class_name LanternVariant
extends CombatVariant
## Variant "Laternenträger" (KONZEPT_RAEUME §4.4, A9; every biome): the room is dark. A soul lantern
## lies inside the entrance, an empty socket stands in front of the exit; the exit only opens once
## the lantern is in the socket. Take and put down with E (SoulLantern); the carrier sees much
## farther, walks slower and cannot attack, but may dash (LanternCarry, state at the player).
## When the lantern is first picked up, more enemies come out of the dark; a share of all enemies
## prefers the carrier (EnemyDecoy, co-op: one carries, the others escort).
## A player sets it in within LANTERN_TIME -> bonus chest. After that the socket calls the lantern
## home by itself (no bonus), so the room can always be finished (failure never costs the run).

const LANTERN_COLOR := Color("#ffd166")
const CHASER_META := &"lantern_rolled"

var lantern: SoulLantern = null
var socket: LanternSocket = null

var _elapsed := 0.0
var _wave_sent := false
var _chasers: Array[Enemy] = []
var _vision_radius := -1.0
var _dimmed_torches: Array[Node2D] = []


func can_host() -> bool:
	var start := _lantern_tile()
	var goal := _socket_tile()
	return start != VariantSpots.INVALID and goal != VariantSpots.INVALID and start != goal


func _on_attach() -> void:
	var goal := _socket_tile()
	_free.erase(goal)
	socket = LanternSocket.new()
	socket.name = "LanternSocket"
	socket.position = _floor_point(goal)
	socket.build()
	add_child(socket)
	var start := _lantern_tile()
	_free.erase(start)
	lantern = SoulLantern.new()
	lantern.name = "SoulLantern"
	lantern.position = _floor_point(start)
	lantern.socket = socket
	lantern.build()
	add_child(lantern)
	lantern.picked_up.connect(_on_picked_up)
	lantern.put_down.connect(_on_put_down)
	lantern.inserted.connect(_on_inserted)


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, LightVariantRules.LANTERN_ROOM_COUNT_FACTOR)


func _on_start() -> void:
	_darken_room()
	socket.show_time_left(LightVariantRules.LANTERN_TIME)
	if lantern.is_carried() and not _wave_sent:
		# Taken before the door shut: the enemies out of the dark come right away.
		send_wave()


func _physics_process(delta: float) -> void:
	if _started and not _finished:
		step(delta)


## One step of the lantern clock (public for tests and tools): time left for the bonus; after
## LANTERN_TIME the socket calls the lantern home.
func step(delta: float) -> void:
	if not _started or _finished or lantern == null or lantern.is_socketed():
		return
	_elapsed += delta
	var open := LightVariantRules.lantern_bonus_open(_elapsed)
	socket.show_time_left(LightVariantRules.LANTERN_TIME - _elapsed if open else -1.0)
	if LightVariantRules.lantern_returns(_elapsed, lantern.is_socketed()):
		_send_home()


func holds_completion() -> bool:
	return LightVariantRules.lantern_holds_room(_started, lantern != null and lantern.is_socketed()) and not _finished


func get_elapsed() -> float:
	return _elapsed


func is_wave_sent() -> bool:
	return _wave_sent


func get_chasers() -> Array[Enemy]:
	var living: Array[Enemy] = []
	for i in _chasers.size():
		var enemy: Variant = _chasers[i]
		if is_instance_valid(enemy) and not (enemy as Enemy).is_dead():
			living.append(enemy)
	return living


## Enemies out of the dark, away from every player (first pickup).
func send_wave() -> Array[Enemy]:
	_wave_sent = true
	var size := LightVariantRules.lantern_wave_size(room.spawner.roll_enemy_count(room.room_index, _rng))
	var enemies := spawn_enemies(_wave_positions(size))
	for enemy in enemies:
		track_enemy(enemy)
	if not enemies.is_empty():
		show_banner(DungeonTexts.t(&"VARIANT_LANTERN_WAVE"), DungeonTexts.t(&"VARIANT_LANTERN_WAVE_SUB"), LOST_COLOR)
	return enemies


func _on_finish() -> void:
	if bonus == Bonus.ACHIEVED:
		spawn_bonus_chests(socket.position + Vector2(0, 40))
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


## One roll per enemy (variant RNG): does it go for the carrier?
func _on_enemy_added(enemy: Enemy) -> void:
	if enemy.has_meta(CHASER_META):
		return
	enemy.set_meta(CHASER_META, true)
	if LightVariantRules.is_chaser(_rng.randf()):
		_chasers.append(enemy)
		if lantern != null and lantern.carrier != null:
			EnemyDecoy.assign(enemy, lantern.carrier)


func _on_picked_up(_lantern: SoulLantern, player: Player) -> void:
	for enemy in get_chasers():
		EnemyDecoy.assign(enemy, player)
	if _started and not _wave_sent:
		send_wave()


func _on_put_down(_lantern: SoulLantern, _player: Player) -> void:
	for enemy in get_chasers():
		EnemyDecoy.clear(enemy)


func _on_inserted(_lantern: SoulLantern, player: Player) -> void:
	for enemy in get_chasers():
		EnemyDecoy.clear(enemy)
	var by_player := player != null and LightVariantRules.lantern_bonus_open(_elapsed)
	set_bonus(by_player)
	if by_player:
		show_banner(DungeonTexts.t(&"VARIANT_LANTERN_PLACED"), DungeonTexts.t(&"VARIANT_LANTERN_PLACED_SUB"), LANTERN_COLOR)
	_restore_light()
	if room != null and is_instance_valid(room):
		room.check_completion()


func _send_home() -> void:
	set_bonus(false)
	show_banner(DungeonTexts.t(&"VARIANT_LANTERN_RETURNS"), DungeonTexts.t(&"VARIANT_LANTERN_RETURNS_SUB"), LOST_COLOR)
	# Decided at once (the room may close), the lantern is seen floating home.
	lantern.send_home()


## The room is dark (vision overlay, like the DungeonManager sets it); the wall torches are out.
func _darken_room() -> void:
	for prop in _wall_torches():
		if prop.visible:
			prop.visible = false
			_dimmed_torches.append(prop)
	var overlay := _overlay()
	if overlay == null:
		return
	_vision_radius = RoomVariants.room_vision_radius(room)
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, _vision_radius * LightVariantRules.LANTERN_ROOM_VISION_FACTOR)


## The lantern is home: the wall torches burn again and the light circle is back.
func _restore_light() -> void:
	for prop in _dimmed_torches:
		if is_instance_valid(prop):
			prop.visible = true
	_dimmed_torches.clear()
	if _vision_radius < 0.0:
		return
	var overlay := _overlay()
	if overlay != null:
		overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, _vision_radius)
	_vision_radius = -1.0


func _overlay() -> VisionOverlay:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay


func _wall_torches() -> Array[Node2D]:
	var torches: Array[Node2D] = []
	var props := room.get_node_or_null("Props") if room != null else null
	if props == null:
		return torches
	for prop in props.get_children():
		if prop is Node2D and String(prop.name).begins_with("Torch"):
			torches.append(prop as Node2D)
	return torches


## Spawn markers at least LANTERN_WAVE_MIN_DISTANCE from every player; the farthest fill up.
func _wave_positions(count: int) -> Array[Vector2]:
	var players := WaveRules.get_player_positions(room)
	var good: Array[Vector2] = []
	var rest: Array[Vector2] = []
	for marker in room.get_spawn_markers():
		var spot := marker.position
		if WaveRules.distance_to_nearest(spot, players) >= LightVariantRules.LANTERN_WAVE_MIN_DISTANCE:
			good.append(spot)
		else:
			rest.append(spot)
	var positions: Array[Vector2] = []
	while positions.size() < count and not good.is_empty():
		positions.append(good.pop_at(_rng.randi_range(0, good.size() - 1)))
	rest.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return WaveRules.distance_to_nearest(a, players) > WaveRules.distance_to_nearest(b, players))
	while positions.size() < count and not rest.is_empty():
		positions.append(rest.pop_front())
	return positions


## A few tiles inside the entrance (the lantern waits for the players).
func _lantern_tile() -> Vector2i:
	var entrance := room.tiles.get_entrance_inside_tile()
	return VariantSpots.nearest_free(_free, entrance + Vector2i(0, -LightVariantRules.LANTERN_ENTRANCE_TILES))


## Right in front of the exit.
func _socket_tile() -> Vector2i:
	var exit := room.tiles.get_exit_inside_tile()
	var start := _lantern_tile()
	var exclude: Array[Vector2i] = [start]
	return VariantSpots.nearest_free(_free, exit + Vector2i(0, 1), exclude)


## Room-local floor point of a tile for objects whose origin is their base line.
static func _floor_point(tile: Vector2i) -> Vector2:
	return RoomTiles.tile_center(tile) + Vector2(0, RoomTiles.TILE_WORLD * 0.25)
