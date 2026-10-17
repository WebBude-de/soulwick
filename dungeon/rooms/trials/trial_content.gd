class_name TrialContent
extends SpecialContent
## Trial room (new special room type, D-102, D-112): entrance -> direct, always safe
## way to the exit -> a parcours branching off with a chest at its end (TrialLayout, trial_room.tscn).
## The kind of trial (gauntlet, light run, crumbling floor) is rolled with the dungeon RNG,
## its course fills the parcours. Mistakes cost damage (half a heart), never the run; whoever
## reaches the chest without a mistake is flawless: +1 soul crystal (D-109). The chest opens as
## soon as the first player arrives and gives an upgrade choice (D-109).
## Co-op: everyone runs for themselves; run state and "flawless" are per player, the chest opens
## once (CHEST_FOR_EVERY_PLAYER prepares per-player chests for MP5).
## Decisions (start, mistake, finish, chest) are functions that emit signals; the effects (damage,
## crystals, banner, chest, shortcut, upgrade dialog) follow the signals (D-088).

signal run_started(player: Player)
signal mistake_made(player: Player, damage: float)
signal run_finished(player: Player, flawless: bool)
signal chest_opened(player: Player)

enum RunState { IDLE, RUNNING, FINISHED }

## Co-op scaling (D-109, decided in MP5): false = one chest for the group, true = every player who
## finishes gets their own upgrade choice.
const CHEST_FOR_EVERY_PLAYER := false  # TESTWERT
## Light run: the room is dark, the player's own light circle is small (TESTWERTE).
const LIGHT_RUN_DARKNESS := 0.97
const LIGHT_RUN_VISION_RADIUS := 120.0
## Safe torches beside the direct way (light run) and their light radius.
const SAFE_TORCH_TILES: Array[Vector2i] = [Vector2i(1, 8), Vector2i(3, 1), Vector2i(13, 0)]
const SAFE_TORCH_RADIUS := 170.0
## Explanation of a kind of trial for the first-time explanations and room banners, which UX2 builds
## centrally (D-110); the trial room itself shows none. Translation keys (D-111); the crumbling
## floor's text says a fall costs a heart there (A4 rule), not ½.
const INTRO_KEY := &"ROOM_TRIAL_INTRO"
const INTRO_KEYS := {
	SpecialTable.TrialKind.GAUNTLET: &"ROOM_TRIAL_GAUNTLET_INTRO",
	SpecialTable.TrialKind.LIGHT_RUN: &"ROOM_TRIAL_LIGHT_RUN_INTRO",
	SpecialTable.TrialKind.CRUMBLE: &"ROOM_TRIAL_CRUMBLE_INTRO",
}
const CAPTION_COLOR := Color(1.0, 0.85, 0.5)
const MISTAKE_COLOR := Color(1.0, 0.35, 0.3)
const FLAWLESS_COLOR := Color(0.86, 0.74, 1.0)

## -1 = roll with the dungeon RNG; otherwise a SpecialTable.TrialKind (tests, screenshots).
var forced_kind := -1
var kind: SpecialTable.TrialKind = SpecialTable.TrialKind.GAUNTLET
var course: TrialCourse = null
var chest: TrialChest = null

var _states: Dictionary[int, RunState] = {}
var _mistakes: Dictionary[int, int] = {}
var _cooldowns: Dictionary[int, float] = {}
var _chest_open := false
var _choosing := false
var _safe_lights := PackedVector2Array()


## Kind, course and props are built while the room is prepared (playtest 15.10.2026 #9): the parcours
## and the chest stand there under the veil. Same dungeon RNG draws in the same order as before, only
## at the room's preparation instead of its entry.
func _on_prepare() -> void:
	# Built in room coordinates: TrialLayout tiles map straight to local positions.
	position = Vector2.ZERO
	var table := SpecialTable.load_default()
	if forced_kind >= 0:
		kind = forced_kind as SpecialTable.TrialKind
	else:
		kind = table.roll_trial_kind(context.rng, CrumbleCourse.is_available())
	if kind == SpecialTable.TrialKind.CRUMBLE and not CrumbleCourse.is_available():
		kind = SpecialTable.TrialKind.GAUNTLET
	course = _create_course(kind)
	course.name = "Course"
	course.y_sort_enabled = true
	add_child(course)
	course.setup(self)
	course.build(context.rng)
	_build_props()
	run_started.connect(_on_run_started)
	mistake_made.connect(_on_mistake_made)
	run_finished.connect(_on_run_finished)
	chest_opened.connect(_on_chest_opened)


## Entered: runs count from now on; the light run darkens the room.
func _on_setup() -> void:
	if kind == SpecialTable.TrialKind.LIGHT_RUN:
		_make_room_dark()


func _physics_process(delta: float) -> void:
	step(delta)


