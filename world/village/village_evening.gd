class_name VillageEvening
extends Node
## Evening look of the village (R7, 06_dorf.md, D-107): the evening light is a soft vignette at the
## screen edges instead of an even veil, the lamps are warm light islands (VisionOverlay, radius 3
## tiles), windows glow and the lanterns of the rescued villagers burn. Pure optics.
## The VisionOverlay is the clock's output (WorldController and the scene gallery set its darkness
## from VillageDaylight), so the evening follows it: night = drawn darkness / NIGHT_DARKNESS. Without
## an overlay (tests) the local clock decides; night_override pins a value.
## Everything that only shows at night joins NIGHT_GROUP: LightSources get intensity × night,
## other CanvasItems (window glows) modulate.a = night.

const NIGHT_GROUP: StringName = &"village_night"
## Base intensity of a night light (meta on the LightSource).
const BASE_INTENSITY_META: StringName = &"night_intensity"
const SHADER: Shader = preload("res://world/village/evening_vignette.gdshader")
## Below the VisionOverlay (layer 2) and every UI layer, above the world.
const LAYER := 1
## TESTWERT: vignette darkness at the screen edge at full night, falloff (share of the half diagonal).
const EDGE_AMOUNT := 0.6
const VIGNETTE_INNER := 0.35
const VIGNETTE_OUTER := 1.05
## TESTWERT: warm evening glow in the middle of the screen, strongest halfway through the dusk.
const DUSK_WARMTH := 0.1
const WARM_COLOR := Color("#ff9a4a")
## TESTWERT: window light (world px radius, intensity) and the colour of lit panes.
const WINDOW_LIGHT_RADIUS := 96.0
const WINDOW_LIGHT_INTENSITY := 0.55
## Window panes closer than this (art px) belong to the same window.
const WINDOW_MERGE := 12.0
## Building sprites that never get lit windows (no glass or not a house).
const WINDOWLESS: Array[String] = ["tree", "lamp_post", "well", "market_stall"]

## Window glow per building texture path (see _glow_for).
static var _glow_cache: Dictionary = {}

## >= 0 pins the night amount (tests, tools); < 0 follows the overlay or the clock.
var night_override := -1.0

var _layer: CanvasLayer = null
var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _night := 0.0


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "EveningLayer"
	_layer.layer = LAYER
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.name = "Vignette"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	_layer.add_child(_rect)
	_apply(current_night(), _dark_color())


func _process(_delta: float) -> void:
	_apply(current_night(), _dark_color())


## 0 = day, 1 = full night, from the overlay's drawn darkness (or the clock without one).
func current_night() -> float:
	if night_override >= 0.0:
		return clampf(night_override, 0.0, 1.0)
	var overlay := _overlay()
	if overlay != null:
		return VillageDaylight.night_from_darkness(overlay.get_visual_darkness())
	return VillageDaylight.night_amount(VillageDaylight.current_hour())


## The amount applied in the last frame.
func get_night() -> float:
	return _night


## Darkness at the screen edge for a night amount (0 by day).
static func edge_for_night(night: float) -> float:
	return EDGE_AMOUNT * clampf(night, 0.0, 1.0)


## Warm glow for a night amount: none by day and in full night, strongest halfway through the dusk.
static func warmth_for_night(night: float) -> float:
	return DUSK_WARMTH * (1.0 - absf(clampf(night, 0.0, 1.0) * 2.0 - 1.0))


## Makes a LightSource (or CanvasItem) show only at night; base is the full-night intensity.
static func mark_night(item: Node, base_intensity := 1.0) -> void:
	item.add_to_group(NIGHT_GROUP)
	if item is LightSource:
		item.set_meta(BASE_INTENSITY_META, base_intensity)
		(item as LightSource).intensity = 0.0
	elif item is CanvasItem:
		(item as CanvasItem).modulate.a = 0.0


