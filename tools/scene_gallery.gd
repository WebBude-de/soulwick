extends SceneTree
## Scene gallery for design work (needs a window, not --headless): PNG photos of the game as it looks
## today, weaknesses included - main menu, village, every combat template, special rooms, bosses,
## combat variants, arena and ambush, doors, the secret niche, the room chain and the dungeon UI.
## Two kinds of pictures: overview (whole room, full light, no HUD/dialogs) and game view (normal
## camera and darkness, HUD on, mid-fight).
## Writes <out>/NNN_<name>.png (running number over the phases taken) and a manifest with category
## and details per picture (user://scene_gallery_manifest.tsv) for the index.
##
## Usage: godot --path . -s tools/scene_gallery.gd -- [out_dir] [phases]
##   out_dir: default docs/design/szenen; relative paths start at the project folder
##   phases:  comma list of menu,village,run,branch,templates,special,variants,arena,doors,ui
##            (default: all of them in this order)
##
## Test storage only (SaveManager.set_storage_root), German texts, randomness only through fixed
## dungeon seeds. Real rooms come from seeded runs; every template, biome, special room and variant
## is built with the same steps as DungeonManager._prepare_slot ("staged" far away from the streamed
## rooms), because single-player runs never draw L templates and biomes start every 15 rooms.
## Game code is not changed: forced content goes through the existing test hooks (forced_ambush,
## forced_kind, forced_pact, BranchRules/SecretRules.chance_override, CombatVariant.attach_to).
## Classes are accessed dynamically: this script is compiled before the autoloads exist.

const STORAGE_ROOT := "user://scene_gallery_storage"
const MANIFEST_PATH := "user://scene_gallery_manifest.tsv"
const DEFAULT_OUT := "docs/design/szenen"
const PHASES: PackedStringArray = ["menu", "village", "run", "branch", "templates", "special", "variants", "arena", "doors", "ui"]
const WINDOW_SIZE := Vector2i(1920, 1080)
## Seeds of the dungeon runs (DungeonManager.seed_value).
const RUN_SEED := 7311
const BRANCH_SEED := 9157
const STAGE_SEED := 4711
## Staged rooms: far away from the streamed rooms, one column of 80 tiles each.
const STAGE_ORIGIN := Vector2(64 * 2000, -64 * 2000)
const STAGE_STEP := 64 * 80
## Room numbers per biome for staged rooms (cycle place 2 = normal combat room, no new-biome banner).
const BIOME_ROOMS: Array[int] = [7, 22, 37, 52]
const BIOME_SLUGS: Array[String] = ["krypta", "schleimgrotte", "schattenreich", "glutkammer"]
const SIDE_NAMES: Array[String] = ["Nord", "Ost", "Süd", "West"]
const SIDE_SLUGS: Array[String] = ["nord", "ost", "sued", "west"]
const UI_LAYERS: Array[StringName] = [&"Hud", &"GameUI", &"DungeonUI", &"VillageUI", &"BossIntroView"]
## RoomSequence.RoomType / SpecialType / RoomTiles.DoorSide values.
const COMBAT := 0
const SPECIAL := 2
const MINIBOSS := 3
const BOSS := 4
const CAMPFIRE := 5
const NORTH := 0
const EAST := 1
const SOUTH := 2
const WEST := 3
const TILE := 64.0

var _out := ""
var _phases: PackedStringArray = PHASES
var _counter := 0
var _manifest: Array[String] = []
var _seed := 0
var _controller: Node = null
var _dungeon: Node = null
var _player: Node = null
var _gallery_camera: Camera2D = null
var _stage_count := 0
var _hidden_layers: Array[Node] = []

var _seq: GDScript = null
var _tiles_script: GDScript = null
var _genre_script: GDScript = null


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_arg := DEFAULT_OUT
	if args.size() > 0 and not args[0].is_empty():
		out_arg = args[0]
	_out = out_arg if out_arg.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out_arg)
	if args.size() > 1 and not args[1].is_empty():
		_phases = args[1].split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	_write_gdignore()
	_seq = load("res://dungeon/room_sequence.gd")
	_tiles_script = load("res://dungeon/rooms/room_tiles.gd")
	_genre_script = load("res://ui/hints/room_genre.gd")
	var usable := DisplayServer.screen_get_usable_rect()
	if usable.size.x >= WINDOW_SIZE.x and usable.size.y >= WINDOW_SIZE.y:
		DisplayServer.window_set_size(WINDOW_SIZE)
		DisplayServer.window_set_position(usable.position + Vector2i(Vector2(usable.size - WINDOW_SIZE) * 0.5))
	AudioServer.set_bus_mute(0, true)
	_prepare_storage()
	node_added.connect(_on_node_added)
	print("scene gallery -> ", _out, " phases ", ",".join(_phases))
	for phase in PHASES:
		if not _phases.has(phase):
			continue
		print("--- phase ", phase)
		match phase:
			"menu":
				await _phase_menu()
			"village":
				await _phase_village()
			"run":
				await _phase_run()
			"branch":
				await _phase_branch()
			"templates":
				await _phase_templates()
			"special":
				await _phase_special()
			"variants":
				await _phase_variants()
			"arena":
				await _phase_arena()
			"doors":
				await _phase_doors()
			"ui":
				await _phase_ui()
		await _close_modals()
	_write_manifest()
	print("scene gallery done: %d pictures, manifest %s" % [_counter, ProjectSettings.globalize_path(MANIFEST_PATH)])
	quit()


# --- Storage, seeds ---

## Fresh test storage (never the real save or settings), German texts, one slot "Lena".
func _prepare_storage() -> void:
	_wipe(STORAGE_ROOT)
	var save_manager := root.get_node("SaveManager")
	save_manager.set_storage_root(STORAGE_ROOT)
	save_manager.set_option(&"language", "de")
	TranslationServer.set_locale("de")
	save_manager.create_slot(1, "Lena", &"hero")
	save_manager.add_permanent_gold(240)
	save_manager.add_permanent_crystals(3)
	save_manager.record_stat_max(&"deepest_room", 23)
	save_manager.add_stat(&"play_time", 3900.0)
	save_manager.save_game()


## An experienced player: no controls card, no first-time cards in the dungeon (the UI phase shows
## one on purpose: the catacomb stays unexplained), no enemy hints.
func _mark_experienced() -> void:
	var save_manager := root.get_node("SaveManager")
	save_manager.mark_seen(&"hint_controls")
	save_manager.mark_seen(&"hint_chasm")
	save_manager.mark_seen(&"hint_secret_wall")
	for genre: StringName in _genre_script.TABLE.keys():
		if genre != &"catacomb":
			_genre_script.mark_explained(genre)


func _on_node_added(node: Node) -> void:
	if _seed != 0 and node.get_script() != null and node.get_script().resource_path.ends_with("dungeon_manager.gd"):
		node.set(&"seed_value", _seed)


func _wipe(folder: String) -> void:
	var absolute := ProjectSettings.globalize_path(folder)
	for dir_path in [absolute.path_join("saves"), absolute]:
		var dir := DirAccess.open(dir_path)
		if dir != null:
			for file in dir.get_files():
				DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(absolute)


## The pictures are documents, not game assets: Godot must not import them.
func _write_gdignore() -> void:
	var path := _out.path_join(".gdignore")
	if not FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string("")


# --- Phase: main menu ---

