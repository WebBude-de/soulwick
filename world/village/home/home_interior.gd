class_name HomeInterior
extends Node2D
## The inside of the player's home (KE8, KONZEPT §6, D-205): its own world, loaded by the
## WorldController through HomeTravel. Furnished "basic cozy" from the first visit (Antwort 20 §1:
## bed with nightstand and lamp, fireplace with armchair, round rug, shelf, chest, plant, broom,
## window sill flower, wall picture, Flint's basket), lit by the light system (fireplace as main
## light, moon or sun through the window, nightstand lamp, the altar's three candles, Flint's own
## circle), the mirror (profile editor, D-152), the candle altar with the talent tree
## (TalentTreeDialog; burns brighter while points are free) and the door out (back to the same spot
## in the village). On the first visit Flint explains altar and mirror (FlintExplanation
## "flint_home_altar", once per account).
## Only alone (HomeTravel.can_enter); talents stay account state (AccountTalents).
## FS6 (D-220, newcomer run P3-9): the village's goal line stays at the top left in here too
## (VillageGoal), as long as there is a goal.
## WK7 (D-202, D-205): the furniture is decoration (DecorLayer "Furniture" on the home's grid,
## DecorGrid.for_home): the starter set of the save, moved, turned, put away and bought in the
## decorating mode (DecorEditor) that the catalog stand by the door opens (DecorStation, only alone).
## Lights come from the pieces (fireplace = "fire", the first other light = "lamp"); wallpaper and
## floor follow the chosen styles (HomeRoom). Fixed: altar, mirror, broom, stand and door.

const EXPLANATION_ID: StringName = &"flint_home_altar"
const PAUSE_MIRROR: StringName = &"home_mirror"
## Width of the profile editor in the mirror dialog (mockup px, like VillageUI).
const PROFILE_EDITOR_WIDTH := 262.0
## Above the darkness and the HUD, like the village dialogs.
const UI_LAYER := 20

var altar: HomeAltar = null
var mirror: VillageMirror = null
var exit_door: Interactable = null
var room: HomeRoom = null
var moon_beam: HomeMoonBeam = null
var ui: CanvasLayer = null
## Lights by role ("fire", "moon", "lamp") for tests and tools.
var lights: Dictionary[StringName, LightSource] = {}
## 0 = day, 1 = night (local clock, VillageDaylight).
var night := 1.0
var _busy := false
var _floor_layer: Node2D = null
var _goal: Control = null
## WK7: the furniture, the catalog stand and the open decorating mode (null while closed).
var furniture: DecorLayer = null
var decor_station: DecorStation = null
var _decor_editor: DecorEditor = null


func _ready() -> void:
	y_sort_enabled = true
	night = VillageDaylight.night_amount(VillageDaylight.current_hour())
	room = HomeRoom.new()
	room.name = "Room"
	add_child(room)
	room.set_night(night)
	_floor_layer = Node2D.new()
	_floor_layer.name = "FloorDecor"
	_floor_layer.z_index = HomeRoom.Z + 1
	add_child(_floor_layer)
	moon_beam = HomeMoonBeam.new()
	moon_beam.name = "MoonBeam"
	moon_beam.scale = Vector2.ONE * HomeLayout.SCALE
	add_child(moon_beam)
	moon_beam.set_night(night)
	_place_fixed_props()
	_place_furniture()
	_place_altar()
	_place_mirror()
	_place_decor_station()
	_place_exit()
	_add_lights()
	_ensure_spawn()
	ui = CanvasLayer.new()
	ui.name = "HomeUI"
	ui.layer = UI_LAYER
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	refresh_goal()
	altar.refresh_from_account()


## WorldController hook (every player of this world): the home is peaceful like the village.
func on_player_spawned(player: Player) -> void:
	if player == null:
		return
	player.set_armed(false)
	player.dash_cooldown = Village.DASH_COOLDOWN
	if player.is_local:
		apply_lighting()
		explain_first_visit.call_deferred(player)


## World-space rectangle the camera must not leave (the room; a larger view is centred on it).
func get_camera_limits() -> Rect2i:
	var rect := HomeLayout.room_rect()
	return Rect2i(rect.position.round(), rect.size.round())


## Ambient light of the room on the vision overlay (Antwort 20 §1): 40 % with a soft blue at night,
## brighter by day; the player's circle (Flint) small, the room lives from its lights.
func apply_lighting() -> void:
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay if is_inside_tree() else null
	if overlay == null:
		return
	overlay.set_dark_color(HomeLayout.DARK_COLOR, true)
	overlay.set_vision(get_darkness(), HomeLayout.FLINT_RADIUS, true)


func get_darkness() -> float:
	return lerpf(HomeLayout.DARKNESS_DAY, HomeLayout.DARKNESS_NIGHT, night)


## Flint explains altar and mirror the first time (per account, AccountSeen). False when seen.
func explain_first_visit(player: Player) -> bool:
	if player == null or not is_instance_valid(player) or not is_inside_tree():
		return false
	return FlintGuide.explain(player, first_visit_explanation())