## Lit windows for every house sprite under buildings: a warm copy of the glass pixels (WindowGlow)
## and one small light per building (WindowLight). Call after SortLift (copies the sprite's place).
static func add_window_glows(buildings: Node) -> int:
	var count := 0
	for building in buildings.get_children():
		var sprite := building.get_node_or_null(^"Sprite") as Sprite2D
		if not building is StaticBody2D or sprite == null or sprite.texture == null or building.get_node_or_null(^"WindowGlow") != null:
			continue
		var path := sprite.texture.resource_path
		if not path.contains("/buildings/") or _is_windowless(path):
			continue
		var glow: Dictionary = _glow_for(sprite.texture)
		if glow["texture"] == null:
			continue
		var window := Sprite2D.new()
		window.name = "WindowGlow"
		window.texture = glow["texture"]
		window.scale = sprite.scale
		window.offset = sprite.offset
		window.flip_h = sprite.flip_h
		window.centered = sprite.centered
		window.position = sprite.position
		building.add_child(window)
		mark_night(window)
		var centres: Array[Vector2] = glow["windows"]
		var middle := Vector2.ZERO
		for centre in centres:
			middle += centre
		middle /= float(centres.size())
		var light := LightSource.new()
		light.name = "WindowLight"
		light.radius = WINDOW_LIGHT_RADIUS
		light.color = LightPalette.WARM
		light.position = sprite.position + _art_to_local(sprite, middle)
		building.add_child(light)
		mark_night(light, WINDOW_LIGHT_INTENSITY)
		count += 1
	return count


## Window glow of a building texture (cached): {"texture", "windows": Array[Vector2] art px}.
static func _glow_for(texture: Texture2D) -> Dictionary:
	var key := texture.resource_path
	if _glow_cache.has(key):
		return _glow_cache[key]
	var raw := VillagePlaceholders.window_glow(texture)
	var windows: Array[Vector2] = []
	for centre: Vector2 in raw["centres"]:
		var merged := false
		for i in windows.size():
			if windows[i].distance_to(centre) <= WINDOW_MERGE:
				merged = true
				break
		if not merged:
			windows.append(centre)
	var result := {"texture": raw["texture"], "windows": windows}
	_glow_cache[key] = result
	return result


static func _is_windowless(path: String) -> bool:
	var file := path.get_file()
	for prefix in WINDOWLESS:
		if file.begins_with(prefix):
			return true
	return false


## Art pixel of a (centered) sprite in the sprite's parent space, ignoring the sprite's position.
static func _art_to_local(sprite: Sprite2D, art: Vector2) -> Vector2:
	var size := sprite.texture.get_size()
	var local := art - size * 0.5 if sprite.centered else art
	local += sprite.offset
	if sprite.flip_h:
		local.x = -local.x
	return local * sprite.scale


func _apply(night: float, dark_color: Color) -> void:
	_night = night
	if _material != null:
		var edge := edge_for_night(night)
		var warm := warmth_for_night(night)
		_rect.visible = edge > 0.001 or warm > 0.001
		_material.set_shader_parameter(&"edge_amount", edge)
		_material.set_shader_parameter(&"warm_amount", warm)
		_material.set_shader_parameter(&"dark_color", dark_color)
		_material.set_shader_parameter(&"warm_color", WARM_COLOR)
		_material.set_shader_parameter(&"inner", VIGNETTE_INNER)
		_material.set_shader_parameter(&"outer", VIGNETTE_OUTER)
		_material.set_shader_parameter(&"screen_size", get_viewport().get_visible_rect().size)
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(NIGHT_GROUP):
		if node is LightSource:
			(node as LightSource).intensity = float(node.get_meta(BASE_INTENSITY_META, 1.0)) * night
		elif node is CanvasItem:
			(node as CanvasItem).modulate.a = night


func _dark_color() -> Color:
	var overlay := _overlay()
	if overlay != null:
		return overlay.get_dark_color()
	return VillageDaylight.dark_color_for_hour(VillageDaylight.current_hour())


func _overlay() -> VisionOverlay:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
