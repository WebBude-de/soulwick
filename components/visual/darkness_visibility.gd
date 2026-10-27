class_name DarknessVisibility
extends Node
## Enemies in the dark stay unseen (Projektmitglied 15.10.2026: "Gegner außerhalb seines Radius
## wirklich nicht sehen, erst reinfaden, wenn sie im Sichtkreis sind"). Pure optics for the LOCAL
## viewer: AI, hits and target choice never read it (the host computes everything in co-op; every
## machine fades for its own local player). Owned by the VisionOverlay, which knows the local player
## and draws the light this class follows: what is drawn as light shows enemies, nothing else.
##
## Light that shows an enemy (viewer circles, x/y = centre in global px, z = edge radius):
##   - the local player's circle as drawn (LightingProfile scale, Finsternis and blindness included),
##     edge where half of its light is left,
##   - every drawn LightSource that is not an enemy's own glow (torches, fires, crystals, lanterns,
##     the player's fire projectiles, explosion flashes), edge at its half light,
##   - co-op: the other living players' circles (logical radius scaled like the local one). The shader
##     does not draw them yet (MP5 "eigener Lichtkreis je Spieler"); they already count, so a mate's
##     fight stays readable.
## What fades: every visual child of the enemy (sprite, health bar, badges, elite name, shadow, its
## glow light). Telegraphs (TelegraphCircle, TelegraphLine, HopMarker) are shown where THEY lie in the
## light, so a leap circle on the lit floor stays visible while the jumper is still in the dark.
## Never hidden: bosses (the boss fight is staged, the boss bar names it), the champion of a miniboss
## room (a staged duel like a boss fight; a champion of an elite nest in a combat room and the
## champion's escorts still hide), the rifts of "Risse schließen" and the crowned one of "Jagd"
## (objectives), and anything with ALWAYS_VISIBLE_META.
## Enemy projectiles and ground blasts are separate nodes and always visible (D-067: projectiles
## carry light; hiding them would make hits unavoidable).
## Cost: the light circles and the target alpha of every enemy are computed TICK_RATE times a second;
## per frame only fading alphas are written and only visible telegraphs of hidden enemies are checked.

const GROUP := &"darkness_visibility"
## How often the circles and the targets are computed (Hz). TESTWERT
const TICK_RATE := 12.0
## Fade in / out time in seconds. TESTWERT
const FADE_TIME := 0.2
## Width of the soft edge in world px, centred on the edge radius. TESTWERT
const FADE_BAND := 24.0
## The player's circle is drawn soft (vision.gdshader "softness"): the edge that shows enemies lies
## where half of the light is left, this share of the softness inside the drawn radius. TESTWERT
const PLAYER_EDGE_SHARE := 0.5
## A source light falls off from 0.3 r to r (vision.gdshader): half light at 0.65 r. TESTWERT
const SOURCE_EDGE_SHARE := 0.65
## Lights dimmer than this (fading flashes, veiled rooms) show nothing. TESTWERT
const SOURCE_MIN_INTENSITY := 0.35
## An enemy shows as soon as its body (not only its centre) reaches the light. TESTWERT
const ENEMY_MARGIN := 12.0
## Below this drawn darkness (special rooms, village by day) every enemy is visible. TESTWERT
const MIN_DARKNESS := 0.3
## Lights farther than this outside the visible world rect are skipped (world px).
const CULL_MARGIN := 160.0
## Damage numbers spawn only where an enemy would be at least this visible.
const NUMBER_MIN_ALPHA := 0.5
const TELEGRAPH_NODES: Array[StringName] = [&"TelegraphCircle", &"TelegraphLine", &"HopMarker"]
## The enemy's own glow (Enemy._apply_data) fades with it and never shows enemies.
const ENEMY_GLOW := &"Glow"
const SPRITE_NODE := &"Sprite"
## Set on an enemy (any value) to keep it visible in the dark.
const ALWAYS_VISIBLE_META := &"always_visible_in_dark"
const ENEMIES_GROUP := &"enemies"


## Fade state of one enemy (only enemies that can hide get one).
class View:
	var enemy: Node2D
	var alpha := 1.0
	var target := 1.0
	var child_count := -1
	## Body visuals: the Sprite fades through self_modulate (its modulate belongs to the enemy code
	## and is mirrored in co-op), everything else through modulate.
	var items: Array[CanvasItem] = []
	var telegraphs: Array[CanvasItem] = []
	var lights: Array[LightSource] = []


## Drawn light the overlay follows (null in tests: set_viewer instead).
var overlay: VisionOverlay = null

var _views: Dictionary = {}  # instance id -> View
var _circles: Array[Vector3] = []
var _active := false
var _tick_left := 0.0
## Test hook: fixed viewer circles and darkness instead of the overlay.
var _fixed_circles: Variant = null
var _fixed_darkness := 1.0


