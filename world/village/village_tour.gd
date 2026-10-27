class_name VillageTour
extends Node2D
## WK9 (KONZEPT §5, §7.2): Flint explains the village. Replaces the chronicler's opening words
## (D-161) and the old explanation cards of the buildings (D-087; Projektmitglied 22.10.2026: "ganz
## durch Flint ersetzen").
## - The tour: on the first start of an account (AccountSeen "flint_village_tour") Flint greets the
##   player, flies the player's own camera over the village (dungeon entrance, forge, trading post,
##   home, chronicle, guild) and says one sentence per station; a locked building gets its "opens
##   after …" sentence. While he talks about a station, a warm ring and rising sparks mark it (this
##   node, drawn above the darkness like the soul-light trail). Report #2e95d42c (23.10.2026, "Der
##   Kreis ist hässlich. Alles in Pixeloptik"): the ring is a pixel ellipse in art px (VillageArt.SCALE,
##   no anti-aliasing) in Flint's flame palette (D-198), it pulses in whole pixels and the sparks are
##   pixel squares, every position snapped to the art pixel grid.
## - The first entry of a building: before its dialog opens, Flint says what it is for and one tip
##   (FlintExplanation "flint_village_<id>", once per account); the dialog's info button asks him
##   again (VillageUI).
## Co-op (D-085, D-088): only local players are explained; the tour flies only the explained
## player's camera and nothing pauses, so a guest in the host's village gets his own tour without
## disturbing the others (the host's and the other guests' machines show nothing). Optics only, no
## randomness, nothing is sent; the network hook for the protected player is FlintGuide's.
## Script runs (tests, tools) start neither unless force_in_scripts is set (like TutorialRun).

## Seen id of the tour (per account, FlintGuide marks it when Flint is done or skipped).
const TOUR_ID: StringName = &"flint_village_tour"
## Building explanations: "flint_village_" + building id.
const BUILDING_PREFIX := "flint_village_"
const ENTRANCE: StringName = &"entrance"
const ENTRANCE_NODE := ^"Buildings/DungeonEntrance"
const BUILDINGS_NODE := ^"Buildings"
## Stations in the order of KONZEPT §7.2.
const STATIONS: Array[StringName] = [ENTRANCE, &"forge", &"trader", &"home", &"chronicle", &"guild"]
## station -> [sentence while open, sentence while locked (or &"")].
const STATION_TEXTS := {
	ENTRANCE: [&"FLINT_VILLAGE_ENTRANCE", &""],
	&"forge": [&"FLINT_VILLAGE_FORGE", &""],
	&"trader": [&"FLINT_VILLAGE_TRADER", &"FLINT_VILLAGE_TRADER_LOCKED"],
	&"home": [&"FLINT_VILLAGE_HOME", &""],
	&"chronicle": [&"FLINT_VILLAGE_CHRONICLE", &"FLINT_VILLAGE_CHRONICLE_LOCKED"],
	&"guild": [&"FLINT_VILLAGE_GUILD", &""],
}
const WELCOME_KEY: StringName = &"FLINT_VILLAGE_WELCOME"
const DONE_KEY: StringName = &"FLINT_VILLAGE_DONE"
## building -> sentences of its first entry (role, then a tip). Zuhause explains itself inside
## (HomeInterior, "flint_home_altar").
const BUILDING_TEXTS := {
	&"forge": [&"FLINT_VILLAGE_FORGE_INTRO", &"FLINT_VILLAGE_FORGE_TIP"],
	&"trader": [&"FLINT_VILLAGE_TRADER_INTRO", &"FLINT_VILLAGE_TRADER_TIP"],
	&"chronicle": [&"FLINT_VILLAGE_CHRONICLE_INTRO", &"FLINT_VILLAGE_CHRONICLE_TIP"],
	&"guild": [&"FLINT_VILLAGE_GUILD_INTRO", &"FLINT_VILLAGE_GUILD_TIP"],
}
## TESTWERT: the camera looks at the middle of a building, not at its base line (world px).
const BUILDING_FOCUS_OFFSET := Vector2(0, -72)
const ENTRANCE_FOCUS_OFFSET := Vector2(0, -40)
## Above the darkness (VisionOverlay 2) like the trail, below the HUD (5).
const HIGHLIGHT_LAYER := 3
## TESTWERT: marker of the station Flint talks about (art px at VillageArt.SCALE, s): ring half axes,
## pulse in whole pixels (PULSE_STEPS sizes, one step every PULSE_STEP_TIME), fade in alpha steps,
## sparks rising from the ring.
const RING_RADIUS_X := 39
const RING_RADIUS_Y := 15
const PULSE_STEPS := 3
const PULSE_STEP_TIME := 0.18
const RING_FADE_TIME := 0.35
const ALPHA_STEPS := 4.0
const SPARKS := 9
const SPARK_RISE := 35.0
const SPARK_SPEED := 0.55
## Flint's flame palette (D-198): ember outline, orange ring, light front arc, spark core.
const RING_EMBER := Color("#e04e2a")
const RING_COLOR := Color("#ff8a3c")
const RING_LIGHT := Color("#ffd166")
const SPARK_COLOR := Color("#ff8a3c")
const SPARK_CORE := Color("#fff3c4")