func _phase_menu() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _seconds(2.2)
	await _shot("hauptmenue", "Menü", "Hauptmenü (Spielansicht), ein Spielstand vorhanden (Lena, tiefster Raum 23)")
	var menu: Node = current_scene.get("menu")
	if menu == null:
		print("menu missing")
		return
	menu.open_slots()
	await _seconds(0.4)
	await _shot("spielstaende", "Menü", "Spielstand-Auswahl mit einem belegten und freien Plätzen")
	var create: Node = menu.open_create(2)
	await _frames(5)
	if create != null:
		create.set_profile_name("Mira")
		await _seconds(0.4)
		await _shot("spielstand_anlegen", "Menü", "Neuen Spielstand anlegen, Name 'Mira' eingetragen")
		create.close()
	await _frames(5)
	menu.close_panel()
	await _frames(5)
	menu.play_slot(1)
	await _seconds(1.4)
	await _frames(30)


# --- Phase: village ---

func _phase_village() -> void:
	await _ensure_game()
	var village: Node = _controller.get_world()
	if village == null or village.get_script().get_global_name() != &"Village":
		_controller.load_world(_controller.village_scene)
		await _seconds(1.0)
		village = _controller.get_world()
	var player: Node = _controller.get_player()
	var camera: Camera2D = player.get_node("Camera2D")
	_set_village_time(village, 12.0)
	camera.reset_smoothing()
	await _seconds(0.8)
	await _shot("dorf_spielansicht_tag", "Dorf", "Dorf am Tag, Spielansicht am Startpunkt mit HUD")
	# Whole map at day and in the evening.
	var map: Rect2 = Rect2(village.get_camera_limits())
	var zoom := minf(1280.0 / map.size.x, 720.0 / map.size.y)
	_hide_ui(true)
	_use_gallery_camera(village, map.get_center(), zoom)
	await _seconds(0.5)
	await _shot("dorf_gesamt_tag", "Dorf", "Dorf, ganze Karte am Tag (12 Uhr), ohne HUD")
	_set_village_time(village, 19.5)
	await _seconds(0.8)
	await _shot("dorf_gesamt_abend", "Dorf", "Dorf, ganze Karte am Abend (19:30), Laternen und Glühwürmchen, ohne HUD")
	_hide_ui(false)
	camera.make_current()
	# Dungeon entrance up close, day and evening.
	var entrance: Node2D = village.get_node_or_null("Buildings/DungeonEntrance")
	if entrance != null:
		player.global_position = entrance.global_position + Vector2(0, 160)
		camera.reset_smoothing()
		_set_village_time(village, 12.0)
		await _seconds(0.8)
		await _shot("dorf_dungeon_eingang_tag", "Dorf", "Dungeon-Eingang nah am Tag, Spielansicht")
		_set_village_time(village, 19.5)
		await _seconds(0.8)
		await _shot("dorf_dungeon_eingang_abend", "Dorf", "Dungeon-Eingang nah am Abend, Spielansicht")
	_set_village_time(village, 12.0)
	# A building: first-visit explanation, then the dialog with values.
	var forge: Node2D = village.get_node_or_null("Buildings/Forge")
	if forge != null:
		player.global_position = forge.global_position + Vector2(200, 140)
		camera.reset_smoothing()
		await _seconds(0.5)
	village.enter_building(&"forge")
	await _seconds(1.4)
	await _shot("dorf_schmiede_erklaerung", "Dorf", "Schmiede betreten: Erklärkarte beim ersten Besuch")
	var intro: Node = village.ui.get_intro_modal()
	if intro != null:
		intro.finish()
	await _seconds(1.4)
	await _shot("dorf_schmiede_dialog", "Dorf", "Schmiede-Dialog mit dauerhaften Upgrades und Preisen")
	await _close_modals()
	await _seconds(0.5)


func _set_village_time(village: Node, hour: float) -> void:
	var daylight: GDScript = load("res://world/village/village_daylight.gd")
	var vision := _overlay()
	if vision != null:
		vision.set_dark_color(daylight.dark_color_for_hour(hour), true)
		vision.set_vision(daylight.darkness_for_hour(hour), daylight.VISION_RADIUS, true)
	var ambience: Node = village.get_node_or_null("Ambience")
	if ambience != null:
		var evening: bool = load("res://world/village/village_ambience.gd").is_evening(int(hour))
		ambience.apply_mode(1 if evening else 0)
		ambience.restart()


# --- Phase: real run (natural seed) ---

## Rooms 1-16 of a seeded run: enemies appearing, doors, corridor, chain, upgrade choice, the real
## crypt boss with its intro, the campfire and its dialog.
func _phase_run() -> void:
	await _start_dungeon(RUN_SEED)
	var taken := {}
	for index in range(1, 17):
		var room: Node = _dungeon.get_room(index)
		if room == null:
			print("room %d not prepared" % index)
			break
		var tiles: Node = room.get_node("Tiles")
		if index > 1:
			await _wait_for_quiet_ui()
			_player.global_position = room.get_player_start()
			_reset_player_camera()
		if index == 2:
			# Normal combat room the moment the enemies appear.
			await _frames(2)
			await _shot("gegner_erscheinen_1_kampfraum", "Erscheinen", "Normaler Kampfraum, direkt nach dem Betreten (Frame 2): %s" % _describe(room))
			await _seconds(0.25)
			await _shot("gegner_erscheinen_2_kampfraum", "Erscheinen", "Gleicher Raum 0,25 s später")
			await _seconds(0.6)
			await _shot("gegner_erscheinen_3_kampfraum", "Erscheinen", "Gleicher Raum 0,85 s nach dem Betreten")
		else:
			await _seconds(0.8)
		print("RUN ROOM ", _describe(room))
		if index == 1:
			await _shot("spielansicht_raum1_krypta", "Spielansicht", "Raum 1 der Krypta, Spielansicht mit HUD: %s" % _describe(room))
		if room.get_chosen_exit().x == NORTH and room.room_type == COMBAT and not taken.has("north"):
			taken["north"] = true
			await _door_shot(room, room.get_chosen_exit(), "tuer_nord_krypta_echt", "Tür", "Ausgangstür Nord in Raum %d (Kampfraum, Krypta), geschlossen, nah" % index)
		if index == 3:
			await _door_shot(room, room.get_chosen_exit(), "tuer_mit_spezialraum_symbol", "Tür", "Ausgangstür von Raum 3 mit Symbol des Spezialraums dahinter (Raum 4: %s)" % _special_name(_dungeon.get_room(4)))
		if index == 14:
			await _door_shot(room, room.get_chosen_exit(), "bosstor_krypta", "Tür", "Bosstor: Ausgang von Raum 14 (Krypta) vor dem Bossraum")
		if tiles.entrance_side != SOUTH and not taken.has("side_in"):
			taken["side_in"] = true
			await _door_shot(room, tiles.get_entrance_door(), "seitentuer_%s_eingang_echt" % SIDE_SLUGS[tiles.entrance_side], "Tür",
					"Seitentür als Eingang (%s) in Raum %d, echter Run, offen" % [SIDE_NAMES[tiles.entrance_side], index])
		var exit: Vector2i = room.get_chosen_exit()
		if exit.x != NORTH and not taken.has("side_out"):
			taken["side_out"] = true
			await _door_shot(room, exit, "seitentuer_%s_ausgang_echt" % SIDE_SLUGS[exit.x], "Tür",
					"Seitentür als Ausgang (%s) in Raum %d, echter Run, geschlossen" % [SIDE_NAMES[exit.x], index])
		if index >= 6 and _dungeon.get_live_room_count() >= 3 and not taken.has("chain"):
			taken["chain"] = true
			await _chain_shot("raumkette_drei_raeume", "Drei lebende Räume (%d-%d) einer echten Kette, weit herausgezoomt" % [index - 1, index + 1])
		if index == 15:
			# The real crypt boss: intro, then the room with the boss.
			await _seconds(0.8)
			await _shot("bossintro_krypta", "Bossraum", "Boss-Intro im echten Run (Raum 15, Krypta), Spielansicht")
			_skip_boss_intros()
			await _seconds(1.0)
			await _shot("bosskampf_krypta_spielansicht", "Bossraum", "Bosskampf Krypta nach dem Intro, Spielansicht mit Bossleiste")
			await _door_shot(room, room.get_chosen_exit(), "tuer_zum_lagerfeuer", "Tür", "Ausgang des Bossraums zum Lagerfeuer (Raum 15, Krypta), geschlossen")
		await _clear(room, "upgrade_wahl" if index == 3 else "")
		if room.has_method(&"is_branch_room") and room.is_branch_room():
			room.choose_branch(0)
			await _frames(10)
		_open_exit(room)
		await _frames(20)
		var next: Node = _dungeon.get_campfire(index) if index == 15 else _dungeon.get_room(index + 1)
		if next != null and (index == 1 or (exit.x != NORTH and not taken.has("corridor_side"))):
			if exit.x != NORTH:
				taken["corridor_side"] = true
			await _corridor_shot(room, next, "gang_%s_raum%d_zu_%d" % [SIDE_SLUGS[exit.x], index, index + 1],
					"Durchgang (Gang) zwischen Raum %d und %d, Ausgang %s, Tür offen" % [index, index + 1, SIDE_NAMES[exit.x]])
		if index == 15 and next != null:
			await _visit_campfire(next)
	# Run end: the player dies for real in room 16.
	await _wait_for_quiet_ui()
	_player.hurtbox.set_invulnerable(&"gallery", false)
	_player.health.take_damage(9999.0)
	await _seconds(3.2)
	await _shot("run_ende", "UI", "Run-Ende nach dem Tod in Raum 16 (echter Run, echte Zusammenfassung)")
	await _close_modals()
	await _seconds(1.5)


