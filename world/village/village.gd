class_name Village
extends Node2D
## Village world: start and return point of every run (PRD 3). Besides the dungeon entrance it
## has four enterable buildings (D-078): Schmiede, Handelsposten, Chronik and Gilde, plus the
## player's Zuhause ("Eintreten", KE8: its door leads into the home interior with the talent altar,
## VillageBuildings.enter_home) and the mirror next to it (D-152, the profile editor: name and look
## of the player, VillageMirror, VillageUI.open_mirror). Pressing E at another door opens that
## building's dialog (VillageUI). A building that has not explained itself yet
## (D-087) shows a bobbing info marker above its door sign until the explanation was seen.
## Locked buildings (MetaUnlocks, D-087: Chronik after the first run, Handelsposten with the first
## crystal) stay visible with a lock and "Öffnet nach …" above the door; E shows that as a notice.
## On load the village records reached unlock events and announces new ones once ("Neu freigeschaltet").
## B3: the layout comes from tools/generate_village.py (neighbour houses, villagers, chimney smoke,
## props from docs/design/sprites/delivered/SPRITES_V4.md); the small decoration is scattered here by VillageDecor.
## R7 (06_dorf.md): village square instead of a cross, the dungeon ruin up on the ridge
## (VillageEntrance), rescued villagers and chickens from the escort walk around (RescueRecord,
## D-135), the evening is a soft vignette with lit windows (VillageEvening). Building names show only
## near a player and never together with a notice (07_ui.md); a locked building keeps its name
## readable: a small lock on the door sign, the "Öffnet nach …" text is in the door prompt and the
## notice. The chronicle has a board in front: empty before the first run, one chalk mark per run.
## P1-2 (VillageGuide): until the first run of a world a trail of soul lights leads from the spawn to
## the ruin, an arrow points at the entrance and the goal line says "Steig in den Dungeon hinab".
## Optics at this machine only: the state is this player's world, nothing is shared in a room.
## WK9 (VillageTour): on the first start of an account Flint shows every local player around the
## village (camera ride, one sentence per building; replaces the chronicler's opening words, D-161)
## and explains each building on its first entry (VillageUI.explain_building).
## P1-3 (VillageAffordable): a pulsing gold "!" over every building where something is affordable
## right now (Schmiede, Handelsposten), on a layer above the darkness; it goes after a visit until
## the building's currency changes. Local only, nothing is sent.
## FS6 (D-220): the goal line follows VillageGoal (before the first run "Steig in den Dungeon hinab",
## after it the next forge goal: "Noch einmal hinab · noch 33 Gold bis Schildplatte I", then "Ab zur
## Schmiede · …"); the way grows stronger when the player strays (VillageGuide, timer held while Flint
## talks or a dialog is open); the tour leaves out locked buildings and Flint names a building when it
## opens (VillageTour.offer_opened, the buildings of the "Neu freigeschaltet" notice).

signal dungeon_requested
## Emitted when the player uses a building door; id is the building's building_id metadata.
signal building_entered(building_id: StringName)