func first_visit_explanation() -> FlintExplanation:
	return FlintExplanation.tour(EXPLANATION_ID, [
		FlintGuideStep.say(&"FLINT_HOME_WELCOME", FlintGuideStep.Mood.HAPPY),
		FlintGuideStep.say(&"FLINT_HOME_ALTAR", FlintGuideStep.Mood.POINT).at_node(altar),
		FlintGuideStep.say(&"FLINT_HOME_PATHS", FlintGuideStep.Mood.PROUD).at_node(altar),
		FlintGuideStep.say(&"FLINT_HOME_RESPEC"),
		FlintGuideStep.say(&"FLINT_HOME_MIRROR", FlintGuideStep.Mood.POINT).at_node(mirror),
		FlintGuideStep.say(&"FLINT_HOME_DECOR", FlintGuideStep.Mood.POINT).at_node(decor_station),
	])


func is_dialog_open() -> bool:
	return _busy or is_decorating()


func is_decorating() -> bool:
	return _decor_editor != null and is_instance_valid(_decor_editor) and not _decor_editor.is_closing()


func get_decor_editor() -> DecorEditor:
	return _decor_editor if is_decorating() else null


## Opens the decorating mode for player (only alone, nothing while a dialog is open).
func open_decor_editor(player: Player) -> DecorEditor:
	if is_dialog_open() or furniture == null:
		return null
	_decor_editor = DecorStation.start(self, furniture, player)
	if _decor_editor != null:
		_decor_editor.closed.connect(func() -> void: _decor_editor = null)
	return _decor_editor


## The talent tree of the altar (editable alone; HomeTravel only lets solo players in).
func open_talent_tree() -> void:
	if _busy:
		return
	_busy = true
	Sfx.play_ui(self, &"torch_ignite")
	await TalentTreeDialog.open_for_account(ui, HomeTravel.can_enter(self))
	_busy = false
	if is_instance_valid(altar):
		altar.refresh_from_account()