## The campfire behind the real boss: overview, the second chain picture, the rest dialog.
func _visit_campfire(campfire: Node) -> void:
	_player.global_position = campfire.get_player_start()
	_reset_player_camera()
	await _seconds(1.2)
	await _shot("lagerfeuer_spielansicht", "Spezialraum", "Lagerfeuer nach dem Krypta-Boss, Spielansicht mit HUD (Genre-Banner)")
	await _room_overview(campfire, "lagerfeuer_krypta_zu_schleimgrotte", "Spezialraum", "Lagerfeuer zwischen Krypta und Schleimgrotte (echter Run): %s" % _describe(campfire), 0)
	await _chain_shot("raumkette_mit_lagerfeuer", "Bossraum, Lagerfeuer und Raum 16 als Kette, weit herausgezoomt")
	_restore_vision(campfire)
	var content: Node = campfire.get_campfire_content()
	if content != null and content.get("_interactable") != null:
		if _player.health.get_health() > 2.0:
			_player.health.take_damage(1.0)
		content.get("_interactable").interact(_player)
		await _seconds(0.7)
		await _shot("lagerfeuer_dialog", "UI", "Lagerfeuer-Dialog (Rast: heilen oder Upgrade verstärken)")
	await _close_modals()
	_open_exit(campfire)
	await _frames(10)


# --- Phase: branch and secret niche (overrides) ---

func _phase_branch() -> void:
	var branch_rules: GDScript = load("res://dungeon/rooms/branches/branch_rules.gd")
	var secret_rules: GDScript = load("res://dungeon/rooms/secrets/secret_rules.gd")
	branch_rules.chance_override = 1.0
	secret_rules.chance_override = 1.0
	await _start_dungeon(BRANCH_SEED)
	var taken := {}
	for index in range(1, 26):
		var room: Node = _dungeon.get_room(index)
		if room == null:
			break
		if index > 1:
			await _wait_for_quiet_ui()
			_player.global_position = room.get_player_start()
			_reset_player_camera()
		await _seconds(0.5)
		var niche: Node = room.get_node_or_null("SecretNiche")
		print("BRANCH RUN ", _describe(room))
		if niche != null and not taken.has("niche"):
			# Game view first: the player in front of the cracked wall, normal darkness.
			_player.global_position = room.to_global((Vector2(niche.site.approach) + Vector2(0.5, 1.6)) * TILE)
			_reset_player_camera()
			await _seconds(0.6)
			await _shot("geheimnische_vorher_spielansicht", "Geheimnis", "Rissige Wand vor dem Sprengen, Spielansicht (normale Dunkelheit): Raum %d" % index)
			await _overview_at(room.to_global((Vector2(niche.site.crack) + Vector2(0.5, 0.0)) * TILE), 1.4,
					"geheimnische_vorher", "Geheimnis", "Rissige Wand / Geheimnische vor dem Sprengen, volles Licht, nah: Raum %d (%s)" % [index, _biome_name(room)])
			_restore_vision(room)
		await _clear(room, "")
		if niche != null and not taken.has("niche"):
			taken["niche"] = true
			var blast: Node = load("res://dungeon/rooms/ingredients/barrel_blast.gd").create(96.0, 0.0, 0.0, 0.0)
			room.add_child(blast)
			blast.global_position = room.to_global((Vector2(niche.site.approach) + Vector2(0.5, 0.2)) * TILE)
			await _seconds(0.9)
			if niche.has_method(&"break_open"):
				niche.break_open()
			await _seconds(0.6)
			await _overview_at(room.to_global((Vector2(niche.site.crack) + Vector2(0.5, 0.0)) * TILE), 1.4,
					"geheimnische_nachher", "Geheimnis", "Geheimnische nach dem Sprengen, volles Licht, nah: Raum %d" % index)
			_restore_vision(room)
			_player.global_position = room.to_global((Vector2(niche.site.approach) + Vector2(0.5, 1.6)) * TILE)
			_reset_player_camera()
			await _seconds(0.5)
			await _shot("geheimnische_nachher_spielansicht", "Geheimnis", "Geöffnete Nische, Spielansicht (normale Dunkelheit)")
		if room.is_branch_room() and not taken.has("branch"):
			taken["branch"] = true
			await _seconds(0.5)
			await _room_overview(room, "abzweigung_raum_uebersicht", "Tür", "Abzweigungsraum nach dem Kampf, zwei Ausgangstüren mit Weg-Symbolen: %s" % _describe(room), 0)
			var doors: Array = room.get_node("Tiles").get_exit_doors()
			if doors.size() == 2:
				var a: Vector2 = _door_world(room, doors[0])
				var b: Vector2 = _door_world(room, doors[1])
				var need: Vector2 = (a - b).abs() + Vector2(8, 6) * TILE
				var zoom := clampf(minf(1280.0 / need.x, 720.0 / need.y), 0.5, 1.6)
				await _overview_at((a + b) * 0.5 + Vector2(0, TILE * 1.5), zoom, "abzweigung_zwei_tueren", "Tür",
						"Abzweigung: beide Ausgangstüren nah (%s / %s)" % [_option_name(room, 0), _option_name(room, 1)])
			_restore_vision(room)
			room.choose_branch(0)
			await _frames(10)
		elif room.is_branch_room():
			room.choose_branch(0)
			await _frames(10)
		_open_exit(room)
		if room.room_type == BOSS:
			var campfire: Node = _dungeon.get_campfire(index)
			if campfire != null:
				_player.global_position = campfire.get_player_start()
				await _seconds(0.5)
				_open_exit(campfire)
		if taken.has("niche") and taken.has("branch"):
			break
	branch_rules.chance_override = -1.0
	secret_rules.chance_override = -1.0
	if not taken.has("niche"):
		print("no secret niche found")
	if not taken.has("branch"):
		print("no branch room found")


