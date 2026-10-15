class_name SideSegment
extends Node2D
## One gang segment in side view (M5): the world of a SideLayout - rock and ledges (SideTiles), a
## dark back wall, torches, ladders with one-way top steps, crumbling ledges, coins on the jump arcs,
## the golden coin (a double-jump spot), spike trap, slimes and skeletons, the chest in a niche on
## the ladder way, the door at the end - and its own camera (SideCamera). It lies far below the dungeon (WORLD_ORIGIN), so rooms and segment never
## meet. Players come in through add_player (PlayerSideMotion takes over their movement) and leave
## through remove_players; their health, shield, gold, weapons and upgrades stay theirs.
## Decisions here (coins, golden coin, door, crumbling ledges, co-op catch-up), looks in the
## children and through signals (each player's moves: SidePlayerFx). Randomness only from the seed handed to setup (multiplayer rule).

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
var _fx: Dictionary[Player, SidePlayerFx] = {}


## Before entering the tree.
func setup(segment_layout: SideLayout, index: int, run_context: DungeonContext, rng_seed: int) -> void:
	layout = segment_layout
	room_index = index
	context = run_context
	_rng.seed = rng_seed
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
	_build_torches()
	_build_ladders()
	_build_crumbles()
	_build_coins()
	_build_spikes()
	_build_chest()
	_build_exit()
	_build_enemies()
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


## Every player back to top-down movement (the caller puts them into the next room).
func remove_players() -> void:
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
## their middle; in co-op these are all players of the session).
func camera_targets() -> Array[Player]:
	var targets: Array[Player] = []
	for player in get_players():
		if player.is_alive():
			targets.append(player)
	return targets


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
	if not layout.is_standable(cell) or layout.spikes.has(cell):
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
			if _exit.is_entered_by(feet):
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
	if not view.has_area() or view.has_point(player.global_position) or motion.is_in_pit():
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
	abyss.z_index = -6
	add_child(abyss)


func _build_torches() -> void:
	for cell in layout.torches:
		var torch := TORCH_SCENE.instantiate() as Node2D
		torch.position = SideLayout.cell_origin(cell)
		add_child(torch)


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


func get_crumbles() -> Array[SideCrumble]:
	return _crumbles


func _build_coins() -> void:
	for cell in layout.coins:
		var coin := SideCoin.new()
		coin.position = SideLayout.cell_center(cell)
		add_child(coin)
		_coins.append(coin)
	coins_total = _coins.size()
	if layout.golden_coin.x >= 0:
		_golden = SideCoin.new()
		_golden.golden = true
		_golden.name = "GoldenCoin"
		_golden.position = SideLayout.cell_center(layout.golden_coin)
		add_child(_golden)


func _build_spikes() -> void:
	for cell in layout.spikes:
		var spikes := SideSpikes.new()
		spikes.position = SideLayout.feet_of(cell)
		spikes.setup(_rng.randf_range(0.4, SideSpikes.IDLE_TIME))
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


func _build_enemies() -> void:
	var cells: Array[Vector2i] = []
	cells.append_array(layout.slimes)
	cells.append_array(layout.skeletons)
	for cell in cells:
		var enemy := SideEnemy.new()
		var kind := SideEnemy.Kind.SLIME if layout.slimes.has(cell) else SideEnemy.Kind.SKELETON
		enemy.setup(kind, room_index, self, _rng.randi())
		enemy.position = SideLayout.feet_of(cell)
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


func has_golden_coin() -> bool:
	return _golden != null and is_instance_valid(_golden)


func get_chest() -> SideChest:
	return _chest


## Darkness rising out of the pits (they fall into nothing).
class _Abyss:
	extends Node2D
	const DEPTH := 3.0
	var layout: SideLayout = null

	func _draw() -> void:
		var tile := SideRules.TILE
		var top := (layout.size.y - 1.5) * tile
		var bottom := (layout.size.y + DEPTH) * tile
		var clear := Color(0, 0, 0, 0)
		var dark := Color(0.0, 0.0, 0.02, 0.95)
		for column in layout.pit_columns():
			var x := column * tile
			draw_polygon(PackedVector2Array([Vector2(x, top), Vector2(x + tile, top), Vector2(x + tile, bottom), Vector2(x, bottom)]),
					PackedColorArray([clear, clear, dark, dark]))


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
				if not layout.is_blocking(cell) or layout.is_blocking(cell + Vector2i.UP) or layout.is_crumble(cell):
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
				draw_rect(Rect2(origin.x + inset_left, origin.y - 2.0, tile - inset_left - inset_right, 5.0), color)
				draw_rect(Rect2(origin.x + inset_left, origin.y + 3.0, tile - inset_left - inset_right, 2.0), color * Color(0.6, 0.6, 0.6, 0.8))
