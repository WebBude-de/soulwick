class_name LightSource
extends Node2D
## A point that cuts a light circle into the dungeon darkness (torches, projectiles, explosions,
## pickups, elites). VisionOverlay collects all nodes of the group every frame.
## Lights that matter for gameplay (torches, crystals, lanterns - not flashes, projectiles or enemy
## glows) set counts_as_light: LightQuery then treats their circle as "lit" (A9, KONZEPT_RAEUME §4.3).
## The colour of the light (R6: warm = safe, cold = goal, red = danger) is pure optics: set color, or
## leave it transparent and LightPalette derives it from the owner once.
## L1 (optics only): the drawn brightness flickers like fire for warm lights and breathes slowly for
## goal and magic lights (get_draw_intensity), and each light draws a glow halo (get_halo). The
## gameplay side (counts_as_light, is_lit, get_lit_center, get_lit_radius) never reads these.

const GROUP := &"light_sources"
## Lights that count for LightQuery ("is this point in the light?").
const GAMEPLAY_GROUP := &"gameplay_lights"
## Share of the drawn radius that counts as lit: the soft outer edge of the circle does not.
const DEFAULT_LIT_SHARE := 0.8
## L1 rework: a light inside a room that is still veiled (prepared, not entered, RoomVeil) is drawn
## this much dimmer, so it does not shine through the rock into the room the player stands in.
## Optics only (TESTWERT). The veil's sheet alpha at full darkness, and how often a light without a
## veil looks again (frames).
const VEIL_LIGHT_DIM := 0.9
const VEIL_FULL_ALPHA := 0.62
const VEIL_RECHECK_FRAMES := 30
const VEIL_NODE := &"RoomVeil"
const VEIL_SEARCH_DEPTH := 10

@export var radius := 140.0
@export_range(0.0, 1.0) var intensity := 1.0
## Random flicker of the radius (0 = steady), e.g. for torches.
@export var flicker := 0.0
## Counts for LightQuery (stone guardians freeze in it, A9). Effects stay out.
@export var counts_as_light := false:
	set(value):
		counts_as_light = value
		_update_gameplay_group()
## Share of radius that counts as lit for LightQuery.
@export_range(0.0, 1.0) var lit_share := DEFAULT_LIT_SHARE
## From the light to the floor point under it: a torch flame hangs above its stand, the lit circle
## on the floor is centred at the stand's foot.
@export var ground_offset := Vector2.ZERO
## Colour of the light as drawn (LightPalette.WARM, COLD, DANGER ...). Transparent = derived from the
## owner (LightPalette.resolve). Optics only.
@export var color := Color(0, 0, 0, 0):
	set(value):
		color = value
		_draw_color_resolved = false
## Strength of the glow halo around the light as drawn (L1); negative = from LightPalette.
@export var halo := -1.0
## Drawn brightness factor set from outside, optics only: an enemy hidden in the dark takes its glow
## with it (DarknessVisibility). Never read by the gameplay side.
var draw_factor := 1.0

# Visual randomness only (D-088): never the dungeon RNG.
var _seed := randf() * 100.0
var _draw_color := LightPalette.NEUTRAL
var _draw_color_resolved := false
var _halo := 0.0
## Room veil above this light (RoomVeil of a prepared room, found by name; null = none) and the
## frame of the last search (a veil may be attached after the light).
var _veil: Node = null
var _veil_checked := -VEIL_RECHECK_FRAMES
## Strip of the owning torch when the colour was resolved: a biome torch that swaps its strip
## (green/purple flame) gets its light colour again.
var _resolved_strip: Variant = null


## Short light flash that fades out and frees itself (explosions, hits). flash_color tints what it
## touches (L1: a fire explosion flashes orange); peak scales the start intensity.
static func flash(parent: Node, global_pos: Vector2, flash_radius: float, duration := 0.35,
		flash_color := LightPalette.NEUTRAL, peak := 1.0) -> LightSource:
	if parent == null or not is_instance_valid(parent):
		return null
	var light := LightSource.new()
	light.name = "Flash"
	light.radius = flash_radius
	light.color = Color(flash_color, 1.0)
	light.intensity = clampf(peak, 0.0, 1.0) * GameOptions.get_flash_strength()
	parent.add_child(light)
	light.global_position = global_pos
	var tween := light.create_tween()
	tween.tween_property(light, "intensity", 0.0, duration)
	tween.tween_callback(light.queue_free)
	return light