# --- Phase: every combat template ---

func _phase_templates() -> void:
	await _ensure_stage()
	var catalog: Object = load("res://dungeon/rooms/room_catalog.gd").load_default()
	var template_script: GDScript = load("res://dungeon/rooms/templates/room_template.gd")
	var entries: Array = []
	var seen := {}
	for entry in catalog.get_entries():
		if entry == null or entry.scene == null or seen.has(entry.id):
			continue
		seen[entry.id] = true
		entries.append(entry)
	entries.sort_custom(func(a, b) -> bool:
		return int(a.room_kind) * 1000 + int(a.shape) * 10 + int(a.size_class) < int(b.room_kind) * 1000 + int(b.shape) * 10 + int(b.size_class))
	var kind_slugs := ["kampfraum", "arena", "abgrund"]
	var size_names := ["S", "M", "L"]
	for i in entries.size():
		var entry: Resource = entries[i]
		var biome := i % 4
		var index := BIOME_ROOMS[biome]
		var room := _stage(entry.scene, index, COMBAT)
		await _frames(12)
		var shape_name: String = template_script.get_shape_name(entry.shape)
		var slug := "%s_%s_%s_%s" % [kind_slugs[int(entry.room_kind)], _slug(shape_name), size_names[int(entry.size_class)].to_lower(), BIOME_SLUGS[biome]]
		if String(entry.id).begins_with("combat_"):
			slug += "_alt"
		var details := "Vorlage %s (%s, %s, Größe %s, %dx%d Kacheln): %s" % [entry.id, kind_slugs[int(entry.room_kind)], shape_name,
				size_names[int(entry.size_class)], entry.room_size.x, entry.room_size.y, _describe(room)]
		await _room_overview(room, slug, "Kampfraum-Vorlage", details, 1)
		_unstage(room)
		await _frames(4)


# --- Phase: special rooms, minibosses, bosses ---

func _phase_special() -> void:
	await _ensure_stage()
	var special_room: PackedScene = _dungeon.special_template
	var trial_room: PackedScene = load("res://dungeon/rooms/special/special_table.gd").get_template_for(4)
	# [slug, special type, room number, trial kind, pact, details]
	var list := [
		["shop", 0, 4, -1, -1, "Shop"],
		["waffenwahl", 1, 19, -1, -1, "Waffenwahl"],
		["brunnen", 2, 34, -1, -1, "Brunnen"],
		["upgrade_altar", 3, 49, -1, 0, "Upgrade-Altar"],
		["pakt_altar", 3, 34, -1, 1, "Pakt-Altar"],
		["pruefung_spiessrutenlauf", 4, 49, 0, -1, "Prüfung Spießrutenlauf"],
		["pruefung_lichtlauf", 4, 4, 1, -1, "Prüfung Lichtlauf"],
		["pruefung_broeckelboden", 4, 19, 2, -1, "Prüfung Bröckelboden"],
	]
	for item in list:
		var scene: PackedScene = trial_room if item[1] == 4 else special_room
		var room := _stage(scene, item[2], SPECIAL, {"special": item[1], "trial": item[3], "pact": item[4]})
		await _frames(6)
		await _enter_staged(room)
		await _seconds(1.0)
		var biome_slug: String = BIOME_SLUGS[_biome_of(item[2])]
		if item[1] == 4 and item[3] == 1:
			await _shot("%s_%s_spielansicht" % [item[0], biome_slug], "Spezialraum", "%s, Spielansicht (eigene Dunkelheit)" % item[5])
		await _room_overview(room, "%s_%s" % [item[0], biome_slug], "Spezialraum", "%s: %s" % [item[5], _describe(room)], 0)
		_restore_vision(room)
		# The dialog of the room (shop, weapons, altar, pact), as the player opens it with E.
		if item[1] != 4:
			var interactable := _find_interactable(room)
			if interactable != null:
				_player.global_position = interactable.global_position + Vector2(0, 70)
				_reset_player_camera()
				await _seconds(0.5)
				if item[1] == 0:
					await _shot("shop_spielansicht", "Spezialraum", "Shop, Spielansicht mit HUD vor dem Händler")
				if item[1] == 1 and _player.weapon_controller.find_free_slot() >= 0:
					# Both slots full, so the weapon swap dialog opens (a player with two weapons).
					_player.weapon_controller.equip_weapon(load("res://weapons/data/dagger.tres"), _player.weapon_controller.find_free_slot())
				interactable.interact(_player)
				await _seconds(0.8)
				if _find_modal(root) != null:
					await _shot("%s_dialog" % item[0], "UI", "%s: Dialog nach Interaktion (E)" % item[5])
					if item[4] == 1:
						# Pact: the second option shows the stronger offer.
						var modal := _find_modal(root)
						modal.finish(1)
						await _seconds(0.6)
						if _find_modal(root) != null:
							await _shot("pakt_angebot", "UI", "Pakt-Altar: Angebot nach 'Pakt schließen'")
							# Not sealed: a curse would change every later picture (light circle, HP).
							for open_modal in _modals():
								open_modal.finish(null)
				else:
					print("no dialog for ", item[0])
				await _close_modals()
		_unstage(room)
		await _frames(4)
	# Campfires of two other biome changes.
	var campfire_scene: PackedScene = load("res://dungeon/rooms/campfire/campfire_room.tscn")
	for index: int in [30, 60]:
		var room := _stage(campfire_scene, index, CAMPFIRE, {"portal": true})
		await _frames(10)
		var next_slug: String = BIOME_SLUGS[_biome_of(index + 1)]
		await _room_overview(room, "lagerfeuer_%s_zu_%s" % [BIOME_SLUGS[_biome_of(index)], next_slug], "Spezialraum",
				"Lagerfeuer nach Raum %d: %s" % [index, _describe(room)], 0)
		_unstage(room)
		await _frames(4)
	# Miniboss rooms (champion with escort).
	for index: int in [10, 40]:
		var room := _stage(_dungeon.miniboss_template, index, MINIBOSS)
		await _frames(6)
		await _enter_staged(room)
		await _seconds(1.4)
		await _room_overview(room, "miniboss_raum_%s" % BIOME_SLUGS[_biome_of(index)], "Bossraum", "Miniboss-Raum mit Champion und Begleitern: %s" % _describe(room), 0)
		_unstage(room)
		await _frames(4)
	# Boss rooms of every biome, with the boss after its intro.
	for index: int in [15, 30, 45, 60]:
		var room := _stage(_dungeon.boss_template, index, BOSS)
		await _frames(6)
		await _enter_staged(room)
		await _seconds(1.0)
		_skip_boss_intros()
		await _seconds(1.2)
		var boss := ""
		for enemy in _enemies(room):
			boss = str(enemy.data.display_name) if enemy.data != null else enemy.name
			break
		await _room_overview(room, "bossraum_%s" % BIOME_SLUGS[_biome_of(index)], "Bossraum", "Bossraum Raum %d mit Boss '%s': %s" % [index, boss, _describe(room)], 0)
		_unstage(room)
		await _frames(4)


