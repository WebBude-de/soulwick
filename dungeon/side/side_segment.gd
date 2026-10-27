class_name SideSegment
extends Node2D
## One gang segment in side view (M5): the world of a SideLayout - rock and ledges (SideTiles), a
## dark back wall, torches, ladders with one-way top steps, crumbling ledges, coins on the jump arcs,
## the golden coin (a double-jump spot), spike trap, slimes and skeletons, the chest in a niche on
## the ladder way, the door at the end - and its own camera (SideCamera). Round 3 (16.10.2026):
## turrets on their mounts (SideTurret, when the layout sets them up), pools (SidePool), spike runs
## as a wave, the biome's dressing (SideDecor), air and pit particles (SideAmbience), biome torches,
## coloured light out of the pits and the doorway the players came through behind the start. It lies far below the dungeon (WORLD_ORIGIN), so rooms and segment never
## meet. Players come in through add_player (PlayerSideMotion takes over their movement) and leave
## through remove_players; their health, shield, gold, weapons and upgrades stay theirs.
## Decisions here (coins, golden coin, door, crumbling ledges, co-op catch-up), looks in the
## children and through signals (each player's moves: SidePlayerFx). Randomness only from the seed handed to setup (multiplayer rule).
## Jump trial (SV2, D-195): the elements of dungeon/side/elements/ - moving platforms and saws run
## on a clock with a phase from the seed (get_element_clock / apply_element_clock for the co-op),
## tilting platforms and bridge pieces are crumbles (get_crumbles, after the plain crumbling ledges),
## springs, lanterns and the hints of shafts; every side enemy kind of SV4 is built through
## SideEnemyKinds.make; the return spot after a pit is the layout's safe spot.
## Obstacle run (Hindernislauf, D-216): the same world for a composed layout (ObstacleRunPlans), with
## the slopes and ramps of its two-way piece (SideSlopes) and the door at the end.

signal finished(segment: SideSegment)
signal coin_collected(player: Player, gold: int)
signal golden_coin_collected(player: Player, gold: int)

## Far below every room (rooms grow north, west and east of room 1).
const WORLD_ORIGIN := Vector2(0, 160000)
## Plan shown when the scene runs on its own (side_segment.tscn in the editor).
const PREVIEW_PLAN := &"crypt_steps"
## Co-op: players start this far apart.
const PLAYER_SPACING := 26.0
const TORCH_SCENE: PackedScene = preload("res://dungeon/environment/decorations/torch.tscn")
const LADDER_TEXTURE: Texture2D = preload("res://art/environment/deco/ladder.png")
const LADDER_TOP_TEXTURE: Texture2D = preload("res://art/environment/deco/ladder_top.png")
## Torch strip per biome (the room torches; the crypt's and the forge's are the warm default).
const TORCH_STRIPS: Dictionary[StringName, String] = {
	&"slime_grotto": "res://art/environment/props/torch_green_4f.png",
	&"shadow_realm": "res://art/environment/props/torch_purple_4f.png",
}
const TORCH_LIGHT_COLORS: Dictionary[StringName, Color] = {
	&"slime_grotto": Color(0.55, 1.0, 0.45),
	&"shadow_realm": Color(0.7, 0.5, 1.0),
}
## Light out of the pits per biome (the forge's glows like embers far below).
const PIT_GLOW: Dictionary[StringName, Color] = {
	&"crypt": Color(0.25, 0.3, 0.6, 0.35),
	&"slime_grotto": Color(0.25, 0.7, 0.25, 0.4),
	&"shadow_realm": Color(0.45, 0.2, 0.75, 0.45),
	&"ember_forge": Color(1.0, 0.4, 0.1, 0.6),
}
## The doorway behind the start: dimmer than the exit, so the way on stays the bright one.
const ENTRANCE_LIGHT := 0.4
## Thickness of a ladder's one-way top step (px).
const LADDER_STEP_DEPTH := 12.0
## Optional platform edge art (SPRITES_V9): 96×16, left / middle / right piece.
const EDGE_ART_PATH := "res://art/environment/deco/platform_edge_%s.png"
const EDGE_COLORS: Dictionary[StringName, Color] = {
	&"crypt": Color(0.55, 0.6, 0.45, 0.9),
	&"slime_grotto": Color(0.35, 0.75, 0.4, 0.95),
	&"shadow_realm": Color(0.6, 0.45, 0.85, 0.9),
	&"ember_forge": Color(1.0, 0.5, 0.2, 0.95),
}

