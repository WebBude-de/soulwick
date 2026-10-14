class_name VisionOverlay
extends CanvasLayer
## Drives vision.gdshader: dungeon darkness with a light circle around the player and all
## LightSource nodes (D-067), blindness, red damage edge and the low-HP vignette.
## Only draws: whether a point is lit for gameplay is LightQuery's decision; the overlay hands it the
## bound player's current circle radius (state at the player).
## Also owns the PostProcess pass (layer 3) and forwards the bound player to it.

const SHADER: Shader = preload("res://components/visual/vision.gdshader")
const MAX_LIGHTS := 24
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

var _material: ShaderMaterial
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


func _ready() -> void:
	add_to_group(GROUP)
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	rect.material = _material
	add_child(rect)
	_post_process = PostProcess.new()
	_post_process.name = "PostProcess"
	add_child(_post_process)


func bind_player(player: Player) -> void:
	_player = player
	_blind_left = 0.0
	player.hurtbox.hit_received.connect(_on_player_hit)
	player.blinded.connect(blind)
	_post_process.bind_player(player)


## darkness 0 = bright (village), 1 = only lights visible. radius in world px.
func set_vision(darkness: float, radius: float, instant := false) -> void:
	_target_darkness = darkness
	_base_radius = radius
	if instant:
		_darkness = darkness
		_radius = radius


## Colour of the darkness, e.g. BiomeData.darkness_color. Blends over ~0.7 s unless instant.
func set_dark_color(color: Color, instant := false) -> void:
	_target_dark_color = Color(color, 1.0)
	if instant:
		_dark_color = _target_dark_color


## Applies a biome's darkness colour and ambient particles (dust, spores, wisps, embers).
func set_biome(biome: BiomeData, instant := false) -> void:
	if biome == null:
		set_dark_color(DEFAULT_DARK_COLOR, instant)
		AmbientParticles.set_biome_for(self, &"")
		return
	set_dark_color(biome.darkness_color, instant)
	AmbientParticles.set_biome_for(self, biome.id)


func get_dark_color() -> Color:
	return _target_dark_color


func get_post_process() -> PostProcess:
	return _post_process


func blind(duration: float) -> void:
	_blind_left = maxf(_blind_left, duration)


func get_current_radius() -> float:
	return _radius


func _process(delta: float) -> void:
	var running := not get_tree().paused
	if running:
		_blind_left = maxf(0.0, _blind_left - delta)
	var target_radius := minf(_base_radius, BLIND_RADIUS) if _blind_left > 0.0 else _base_radius
	# Dark zones of a room (A3 ingredient) narrow the circle while the player stands in them.
	if _player != null and is_instance_valid(_player):
		target_radius *= DarkZone.get_vision_factor_at(get_tree(), _player.global_position)
	_radius = lerpf(_radius, target_radius, 1.0 - exp(-RADIUS_SMOOTHING * delta))
	# The circle as drawn is the player's light for gameplay too (LightQuery, A9): state at the player.
	if _player != null and is_instance_valid(_player):
		LightQuery.set_player_radius(_player, _radius)
	_darkness = move_toward(_darkness, _target_darkness, DARKNESS_SPEED * delta)
	_hurt = maxf(0.0, _hurt - HURT_DECAY * delta)
	var blend := 1.0 - exp(-DARK_COLOR_SPEED * 3.0 * delta)
	_dark_color = _dark_color.lerp(_target_dark_color, blend)
	_post_process.grain = DARK_GRAIN * clampf((_darkness - 0.5) * 2.0, 0.0, 1.0)

	var screen := get_viewport().get_visible_rect().size
	var canvas := get_viewport().get_canvas_transform()
	var zoom := canvas.get_scale().x
	_material.set_shader_parameter(&"screen_size", screen)
	_material.set_shader_parameter(&"darkness", _darkness)
	_material.set_shader_parameter(&"vision_radius", _radius * zoom)
	_material.set_shader_parameter(&"softness", 150.0 * zoom)
	_material.set_shader_parameter(&"hurt", _hurt)
	_material.set_shader_parameter(&"dark_color", _dark_color)
	_material.set_shader_parameter(&"pixel_size", PIXEL_SIZE)
	# Lock the dither raster to the world, so it scrolls with the floor instead of shimmering.
	var origin := canvas.origin
	_material.set_shader_parameter(&"grid_offset", Vector2(fposmod(origin.x, PIXEL_SIZE * 4.0), fposmod(origin.y, PIXEL_SIZE * 4.0)))

	var low_hp := 0.0
	if _player != null and is_instance_valid(_player) and _player.is_alive():
		_material.set_shader_parameter(&"player_pos", canvas * _player.global_position)
		var hp := _player.health.get_health()
		low_hp = 1.0 if hp <= 1.0 else (0.55 if hp <= 2.0 else 0.0)
	_material.set_shader_parameter(&"low_hp", low_hp)
	_update_lights(canvas, zoom, screen)


func _update_lights(canvas: Transform2D, zoom: float, screen: Vector2) -> void:
	var packed := PackedVector4Array()
	if _darkness > 0.0:
		for node in get_tree().get_nodes_in_group(LightSource.GROUP):
			var light := node as LightSource
			if light == null or not light.is_lit():
				continue
			var pos := canvas * light.global_position
			var r := light.get_current_radius() * zoom
			if pos.x < -r or pos.y < -r or pos.x > screen.x + r or pos.y > screen.y + r:
				continue
			packed.append(Vector4(pos.x, pos.y, r, light.intensity))
			if packed.size() >= MAX_LIGHTS:
				break
	var count := packed.size()
	while packed.size() < MAX_LIGHTS:
		packed.append(Vector4.ZERO)
	_material.set_shader_parameter(&"lights", packed)
	_material.set_shader_parameter(&"light_count", count)


func _on_player_hit(result: DamageResult, _damage: DamageData) -> void:
	if result.is_effective():
		_hurt = 1.0
