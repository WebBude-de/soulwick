class_name VisionOverlay
extends CanvasLayer
## Drives vision.gdshader: dungeon darkness with a light circle around the player and all
## LightSource nodes (D-067), coloured light (R6), blindness, red damage edge and the low-HP vignette.
## Only draws: whether a point is lit for gameplay is LightQuery's decision; the overlay hands it the
## bound player's current LOGICAL circle radius (state at the player), never the drawn one.
## R6: the drawn look follows a LightingProfile (ambient cap, drawn radius scale). The logical values
## from set_vision stay the gameplay truth; the profile only lifts the unlit environment and widens
## the drawn circles, except in rooms that are dark on purpose (LightingProfile.deep()).
## Also owns the PostProcess pass (layer 3) and forwards the bound player to it, and the
## DarknessVisibility that fades enemies outside the drawn light of the local player (optics only).
## L1: glow halos around the sources, flickering/breathing source brightness, mist in the light and
## the biome grade (BiomeGrade: shadow/highlight tint, vignette) are drawn in the same single pass;
## LightingQuality low switches them off. With more lights on screen than the shader takes, the
## gameplay lights (counts_as_light) and the strongest ones near the view centre are kept.

const SHADER: Shader = preload("res://components/visual/vision.gdshader")
## Must match MAX_LIGHTS in vision.gdshader.
const MAX_LIGHTS := 32
const BLIND_RADIUS := 110.0
const RADIUS_SMOOTHING := 4.0
const DARKNESS_SPEED := 1.2
const HURT_DECAY := 2.2
const GROUP := &"vision_overlay"
const DEFAULT_DARK_COLOR := Color(0.012, 0.008, 0.025)
const DARK_COLOR_SPEED := 1.5
## Film grain in the post-process at full darkness (0 = off).
const DARK_GRAIN := 0.018
## The darkness raster is locked to the world on blocks of this many screen px.
const PIXEL_SIZE := 4.0
## Coloured light (R6, TESTWERTE): tint of what a light touches and faint haze in the dark.
const LIGHT_TINT := 0.6
const LIGHT_HAZE := 0.08
## Lit areas a little brighter than the plain scene (R6, TESTWERT).
const LIGHT_BOOST := 0.15
## Coloured light fades in with the darkness (none in daylight): glow = clamp(darkness * this).
const GLOW_PER_DARKNESS := 2.5
## L1 (TESTWERTE): glow halo strength and core size (share of the light radius), shadow lift and
## highlight tint of the biome grade, how fast the grade follows a biome change.
const HALO_STRENGTH := 0.42
const HALO_SHARE := 0.5
## Self-lit art (lava, flames, crystals): share of the darkness kept off, glow strength, reach in
## world px (TESTWERTE).
const EMISSIVE_KEEP := 0.75
const EMISSIVE_GLOW := 0.55
const EMISSIVE_RADIUS := 5.0
## Self-lit only for details: share of bright neighbours (1 / this) at which it is fully off, so
## large bright areas like door light cones never glow as a block (L1 rework, TESTWERT).
const EMISSIVE_AREA := 1.6
const SHADOW_LIFT := 0.35
const HIGHLIGHT_MIX := 0.5
const GRADE_SPEED := 1.5

var _material: ShaderMaterial
var _rect: ColorRect
var _player: Player = null
var _darkness := 0.0
var _target_darkness := 0.0
var _radius := 300.0
var _base_radius := 300.0
var _blind_left := 0.0
var _hurt := 0.0
var _dark_color := DEFAULT_DARK_COLOR
var _target_dark_color := DEFAULT_DARK_COLOR
var _post_process: PostProcess = null
var _darkness_visibility: DarknessVisibility = null
## Look of the current room (R6) and its smoothed values.
var _profile: LightingProfile = LightingProfile.for_biome(&"")
var _ambient := 1.0
var _player_scale := 1.0
var _source_scale := 1.0
var _softness_scale := 1.0
var _visual_darkness := 0.0
## Biome grade (L1): target from set_biome, drawn value blends towards the effective one.
var _grade_target: BiomeGrade = BiomeGrade.for_biome(&"")
var _grade: BiomeGrade = BiomeGrade.neutral()


func _ready() -> void:
	add_to_group(GROUP)
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)
	_post_process = PostProcess.new()
	_post_process.name = "PostProcess"
	add_child(_post_process)
	_darkness_visibility = DarknessVisibility.new()
	_darkness_visibility.name = "DarknessVisibility"
	_darkness_visibility.overlay = self
	add_child(_darkness_visibility)
	_snap_profile()
	_grade = _effective_grade()


