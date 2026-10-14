class_name WagerAltar
extends Node2D
## Wager altar (KONZEPT_RAEUME §5, D-104, D-109): stands right behind the entrance of a normal
## combat room and offers one condition - a trial (no hit, under 30 s, secondary weapon only) or a
## curse (light circle -40 %, enemies +15 % speed, no healing in this room). Accepted with E while
## the door is still open; once a player walks in, the offer is gone. Met when the room is cleared
## -> soul crystals; broken -> nothing more happens (no further penalty).
## Co-op: the condition holds for the group, any player may accept it (D-104).
## Decisions (accept, break, resolve) are functions that emit signals; effects (banner, crystals,
## light, enemy speed, blocked heals) follow them (D-088). The condition is drawn on attach with
## the dungeon RNG (one number).

signal accepted(altar: WagerAltar, player: Player)
signal broken(altar: WagerAltar)
signal resolved(altar: WagerAltar, won: bool)

enum State { OFFERED, ACCEPTED, DECLINED, WON, LOST }

const NODE_NAME := &"WagerAltar"
const COLOR := Color("#dcbcff")
const WON_COLOR := Color("#f2cf4a")
const LOST_COLOR := Color("#e0463a")
const LIGHT_RADIUS := 130.0
const INTERACT_RADIUS := 60.0
const FOOTPRINT := Vector2(40, 18)
const SPEED_META := &"wager_haste"

var condition: WagerRules.Condition = WagerRules.Condition.NO_HIT
var state := State.OFFERED
var room: RoomController = null
var context: DungeonContext = null

var _elapsed := 0.0
var _fighting := false
## Health of each player while healing is blocked: player instance id -> last value.
var _health_seen: Dictionary[int, float] = {}
var _connected_players: Array[Player] = []
var _interactable: Interactable = null
var _sprite: AnimatedSprite2D = null
var _light: LightSource = null
var _vision_radius := -1.0


# --- Creation (RoomVariants.attach) ---

## Places an altar next to the entrance of a prepared normal combat room. roll: one number of the
## dungeon RNG, drawn by the caller in any case. Null if there is no free tile beside the entrance.
static func attach_to(target: RoomController, roll: float) -> WagerAltar:
	if target == null or not is_instance_valid(target) or not target.has_room_kind() or of(target) != null:
		return null
	var free := VariantSpots.free_tiles(target)
	var tile := VariantSpots.altar_tile(free, target.tiles.get_entrance_inside_tile())
	if tile == VariantSpots.INVALID:
		return null
	var altar := WagerAltar.new()
	altar.name = NODE_NAME
	altar.room = target
	altar.context = target.context
	altar.condition = WagerRules.pick(roll, has_second_weapon(target.context))
	# Origin = body centre like a character's, so it sorts against the players' feet.
	altar.position = RoomTiles.tile_center(tile) + Vector2(0, 26.0 - Player.FEET_OFFSET.y)
	target.add_child(altar)
	target.tiles.set_navigation_blocked(tile, true)
	altar._build()
	altar._connect_room()
	return altar


static func of(target: Node) -> WagerAltar:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NodePath(NODE_NAME)) as WagerAltar


## Does the group have a second weapon (condition "secondary weapon only")?
static func has_second_weapon(dungeon_context: DungeonContext) -> bool:
	if dungeon_context == null or dungeon_context.player == null or not is_instance_valid(dungeon_context.player):
		return false
	return dungeon_context.player.weapon_controller.get_weapon(1) != null


# --- Decisions ---

## A player accepts the wager (E at the altar). Only while the door is open (room not entered).
func accept(player: Player) -> bool:
	if state != State.OFFERED or not can_accept():
		return false
	state = State.ACCEPTED
	accepted.emit(self, player)
	return true


## The door is still open: nobody walked in yet.
func can_accept() -> bool:
	return room != null and room.state == RoomController.State.PREPARED


func is_accepted() -> bool:
	return state == State.ACCEPTED


## The group broke the condition (hit taken, too slow, first weapon used). No further penalty.
func break_wager() -> bool:
	if state != State.ACCEPTED:
		return false
	state = State.LOST
	broken.emit(self)
	resolved.emit(self, false)
	return true


## Room cleared with the wager still standing: won.
func resolve() -> bool:
	if state != State.ACCEPTED:
		return false
	state = State.WON
	resolved.emit(self, true)
	return true


## Fight time of the room (UNDER_TIME) and the check that belongs to it.
func step(delta: float) -> void:
	if not _fighting or state != State.ACCEPTED:
		return
	_elapsed += delta
	if WagerRules.breaks_on_time(condition, _elapsed):
		break_wager()


func get_elapsed() -> float:
	return _elapsed


