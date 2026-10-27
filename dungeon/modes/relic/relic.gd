class_name Relic
extends Node2D
## The relic of "Reliquie holen" (RAEUME §3.5, R4b): a banner (crypt), lantern (grotto,
## shadow realm) or skull (ember forge) that lies at the far end of the room. E takes it, E puts it
## down; put down at the altar (or carried into its reach and E) it lies on the altar for good. The
## carrier is slower and cannot attack, dash stays (LanternCarry, state at the player). A hit that
## gets through drops it at the carrier's feet (co-op: hand it over by putting it down).
## Decisions are functions that emit signals (pick_up, drop, place, send_home); RelicMode follows
## them. It follows its carrier every frame and falls where the carrier goes down or into an abyss.

signal picked_up(relic: Relic, player: Player)
signal dropped(relic: Relic, player: Player, by_hit: bool)
signal placed(relic: Relic, player: Player)

enum State { LYING, CARRIED, PLACED }

const ART_DIR := "res://art/environment/objectives/"
## Relic art per biome (objectives.json: 16x24, pivot 8,23).
const BIOME_ART := {
	&"crypt": "relic_banner",
	&"slime_grotto": "relic_lantern",
	&"shadow_realm": "relic_lantern",
	&"ember_forge": "relic_skull",
}
const FRAME := Vector2i(16, 24)
const PIVOT := Vector2(8, 23)
const INTERACT_RADIUS := 40.0
## In the hand: beside the carrier's body, a little above the feet line so it draws over the body.
const HAND_OFFSET := Vector2(16.0, 4.0)
const LIGHT_HEIGHT := -26.0
const RETURN_TIME := 1.2
const COLOR := Color("#f2cf4a")
const BOB := 3.0

var state := State.LYING
var carrier: Player = null
## Altar the relic belongs to (set by the mode).
var altar: RelicAltar = null
## Where it lay at the start (it waits there until it is lifted).
var home := Vector2.ZERO

var _sprite: Sprite2D = null
var _light: LightSource = null
var _interactable: Interactable = null
var _clock := 0.0


## Builds the children; call once before or after entering the tree. biome_id picks the look.
func build(biome_id: StringName) -> void:
	DropShadow.attach(self, 8.0, -2.0)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = get_texture(String(BIOME_ART.get(biome_id, "relic_banner")))
	_sprite.centered = false
	_sprite.offset = -PIVOT
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	add_child(_sprite)
	_light = LightSource.new()
	_light.name = "Light"
	_light.radius = RelicRules.LIGHT_RADIUS
	_light.intensity = 0.9
	_light.flicker = 0.04
	_light.position = Vector2(0.0, LIGHT_HEIGHT)
	_light.ground_offset = Vector2(0.0, -LIGHT_HEIGHT)
	add_child(_light)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	var shape := CircleShape2D.new()
	shape.radius = INTERACT_RADIUS
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0.0, -12.0)
	_interactable.add_child(collision)
	add_child(_interactable)
	_interactable.interacted.connect(_on_interacted)
	home = position
	_update_prompt()


func get_interactable() -> Interactable:
	return _interactable


func get_light() -> LightSource:
	return _light


func is_carried() -> bool:
	return state == State.CARRIED


func is_placed() -> bool:
	return state == State.PLACED


# --- Decisions ---

## A living player takes the relic from the floor.
func pick_up(player: Player) -> bool:
	if state != State.LYING or player == null or not EnemyTargeting.is_alive(player) or LanternCarry.is_carrying(player):
		return false
	state = State.CARRIED
	carrier = player
	LanternCarry.attach(player, self)
	if not player.hurtbox.hit_received.is_connected(_on_carrier_hit):
		player.hurtbox.hit_received.connect(_on_carrier_hit)
	_light.radius = RelicRules.CARRIED_LIGHT_RADIUS
	z_index = 2
	_follow_carrier()
	_update_prompt()
	picked_up.emit(self, player)
	if is_inside_tree():
		Sfx.play_at(self, &"relic_pickup", global_position, -6.0)
	return true


## The carrier sets the relic down at its feet - onto the altar when it is close enough. by_hit: a
## hit knocked it out of the hands.
func drop(at_global := Vector2.INF, by_hit := false) -> bool:
	if state != State.CARRIED:
		return false
	var player: Player = carrier if carrier != null and is_instance_valid(carrier) else null
	_release_carrier()
	if at_global != Vector2.INF:
		global_position = at_global
	state = State.LYING
	_light.radius = RelicRules.LIGHT_RADIUS
	z_index = 0
	_update_prompt()
	dropped.emit(self, player, by_hit)
	if not by_hit and altar != null and RelicRules.can_place(global_position.distance_to(altar.global_position)):
		place(player)
	return true