# --- Phase: combat variants ---

func _phase_variants() -> void:
	await _ensure_stage()
	# [variant id, slug, room number, templates to try]
	var list := [
		[&"soul_flame", "seelenflamme", 22, ["normal_rectangle_m", "normal_ring_m"]],
		[&"rifts", "beschwoerungsrisse", 37, ["normal_cross_m", "normal_rectangle_m"]],
		[&"gravedigger", "totengraeber", 7, ["normal_pillar_hall_m", "normal_rectangle_m"]],
		[&"bounty", "kopfgeld", 52, ["normal_ring_m", "normal_rectangle_m"]],
		[&"stone_guardian", "steinwaechter", 38, ["normal_two_chambers_m", "normal_rectangle_m"]],
		[&"lantern", "laternentraeger", 8, ["normal_l_shape_m", "normal_rectangle_m"]],
		[&"torch_room", "fackelraum", 36, ["normal_rectangle_m", "normal_cross_m"]],
		[&"elite_nest", "elite_nest", 53, ["normal_cross_m", "normal_rectangle_m"]],
		[&"wager", "wagnis_altar", 23, ["normal_ring_s", "normal_rectangle_m"]],
	]
	for item in list:
		var room: Node = null
		for template_id: String in item[3]:
			var scene: PackedScene = load("res://dungeon/rooms/combat/%s.tscn" % template_id)
			room = _stage(scene, item[2], COMBAT)
			await _frames(4)
			if _attach_variant(room, item[0]):
				break
			_unstage(room)
			room = null
			await _frames(4)
		if room == null:
			print("variant %s could not be attached" % item[0])
			continue
		var biome_slug: String = BIOME_SLUGS[_biome_of(item[2])]
		await _enter_staged(room)
		# After the genre banner (about 3.6 s on screen), the fight is under way.
		await _fight(4.2)
		await _shot("variante_%s_%s_spielansicht" % [item[1], biome_slug], "Kampf-Variante", "Variante %s mitten im Kampf (4 s nach dem Betreten), Spielansicht: %s" % [item[0], _describe(room)])
		await _room_overview(room, "variante_%s_%s_uebersicht" % [item[1], biome_slug], "Kampf-Variante", "Variante %s mitten im Kampf, ganzer Raum: %s" % [item[0], _describe(room)], 0)
		_unstage(room)
		await _frames(4)


## Hangs a combat variant, the elite nest or the wager altar onto a staged room (like _prepare_slot).
func _attach_variant(room: Node, id: StringName) -> bool:
	var context: Object = _dungeon.context
	if id == &"elite_nest":
		return (load("res://dungeon/variants/elite_nest_variant.gd") as GDScript).call(&"attach", room, context.rng.randi()) != null
	var pick: Object = load("res://dungeon/variants/variant_table.gd").Pick.new()
	if id == &"wager":
		pick.wager = true
	else:
		pick.variant_id = id
	load("res://dungeon/variants/room_variants.gd").attach(room, pick, context.rng)
	if id == &"wager":
		var altar: Node = room.get_node_or_null("WagerAltar")
		if altar == null:
			return false
		altar.accept(_player)
		return true
	return room.get_variant_id() == id


# --- Phase: arena and ambush ---

func _phase_arena() -> void:
	await _ensure_stage()
	# Arena: enemies step out of the walls right after entering.
	var arena := _stage(load("res://dungeon/rooms/combat/arena_pillar_hall_m.tscn"), 22, COMBAT, {"ambush": 0})
	await _frames(10)
	await _enter_staged(arena)
	await _seconds(0.2)
	await _shot("arena_1_wand_bricht_auf", "Arena/Hinterhalt", "Arena (Säulenhalle M, Schleimgrotte) 0,2 s nach dem Betreten: Wand-Tore kündigen sich an")
	await _seconds(0.25)
	await _room_overview(arena, "arena_uebersicht_tore", "Arena/Hinterhalt", "Arena ca. 0,5 s nach dem Betreten, ganzer Raum (alle Wand-Tore): %s" % _describe(arena), 0)
	_restore_vision(arena)
	await _seconds(0.1)
	await _shot("arena_2_gegner_treten_heraus", "Arena/Hinterhalt", "Arena ca. 0,75 s: Gegner treten aus der Wand")
	await _seconds(0.45)
	await _shot("arena_3_gegner_im_raum", "Arena/Hinterhalt", "Arena ca. 1,2 s: erste Welle im Raum")
	await _room_overview(arena, "arena_uebersicht_erste_welle", "Arena/Hinterhalt", "Arena mitten in der ersten Welle, ganzer Raum: %s" % _describe(arena), 0)
	_unstage(arena)
	await _frames(6)
	# Ambush: looks empty, breaks open when the door closes behind the player.
	var ambush := _stage(load("res://dungeon/rooms/combat/arena_cross_m.tscn"), 52, COMBAT, {"ambush": 1})
	await _frames(10)
	await _room_overview(ambush, "hinterhalt_vorher_leer", "Arena/Hinterhalt", "Hinterhalt vor dem Betreten (wirkt leer): %s" % _describe(ambush), 1)
	await _enter_staged(ambush)
	await _seconds(0.1)
	await _shot("hinterhalt_1_tuer_schliesst", "Arena/Hinterhalt", "Hinterhalt (Kreuz M, Glutkammer) 0,1 s: Tür schließt hinter dem Spieler")
	await _seconds(0.45)
	await _shot("hinterhalt_2_ausbruch", "Arena/Hinterhalt", "Hinterhalt 0,55 s: Ausbruch aus den Wänden")
	await _room_overview(ambush, "hinterhalt_uebersicht_ausbruch", "Arena/Hinterhalt", "Hinterhalt ca. 0,7 s, ganzer Raum beim Ausbruch: %s" % _describe(ambush), 0)
	_restore_vision(ambush)
	await _seconds(0.3)
	await _shot("hinterhalt_3_gegner_treten_heraus", "Arena/Hinterhalt", "Hinterhalt ca. 1,1 s: Gegner treten heraus")
	await _seconds(0.6)
	await _shot("hinterhalt_4_kampf", "Arena/Hinterhalt", "Hinterhalt 1,6 s: Kampf läuft")
	_unstage(ambush)
	await _frames(6)


# --- Phase: doors ---