## Tools and tests: let tour and building explanations run in script runs too.
static var force_in_scripts := false

## The guide whose steps this marker follows.
var guide: FlintGuide = null
var _layer: CanvasLayer = null
var _drawing: Node2D = null
var _focus: Node2D = null
var _alpha := 0.0
var _time := 0.0
## Ring textures, one per pulse step (built once).
static var _ring_textures: Array[Texture2D] = []


# --- Tour ---

## Flint's village tour for player (local only, once per account; Village.on_player_spawned waits
## while the lobby dialog opens by itself). Adds the station marker. True if it will show.
static func offer(player: Player, village: Node) -> bool:
	if not may_explain(player) or village == null or not village.is_inside_tree():
		return false
	if not FlintGuide.explain(player, build_tour(village)):
		return false
	var guide := FlintGuide.of(player)
	if guide != null:
		var marker := VillageTour.new()
		marker.guide = guide
		village.add_child(marker)
	return true


## The tour through village: greeting, one step per station found (camera on it), goodbye.
static func build_tour(village: Node) -> FlintExplanation:
	var steps: Array[FlintGuideStep] = [FlintGuideStep.say(WELCOME_KEY, FlintGuideStep.Mood.HAPPY)]
	for station in STATIONS:
		var node := station_node(village, station)
		if node == null:
			continue
		var offset := ENTRANCE_FOCUS_OFFSET if station == ENTRANCE else BUILDING_FOCUS_OFFSET
		steps.append(FlintGuideStep.say(station_key(station), FlintGuideStep.Mood.POINT).at_node(node, offset))
	steps.append(FlintGuideStep.say(DONE_KEY, FlintGuideStep.Mood.HAPPY))
	return FlintExplanation.tour(TOUR_ID, steps)


## Sentence of a station: the locked one while its building is closed (MetaUnlocks, D-087).
static func station_key(station: StringName) -> StringName:
	var texts: Array = STATION_TEXTS.get(station, [&"", &""])
	var locked_key: StringName = texts[1]
	if locked_key != &"" and not MetaUnlocks.is_building_open(station):
		return locked_key
	return texts[0]


## The node of a station in village: the ruin, or the building with that building_id.
static func station_node(village: Node, station: StringName) -> Node2D:
	if village == null or not is_instance_valid(village):
		return null
	if station == ENTRANCE:
		return village.get_node_or_null(ENTRANCE_NODE) as Node2D
	var buildings := village.get_node_or_null(BUILDINGS_NODE)
	if buildings == null:
		return null
	for building in buildings.get_children():
		if building.has_meta(&"building_id") and StringName(building.get_meta(&"building_id")) == station:
			return building as Node2D
	return null


## True if Flint may explain to player here: a local player, and no script run unless forced.
static func may_explain(player: Player) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_local:
		return false
	return force_in_scripts or not PlayerProfile.is_script_run()


# --- First entry of a building ---

## Seen id of a building's first-entry explanation ("flint_village_forge").
static func explanation_id(building_id: StringName) -> StringName:
	return StringName(BUILDING_PREFIX + String(building_id))


## The account's seen id that counts as "this building was explained": Zuhause explains itself
## inside (HomeInterior), the others with explanation_id.
static func account_seen_id(building_id: StringName) -> StringName:
	return HomeInterior.EXPLANATION_ID if building_id == &"home" else explanation_id(building_id)


## True if Flint has a first-entry explanation for the building.
static func has_building_explanation(building_id: StringName) -> bool:
	return BUILDING_TEXTS.has(building_id)


