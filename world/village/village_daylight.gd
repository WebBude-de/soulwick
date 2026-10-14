class_name VillageDaylight
extends RefCounted
## Time of day in the village (local clock): bright by day, a warm dusk, a blue night with the
## lamps as light islands. Feeds the VisionOverlay like the dungeon darkness (D-067); pure optics.

## TESTWERT: hours (local time, fractional) of the light curve.
const DUSK_START := 17.5
const NIGHT_START := 20.0
const NIGHT_END := 5.0
const DAY_START := 7.0
## TESTWERT: darkness at night (0 = bright, 1 = black) and the player's light radius in the village.
const NIGHT_DARKNESS := 0.6
const VISION_RADIUS := 320.0
## Darkness colours: warm violet at dusk and dawn, deep blue at night.
const DUSK_COLOR := Color("#2a1430")
const NIGHT_COLOR := Color("#070b24")
## TESTWERT: light of the village lamps (R7: warm light islands of 3 tiles).
const LAMP_RADIUS := 192.0
const LAMP_INTENSITY := 0.85
const LAMP_FLICKER := 0.04


## Local time as fractional hours (e.g. 19.5 = 19:30).
static func current_hour() -> float:
	var time := Time.get_time_dict_from_system()
	return float(time["hour"]) + float(time["minute"]) / 60.0


## 0 by day, rising through dusk to NIGHT_DARKNESS, falling again at dawn.
static func darkness_for_hour(hour: float) -> float:
	return NIGHT_DARKNESS * night_amount(hour)


## 0 = full day, 1 = full night.
static func night_amount(hour: float) -> float:
	hour = fposmod(hour, 24.0)
	if hour >= NIGHT_START or hour < NIGHT_END:
		return 1.0
	if hour >= DUSK_START:
		return smoothstep(DUSK_START, NIGHT_START, hour)
	if hour < DAY_START:
		return 1.0 - smoothstep(NIGHT_END, DAY_START, hour)
	return 0.0


## Night amount (0..1) back from a darkness as drawn: the VisionOverlay carries the clock's value
## (VillageEvening follows it, so tools that set the overlay also set the evening look).
static func night_from_darkness(darkness: float) -> float:
	if NIGHT_DARKNESS <= 0.0:
		return 0.0
	return clampf(darkness / NIGHT_DARKNESS, 0.0, 1.0)


## Colour of the darkness: violet while the light changes, blue in full night.
static func dark_color_for_hour(hour: float) -> Color:
	var night := night_amount(hour)
	return DUSK_COLOR.lerp(NIGHT_COLOR, clampf((night - 0.5) * 2.0, 0.0, 1.0))


## Gives every lamp post (props named "Lamp…") a light source; they only show while it is dark.
static func add_lamp_lights(props: Node) -> void:
	for prop in props.get_children():
		if not String(prop.name).begins_with("Lamp") or prop.get_node_or_null(^"LampLight") != null:
			continue
		var light := LightSource.new()
		light.name = "LampLight"
		light.radius = LAMP_RADIUS
		light.intensity = LAMP_INTENSITY
		light.flicker = LAMP_FLICKER
		light.color = LightPalette.WARM
		# Lamp head near the top of the 96 px post (the prop origin is already SortLift-raised by 16 px).
		light.position = Vector2(0, -72)
		prop.add_child(light)