var layout: SideLayout = null
var room_index := 1
## The run's context (chest reward, banners); null in tests and tools.
var context: DungeonContext = null
var camera: SideCamera = null
var is_finished := false
var coins_total := 0
var coins_taken := 0
var gold_earned := 0
var golden_coin_taken := false
## Co-op (online test 16.10.2026): reaching the door does not end the segment for everybody at once;
## the host's NetSide decides (every living player at the door or its timer, CoopRules.SIDE_WAIT_TIME)
## and calls finish(). Off in a solo run: the first player at the door ends it as before.
var door_waits := false

var _players: Array[Player] = []
var _rng := RandomNumberGenerator.new()
var _tiles: TileMapLayer = null
var _coins: Array[SideCoin] = []
var _golden: SideCoin = null
var _ladder_bodies: Array[PhysicsBody2D] = []
var _exit: SideExit = null
var _enemies: Array[SideEnemy] = []
var _spikes: Array[SideSpikes] = []
var _chest: SideChest = null
var _crumbles: Array[SideCrumble] = []
var _turrets: Array[SideTurret] = []
var _pools: Array[SidePool] = []
var _fx: Dictionary[Player, SidePlayerFx] = {}
var _seed := 0
var _movers: Array[SideMover] = []
var _saws: Array[SideSaw] = []
var _springs: Array[SideSpring] = []
var _lanterns: Array[SideLantern] = []
## Co-op: players waiting at the door for the others (set_door_waiting).
var _door_waiting: Array[Player] = []
## Every coin built (also the taken ones: a client's coins go without passing through _coins).
var _all_coins: Array[SideCoin] = []


## Before entering the tree.
func setup(segment_layout: SideLayout, index: int, run_context: DungeonContext, rng_seed: int) -> void:
	layout = segment_layout
	room_index = index
	context = run_context
	_rng.seed = rng_seed
	_seed = rng_seed
	name = "SideSegment"


func _ready() -> void:
	if layout == null:
		# Opened as a scene of its own (editor look): the first crypt plan.
		layout = SidePlans.build(PREVIEW_PLAN)
	var backdrop := SideBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.setup(layout.biome_id, layout.world_size())
	add_child(backdrop)
	_build_tiles()
	_build_edges()
	add_child(SideDecor.create(layout))
	if not layout.slopes.is_empty():
		add_child(SideSlopes.create(self))
	_build_entrance()
	_build_torches()
	_build_ladders()
	_build_crumbles()
	_build_elements()
	_build_pools()
	_build_coins()
	_build_spikes()
	_build_chest()
	_build_exit()
	_build_enemies()
	_build_turrets()
	add_child(SideAmbience.create(layout))
	camera = SideCamera.new()
	camera.name = "Camera"
	camera.segment = self
	add_child(camera)


# --- Players ---

## Brings a player in: feet at the start (co-op: side by side), side motion on.
func add_player(player: Player) -> void:
	if _players.has(player):
		return
	var feet := get_start_feet() + Vector2(layout.run_direction() * -PLAYER_SPACING * _players.size(), 0.0)
	_players.append(player)
	var motion := PlayerSideMotion.attach(player)
	motion.enter(self, feet)
	_fx[player] = SidePlayerFx.attach(player, self)


## Every player back to top-down movement (the caller puts them into the next room); pools let go of
## their slow first.
func remove_players() -> void:
	for pool in _pools:
		if is_instance_valid(pool):
			pool.release_all()
	for player in _players:
		if not is_instance_valid(player) or player.side_motion == null:
			continue
		if _fx.has(player) and is_instance_valid(_fx[player]):
			_fx[player].detach()
		player.side_motion.exit()
	_fx.clear()
	_players.clear()


## The look of a player's moves in this segment (tests).
func get_fx(player: Player) -> SidePlayerFx:
	return _fx.get(player, null)


func get_players() -> Array[Player]:
	var alive: Array[Player] = []
	for player in _players:
		if is_instance_valid(player):
			alive.append(player)
	return alive


