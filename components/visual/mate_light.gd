class_name MateLight
extends LightSource
## Co-op (MP5, D-191): the light circle of a teammate, drawn on this machine. The VisionOverlay draws
## only the circle of its own (bound) player; every other player of the session carries a MateLight,
## so a mate walking ahead lights his way on every screen. Optics only: counts_as_light stays off
## (the gameplay already counts every player's own circle, LightQuery.player_circles), no halo.
## Its size follows the same circle DarknessVisibility shows enemies in (LightQuery.get_player_radius
## of the mate, scaled like the own circle), narrowed for a downed mate and gone in a tunnel under
## the rock (set_hidden by the NetDungeon).

const NODE_NAME := &"MateLight"
## TESTWERTE: brightness (the own circle stays the brightest) and size of a downed mate's glow.
const MATE_INTENSITY := 0.85
const DOWNED_SHARE := 0.4
## Drawn size relative to the own circle (a source fades from 30 % of its radius on).
const DRAW_SCALE := 1.0

var mate: Player = null
var _hidden := false


## The MateLight of player, created on first use.
static func attach(player: Player) -> MateLight:
	if player == null or not is_instance_valid(player):
		return null
	var existing := of(player)
	if existing != null:
		return existing
	var light := MateLight.new()
	light.name = NODE_NAME
	light.mate = player
	player.add_child(light)
	return light


static func of(player: Node) -> MateLight:
	if player == null or not is_instance_valid(player):
		return null
	return player.get_node_or_null(NodePath(NODE_NAME)) as MateLight


## Drawn radius of a mate's light: logical radius * the overlay's player scale / its source scale
## (the overlay scales every source by that), smaller while the mate is down.
static func radius_for(logical: float, player_scale: float, source_scale: float, downed: bool) -> float:
	var drawn := logical * player_scale * DRAW_SCALE / maxf(0.01, source_scale)
	return drawn * DOWNED_SHARE if downed else drawn


func _init() -> void:
	color = Color(LightPalette.NEUTRAL, 1.0)
	halo = 0.0
	intensity = MATE_INTENSITY
	counts_as_light = false


func set_hidden(hidden: bool) -> void:
	_hidden = hidden
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if mate == null or not is_instance_valid(mate):
		visible = false
		return
	var gone := mate.health != null and mate.health.is_dead() and not mate.is_downed()
	visible = not _hidden and not gone
	if not visible:
		return
	var player_scale := 1.0
	var source_scale := 1.0
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay if is_inside_tree() else null
	if overlay != null:
		player_scale = overlay.get_player_scale()
		source_scale = overlay.get_source_scale()
	radius = radius_for(LightQuery.get_player_radius(mate), player_scale, source_scale, mate.is_downed())
	# The mate's circle sits at the mate's figure like the own one (D-212).
	global_position = LightQuery.get_player_light_center(mate)