func _phase_doors() -> void:
	await _ensure_stage()
	var rectangle: PackedScene = load("res://dungeon/rooms/combat/normal_rectangle_m.tscn")
	for biome in 4:
		var room := _stage(rectangle, BIOME_ROOMS[biome], COMBAT)
		await _frames(10)
		_overlay().set_biome(room.spawner.get_biome(room.room_index), true)
		await _door_shot(room, room.get_chosen_exit(), "tuer_nord_%s" % BIOME_SLUGS[biome], "Tür", "Nordtür (Ausgang, geschlossen) in %s, nah" % _biome_name(room))
		if biome == 0:
			await _door_shot(room, room.get_node("Tiles").get_entrance_door(), "tuer_sued_eingang_%s" % BIOME_SLUGS[biome], "Tür", "Eingangstür Süd (offen) in %s, nah" % _biome_name(room))
		_unstage(room)
		await _frames(4)
	# Side doors: entered from the west, leaving to the east.
	var ring: PackedScene = load("res://dungeon/rooms/combat/normal_ring_m.tscn")
	for biome: int in [1, 2]:
		var probe: Node = ring.instantiate()
		var tiles: Node = probe.get_node("Tiles")
		var west: Array = tiles.get_door_slots(WEST)
		var east: Array = tiles.get_door_slots(EAST)
		probe.free()
		if west.is_empty() or east.is_empty():
			print("ring template has no side door places")
			break
		var room := _stage(ring, BIOME_ROOMS[biome], COMBAT, {"entrance": Vector2i(WEST, west[0]), "exits": [Vector2i(EAST, east[0])]})
		await _frames(10)
		await _door_shot(room, Vector2i(WEST, west[0]), "seitentuer_west_eingang_%s" % BIOME_SLUGS[biome], "Tür", "Seitentür West als Eingang (offen) in %s, nah" % _biome_name(room))
		await _door_shot(room, Vector2i(EAST, east[0]), "seitentuer_ost_ausgang_%s" % BIOME_SLUGS[biome], "Tür", "Seitentür Ost als Ausgang (geschlossen) in %s, nah" % _biome_name(room))
		_unstage(room)
		await _frames(4)
	# Boss gates of the other biomes: the special room before the boss room.
	for index: int in [29, 44, 59]:
		var room := _stage(_dungeon.special_template, index, SPECIAL, {"special": 2})
		await _frames(10)
		await _door_shot(room, room.get_chosen_exit(), "bosstor_%s" % BIOME_SLUGS[_biome_of(index)], "Tür", "Bosstor: Ausgang von Raum %d (%s) vor dem Bossraum, nah" % [index, _biome_name(room)])
		_unstage(room)
		await _frames(4)


# --- Phase: dungeon UI ---

func _phase_ui() -> void:
	await _ensure_stage()
	var context: Object = _dungeon.context
	var ui: Node = _dungeon.get_node("DungeonUI")
	var by_id := {}
	for file in DirAccess.get_files_at("res://upgrades/data/"):
		if file.ends_with(".tres"):
			var upgrade: Resource = load("res://upgrades/data/" + file)
			by_id[upgrade.id] = upgrade
	for id: StringName in [&"wide_swing", &"strong_attack", &"strong_attack", &"shield_boost", &"heal_on_kill"]:
		if by_id.has(id):
			context.upgrade_manager.acquire_upgrade(by_id[id])
	root.get_node("RunManager").add_run_gold(55)
	_player.weapon_controller.equip_weapon(load("res://weapons/data/bow.tres"), 1)
	if _player.health.get_health() > 3.0:
		_player.health.take_damage(2.0)
	# HUD mid-fight.
	var room := _stage(load("res://dungeon/rooms/combat/normal_cross_m.tscn"), 37, COMBAT)
	await _frames(8)
	await _enter_staged(room)
	await _fight(4.2)
	await _shot("hud_im_kampf", "UI", "HUD im Kampf (Schattenreich, Raum 37): Herzen, Waffen, Gold, Upgrades: %s" % _describe(room))
	ui.show_upgrade_overview()
	await _seconds(0.6)
	await _shot("tab_uebersicht", "UI", "Tab-Übersicht mit Upgrades, Werten und zweiter Waffe")
	await _close_modals()
	var game_ui: Node = current_scene.get_node("GameUI")
	game_ui.open_pause_menu()
	await _seconds(0.6)
	await _shot("pause_menue", "UI", "Pause-Menü (Esc)")
	game_ui.open_options()
	await _seconds(0.6)
	await _shot("pause_optionen", "UI", "Pause, Optionen geöffnet")
	await _close_modals()
	await _close_modals()
	_unstage(room)
	await _frames(6)
	# Genre banner with the first-time card: a catacomb (its explanation is shown again on purpose).
	root.get_node("SaveManager").get(&"_seen").erase(_genre_script.get_seen_id(&"catacomb"))
	var catacomb := _stage(load("res://dungeon/rooms/combat/normal_catacomb_m.tscn"), 22, COMBAT)
	await _frames(8)
	await _enter_staged(catacomb)
	await _seconds(0.9)
	await _shot("genre_banner_katakombe_mit_erklaerkarte", "UI", "Genre-Banner 'Katakombe' mit Erklärkarte beim ersten Betreten (Schleimgrotte)")
	await _seconds(1.0)
	_unstage(catacomb)
	await _frames(6)


# --- Dungeon setup and staging ---

func _ensure_game() -> void:
	if current_scene == null or current_scene.scene_file_path != "res://scenes/game.tscn":
		var save_manager := root.get_node("SaveManager")
		save_manager.load_slot(1)
		change_scene_to_file("res://scenes/game.tscn")
		await _seconds(1.5)
	_controller = current_scene.get_node("WorldController")


## A fresh run with the given seed; the player cannot be hurt, the first-time teaching is skipped.
func _start_dungeon(seed_value: int) -> void:
	await _ensure_game()
	await _close_modals()
	_mark_experienced()
	_seed = seed_value
	_controller.enter_dungeon()
	await _frames(40)
	_dungeon = _controller.get_world()
	_player = _controller.get_player()
	_player.hurtbox.set_invulnerable(&"gallery", true)
	_gallery_camera = null
	var ui: Node = _dungeon.get_node("DungeonUI")
	ui.set(&"auto_enemy_hints", false)
	await _seconds(0.6)


## The staging dungeon: a fresh seeded run, room 1 cleared so nothing follows the player.
func _ensure_stage() -> void:
	if _dungeon != null and is_instance_valid(_dungeon) and _seed == STAGE_SEED and _player != null and is_instance_valid(_player) and _player.is_alive():
		return
	await _start_dungeon(STAGE_SEED)
	var first: Node = _dungeon.get_room(1)
	for enemy in _enemies(first):
		enemy.health.take_damage(INF)
	await _seconds(2.2)
	await _close_modals()


## Builds a room like DungeonManager._prepare_slot (setup, door plan, ingredients, encounter group),
## far away from the streamed rooms. opts: special, trial, pact, portal, ambush, entrance, exits.
func _stage(scene: PackedScene, index: int, room_type: int, opts := {}) -> Node:
	var context: Object = _dungeon.context
	var room: Node = scene.instantiate()
	_stage_count += 1
	room.name = "GalleryRoom%d" % _stage_count
	var combat: bool = _seq.is_normal_combat(room_type)
	room.rolled_kind = int(room.room_kind) if combat else -1
	var slot: int = _seq.get_slot_for_room(index)
	room.slot_index = slot + 1 if room_type == CAMPFIRE else slot
	room.setup(index, room_type, int(opts.get("special", -1)), bool(opts.get("portal", false)), context, false)
	if opts.has("ambush"):
		room.forced_ambush = int(opts["ambush"])
	var tiles: Node = room.get_node("Tiles")
	var entrance: Vector2i = opts.get("entrance", Vector2i(SOUTH, tiles.entrance_x))
	var exits: Array[Vector2i] = []
	exits.assign(opts.get("exits", [Vector2i(NORTH, tiles.exit_x)]))
	room.apply_door_plan(entrance, exits, 0)
	room.position = STAGE_ORIGIN + Vector2(STAGE_STEP * (_stage_count % 40), 0)
	var trial := int(opts.get("trial", -1))
	var pact := int(opts.get("pact", -1))
	if trial >= 0 or pact >= 0:
		room.child_entered_tree.connect(func(child: Node) -> void:
			if trial >= 0 and &"forced_kind" in child:
				child.set(&"forced_kind", trial)
			if pact >= 0 and &"forced_pact" in child:
				child.set(&"forced_pact", pact))
	_dungeon.add_child(room)
	if combat:
		var variation: GDScript = load("res://dungeon/rooms/ingredients/encounter_variation.gd")
		var plan: Object = variation.roll(index, room_type, context.rng, room.room_kind)
		room.set_encounter_group(variation.build_group(plan, index, room.spawner.get_biome(index)))
	room.encounter_started.connect(_dungeon._on_encounter_started)
	room.wave_started.connect(_dungeon._on_wave_started)
	return room