## The players the camera keeps in view: every living player in the segment (the camera follows
## their middle; in co-op these are all players of the session). Co-op door wait: the players
## waiting at the door drop out while somebody else still runs, so the stragglers stay in view.
func camera_targets() -> Array[Player]:
	var targets: Array[Player] = []
	var running: Array[Player] = []
	for player in get_players():
		if player.is_alive():
			targets.append(player)
			if not _door_waiting.has(player):
				running.append(player)
	return running if not running.is_empty() else targets


## Co-op: who waits at the door (NetSide, on every machine). While anybody waits, nobody is pulled
## to the foremost player (catch-up): the stragglers have the wait's time to come.
func set_door_waiting(players: Array[Player]) -> void:
	_door_waiting = players.duplicate()


func get_door_waiting() -> Array[Player]:
	return _door_waiting.duplicate()


## Does player stand in the doorway (feet)? The door's own rule (SideExit.is_entered_by).
func is_at_door(player: Player) -> bool:
	return _exit != null and is_instance_valid(player) and _exit.is_entered_by(player.get_feet_position())


## The living player closest to the door (co-op catch-up target).
func get_foremost_player() -> Player:
	var best: Player = null
	var best_progress := -INF
	var direction := layout.run_direction()
	for player in get_players():
		if not player.is_alive():
			continue
		var progress := player.global_position.x * direction
		if progress > best_progress:
			best_progress = progress
			best = player
	return best


func make_camera_current() -> void:
	if camera == null:
		return
	var players := get_players()
	if not players.is_empty():
		var own := players[0].get_node_or_null("Camera2D") as Camera2D
		if own != null:
			camera.zoom = own.zoom
	camera.make_current()
	camera.snap()


# --- Queries for PlayerSideMotion ---

func get_run_direction() -> float:
	return layout.run_direction()


func get_start_feet() -> Vector2:
	return to_global(SideLayout.feet_of(layout.start))


func get_door_feet() -> Vector2:
	return to_global(SideLayout.feet_of(layout.door))


func get_kill_y() -> float:
	return global_position.y + layout.kill_y()


## Climbable rectangle (global) of the ladder at feet, empty Rect2 if none.
func ladder_rect_at(feet: Vector2) -> Rect2:
	var rect := layout.ladder_rect_at(to_local(feet))
	return Rect2(rect.position + global_position, rect.size) if rect.has_area() else Rect2()


func get_ladder_bodies() -> Array[PhysicsBody2D]:
	return _ladder_bodies


## The safe landing spot for feet standing here (global): the middle of the stand cell, INF if the
## cell is no safe ground (spikes, ladder step, outside).
func safe_feet_for(feet: Vector2) -> Vector2:
	var cell := SideLayout.cell_at(to_local(feet) + Vector2(0, -4))
	if not layout.is_safe_spot(cell):
		return Vector2.INF
	if layout.is_ladder_top(cell + Vector2i.DOWN):
		return Vector2.INF
	return to_global(SideLayout.feet_of(cell))


# --- Running ---

func _physics_process(delta: float) -> void:
	if is_finished:
		return
	var view := camera.get_view_rect().grow(-8.0) if camera != null else Rect2()
	var players := get_players()
	for crumble in _crumbles:
		crumble.update(players, delta)
	for player in players:
		if not player.is_alive() or player.side_motion == null or not player.side_motion.is_active():
			continue
		var center := player.global_position
		_collect_coins(player, center)
		if _exit != null:
			var feet := player.get_feet_position()
			if _exit.is_near(feet):
				_exit.open()
			if _exit.is_entered_by(feet) and not door_waits:
				finish()
				return
		_update_catch_up(player, view, delta)


## The group reached the door (decision; the transit fades out).
func finish() -> void:
	if is_finished:
		return
	is_finished = true
	finished.emit(self)


