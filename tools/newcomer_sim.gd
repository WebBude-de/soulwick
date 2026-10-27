extends SceneTree
## Newcomer run (FS4, ROADMAP Strang F): a bot plays the game like somebody who has never seen it,
## from the very first start, and writes down what the game tells him and where he hangs.
## Fresh account in its own folder (SaveManager.set_storage_root: save, settings, profile, progress
## and seen flags; the real files are never touched, AGENTS.md rule 4), then:
## 1. Main menu: "Wie heißt du?" - a name, "Los geht's" (P1-1: creates Welt 1, straight into the village).
## 2. Village: Flint's tour (WK9) plays; the bot reads it like a player who clicks it away (read=fast),
##    reads every sentence (read=slow) or presses "Überspringen" (read=skip). Then by mode:
##    - guided: follows the hints (goal line, soul-light trail, arrow) to the ruin and presses E.
##    - wander: walks a few seconds in a random direction (seed), turns when it bumps into something,
##      stops in front of whatever shows a use prompt and presses E (buildings, animals, the entrance,
##      inside the home too), reads the dialogs and closes them. After village_limit seconds it gives up and follows the
##      arrow (logged). Every 30 s a status line shows whether the hints change (stronger arrow, Flint).
## 3. Dungeon: the practice run (WK10) with the TutorialBot (paused while a Flint tour talks, so the
##    reading style above applies), then rooms 1..rooms with a simple newcomer fighter on the player's
##    real input (RemoteInput): walks to the nearest enemy, attacks in reach, dodges a telegraph only
##    sometimes, uses the special now and then, walks through the exit gate (obstacle runs with
##    SideBot). It is not the balance bot on purpose: tools/balance_sim.gd drives the body directly
##    (no input, no prompts, no Flint) and lives in its own SceneTree script; this one has to go
##    through the same door as a player so the hints fire. Upgrade dialogs: the first upgrade.
## 4. The run ends by death (or, after the last room, on purpose); the bot goes back to the village
##    and watches what it is told there for RETURN_WATCH seconds.
## Log: a Markdown file per run (timeline in game seconds: every Flint sentence with its key, goal
## line, notices, prompts, banners, dialogs, rooms, deaths; idle stretches over IDLE_LIMIT s; the
## newcomer questions "who explains X?"), plus a summary line on stdout ("NEWCOMER ...").
##
## Usage (headless, silent, from the project root):
##   godot --headless --fixed-fps 60 --audio-driver Dummy --path . -s tools/newcomer_sim.gd -- mode=guided read=slow
## Arguments (key=value):
##   mode=guided        guided | wander
##   read=slow          slow (reads every Flint sentence) | fast (clicks it away) | skip ("Überspringen")
##   seed=1             random walk and dodge decisions (wander) - the dungeon itself stays random
##   dseed=0            N != 0: fixed dungeon seed (DungeonManager.seed_value)
##   rooms=5            rooms to play after the practice run
##   village_limit=300  seconds of wandering before the bot gives up and follows the arrow
##   room_timeout=150   seconds before an unfinished room is cleared by the tool (bot limit, logged)
##   max_time=1500      game seconds for the whole run
##   out=<dir>          folder of the Markdown log (default user://newcomer_sim)
##   quiet=1            print only the summary
##   keep=1             keep the test account folder (user://newcomer_sim_storage_<pid>)
##   debug=1            trace the way to the exit every second
##   side_guard=1       the player cannot be hurt in obstacle runs (SideBot plays them; it jumps
##                      well but is no newcomer model and died there); 0 = real damage
## Classes are accessed dynamically: this script is compiled before autoloads exist.

const FRAME := 1.0 / 60.0
const DEFAULT_OUT := "user://newcomer_sim"
const STORAGE := "user://newcomer_sim_storage_%d"
## A stretch without anything meaningful (no progress, no Flint, no dialog) longer than this is
## logged as "hängt" (FS4).
const IDLE_LIMIT := 20.0
## Seconds the bot watches the village after the run.
const RETURN_WATCH := 30.0
## Reading speed of the newcomer: seconds before he acts on the first-start panel and on a dialog.
const MENU_READ := {"fast": 2.0, "slow": 7.0, "skip": 1.5}
const DIALOG_READ := {"fast": 1.2, "slow": 4.5, "skip": 0.8}
## read=fast: clicks "Weiter" this long after a sentence starts (reveal) and again after the reveal.
const FAST_PRESS := 0.4
## Wander: seconds per direction, chance of standing still for a moment, stand time (s), time in
## front of a prompt before pressing E, how often the same thing is spoken to again.
const LEG_MIN := 1.5
const LEG_MAX := 4.0
const LOOK_AROUND_CHANCE := 0.2
const LOOK_AROUND := Vector2(0.8, 2.0)
const PROMPT_READ := 0.6
const TALK_AGAIN := 45.0
const STATUS_EVERY := 30.0
## Fighter: chance to dash away from a telegraph that is close (newcomer, D-213 "Neuling" 0.5),
## special every few seconds of fighting, how close counts as "at the exit door".
const DODGE_CHANCE := 0.5
const DODGE_RADIUS := 90.0
const SPECIAL_EVERY := 6.0
const DOOR_REACHED := 44.0
const EXIT_TIMEOUT := 30.0
const SPECIAL_ROOM_TIME := 25.0
## Movement stuck: no progress of the feet for this long while walking -> sidestep.
const STUCK_TIME := 0.6
const SIDESTEP_TIME := 0.5
const ARRIVE := 18.0
## Newcomer questions: concept -> [question, words that mean it is talked about].
const QUESTIONS := [
	["Wie laufe ich, wie benutze ich etwas?", ["lauf mit", "bewegen", "benutzen", "mit e "]],
	["Wohin soll ich?", ["dungeon", "steig"]],
	["Wofür ist Gold – behalte ich es?", ["gold"]],
	["Wofür sind (Seelen-)Kristalle?", ["kristall"]],
	["Was ist ein Seelentor?", ["seelentor"]],
	["Was passiert, wenn ich sterbe?", ["fällst", "stirbst", "viertel", "tod"]],
	["Was bedeuten Rang und Gefahrenstufe?", ["rang", "gefahr"]],
	["Was bringen XP, Level und Talentpunkte?", ["xp", "talent", "level", "stufe"]],
	["Was ist der Schild (blaue Anzeige)?", ["schild"]],
	["Was ist der Spezialangriff?", ["spezial"]],
	["Was macht der Dash?", ["dash"]],
	["Was sind Upgrades?", ["upgrade"]],
	["Wie bekomme ich Herzen zurück?", ["herz", "heil", "brunnen"]],
]

## Log kinds that are the game talking (for the newcomer questions); the others are the tool's own.
const SHOWN_KINDS := ["MENÜ", "HUD", "ZIEL", "HINWEIS", "EINGANG", "PROMPT", "BANNER", "STATUSZEILE", "ÜBUNG", "DIALOG"]

var opt := {
	"mode": "guided", "read": "slow", "seed": 1, "dseed": 0, "rooms": 5, "village_limit": 300.0,
	"room_timeout": 150.0, "max_time": 1500.0, "out": "", "quiet": 0, "keep": 0, "debug": 0,
	"side_guard": 1,
}

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _phase := "Start"
var _events: Array[Dictionary] = []
var _done := false
var _storage := ""

# Scripts (loaded at run time: autoloads do not exist when this file compiles).
var _guide_script: Script = null
var _guide_rules: Script = null
var _tutorial_script: Script = null
var _tutorial_bot_script: Script = null
var _side_bot_script: Script = null
var _modal_script: Script = null
var _remote_input_script: Script = null
var _player_input_script: Script = null