const INFO_ICON: Texture2D = preload("res://art/ui/icon_info.png")
## Marker height above the door sign (world px) and bob amplitude/period.
const MARKER_OFFSET := Vector2(0, -22)
const MARKER_BOB := 4.0
const MARKER_BOB_TIME := 0.6
## Door sign placement (art px, x2 like tools/generate_village.py): 24×16 board above the door.
const SIGN_SIZE := Vector2(24, 16)
const SIGN_TOP := -94.0
const SIGN_WOOD := Color("#8a5a34")
const SIGN_WOOD_DARK := Color("#5c3a24")
const SIGN_WOOD_LIGHT := Color("#a8703f")
const LOCK_ICON: Texture2D = preload("res://art/ui/icon_lock.png")
## Lock marker above a locked door (world px): offset above the sign.
const LOCK_OFFSET := Vector2(0, -22)
## A locked building and its caption are drawn slightly darker (not the sign or the lock).
const LOCKED_TINT := Color(0.72, 0.7, 0.8)
## TESTWERT: a building's name shows while a player is this close to its door (world px), fade speed.
const CAPTION_NEAR := 400.0
const CAPTION_FADE := 4.0
## TESTWERT: rescued villagers and chickens walking in the village at most (D-135, RescueRecord).
const MAX_RESCUED_VILLAGERS := 6
const MAX_RESCUED_CHICKENS := 4
## TESTWERT: lantern of a rescued villager at night (world px radius, intensity).
const RESCUED_LANTERN_RADIUS := 110.0
const RESCUED_LANTERN_INTENSITY := 0.8
## Chronicle board next to the chronicle's door (world px from the door, art bottom centre).
const BOARD_OFFSET := Vector2(-78, 0)
## TESTWERT: the mirror stands right of the home's door (world px from the home's origin).
const MIRROR_OFFSET := Vector2(112, 6)
## P1-2: way to the dungeon until the first run (preloaded: works before the class cache knows it).
const GuideScript := preload("res://world/village/village_guide.gd")
## WK9: Flint's village tour (preloaded like the guide).
const TourScript := preload("res://world/village/village_tour.gd")
const GOAL_DESCEND: StringName = VillageGoal.DESCEND
## P1-3: affordable marks and the forge goal (preloaded like the guide).
const AffordableScript := preload("res://world/village/village_affordable.gd")
const AffordMarkerScript := preload("res://world/village/village_afford_marker.gd")
## FS6: the forge goals of the goal line ("Ab zur Schmiede · …", "Noch einmal hinab · …").
const GOAL_FORGE: StringName = VillageGoal.FORGE
const GOAL_SAVE: StringName = VillageGoal.SAVE
## Above the darkness (VisionOverlay 2) like the trail, below the HUD (5) and the dialogs (20).
const AFFORD_LAYER := 3
## "!" above the door sign (world px, like the info marker); next to the info marker while that shows.
const AFFORD_OFFSET := Vector2(0, -24)
const AFFORD_BESIDE_INFO := Vector2(26, 0)
## TESTWERT (#80c94d8c): dash cooldown in the village (dungeon 1.5 s). Feels unlimited; the dash
## itself lasts 0.2 s, the 0.05 s on the ground between two dashes keeps dust and sound apart.
const DASH_COOLDOWN := 0.25

@onready var _entrance: Interactable = $Buildings/DungeonEntrance/Interactable
@onready var _ground: VillageTiles = $Ground
@onready var _buildings: Node2D = $Buildings
@onready var _decor: VillageDecor = $Decor
@onready var _ambience: VillageAmbience = $Ambience
@onready var _villagers: Node2D = $Villagers
@onready var _evening: VillageEvening = get_node_or_null(^"Evening") as VillageEvening

var ui: VillageUI = null
## building id -> its info marker (only buildings that still need their explanation).
var _intro_markers: Dictionary[StringName, Node2D] = {}
## building id -> its lock marker (only locked buildings).
var _lock_markers: Dictionary[StringName, Node2D] = {}
## Trail and arrow to the entrance (null after the first run).
var _guide: GuideScript = null
## P1-3: layer and "!" markers per building id (only where something is affordable).
var _afford_layer: CanvasLayer = null
var _afford_markers: Dictionary[StringName, Node2D] = {}
## Which goal the goal line shows: GOAL_DESCEND, GOAL_FORGE, GOAL_SAVE or &"" (none), and its text.
var _goal_kind: StringName = &""
var _goal_text := ""
## FS6: buildings that open with this visit (their "Neu freigeschaltet" was not shown yet); Flint
## names them (VillageTour.offer_opened).
var _opened_now: Array[StringName] = []