## One simulation step: hazard timers, then every player's run (public for tests and tools).
func step(delta: float) -> void:
	if course == null:
		return
	course.advance(delta)
	# Prepared, not entered yet: the hazards keep their beat, nobody runs (#9).
	if not is_set_up():
		return
	for id in _cooldowns.keys():
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - delta)
	for player in get_players():
		update_player(player, delta)


## Run state machine of one player from the position of their feet.
func update_player(player: Player, delta: float) -> void:
	if player == null or not player.is_alive():
		return
	var feet := room.to_local(player.get_feet_position()) if room != null else player.get_feet_position()
	var tile := RoomTiles.local_to_tile(feet)
	match get_run_state(player):
		RunState.IDLE:
			if TrialLayout.is_parcours_tile(tile):
				start_run(player)
		RunState.RUNNING:
			if TrialLayout.FINISH.has_point(tile):
				finish_run(player)
			elif not TrialLayout.is_parcours_tile(tile):
				leave_run(player)
			else:
				var damage := course.get_damage(player, feet, delta)
				if damage > 0.0:
					register_mistake(player, damage)


func get_run_state(player: Player) -> RunState:
	return _states.get(player.get_instance_id(), RunState.IDLE)


func get_mistakes(player: Player) -> int:
	return _mistakes.get(player.get_instance_id(), 0)


func has_running_players() -> bool:
	for state in _states.values():
		if state == RunState.RUNNING:
			return true
	return false


func is_chest_open() -> bool:
	return _chest_open


## Translation key of the explanation of a kind of trial, for UX2.
static func get_intro_key(trial_kind: int) -> StringName:
	return INTRO_KEYS.get(trial_kind, INTRO_KEY)


## Explanation of a kind of trial in the current language.
static func get_intro_text(trial_kind: int) -> String:
	return Loc.t(get_intro_key(trial_kind))


# --- Decisions ---

## The player stepped into the parcours. Mistakes made so far in this room stay counted.
func start_run(player: Player) -> bool:
	if player == null or get_run_state(player) != RunState.IDLE:
		return false
	_states[player.get_instance_id()] = RunState.RUNNING
	run_started.emit(player)
	return true


## Back on the safe way without reaching the chest: the run pauses, a new start is possible.
func leave_run(player: Player) -> bool:
	if player == null or get_run_state(player) != RunState.RUNNING:
		return false
	_states[player.get_instance_id()] = RunState.IDLE
	course.on_run_ended(player)
	return true


## A hazard or the darkness caught a running player. Not a mistake while the player is
## invulnerable (dash, hit I-frames) or right after the last one. The damage is capped so the trial
## never ends the run.
func register_mistake(player: Player, damage: float) -> bool:
	if player == null or get_run_state(player) != RunState.RUNNING:
		return false
	var id := player.get_instance_id()
	if _cooldowns.get(id, 0.0) > 0.0 or player.hurtbox.is_invulnerable():
		return false
	_mistakes[id] = get_mistakes(player) + 1
	_cooldowns[id] = TrialRules.MISTAKE_COOLDOWN
	var capped := TrialRules.capped_damage(damage, player.health.get_health(), player.shield.get_shield())
	mistake_made.emit(player, capped)
	return true


## A running player fell into the abyss of the course (crumbling floor): always a mistake, also
## while invulnerable; the fall itself deals the (capped) damage (PlayerFall, CrumbleCourse).
func register_fall(player: Player) -> bool:
	if player == null or get_run_state(player) != RunState.RUNNING:
		return false
	var id := player.get_instance_id()
	_mistakes[id] = get_mistakes(player) + 1
	_cooldowns[id] = TrialRules.MISTAKE_COOLDOWN
	mistake_made.emit(player, 0.0)
	return true


## The player reached the chest. Flawless = no mistake in this room.
func finish_run(player: Player) -> bool:
	if player == null or get_run_state(player) != RunState.RUNNING:
		return false
	_states[player.get_instance_id()] = RunState.FINISHED
	course.on_run_ended(player)
	run_finished.emit(player, TrialRules.is_flawless(get_mistakes(player)))
	if not _chest_open or CHEST_FOR_EVERY_PLAYER:
		open_chest(player)
	return true


## The chest opens once, for the first player who arrives (unless every player gets one).
func open_chest(player: Player) -> bool:
	if _chest_open and not CHEST_FOR_EVERY_PLAYER:
		return false
	_chest_open = true
	chest_opened.emit(player)
	return true


## Room-local points that are always lit: the chest and the safe torches (light run).
func get_permanent_lights() -> PackedVector2Array:
	var lights := _safe_lights.duplicate()
	if chest != null:
		lights.append(chest.get_light_position())
	return lights


# --- Effects ---

func _on_run_started(player: Player) -> void:
	course.on_run_started(player)


func _on_mistake_made(player: Player, damage: float) -> void:
	if damage > 0.0:
		var hit := DamageData.new()
		hit.amount = damage
		hit.source = self
		hit.tags.assign([&"trap", &"trial"])
		hit.hit_id = DamageData.next_hit_id()
		player.hurtbox.receive_hit(hit)
	else:
		# Capped to nothing: the mistake still shows.
		Sfx.play_at(self, &"hit_player", player.global_position, -6.0)
	Burst.spawn(get_parent(), player.global_position + Vector2(0, -20), MISTAKE_COLOR, 10, 110.0)


