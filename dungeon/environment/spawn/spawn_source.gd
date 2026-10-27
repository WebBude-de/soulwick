class_name SpawnSource
extends Node2D
## One place enemies come out of (R2, design answer 03_gegner_auftritt.md): grave (crypt),
## sarcophagus (elites, champions), puddle (slime grotto), floor rift (shadow realm), lava vent
## (ember forge), wall gate (arenas) or wall rift. Look and sound only: SpawnSources decides which
## source a push uses (SpawnSourceRules), this node shows it -
##   rest:    a faint glimmer, so players see the sources before the fight,
##   warning: SpawnSourceRules.WARN_TIME of light, sound and animation,
##   opening: the enemy comes out (Enemy.begin_emerge; wall sources move it onto the floor),
##   rest:    the source stays as decoration.
## Art from art/environment/spawn/ (spawn.json: frames 1-2 warning, 3-4 coming out, 5 enemy stands,
## 6 rest; the sarcophagus has 4: closed, warning, lid slides, open - it rests closed, spawn.json
## "Frame 1 bzw. 6"). Gates and wall rifts use the
## arena wall art (WallBreach: enemy_gate_4f / wall_breach_6f). Without art a drawn placeholder.
## Floor sources stand at their pivot (where the enemy appears); wall sources sit on the edge between
## wall and floor tile, local +y pointing into the room. A sarcophagus also has a solid foot behind
## its pivot (SOLID_FOOT), so nobody walks into or behind it.

enum Phase { IDLE, WARN, OPEN, REST }