## The player walks into a staged room: room number, darkness and genre banner like
## DungeonManager._on_player_entered_room, then the room starts.
func _enter_staged(room: Node) -> void:
	await _wait_for_quiet_ui()
	var run_manager := root.get_node("RunManager")
	run_manager.set(&"_current_room", room.room_index)
	run_manager.room_changed.emit(room.room_index)
	_player.global_position = room.get_player_start()
	_reset_player_camera()
	_dungeon._apply_vision(room)
	room.activate()
	await _frames(2)


## Banners and teaching cards of the previous room are gone (a player needs a moment to walk over).
func _wait_for_quiet_ui(limit := 8.0) -> void:
	var ui: Node = _dungeon.get_node("DungeonUI")
	var waited := 0.0
	while waited < limit and (ui.get_banner() != null or ui.get_banner_queue_size() > 0 or is_instance_valid(ui.get(&"_hint_card"))):
		await _seconds(0.2)
		waited += 0.2


func _unstage(room: Node) -> void:
	_skip_boss_intros()
	var ui: Node = _dungeon.get_node("DungeonUI")
	ui.hide_boss_bar()
	for modal in _modals():
		modal.finish(modal.cancel_result)
	var first: Node = _dungeon.get_room(1)
	if first != null:
		_player.global_position = first.get_player_start()
		_reset_player_camera()
	if is_instance_valid(room):
		room.queue_free()


# --- Pictures ---

## Overview of a whole room: own camera fitted to the floor, full light, no HUD, no dialogs.
## extra_tiles: margin around the floor (walls, rock ring, corridors).
func _room_overview(room: Node, slug: String, category: String, details: String, extra_tiles := 0) -> void:
	var tiles: Node = room.get_node("Tiles")
	var rect: Rect2 = tiles.get_floor_rect()
	var need: Vector2 = rect.size + Vector2(4 + extra_tiles, 5 + extra_tiles) * TILE
	var zoom := minf(1280.0 / need.x, 720.0 / need.y)
	_overlay().set_biome(room.spawner.get_biome(room.room_index), true)
	await _overview_at(room.to_global(rect.get_center()), zoom, slug, category, details)


func _overview_at(center: Vector2, zoom: float, slug: String, category: String, details: String) -> void:
	var dungeon_ui: Node = _dungeon.get_node_or_null("DungeonUI") if _dungeon != null and is_instance_valid(_dungeon) else null
	_hide_ui(true)
	if dungeon_ui != null:
		dungeon_ui.visible = false
	_use_gallery_camera(_controller.get_world(), center, zoom)
	_light_full()
	await _frames(8)
	await _shot(slug, category, details + " | Übersicht (volles Licht, ohne HUD), Zoom %.2f" % zoom)
	_hide_ui(false)
	if dungeon_ui != null:
		dungeon_ui.visible = true
	_reset_player_camera()


## A door up close: a little floor in front of it, full light, no HUD.
func _door_shot(room: Node, door: Vector2i, slug: String, category: String, details: String) -> void:
	var tiles: Node = room.get_node("Tiles")
	var tile: Vector2i = _tiles_script.door_tile_of(door.x, door.y, tiles.room_size)
	var outward: Vector2 = Vector2(_tiles_script.SIDE_DIRECTIONS[door.x])
	# A little inwards, so a north door's arch and the wall beside it stay in the picture.
	var center: Vector2 = room.to_global(_tiles_script.tile_center(tile) - outward * TILE * 0.6)
	await _overview_at(center, 1.6, slug, category, details + " (%s)" % _biome_name(room))
	_restore_vision(room)


## Corridor between a room's exit and the next room's entrance.
func _corridor_shot(room: Node, next: Node, slug: String, details: String) -> void:
	var a: Vector2 = _door_world(room, room.get_chosen_exit())
	var b: Vector2 = next.to_global(_tiles_script.tile_center(next.get_entrance_tile()))
	var need: Vector2 = (a - b).abs() + Vector2(10, 7) * TILE
	var zoom := clampf(minf(1280.0 / need.x, 720.0 / need.y), 0.5, 1.8)
	await _overview_at((a + b) * 0.5, zoom, slug, "Tür", details)
	_restore_vision(room)


## Every live room of the run in one picture.
func _chain_shot(slug: String, details: String) -> void:
	var bounds := Rect2()
	var first := true
	for room in _dungeon.room_container.get_children():
		var rect: Rect2 = room.get_node("Tiles").get_floor_rect()
		var world := Rect2(room.to_global(rect.position), rect.size).grow(TILE * 3)
		bounds = world if first else bounds.merge(world)
		first = false
	if first:
		return
	var zoom := minf(1280.0 / bounds.size.x, 720.0 / bounds.size.y)
	await _overview_at(bounds.get_center(), zoom, slug, "Raumkette", details + " (%d Räume)" % _dungeon.get_live_room_count())
	var active: Node = _dungeon.get_room(_dungeon.get_active_room_index())
	if active != null:
		_restore_vision(active)


func _shot(slug: String, category: String, details: String) -> void:
	await process_frame
	await process_frame
	_counter += 1
	var file := "%03d_%s.png" % [_counter, slug]
	var image := root.get_texture().get_image()
	image.save_png(_out.path_join(file))
	_manifest.append("%s\t%s\t%s" % [file, category, details])
	print("SHOT %s | %s | %s" % [file, category, details])
	_write_manifest()


func _write_manifest() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_manifest) + "\n")


# --- Camera, light, UI ---

func _use_gallery_camera(world: Node, center: Vector2, zoom: float) -> void:
	if _gallery_camera == null or not is_instance_valid(_gallery_camera) or _gallery_camera.get_parent() != world:
		_gallery_camera = Camera2D.new()
		_gallery_camera.name = "GalleryCamera"
		world.add_child(_gallery_camera)
	_gallery_camera.global_position = center
	_gallery_camera.zoom = Vector2(zoom, zoom)
	_gallery_camera.make_current()
	_gallery_camera.reset_smoothing()


func _reset_player_camera() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.make_current()
	camera.zoom = Vector2.ONE
	camera.reset_smoothing()


func _overlay() -> Node:
	return get_first_node_in_group(&"vision_overlay")


func _light_full() -> void:
	var overlay := _overlay()
	if overlay != null:
		overlay.set_vision(0.0, 2400.0, true)


## Darkness of a room as the DungeonManager sets it (without its banners).
func _restore_vision(room: Node) -> void:
	var overlay := _overlay()
	if overlay == null or room == null or not is_instance_valid(room):
		return
	var biome: Resource = room.spawner.get_biome(room.room_index)
	overlay.set_biome(biome, true)
	if room.room_type == SPECIAL:
		overlay.set_vision(0.2, 300.0, true)
	elif room.room_type == CAMPFIRE:
		overlay.set_vision(0.9, 300.0, true)
	else:
		overlay.set_vision(0.97, load("res://dungeon/variants/room_variants.gd").room_vision_radius(room), true)