func _ready() -> void:
	ui = VillageUI.new()
	ui.name = "VillageUI"
	add_child(ui)
	_entrance.interacted.connect(_on_entrance_used)
	_add_missing_signs()
	_add_chronicle_board()
	_add_mirror()
	_populate_rescued()
	# Sort buildings, decoration and NPCs by their base line against the player's feet.
	SortLift.lift_props(_buildings)
	# Building NPCs stand with their real feet line on the ground (not every art ends on row 29).
	for prop in _buildings.get_children():
		var npc := prop.get_node_or_null(^"Sprite") as AnimatedSprite2D
		if npc != null and npc.sprite_frames != null and npc.sprite_frames.resource_path.contains("/npcs/"):
			npc.offset.y = VillageArt.feet_offset_y(npc.sprite_frames)
	# B3: scattered flowers, stones and bushes (fixed seed) and pollen/fireflies over the map.
	_decor.populate(self)
	_ambience.setup(Rect2(get_camera_limits()))
	# Lamps light up the village at dusk and night (VillageDaylight, darkness set by WorldController).
	VillageDaylight.add_lamp_lights(_buildings)
	# Windows glow in the evening (VillageEvening fades them in with the darkness).
	VillageEvening.add_window_glows(_buildings)
	# Unlock events reached in the last run (or missed by an older build) open buildings now.
	var new_events := MetaUnlocks.sync_from_save()
	_opened_now = TourScript.opening_buildings()
	var announcements := MetaUnlocks.take_announcements()
	if not new_events.is_empty() or not announcements.is_empty():
		SaveManager.save_game()
	for building in _buildings.get_children():
		var door := building.get_node_or_null("Door") as Interactable
		if door != null and building.has_meta(&"building_id"):
			var building_id := StringName(building.get_meta(&"building_id"))
			door.interacted.connect(_on_door_used.bind(building_id))
	_apply_captions()
	refresh_locks()
	SaveManager.seen_changed.connect(_on_seen_changed)
	ui.show_unlocks(announcements)
	# KE4: the v5 forge conversion, short on arrival (the forge shows and takes it on its first visit).
	var news := MetaProgression.peek_migration_notice()
	if announcements.is_empty() and not news.is_empty():
		ui.show_notice(Loc.t(&"FORGE_MIGRATION_TITLE"), news)
	_setup_guide()
	# P1-3: purchases, a payout or an unlock change what is affordable.
	SaveManager.permanent_gold_changed.connect(_on_wallet_changed.unbind(1))
	SaveManager.permanent_crystals_changed.connect(_on_wallet_changed.unbind(1))
	SaveManager.meta_changed.connect(_on_wallet_changed)
	refresh_affordable()
	_update_captions(INF)


func _process(delta: float) -> void:
	_update_captions(delta)


## Called by the WorldController for every player of this world (register_player), on every
## machine and for every copy, so all copies of a group game agree (D-088). The village is peaceful
## (#80c94d8c): no weapon in the hand and a dash that is almost always ready. The dungeon spawns new
## players (D-041): weapons and the forge's "Dash-Training" apply there as before.
func on_player_spawned(player: Player) -> void:
	if player == null:
		return
	player.set_armed(false)
	player.dash_cooldown = DASH_COOLDOWN
	_offer_tour(player)


## Lock or intro marker per building from the save: locked buildings get the lock (and no intro
## marker yet), open ones the info marker until explained. Call again after an unlock.
func refresh_locks() -> void:
	for building in _buildings.get_children():
		if not building.has_meta(&"building_id") or building.get_node_or_null("Door") == null:
			continue
		var building_id := StringName(building.get_meta(&"building_id"))
		var door := building.get_node("Door") as Interactable
		var locked := not MetaUnlocks.is_building_open(building_id)
		for part in ["Sprite", "Caption"]:
			var item := building.get_node_or_null(part) as CanvasItem
			if item != null:
				item.self_modulate = LOCKED_TINT if locked else Color.WHITE
		if locked:
			door.prompt = "%s · %s" % [VillageBuildings.get_display_name(building_id), MetaUnlocks.get_building_lock_text(building_id)]
			if not has_lock_marker(building_id):
				_add_lock_marker(building as Node2D, building_id)
			_remove_marker(_intro_markers, building_id)
		else:
			var prompt: String = VillageBuildings.get_prompt(building_id)
			if not prompt.is_empty():
				door.prompt = prompt
			_remove_marker(_lock_markers, building_id)
			if VillageBuildings.needs_intro(building_id) and not has_intro_marker(building_id):
				_add_intro_marker(building as Node2D, building_id)
	if is_node_ready():
		refresh_affordable()


## Building captions and the dungeon entrance in the current language (D-111): captions get the key
## (Labels translate by themselves), door prompts the text (the player's prompt line composes it).
func _apply_captions() -> void:
	_entrance.prompt = Loc.t(VillageBuildings.DUNGEON_PROMPT)
	var entrance_caption := _entrance.get_parent().get_node_or_null(^"Caption") as Label
	if entrance_caption != null:
		entrance_caption.text = VillageBuildings.DUNGEON_NAME
	for building in _buildings.get_children():
		var caption := building.get_node_or_null(^"Caption") as Label
		if caption != null and building.has_meta(&"building_id"):
			var building_id := StringName(building.get_meta(&"building_id"))
			if VillageBuildings.has_building(building_id):
				caption.text = VillageBuildings.get_name_key(building_id)


