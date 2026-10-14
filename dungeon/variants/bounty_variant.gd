class_name BountyVariant
extends CombatVariant
## Variant "Kopfgeld" (KONZEPT_RAEUME §4.6): one enemy of the first wave wears a gold crown
## (BountyFlight). Once it sees a player it flees to an escape hole that opens over
## BOUNTY_CATCH_TIME seconds. Caught (killed) in time -> bonus chest; escaped -> it is gone, no
## bonus, the room is completed as usual. Works with every room shape.

const HOLE_Z := -1

var bounty: Enemy = null
var flight: BountyFlight = null

var _hole: AnimatedSprite2D = null
var _caught_at := Vector2.ZERO


func _on_start() -> void:
	bounty = _choose_bounty(get_living_enemies())
	if bounty == null:
		# Nobody to crown (should not happen): the room is a plain fight, no bonus.
		set_bonus(false)
		return
	flight = BountyFlight.attach(bounty)
	flight.spotted.connect(_on_spotted)
	flight.escaped.connect(_on_escaped)
	bounty.died.connect(_on_bounty_died)


func _physics_process(_delta: float) -> void:
	_update_hole()


func get_hole() -> AnimatedSprite2D:
	return _hole


## The crowned one: preferably a plain (no elite) enemy, drawn with the variant RNG.
func _choose_bounty(enemies: Array[Enemy]) -> Enemy:
	var plain: Array[Enemy] = []
	for enemy in enemies:
		if enemy.elite == Enemy.Elite.NONE and not enemy.data.is_boss:
			plain.append(enemy)
	var pool := plain if not plain.is_empty() else enemies
	if pool.is_empty():
		return null
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _on_spotted(_flight: BountyFlight) -> void:
	var origin := RoomTiles.local_to_tile(room.to_local(bounty.global_position))
	var away := get_player_tiles()
	away.append(room.tiles.get_entrance_inside_tile())
	away.append(room.tiles.get_exit_inside_tile())
	var tile := VariantSpots.far_tile(_free, origin, VariantRules.BOUNTY_HOLE_MIN_TILES, away, VariantRules.BOUNTY_HOLE_PLAYER_TILES, _rng)
	var local := RoomTiles.tile_center(tile) if tile != VariantSpots.INVALID else room.to_local(bounty.global_position)
	flight.hole_position = room.to_global(local)
	_hole = VariantArt.make_animated(VariantArt.ESCAPE_HOLE, false)
	_hole.name = "EscapeHole"
	_hole.z_index = HOLE_Z
	_hole.position = local + Vector2(0, 8)
	_hole.stop()
	_hole.frame = 0
	add_child(_hole)
	show_banner(DungeonTexts.t(&"VARIANT_BOUNTY_SPOTTED"), DungeonTexts.t(&"VARIANT_BOUNTY_SPOTTED_SUB", [roundi(VariantRules.BOUNTY_CATCH_TIME)]), BONUS_COLOR)
	if is_inside_tree():
		Sfx.play_at(self, &"bounty_hole", flight.hole_position, -6.0)


## The hole opens frame by frame with the remaining time.
func _update_hole() -> void:
	if _hole == null or not is_instance_valid(_hole) or flight == null or not is_instance_valid(flight):
		return
	if not flight.is_fleeing():
		return
	var count := VariantArt.get_frame_count(VariantArt.ESCAPE_HOLE)
	_hole.frame = mini(count - 1, floori(flight.get_hole_progress() * count))


## Escaped: the enemy leaves the room without a death (no gold, no kill) - the room counts it as
## gone through its died signal, so the room still completes as usual.
func _on_escaped(_flight: BountyFlight) -> void:
	set_bonus(false)
	if is_instance_valid(bounty) and not bounty.is_dead():
		bounty.gold_drop = 0
		bounty.hurtbox.set_deferred("monitorable", false)
		bounty.visible = false
		bounty.died.emit(bounty)
		bounty.queue_free()
	_close_hole()
	show_banner(DungeonTexts.t(&"VARIANT_BOUNTY_ESCAPED"), DungeonTexts.t(&"VARIANT_BOUNTY_ESCAPED_SUB"), LOST_COLOR)
	if is_inside_tree() and flight != null:
		Burst.spawn(self, flight.hole_position, Color(0.2, 0.15, 0.3), 14, 90.0)
		Sfx.play_at(self, &"bounty_escape", flight.hole_position, -6.0)


func _on_bounty_died(enemy: Enemy) -> void:
	if flight == null or flight.is_escaped():
		return
	_caught_at = room.to_local(enemy.global_position)
	if set_bonus(true):
		show_banner(DungeonTexts.t(&"VARIANT_BOUNTY_CAUGHT"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)
	_close_hole()


func _close_hole() -> void:
	if _hole == null or not is_instance_valid(_hole) or not is_inside_tree():
		return
	var hole := _hole
	var tween := hole.create_tween()
	tween.tween_property(hole, "modulate:a", 0.0, 0.6)
	tween.tween_callback(hole.queue_free)


func _is_bonus_met() -> bool:
	return false


func _on_finish() -> void:
	if bonus == Bonus.ACHIEVED:
		spawn_bonus_chests(_caught_at)