var _controller: Node = null
var _world: Node = null
var _dungeon: Node = null
var _village: Node = null
var _player: Node = null
var _input: Object = null

# Flint reading.
var _step_at := -1.0
var _step_text := ""
var _last_press := -10.0
var _explanation_start := {}
var _flint_count := {"tour": 0, "hint": 0, "sentences": 0, "seconds": 0.0}
var _flint_texts: Array[String] = []

# Monitors: last text seen per channel, last modal handled.
var _seen_text := {}
var _modal: Node = null
var _modal_at := 0.0
var _monitor_frame := 0

# Progress and idle stretches.
var _progress_at := 0.0
var _idle_open := false
var _idle_from := 0.0
var _stuck_list: Array[Dictionary] = []
var _busy_reason := ""

# Milestones (game seconds, -1 = never).
var _ms := {
	"village": -1.0, "tour_end": -1.0, "goal_clear": -1.0, "entrance_seen": -1.0,
	"entrance_near": -1.0, "entrance_pressed": -1.0, "dungeon": -1.0, "tutorial_end": -1.0,
	"room1": -1.0, "run_end": -1.0, "back_village": -1.0, "gave_up": -1.0,
}
var _tour_skipped := false

# Village bots.
var _entrance: Node = null
var _trail := PackedVector2Array()
var _trail_index := 0
var _best_entrance_distance := INF
var _leg_dir := Vector2.ZERO
var _leg_left := 0.0
var _stand_left := 0.0
var _prompt_time := 0.0
var _talked := {}
var _bumps := 0
var _villager_bumps := 0
var _villager_near := {}
var _gave_up := false
var _next_status := STATUS_EVERY
var _wander_used: Array[String] = []

# Movement helpers.
var _last_feet := Vector2.INF
var _stuck_for := 0.0
var _sidestep_left := 0.0
var _sidestep_dir := Vector2.ZERO
var _nav_cache := {"t": -1.0, "goal": Vector2.INF, "wp": Vector2.INF}

# Dungeon.
var _tutorial: Node = null
var _tutorial_bot: Node = null
var _side_bot: RefCounted = null
var _room_index := 0
var _room_at := 0.0
var _rooms_cleared := 0
var _deaths: Array[String] = []
var _dodged := {}
var _next_special := 0.0
var _enemy_hp := -1.0
var _visited := {}
var _special_target: Node = null
var _door_passed := false
var _falls_seen := 0
var _timed_out := {}
var _ended_on_purpose := false
var _st_telegraph := 2
var _room_cleared_state := 2
var _room_special_type := 2


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_parse_args()
	_rng.seed = int(opt.seed)
	seed(int(opt.seed))
	_load_scripts()
	_setup_storage()
	_silence_sfx()
	node_added.connect(_on_node_added)
	physics_frame.connect(_on_physics_frame)
	var bus := root.get_node("EventBus")
	bus.room_completed.connect(_on_room_completed)
	bus.upgrade_acquired.connect(func(id: StringName, stacks: int) -> void: _log("UPGRADE", "%s (Stufe %d)" % [id, stacks]))
	bus.run_ended.connect(func(reason: int, remaining: int, payout: int) -> void:
		_ms.run_end = _t
		_log("RUN-ENDE", "Grund %d, Run-Gold %d, ausgezahlt %d" % [reason, remaining, payout]))
	_phase = "Hauptmenü"
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)
	_silence_music()
	await _main_menu()
	while not _done and _t < float(opt.max_time):
		await physics_frame
	if not _done:
		_log("ENDE", "Zeitgrenze von %d s erreicht (Phase %s)" % [int(opt.max_time), _phase])
	_close_idle()
	_write_report()
	_done = true
	# The game saves while it is torn down (StatsTracker): unload first, then wipe the test account.
	if current_scene != null:
		current_scene.queue_free()
	await _frames(5)
	if int(opt.keep) == 0:
		_wipe(_storage)
	quit(0)


# --- Setup ---

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2 or not opt.has(parts[0]):
			push_warning("newcomer_sim: unknown argument '%s' (see the head of tools/newcomer_sim.gd)" % arg)
			continue
		var old: Variant = opt[parts[0]]
		match typeof(old):
			TYPE_INT:
				opt[parts[0]] = int(parts[1])
			TYPE_FLOAT:
				opt[parts[0]] = float(parts[1])
			_:
				opt[parts[0]] = parts[1]
	if not ["guided", "wander"].has(String(opt.mode)):
		push_warning("newcomer_sim: mode must be guided or wander; using guided")
		opt.mode = "guided"
	if not ["fast", "slow", "skip"].has(String(opt.read)):
		push_warning("newcomer_sim: read must be fast, slow or skip; using slow")
		opt.read = "slow"


func _load_scripts() -> void:
	_guide_script = load("res://companions/guide/flint_guide.gd")
	_guide_rules = load("res://companions/guide/flint_guide_rules.gd")
	_tutorial_script = load("res://dungeon/tutorial/tutorial_run.gd")
	_tutorial_bot_script = load("res://dungeon/tutorial/tutorial_bot.gd")
	_side_bot_script = load("res://dungeon/side/side_bot.gd")
	_modal_script = load("res://ui/menus/modal.gd")
	_remote_input_script = load("res://player/input/remote_input.gd")
	_player_input_script = load("res://player/input/player_input.gd")
	var enemy_consts: Dictionary = (load("res://enemies/enemy_base.gd") as Script).get_script_constant_map()
	_st_telegraph = (enemy_consts["State"] as Dictionary)["TELEGRAPH"]
	var room_consts: Dictionary = (load("res://dungeon/rooms/room_controller.gd") as Script).get_script_constant_map()
	_room_cleared_state = (room_consts["State"] as Dictionary)["CLEARED"]
	var seq_consts: Dictionary = (load("res://dungeon/room_sequence.gd") as Script).get_script_constant_map()
	_room_special_type = (seq_consts["RoomType"] as Dictionary)["SPECIAL"]


## A fresh account in its own folder: save slots, settings, profile, progress and seen flags. The
## script switches (tour, practice run, room explanations) are on, as in the real game.
func _setup_storage() -> void:
	_storage = STORAGE % OS.get_process_id()
	_wipe(_storage)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_storage))
	TranslationServer.set_locale("de")
	var save_manager := root.get_node("SaveManager")
	save_manager.set_storage_root(_storage)
	save_manager.set_option(&"language", "de")
	load("res://meta/account_progress.gd").reset()
	load("res://ui/main_menu/main_menu.gd").online_check = false
	load("res://world/village/village_tour.gd").force_in_scripts = true
	load("res://dungeon/modes/room_flint.gd").explain_in_scripts = true
	_tutorial_script.force_next = true


func _wipe(folder: String) -> void:
	var base := ProjectSettings.globalize_path(folder)
	for dir_path in [base.path_join("saves"), base.path_join("runs"), base]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
		if dir_path != base:
			DirAccess.remove_absolute(dir_path)
	DirAccess.remove_absolute(base)


## No sound effects: every known sound is cached as "missing" (high frame rates and the mixer
## thread, D-134; same trick as tools/balance_sim.gd).
func _silence_sfx() -> void:
	var sfx: Script = load("res://components/audio/sfx.gd")
	var cache: Dictionary = sfx.get(&"_cache")
	var dir := DirAccess.open(sfx.SFX_DIR)
	if cache == null or dir == null:
		return
	for file in dir.get_files():
		var file_name := file.trim_suffix(".import").trim_suffix(".remap")
		if file_name.get_extension() == "wav":
			cache[StringName(file_name.get_basename())] = null