## Language switch (options in the pause menu): prompts and lock texts are composed, rebuild them.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _buildings != null and is_node_ready():
		_apply_captions()
		refresh_locks()
		refresh_goal()


## True while the building still shows its "not explained yet" marker (for tests and tools).
func has_intro_marker(building_id: StringName) -> bool:
	return _intro_markers.has(building_id) and is_instance_valid(_intro_markers[building_id])


## True while the building is locked and shows the lock (for tests and tools); "Öffnet nach …" is in
## the door prompt and the notice.
func has_lock_marker(building_id: StringName) -> bool:
	return _lock_markers.has(building_id) and is_instance_valid(_lock_markers[building_id])


## World-space rectangle the camera must not leave.
func get_camera_limits() -> Rect2i:
	var tile_size := 32 * _ground.scale.x
	return Rect2i(Vector2i.ZERO, Vector2i(Vector2(_ground.map_size) * tile_size))


## Opens the dialog of a building ("forge", "trader", "chronicle", "guild", "home").
## A locked building only shows its "Öffnet nach …" notice.
func enter_building(building_id: StringName) -> void:
	if ui.is_dialog_open():
		return
	if not MetaUnlocks.is_building_open(building_id):
		ui.show_locked(building_id)
		return
	building_entered.emit(building_id)
	Sfx.play_ui(self, &"door_open")
	match building_id:
		&"forge":
			await ui.open_forge()
		&"trader":
			await ui.open_trader()
		&"chronicle":
			await ui.open_chronicle()
		&"guild":
			await ui.open_guild()
		&"home":
			# KE8: inside alone (HomeTravel), the talent tree read-only in a group session.
			await VillageBuildings.enter_home(self)
		_:
			push_warning("Village: unknown building '%s'." % building_id)
	# P1-3: seen now; its "!" waits until the currency changes.
	if is_inside_tree():
		AffordableScript.mark_visited(building_id)
		refresh_affordable()


# --- P1-2: goal and way to the dungeon until the first run ---

## Trail and arrow while the world has no run yet (the greeting is Flint's tour, WK9:
## on_player_spawned; the goal line comes from refresh_goal). FS6: the guide measures how far this
## machine's players are from the entrance and holds its stray timer while Flint or a dialog holds them.
func _setup_guide() -> void:
	if not GuideScript.is_active():
		return
	var spawn := find_child("PlayerSpawn", true, false) as Node2D
	var entrance := _entrance.get_parent() as Node2D
	var start := spawn.global_position if spawn != null else entrance.global_position
	_guide = GuideScript.new()
	_guide.setup(start, entrance.global_position)
	_guide.hidden_check = ui.is_dialog_open
	_guide.distance_source = _local_entrance_distance
	_guide.paused_check = _guide_paused
	add_child(_guide)


## Distance of the nearest player of this machine to the entrance (INF without one).
func _local_entrance_distance() -> float:
	if _guide == null:
		return INF
	var best := INF
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_local:
			best = minf(best, player.global_position.distance_to(_guide.target))
	return best


## True while the stray timer waits: a dialog is open or Flint holds a player of this machine.
func _guide_paused() -> bool:
	if ui != null and ui.is_dialog_open():
		return true
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_local and player.is_protected():
			return true
	return false


## WK9: Flint's tour for a local player on the first start of the account (each machine its own, a
## guest in the host's village too). When the guild dialog opens right away (a room wish of the main
## menu, a reopened lobby) the tour waits until it is closed.
func _offer_tour(player: Player) -> void:
	if player == null or not player.is_local:
		return
	if _lobby_dialog_pending():
		# The lobby dialog opens deferred (VillageUI._resume_lobby).
		await get_tree().process_frame
		while is_inside_tree() and is_instance_valid(player) and ui.is_dialog_open():
			await get_tree().process_frame
	if is_inside_tree() and is_instance_valid(player) and player.is_inside_tree():
		# The first tour shows every building open by now; otherwise Flint names the ones that just
		# opened (FS6, D-220: the tour leaves locked buildings out).
		if not TourScript.offer(player, self):
			TourScript.offer_opened(player, self, _opened_now)


## True while the guild dialog is about to open by itself (VillageUI._resume_lobby).
func _lobby_dialog_pending() -> bool:
	if LobbyClient.has_pending_launch():
		return true
	var lobby := LobbyClient.find(self)
	return lobby != null and lobby.is_in_room() and lobby.resume_dialog