## The mirror (D-152): name and look, the same editor as the mirror in the village.
func open_mirror() -> void:
	if _busy:
		return
	_busy = true
	Sfx.play_ui(self, &"ui_click")
	var modal := Modal.create(PAUSE_MIRROR)
	modal.name = "MirrorModal"
	var title := UiKit.title(Loc.t(&"MIRROR_TITLE"))
	modal.content.add_child(title)
	var subtitle := UiKit.text_label(Loc.t(&"MIRROR_SUBTITLE"), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal.content.add_child(subtitle)
	var profile := PlayerProfile.current()
	var editor := ProfileEditor.create(profile.player_name, profile.look, false, PROFILE_EDITOR_WIDTH)
	editor.show_level = true
	modal.content.add_child(editor)
	modal.input_handler = editor.handle_input
	# Esc goes through the editor (cancel), so a running save is never cut off.
	modal.cancel_allowed = false
	editor.saved.connect(modal.finish)
	editor.cancelled.connect(modal.finish)
	await modal.open(ui)
	_busy = false


## Back to the village, in front of the home's door (HomeTravel).
func leave() -> bool:
	if _busy:
		return false
	Sfx.play_ui(self, &"door_open")
	return HomeTravel.leave(self)


# --- Building the room ---

## The fixed props that are no catalog furniture (the broom).
func _place_fixed_props() -> void:
	for item in HomeLayout.FIXED_PROPS:
		var prop_name := String(item["name"])
		var layer := StringName(item.get("layer", HomeLayout.ROOM))
		var prop := _make_prop(prop_name, item["at"], item.get("solid", Vector2.ZERO))
		if layer == HomeLayout.ROOM:
			add_child(prop)
			SortLift.lift(prop)
		else:
			_floor_layer.add_child(prop)


## WK7: the furniture of the save on the home's grid; its lights are the room's lights.
func _place_furniture() -> void:
	furniture = DecorLayer.new()
	furniture.name = "Furniture"
	add_child(furniture)
	furniture.rebuilt.connect(_collect_lights)
	furniture.setup(DecorCatalog.HOME, DecorGrid.for_home(), HomeRoom.Z + 1, HomeRoom.Z + 1)


func _place_decor_station() -> void:
	decor_station = DecorStation.create(DecorCatalog.HOME)
	decor_station.position = HomeLayout.to_world(HomeLayout.DECOR_STATION_AT)
	add_child(decor_station)
	SortLift.lift(decor_station)
	decor_station.used.connect(open_decor_editor)


func _make_prop(prop_name: String, at: Vector2, solid: Vector2) -> Node2D:
	var prop := Node2D.new()
	prop.name = "Prop_" + prop_name
	prop.position = HomeLayout.to_world(at)
	var spec := HomeArt.prop_spec(prop_name)
	var frames := int(spec.get("frames", 1))
	var offset := SpriteStrip.pivot_offset(HomeArt.frame_size(spec), HomeArt.pivot(spec))
	if frames > 1:
		var animated := AnimatedSprite2D.new()
		animated.sprite_frames = HomeArt.prop_frames(prop_name)
		animated.play(&"default")
		animated.offset = offset
		_add_sprite(prop, animated)
	else:
		var sprite := Sprite2D.new()
		sprite.texture = HomeArt.prop_texture(prop_name)
		sprite.offset = offset
		_add_sprite(prop, sprite)
	if solid != Vector2.ZERO:
		_add_solid(prop, solid)
	return prop


static func _add_sprite(prop: Node2D, sprite: Node2D) -> void:
	sprite.name = "Sprite"
	sprite.scale = Vector2.ONE * HomeLayout.SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.add_child(sprite)


## Footprint (art px) at the foot that blocks walking.
static func _add_solid(prop: Node2D, footprint: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = "Solid"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = footprint * HomeLayout.SCALE
	shape.shape = box
	shape.position = Vector2(0, -box.size.y * 0.5)
	body.add_child(shape)
	prop.add_child(body)


func _place_altar() -> void:
	altar = HomeAltar.create()
	altar.position = HomeLayout.to_world(HomeLayout.ALTAR_AT)
	add_child(altar)
	_add_solid(altar, HomeLayout.ALTAR_SOLID)
	SortLift.lift(altar)
	altar.used.connect(func(_player: Player) -> void: open_talent_tree())


func _place_mirror() -> void:
	mirror = VillageMirror.create()
	mirror.position = HomeLayout.to_world(HomeLayout.MIRROR_AT)
	add_child(mirror)
	SortLift.lift(mirror)
	mirror.used.connect(func(_player: Player) -> void: open_mirror())


func _place_exit() -> void:
	exit_door = Interactable.new()
	exit_door.name = "ExitDoor"
	exit_door.prompt = Loc.t(&"HOME_EXIT_PROMPT")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HomeLayout.DOOR_USE_RADIUS * HomeLayout.SCALE
	shape.shape = circle
	exit_door.add_child(shape)
	exit_door.position = HomeLayout.to_world(HomeLayout.DOOR_USE_AT)
	add_child(exit_door)
	exit_door.interacted.connect(func(_player: Player) -> void: leave())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and exit_door != null:
		exit_door.prompt = Loc.t(&"HOME_EXIT_PROMPT")
		refresh_goal()


## The goal line of the village (VillageGoal) at the top left; none without a goal.
func refresh_goal() -> void:
	if ui == null:
		return
	if _goal != null and is_instance_valid(_goal):
		_goal.queue_free()
	_goal = null
	var goal := VillageGoal.current()
	if goal.is_empty():
		return
	_goal = VillageGoal.build_card(String(goal["text"]), goal["icon"])
	ui.add_child(_goal)


## The goal line while shown (null otherwise), for tests and tools.
func get_goal() -> Control:
	return _goal if _goal != null and is_instance_valid(_goal) and not _goal.is_queued_for_deletion() else null


func _add_lights() -> void:
	var moon_colour := HomeLayout.SUN_COLOR.lerp(HomeLayout.MOON_COLOR, night)
	lights[&"moon"] = _light("MoonLight", HomeLayout.MOON_FLOOR_AT, moon_colour,
		HomeLayout.MOON_RADIUS_TILES, HomeLayout.MOON_INTENSITY, 0.0, HomeLayout.MOON_FLOOR_AT)
	_collect_lights()


## Lights by role from the furniture (WK7): the first fireplace is "fire", the first other light
## "lamp" (none while no such piece stands); the moon stays.
func _collect_lights() -> void:
	lights.erase(&"fire")
	lights.erase(&"lamp")
	if furniture == null:
		return
	for piece in furniture.get_pieces():
		if piece.light == null:
			continue
		if piece.item.kind == "fireplace" and not lights.has(&"fire"):
			lights[&"fire"] = piece.light
		elif piece.item.kind != "fireplace" and not lights.has(&"lamp"):
			lights[&"lamp"] = piece.light


## A light at art px at, its lit circle centred on the floor point under it (ground, art px).
func _light(light_name: String, at: Vector2, colour: Color, radius_tiles: float, intensity: float,
		flicker: float, ground: Vector2) -> LightSource:
	var light := LightSource.new()
	light.name = light_name
	light.color = colour
	light.radius = HomeLayout.tiles_to_world(radius_tiles)
	light.intensity = intensity
	light.flicker = flicker
	light.position = HomeLayout.to_world(at)
	light.ground_offset = HomeLayout.to_world(ground - at)
	add_child(light)
	return light


func _ensure_spawn() -> void:
	var spawn := get_node_or_null(NodePath(WorldController.PLAYER_SPAWN_NODE)) as Marker2D
	if spawn == null:
		spawn = Marker2D.new()
		spawn.name = WorldController.PLAYER_SPAWN_NODE
		add_child(spawn)
	spawn.position = HomeLayout.to_world(HomeLayout.SPAWN_AT)


func get_prop(prop_name: String) -> Node2D:
	var prop := get_node_or_null(NodePath("Prop_" + prop_name)) as Node2D
	if prop == null and _floor_layer != null:
		prop = _floor_layer.get_node_or_null(NodePath("Prop_" + prop_name)) as Node2D
	return prop
