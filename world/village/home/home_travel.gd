class_name HomeTravel
extends RefCounted
## The way into the home and back (KE8, KONZEPT §6): the home's door in the village opens (second
## state of the building, home_door_open.png) and the WorldController loads the interior as its own
## world; the door out loads the village again and puts the players back in front of the home's
## door, where they went in. Uses the WorldController's public load_world, so no hotspot changes.
## Koop-Check (KE8): the home is entered alone only; in a session with more than one player
## (quick game, guild run, local group) the door does not change the world but shows the talent tree
## read-only (VillageBuildings.enter_home), guests never respec. Talents stay account state.

const HOME_SCENE_PATH := "res://world/village/home/home.tscn"
## The home building in the village (village.tscn) and its door.
const HOME_NODE := ^"Buildings/Home"
const DOOR_NODE := ^"Door"
## TESTWERT: a player leaving the home stands this far in front of the door's use point (world px):
## just outside the door's use range (door circle 32 + player's interaction area 44), so the first
## step outside does not show "Eintreten" again (FS4: a newcomer pressing E twice went straight back in).
const DOOR_STEP := Vector2(0, 80)
## TESTWERT: the open door shows this long before the interior loads, and after leaving (s).
const DOOR_OPEN_TIME := 0.25
const DOOR_CLOSE_DELAY := 0.6

## Where the players come back to in the village (Vector2.INF: the village's own spawn).
static var return_point := Vector2.INF
## A world change is on its way (a second E does nothing).
static var _travelling := false


## True when this session may go inside alone (solo only, KE8 Koop-Check).
static func can_enter(node: Node) -> bool:
	return not GameMode.of(node).is_multiplayer()


static func find_controller(node: Node) -> WorldController:
	if node == null or not node.is_inside_tree():
		return null
	for owner_node in node.get_tree().get_nodes_in_group(GameMode.OWNER_GROUP):
		if owner_node is WorldController:
			return owner_node as WorldController
	return null


static func home_scene() -> PackedScene:
	return load(HOME_SCENE_PATH) as PackedScene


static func is_travelling() -> bool:
	return _travelling


## Goes from the village into the home: opens the door, remembers the way back and loads the
## interior. False (nothing happens) in a group session or without a WorldController.
static func enter(village: Node) -> bool:
	if _travelling or not can_enter(village):
		return false
	var controller := find_controller(village)
	if controller == null:
		return false
	var home := village.get_node_or_null(HOME_NODE) as Node2D
	return_point = door_point(home) + DOOR_STEP if home != null else Vector2.INF
	VillageBuildings.set_home_door_open(home, true)
	_travelling = true
	await village.get_tree().create_timer(DOOR_OPEN_TIME).timeout
	_travelling = false
	if not is_instance_valid(controller) or not controller.is_inside_tree():
		return false
	controller.load_world(home_scene())
	return true


## Goes from the home back to the village and puts the players in front of the home's door.
static func leave(from: Node) -> bool:
	if _travelling:
		return false
	var controller := find_controller(from)
	if controller == null or controller.village_scene == null:
		return false
	_travelling = true
	_arrive.call_deferred(controller)
	return true


static func _arrive(controller: WorldController) -> void:
	_travelling = false
	if not is_instance_valid(controller):
		return
	controller.load_world(controller.village_scene)
	var village := controller.get_world()
	var home := village.get_node_or_null(HOME_NODE) as Node2D if village != null else null
	if return_point.is_finite():
		place_players(controller.get_players(), return_point)
	if home != null:
		VillageBuildings.set_home_door_open(home, true)
		var tween := home.create_tween()
		tween.tween_interval(DOOR_CLOSE_DELAY)
		tween.tween_callback(func() -> void: VillageBuildings.set_home_door_open(home, false))


## Players stand around point like at a spawn marker (WorldController offsets), cameras jump along.
static func place_players(players: Array[Player], point: Vector2) -> void:
	for index in players.size():
		var player := players[index]
		if player == null or not is_instance_valid(player):
			continue
		player.global_position = point + WorldController.get_spawn_offset(index)
		var camera := player.get_node_or_null(^"Camera2D") as Camera2D
		if camera != null:
			if camera.has_method(&"snap_to_targets"):
				camera.call(&"snap_to_targets")
			camera.reset_smoothing()


## Use point of the home's door (global), the building's origin without a door.
static func door_point(home: Node2D) -> Vector2:
	var door := home.get_node_or_null(DOOR_NODE) as Node2D
	return door.global_position if door != null else home.global_position


## Forgets the way back (tests).
static func reset() -> void:
	return_point = Vector2.INF
	_travelling = false
