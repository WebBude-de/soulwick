class_name TutorialJump
extends Node
## Station 3 of the practice run (WK10): a short stretch in side view (TutorialPlans.JUMP, a
## SideSegment of its own) - jump onto a block, the double jump up a high wall, a long run-up and a
## ditch that a jump with momentum (Schwung, D-195/SV1) clears. The way: black fade with the station
## title -> the stretch (players in side view, its camera) -> its door -> black fade -> back in the
## hall behind the jump door (on_finished places the players). Input is locked per player while black,
## nothing pauses (D-088). The stretch has no pit (no heart lost while practising) and no enemies.
## Nothing lies over it but Flint's corner (TutorialRun hides its strip).
## Decisions here (which hint is due: the first player passing a hint column, momentum over the
## ditch), effects outside: hint_due goes to TutorialRun, which lets Flint say it.

signal entered(segment: SideSegment)
signal hint_due(text_key: StringName)
signal left(jump: TutorialJump)

const INPUT_LOCK := &"tutorial_jump"
const LAYER := 90
const TITLE_SIZE := 40
## The title stays on the black this long (s).
const TITLE_TIME := 1.2
## Momentum over the ditch: praise, or a tip for next time.
const MOMENTUM_KEY: StringName = &"FLINT_TUTORIAL_JUMP_MOMENTUM"
const DITCH_KEY: StringName = &"FLINT_TUTORIAL_JUMP_DITCH"

var segment: SideSegment = null
var players: Array[Player] = []
var is_running := false
## Hint columns already passed (TutorialPlans.JUMP_HINTS) and the ditch's outcome.
var hints_given: Array[StringName] = []
var was_in_ditch := false
var ditch_judged := false

var _world: Node2D = null
var _context: DungeonContext = null
var _on_finished: Callable
var _layer: CanvasLayer = null
var _black: ColorRect = null
var _title: Label = null
var _saved_lighting: LightingProfile = null


## Takes group through the stretch. world: where the segment goes (the dungeon); on_finished:
## Callable(players: Array[Player]) puts them back into the hall.
static func start(world: Node2D, group: Array[Player], run_context: DungeonContext, on_finished: Callable) -> TutorialJump:
	var jump := TutorialJump.new()
	jump.name = "TutorialJump"
	jump._world = world
	jump.players = group.duplicate()
	jump._context = run_context
	jump._on_finished = on_finished
	world.add_child(jump)
	jump._run()
	return jump


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
	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override(&"font", UiKit.FONT)
	_title.add_theme_font_size_override(&"font_size", TITLE_SIZE)
	_title.add_theme_color_override(&"font_color", UiKit.COLOR_GOLD)
	_title.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_title.add_theme_constant_override(&"outline_size", 4)
	_black.add_child(_title)


func _run() -> void:
	is_running = true
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_lock(true)
	Sfx.play_ui(self, SideRules.sound_or(SideRules.SOUND_DRONE, SideRules.SOUND_DRONE_FALLBACK), -6.0)
	await _fade(1.0)
	if not is_inside_tree():
		return
	_enter_segment()
	_title.text = Loc.t(&"TUTORIAL_STATION_CAPTION", [TutorialRules.station_number(TutorialRules.Station.JUMP),
			Loc.t(TutorialRules.title_key(TutorialRules.Station.JUMP))])
	await get_tree().create_timer(TITLE_TIME, false).timeout
	if not is_inside_tree():
		return
	_title.text = ""
	_lock(false)
	await _fade(0.0)
	if not is_inside_tree() or segment == null:
		return
	if not segment.is_finished:
		await segment.finished
	if not is_inside_tree():
		return
	_lock(true)
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


func _physics_process(_delta: float) -> void:
	if segment == null or segment.is_finished:
		return
	var foremost := segment.get_foremost_player()
	if foremost == null:
		return
	var key := hint_for(segment.to_local(foremost.get_feet_position()))
	if key != &"":
		hint_due.emit(key)


## Decision: the hint due for a player whose feet stand at local (segment space), &"" for none.
## Each hint once; the ditch is judged once the player is past it.
func hint_for(local: Vector2) -> StringName:
	var cell := SideLayout.cell_at(local + Vector2(0, -4))
	for spot: Array in TutorialPlans.JUMP_HINTS:
		var key: StringName = spot[1]
		if cell.x >= int(spot[0]) and not hints_given.has(key):
			hints_given.append(key)
			return key
	var ditch := TutorialPlans.JUMP_DITCH
	if cell.x >= ditch.x and cell.x <= ditch.y and cell.y > SideRules.ROWS - 4:
		was_in_ditch = true
	if not ditch_judged and cell.x > ditch.y and cell.y <= SideRules.ROWS - 4:
		ditch_judged = true
		return DITCH_KEY if was_in_ditch else MOMENTUM_KEY
	return &""


func _enter_segment() -> void:
	segment = SideSegment.new()
	segment.setup(TutorialPlans.jump_layout(), 1, _context, TutorialRules.JUMP_SEED)
	_world.add_child(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	for player in players:
		if is_instance_valid(player):
			segment.add_player(player)
	segment.make_camera_current()
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null:
		_saved_lighting = overlay.get_lighting()
		overlay.set_lighting(LightingProfile.for_biome(TutorialPlans.JUMP_BIOME), true)
	entered.emit(segment)


func _leave_segment() -> void:
	var group := segment.get_players() if segment != null else players
	if segment != null:
		segment.remove_players()
	for player in group:
		if not is_instance_valid(player):
			continue
		var own := player.get_node_or_null("Camera2D") as Camera2D
		if own != null and own.enabled:
			own.make_current()
	if _on_finished.is_valid():
		_on_finished.call(group)
	for player in group:
		if not is_instance_valid(player):
			continue
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
	tween.tween_property(_black, ^"modulate:a", alpha, TutorialRules.FADE_TIME)
	await tween.finished