func _silence_music() -> void:
	if current_scene == null:
		return
	for node in current_scene.find_children("*Music*", "", false, false):
		node.queue_free()


# --- Main menu ---

func _main_menu() -> void:
	var menu: Node = current_scene.get("menu") if current_scene != null else null
	if menu == null:
		_log("FEHLER", "Hauptmenü nicht gefunden")
		_done = true
		return
	await _frames(5)
	var panel: Node = menu.get_open_panel()
	if panel == null or not bool(panel.get("first_start")):
		_log("FEHLER", "Erststart-Seite „Wie heißt du?“ öffnet sich nicht")
		_done = true
		return
	_log("MENÜ", "Erster Start: " + " · ".join(_texts_of(panel)))
	_progress("Hauptmenü")
	await _seconds(float(MENU_READ[String(opt.read)]))
	panel.editor.set_player_name("Neuling")
	panel.editor.confirm()
	_log("MENÜ", "Name „Neuling“, Figur unverändert, „Los geht's“")
	for i in 600:
		await physics_frame
		if current_scene != null and current_scene.get_node_or_null("WorldController") != null:
			break
	if current_scene == null or current_scene.get_node_or_null("WorldController") == null:
		_log("FEHLER", "Nach „Los geht's“ startet kein Spiel")
		_done = true
		return
	await _frames(3)
	_silence_music()
	_controller = current_scene.get_node("WorldController")


# --- Every physics frame ---

func _on_physics_frame() -> void:
	_t += FRAME
	if _controller == null or not is_instance_valid(_controller) or _done:
		return
	_follow_world()
	_follow_player()
	if _player == null:
		return
	_read_flint()
	_handle_modal()
	_monitor_frame += 1
	if _monitor_frame % 15 == 0:
		_monitor()
	_watch_idle()
	_update_stuck()
	if _modal != null:
		_input_clear()
		return
	match _phase:
		"Dorf":
			if String(opt.mode) == "wander" and not _gave_up:
				_village_wander()
			else:
				_village_guided()
		"Zuhause":
			if String(opt.mode) == "wander" and not _gave_up:
				_village_wander()
			else:
				_leave_home()
		"Übungsgang":
			_tutorial_step()
		"Dungeon":
			_fight_step()
		"Rückkehr":
			_input_clear()
			if _t - float(_ms.back_village) >= RETURN_WATCH:
				_log("ENDE", "Beobachtung im Dorf nach dem Run beendet")
				_done = true


func _follow_world() -> void:
	var world: Node = _controller.get_world()
	if world == _world or world == null:
		return
	_world = world
	var world_name := String(world.get_script().get_global_name()) if world.get_script() != null else ""
	if world_name == "Village":
		_village = world
		_dungeon = null
		if float(_ms.village) < 0.0:
			_ms.village = _t
			_phase = "Dorf"
			_log("WELT", "Dorf geladen (frische Welt)")
			_setup_village()
		elif float(_ms.dungeon) < 0.0:
			# Back from the home (KE8): the village is built again, the bot goes on looking.
			_phase = "Dorf"
			_log("WELT", "wieder draußen im Dorf")
			_setup_village()
		else:
			_ms.back_village = _t
			_phase = "Rückkehr"
			_log("WELT", "Zurück im Dorf nach dem Run")
	elif world_name == "HomeInterior":
		_village = null
		_entrance = null
		_phase = "Zuhause"
		_log("WELT", "im Zuhause (eigene Welt, KE8)")
		_progress("Zuhause")
	elif world_name == "DungeonManager":
		_dungeon = world
		_village = null
		_ms.dungeon = _t
		_log("WELT", "Dungeon geladen (%.1f s nach dem Dorf-Start)" % (_t - float(_ms.village)))
		_phase = "Übungsgang"
		_room_index = 0
		_progress("Dungeon")
		_log_hud.call_deferred()


func _follow_player() -> void:
	var player: Node = _controller.get_player()
	if player == _player:
		return
	_player = player
	_side_bot = null
	_falls_seen = 0
	_last_feet = Vector2.INF
	if player == null:
		return
	_input = _remote_input_script.new()
	player.input = _input
	player.died.connect(_on_player_died)
	# The guide may exist already (village tour offered at the spawn).
	var guide: Node = _guide_script.of(player)
	if guide != null:
		_hook_guide(guide)


func _on_node_added(node: Node) -> void:
	var script: Script = node.get_script()
	if script == null:
		return
	if script.get_global_name() == &"DungeonManager" and int(opt.dseed) != 0:
		node.set(&"seed_value", int(opt.dseed))
	if script == _guide_script:
		_hook_guide(node)
	elif script == _tutorial_script:
		_hook_tutorial(node)


# --- Flint: logging and reading ---

func _hook_guide(guide: Node) -> void:
	if not is_instance_valid(guide) or guide.started.is_connected(_on_flint_started):
		return
	guide.started.connect(_on_flint_started)
	guide.step_started.connect(_on_flint_step.bind(guide))
	guide.finished.connect(_on_flint_finished)
	if guide.current != null:
		# Hooked late (the player came with a running explanation): log what runs.
		_on_flint_started(guide.current)
		if guide.get_text() != "":
			_on_flint_step(guide.step_index, guide.get_text(), 0, guide)


func _on_flint_started(explanation: Resource) -> void:
	var tour: bool = explanation.locks_player()
	_flint_count["tour" if tour else "hint"] += 1
	_explanation_start[String(explanation.id)] = _t
	_log("FLINT", "▶ %s (%s, %d Sätze)" % [explanation.id, "Tour, hält an" if tour else "Hinweis, läuft weiter", explanation.steps.size()])
	_progress("Flint")
	if tour and _tutorial_bot != null and is_instance_valid(_tutorial_bot):
		# The TutorialBot would skip the tour; this bot reads it in its own style instead.
		_tutorial_bot.set_physics_process(false)


func _on_flint_step(index: int, text: String, _mood: int, guide: Node) -> void:
	var step: Resource = guide.get_step()
	var key := String(step.text_key) if step != null else "?"
	var total: int = guide.current.steps.size() if guide.current != null else 0
	_flint_count.sentences += 1
	_flint_texts.append(text)
	_step_at = _t
	_step_text = text
	_log("FLINT", "  %d/%d %s: „%s“" % [index + 1, total, key, text])
	_progress("Flint")


func _on_flint_finished(explanation: Resource, skipped: bool) -> void:
	var id := String(explanation.id)
	var took: float = _t - float(_explanation_start.get(id, _t))
	_flint_count.seconds += took
	_log("FLINT", "■ %s %s nach %.1f s" % [id, "übersprungen" if skipped else "fertig", took])
	if id == "flint_village_tour":
		_ms.tour_end = _t
		_tour_skipped = skipped
	_step_at = -1.0
	_progress("Flint")
	if _tutorial_bot != null and is_instance_valid(_tutorial_bot):
		_tutorial_bot.set_physics_process(true)