# --- Pure decision ---

## Visibility 0..1 of a point in the viewer circles (z = edge radius): 1 well inside, 0 outside,
## soft over band px centred on the edge.
static func alpha_in_circles(point: Vector2, circles: Array[Vector3], band := FADE_BAND, margin := 0.0) -> float:
	var best := 0.0
	var half := band * 0.5
	for c in circles:
		var outer := c.z + half + margin
		var dx := point.x - c.x
		var dy := point.y - c.y
		var d2 := dx * dx + dy * dy
		if c.z <= 0.0 or d2 >= outer * outer:
			continue
		var t := clampf((outer - sqrt(d2)) / maxf(band, 0.001), 0.0, 1.0)
		best = maxf(best, t * t * (3.0 - 2.0 * t))
		if best >= 1.0:
			return 1.0
	return best


## Edge radius of a player circle drawn with drawn_radius and softness (both world px).
static func player_edge(drawn_radius: float, softness: float) -> float:
	return maxf(0.0, drawn_radius - softness * PLAYER_EDGE_SHARE)


## Edge radius of a drawn source light (radius in world px, intensity as drawn).
static func source_edge(drawn_radius: float, intensity: float) -> float:
	if intensity < SOURCE_MIN_INTENSITY:
		return 0.0
	return drawn_radius * SOURCE_EDGE_SHARE