func _enter_tree() -> void:
	add_to_group(GROUP)
	_update_gameplay_group()


func get_current_radius() -> float:
	if flicker <= 0.0:
		return radius
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	return radius * (1.0 + flicker * (0.6 * sin(t * 9.0) + 0.4 * sin(t * 23.0)))


## Colour the VisionOverlay draws this light in (cached; the owner does not change).
func get_draw_color() -> Color:
	if _draw_color_resolved and color.a <= 0.0 and _owner_strip() != _resolved_strip:
		_draw_color_resolved = false
	if not _draw_color_resolved:
		_resolved_strip = _owner_strip()
		_draw_color = LightPalette.resolve(self)
		_halo = LightPalette.halo_for(self, _draw_color)
		_draw_color_resolved = true
	return _draw_color


## Brightness as drawn (L1): fire lights flicker, goal and magic lights breathe. Optics only.
func get_draw_intensity() -> float:
	var color_value := get_draw_color()
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	if flicker > 0.0 and LightPalette.is_fire(color_value):
		var wobble := 0.55 * sin(t * 11.0) + 0.3 * sin(t * 27.0 + 1.3) + 0.15 * sin(t * 4.1)
		return clampf(intensity * (1.0 + flicker * LightPalette.FIRE_INTENSITY_FLICKER * wobble), 0.0, 1.0)
	if LightPalette.breathes(color_value):
		var breath := sin(t * TAU / LightPalette.BREATH_PERIOD)
		return clampf(intensity * (1.0 + LightPalette.BREATH_AMPLITUDE * breath), 0.0, 1.0)
	return intensity


func _owner_strip() -> Variant:
	var parent := get_parent()
	return parent.get(&"strip") if parent != null else null


## Brightness factor as drawn under a room veil (L1 rework): 1 without a veil or once it lifted,
## down to 1 - VEIL_LIGHT_DIM under a full veil, following the veil while it fades.
func get_veil_factor() -> float:
	if _veil == null or not is_instance_valid(_veil):
		var frame := Engine.get_process_frames()
		if frame - _veil_checked < VEIL_RECHECK_FRAMES:
			return 1.0
		_veil_checked = frame
		_veil = _find_veil()
		if _veil == null:
			return 1.0
	if not (_veil as CanvasItem).visible:
		return 1.0
	var sheet: Variant = _veil.call(&"get_sheet") if _veil.has_method(&"get_sheet") else null
	if not sheet is CanvasItem:
		return 1.0
	var share := clampf((sheet as CanvasItem).modulate.a / VEIL_FULL_ALPHA, 0.0, 1.0)
	return 1.0 - VEIL_LIGHT_DIM * share


## The RoomVeil of the room this light belongs to (child named RoomVeil of an ancestor).
func _find_veil() -> Node:
	var node := get_parent()
	for _i in VEIL_SEARCH_DEPTH:
		if node == null:
			return null
		var veil := node.get_node_or_null(NodePath(String(VEIL_NODE)))
		if veil is CanvasItem:
			return veil
		node = node.get_parent()
	return null


## Glow halo strength as drawn (L1).
func get_halo() -> float:
	get_draw_color()
	return _halo


func is_lit() -> bool:
	return visible and intensity > 0.01 and is_visible_in_tree()


## Floor point in the middle of the lit circle (LightQuery). No flicker: the decision is steady.
func get_lit_center() -> Vector2:
	return global_position + ground_offset


## Radius of the circle that counts as lit (LightQuery).
func get_lit_radius() -> float:
	return radius * lit_share


func _update_gameplay_group() -> void:
	if not is_inside_tree():
		return
	if counts_as_light:
		add_to_group(GAMEPLAY_GROUP)
	elif is_in_group(GAMEPLAY_GROUP):
		remove_from_group(GAMEPLAY_GROUP)