## Flint's first-entry explanation of a building (null for buildings without one).
static func building_explanation(building_id: StringName) -> FlintExplanation:
	if not BUILDING_TEXTS.has(building_id):
		return null
	var keys: Array = BUILDING_TEXTS[building_id]
	var steps: Array[FlintGuideStep] = [
		FlintGuideStep.say(keys[0], FlintGuideStep.Mood.HAPPY),
		FlintGuideStep.say(keys[1], FlintGuideStep.Mood.POINT),
	]
	return FlintExplanation.tour(explanation_id(building_id), steps)


## Flint explains the building to player (force: again, from the info button). True if he will.
static func explain_building(player: Player, building_id: StringName, force := false) -> bool:
	if not may_explain(player):
		return false
	return FlintGuide.explain(player, building_explanation(building_id), force)


## Waits until the explanation id is neither running nor queued at player's guide (finished,
## skipped, cancelled or the player left). Returns at once when it is not there.
static func wait_until_done(player: Player, id: StringName) -> void:
	var guide := FlintGuide.of(player)
	if guide == null or not guide.is_known(id):
		return
	var waiter := Waiter.new(guide, id)
	if waiter.fired:
		return
	await waiter.done


## Resolves once the guide no longer knows the id (or is gone).
class Waiter extends RefCounted:
	signal done
	var guide: FlintGuide = null
	var id: StringName = &""
	var fired := false
	var _finished_check := Callable()
	var _phase_check := Callable()

	func _init(watched: FlintGuide, watched_id: StringName) -> void:
		guide = watched
		id = watched_id
		_finished_check = _check.unbind(2)
		_phase_check = _check.unbind(1)
		guide.finished.connect(_finished_check)
		guide.phase_changed.connect(_phase_check)
		guide.tree_exiting.connect(_fire)

	func _check() -> void:
		if guide == null or not is_instance_valid(guide) or not guide.is_known(id):
			_fire()

	func _fire() -> void:
		if fired:
			return
		fired = true
		if guide != null and is_instance_valid(guide):
			for connection: Array in [[guide.finished, _finished_check], [guide.phase_changed, _phase_check], [guide.tree_exiting, Callable(self, &"_fire")]]:
				var source: Signal = connection[0]
				if source.is_connected(connection[1]):
					source.disconnect(connection[1])
		done.emit()


# --- Station marker (the node) ---

func _ready() -> void:
	name = "VillageTour"
	_layer = CanvasLayer.new()
	_layer.name = "HighlightLayer"
	_layer.layer = HIGHLIGHT_LAYER
	_layer.follow_viewport_enabled = true
	add_child(_layer)
	_drawing = Node2D.new()
	_drawing.name = "Highlight"
	# Pixel look: no smoothing of the ring texture.
	_drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drawing.draw.connect(_draw_highlight)
	_layer.add_child(_drawing)
	if guide != null:
		guide.finished.connect(_on_finished)
		guide.tree_exiting.connect(queue_free)


func _process(delta: float) -> void:
	if guide == null or not is_instance_valid(guide):
		queue_free()
		return
	_time += delta
	var wanted := get_focus()
	if wanted != null:
		_focus = wanted
	var target := 1.0 if wanted != null else 0.0
	_alpha = move_toward(_alpha, target, delta / RING_FADE_TIME)
	_drawing.queue_redraw()


## The station Flint talks about now (null between stations and outside the tour).
func get_focus() -> Node2D:
	if guide == null or not is_instance_valid(guide) or guide.current == null or guide.current.id != TOUR_ID:
		return null
	if guide.phase != FlintGuide.Phase.TALK:
		return null
	var step := guide.get_step()
	if step == null or step.focus_node == null or not is_instance_valid(step.focus_node):
		return null
	return step.focus_node


func _on_finished(explanation: FlintExplanation, _skipped: bool) -> void:
	if explanation != null and explanation.id == TOUR_ID:
		queue_free()


## A pixel ring at the station's base line and pixel sparks rising from it (art px grid).
func _draw_highlight() -> void:
	if _focus == null or not is_instance_valid(_focus) or _alpha <= 0.0:
		return
	var px := VillageArt.SCALE
	var base := snap_to_art(_focus.global_position)
	var alpha := stepped_alpha(_alpha)
	var ring := ring_texture(pulse_step(_time))
	var half := Vector2(ring.get_size() * 0.5).floor() * px
	_drawing.draw_texture_rect(ring, Rect2(base - half, ring.get_size() * px), false, Color(1, 1, 1, alpha))
	for i in SPARKS:
		var phase := fposmod(_time * SPARK_SPEED + float(i) / SPARKS, 1.0)
		var angle := TAU * float(i) / SPARKS
		var spot := Vector2(cos(angle) * RING_RADIUS_X, sin(angle) * RING_RADIUS_Y - phase * SPARK_RISE)
		var cell := base + spot.round() * px
		var fade := stepped_alpha(sin(phase * PI) * _alpha)
		if fade <= 0.0:
			continue
		# A plus of orange around a light core pixel.
		for offset: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_drawing.draw_rect(Rect2(cell + offset * px, Vector2(px, px)), Color(SPARK_COLOR, 0.6 * fade))
		_drawing.draw_rect(Rect2(cell, Vector2(px, px)), Color(SPARK_CORE, fade))


