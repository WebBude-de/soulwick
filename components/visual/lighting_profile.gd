class_name LightingProfile
extends RefCounted
## How a room LOOKS lit (R6, Claude-Design answer: "Umgebung 45-55 % sichtbar statt schwarz,
## Lichtkreis 5 Kacheln, jede Quelle wirft Licht"). Pure optics: the gameplay decision "is this point
## in the light?" stays with LightQuery and the logical vision values (DungeonManager.set_vision),
## which this profile never changes.
##
## The rule: the room code keeps setting its logical darkness (0.97 dungeon, 0.9 campfire, 0.2
## special rooms, the village clock). The overlay draws min(logical, ambient) - the profile only caps
## how dark the unlit environment gets. Rooms that are dark on purpose (light run, torch room,
## lantern, stone guardians) get a deep ambient and keep the drawn circle at the gameplay size, so
## what you see as light is what counts as light there.
##
## All numbers are TESTWERTE (R6).

## Unlit environment of a normal combat room per biome: darkness 0.55 = 45 % visible (measured on the
## Claude-Design mockups: unlit floor about 40-55 % of the lit floor).
const BIOME_AMBIENT := {
	&"crypt": 0.56,
	&"slime_grotto": 0.53,
	&"shadow_realm": 0.6,
	&"ember_forge": 0.54,
}
const DEFAULT_AMBIENT := 0.56
## Darker variants of the normal room ("Dunkler Raum" event).
const EXTRA_DARK_AMBIENT_BONUS := 0.12
## Room kinds (RoomSequence.RoomKind): offset on the biome ambient. Arena: enemies come from all
## gates, so the whole hall reads a bit better.
const KIND_AMBIENT_OFFSET := {0: 0.0, 1: -0.03, 2: 0.0}
## Boss: the boss has to stay visible everywhere (mockup: "Umgebung 45 %", a bit brighter than a
## combat room).
const BOSS_AMBIENT := 0.5
const MINIBOSS_AMBIENT := 0.52
## Campfire: calm and warm, the fire is the main light (mockup "Umgebung 35 %" looked too bright in
## the game view).
const CAMPFIRE_AMBIENT := 0.48
## "Almost dark" on purpose ("Umgebung 80 % dunkel"): light run, torch room, lantern, stone guardians.
## Special rooms use it too: they are bright by their own logical darkness (0.2); only a room that
## goes dark on purpose (light run) reaches this cap.
const DEEP_AMBIENT := 0.84
## Combat variants that live from darkness (RoomVariants ids). R4 adds its dark modes here.
const DEEP_VARIANTS: Array[StringName] = [&"stone_guardian", &"torch_room", &"lantern"]

## The player's circle as drawn: the logical radius (300 px, gameplay) times this. 300 * 1.45 = 435 px
## with a soft edge of 150 * 1.45 * 1.1 = 239 px: full light to ~196 px, half light at ~315 px
## (about 5 tiles of 64 px).
const PLAYER_RADIUS_SCALE := 1.45
## Light sources (torches, crystals, braziers) are drawn this much larger outside deep rooms.
const SOURCE_RADIUS_SCALE := 1.2
## Soft edge of the player's circle: SOFTNESS_PX (LightQuery.PLAYER_SOFT_EDGE * 2, the edge the
## gameplay radius assumes) times the radius scale times this. Deep rooms keep exactly 150 px.
const SOFTNESS_PX := 150.0
const SOFTNESS_SCALE := 1.1

## While blinded the environment sinks back into near darkness (gameplay radius stays LightQuery's).
const BLIND_AMBIENT := 0.9

## Player option "Helligkeit" (hook for GameOptions, R6): -1 darker .. +1 brighter. Shifts the
## ambient by up to BRIGHTNESS_RANGE, never below MIN_AMBIENT or above MAX_AMBIENT.
const BRIGHTNESS_RANGE := 0.12
const MIN_AMBIENT := 0.25
const MAX_AMBIENT := 0.97

static var brightness := 0.0

## Ambient cap (max darkness of the unlit environment).
var ambient := DEFAULT_AMBIENT
## Drawn player radius = logical radius * player_radius_scale.
var player_radius_scale := PLAYER_RADIUS_SCALE
## Drawn source radius = LightSource radius * source_radius_scale.
var source_radius_scale := SOURCE_RADIUS_SCALE
## Extra widening of the soft edge (1 = the gameplay edge of 150 px times the radius scale).
var softness_scale := SOFTNESS_SCALE