const ART_DIR := "res://art/environment/spawn/"
## From art/environment/spawn/spawn.json. idle/rest: frame shown before and after use; warn: the
## two warning frames; open: frames while the enemy comes out.
const ART := {
	SpawnSourceRules.Kind.GRAVE: {"file": "spawn_grave_6f.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 28), "idle": 0, "warn": [0, 1], "open": [2, 3, 4], "rest": 5},
	SpawnSourceRules.Kind.SARCOPHAGUS: {"file": "spawn_sarcophagus_4f.png", "frame": Vector2i(32, 40), "pivot": Vector2(16, 38), "idle": 0, "warn": [0, 1], "open": [2, 3], "rest": 0},
	SpawnSourceRules.Kind.PUDDLE: {"file": "spawn_puddle_6f.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 24), "idle": 0, "warn": [0, 1], "open": [2, 3, 4], "rest": 5},
	SpawnSourceRules.Kind.RIFT: {"file": "spawn_rift_6f.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 20), "idle": 0, "warn": [0, 1], "open": [2, 3, 4], "rest": 5},
	SpawnSourceRules.Kind.VENT: {"file": "spawn_vent_6f.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 24), "idle": 0, "warn": [0, 1], "open": [2, 3, 4], "rest": 5},
}
## Colour of glimmer, warning ring and light per kind (design answer: graves glow green, rifts
## violet, vents orange, gates red).
const COLORS := {
	SpawnSourceRules.Kind.GRAVE: Color("7dffa0"),
	SpawnSourceRules.Kind.SARCOPHAGUS: Color("7dffa0"),
	SpawnSourceRules.Kind.PUDDLE: Color("a6f05a"),
	SpawnSourceRules.Kind.RIFT: Color("b07cff"),
	SpawnSourceRules.Kind.VENT: Color("ff8a3a"),
	SpawnSourceRules.Kind.GATE: Color("ff5a3a"),
	SpawnSourceRules.Kind.RIFT_WALL: Color("b07cff"),
}
## Flat sources lie on the floor and draw below everything standing; graves and sarcophagi stand
## and sort by their foot line, a little behind the enemy that rises in front of them.
const FLAT_KINDS: Array[int] = [SpawnSourceRules.Kind.PUDDLE, SpawnSourceRules.Kind.RIFT, SpawnSourceRules.Kind.VENT]
## Characters sort by their body centre (Player.FEET_OFFSET above the feet), so standing art sorts
## that much higher too; a grave by the foot of its stone at the top of the mound (the mound is flat:
## a player standing on it is in front, playtest 15.10.2026 note 21). World px above the pivot
## (TESTWERT).
const STAND_SORT_LIFT := 3.0
const FOOT_ABOVE_PIVOT := {SpawnSourceRules.Kind.GRAVE: 18.0}
## Solid foot (width, depth in world px before the node's own scale; a champion's source is
## bigger): a sarcophagus lies on the floor, its lid is the top face of the art (22x31 art px above
## the pivot), so a player could walk into it and vanish behind it (bug report #a461e6ff). The foot
## covers the lid and ends SOLID_PIVOT_GAP above the pivot: the enemy rises there without a body
## (D-132) and its body (circle up to a quarter radius above its position) stays clear of the foot.
## Graves, puddles, rifts and vents stay walkable. TESTWERTE
const SOLID_FOOT := {SpawnSourceRules.Kind.SARCOPHAGUS: Vector2(44, 44)}
const SOLID_PIVOT_GAP := 12.0
## get_blocked_tile() of a source that took no navigation.
const INVALID_TILE := Vector2i(-9999, -9999)
## Rest glimmer: brightness pulse of the art (no light of its own - the vision overlay draws a
## limited number of lights). TESTWERTE
const GLIMMER_STRENGTH := 0.22
const GLIMMER_PERIOD := 2.6
## Warning light (px, 0-1). TESTWERTE
const WARN_LIGHT_RADIUS := 120.0
const WARN_LIGHT_INTENSITY := 0.8
const OPEN_FLASH_RADIUS := 110.0
const LIGHT_FADE := 0.6
## Warning ring on the floor (px, flattened circle).
const RING_RADIUS := 26.0
const RING_SQUASH := 0.5
## Grate up when an enemy steps out of a gate (s).
const GATE_LIFT_TIME := 0.2
const DUST_COLOR := Color("8a8070")

var kind: int = SpawnSourceRules.Kind.GRAVE
var phase := Phase.IDLE
## Wall side (WallGates.Side / RoomTiles.DoorSide) of a gate or wall rift, -1 for floor sources.
var side := -1
var wall_tile := Vector2i.ZERO
var floor_tile := Vector2i.ZERO
## Room-local floor point the enemy stands on once it is out.
var spot := Vector2.ZERO
## Room-local point where the enemy waits hidden (in the wall for wall sources).
var hold := Vector2.ZERO
## How often the source brought enemies (tests, tools).
var uses := 0
## After the fight: no glimmer any more.
var quiet := false

var _sprite: AnimatedSprite2D = null
var _foot: StaticBody2D = null
## Room tiles whose navigation the foot took (null if it took none) and that tile.
var _foot_tiles: RoomTiles = null
var _foot_tile := Vector2i.ZERO
var _breach: WallBreach = null
var _light: LightSource = null
var _timeline: Tween = null
var _phase_time := 0.0
var _phase_length := 1.0
var _open_frames: Array = []
var _glimmer_seed := 0.0


## A source on the floor at a room-local point (its pivot = where the enemy appears).
static func create_floor(source_kind: int, local_position: Vector2) -> SpawnSource:
	var source := SpawnSource.new()
	source.kind = source_kind
	source.spot = local_position
	source.hold = local_position
	source.position = local_position
	source.floor_tile = RoomTiles.local_to_tile(local_position)
	source.wall_tile = source.floor_tile
	return source


## A gate or wall rift in the wall tile wall, its enemies step onto floor (side: the wall the
## opening sits in, seen from floor).
static func create_wall(source_kind: int, wall_side: int, wall: Vector2i, floor_cell: Vector2i) -> SpawnSource:
	var source := SpawnSource.new()
	source.kind = source_kind
	source.side = wall_side
	source.wall_tile = wall
	source.floor_tile = floor_cell
	source.spot = RoomTiles.tile_center(floor_cell)
	source.hold = RoomTiles.tile_center(wall)
	source.position = (source.spot + source.hold) * 0.5
	return source


static func has_art(source_kind: int) -> bool:
	if SpawnSourceRules.is_wall_kind(source_kind):
		return WallBreach.has_art(WallBreach.Mode.GATE if source_kind == SpawnSourceRules.Kind.GATE else WallBreach.Mode.BREACH)
	return ART.has(source_kind) and ResourceLoader.exists(ART_DIR + String(ART[source_kind]["file"]))


func _ready() -> void:
	name = "%s_%d_%d" % [SpawnSourceRules.kind_id(kind), wall_tile.x, wall_tile.y] if is_wall_source() else "%s_%d_%d" % [SpawnSourceRules.kind_id(kind), roundi(spot.x), roundi(spot.y)]
	_glimmer_seed = fposmod(spot.x * 0.013 + spot.y * 0.007, 1.0) * TAU
	if is_wall_source():
		_build_wall()
	else:
		if FLAT_KINDS.has(kind):
			z_index = -1
		else:
			# Sorts at the foot line of the art (sort_lift); everything drawn moves back down. Times
			# the node's scale (a champion's bigger source), so the art's pivot stays on the spot
			# the enemy rises from.
			position.y -= sort_lift() * scale.y
		_build_sprite()
		_build_foot()
	_show_frame()


## A mode shows the opening itself (rifts mode: the rift in the wall is the opening): the wall
## stays whole, enemies still step out here. Pure optics.
func hide_opening() -> void:
	if _breach != null:
		_breach.visible = false
	if _sprite != null:
		_sprite.visible = false


func is_opening_hidden() -> bool:
	return (_breach == null or not _breach.visible) and (_sprite == null or not _sprite.visible)


func is_wall_source() -> bool:
	return SpawnSourceRules.is_wall_kind(kind)


func get_color() -> Color:
	return COLORS.get(kind, Color.WHITE)


## How enemies come out of this source (Enemy.begin_emerge).
func get_emerge_style() -> Enemy.Emerge:
	if is_wall_source():
		return Enemy.Emerge.STEP
	return Enemy.Emerge.JUMP if kind == SpawnSourceRules.Kind.PUDDLE else Enemy.Emerge.RISE


## Group for spreading a push over several walls (SpawnSourceRules.pick): the wall side, -1 on the floor.
func get_group() -> int:
	return side if is_wall_source() else -1


## Is the source busy with a push right now (warning or opening)?
func is_active() -> bool:
	return phase == Phase.WARN or phase == Phase.OPEN


## Schedules one push of count enemies: warning after start_delay, one opening per enemy
## (SpawnSourceRules timing), then rest. A running push of this source is replaced.
func play(start_delay: float, count: int) -> void:
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	uses += 1
	_timeline = create_tween()
	if start_delay > 0.0:
		_timeline.tween_interval(start_delay)
	_timeline.tween_callback(warn)
	_timeline.tween_interval(SpawnSourceRules.WARN_TIME)
	for i in maxi(1, count):
		_timeline.tween_callback(open.bind(i == 0))
		if i < count - 1:
			_timeline.tween_interval(SpawnSourceRules.SAME_SOURCE_DELAY)
	_timeline.tween_interval(SpawnSourceRules.EMERGE_TIME)
	_timeline.tween_callback(settle)


## The tween of the current push (null before the first one). Tests and tools pause it and step it
## by hand (Tween.custom_step), so the timeline does not depend on the frame times of the machine.
func get_timeline() -> Tween:
	return _timeline


## Puts enemy (already in the tree) into this source: hidden at the hold point for wait seconds,
## then it comes out (place: its turn at this source, queued enemies stand a little apart).
## room: the node the spot coordinates belong to (the SpawnSources node at the room origin).
func bring(enemy: Enemy, room: Node2D, wait: float, place: int) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
		return
	var out := spot
	if not is_wall_source():
		out += SpawnSourceRules.queue_offset(place)
	enemy.global_position = room.to_global(hold if is_wall_source() else out)
	enemy.begin_emerge(wait, SpawnSourceRules.EMERGE_TIME, get_emerge_style())
	if is_wall_source():
		var tween := enemy.create_tween()
		tween.tween_interval(maxf(0.0, wait))
		tween.tween_property(enemy, "global_position", room.to_global(out), SpawnSourceRules.EMERGE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Warning: light, sound and the warning frames (grate rattles, wall cracks).
func warn() -> void:
	_set_phase(Phase.WARN, SpawnSourceRules.WARN_TIME)
	Sfx.play_at(self, SpawnSourceRules.sound_for(kind), get_pivot_global(), -3.0)
	if _breach != null:
		if kind == SpawnSourceRules.Kind.GATE:
			_breach.rattle(SpawnSourceRules.WARN_TIME)
		else:
			_breach.telegraph(SpawnSourceRules.WARN_TIME)
		return
	_ensure_light()
	_light.intensity = 0.15
	_light.radius = WARN_LIGHT_RADIUS * 0.6
	var tween := _light.create_tween().set_parallel()
	tween.tween_property(_light, "intensity", WARN_LIGHT_INTENSITY, SpawnSourceRules.WARN_TIME)
	tween.tween_property(_light, "radius", WARN_LIGHT_RADIUS, SpawnSourceRules.WARN_TIME)


## An enemy comes out: opening frames, dust (first: the gate goes up / the wall breaks).
func open(first: bool) -> void:
	_set_phase(Phase.OPEN, SpawnSourceRules.EMERGE_TIME)
	if _breach != null:
		if kind == SpawnSourceRules.Kind.GATE:
			_breach.lift(GATE_LIFT_TIME)
		_breach.burst(first)
		return
	Burst.spawn(self, get_pivot_global(), DUST_COLOR, 10, 80.0, 0.5, 3.0)
	Burst.spawn(self, get_pivot_global(), get_color(), 6, 60.0, 0.6, 2.5)
	if first:
		LightSource.flash(self, get_pivot_global(), OPEN_FLASH_RADIUS, 0.3)


## Rest after a push: rest frame, the light fades, the grate goes down.
func settle() -> void:
	_set_phase(Phase.REST, 1.0)
	if _breach != null:
		_breach.settle()
	_fade_light()


## The room is cleared: the source stays as decoration without glimmer.
func go_quiet() -> void:
	quiet = true
	if not is_active():
		_fade_light()
	_show_frame()


func _set_phase(value: Phase, length: float) -> void:
	phase = value
	_phase_time = 0.0
	_phase_length = maxf(0.05, length)
	_show_frame()
	queue_redraw()


func _process(delta: float) -> void:
	_phase_time += delta
	_show_frame()
	if phase == Phase.WARN or (phase == Phase.IDLE and _sprite == null and _breach == null):
		queue_redraw()


## Frame and brightness of the art for the current phase.
func _show_frame() -> void:
	if _sprite == null:
		return
	var art: Dictionary = ART[kind]
	var t := clampf(_phase_time / _phase_length, 0.0, 1.0)
	var brightness := 1.0
	match phase:
		Phase.IDLE:
			_sprite.frame = art["idle"]
			brightness += _glimmer()
		Phase.WARN:
			var warn_frames: Array = art["warn"]
			# Blinks between the two warning frames, then stays on the bright one.
			var blink := t < 0.5 and fmod(_phase_time, 0.24) < 0.12
			_sprite.frame = warn_frames[0] if blink else warn_frames[1]
			brightness += 0.35 * t
		Phase.OPEN:
			var frames: Array = art["open"]
			_sprite.frame = frames[mini(frames.size() - 1, floori(t * frames.size()))]
			brightness += 0.3
		Phase.REST:
			_sprite.frame = art["rest"]
			if not quiet:
				brightness += _glimmer() * 0.6
	_sprite.modulate = Color(brightness, brightness, brightness)


func _glimmer() -> float:
	if quiet:
		return 0.0
	var t := Time.get_ticks_msec() / 1000.0
	return GLIMMER_STRENGTH * (0.5 + 0.5 * sin(t * TAU / GLIMMER_PERIOD + _glimmer_seed))


func _build_sprite() -> void:
	if not has_art(kind):
		return
	var art: Dictionary = ART[kind]
	var frame_size: Vector2i = art["frame"]
	var texture := load(ART_DIR + String(art["file"])) as Texture2D
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Art"
	_sprite.sprite_frames = SpriteStrip.make_frames(texture, frame_size, 6.0, false)
	_sprite.offset = SpriteStrip.pivot_offset(frame_size, art["pivot"])
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	if not FLAT_KINDS.has(kind):
		_sprite.position.y = sort_lift()
	add_child(_sprite)


## How far above its pivot a standing source sorts (world px): a hair behind an enemy rising on the
## pivot, at the foot line of the stone for graves. Zero for flat and wall sources.
func sort_lift() -> float:
	if is_wall_source() or FLAT_KINDS.has(kind):
		return 0.0
	return Player.FEET_OFFSET.y + float(FOOT_ABOVE_PIVOT.get(kind, 0.0)) + STAND_SORT_LIFT


## The pivot (where the enemy appears) in global coordinates.
func get_pivot_global() -> Vector2:
	return to_global(Vector2(0.0, sort_lift()))


## Does this source block walking (SOLID_FOOT)?
func is_solid() -> bool:
	return _foot != null and is_instance_valid(_foot)


## Centre of the solid foot in own coordinates: SOLID_PIVOT_GAP and half its depth above the pivot.
func get_foot_center() -> Vector2:
	var size: Vector2 = SOLID_FOOT.get(kind, Vector2.ZERO)
	return Vector2(0.0, sort_lift() - SOLID_PIVOT_GAP - size.y * 0.5)


## Room tile whose navigation the foot took (D-115), INVALID_TILE if none.
func get_blocked_tile() -> Vector2i:
	return _foot_tile if _foot_tiles != null else INVALID_TILE


## The solid foot of a standing source (SOLID_FOOT): a static body like a DecoProp's, a drop shadow
## at the foot line and no navigation on the room tile under it. Same on every peer (plan or the
## champion's spot, no randomness).
func _build_foot() -> void:
	var size: Vector2 = SOLID_FOOT.get(kind, Vector2.ZERO)
	if size == Vector2.ZERO:
		return
	_foot = StaticBody2D.new()
	_foot.name = "Foot"
	_foot.collision_layer = PhysicsLayers.WORLD
	_foot.collision_mask = 0
	_foot.position = get_foot_center()
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_foot.add_child(collision)
	add_child(_foot)
	DropShadow.attach(self, size.x * 0.4, sort_lift() - 2.0)
	_block_navigation()


## Takes the navigation off the room tile under the foot's centre, so enemies path around it like
## around a solid prop (D-115); given back when the source leaves. Only a free floor tile and never
## the one its enemies rise on (they would start in a hole of the navigation); only a tile this
## source blocked itself is given back. Nothing outside a room (tests).
func _block_navigation() -> void:
	var room := _room_node()
	if room == null:
		return
	var tiles := room.get_node(^"Tiles") as RoomTiles
	var tile := RoomTiles.local_to_tile(room.to_local(to_global(get_foot_center())))
	if tile == RoomTiles.local_to_tile(room.to_local(get_pivot_global())):
		return
	if tiles.is_navigation_blocked(tile) or not tiles.is_walkable(tile):
		return
	tiles.set_navigation_blocked(tile, true)
	_foot_tiles = tiles
	_foot_tile = tile
	tree_exiting.connect(_free_navigation, CONNECT_ONE_SHOT)


func _free_navigation() -> void:
	if _foot_tiles != null and is_instance_valid(_foot_tiles) and not _foot_tiles.is_queued_for_deletion():
		_foot_tiles.set_navigation_blocked(_foot_tile, false)
	_foot_tiles = null


func _build_wall() -> void:
	_breach = WallBreach.new()
	_breach.name = "Opening"
	add_child(_breach)
	var inward := -Vector2(RoomTiles.SIDE_DIRECTIONS[side]) if side >= 0 else Vector2.DOWN
	var mode := WallBreach.Mode.GATE if kind == SpawnSourceRules.Kind.GATE else WallBreach.Mode.BREACH
	_breach.setup(mode, inward, wall_tile.x * 73 + wall_tile.y * 31, _cave_biome())


## Biome of the room when its walls are cave rock (the breach breaks a rock front), else empty.
func _cave_biome() -> StringName:
	var room := _room_node()
	if room == null:
		return &""
	var tiles := room.get_node(^"Tiles") as RoomTiles
	# The room may still hold its paint back (staged build): the look it will have.
	if tiles.tile_set != null and tiles.is_terrain_planned() and tiles.get_planned_look() == RockTerrain.Look.CAVE:
		return WallAutotile.biome_of(tiles.tile_set)
	return &""


## The nearest ancestor holding the room's RoomTiles as "Tiles" (the room), null outside a room.
func _room_node() -> Node2D:
	var node := get_parent()
	while node != null:
		if node is Node2D and node.get_node_or_null(^"Tiles") is RoomTiles:
			return node as Node2D
		node = node.get_parent()
	return null


func _ensure_light() -> void:
	if _light != null and is_instance_valid(_light):
		return
	_light = LightSource.new()
	_light.name = "Warning"
	_light.flicker = 0.12
	if &"color" in _light:
		_light.set(&"color", get_color())
	_light.position.y = sort_lift()
	add_child(_light)


func _fade_light() -> void:
	if _light == null or not is_instance_valid(_light):
		_light = null
		return
	var light := _light
	_light = null
	var tween := light.create_tween()
	tween.tween_property(light, "intensity", 0.0, LIGHT_FADE)
	tween.tween_callback(light.queue_free)


func _draw() -> void:
	if is_wall_source():
		return
	# Drawn at the pivot (the node sorts sort_lift above it). Pixel art (D-218, PixelDraw).
	var floor_offset := Vector2(0.0, sort_lift())
	var color := get_color()
	if phase == Phase.WARN:
		# Pulsing ring on the floor: readable even before the light has grown. Blinks in two steps.
		var t := clampf(_phase_time / _phase_length, 0.0, 1.0)
		var pulse := 1.0 if sin(_phase_time * 14.0) >= 0.0 else 0.0
		var fill := RING_RADIUS * (0.7 + 0.3 * t)
		var ring := RING_RADIUS * (0.8 + 0.4 * t)
		PixelDraw.ellipse(self, floor_offset, Vector2(fill, fill * RING_SQUASH), Color(color, 0.12 + 0.18 * t))
		PixelDraw.ellipse_ring(self, floor_offset, Vector2(ring, ring * RING_SQUASH), Color(color, 0.35 + 0.4 * pulse))
	if _sprite == null:
		_draw_placeholder(color, floor_offset)


## Drawn stand-in while the art is missing (pixel art, D-218).
func _draw_placeholder(color: Color, floor_offset := Vector2.ZERO) -> void:
	var glow := Color(color, PixelDraw.stepped(0.25 + _glimmer(), 4))
	match kind:
		SpawnSourceRules.Kind.GRAVE:
			PixelDraw.ellipse(self, floor_offset + Vector2(0, -2), Vector2(22.0, 22.0 * RING_SQUASH), Color("4a3d33"))
			PixelDraw.rect(self, Rect2(floor_offset + Vector2(-9, -40), Vector2(18, 26)), Color("6b6275"))
			PixelDraw.rect(self, Rect2(floor_offset + Vector2(-9, -40), Vector2(18, 2)), Color("8d8498"))
			PixelDraw.disc(self, floor_offset + Vector2(0, -6), 6.0, glow)
		SpawnSourceRules.Kind.SARCOPHAGUS:
			PixelDraw.rect(self, Rect2(floor_offset + Vector2(-24, -66), Vector2(48, 66)), Color("4b4655"))
			PixelDraw.rect(self, Rect2(floor_offset + Vector2(-20, -62), Vector2(40, 58)), Color("6b6275"))
			PixelDraw.line(self, floor_offset + Vector2(0, -56), floor_offset + Vector2(0, -16), glow, 2)
		SpawnSourceRules.Kind.PUDDLE:
			PixelDraw.ellipse(self, floor_offset, Vector2(24.0, 24.0 * RING_SQUASH), Color(color.darkened(0.55), 0.85))
			PixelDraw.ellipse(self, floor_offset + Vector2(-4, -1), Vector2(12.0, 12.0 * RING_SQUASH), glow)
		_:
			var crack := PackedVector2Array([Vector2(-22, -4), Vector2(-10, 2), Vector2(-2, -5), Vector2(8, 3), Vector2(20, -2)])
			PixelDraw.polyline(self, crack, Color("120d18"), 3)
			PixelDraw.polyline(self, crack, glow, 1)