func register_hit(_player: Player) -> void:
	if _fighting and WagerRules.breaks_on_hit(condition):
		break_wager()


func register_attack(slot: int) -> void:
	if _fighting and WagerRules.breaks_on_attack(condition, slot):
		break_wager()


# --- Room flow ---

func _connect_room() -> void:
	room.player_entered.connect(_on_player_entered)
	room.encounter_started.connect(_on_encounter_started)
	room.completed.connect(_on_room_completed)
	room.enemy_container.child_entered_tree.connect(_on_enemy_added)
	accepted.connect(_on_accepted)
	resolved.connect(_on_resolved)


func _physics_process(delta: float) -> void:
	step(delta)


## Walked in: the offer is gone (accepted or declined).
func _on_player_entered(_room: RoomController) -> void:
	if state == State.OFFERED:
		state = State.DECLINED
	if _interactable != null:
		_interactable.enabled = false
	_update_look()


func _on_encounter_started(_room: RoomController, enemies: Array[Enemy]) -> void:
	if state != State.ACCEPTED:
		return
	_fighting = true
	_elapsed = 0.0
	for player in _players():
		_watch_player(player)
	for enemy in enemies:
		_apply_haste(enemy)
	for enemy in _living_enemies():
		_apply_haste(enemy)
	if condition == WagerRules.Condition.CURSE_GLOOM:
		_apply_gloom()


func _on_room_completed(_room: RoomController) -> void:
	_fighting = false
	if state == State.ACCEPTED:
		resolve()
	_release_players()
	_restore_vision()


func _on_enemy_added(node: Node) -> void:
	var enemy := node as Enemy
	if enemy != null and state == State.ACCEPTED:
		_apply_haste(enemy)


# --- Effects ---

func _on_interacted(player: Player) -> void:
	accept(player)


func _on_accepted(_altar: WagerAltar, _player: Player) -> void:
	if _interactable != null:
		_interactable.enabled = false
	_update_look()
	_show_banner(DungeonTexts.t(&"WAGER_ACCEPTED"), WagerRules.get_condition_name(condition), COLOR)
	if is_inside_tree():
		Sfx.play_at(self, &"upgrade", global_position, -4.0)
		Burst.spawn(get_parent(), global_position + Vector2(0, -40), COLOR, 18, 130.0)


func _on_resolved(_altar: WagerAltar, won: bool) -> void:
	_update_look()
	if won:
		var crystals := WagerRules.get_payout(condition, _players().size())
		RunManager.add_run_crystals(crystals)
		_show_banner(DungeonTexts.t(&"WAGER_WON"), DungeonTexts.t(&"WAGER_WON_SUB", [crystals]), WON_COLOR)
	else:
		_show_banner(DungeonTexts.t(&"WAGER_LOST"), DungeonTexts.t(&"WAGER_LOST_SUB"), LOST_COLOR)
	_release_players()
	_restore_vision()


## Watches one player for hits, attacks and heals (group condition, D-104).
func _watch_player(player: Player) -> void:
	if _connected_players.has(player):
		return
	_connected_players.append(player)
	player.hurtbox.hit_received.connect(_on_player_hit.bind(player))
	player.weapon_controller.attack_performed.connect(_on_player_attack.bind(player))
	player.weapon_controller.special_performed.connect(_on_player_attack.bind(player))
	if condition == WagerRules.Condition.CURSE_NO_HEAL:
		_health_seen[player.get_instance_id()] = player.health.get_health()
		player.health.health_changed.connect(_on_player_health_changed.bind(player))


func _release_players() -> void:
	for i in _connected_players.size():
		var player: Variant = _connected_players[i]
		if not is_instance_valid(player):
			continue
		var target := player as Player
		_disconnect(target.hurtbox.hit_received, _on_player_hit)
		_disconnect(target.weapon_controller.attack_performed, _on_player_attack)
		_disconnect(target.weapon_controller.special_performed, _on_player_attack)
		_disconnect(target.health.health_changed, _on_player_health_changed)
	_connected_players.clear()
	_health_seen.clear()


static func _disconnect(sig: Signal, method: Callable) -> void:
	for connection in sig.get_connections():
		var callable: Callable = connection["callable"]
		if callable.get_method() == method.get_method() and callable.get_object() == method.get_object():
			sig.disconnect(callable)


func _on_player_hit(_result: DamageResult, _damage: DamageData, player: Player) -> void:
	register_hit(player)


func _on_player_attack(_weapon: WeaponData, player: Player) -> void:
	if is_instance_valid(player):
		register_attack(player.weapon_controller.get_active_slot())