func bind_player(player: Player) -> void:
	_player = player
	_blind_left = 0.0
	player.hurtbox.hit_received.connect(_on_player_hit)
	player.blinded.connect(blind)
	_post_process.bind_player(player)
	# The dungeon announces every room it activates; its look follows (R6). Effects only listen.
	var world := player.get_parent()
	if world != null and world.has_signal(&"room_activated") and not world.is_connected(&"room_activated", _on_room_activated):
		world.connect(&"room_activated", _on_room_activated)


## darkness 0 = bright (village), 1 = only lights visible. radius in world px. These are the logical
## (gameplay) values; what is drawn follows the LightingProfile (R6).
func set_vision(darkness: float, radius: float, instant := false) -> void:
	_target_darkness = darkness
	_base_radius = radius
	if instant:
		_darkness = darkness
		_radius = radius
		_snap_profile()


## Colour of the darkness, e.g. BiomeData.darkness_color. Blends over ~0.7 s unless instant.
func set_dark_color(color: Color, instant := false) -> void:
	_target_dark_color = Color(color, 1.0)
	if instant:
		_dark_color = _target_dark_color


## Applies a biome's darkness colour, ambient particles (dust, spores, wisps, embers) and its
## default look (LightingProfile.for_biome) until a room sets its own.
func set_biome(biome: BiomeData, instant := false) -> void:
	var biome_id: StringName = biome.id if biome != null else &""
	set_dark_color(biome.darkness_color if biome != null else DEFAULT_DARK_COLOR, instant)
	AmbientParticles.set_biome_for(self, biome_id)
	set_lighting(LightingProfile.for_biome(biome_id), instant)
	set_grade(BiomeGrade.for_biome(biome_id), instant)


## Colour grading of the dungeon (L1). Blends over ~0.7 s unless instant. The village and the menu
## use their own grade (see _effective_grade).
func set_grade(grade: BiomeGrade, instant := false) -> void:
	_grade_target = grade if grade != null else BiomeGrade.for_biome(&"")
	if instant:
		_grade = _effective_grade()


## The grade as drawn right now (after blending; neutral with LightingQuality low).
func get_grade() -> BiomeGrade:
	return _grade if LightingQuality.is_high() else BiomeGrade.neutral()


## Look of the current room (R6): ambient cap and drawn circle sizes. Blends unless instant.
func set_lighting(profile: LightingProfile, instant := false) -> void:
	_profile = profile if profile != null else LightingProfile.for_biome(&"")
	if instant:
		_snap_profile()


func get_lighting() -> LightingProfile:
	return _effective_profile()


func get_dark_color() -> Color:
	return _target_dark_color


func get_post_process() -> PostProcess:
	return _post_process


func get_darkness_visibility() -> DarknessVisibility:
	return _darkness_visibility


## The local player whose light is drawn (null before bind_player).
func get_bound_player() -> Player:
	return _player if _player != null and is_instance_valid(_player) else null


func blind(duration: float) -> void:
	_blind_left = maxf(_blind_left, duration)


## The logical (gameplay) radius of the player's circle, as LightQuery sees it.
func get_current_radius() -> float:
	return _radius


## The radius of the player's circle as drawn (R6: wider than the logical one outside deep rooms).
func get_visual_radius() -> float:
	return _radius * _player_scale


## The darkness of the unlit environment as drawn (after the ambient cap).
func get_visual_darkness() -> float:
	return _visual_darkness


## Soft edge of the player's circle as drawn, in world px.
func get_visual_softness() -> float:
	return LightingProfile.SOFTNESS_PX * _player_scale * _softness_scale


## Drawn player radius = logical radius * this (R6).
func get_player_scale() -> float:
	return _player_scale


## Drawn source radius = LightSource.radius * this (R6).
func get_source_scale() -> float:
	return _source_scale


