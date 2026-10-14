class_name WorldCaption
extends RefCounted
## World captions ("Brunnen", "Händler", "Pakt-Altar", the wager rule …) share the screen with the
## banners (07_ui.md, R3): a caption shows only while a player stands near it and never while a
## banner is on screen; it fades in and out (self_modulate, so the owner may still use visible and
## modulate). DungeonUI drives them (update_all); the rooms only create the labels.
## Captions are found by themselves: labels under a SpecialContent (add_caption) and labels named
## "Caption…" under a Node2D (wager altar). Other world labels can join with mark().

const GROUP: StringName = &"world_caption"
## A caption shows while a player is at most this far from its centre (world px; one tile is 64).
## TESTWERT
const NEAR_DISTANCE := 230.0
## Fade speed (alpha per second).
const FADE_SPEED := 5.0


## Lets label take part (near-only, never together with a banner).
static func mark(label: CanvasItem) -> void:
	if label != null and not label.is_in_group(GROUP):
		label.add_to_group(GROUP)


## Takes node in when it is a world caption (see class doc). Returns true when it was taken.
static func adopt(node: Node) -> bool:
	var label := node as Label
	if label == null or label is DamageNumber:
		return false
	var parent := label.get_parent()
	if parent == null or not parent is Node2D:
		return false
	if parent is SpecialContent or String(label.name).begins_with("Caption"):
		mark(label)
		label.self_modulate.a = 0.0
		return true
	return false


## World position of a caption's centre.
static func get_center(caption: CanvasItem) -> Vector2:
	var control := caption as Control
	if control != null:
		return control.get_global_transform() * (control.size * 0.5)
	return (caption as Node2D).global_position if caption is Node2D else Vector2.ZERO


static func is_near(center: Vector2, player_positions: Array[Vector2]) -> bool:
	for position in player_positions:
		if center.distance_to(position) <= NEAR_DISTANCE:
			return true
	return false


## Fades every caption in tree towards its target: shown when near a player and no banner is up.
## Returns how many captions are (becoming) visible.
static func update_all(tree: SceneTree, banner_up: bool, player_positions: Array[Vector2], delta: float) -> int:
	var shown := 0
	for node in tree.get_nodes_in_group(GROUP):
		var caption := node as CanvasItem
		if caption == null or not caption.is_inside_tree():
			continue
		var want := not banner_up and is_near(get_center(caption), player_positions)
		var target := 1.0 if want else 0.0
		caption.self_modulate.a = move_toward(caption.self_modulate.a, target, FADE_SPEED * delta)
		if want:
			shown += 1
	return shown