func _collect_coins(player: Player, center: Vector2) -> void:
	for i in range(_coins.size() - 1, -1, -1):
		var coin := _coins[i]
		if not is_instance_valid(coin):
			_coins.remove_at(i)
			continue
		if center.distance_to(coin.global_position) > coin.get_pickup_radius():
			continue
		_coins.remove_at(i)
		var gold := SideRules.coin_gold(room_index, MetaProgression.get_gold_multiplier())
		coins_taken += 1
		gold_earned += gold
		RunManager.add_run_gold(gold)
		coin.take()
		coin_collected.emit(player, gold)
	if _golden != null and is_instance_valid(_golden) and center.distance_to(_golden.global_position) <= _golden.get_pickup_radius():
		var golden := _golden
		_golden = null
		var gold := SideRules.golden_coin_gold(room_index, MetaProgression.get_gold_multiplier())
		golden_coin_taken = true
		gold_earned += gold
		RunManager.add_run_gold(gold)
		golden.take()
		golden_coin_collected.emit(player, gold)
		if context != null and context.ui != null:
			context.ui.show_banner(DungeonTexts.t(&"SIDE_GOLDEN_COIN_TITLE"),
					Loc.t(&"SIDE_GOLDEN_COIN_GOLD", [gold]), UiKit.COLOR_GOLD)


## Co-op: whoever stays outside the view CATCH_UP_TIME seconds is brought to the foremost player.
func _update_catch_up(player: Player, view: Rect2, delta: float) -> void:
	var motion := player.side_motion
	if not view.has_area() or view.has_point(player.global_position) or motion.is_in_pit() or not _door_waiting.is_empty():
		motion.outside_time = 0.0
		return
	motion.outside_time += delta
	if motion.outside_time < SideRules.CATCH_UP_TIME:
		return
	var leader := get_foremost_player()
	if leader == null or leader == player:
		motion.outside_time = 0.0
		return
	var feet := leader.side_motion.get_safe_feet() if leader.side_motion != null else Vector2.INF
	motion.place_at(feet if feet != Vector2.INF else leader.get_feet_position())


# --- Building ---

func _build_tiles() -> void:
	_tiles = TileMapLayer.new()
	_tiles.name = "Tiles"
	_tiles.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_tiles.z_index = -5
	add_child(_tiles)
	SideTiles.paint(_tiles, layout, layout.biome_id)


## Top edges of every walkable surface: delivered edge art or a thin biome-coloured strip.
func _build_edges() -> void:
	var edges := _Edges.new()
	edges.name = "Edges"
	edges.layout = layout
	edges.color = EDGE_COLORS.get(layout.biome_id, EDGE_COLORS[&"crypt"])
	var art_path := EDGE_ART_PATH % layout.biome_id
	edges.art = load(art_path) as Texture2D if ResourceLoader.exists(art_path) else null
	edges.z_index = -4
	add_child(edges)
	var abyss := _Abyss.new()
	abyss.name = "Abyss"
	abyss.layout = layout
	abyss.glow = PIT_GLOW.get(layout.biome_id, PIT_GLOW[&"crypt"])
	abyss.z_index = -6
	add_child(abyss)


func _build_torches() -> void:
	var strip_path: String = TORCH_STRIPS.get(layout.biome_id, "")
	var strip := load(strip_path) as Texture2D if not strip_path.is_empty() and ResourceLoader.exists(strip_path) else null
	for cell in layout.torches:
		var torch := TORCH_SCENE.instantiate() as Node2D
		if strip != null:
			torch.set(&"strip", strip)
		var light := torch.get_node_or_null(^"Light") as LightSource
		if light != null and TORCH_LIGHT_COLORS.has(layout.biome_id):
			light.color = TORCH_LIGHT_COLORS[layout.biome_id]
		torch.position = SideLayout.cell_origin(cell)
		add_child(torch)


## The doorway the players came through, open behind the start (dim; the exit is the bright one).
func _build_entrance() -> void:
	var entrance := Node2D.new()
	entrance.name = "Entrance"
	entrance.z_index = -3
	entrance.position = SideLayout.feet_of(layout.start)
	add_child(entrance)
	for biome in [layout.biome_id, SideExit.FALLBACK_BIOME]:
		var path := SideExit.DOORS_DIR + "door_frame_%s.png" % biome
		if not ResourceLoader.exists(path):
			continue
		var frame_texture := load(path) as Texture2D
		var frame := Sprite2D.new()
		frame.name = "Frame"
		frame.texture = frame_texture
		frame.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		frame.offset = SpriteStrip.pivot_offset(Vector2i(frame_texture.get_size()), SideExit.FRAME_PIVOT)
		frame.modulate = Color(0.75, 0.75, 0.8)
		entrance.add_child(frame)
		break
	var light := LightSource.new()
	light.name = "Glow"
	light.radius = 120.0
	light.intensity = ENTRANCE_LIGHT
	light.flicker = 0.04
	light.position = Vector2(0, -48)
	entrance.add_child(light)