func _process(delta: float) -> void:
	var running := not get_tree().paused
	if running:
		_blind_left = maxf(0.0, _blind_left - delta)
	var blinded := _blind_left > 0.0
	# Laterne of the forge (KE4) widens the circle; blindness still wins (BLIND_RADIUS caps it).
	var lit_radius := _base_radius * MetaProgression.player_light_factor(get_bound_player())
	var target_radius := minf(lit_radius, BLIND_RADIUS) if blinded else lit_radius
	# Dark zones of a room (A3 ingredient) narrow the circle while the player stands in them;
	# Klarsicht (KE5 Proviant) keeps it open there.
	if _player != null and is_instance_valid(_player) and not MetaProgression.player_blind_immune(_player):
		target_radius *= DarkZone.get_vision_factor_at(get_tree(), _player.global_position)
	_radius = lerpf(_radius, target_radius, 1.0 - exp(-RADIUS_SMOOTHING * delta))
	# The logical circle is the player's light for gameplay (LightQuery, A9): state at the player.
	if _player != null and is_instance_valid(_player):
		LightQuery.set_player_radius(_player, _radius)
	_darkness = move_toward(_darkness, _target_darkness, DARKNESS_SPEED * delta)
	_update_profile(delta, blinded)
	_visual_darkness = LightingProfile.visual_darkness(_darkness, _ambient)
	_hurt = maxf(0.0, _hurt - HURT_DECAY * delta)
	var blend := 1.0 - exp(-DARK_COLOR_SPEED * 3.0 * delta)
	_dark_color = _dark_color.lerp(_target_dark_color, blend)
	_post_process.grain = DARK_GRAIN * clampf((_visual_darkness - 0.5) * 2.0, 0.0, 1.0)
	_grade = _grade.lerp_to(_effective_grade(), 1.0 - exp(-GRADE_SPEED * 3.0 * delta))

	var screen := get_viewport().get_visible_rect().size
	var canvas := get_viewport().get_canvas_transform()
	var zoom := canvas.get_scale().x
	var drawn_radius := get_visual_radius()
	_material.set_shader_parameter(&"screen_size", screen)
	_material.set_shader_parameter(&"darkness", _visual_darkness)
	_material.set_shader_parameter(&"vision_radius", drawn_radius * zoom)
	_material.set_shader_parameter(&"softness", get_visual_softness() * zoom)
	_material.set_shader_parameter(&"hurt", _hurt)
	_material.set_shader_parameter(&"dark_color", _dark_color)
	_material.set_shader_parameter(&"pixel_size", PIXEL_SIZE)
	_material.set_shader_parameter(&"tint_strength", LIGHT_TINT)
	_material.set_shader_parameter(&"haze_strength", LIGHT_HAZE)
	_material.set_shader_parameter(&"light_boost", LIGHT_BOOST)
	_material.set_shader_parameter(&"glow_amount", clampf(_visual_darkness * GLOW_PER_DARKNESS, 0.0, 1.0))
	# Lock the dither raster to the world, so it scrolls with the floor instead of shimmering.
	var origin := canvas.origin
	_material.set_shader_parameter(&"grid_offset", Vector2(fposmod(origin.x, PIXEL_SIZE * 4.0), fposmod(origin.y, PIXEL_SIZE * 4.0)))
	_apply_fx(origin, zoom)

	var low_hp := 0.0
	if _player != null and is_instance_valid(_player) and _player.is_alive():
		# The circle sits where gameplay counts it: at the player's figure (LightQuery, D-212).
		_material.set_shader_parameter(&"player_pos", canvas * LightQuery.get_player_light_center(_player))
		var hp := _player.health.get_health()
		low_hp = 1.0 if hp <= 1.0 else (0.55 if hp <= 2.0 else 0.0)
	_material.set_shader_parameter(&"low_hp", low_hp)
	# The pass reads the whole screen: skip it while it would change nothing (village by day).
	_rect.visible = _visual_darkness > 0.001 or _hurt > 0.0 or low_hp > 0.0
	_update_lights(canvas, zoom, screen)


## The profile that applies right now: outside the dungeon (village, menu) nothing is lifted.
func _effective_profile() -> LightingProfile:
	if GameManager.get_phase() != GameManager.Phase.DUNGEON:
		return LightingProfile.neutral()
	return _profile


## The grade that applies right now: the biome's in the dungeon, warm lamps and blue shadows in the
## village at night (none by day), nothing in the menu.
func _effective_grade() -> BiomeGrade:
	match GameManager.get_phase():
		GameManager.Phase.DUNGEON:
			return _grade_target
		GameManager.Phase.VILLAGE:
			return BiomeGrade.for_village(VillageDaylight.night_from_darkness(_visual_darkness))
	return BiomeGrade.neutral()


## L1 parameters of the pass: quality switch, halo, mist (world-locked) and the biome grade.
func _apply_fx(origin: Vector2, zoom: float) -> void:
	var grade := get_grade()
	_material.set_shader_parameter(&"quality", 1.0 if LightingQuality.is_high() else 0.0)
	_material.set_shader_parameter(&"halo_strength", HALO_STRENGTH)
	_material.set_shader_parameter(&"halo_share", HALO_SHARE)
	_material.set_shader_parameter(&"emissive_keep", EMISSIVE_KEEP)
	_material.set_shader_parameter(&"emissive_area", EMISSIVE_AREA)
	_material.set_shader_parameter(&"emissive_glow", EMISSIVE_GLOW)
	_material.set_shader_parameter(&"emissive_radius", EMISSIVE_RADIUS * zoom)
	_material.set_shader_parameter(&"world_origin", origin)
	_material.set_shader_parameter(&"world_zoom", zoom)
	_material.set_shader_parameter(&"mist_strength", grade.mist)
	_material.set_shader_parameter(&"grade_shadow", grade.shadow)
	_material.set_shader_parameter(&"grade_highlight", grade.highlight)
	_material.set_shader_parameter(&"grade_amount", grade.amount)
	_material.set_shader_parameter(&"shadow_lift", SHADOW_LIFT)
	_material.set_shader_parameter(&"highlight_mix", HIGHLIGHT_MIX)
	_material.set_shader_parameter(&"vignette", grade.vignette)


