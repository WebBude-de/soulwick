class_name SideTransit
extends Node
## The way through a side segment (M5): door -> black fade 0.3 s with a low drone -> banner
## "Abstieg" (the first three segments of a save also show "Springen: Leertaste") -> the segment
## (players in side view, its own camera and light) -> door -> black fade -> the next room, where
## the caller puts the players (on_finished) -> fade in. Input is locked per player while black, no
## global pause (multiplayer rule). The transit frees itself and the segment at the end; a run that
## ends meanwhile frees it with its world.
##
## Hook (DungeonManager, see the M5 report): SideTransit.start(self, players, layout, room_index,
## context, rng.randi(), place_in_next_room) when the group walks through a door that leads into a
## segment; place_in_next_room(players) moves them just inside the next room's entrance.

signal entered(segment: SideSegment)
signal left(transit: SideTransit)

const INPUT_LOCK := &"side_transit"
const LAYER := 90
const TITLE_SIZE := 40
const SUBTITLE_SIZE := 20

var segment: SideSegment = null
var players: Array[Player] = []
var is_running := false

var _world: Node2D = null
var _layout: SideLayout = null
var _room_index := 1
var _context: DungeonContext = null
var _seed := 0
var _on_finished: Callable
var _layer: CanvasLayer = null
var _black: ColorRect = null
var _title: Label = null
var _subtitle: Label = null
var _saved_lighting: LightingProfile = null


## Starts the way through a segment. world: the dungeon node the segment goes under; seed: from the
## caller's RNG; on_finished: Callable(players: Array[Player]) placing them in the next room.
static func start(world: Node2D, group: Array[Player], layout: SideLayout, room_index: int,
		run_context: DungeonContext, rng_seed: int, on_finished: Callable) -> SideTransit:
	var transit := SideTransit.new()
	transit.name = "SideTransit"
	transit._world = world
	transit.players = group.duplicate()
	transit._layout = layout
	transit._room_index = room_index
	transit._context = run_context
	transit._seed = rng_seed
	transit._on_finished = on_finished
	world.add_child(transit)
	transit._run()
	return transit


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "Fade"
	_layer.layer = LAYER
	add_child(_layer)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.modulate.a = 0.0
	_layer.add_child(_black)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.add_child(box)
	_title = _label(TITLE_SIZE, UiKit.COLOR_GOLD)
	box.add_child(_title)
	_subtitle = _label(SUBTITLE_SIZE, UiKit.COLOR_TEXT_SOFT)
	box.add_child(_subtitle)


func _run() -> void:
	is_running = true
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_lock(true)
	Sfx.play_ui(self, SideRules.sound_or(SideRules.SOUND_DRONE, SideRules.SOUND_DRONE_FALLBACK), -4.0)
	await _fade(1.0)
	if not is_inside_tree():
		return
	_enter_segment()
	var seen := int(SaveManager.get_stat(SideRules.STAT_SEGMENTS)) if SaveManager.get_stat(SideRules.STAT_SEGMENTS) != null else 0
	var hint := SideRules.shows_jump_hint(seen)
	SaveManager.add_stat(SideRules.STAT_SEGMENTS, 1)
	_title.text = DungeonTexts.t(&"SIDE_DESCENT_TITLE")
	var subtitle := DungeonTexts.t(&"SIDE_DESCENT_SUB")
	if hint:
		subtitle += " · " + jump_hint_text()
	_subtitle.text = subtitle
	await get_tree().create_timer(SideRules.BANNER_TIME_WITH_HINT if hint else SideRules.BANNER_TIME, false).timeout
	if not is_inside_tree():
		return
	_title.text = ""
	_subtitle.text = ""
	_lock(false)
	await _fade(0.0)
	if not is_inside_tree() or segment == null:
		return
	if not segment.is_finished:
		await segment.finished
	if not is_inside_tree():
		return
	_lock(true)
	Sfx.play_ui(self, SideRules.sound_or(SideRules.SOUND_DRONE, SideRules.SOUND_DRONE_FALLBACK), -8.0)
	await _fade(1.0)
	if not is_inside_tree():
		return
	_leave_segment()
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_lock(false)
	await _fade(0.0)
	is_running = false
	left.emit(self)
	queue_free()


## "Springen: Leertaste · Dash: Umschalt" with the keys actually bound.
static func jump_hint_text() -> String:
	var jump := ControlsInfo.action_key(PlayerSideMotion.JUMP_ACTION)
	PlayerSideMotion.ensure_actions()
	var dash := ControlsInfo.action_key(PlayerSideMotion.DASH_ACTION)
	return DungeonTexts.t(&"SIDE_HINT_JUMP", [jump if not jump.is_empty() else "Space", dash if not dash.is_empty() else "Shift"])


func _enter_segment() -> void:
	segment = SideSegment.new()
	segment.setup(_layout, _room_index, _context, _seed)
	_world.add_child(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	for player in players:
		if is_instance_valid(player):
			segment.add_player(player)
	segment.make_camera_current()
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null:
		_saved_lighting = overlay.get_lighting()
		overlay.set_lighting(LightingProfile.for_biome(_layout.biome_id), true)
	entered.emit(segment)


func _leave_segment() -> void:
	var group := segment.get_players() if segment != null else players
	if segment != null:
		segment.remove_players()
	for player in group:
		if not is_instance_valid(player):
			continue
		var own := player.get_node_or_null("Camera2D") as Camera2D
		# Only the local player's camera is enabled (MP: the others have none at this machine).
		if own != null and own.enabled:
			own.make_current()
	if _on_finished.is_valid():
		_on_finished.call(group)
	for player in group:
		if not is_instance_valid(player):
			continue
		# The next fall in the room returns here, and the room camera does not sweep across the map.
		player.fall.remember_safe_spot(player.get_feet_position())
		var own := player.get_node_or_null("Camera2D") as Camera2D
		if own != null:
			own.reset_smoothing()
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null and _saved_lighting != null:
		overlay.set_lighting(_saved_lighting, true)
	if segment != null:
		segment.queue_free()
		segment = null


func _lock(locked: bool) -> void:
	for player in players:
		if is_instance_valid(player):
			player.set_input_locked(INPUT_LOCK, locked)


func _fade(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", alpha, SideRules.FADE_TIME)
	await tween.finished


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", UiKit.FONT)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	return label