## Pools in the floor (plan "w"): slow running on every machine (SidePool).
func _build_pools() -> void:
	for run in layout.pools:
		var pool := SidePool.new()
		pool.name = "Pool%d_%d" % [run.x, run.z]
		pool.cells = run.y - run.x + 1
		pool.biome_id = layout.biome_id
		pool.segment = self
		pool.position = SideLayout.cell_origin(Vector2i(run.x, run.z))
		add_child(pool)
		_pools.append(pool)


func get_pools() -> Array[SidePool]:
	return _pools


## Turrets on their mounts (plan "T") when the layout sets them up (SideRules.TURRET_CHANCE).
func _build_turrets() -> void:
	if not layout.turrets_enabled:
		return
	for cell in layout.turrets:
		var normal := layout.turret_normal(cell)
		if normal == Vector2i.ZERO:
			continue
		var turret := SideTurret.new()
		turret.name = "Turret%d_%d" % [cell.x, cell.y]
		turret.setup(layout.biome_id, room_index, self, normal)
		# Mount point: the middle of the cell's side that touches the rock.
		turret.position = SideLayout.cell_center(cell) - Vector2(normal) * SideRules.TILE * 0.5
		add_child(turret)
		_turrets.append(turret)


## Every turret built here, in build order (also the destroyed ones: NetSide counts by index).
func get_turrets() -> Array[SideTurret]:
	return _turrets


func get_spikes() -> Array[SideSpikes]:
	return _spikes


func _build_ladders() -> void:
	for column in layout.ladders:
		var span: Vector2i = layout.ladders[column]
		for row in range(span.x, span.y + 1):
			var rung := Sprite2D.new()
			rung.texture = LADDER_TEXTURE
			rung.centered = false
			rung.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
			rung.position = SideLayout.cell_origin(Vector2i(column, row))
			rung.z_index = -3
			add_child(rung)
		var top := Sprite2D.new()
		top.texture = LADDER_TOP_TEXTURE
		top.centered = false
		top.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		top.position = SideLayout.cell_origin(Vector2i(column, span.x)) - Vector2(0, LADDER_TOP_TEXTURE.get_height() * SpriteStrip.PIXEL_SCALE)
		top.z_index = -3
		add_child(top)
		# The top step: one-way, so a climber passes and a walker stands on it.
		var step := StaticBody2D.new()
		step.name = "LadderStep%d" % column
		step.collision_layer = PhysicsLayers.WORLD
		step.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = Vector2(SideRules.TILE, LADDER_STEP_DEPTH)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.one_way_collision = true
		collision.position = Vector2(SideRules.TILE * 0.5, LADDER_STEP_DEPTH * 0.5)
		step.add_child(collision)
		step.position = SideLayout.cell_origin(Vector2i(column, span.x))
		add_child(step)
		_ladder_bodies.append(step)


func _build_crumbles() -> void:
	for run in layout.crumbles:
		var crumble := SideCrumble.new()
		crumble.name = "Crumble%d_%d" % [run.x, run.z]
		crumble.cells = run.y - run.x + 1
		crumble.biome_id = layout.biome_id
		crumble.position = SideLayout.cell_origin(Vector2i(run.x, run.z))
		add_child(crumble)
		_crumbles.append(crumble)


## Crumbling ledges, then tilting platforms, then bridge pieces (build order = NetSide index).
func get_crumbles() -> Array[SideCrumble]:
	return _crumbles