func _on_run_finished(player: Player, flawless: bool) -> void:
	if flawless:
		RunManager.add_run_crystals(TrialRules.FLAWLESS_CRYSTALS)
		Burst.spawn(get_parent(), player.global_position + Vector2(0, -24), FLAWLESS_COLOR, 18, 130.0)
	if context != null and context.ui != null:
		if flawless:
			context.ui.show_banner(DungeonTexts.t(&"TRIAL_FLAWLESS"), DungeonTexts.t(&"TRIAL_FLAWLESS_SUB", [TrialRules.FLAWLESS_CRYSTALS]), FLAWLESS_COLOR)
		else:
			context.ui.show_banner(DungeonTexts.t(&"TRIAL_PASSED"), DungeonTexts.t(&"TRIAL_PASSED_SUB"), CAPTION_COLOR)


func _on_chest_opened(player: Player) -> void:
	if chest != null:
		chest.open()
	# The way back: the gate between the chest and the safe column opens.
	if room != null:
		room.tiles.wall_rects = TrialLayout.get_wall_rects(true)
	_offer_chest_upgrade(player)


func _offer_chest_upgrade(player: Player) -> void:
	if context == null or context.upgrade_manager == null or context.ui == null or _choosing:
		return
	var offer := context.upgrade_manager.roll_offer(player.weapon_controller.get_owned_weapons(), context.rng)
	if offer.is_empty():
		context.ui.show_banner(DungeonTexts.t(&"TRIAL_EMPTY"), DungeonTexts.t(&"UPGRADES_NONE"), CAPTION_COLOR)
		return
	_choosing = true
	var choice: UpgradeData = await context.ui.choose_upgrade(offer, DungeonTexts.t(&"TRIAL_CHEST"))
	_choosing = false
	if choice != null:
		context.upgrade_manager.acquire_upgrade(choice)


# --- Look ---

func _create_course(trial_kind: SpecialTable.TrialKind) -> TrialCourse:
	match trial_kind:
		SpecialTable.TrialKind.LIGHT_RUN:
			return LightRunCourse.new()
		SpecialTable.TrialKind.CRUMBLE:
			return CrumbleCourse.new()
	return GauntletCourse.new()


func _build_props() -> void:
	var tile := RoomTiles.TILE_WORLD
	# Start and finish plates.
	var start_plate := TrialArt.make_sprite(TrialArt.PLATE)
	start_plate.offset = Vector2.ZERO
	start_plate.z_index = -9
	start_plate.position = Vector2(TrialLayout.START.position.x + 0.5, TrialLayout.START.get_center().y) * tile
	add_child(start_plate)
	var finish_plate := TrialArt.make_sprite(TrialArt.PLATE)
	finish_plate.offset = Vector2.ZERO
	finish_plate.z_index = -9
	finish_plate.position = Vector2(TrialLayout.FINISH.end.x - 0.5, TrialLayout.FINISH.get_center().y) * tile
	finish_plate.modulate = Color(1.0, 0.9, 0.6)
	add_child(finish_plate)
	# The chest, visible from the entrance.
	chest = TrialChest.new()
	chest.name = "Chest"
	chest.build()
	chest.base_position = (Vector2(TrialLayout.CHEST_TILE) + Vector2(0.5, 0.85)) * tile
	chest.position = chest.base_position
	add_child(chest)
	SortLift.lift(chest)
	add_blocker(Vector2(44, 18), chest.base_position + Vector2(0, -10))
	var caption_text := SpecialTable.get_trial_name(kind)
	add_caption(caption_text, Vector2(TrialLayout.START.position.x + 1.5, TrialLayout.START.position.y - 0.0) * tile + Vector2(40, 14))
	var reward := add_caption(DungeonTexts.t(&"TRIAL_FLAWLESS_CAPTION", [TrialRules.FLAWLESS_CRYSTALS]), chest.base_position + Vector2(0, -92))
	reward.add_theme_color_override("font_color", FLAWLESS_COLOR)
	reward.add_theme_font_size_override("font_size", 13)


## Light run: dark room with a small own light circle; torches along the safe way stay lit.
func _make_room_dark() -> void:
	for safe_tile in SAFE_TORCH_TILES:
		var torch := TrialTorch.new()
		torch.build(SAFE_TORCH_RADIUS)
		torch.base_position = RoomTiles.tile_center(safe_tile) + Vector2(0, 24)
		torch.position = torch.base_position
		add_child(torch)
		SortLift.lift(torch)
		_safe_lights.append(torch.base_position)
	if not is_inside_tree():
		return
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null:
		overlay.set_vision(LIGHT_RUN_DARKNESS, LIGHT_RUN_VISION_RADIUS)
