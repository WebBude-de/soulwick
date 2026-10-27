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
	_place_furniture()
	_place_altar()
	_place_mirror()
	_place_exit()
	_add_lights()
	_ensure_spawn()
	ui = CanvasLayer.new()
	ui.name = "HomeUI"
	ui.layer = UI_LAYER
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
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
	])


func is_dialog_open() -> bool:
	return _busy


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

func _place_furniture() -> void:
	for item in HomeLayout.FURNITURE:
		var prop_name := String(item["name"])
		if bool(item.get("optional", false)) and not HomeArt.has_prop(prop_name):
			continue
		var layer := StringName(item.get("layer", HomeLayout.ROOM))
		var prop := _make_prop(prop_name, item["at"], item.get("solid", Vector2.ZERO))
		if layer == HomeLayout.ROOM:
			add_child(prop)
			SortLift.lift(prop)
		else:
			_floor_layer.add_child(prop)


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


func _add_lights() -> void:
	lights[&"fire"] = _light("FireLight", HomeLayout.FIRE_AT, HomeLayout.FIRE_COLOR,
		HomeLayout.FIRE_RADIUS_TILES, 1.0, HomeLayout.FIRE_FLICKER, Vector2(392, 74))
	var moon_colour := HomeLayout.SUN_COLOR.lerp(HomeLayout.MOON_COLOR, night)
	lights[&"moon"] = _light("MoonLight", HomeLayout.MOON_FLOOR_AT, moon_colour,
		HomeLayout.MOON_RADIUS_TILES, HomeLayout.MOON_INTENSITY, 0.0, HomeLayout.MOON_FLOOR_AT)
	lights[&"lamp"] = _light("NightLamp", HomeLayout.NIGHT_LAMP_AT, HomeLayout.NIGHT_LAMP_COLOR,
		HomeLayout.NIGHT_LAMP_RADIUS_TILES, 0.8, 0.02, Vector2(98, 126))


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