## Curse "no healing": whatever healed the player in this room is taken back at once.
func _on_player_health_changed(current: float, _maximum: float, player: Player) -> void:
	var id := player.get_instance_id()
	var seen: float = _health_seen.get(id, current)
	if _fighting and state == State.ACCEPTED and current > seen and not player.health.is_dead():
		_health_seen[id] = seen
		player.health.take_damage(current - seen)
		return
	_health_seen[id] = current


## Curse "enemies faster": every enemy of the room gets its own copy of its data, a bit faster.
func _apply_haste(enemy: Enemy) -> void:
	if condition != WagerRules.Condition.CURSE_HASTE or enemy == null or enemy.data == null or enemy.has_meta(SPEED_META):
		return
	var copy := enemy.data.duplicate() as EnemyData
	copy.move_speed *= WagerRules.HASTE_SPEED_FACTOR
	copy.charge_speed *= WagerRules.HASTE_SPEED_FACTOR
	enemy.data = copy
	enemy.set_meta(SPEED_META, true)


func _apply_gloom() -> void:
	var overlay := _overlay()
	if overlay == null:
		return
	_vision_radius = RoomVariants.room_vision_radius(room)
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, _vision_radius * WagerRules.GLOOM_VISION_FACTOR)


func _restore_vision() -> void:
	if _vision_radius < 0.0:
		return
	var overlay := _overlay()
	if overlay != null:
		overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, _vision_radius)
	_vision_radius = -1.0


func _overlay() -> VisionOverlay:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay


func _players() -> Array[Player]:
	var players: Array[Player] = []
	if not is_inside_tree():
		return players
	for node in EnemyTargeting.living_players(get_tree()):
		if node is Player:
			players.append(node as Player)
	return players


func _living_enemies() -> Array[Enemy]:
	var living: Array[Enemy] = []
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dead():
			living.append(enemy)
	return living


func _show_banner(title: String, subtitle: String, color: Color) -> void:
	if context != null and context.ui != null and is_instance_valid(context.ui):
		context.ui.show_banner(title, subtitle, color)


# --- Look ---

func _build() -> void:
	var base := Player.FEET_OFFSET
	DropShadow.attach(self, 18.0, base.y - 2.0)
	_sprite = VariantArt.make_animated(VariantArt.WAGER_ALTAR, true)
	_sprite.name = "Sprite"
	_sprite.position = base
	add_child(_sprite)
	_sprite.play(&"default")
	_light = LightSource.new()
	_light.name = "Light"
	_light.radius = LIGHT_RADIUS
	_light.intensity = 0.7
	_light.flicker = 0.06
	_light.position = Vector2(0, -36)
	add_child(_light)
	var blocker := StaticBody2D.new()
	blocker.name = "Blocker"
	blocker.collision_layer = PhysicsLayers.WORLD
	blocker.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = FOOTPRINT
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = base - Vector2(0, FOOTPRINT.y * 0.5)
	blocker.add_child(collision)
	add_child(blocker)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt = DungeonTexts.t(&"WAGER_PROMPT")
	var area := CircleShape2D.new()
	area.radius = INTERACT_RADIUS
	var area_shape := CollisionShape2D.new()
	area_shape.shape = area
	_interactable.add_child(area_shape)
	_interactable.interacted.connect(_on_interacted)
	add_child(_interactable)
	var icon := VariantArt.make_sprite(VariantArt.WAGER_ICONS, WagerRules.icon_index(condition))
	icon.name = "Icon"
	icon.position = Vector2(0, -92)
	icon.z_index = 30
	icon.modulate = LOST_COLOR.lightened(0.3) if WagerRules.is_curse(condition) else COLOR
	add_child(icon)
	_add_caption(WagerRules.get_condition_name(condition), Vector2(0, -128), 15, COLOR)
	_add_caption(WagerRules.get_condition_rule(condition), Vector2(0, -112), 12, Color(0.9, 0.88, 0.95))
	_add_caption(DungeonTexts.t(&"WAGER_REWARD", [WagerRules.get_reward(condition)]), Vector2(0, -64), 12, WON_COLOR)


func _add_caption(text: String, offset_position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = "Caption%d" % get_child_count()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.size = Vector2(240, 20)
	label.position = offset_position - Vector2(120, 10)
	label.z_index = 30
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _update_look() -> void:
	if _sprite == null:
		return
	match state:
		State.ACCEPTED:
			_sprite.modulate = Color(1.15, 1.05, 1.25)
			_light.radius = LIGHT_RADIUS * 1.3
			_light.intensity = 1.0
		State.WON:
			_sprite.modulate = Color(1.2, 1.1, 0.8)
		State.DECLINED, State.LOST:
			_sprite.modulate = Color(0.55, 0.55, 0.65)
			_light.intensity = 0.3
	for child in get_children():
		if child is Label and state in [State.DECLINED, State.LOST]:
			(child as Label).modulate.a = 0.4