static func create(ambient_value: float, player_scale := PLAYER_RADIUS_SCALE, source_scale := SOURCE_RADIUS_SCALE, soft_scale := SOFTNESS_SCALE) -> LightingProfile:
	var profile := LightingProfile.new()
	profile.ambient = ambient_value
	profile.player_radius_scale = player_scale
	profile.source_radius_scale = source_scale
	profile.softness_scale = soft_scale
	return profile


## Soft edge in world px of a player circle drawn with this profile.
func get_softness() -> float:
	return SOFTNESS_PX * player_radius_scale * softness_scale


## No lift at all: the drawn darkness is the logical one (village, menu, tools).
static func neutral() -> LightingProfile:
	return create(1.0, 1.0, 1.0, 1.0)


## Deep darkness on purpose: drawn circles match the gameplay circles.
static func deep() -> LightingProfile:
	return create(DEEP_AMBIENT, 1.0, 1.0, 1.0)


## Normal combat room of a biome (also the default before any room is known).
static func for_biome(biome_id: StringName) -> LightingProfile:
	return create(biome_ambient(biome_id))


static func biome_ambient(biome_id: StringName) -> float:
	return float(BIOME_AMBIENT.get(biome_id, DEFAULT_AMBIENT))


## Profile of a room from what it is (type, kind, variant, biome). room is a RoomController; read
## duck-typed so this helper stays free of dungeon classes.
static func for_room(room: Node) -> LightingProfile:
	if room == null or not is_instance_valid(room):
		return for_biome(&"")
	var biome_id: StringName = &""
	var spawner: Variant = room.get(&"spawner")
	if spawner != null and room.get(&"room_index") != null:
		var biome: Variant = spawner.call(&"get_biome", int(room.get(&"room_index")))
		if biome != null:
			biome_id = biome.get(&"id")
	var variant_id: StringName = room.call(&"get_variant_id") if room.has_method(&"get_variant_id") else &""
	var is_campfire: bool = room.call(&"is_campfire") if room.has_method(&"is_campfire") else false
	return for_situation(biome_id, int(room.get(&"room_type")), int(room.get(&"room_kind")),
			variant_id, bool(room.get(&"is_extra_dark")), is_campfire)


## Pure decision behind for_room (tests). room_type / room_kind are RoomSequence values.
static func for_situation(biome_id: StringName, room_type: int, room_kind := 0, variant_id: StringName = &"", extra_dark := false, campfire := false) -> LightingProfile:
	# RoomSequence.RoomType: COMBAT, COMBAT_UPGRADE, SPECIAL, MINIBOSS, BOSS, CAMPFIRE
	if campfire or room_type == 5:
		return create(CAMPFIRE_AMBIENT)
	if room_type == 2:
		return deep()
	if DEEP_VARIANTS.has(variant_id):
		return deep()
	if room_type == 4:
		return create(BOSS_AMBIENT)
	if room_type == 3:
		return create(MINIBOSS_AMBIENT)
	var value := biome_ambient(biome_id) + float(KIND_AMBIENT_OFFSET.get(room_kind, 0.0))
	if extra_dark:
		value += EXTRA_DARK_AMBIENT_BONUS
	return create(value)


## The darkness that is drawn: the logical darkness, capped by the ambient (shifted by the
## brightness option). Logical values below the cap (bright special rooms, the village) stay as they are.
static func visual_darkness(logical: float, ambient_cap: float, brightness_value := brightness) -> float:
	return minf(logical, apply_brightness(ambient_cap, brightness_value))


## Ambient cap shifted by the brightness option. A neutral cap (1.0) stays neutral.
static func apply_brightness(ambient_cap: float, brightness_value := brightness) -> float:
	if ambient_cap >= 1.0 or is_zero_approx(brightness_value):
		return ambient_cap
	return clampf(ambient_cap - clampf(brightness_value, -1.0, 1.0) * BRIGHTNESS_RANGE, MIN_AMBIENT, MAX_AMBIENT)


## Hook for GameOptions (R6 report): value -1 .. +1, 0 = as designed.
static func set_brightness(value: float) -> void:
	brightness = clampf(value, -1.0, 1.0)