## World position on the art pixel grid (VillageArt.SCALE world px per art px).
static func snap_to_art(point: Vector2) -> Vector2:
	return (point / VillageArt.SCALE).round() * VillageArt.SCALE


## Alpha in ALPHA_STEPS steps (pixel art fades in steps, not smoothly).
static func stepped_alpha(alpha: float) -> float:
	return ceilf(clampf(alpha, 0.0, 1.0) * ALPHA_STEPS) / ALPHA_STEPS


## Pulse step at time: 0, 1, …, PULSE_STEPS - 1 and back (the ring grows and shrinks a pixel at a time).
static func pulse_step(time: float) -> int:
	var cycle := PULSE_STEPS * 2 - 2
	var index := int(floorf(time / PULSE_STEP_TIME)) % maxi(cycle, 1)
	return index if index < PULSE_STEPS else cycle - index


## The ring texture of a pulse step: half axes grow by one art px per step.
static func ring_texture(step: int) -> Texture2D:
	if _ring_textures.is_empty():
		for i in PULSE_STEPS:
			_ring_textures.append(ImageTexture.create_from_image(ring_image(RING_RADIUS_X + i, RING_RADIUS_Y + i)))
	return _ring_textures[clampi(step, 0, PULSE_STEPS - 1)]


## Pixel ellipse ring (art px, no anti-aliasing): an orange line one pixel wide with an ember
## outline outside and inside, the front (lower) arc lit; the back arc (behind the building's base
## line) is dotted, every other pixel, without outline. Size (2 rx + 5) × (2 ry + 5).
static func ring_image(rx: int, ry: int) -> Image:
	var size := Vector2i(rx * 2 + 5, ry * 2 + 5)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := Vector2i(rx + 2, ry + 2)
	var line := ellipse_cells(rx, ry)
	for cell in line:
		if is_back_arc(cell):
			continue
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var at := centre + cell + offset
			if image.get_pixelv(at).a == 0.0:
				image.set_pixelv(at, Color(RING_EMBER, 0.55))
	for cell in line:
		if is_back_arc(cell):
			if posmod(cell.x, 2) == 0:
				image.set_pixelv(centre + cell, RING_COLOR)
		else:
			image.set_pixelv(centre + cell, RING_LIGHT if float(cell.y) > ry * 0.5 else RING_COLOR)
	return image


## True for a ring cell on the back arc (above the centre line, behind the station).
static func is_back_arc(cell: Vector2i) -> bool:
	return cell.y < -1


## Cells of a closed one-pixel ellipse outline around (0, 0) with half axes rx, ry (midpoint
## algorithm, every quadrant mirrored, no gaps).
static func ellipse_cells(rx: int, ry: int) -> Array[Vector2i]:
	var cells := {}
	var rx2 := float(rx * rx)
	var ry2 := float(ry * ry)
	var x := 0
	var y := ry
	# Region 1: slope above -1, step in x.
	while ry2 * x <= rx2 * y:
		_mirror(cells, x, y)
		x += 1
		if ry2 * x * x + rx2 * (y - 0.5) * (y - 0.5) > rx2 * ry2:
			y -= 1
	# Region 2: step in y.
	x = rx
	y = 0
	while rx2 * y <= ry2 * x:
		_mirror(cells, x, y)
		y += 1
		if ry2 * (x - 0.5) * (x - 0.5) + rx2 * y * y > rx2 * ry2:
			x -= 1
	var result: Array[Vector2i] = []
	for cell: Vector2i in cells:
		result.append(cell)
	return result


static func _mirror(cells: Dictionary, x: int, y: int) -> void:
	for cell: Vector2i in [Vector2i(x, y), Vector2i(-x, y), Vector2i(x, -y), Vector2i(-x, -y)]:
		cells[cell] = true