## Onto the altar (by a player, or player = null when it came home by itself). The decision is made
## at once; with fly the relic is only seen floating there (RETURN_TIME).
func place(player: Player, fly := false) -> bool:
	if state == State.PLACED or altar == null:
		return false
	if state == State.CARRIED:
		_release_carrier()
	state = State.PLACED
	_interactable.enabled = false
	z_index = 0
	var slot := altar.take_slot()
	if fly and is_inside_tree():
		var tween := create_tween()
		tween.tween_property(self, "global_position", slot, RETURN_TIME).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(_settle_on_altar)
	else:
		global_position = slot
		_settle_on_altar()
	placed.emit(self, player)
	return true


## Time is up: the relic leaves its carrier or the floor and floats home onto the altar.
func send_home() -> bool:
	return place(null, true)


# --- Internals ---

## Leaving the tree while carried (room unloaded, run over): the carrier is free again.
func _exit_tree() -> void:
	if state == State.CARRIED:
		_release_carrier()
		state = State.LYING


func _physics_process(delta: float) -> void:
	_clock += delta
	if state == State.LYING and _sprite != null:
		# Lying relics float a little, so they read as the goal from far away.
		_sprite.position.y = -absf(sin(_clock * 2.4)) * BOB
	if state != State.CARRIED:
		return
	if carrier == null or not is_instance_valid(carrier) or not carrier.is_alive():
		# Carrier down (co-op) or gone: the relic falls where it stood.
		drop(global_position, true)
		return
	if carrier.is_falling():
		# Into an abyss: the relic stays at the rim (the carrier's last safe spot).
		drop(carrier.get_last_safe_position(), true)
		return
	_follow_carrier()
	_update_prompt()


func _follow_carrier() -> void:
	if carrier == null or not is_instance_valid(carrier):
		return
	var side := -1.0 if carrier.get_aim_direction().x < 0.0 else 1.0
	global_position = carrier.global_position + Vector2(HAND_OFFSET.x * side, HAND_OFFSET.y)
	# Under the rock of a passage the carrier is hidden; the relic in hand (z 2) goes with them.
	visible = not DoorView.is_in_tunnel(get_tree(), carrier.global_position)
	if _sprite != null:
		_sprite.position.y = 0.0


func _release_carrier() -> void:
	visible = true
	if carrier != null and is_instance_valid(carrier):
		LanternCarry.detach(carrier)
		if carrier.hurtbox.hit_received.is_connected(_on_carrier_hit):
			carrier.hurtbox.hit_received.disconnect(_on_carrier_hit)
	carrier = null


## A hit that gets through knocks the relic out of the hands (KONZEPT: "Bei Treffer fällt sie hin").
func _on_carrier_hit(result: DamageResult, _damage: DamageData) -> void:
	if state != State.CARRIED or result == null or not result.is_effective():
		return
	var feet := carrier.get_feet_position() if carrier != null and is_instance_valid(carrier) else global_position
	drop.call_deferred(feet, true)


## On the altar the relic is part of the altar's look.
func _settle_on_altar() -> void:
	visible = false
	if altar != null and is_instance_valid(altar):
		altar.add_relic(_sprite.texture if _sprite != null else null)
	if is_inside_tree():
		Sfx.play_at(self, &"relic_place", global_position, -4.0)


func _on_interacted(player: Player) -> void:
	match state:
		State.LYING:
			pick_up(player)
		State.CARRIED:
			# Only the carrier puts it down (co-op: nobody snatches it).
			if player == carrier:
				drop(carrier.get_feet_position())


func _update_prompt() -> void:
	if _interactable == null:
		return
	var key := &"MODE_RELIC_TAKE"
	if state == State.CARRIED:
		var near_altar := altar != null and RelicRules.can_place(global_position.distance_to(altar.global_position))
		key = &"MODE_RELIC_PLACE" if near_altar else &"MODE_RELIC_DROP"
	var text := DungeonTexts.t(key)
	if _interactable.prompt != text:
		_interactable.prompt = text


## Texture of an objective art file, a drawn placeholder while it is missing.
static func get_texture(art_name: String) -> Texture2D:
	var path := ART_DIR + art_name + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var image := Image.create(FRAME.x, FRAME.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(4, 23):
		image.set_pixel(7, y, Color("#6b5a3a"))
		image.set_pixel(8, y, Color("#6b5a3a"))
	for y in range(4, 12):
		for x in range(9, 15):
			image.set_pixel(x, y, COLOR)
	return ImageTexture.create_from_image(image)
