class_name Village
extends Node2D
## Village world: start and return point of every run (PRD 3). Besides the dungeon entrance it
## has four enterable buildings (D-078): Schmiede, Handelsposten, Chronik and Gilde, plus the
## player's Zuhause with the wardrobe (MM1, "Umkleiden"). Pressing E at a door opens that
## building's dialog (VillageUI). A building that has not explained itself yet
## (D-087) shows a bobbing info marker above its door sign until the explanation was seen.
## Locked buildings (MetaUnlocks, D-087: Chronik after the first run, Handelsposten with the first
## crystal) stay visible with a lock and "Öffnet nach …" above the door; E shows that as a notice.
## On load the village records reached unlock events and announces new ones once ("Neu freigeschaltet").
## B3: the layout comes from tools/generate_village.py (neighbour houses, villagers, chimney smoke,
## props from docs/SPRITES_V4.md); the small decoration is scattered here by VillageDecor.

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
## Lock marker above a locked door (world px): offset above the sign, maximum text width.
const LOCK_OFFSET := Vector2(0, -22)
const LOCK_TEXT_WIDTH := 260.0
## A locked building and its caption are drawn slightly darker (not the sign or the lock).
const LOCKED_TINT := Color(0.72, 0.7, 0.8)

@onready var _entrance: Interactable = $Buildings/DungeonEntrance/Interactable
@onready var _ground: VillageTiles = $Ground
@onready var _buildings: Node2D = $Buildings
@onready var _decor: VillageDecor = $Decor
@onready var _ambience: VillageAmbience = $Ambience

var ui: VillageUI = null
## building id -> its info marker (only buildings that still need their explanation).
var _intro_markers: Dictionary[StringName, Node2D] = {}
## building id -> its lock marker (only locked buildings).
var _lock_markers: Dictionary[StringName, Node2D] = {}
## building id -> door prompt of the open building ("Chronik betreten").
var _open_prompts: Dictionary[StringName, String] = {}


func _ready() -> void:
	ui = VillageUI.new()
	ui.name = "VillageUI"
	add_child(ui)
	_entrance.interacted.connect(_on_entrance_used)
	_add_missing_signs()
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
	# Unlock events reached in the last run (or missed by an older build) open buildings now.
	var new_events := MetaUnlocks.sync_from_save()
	var announcements := MetaUnlocks.take_announcements()
	if not new_events.is_empty() or not announcements.is_empty():
		SaveManager.save_game()
	for building in _buildings.get_children():
		var door := building.get_node_or_null("Door") as Interactable
		if door != null and building.has_meta(&"building_id"):
			var building_id := StringName(building.get_meta(&"building_id"))
			_open_prompts[building_id] = door.prompt
			door.interacted.connect(_on_door_used.bind(building_id))
	refresh_locks()
	SaveManager.seen_changed.connect(_on_seen_changed)
	ui.show_unlocks(announcements)


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
			door.prompt = _open_prompts.get(building_id, door.prompt)
			_remove_marker(_lock_markers, building_id)
			if VillageBuildings.needs_intro(building_id) and not has_intro_marker(building_id):
				_add_intro_marker(building as Node2D, building_id)


## True while the building still shows its "not explained yet" marker (for tests and tools).
func has_intro_marker(building_id: StringName) -> bool:
	return _intro_markers.has(building_id) and is_instance_valid(_intro_markers[building_id])


## True while the building is locked and shows the lock with "Öffnet nach …" (for tests and tools).
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
			await ui.open_home()
		_:
			push_warning("Village: unknown building '%s'." % building_id)


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


## Lock icon above the door sign with "Öffnet nach …" between it and the caption (the building
## stays visible).
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
	# Same small dark panel as the interaction prompt, wrapped so it never runs into a neighbour's caption.
	var label := Label.new()
	label.name = "LockText"
	label.text = MetaUnlocks.get_building_lock_text(building_id)
	UiKit.apply_prompt_style(label)
	label.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_EYEBROW))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = LOCK_TEXT_WIDTH
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(label)
	# The wrapped height is only known after layout: keep the panel centred above the lock icon.
	label.resized.connect(func() -> void: label.position = Vector2(-label.size.x / 2.0, -label.size.y - 20))
	label.size = Vector2(LOCK_TEXT_WIDTH, 0)
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