## "Weiter" like the chosen reader: fast clicks right away, slow waits for the text and its reading
## time, skip presses "Überspringen". Hints close by themselves (nobody presses).
func _read_flint() -> void:
	var guide: Node = _guide_script.of(_player)
	if guide == null or guide.current == null or not guide.current.locks_player():
		return
	_busy_reason = "Flint erklärt"
	_progress_soft()
	if guide.phase != _guide_script.Phase.TALK or _step_at < 0.0:
		return
	var in_step := _t - _step_at
	match String(opt.read):
		"skip":
			if in_step >= FAST_PRESS:
				guide.skip()
		"fast":
			if in_step >= FAST_PRESS and _t - _last_press >= FAST_PRESS:
				if guide.press():
					_last_press = _t
		"slow":
			var wait: float = _guide_rules.typing_time(_step_text) + _guide_rules.read_time(_step_text)
			if in_step >= wait and _t - _last_press >= 0.3:
				if guide.press():
					_last_press = _t


# --- Dialogs ---

## Every dialog: logged once with its texts, read for a moment, then the newcomer's button: an
## upgrade (the first), "Weiter" at a soul gate, "Zurück ins Dorf" after the run, else close.
func _handle_modal() -> void:
	if _modal != null and (not is_instance_valid(_modal) or _modal.is_queued_for_deletion() or not _modal.is_inside_tree()):
		_modal = null
		_progress("Dialog zu")
	if _modal == null:
		if _modal_script.open_count() <= 0:
			return
		_modal = _find_modal(root)
		if _modal == null:
			return
		_modal_at = _t
		_log("DIALOG", " · ".join(_texts_of(_modal)).left(400))
		_progress("Dialog")
	_busy_reason = "liest Dialog"
	_progress_soft()
	if _t - _modal_at < float(DIALOG_READ[String(opt.read)]):
		return
	var button := _choose_button(_modal)
	if button != null:
		_log("DIALOG", "drückt [%s]" % _caption(button))
		button.pressed.emit()
		_modal_at = _t + 0.5


func _choose_button(modal: Node) -> Button:
	var buttons := _buttons(modal)
	for button in buttons:
		if not button.disabled and _bound_upgrade(button) != null:
			return button
	for wanted in ["Weiter", "Zurück ins Dorf", "Schließen", "Zurück", "Weiterspielen", "OK", "Nein", "Abbrechen", "Speichern"]:
		for button in buttons:
			if _caption(button) == wanted and not button.disabled and button.is_visible_in_tree():
				return button
	for button in buttons:
		if not button.disabled and button.is_visible_in_tree():
			return button
	return null


func _caption(button: Button) -> String:
	return String(button.tr(StringName(button.text))).strip_edges()


func _bound_upgrade(button: Button) -> Variant:
	for connection in button.pressed.get_connections():
		var callable: Callable = connection.callable
		for argument in callable.get_bound_arguments():
			if argument is Resource and &"effect" in argument and &"max_stacks" in argument:
				return argument
	return null


func _find_modal(node: Node) -> Node:
	for child in node.get_children():
		if child.get_script() == _modal_script and not child.is_queued_for_deletion():
			return child
		var found := _find_modal(child)
		if found != null:
			return found
	return null


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


# --- What the screen says (every 15 frames) ---

func _monitor() -> void:
	var prompt: Label = _player.get_node_or_null(^"PromptLabel") as Label
	_note("PROMPT", prompt.text if prompt != null and prompt.visible else "")
	if _village != null and is_instance_valid(_village):
		_monitor_village()
	if _dungeon != null and is_instance_valid(_dungeon):
		_monitor_dungeon()


func _monitor_village() -> void:
	var ui: Node = _village.ui
	var goal: Control = ui.get_goal()
	var goal_text := " ".join(_texts_of(goal)) if goal != null else ""
	_note("ZIEL", goal_text)
	var notice: Control = ui.get_notice()
	_note("HINWEIS", " · ".join(_texts_of(notice)) if notice != null else "")
	var card: Control = ui.get_entrance_info()
	_note("EINGANG", " · ".join(_texts_of(card)) if card != null else "")
	var guide: Node = _village.get_guide()
	var arrow := ""
	if guide != null and guide.is_pointer_shown():
		arrow = "Pfeil über dem Eingang" if guide.is_pointer_on_screen() else "Pfeil am Bildrand"
	_note("PFEIL", arrow)
	var free := not _locked()
	if float(_ms.goal_clear) < 0.0 and not goal_text.is_empty() and free and _phase == "Dorf":
		_ms.goal_clear = _t
		_log("MEILENSTEIN", "Ziel klar: Zielzeile „%s“ sichtbar, Spieler frei, Spur und Pfeil %s" % [goal_text, "da" if guide != null else "fehlen"])
	if _entrance != null and float(_ms.entrance_seen) < 0.0 and _on_screen(_entrance.global_position):
		_ms.entrance_seen = _t
		_log("MEILENSTEIN", "Eingang zum ersten Mal im Bild")
	if _phase == "Dorf" and String(opt.mode) == "wander" and not _gave_up and _t - float(_ms.village) >= _next_status:
		_next_status = (floorf((_t - float(_ms.village)) / STATUS_EVERY) + 1.0) * STATUS_EVERY
		_log("LAGE", "%d s im Dorf: Abstand zum Eingang %d px, %s, Zielzeile „%s“, Flint %s, %d× angestoßen" % [
			int(_t - float(_ms.village)), int(_entrance_distance()), arrow if not arrow.is_empty() else "kein Pfeil", goal_text,
			"redet" if _flint_busy() else "still", _bumps])
	_watch_villagers()


func _monitor_dungeon() -> void:
	var ui: Node = _dungeon.ui
	var banner: Control = ui.get_banner()
	_note("BANNER", " · ".join(_texts_of(banner)) if banner != null else "")
	_note("STATUSZEILE", ui.get_status_line_text() if ui.get_status_line() != null and ui.get_status_line().visible else "")
	if _tutorial != null and is_instance_valid(_tutorial) and _tutorial.hud != null and is_instance_valid(_tutorial.hud):
		_note("ÜBUNG", "%s %s" % [_tutorial.hud.get_progress_text(), _tutorial.hud.get_station_text()])


## Logs text under channel when it changed (empty = gone, not logged).
func _note(channel: String, text: String) -> void:
	text = text.strip_edges()
	if _seen_text.get(channel, "") == text:
		return
	var had := not String(_seen_text.get(channel, "")).is_empty()
	_seen_text[channel] = text
	if not text.is_empty():
		_log(channel, text)
	elif had and channel == "ZIEL":
		_log(channel, "(Zielzeile weg)")