## Trail and arrow to the entrance (null after the first run), for tests and tools.
func get_guide() -> GuideScript:
	return _guide


# --- P1-3: what can I afford? ---

## "!" over every building where something is affordable (VillageAffordable.needs_marker) and the
## goal line (VillageGoal). Called on load, after a visit and whenever gold, crystals or forge levels
## change.
func refresh_affordable() -> void:
	for building_id in AffordableScript.BUILDINGS:
		var building := _building_node(building_id)
		if building != null and AffordableScript.needs_marker(building_id):
			_place_afford_marker(building, building_id)
		else:
			_remove_marker(_afford_markers, building_id)
	refresh_goal()


## True while the building shows its "!" (for tests and tools).
func has_afford_marker(building_id: StringName) -> bool:
	return _afford_markers.has(building_id) and is_instance_valid(_afford_markers[building_id]) \
		and not _afford_markers[building_id].is_queued_for_deletion()


## The "!" of a building (null if none), for tests and tools.
func get_afford_marker(building_id: StringName) -> Node2D:
	return _afford_markers[building_id] if has_afford_marker(building_id) else null


## Which goal the goal line shows (GOAL_DESCEND, GOAL_FORGE, GOAL_SAVE or &""), for tests and tools.
func get_goal_kind() -> StringName:
	return _goal_kind


func _building_node(building_id: StringName) -> Node2D:
	for building in _buildings.get_children():
		if building.has_meta(&"building_id") and StringName(building.get_meta(&"building_id")) == building_id:
			return building as Node2D
	return null


## World position of the "!": above the door sign, beside the info marker while that shows.
func _afford_position(building: Node2D, building_id: StringName) -> Vector2:
	var sign := building.get_node_or_null("Sign") as Node2D
	var local := (sign.position if sign != null else Vector2(0, SIGN_TOP)) + AFFORD_OFFSET
	if has_intro_marker(building_id):
		local += AFFORD_BESIDE_INFO
	return building.to_global(local)


func _place_afford_marker(building: Node2D, building_id: StringName) -> void:
	if _afford_layer == null:
		_afford_layer = CanvasLayer.new()
		_afford_layer.name = "AffordLayer"
		_afford_layer.layer = AFFORD_LAYER
		_afford_layer.follow_viewport_enabled = true
		add_child(_afford_layer)
	var marker := get_afford_marker(building_id)
	if marker == null:
		marker = AffordMarkerScript.new()
		marker.name = "AffordMarker_%s" % building_id
		_afford_layer.add_child(marker)
		_afford_markers[building_id] = marker
	marker.global_position = _afford_position(building, building_id)


## The goal line from VillageGoal (FS6, D-220): replaced only when goal or text changed.
func refresh_goal() -> void:
	if ui == null:
		return
	var goal := VillageGoal.current()
	var kind: StringName = goal.get("kind", &"")
	var text: String = goal.get("text", "")
	if kind == _goal_kind and text == _goal_text and (kind == &"") == (ui.get_goal() == null):
		return
	_goal_kind = kind
	_goal_text = text
	if kind == &"":
		ui.hide_goal()
	else:
		ui.show_goal(text, goal["icon"])


func _on_wallet_changed() -> void:
	if is_inside_tree():
		refresh_affordable()


func _on_entrance_used(_player: Player) -> void:
	dungeon_requested.emit()


func _on_door_used(_player: Player, building_id: StringName) -> void:
	enter_building(building_id)


## Buildings whose sign art is not in the scene (Zuhause: art/ui/sign_home.png still missing) get the
## file if it exists by now, else a plain wooden board as placeholder.
func _add_missing_signs() -> void:
	for building in _buildings.get_children():
		if not building.has_meta(&"building_id") or building.get_node_or_null("Sign") != null:
			continue
		var texture := VillageBuildings.get_sign_texture(StringName(building.get_meta(&"building_id")))
		var sign := Sprite2D.new()
		sign.name = "Sign"
		sign.texture = texture if texture != null else _placeholder_sign()
		sign.centered = false
		sign.offset = Vector2(-SIGN_SIZE.x / 2.0, 0)
		sign.scale = Vector2(2, 2)
		sign.position = Vector2(0, SIGN_TOP)
		building.add_child(sign)