## The jump trial's elements (SV2): moving platforms, tilting platforms and bridge pieces (as
## crumbles), springs, saws, lanterns and the drawn hints. Platform and saw phases come from the
## segment seed and the build index (no draw from _rng, so the enemies keep their seeds).
func _build_elements() -> void:
	for run in layout.tilts:
		_add_crumble(SideTilt.new(), "Tilt", run)
	for run in layout.bridges:
		for column in range(run.x, run.y + 1):
			_add_crumble(SideBridge.new(), "Bridge", Vector3i(column, column, run.z))
	var index := 0
	for plan_mover in layout.movers:
		var mover := SideMover.new()
		mover.setup(plan_mover, layout.biome_id, _seed, index)
		add_child(mover)
		_movers.append(mover)
		index += 1
	for plan_saw in layout.saws:
		var saw := SideSaw.new()
		saw.setup(plan_saw, _seed, index)
		saw.position = SideLayout.cell_center(plan_saw.cell)
		add_child(saw)
		_saws.append(saw)
		index += 1
	for cell in layout.springs:
		var spring := SideSpring.new()
		spring.name = "Spring%d_%d" % [cell.x, cell.y]
		spring.segment = self
		spring.position = SideLayout.feet_of(cell)
		add_child(spring)
		_springs.append(spring)
	for cell in layout.lanterns:
		var lantern := SideLantern.new()
		lantern.name = "Lantern%d_%d" % [cell.x, cell.y]
		lantern.segment = self
		lantern.position = SideLayout.feet_of(cell)
		add_child(lantern)
		_lanterns.append(lantern)
	if not layout.shafts.is_empty():
		add_child(SideElementHints.create(layout))


func _add_crumble(crumble: SideCrumble, prefix: String, run: Vector3i) -> void:
	crumble.name = "%s%d_%d" % [prefix, run.x, run.z]
	crumble.cells = run.y - run.x + 1
	crumble.biome_id = layout.biome_id
	crumble.position = SideLayout.cell_origin(Vector2i(run.x, run.z))
	add_child(crumble)
	_crumbles.append(crumble)


func get_movers() -> Array[SideMover]:
	return _movers


func get_saws() -> Array[SideSaw]:
	return _saws


func get_springs() -> Array[SideSpring]:
	return _springs


func get_lanterns() -> Array[SideLantern]:
	return _lanterns


## Clock of the moving platforms and saws (seconds since the segment began; 0 without any). Co-op
## hook: the host sends it now and then, a client applies it (apply_element_clock).
func get_element_clock() -> float:
	if not _movers.is_empty():
		return _movers[0].clock
	if not _saws.is_empty():
		return _saws[0].clock
	return 0.0


## The host's clock on a client (NetSide): every platform and saw at the host's place.
func apply_element_clock(time: float) -> void:
	for mover in _movers:
		if is_instance_valid(mover):
			mover.apply_clock(time)
	for saw in _saws:
		if is_instance_valid(saw):
			saw.apply_clock(time)


## The moving platform whose top the feet (global) stand on, or null.
func mover_under(feet: Vector2) -> SideMover:
	for mover in _movers:
		if is_instance_valid(mover) and mover.carries(feet):
			return mover
	return null


func _build_coins() -> void:
	for cell in layout.coins:
		var coin := SideCoin.new()
		coin.position = SideLayout.cell_center(cell)
		add_child(coin)
		_coins.append(coin)
		_all_coins.append(coin)
	coins_total = _coins.size()
	if layout.golden_coin.x >= 0:
		_golden = SideCoin.new()
		_golden.golden = true
		_golden.name = "GoldenCoin"
		_golden.position = SideLayout.cell_center(layout.golden_coin)
		add_child(_golden)


## Spike traps; the traps of one run fire as a wave (one draw per run, SideRules.SPIKE_WAVE_STEP).
func _build_spikes() -> void:
	var offset := 0.0
	var previous := Vector2i(-10, -10)
	var in_run := 0
	for cell in layout.spikes:
		if cell == previous + Vector2i.RIGHT:
			in_run += 1
		else:
			in_run = 0
			offset = _rng.randf_range(0.4, SideSpikes.IDLE_TIME)
		previous = cell
		var spikes := SideSpikes.new()
		spikes.position = SideLayout.feet_of(cell)
		spikes.setup(offset + SideRules.SPIKE_WAVE_STEP * in_run)
		add_child(spikes)
		_spikes.append(spikes)


## The chest only on the ladder way (SideRules.has_chest, layout.chest_enabled); otherwise its niche
## stays empty.
func _build_chest() -> void:
	if layout.chest.x < 0 or not layout.chest_enabled:
		return
	_chest = SideChest.new()
	_chest.name = "Chest"
	_chest.segment_context = context
	_chest.position = SideLayout.feet_of(layout.chest)
	add_child(_chest)


