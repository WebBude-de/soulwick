class_name SoulLantern
extends Node2D
## The soul lantern of the variant "Laternenträger" (KONZEPT_RAEUME §4.4, A9). Lies on the floor,
## is carried by one player (E to take, E to put down) or stands in the socket at the exit. Its
## light counts for LightQuery and grows in the hand (the carrier sees much farther). Carrying is
## state at the player (LanternCarry: slower, no attacks, dash allowed).
## Decisions are functions that emit signals (pick_up, put_down, insert, send_home); the variant
## follows them. The lantern follows its carrier every frame and falls to the floor when the
## carrier goes down or drops into an abyss (at the carrier's last safe spot).

signal picked_up(lantern: SoulLantern, player: Player)
signal put_down(lantern: SoulLantern, player: Player)
signal inserted(lantern: SoulLantern, player: Player)

enum State { LYING, CARRIED, SOCKETED }

const INTERACT_RADIUS := 34.0
## In the hand: beside the carrier's body, a little above the feet line so it draws over the body.
const HAND_OFFSET := Vector2(14.0, 2.0)
const LIGHT_HEIGHT := -22.0
const RETURN_TIME := 1.2
const COLOR := Color("#ffd166")

var state := State.LYING
var carrier: Player = null
## Socket the lantern belongs to (set by the variant).
var socket: LanternSocket = null

var _sprite: AnimatedSprite2D = null
var _light: LightSource = null
var _interactable: Interactable = null


## Builds the children; call once before or after entering the tree.
func build() -> void:
	DropShadow.attach(self, 8.0, -2.0)
	_sprite = VariantArt.make_animated(VariantArt.SOUL_LANTERN, true)
	_sprite.name = "Sprite"
	add_child(_sprite)
	_sprite.play()
	_light = LightSource.new()
	_light.name = "Light"
	_light.radius = LightVariantRules.LANTERN_LIGHT_RADIUS
	_light.intensity = 1.0
	_light.flicker = 0.05
	_light.position = Vector2(0.0, LIGHT_HEIGHT)
	_light.ground_offset = Vector2(0.0, -LIGHT_HEIGHT)
	_light.counts_as_light = true
	add_child(_light)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	var shape := CircleShape2D.new()
	shape.radius = INTERACT_RADIUS
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0.0, -10.0)
	_interactable.add_child(collision)
	add_child(_interactable)
	_interactable.interacted.connect(_on_interacted)
	_update_prompt()


func get_interactable() -> Interactable:
	return _interactable


func get_light() -> LightSource:
	return _light


func is_carried() -> bool:
	return state == State.CARRIED


func is_socketed() -> bool:
	return state == State.SOCKETED


# --- Decisions ---

## A living player takes the lantern from the floor.
func pick_up(player: Player) -> bool:
	if state != State.LYING or player == null or not EnemyTargeting.is_alive(player) or LanternCarry.is_carrying(player):
		return false
	state = State.CARRIED
	carrier = player
	LanternCarry.attach(player, self)
	_light.radius = LightVariantRules.LANTERN_CARRIED_RADIUS
	z_index = 2
	_follow_carrier()
	_update_prompt()
	picked_up.emit(self, player)
	if is_inside_tree():
		Sfx.play_at(self, &"heal", global_position, -8.0)
	return true


## The carrier sets the lantern down at its feet - into the socket when it is close enough.
func drop(at_global := Vector2.INF) -> bool:
	if state != State.CARRIED:
		return false
	var player: Player = carrier if carrier != null and is_instance_valid(carrier) else null
	_release_carrier()
	if at_global != Vector2.INF:
		global_position = at_global
	state = State.LYING
	_light.radius = LightVariantRules.LANTERN_LIGHT_RADIUS
	z_index = 0
	_update_prompt()
	put_down.emit(self, player)
	if socket != null and LightVariantRules.can_insert(global_position.distance_to(socket.global_position)):
		insert(player)
	return true


## Into the socket (by a player, or player = null when it came home by itself). The decision is
## made at once; with fly the lantern is only seen floating there (RETURN_TIME).
func insert(player: Player, fly := false) -> bool:
	if state == State.SOCKETED or socket == null:
		return false
	if state == State.CARRIED:
		_release_carrier()
	state = State.SOCKETED
	_interactable.enabled = false
	_light.radius = LightVariantRules.LANTERN_LIGHT_RADIUS
	z_index = 0
	if fly and is_inside_tree():
		var tween := create_tween()
		tween.tween_property(self, "global_position", socket.global_position, RETURN_TIME).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(_settle_in_socket)
	else:
		global_position = socket.global_position
		_settle_in_socket()
	inserted.emit(self, player)
	return true


## Time is up: the lantern leaves its carrier or the floor and floats home into the socket.
func send_home() -> bool:
	return insert(null, true)


# --- Internals ---

## Leaving the tree while carried (room unloaded, run over): the carrier is free again.
func _exit_tree() -> void:
	if state == State.CARRIED:
		_release_carrier()
		state = State.LYING


func _physics_process(_delta: float) -> void:
	if state != State.CARRIED:
		return
	if carrier == null or not is_instance_valid(carrier) or not carrier.is_alive():
		# Carrier down (co-op) or gone: the lantern falls where it stood.
		drop(global_position)
		return
	if carrier.is_falling():
		# Into an abyss: the lantern stays at the rim (the carrier's last safe spot).
		drop(carrier.get_last_safe_position())
		return
	_follow_carrier()
	_update_prompt()


func _follow_carrier() -> void:
	if carrier == null or not is_instance_valid(carrier):
		return
	var side := -1.0 if carrier.get_aim_direction().x < 0.0 else 1.0
	global_position = carrier.global_position + Vector2(HAND_OFFSET.x * side, HAND_OFFSET.y)


func _release_carrier() -> void:
	if carrier != null and is_instance_valid(carrier):
		LanternCarry.detach(carrier)
	carrier = null


## Look of a lantern in its socket: the lantern itself disappears, the socket lights up.
func _settle_in_socket() -> void:
	visible = false
	_light.visible = false
	if socket != null and is_instance_valid(socket):
		socket.set_lit(true)


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
	var key := &"VARIANT_LANTERN_TAKE"
	if state == State.CARRIED:
		var near_socket := socket != null and LightVariantRules.can_insert(global_position.distance_to(socket.global_position))
		key = &"VARIANT_LANTERN_INSERT" if near_socket else &"VARIANT_LANTERN_DROP"
	var text := DungeonTexts.t(key)
	if _interactable.prompt != text:
		_interactable.prompt = text