## 24×16 wooden board with a darker frame and two plank lines.
static func _placeholder_sign() -> Texture2D:
	var image := Image.create(int(SIGN_SIZE.x), int(SIGN_SIZE.y), false, Image.FORMAT_RGBA8)
	image.fill(SIGN_WOOD)
	for x in int(SIGN_SIZE.x):
		image.set_pixel(x, 0, SIGN_WOOD_DARK)
		image.set_pixel(x, int(SIGN_SIZE.y) - 1, SIGN_WOOD_DARK)
		image.set_pixel(x, 5, SIGN_WOOD_LIGHT)
		image.set_pixel(x, 10, SIGN_WOOD_DARK)
	for y in int(SIGN_SIZE.y):
		image.set_pixel(0, y, SIGN_WOOD_DARK)
		image.set_pixel(int(SIGN_SIZE.x) - 1, y, SIGN_WOOD_DARK)
	return ImageTexture.create_from_image(image)


func _add_intro_marker(building: Node2D, building_id: StringName) -> void:
	var sign := building.get_node_or_null("Sign") as Node2D
	var marker := Sprite2D.new()
	marker.name = "IntroMarker"
	marker.texture = INFO_ICON
	marker.scale = Vector2(2, 2)
	marker.position = (sign.position if sign != null else Vector2(0, -94)) + MARKER_OFFSET
	building.add_child(marker)
	_intro_markers[building_id] = marker
	var tween := marker.create_tween().set_loops()
	tween.tween_property(marker, "position:y", marker.position.y - MARKER_BOB, MARKER_BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(marker, "position:y", marker.position.y, MARKER_BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Small lock above the door sign (R7: no text panel that would cover the building's name; the
## "Öffnet nach …" text is in the door prompt and in the notice on E). The building stays visible.
func _add_lock_marker(building: Node2D, building_id: StringName) -> void:
	var sign := building.get_node_or_null("Sign") as Node2D
	var marker := Node2D.new()
	marker.name = "LockMarker"
	marker.position = (sign.position if sign != null else Vector2(0, SIGN_TOP)) + LOCK_OFFSET
	var icon := Sprite2D.new()
	icon.name = "LockIcon"
	icon.texture = LOCK_ICON
	icon.scale = Vector2(2, 2)
	marker.add_child(icon)
	building.add_child(marker)
	_lock_markers[building_id] = marker


func _remove_marker(markers: Dictionary[StringName, Node2D], building_id: StringName) -> void:
	if markers.has(building_id):
		if is_instance_valid(markers[building_id]):
			markers[building_id].queue_free()
		markers.erase(building_id)


func _on_seen_changed(id: StringName) -> void:
	for building_id in _intro_markers.keys():
		if VillageBuildings.get_intro_key(building_id) == id:
			var marker := _intro_markers[building_id]
			if is_instance_valid(marker):
				marker.queue_free()
			_intro_markers.erase(building_id)
			# The "!" moves back over the sign.
			var building := _building_node(building_id)
			if building != null and has_afford_marker(building_id):
				_afford_markers[building_id].global_position = _afford_position(building, building_id)


# --- R7: names near the player, chronicle board, rescued villagers ---

## Building names (and "Dungeon") fade in while a player is near the door and never while a notice
## is on screen (07_ui.md: world captions and banners never share the screen). delta = INF snaps.
func _update_captions(delta: float) -> void:
	var positions := _player_positions()
	var notice_up := ui != null and ui.get_notice() != null
	for building in _buildings.get_children():
		var caption := building.get_node_or_null(^"Caption") as Label
		if caption == null:
			continue
		var anchor := (building as Node2D).global_position
		var near := false
		for point in positions:
			if point.distance_to(anchor) <= CAPTION_NEAR:
				near = true
				break
		var target := 1.0 if near and not notice_up else 0.0
		caption.self_modulate.a = target if is_inf(delta) else move_toward(caption.self_modulate.a, target, CAPTION_FADE * delta)


## True while the building's name is (becoming) visible, for tests and tools.
func is_caption_shown(node_name: StringName) -> bool:
	var caption := _buildings.get_node_or_null(NodePath(String(node_name) + "/Caption")) as Label
	return caption != null and caption.self_modulate.a > 0.5


## Every player in the village (coop: all of them).
func _player_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node2D
		if player != null and is_instance_valid(player):
			positions.append(player.global_position)
	return positions


## The chronicle's board: empty before the first run (instead of a sign over the name), then one
## chalk mark per run (StatsTracker.RUNS, at most VillagePlaceholders.BOARD_MAX_TALLY).
func _add_chronicle_board() -> void:
	var chronicle := _buildings.get_node_or_null(^"Chronicle") as Node2D
	if chronicle == null or chronicle.get_node_or_null(^"Board") != null:
		return
	var board := Sprite2D.new()
	board.name = "Board"
	board.texture = VillageArt.get_texture("chronicle_board")
	board.scale = Vector2.ONE * VillageArt.SCALE
	board.offset = Vector2(0, -board.texture.get_height() * 0.5)
	board.position = BOARD_OFFSET
	var runs := int(SaveManager.get_stat(StatsTracker.RUNS))
	if runs > 0:
		var tally := Sprite2D.new()
		tally.name = "Tally"
		tally.texture = VillagePlaceholders.tally_overlay(runs)
		tally.offset = board.offset
		board.add_child(tally)
	chronicle.add_child(board)


## The mirror next to Zuhause (D-152): opens the profile editor.
func _add_mirror() -> void:
	var home := _buildings.get_node_or_null(^"Home") as Node2D
	if home == null or _buildings.get_node_or_null(^"Mirror") != null:
		return
	var mirror := VillageMirror.create()
	mirror.position = home.position + MIRROR_OFFSET
	_buildings.add_child(mirror)
	mirror.used.connect(func(_player: Player) -> void: open_mirror())


## Opens the profile editor of the mirror (nothing while another dialog is open).
func open_mirror() -> void:
	if ui.is_dialog_open():
		return
	Sfx.play_ui(self, &"ui_click")
	await ui.open_mirror()


func get_mirror() -> VillageMirror:
	return _buildings.get_node_or_null(^"Mirror") as VillageMirror


## Number of chalk marks on the chronicle board (0 = empty), for tests.
func get_board_tally() -> int:
	var tally := _buildings.get_node_or_null(^"Chronicle/Board/Tally")
	return mini(int(SaveManager.get_stat(StatsTracker.RUNS)), VillagePlaceholders.BOARD_MAX_TALLY) if tally != null else 0


## Rescued villagers and chickens shown in the village (RescueRecord, capped).
static func rescued_shown(chicken: bool) -> int:
	return clampi(RescueRecord.get_rescued(chicken), 0, MAX_RESCUED_CHICKENS if chicken else MAX_RESCUED_VILLAGERS)


## Keeps one generator slot per rescued villager/chicken (rescue order) and frees the rest. Rescued
## villagers wear the cloak colours of the escort (LostVillager.CLOAK_TINTS) and carry their lantern,
## lit at night.
func _populate_rescued() -> void:
	var villagers := rescued_shown(false)
	var chickens := rescued_shown(true)
	for node in _villagers.get_children():
		var villager := node as Villager
		if villager == null:
			continue
		var is_villager := villager.has_meta(&"rescued_slot")
		var is_chicken := villager.has_meta(&"rescued_chicken_slot")
		if not is_villager and not is_chicken:
			continue
		var slot := int(villager.get_meta(&"rescued_slot" if is_villager else &"rescued_chicken_slot"))
		if slot >= (villagers if is_villager else chickens) or villager.is_queued_for_deletion():
			_villagers.remove_child(villager)
			if not villager.is_queued_for_deletion():
				villager.free()
			continue
		if is_villager:
			villager.set_cloak(LostVillager.CLOAK_TINTS[slot % LostVillager.CLOAK_TINTS.size()])
			var lantern := LightSource.new()
			lantern.name = "Lantern"
			lantern.radius = RESCUED_LANTERN_RADIUS
			lantern.color = LightPalette.WARM
			lantern.flicker = 0.05
			var offset := (LostVillager.LANTERN_ANCHOR - LostVillager.PIVOT) * VillageArt.SCALE
			lantern.position = Villager.FEET_OFFSET + offset
			lantern.ground_offset = Vector2(0, -offset.y)
			villager.add_child(lantern)
			VillageEvening.mark_night(lantern, RESCUED_LANTERN_INTENSITY)


## Rescued villagers (chicken = false) or chickens walking in the village right now.
func get_rescued_walkers(chicken := false) -> Array[Villager]:
	var result: Array[Villager] = []
	var key := &"rescued_chicken_slot" if chicken else &"rescued_slot"
	for node in _villagers.get_children():
		if node is Villager and node.has_meta(key) and not node.is_queued_for_deletion():
			result.append(node as Villager)
	return result


func get_evening() -> VillageEvening:
	return _evening