func _hide_ui(hidden: bool) -> void:
	if hidden:
		_hidden_layers.clear()
		for node in root.find_children("*", "CanvasLayer", true, false):
			var script: Script = node.get_script()
			if script != null and UI_LAYERS.has(script.get_global_name()) and node.visible:
				node.visible = false
				_hidden_layers.append(node)
	else:
		for node in _hidden_layers:
			if is_instance_valid(node):
				node.visible = true
		_hidden_layers.clear()


# --- Fighting, clearing ---

## Lets the fight run: the player swings now and then (enemies come to him).
func _fight(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		Input.action_press(&"attack")
		await _seconds(0.12)
		Input.action_release(&"attack")
		await _seconds(0.33)
		elapsed += 0.45


## Kills everything, waits for the reward dialog; capture_slug: picture of the first dialog.
func _clear(room: Node, capture_slug: String) -> void:
	await _frames(5)
	_skip_boss_intros()
	var variant: Node = room.get_node_or_null("CombatVariant")
	if variant != null and variant.has_method(&"step"):
		variant.step(41.0)
	for sweep in 12:
		var alive := 0
		for enemy in _enemies(room):
			enemy.health.take_damage(INF)
			alive += 1
		await _frames(25)
		if alive == 0:
			break
	await _seconds(1.9)
	if not capture_slug.is_empty():
		for attempt in 20:
			if _find_modal(root) != null:
				break
			await _seconds(0.1)
		if _find_modal(root) != null:
			await _seconds(0.4)
			await _shot(capture_slug, "UI", "Upgrade-Wahl nach dem Kampf in Raum %d (echter Run)" % room.room_index)
	await _close_modals()


func _enemies(room: Node) -> Array:
	var result := []
	if room == null or not is_instance_valid(room):
		return result
	for child in room.enemy_container.get_children():
		if _is_enemy(child) and not child.is_dead():
			result.append(child)
	return result


func _is_enemy(node: Object) -> bool:
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == &"Enemy":
			return true
		script = script.get_base_script()
	return false


func _skip_boss_intros() -> void:
	for node in root.find_children("*", "Node", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"BossIntro":
			node.skip()


func _open_exit(room: Node) -> void:
	var exit: Node = room.get("_exit_door")
	if exit != null and not exit.is_open:
		exit.open()


func _find_interactable(room: Node) -> Node:
	for node in room.find_children("*", "Area2D", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"Interactable" and node.enabled:
			if String(node.prompt).begins_with("Dungeon verlassen"):
				continue
			return node
	return null


# --- Dialogs ---

func _modals() -> Array:
	var result := []
	for node in root.find_children("*", "Control", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"Modal" and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _find_modal(_from: Node) -> Node:
	var modals := _modals()
	return modals[0] if not modals.is_empty() else null


## Answers every open dialog: cancel where allowed, else the first card or button.
func _close_modals() -> void:
	for attempt in 12:
		var modal := _find_modal(root)
		if modal == null:
			return
		if modal.cancel_allowed:
			modal.finish(modal.cancel_result)
		else:
			var done := false
			for card in modal.find_children("*", "Control", true, false):
				if card.get_script() != null and card.get_script().get_global_name() == &"UiCard":
					card.activate()
					done = true
					break
			if not done:
				for button in modal.find_children("*", "Button", true, false):
					if not button.disabled:
						button.pressed.emit()
						done = true
						break
			if not done:
				modal.finish(modal.cancel_result)
		await _frames(8)


# --- Descriptions ---

func _describe(room: Node) -> String:
	if room == null or not is_instance_valid(room):
		return "-"
	var tiles: Node = room.get_node("Tiles")
	var template: Object = load("res://dungeon/rooms/templates/room_template.gd").of(room)
	var parts: Array[String] = []
	parts.append("Raum %d" % room.room_index)
	parts.append(["Kampf", "Kampf+Upgrade", "Spezial", "Miniboss", "Boss", "Lagerfeuer"][room.room_type])
	parts.append("Vorlage %s" % (template.id if template != null else room.scene_file_path.get_file().get_basename()))
	parts.append("Biom %s" % _biome_name(room))
	parts.append("%dx%d" % [tiles.room_size.x, tiles.room_size.y])
	var exits: Array[String] = []
	for door in tiles.get_exit_doors():
		exits.append(SIDE_NAMES[door.x])
	parts.append("Eingang %s, Ausgang %s" % [SIDE_NAMES[tiles.entrance_side], "/".join(exits)])
	var scatter: Node = room.get_node_or_null("Ingredients")
	if scatter != null and scatter.get("plan") != null:
		var ingredient_set: GDScript = load("res://dungeon/rooms/ingredients/ingredient_set.gd")
		var names: Array[String] = []
		for kind in scatter.plan.ingredients:
			names.append(str(ingredient_set.get_kind_name(kind)))
		parts.append("Zutaten [%s]" % ", ".join(names))
	var genre := str(_genre_script.of_room(room))
	if not genre.is_empty():
		parts.append("Genre %s" % genre)
	var variant := str(room.get_variant_id()) if room.has_method(&"get_variant_id") else ""
	if not variant.is_empty():
		parts.append("Variante %s" % variant)
	if room.has_method(&"has_wager_altar") and room.has_wager_altar():
		parts.append("Wagnis-Altar")
	if room.is_arena:
		parts.append("Hinterhalt" if room.is_ambush else "Arena")
	if tiles.has_method(&"has_pits") and tiles.has_pits():
		parts.append("Abgründe")
	if room.get_node_or_null("SecretNiche") != null:
		parts.append("Geheimnische")
	if room.has_method(&"is_branch_room") and room.is_branch_room():
		parts.append("Abzweigung")
	if room.room_type == SPECIAL:
		parts.append("Spezial %s" % _special_name(room))
	var enemies := _enemies(room)
	if not enemies.is_empty():
		parts.append("%d Gegner" % enemies.size())
	return " · ".join(parts)


func _biome_name(room: Node) -> String:
	var biome: Resource = room.spawner.get_biome(room.room_index)
	return str(biome.display_name) if biome != null else "?"


func _biome_of(index: int) -> int:
	return int(_seq.get_biome(index))


func _special_name(room: Node) -> String:
	if room == null or not is_instance_valid(room) or room.room_type != SPECIAL:
		return "-"
	return ["Shop", "Waffenwahl", "Brunnen", "Upgrade-Altar", "Prüfung"][clampi(room.special_type, 0, 4)]


func _option_name(room: Node, index: int) -> String:
	if index >= room.branch_options.size():
		return "?"
	var option: Object = room.branch_options[index]
	var kinds: Array = load("res://dungeon/rooms/branches/branch_option.gd").Kind.keys()
	return "%s, Symbol %s" % [str(kinds[option.kind]) if option.kind < kinds.size() else str(option.kind), str(option.get_symbol())]


func _door_world(room: Node, door: Vector2i) -> Vector2:
	var tiles: Node = room.get_node("Tiles")
	return room.to_global(_tiles_script.tile_center(_tiles_script.door_tile_of(door.x, door.y, tiles.room_size)))


func _slug(text: String) -> String:
	var result := text.to_lower()
	for pair in [["ä", "ae"], ["ö", "oe"], ["ü", "ue"], ["ß", "ss"], [" ", "-"]]:
		result = result.replace(pair[0], pair[1])
	return result


# --- Time ---

func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout


func _frames(count: int) -> void:
	for i in count:
		await process_frame