## Visible texts under node (labels translated, buttons in brackets).
func _texts_of(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node != null and is_instance_valid(node):
		_collect_texts(node, out)
	return out


func _collect_texts(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		var text := String(node.tr(StringName((node as Label).text))).strip_edges()
		if not text.is_empty():
			out.append(text)
	elif node is RichTextLabel:
		var rich := (node as RichTextLabel).get_parsed_text().strip_edges()
		if not rich.is_empty():
			out.append(rich)
	elif node is Button:
		var caption := String(node.tr(StringName((node as Button).text))).strip_edges()
		if not caption.is_empty():
			out.append("[%s]" % caption)
	for child in node.get_children():
		_collect_texts(child, out)


# --- Village ---

func _setup_village() -> void:
	_entrance = _village.get_node_or_null(^"Buildings/DungeonEntrance/Interactable")
	var guide: Node = _village.get_guide()
	_trail = guide.get_points() if guide != null else PackedVector2Array()
	_log_hud()
	_log("DORF", "Wegweiser: %s, Zielzeile %s, %d Gebäude mit Info-Marker" % [
		"Spur aus %d Punkten und Pfeil" % _trail.size() if guide != null else "keiner",
		"„%s“" % TranslationServer.translate(_village.get_goal_kind()) if _village.get_goal_kind() != &"" else "keine",
		_intro_marker_count()])
	_leg_left = 0.0
	_progress("Dorf")


## The HUD's key line (bottom right) as text, once per world.
func _log_hud() -> void:
	var hud: Node = _controller.get("hud")
	var row: Node = hud.get("_hint_row") if hud != null else null
	var texts := _texts_of(row)
	_log("HUD", "Tastenzeile: " + (" ".join(texts) if not texts.is_empty() else "(leer)"))


func _intro_marker_count() -> int:
	var count := 0
	for id in ["forge", "trader", "chronicle", "guild", "home"]:
		if _village.has_intro_marker(StringName(id)):
			count += 1
	return count


## guided: along the soul-light trail to the ruin, E at the entrance.
func _village_guided() -> void:
	_input_clear()
	if _locked() or _ui_dialog_open():
		return
	if _press_entrance():
		return
	var feet: Vector2 = _player.global_position
	if not _trail.is_empty():
		if _trail_index == 0 and _gave_up:
			_trail_index = _nearest_trail_index(feet)
		while _trail_index < _trail.size() and feet.distance_to(_trail[_trail_index]) < ARRIVE * 1.5:
			_trail_index += 1
	var goal: Vector2 = _trail[_trail_index] if _trail_index < _trail.size() else _entrance.global_position
	_track_entrance_distance()
	_walk(goal)


func _nearest_trail_index(feet: Vector2) -> int:
	var best := 0
	for i in _trail.size():
		if feet.distance_to(_trail[i]) < feet.distance_to(_trail[best]):
			best = i
	return best


## E when the use prompt is the entrance's. True while it does.
func _press_entrance() -> bool:
	var focused: Node = _player.get("_focused_interactable")
	if focused == null or focused != _entrance:
		return false
	if float(_ms.entrance_pressed) < 0.0:
		_ms.entrance_pressed = _t
		_log("MEILENSTEIN", "Drückt E am Dungeon-Eingang (%.1f s nach dem Dorf-Start)" % (_t - float(_ms.village)))
	_input.tap(_player_input_script.INTERACT)
	return true


## wander: random legs, turns at walls, presses E at every new prompt (dialogs are read and closed).
func _village_wander() -> void:
	_input_clear()
	if _locked() or _ui_dialog_open():
		return
	_track_entrance_distance()
	var free_since := float(_ms.tour_end) if float(_ms.tour_end) >= 0.0 else float(_ms.village)
	if _t - free_since > float(opt.village_limit):
		_gave_up = true
		_ms.gave_up = _t
		_trail_index = 0
		_log("MEILENSTEIN", "Gibt nach %d s Herumirren auf und folgt jetzt dem Pfeil" % int(opt.village_limit))
		return
	var focused: Node = _player.get("_focused_interactable")
	if focused != null:
		# By world and prompt: worlds are built again on every visit (village, home), nodes are new.
		var key := "%s|%s" % [_phase, String(focused.prompt)]
		if not _talked.has(key) or _t - float(_talked[key]) > TALK_AGAIN:
			_prompt_time += FRAME
			if _prompt_time < PROMPT_READ:
				return
			_prompt_time = 0.0
			_talked[key] = _t
			var label := String(focused.prompt)
			_wander_used.append(label)
			_log("HERUMIRREN", "steht vor „%s“ und drückt E" % TranslationServer.translate(StringName(label)))
			if focused == _entrance and float(_ms.entrance_pressed) < 0.0:
				_ms.entrance_pressed = _t
				_log("MEILENSTEIN", "Drückt E am Dungeon-Eingang (%.1f s nach dem Dorf-Start, zufällig gefunden)" % (_t - float(_ms.village)))
			else:
				_progress("spricht an")
			_input.tap(_player_input_script.INTERACT)
			return
	_prompt_time = 0.0
	if _stand_left > 0.0:
		_stand_left -= FRAME
		return
	_leg_left -= FRAME
	var bumped := _moved_too_little()
	if bumped:
		_bumps += 1
	if _leg_left <= 0.0 or bumped:
		if not bumped and _rng.randf() < LOOK_AROUND_CHANCE:
			_stand_left = _rng.randf_range(LOOK_AROUND.x, LOOK_AROUND.y)
		var turn := _rng.randf() * TAU
		if bumped and _leg_dir != Vector2.ZERO:
			# Away from the wall, roughly: somewhere in the half behind.
			turn = _leg_dir.angle() + PI + _rng.randf_range(-PI * 0.5, PI * 0.5)
		_leg_dir = Vector2.from_angle(turn)
		_leg_left = _rng.randf_range(LEG_MIN, LEG_MAX)
		_stuck_for = 0.0
	_input.set_move(_leg_dir)


func _track_entrance_distance() -> void:
	var distance := _entrance_distance()
	if distance < _best_entrance_distance - 16.0:
		_best_entrance_distance = distance
		_progress("näher am Eingang")
	if float(_ms.entrance_near) < 0.0 and distance < 160.0:
		_ms.entrance_near = _t
		_log("MEILENSTEIN", "Am Dungeon-Eingang angekommen (%.1f s nach dem Dorf-Start)" % (_t - float(_ms.village)))


func _entrance_distance() -> float:
	if _entrance == null or _player == null:
		return INF
	return _player.global_position.distance_to(_entrance.global_position)


## Villagers hop aside when run into (#ec4f0b9f); counted, the first few logged.
func _watch_villagers() -> void:
	var villagers: Node = _village.get_node_or_null(^"Villagers")
	if villagers == null:
		return
	for villager in villagers.get_children():
		var key := villager.get_instance_id()
		var near: bool = (villager as Node2D).global_position.distance_to(_player.global_position) < 30.0
		if near and not _villager_near.get(key, false):
			_villager_bumps += 1
			if _villager_bumps <= 3:
				_log("HERUMIRREN", "läuft in %s (%s)" % [villager.name, "Tier" if String(villager.get("animal")) != "" else "Bewohner"])
		_villager_near[key] = near


func _ui_dialog_open() -> bool:
	if _village != null and is_instance_valid(_village):
		return _village.ui.is_dialog_open()
	if _world != null and is_instance_valid(_world) and _world.has_method(&"is_dialog_open"):
		return bool(_world.is_dialog_open())
	return false


## guided (or given up) inside the home: out through its door (HomeInterior.exit_door).
func _leave_home() -> void:
	_input_clear()
	if _locked() or _ui_dialog_open():
		return
	var door: Node2D = _world.get("exit_door")
	if door == null:
		return
	if _player.get("_focused_interactable") == door:
		_input.tap(_player_input_script.INTERACT)
		return
	_walk(door.global_position)


# --- Practice run ---

func _hook_tutorial(run: Node) -> void:
	if not is_instance_valid(run):
		return
	_tutorial = run
	run.station_started.connect(func(station: int) -> void:
		_log("ÜBUNG", "Station %d beginnt" % (station + 1))
		_progress("Station"))
	run.station_completed.connect(func(station: int) -> void:
		_log("ÜBUNG", "Station %d geschafft" % (station + 1))
		_progress("Station"))
	run.finished.connect(func(completed: bool, xp: int) -> void:
		_ms.tutorial_end = _t
		_log("ÜBUNG", "Übungsgang %s, +%d XP (%.1f s)" % ["geschafft" if completed else "übersprungen", xp, _t - float(_ms.dungeon)])
		_progress("Übungsgang fertig"))


func _tutorial_step() -> void:
	if _player.get("fall") != null:
		_watch_falls()
	if _tutorial == null or not is_instance_valid(_tutorial) or _tutorial.is_finished:
		if _dungeon != null and _dungeon.get_active_room_index() >= 1:
			_phase = "Dungeon"
			_log("PHASE", "Run beginnt in Raum 1")
		return
	if _tutorial_bot == null and _tutorial.player != null:
		_tutorial_bot = _tutorial_bot_script.drive(_tutorial)
		_log("ÜBUNG", "Übungsgang beginnt (Bot: TutorialBot, liest Flint wie eingestellt)")
	var guide: Node = _guide_script.of(_player)
	var tour: bool = guide != null and guide.current != null and guide.current.locks_player()
	if _tutorial_bot != null and is_instance_valid(_tutorial_bot):
		_tutorial_bot.set_physics_process(not tour)
		_busy_reason = "Übungsgang: " + String(_tutorial_bot.stage)


# --- Dungeon rooms: the newcomer fighter ---

func _fight_step() -> void:
	_input_clear()
	if not _player.is_alive():
		return
	_follow_room()
	_watch_falls()
	if _player.is_side_view():
		_side_step()
		return
	if _side_bot != null:
		_side_bot = null
		_player.hurtbox.set_invulnerable(&"newcomer_side", false)
		_log("HINDERNISLAUF", "zurück in der Draufsicht, Leben %.1f" % _player.health.get_health())
	if _player.is_input_locked():
		return
	var room: Node = _dungeon.get_room(_dungeon.get_active_room_index())
	if room == null:
		return
	if _room_index > int(opt.rooms) or (_room_index == int(opt.rooms) and room.state == _room_cleared_state):
		_end_on_purpose()
		return
	var enemies := _alive_enemies(room)
	_watch_enemy_health(enemies)
	if not enemies.is_empty():
		_busy_reason = "kämpft in Raum %d" % _room_index
		_fight(room, enemies)
	elif room.state != _room_cleared_state:
		_busy_reason = "wartet in Raum %d (keine Gegner, Raum nicht geschafft)" % _room_index
		_walk(room.get_arena().get_center(), room)
	elif room.room_type == _room_special_type and _t - _room_at < SPECIAL_ROOM_TIME and _visit_special(room):
		_busy_reason = "schaut sich den Sonderraum an"
	else:
		_busy_reason = "sucht den Ausgang von Raum %d" % _room_index
		_go_exit(room)
	_check_room_timeout(room)


func _follow_room() -> void:
	var index: int = _dungeon.get_active_room_index()
	if index == _room_index:
		return
	_room_index = index
	_room_at = _t
	_visited.clear()
	_special_target = null
	_door_passed = false
	_nav_cache.t = -1.0
	var room: Node = _dungeon.get_room(index)
	if index == 1 and float(_ms.room1) < 0.0:
		_ms.room1 = _t
	var type_name: String = ["Kampf", "Kampf + Upgrade", "Sonderraum", "Champion", "Boss", "Lagerfeuer"][int(room.room_type)] if room != null else "?"
	_log("RAUM", "Raum %d betreten (%s), Leben %.1f, Gold %d" % [index, type_name, _player.health.get_health(),
			root.get_node("RunManager").get_run_gold()])
	_progress("neuer Raum")


## Every fall into a hole is logged (a newcomer datum; the hole hint is FlintControls.CHASM).
func _watch_falls() -> void:
	var fall: Object = _player.get("fall")
	if fall == null:
		return
	if int(fall.falls) > _falls_seen:
		_falls_seen = int(fall.falls)
		_log("STURZ", "fällt in ein Loch (Raum %d, %d. Sturz), Leben danach %.1f" % [_room_index, _falls_seen, _player.health.get_health()])


func _alive_enemies(room: Node) -> Array:
	var result: Array = []
	for node in room.enemy_container.get_children():
		if node.has_method(&"is_dead") and not node.is_dead() and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _watch_enemy_health(enemies: Array) -> void:
	var total := 0.0
	for enemy in enemies:
		total += float(enemy.health.get_health())
	if _enemy_hp >= 0.0 and total < _enemy_hp - 0.01:
		_progress("trifft")
	_enemy_hp = total


func _fight(room: Node, enemies: Array) -> void:
	var feet: Vector2 = _player.global_position
	var target: Node2D = null
	for enemy in enemies:
		if target == null or feet.distance_to(enemy.global_position) < feet.distance_to(target.global_position):
			target = enemy
	var weapon: Resource = _player.weapon_controller.get_active_weapon()
	var reach: float = weapon.attack_range
	var melee: bool = weapon.is_melee()
	var distance := feet.distance_to(target.global_position)
	var want := reach * 0.7 if melee else minf(reach * 0.7, 200.0)
	if distance > want:
		_walk(target.global_position, room)
	elif not melee and distance < want * 0.5:
		_input.set_move(_avoid_pits((feet - target.global_position).normalized()))
	_input.set_aim_point(target.global_position)
	if distance <= reach + 6.0 and _line_of_sight(feet, target.global_position):
		_input.press(_player_input_script.ATTACK)
		if _t >= _next_special:
			_next_special = _t + SPECIAL_EVERY
			_input.press(_player_input_script.SPECIAL)
	_dodge(enemies, feet)


## A newcomer sees a wind-up only sometimes: once per telegraph, DODGE_CHANCE to dash away.
func _dodge(enemies: Array, feet: Vector2) -> void:
	for enemy in enemies:
		if int(enemy.get("_state")) != _st_telegraph:
			_dodged.erase(enemy.get_instance_id())
			continue
		if _dodged.has(enemy.get_instance_id()) or feet.distance_to(enemy.global_position) > DODGE_RADIUS:
			continue
		_dodged[enemy.get_instance_id()] = true
		if _rng.randf() < DODGE_CHANCE and _player.can_dash():
			_input.set_move((feet - enemy.global_position).normalized())
			_input.tap(_player_input_script.DASH)
		return


## Special rooms: walks up to everything usable once and presses E (shop, fountain, altar).
func _visit_special(room: Node) -> bool:
	if _special_target == null or not is_instance_valid(_special_target):
		_special_target = null
		for node in room.find_children("*", "Interactable", true, false):
			if not _visited.has(node.get_instance_id()) and node.is_available():
				_special_target = node
				break
	if _special_target == null:
		return false
	var focused: Node = _player.get("_focused_interactable")
	if focused == _special_target:
		_visited[_special_target.get_instance_id()] = true
		_log("SONDERRAUM", "drückt E bei „%s“" % TranslationServer.translate(StringName(String(_special_target.prompt))))
		_input.tap(_player_input_script.INTERACT)
		_special_target = null
		_progress("benutzt")
		return true
	_walk(_special_target.global_position, room)
	if _stuck_for > 3.0:
		_visited[_special_target.get_instance_id()] = true
		_special_target = null
	return true


## Walks to the exit gate (or the obstacle-run gate), then on into the next room.
func _go_exit(room: Node) -> void:
	var gate: Node = room.get_node_or_null(^"SideGate")
	var goal := Vector2.INF
	if gate != null and not bool(gate.is_used):
		goal = gate.global_position
	else:
		var doors: Array = room.get_exit_doors()
		if doors.is_empty():
			return
		var door: Node2D = doors[clampi(room.get_chosen_branch(), 0, doors.size() - 1)]
		var next: Node = _dungeon.get_room(_room_index + 1)
		if room.is_branch_room() and room.get_chosen_branch() < 0 and _t - _room_at > EXIT_TIMEOUT:
			room.choose_branch(0)
			_log("BOT", "Abzweigung: wählt den ersten Weg (Tool, nach %d s)" % int(EXIT_TIMEOUT))
		if _player.global_position.distance_to(door.global_position) <= DOOR_REACHED and next != null:
			_door_passed = true
		goal = next.get_player_start() if _door_passed and next != null else door.global_position
		if int(opt.debug) == 1 and Engine.get_physics_frames() % 60 == 0:
			print("    exit r%d feet=%s door=%s open=%s next=%s passed=%s stuck=%.1f los=%s" % [_room_index,
					_player.global_position.round(), door.global_position.round(), door.is_open,
					next.get_player_start().round() if next != null else Vector2.INF, _door_passed, _stuck_for,
					_line_of_sight(_player.global_position, goal)])
	_walk(goal, room)


func _side_step() -> void:
	_busy_reason = "Hindernislauf"
	_progress_soft()
	if _side_bot != null:
		return
	var transit: Node = _dungeon.get_side_transit()
	if transit == null or transit.segment == null:
		return
	_side_bot = _side_bot_script.drive(transit.segment, _player)
	var guarded := int(opt.side_guard) == 1
	if guarded:
		_player.hurtbox.set_invulnerable(&"newcomer_side", true)
	_log("HINDERNISLAUF", "Seitenansicht beginnt (Bot: SideBot%s)" % (", vom Tool geschützt: SideBot ist kein Neuling-Modell" if guarded else ""))


## A room the fighter cannot finish (modes like the escort, a stuck exit): logged as a bot limit,
## enemies removed, and after another minute the measurement ends.
func _check_room_timeout(room: Node) -> void:
	var stay := _t - _room_at
	if stay > float(opt.room_timeout) and not _timed_out.has(_room_index):
		_timed_out[_room_index] = true
		_log("BOT", "Raum %d nach %d s nicht verlassen (%s) – Tool räumt die Gegner ab (Grenze des Bots, kein Spielbefund)" % [
				_room_index, int(stay), _busy_reason])
		for enemy in _alive_enemies(room):
			enemy.health.take_damage(INF)
		var variant: Node = room.get_node_or_null(^"CombatVariant")
		if variant != null and variant.has_method(&"step"):
			variant.step(61.0)
	elif stay > float(opt.room_timeout) + 60.0 and not _ended_on_purpose:
		_log("BOT", "Raum %d bleibt hängen – Messung endet hier" % _room_index)
		_end_on_purpose()


func _end_on_purpose() -> void:
	if _ended_on_purpose:
		return
	_ended_on_purpose = true
	_log("ENDE", "Messung nach Raum %d beendet: Figur wird absichtlich besiegt, um Run-Ende und Rückkehr zu sehen" % _room_index)
	_player.health.take_damage(999999.0)


func _on_room_completed(index: int) -> void:
	_rooms_cleared = maxi(_rooms_cleared, index)
	if _player != null and is_instance_valid(_player):
		_log("RAUM", "Raum %d geschafft, Leben %.1f" % [index, _player.health.get_health()])
	_progress("Raum geschafft")


func _on_player_died() -> void:
	if _ended_on_purpose:
		return
	var cause := ""
	if _dungeon != null and is_instance_valid(_dungeon):
		cause = String(_dungeon.ui.get_last_hit_by(_player))
	var text := "Raum %d%s" % [_room_index, (" durch " + cause) if not cause.is_empty() else ""]
	_deaths.append(text)
	_ms.run_end = _t
	_log("TOD", text)


# --- Movement ---

func _walk(goal: Vector2, room: Node = null) -> void:
	var feet: Vector2 = _player.global_position
	if feet.distance_to(goal) <= ARRIVE * 0.5:
		return
	var point := goal
	if room != null and not _line_of_sight(feet, goal):
		var waypoint := _nav_waypoint(room, feet, goal)
		if waypoint != Vector2.INF:
			point = waypoint
	var direction := (point - feet).normalized()
	if _moved_too_little() and _sidestep_left <= 0.0:
		_sidestep_left = SIDESTEP_TIME
		_sidestep_dir = direction.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
	if _sidestep_left > 0.0:
		_sidestep_left -= FRAME
		direction = (direction * 0.3 + _sidestep_dir).normalized()
	_input.set_move(_avoid_pits(direction))


## Somebody who sees a hole walks around it: the nearest direction whose next steps stay on floor.
func _avoid_pits(direction: Vector2) -> Vector2:
	var fall: Object = _player.get("fall")
	if fall == null or direction == Vector2.ZERO:
		return direction
	var probe: Callable = fall.pit_probe
	if not probe.is_valid():
		return direction
	var feet: Vector2 = _player.get_feet_position()
	for angle: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.2, -2.2, PI]:
		var turned := direction.rotated(angle)
		if not bool(probe.call(feet + turned * 10.0)) and not bool(probe.call(feet + turned * 24.0)):
			return turned
	return direction


## Every frame before the bots step: did the feet move with last frame's wish to walk?
func _update_stuck() -> void:
	var feet: Vector2 = _player.global_position
	var wanted: bool = _input != null and _input.get("move") != Vector2.ZERO
	if _last_feet != Vector2.INF and wanted and feet.distance_to(_last_feet) < 0.4:
		_stuck_for += FRAME
	else:
		_stuck_for = 0.0
	_last_feet = feet


## True once the feet hardly moved for STUCK_TIME while the bot wanted to walk.
func _moved_too_little() -> bool:
	return _stuck_for >= STUCK_TIME


func _line_of_sight(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return _player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _nav_waypoint(room: Node, from: Vector2, goal: Vector2) -> Vector2:
	if _t - float(_nav_cache.t) < 0.3 and Vector2(_nav_cache.goal).distance_to(goal) < 24.0 and Vector2(_nav_cache.wp) != Vector2.INF \
			and from.distance_to(_nav_cache.wp) > 12.0:
		return _nav_cache.wp
	var map := RID()
	for layer in room.find_children("*", "TileMapLayer", true, false):
		var candidate: RID = (layer as TileMapLayer).get_navigation_map()
		if candidate.is_valid() and not NavigationServer2D.map_get_regions(candidate).is_empty():
			map = candidate
			break
	var waypoint := Vector2.INF
	if map.is_valid():
		for point in NavigationServer2D.map_get_path(map, from, goal, true):
			if point.distance_to(from) > 20.0:
				waypoint = point
				break
	_nav_cache = {"t": _t, "goal": goal, "wp": waypoint}
	return waypoint


func _input_clear() -> void:
	if _input != null:
		_input.clear()


func _locked() -> bool:
	return _player == null or _player.is_input_locked() or _flint_busy()


func _flint_busy() -> bool:
	var guide: Node = _guide_script.of(_player) if _player != null else null
	return guide != null and guide.current != null and guide.current.locks_player()


func _on_screen(point: Vector2) -> bool:
	var viewport := root.get_viewport()
	var screen: Vector2 = viewport.get_canvas_transform() * point
	return Rect2(Vector2.ZERO, viewport.get_visible_rect().size).has_point(screen)


# --- Progress and idle stretches ---

## Something meaningful happened (closer to the goal, a hit, a station, Flint, a dialog).
func _progress(_why: String) -> void:
	_close_idle()
	_progress_at = _t


## Busy without moving on (reading Flint or a dialog, an obstacle run): never counts as idle.
func _progress_soft() -> void:
	_progress_at = _t


func _watch_idle() -> void:
	if _phase == "Rückkehr" or _phase == "Hauptmenü":
		return
	if not _idle_open and _t - _progress_at > IDLE_LIMIT:
		_idle_open = true
		_idle_from = _progress_at
		_log("HÄNGT", "seit %d s nichts Sinnvolles: %s (Abstand zum Eingang %s)" % [int(IDLE_LIMIT), _describe_doing(),
				str(int(_entrance_distance())) + " px" if _village != null else "–"])


func _close_idle() -> void:
	if not _idle_open:
		return
	_idle_open = false
	var took := _t - _idle_from
	_stuck_list.append({"from": _idle_from, "seconds": took, "phase": _phase, "doing": _describe_doing()})
	_log("HÄNGT", "vorbei nach %.0f s" % took)


func _describe_doing() -> String:
	if _phase == "Dorf" or _phase == "Zuhause":
		if String(opt.mode) == "wander" and not _gave_up:
			return "irrt herum (%s, %d× angestoßen)" % [_phase, _bumps]
		return "folgt der Spur (Punkt %d/%d)" % [_trail_index, _trail.size()]
	return _busy_reason if not _busy_reason.is_empty() else _phase


# --- Log and report ---

func _log(kind: String, text: String) -> void:
	_events.append({"t": _t, "phase": _phase, "kind": kind, "text": text})
	if int(opt.quiet) == 0:
		print("%7.1f  %-11s %-12s %s" % [_t, _phase, kind, text])


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _seconds(seconds: float) -> void:
	await _frames(int(ceilf(seconds / FRAME)))


func _write_report() -> void:
	var folder := String(opt.out) if not String(opt.out).is_empty() else DEFAULT_OUT
	var absolute := ProjectSettings.globalize_path(folder)
	DirAccess.make_dir_recursive_absolute(absolute)
	var file_name := "newcomer_%s_%s_s%d.md" % [opt.mode, opt.read, int(opt.seed)]
	var path := absolute.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("newcomer_sim: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(_report_text())
	file.close()
	print("NEWCOMER mode=%s read=%s seed=%d %s -> %s" % [opt.mode, opt.read, int(opt.seed), _summary_line(), path])


func _since_village(key: String) -> String:
	var at := float(_ms[key])
	if at < 0.0 or float(_ms.village) < 0.0:
		return "–"
	return "%.1f s" % (at - float(_ms.village))


func _summary_line() -> String:
	return "tour_end=%s goal_clear=%s entrance=%s dungeon=%s room1=%s rooms=%d deaths=%d idle=%d" % [
		_since_village("tour_end"), _since_village("goal_clear"), _since_village("entrance_pressed"),
		_since_village("dungeon"), _since_village("room1"), _rooms_cleared, _deaths.size(), _stuck_list.size()]


func _report_text() -> String:
	var lines: Array[String] = []
	lines.append("# Neuling-Durchlauf: %s, Lesen %s, Seed %d" % [opt.mode, opt.read, int(opt.seed)])
	lines.append("")
	lines.append("Erzeugt von `tools/newcomer_sim.gd` am %s (Spielzeit in Sekunden, frischer Test-Spielstand)." % Time.get_datetime_string_from_system(false, true))
	lines.append("")
	lines.append("## Kernzahlen (ab Dorf-Start)")
	lines.append("")
	lines.append("| Messgröße | Wert |")
	lines.append("| --- | --- |")
	lines.append("| Hauptmenü bis Dorf | %.1f s |" % maxf(0.0, float(_ms.village)))
	lines.append("| Flints Rundgang vorbei | %s%s |" % [_since_village("tour_end"), " (übersprungen)" if _tour_skipped else ""])
	lines.append("| Ziel klar (Zielzeile sichtbar, Spieler frei) | %s |" % _since_village("goal_clear"))
	lines.append("| Eingang zum ersten Mal im Bild | %s |" % _since_village("entrance_seen"))
	lines.append("| Am Eingang angekommen | %s |" % _since_village("entrance_near"))
	lines.append("| E am Eingang gedrückt | %s |" % _since_village("entrance_pressed"))
	if String(opt.mode) == "wander":
		lines.append("| Aufgegeben, folgt dem Pfeil | %s |" % _since_village("gave_up"))
		lines.append("| Angestoßen / in Bewohner gelaufen | %d / %d |" % [_bumps, _villager_bumps])
		var used := PackedStringArray()
		for prompt in _wander_used:
			used.append(String(TranslationServer.translate(StringName(prompt))))
		lines.append("| Angesprochen | %s |" % (", ".join(used) if not used.is_empty() else "nichts"))
	lines.append("| Dungeon geladen | %s |" % _since_village("dungeon"))
	lines.append("| Übungsgang fertig | %s |" % _since_village("tutorial_end"))
	lines.append("| Raum 1 betreten | %s |" % _since_village("room1"))
	lines.append("| Räume geschafft | %d von %d |" % [_rooms_cleared, int(opt.rooms)])
	lines.append("| Tode | %s |" % ("; ".join(_deaths) if not _deaths.is_empty() else "keine"))
	lines.append("| Flint: Touren / Hinweise / Sätze / Sekunden | %d / %d / %d / %.0f |" % [_flint_count.tour, _flint_count.hint, _flint_count.sentences, _flint_count.seconds])
	lines.append("| Hängestellen (> %d s ohne Sinnvolles) | %d |" % [int(IDLE_LIMIT), _stuck_list.size()])
	lines.append("")
	lines.append("## Hängestellen")
	lines.append("")
	if _stuck_list.is_empty():
		lines.append("Keine.")
	for stuck in _stuck_list:
		lines.append("- ab %.0f s, %.0f s lang (%s): %s" % [stuck.from, stuck.seconds, stuck.phase, stuck.doing])
	lines.append("")
	lines.append("## Fragen eines Neulings – wo kommt das Wort zuerst vor?")
	lines.append("")
	lines.append("Erste Erwähnung, nicht unbedingt Erklärung (Stichwortsuche); bewerten muss man es selbst.")
	lines.append("")
	lines.append("| Frage | Flint sagt es zuerst | sonst gezeigt (Tastenzeile, Zielzeile, Dialog, Banner …) |")
	lines.append("| --- | --- | --- |")
	for question: Array in QUESTIONS:
		lines.append("| %s | %s | %s |" % [question[0], _first_mention(question[1], true), _first_mention(question[1], false)])
	lines.append("")
	lines.append("## Zeitleiste")
	lines.append("")
	lines.append("| t (s) | Phase | Art | Was |")
	lines.append("| ---: | --- | --- | --- |")
	for event in _events:
		lines.append("| %.1f | %s | %s | %s |" % [event.t, event.phase, event.kind, String(event.text).replace("|", "/").replace("\n", " ")])
	lines.append("")
	return "\n".join(lines)


## First event (a Flint sentence, or what the game shows elsewhere) whose text contains one of
## words: "12.3 s: „…“". A mention is not yet an explanation; the report reader judges.
func _first_mention(words: Array, flint: bool) -> String:
	for event in _events:
		var kind := String(event.kind)
		var text := String(event.text).to_lower()
		if flint and (kind != "FLINT" or not text.contains("„")):
			continue
		if not flint and (not SHOWN_KINDS.has(kind) or text.begins_with("drückt")):
			continue
		for word: String in words:
			if text.contains(word):
				return "%.0f s: „%s“" % [event.t, String(event.text).strip_edges().left(110)]
	return "nie"