func _update_profile(delta: float, blinded: bool) -> void:
	var profile := _effective_profile()
	var target_ambient := profile.ambient
	var target_scale := profile.player_radius_scale
	if blinded:
		# Blindness takes the lifted environment and the wide circle away (optics only).
		target_ambient = maxf(target_ambient, LightingProfile.BLIND_AMBIENT)
		target_scale = 1.0
	_ambient = move_toward(_ambient, target_ambient, DARKNESS_SPEED * delta)
	var k := 1.0 - exp(-RADIUS_SMOOTHING * delta)
	_player_scale = lerpf(_player_scale, target_scale, k)
	_source_scale = lerpf(_source_scale, profile.source_radius_scale, k)
	_softness_scale = lerpf(_softness_scale, profile.softness_scale, k)


func _snap_profile() -> void:
	var profile := _effective_profile()
	_ambient = profile.ambient
	_player_scale = profile.player_radius_scale
	_source_scale = profile.source_radius_scale
	_softness_scale = profile.softness_scale
	_visual_darkness = LightingProfile.visual_darkness(_darkness, _ambient)


func _update_lights(canvas: Transform2D, zoom: float, screen: Vector2) -> void:
	var packed := PackedVector4Array()
	var colors := PackedVector4Array()
	var halos := PackedFloat32Array()
	if _visual_darkness > 0.0:
		var picked := pick_lights(get_tree().get_nodes_in_group(LightSource.GROUP), canvas, zoom * _source_scale, screen)
		for entry in picked:
			var light: LightSource = entry[0]
			var pos: Vector2 = entry[1]
			var r: float = entry[2]
			# Lights of a room still under its veil stay dim (they would shine through the rock); an
			# enemy's glow fades with the enemy (DarknessVisibility).
			packed.append(Vector4(pos.x, pos.y, r, light.get_draw_intensity() * light.get_veil_factor() * light.draw_factor))
			var color := light.get_draw_color()
			colors.append(Vector4(color.r, color.g, color.b, LightPalette.tint_strength(color)))
			halos.append(light.get_halo())
	var count := packed.size()
	while packed.size() < MAX_LIGHTS:
		packed.append(Vector4.ZERO)
		colors.append(Vector4.ZERO)
		halos.append(0.0)
	_material.set_shader_parameter(&"lights", packed)
	_material.set_shader_parameter(&"light_colors", colors)
	_material.set_shader_parameter(&"light_halos", halos)
	_material.set_shader_parameter(&"light_count", count)


## The lights to draw: every burning LightSource whose circle touches the screen, as
## [light, screen position, screen radius]. With more than MAX_LIGHTS the gameplay lights
## (counts_as_light) come first, then the strongest ones nearest to the view centre.
static func pick_lights(nodes: Array, canvas: Transform2D, radius_scale: float, screen: Vector2) -> Array:
	var visible_lights: Array = []
	for node in nodes:
		var light := node as LightSource
		if light == null or not light.is_lit() or light.draw_factor <= 0.01:
			continue
		var pos := canvas * light.global_position
		var r := light.get_current_radius() * radius_scale
		if pos.x < -r or pos.y < -r or pos.x > screen.x + r or pos.y > screen.y + r:
			continue
		visible_lights.append([light, pos, r])
	if visible_lights.size() <= MAX_LIGHTS:
		return visible_lights
	var centre := screen * 0.5
	var diagonal := maxf(screen.length(), 1.0)
	for entry in visible_lights:
		var light: LightSource = entry[0]
		var dist: float = (entry[1] as Vector2).distance_to(centre)
		var score := light.intensity * float(entry[2]) / (1.0 + dist / diagonal * 4.0)
		if light.counts_as_light:
			score += 1000000.0
		entry.append(score)
	visible_lights.sort_custom(func(a: Array, b: Array) -> bool: return float(a[3]) > float(b[3]))
	visible_lights.resize(MAX_LIGHTS)
	return visible_lights


func _on_room_activated(room: Node) -> void:
	set_lighting(LightingProfile.for_room(room), int(room.get(&"room_index")) <= 1)


func _on_player_hit(result: DamageResult, _damage: DamageData) -> void:
	if result.is_effective():
		_hurt = 1.0