func _build_exit() -> void:
	_exit = SideExit.new()
	_exit.name = "Exit"
	_exit.biome_id = layout.biome_id
	_exit.position = SideLayout.feet_of(layout.door)
	add_child(_exit)


## Every side enemy of the plan (SideLayout.enemy_cells: slimes, skeletons, then the SV4 kinds),
## one draw from the segment RNG each, in this order (old seeds keep their enemies; build order =
## NetSide index).
func _build_enemies() -> void:
	for entry in layout.enemy_cells():
		var enemy := SideEnemyKinds.make(entry.z as SideEnemy.Kind, room_index, self, _rng.randi())
		enemy.position = SideLayout.feet_of(Vector2i(entry.x, entry.y))
		add_child(enemy)
		_enemies.append(enemy)


func get_enemies() -> Array[SideEnemy]:
	var alive: Array[SideEnemy] = []
	for enemy in _enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			alive.append(enemy)
	return alive


func get_coins_left() -> int:
	return _coins.size()


## Coins taken so far, on every machine (a client's go through NetSide).
func count_taken_coins() -> int:
	var taken := 0
	for coin in _all_coins:
		if not is_instance_valid(coin) or coin.is_taken:
			taken += 1
	return taken


## Enemies beaten so far (dead or gone).
func count_defeated_enemies() -> int:
	var count := 0
	for enemy in _enemies:
		if not is_instance_valid(enemy) or enemy.is_dead():
			count += 1
	return count


func has_golden_coin() -> bool:
	return _golden != null and is_instance_valid(_golden)


func get_chest() -> SideChest:
	return _chest


## Darkness rising out of the pits (they fall into nothing), lit faintly in the biome's colour from
## far below; both in hard bands (D-218).
class _Abyss:
	extends Node2D
	const DEPTH := 3.0
	const BANDS := 6
	const GLOW_BANDS := 4
	var layout: SideLayout = null
	var glow := Color(0, 0, 0, 0)

	func _draw() -> void:
		var tile := SideRules.TILE
		var top := (layout.size.y - 1.5) * tile
		var bottom := (layout.size.y + DEPTH) * tile
		var clear := Color(0, 0, 0, 0)
		var dark := Color(0.0, 0.0, 0.02, 0.95)
		for column in layout.pit_columns():
			var x := column * tile
			SidePixels.bands(self, Rect2(x, top, tile, bottom - top), clear, dark, BANDS)
			if glow.a > 0.0:
				var lit := (layout.size.y + 0.4) * tile
				var faint := Color(glow, 0.0)
				SidePixels.bands(self, Rect2(x, lit - tile * 1.2, tile, bottom - lit + tile * 1.2), faint, glow, GLOW_BANDS)


## Surface edges (placeholder until platform_edge_<biome> exists).
class _Edges:
	extends Node2D
	var layout: SideLayout = null
	var color := Color.WHITE
	var art: Texture2D = null

	func _draw() -> void:
		var tile := SideRules.TILE
		for row in range(1, layout.size.y):
			for column in range(1, layout.size.x - 1):
				var cell := Vector2i(column, row)
				if not layout.is_blocking(cell) or layout.is_blocking(cell + Vector2i.UP) or layout.is_element_ground(cell):
					continue
				# Under a slope the slope's art carries the edge (SideSlopes).
				if layout.is_slope(cell + Vector2i.UP):
					continue
				var left := layout.is_blocking(cell + Vector2i.LEFT) and not layout.is_blocking(cell + Vector2i(-1, -1))
				var right := layout.is_blocking(cell + Vector2i.RIGHT) and not layout.is_blocking(cell + Vector2i(1, -1))
				var origin := Vector2(column * tile, row * tile)
				if art != null:
					var piece := 1 if left and right else (0 if right else (2 if left else 1))
					draw_texture_rect_region(art, Rect2(origin + Vector2(0, -8), Vector2(tile, 32)), Rect2(piece * 32, 0, 32, 16))
					continue
				var inset_left := 0.0 if left else 6.0
				var inset_right := 0.0 if right else 6.0
				draw_rect(Rect2(origin.x + inset_left, origin.y - 2.0, tile - inset_left - inset_right, 6.0), color)
				draw_rect(Rect2(origin.x + inset_left, origin.y + 4.0, tile - inset_left - inset_right, 2.0), color * Color(0.6, 0.6, 0.6, 0.8))