## Whether this enemy may fade out in the dark at all.
static func can_hide(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.has_meta(ALWAYS_VISIBLE_META):
		return false
	if enemy is SummoningRift or BountyFlight.of(enemy) != null:
		return false
	if enemy is Enemy and (enemy as Enemy).is_champion() and is_in_miniboss_room(enemy):
		return false
	var data: Variant = enemy.get(&"data")
	return data == null or not bool(data.get(&"is_boss"))


## Whether node lies in a miniboss room (the nearest RoomController above it).
static func is_in_miniboss_room(node: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		var room := current as RoomController
		if room != null:
			return room.room_type == RoomSequence.RoomType.MINIBOSS
		current = current.get_parent()
	return false


## Visibility of a global point for the local viewer (1 without a DarknessVisibility, e.g. tools).
static func alpha_at_point(tree: SceneTree, point: Vector2) -> float:
	if tree == null:
		return 1.0
	var node := tree.get_first_node_in_group(GROUP) as DarknessVisibility
	return node.alpha_at(point) if node != null else 1.0


## Shows a damage number at point? (Numbers on enemies hidden in the dark stay away.)
static func shows_number_at(point: Vector2) -> bool:
	return alpha_at_point(Engine.get_main_loop() as SceneTree, point) >= NUMBER_MIN_ALPHA


# --- Node ---

func _ready() -> void:
	add_to_group(GROUP)
	# The overlay runs always; fades stop with the game (pause menu, dialogs).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group(ENEMIES_GROUP):
		_register(node)
	_refresh(true)


## Test hook: fixed viewer circles (z = edge radius) and drawn darkness instead of the overlay.
func set_viewer(circles: Array[Vector3], darkness := 1.0) -> void:
	_fixed_circles = circles
	_fixed_darkness = darkness


## Visibility of a point right now (circles of the last tick).
func alpha_at(point: Vector2) -> float:
	if not _active:
		return 1.0
	return alpha_in_circles(point, _circles)


## The viewer circles of the last tick (z = edge radius).
func get_circles() -> Array[Vector3]:
	return _circles


## Current (faded) visibility of an enemy, 1 if it never hides.
func get_enemy_alpha(enemy: Node) -> float:
	var view: View = _views.get(enemy.get_instance_id()) if enemy != null else null
	return view.alpha if view != null else 1.0


## Recomputes circles and targets now; snap = no fade (room change, tests).
func refresh(snap := false) -> void:
	_refresh(snap)


func _process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = 1.0 / TICK_RATE
		_refresh(false)
	var step := delta / FADE_TIME
	for id: int in _views.keys():
		var view: View = _views[id]
		if not is_instance_valid(view.enemy):
			_views.erase(id)
			continue
		if not is_equal_approx(view.alpha, view.target):
			view.alpha = move_toward(view.alpha, view.target, step)
			_apply_body(view)
		_update_telegraphs(view)


func _refresh(snap: bool) -> void:
	_active = _collect_circles()
	for id: int in _views.keys():
		var view: View = _views[id]
		if not is_instance_valid(view.enemy) or not view.enemy.is_inside_tree():
			_views.erase(id)
			continue
		if view.enemy.get_child_count() != view.child_count:
			_collect_items(view)
			_apply_body(view)
		view.target = _target_alpha(view.enemy)
		if snap:
			view.alpha = view.target
			_apply_body(view)


func _target_alpha(enemy: Node2D) -> float:
	if not _active or not can_hide(enemy):
		return 1.0
	return alpha_in_circles(enemy.global_position, _circles, FADE_BAND, ENEMY_MARGIN)


## Builds the viewer circles; false = nothing hides right now (too bright, no viewer).
func _collect_circles() -> bool:
	_circles.clear()
	if _fixed_circles != null:
		_circles.append_array(_fixed_circles)
		return _fixed_darkness >= MIN_DARKNESS
	if overlay == null or not is_instance_valid(overlay):
		return false
	var viewer := overlay.get_bound_player()
	if viewer == null or not is_instance_valid(viewer) or not viewer.is_inside_tree():
		return false
	if overlay.get_visual_darkness() < MIN_DARKNESS:
		return false
	_circles.append(LightQuery.circle(LightQuery.get_player_light_center(viewer), player_edge(overlay.get_visual_radius(), overlay.get_visual_softness())))
	# Co-op: the mates' circles show enemies too (logical radius at the mate, scaled like ours).
	for mate in EnemyTargeting.living_players(get_tree()):
		if mate != viewer:
			var drawn := LightQuery.get_player_radius(mate) * overlay.get_player_scale()
			_circles.append(LightQuery.circle(LightQuery.get_player_light_center(mate), player_edge(drawn, overlay.get_visual_softness())))
	var source_scale := overlay.get_source_scale()
	var view_rect := _visible_world_rect().grow(CULL_MARGIN)
	for node in get_tree().get_nodes_in_group(LightSource.GROUP):
		var light := node as LightSource
		if light == null or not light.is_lit() or light.get_parent() is Enemy:
			continue
		var edge := source_edge(light.radius * source_scale, light.intensity * light.get_veil_factor())
		if edge <= 0.0:
			continue
		var pos := light.global_position
		if not view_rect.grow(edge).has_point(pos):
			continue
		_circles.append(LightQuery.circle(pos, edge))
	return true


## The world rect on screen right now (lights outside it cannot show an enemy the player sees).
func _visible_world_rect() -> Rect2:
	var viewport := get_viewport()
	var screen := viewport.get_visible_rect()
	return viewport.get_canvas_transform().affine_inverse() * screen


func _on_node_added(node: Node) -> void:
	if not node is Enemy:
		return
	if node.is_node_ready():
		_register(node)
	else:
		# After its children exist (ready), so the first frame already shows the right alpha.
		node.ready.connect(_register.bind(node), CONNECT_ONE_SHOT)


func _register(node: Node) -> void:
	var enemy := node as Enemy
	if enemy == null or not is_instance_valid(enemy) or _views.has(enemy.get_instance_id()):
		return
	if enemy.has_meta(ALWAYS_VISIBLE_META) or (enemy.data != null and enemy.data.is_boss):
		return
	var view := View.new()
	view.enemy = enemy
	_collect_items(view)
	view.target = _target_alpha(enemy)
	view.alpha = view.target
	_views[enemy.get_instance_id()] = view
	_apply_body(view)


func _collect_items(view: View) -> void:
	view.items.clear()
	view.telegraphs.clear()
	view.lights.clear()
	view.child_count = view.enemy.get_child_count()
	for child in view.enemy.get_children():
		if child is LightSource:
			if child.name == ENEMY_GLOW:
				view.lights.append(child)
		elif child is CollisionObject2D or child is CollisionShape2D:
			continue
		elif child is CanvasItem:
			if TELEGRAPH_NODES.has(child.name):
				view.telegraphs.append(child)
			else:
				view.items.append(child)


func _apply_body(view: View) -> void:
	var a := view.alpha
	for item in view.items:
		if not is_instance_valid(item):
			continue
		if item.name == SPRITE_NODE:
			item.self_modulate.a = a
		else:
			item.modulate.a = a
	for light in view.lights:
		if is_instance_valid(light):
			light.draw_factor = a


## A telegraph shows where it lies in the light, never less than its enemy.
func _update_telegraphs(view: View) -> void:
	for item in view.telegraphs:
		if not is_instance_valid(item):
			continue
		var a := view.alpha
		if a < 1.0 and item.visible and _active:
			a = maxf(a, _telegraph_alpha(item))
		if not is_equal_approx(item.self_modulate.a, a):
			item.self_modulate.a = a


func _telegraph_alpha(item: CanvasItem) -> float:
	var node := item as Node2D
	if node == null:
		return 1.0
	var line := item as Line2D
	if line != null and line.points.size() > 0:
		var start := line.global_transform * line.points[0]
		var end := line.global_transform * line.points[line.points.size() - 1]
		return maxf(alpha_in_circles(start, _circles), alpha_in_circles(end, _circles))
	# A circle shows as soon as its rim reaches the light.
	var radius: Variant = item.get(&"radius")
	var margin := float(radius) * float(absf(node.global_scale.x)) if radius is float else 0.0
	return alpha_in_circles(node.global_position, _circles, FADE_BAND, margin)
