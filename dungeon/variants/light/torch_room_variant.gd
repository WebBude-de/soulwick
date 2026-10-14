class_name TorchRoomVariant
extends CombatVariant
## Variant "Fackelraum" (KONZEPT_RAEUME §4.7, A9; shadow realm only): the room is dark except for
## the light circle - the wall torches are out. 4-6 unlit torch stands stand in the room; a hit or
## E lights one for good (RoomTorch). Every burning torch lights its circle and widens the players'
## light circle (LightVariantRules.torch_vision_factor). Enemies inside the light of a burning torch
## deal less damage (TORCH_DAMAGE_FACTOR). All torches burning -> bonus chest; the room itself is
## done as always when every enemy is beaten.
## The damage rule is applied without touching enemy_base: an enemy in torchlight gets a copy of its
## data with less damage, and its own data back when it leaves the light (one copy per enemy type).

const DIM_META := &"torch_room_original_data"
const TINT := Color("#c9a6ff")

var torches: Array[RoomTorch] = []

var _vision_radius := -1.0
## Original data -> copy with torchlight damage.
var _dim_copies: Dictionary[EnemyData, EnemyData] = {}


func can_host() -> bool:
	return _candidates().size() >= LightVariantRules.TORCH_COUNT.x


func _on_attach() -> void:
	var candidates := _candidates()
	var count := LightVariantRules.torch_count(_rng.randf(), candidates.size())
	var tiles := VariantSpots.pick_spread(candidates, count, LightVariantRules.TORCH_MIN_TILE_DISTANCE, _rng)
	if tiles.size() < LightVariantRules.TORCH_COUNT.x:
		tiles = VariantSpots.pick_spread(candidates, count, LightVariantRules.TORCH_MIN_TILE_DISTANCE * 0.5, _rng)
	for tile in tiles:
		_free.erase(tile)
		var torch := RoomTorch.new()
		torch.name = "RoomTorch%d" % torches.size()
		torch.position = RoomTiles.tile_center(tile) + Vector2(0, RoomTiles.TILE_WORLD * 0.25)
		torch.build(TINT)
		add_child(torch)
		torch.ignited.connect(_on_torch_ignited)
		torches.append(torch)


func _on_start() -> void:
	_darken_room()


func _physics_process(_delta: float) -> void:
	if _started and not _finished:
		update_enemy_damage()


func get_lit_count() -> int:
	var count := 0
	for torch in torches:
		if torch.lit:
			count += 1
	return count


## Circles of the burning torches (the light that weakens enemies).
func get_torch_circles() -> Array[Vector3]:
	var circles: Array[Vector3] = []
	for torch in torches:
		if torch.lit:
			circles.append(torch.get_light_circle())
	return circles


## Is an enemy in torchlight? Same circle test as every light (LightQuery).
func is_in_torchlight(enemy: Enemy) -> bool:
	return enemy != null and is_instance_valid(enemy) and LightQuery.is_in_circles(enemy.global_position, get_torch_circles())


## Applies the torchlight damage rule to every living enemy (public for tests and tools).
func update_enemy_damage() -> void:
	var circles := get_torch_circles()
	for enemy in get_living_enemies():
		set_dimmed(enemy, not circles.is_empty() and LightQuery.is_in_circles(enemy.global_position, circles))


## Gives the enemy the torchlight copy of its data (dimmed) or its own data back.
func set_dimmed(enemy: Enemy, dimmed: bool) -> void:
	if enemy == null or enemy.data == null:
		return
	var is_dimmed := enemy.has_meta(DIM_META)
	if dimmed == is_dimmed:
		return
	if dimmed:
		var original := enemy.data
		enemy.set_meta(DIM_META, original)
		enemy.data = _dim_copy(original)
	else:
		var original := enemy.get_meta(DIM_META) as EnemyData
		enemy.remove_meta(DIM_META)
		if original != null:
			enemy.data = original


func is_dimmed(enemy: Enemy) -> bool:
	return enemy != null and enemy.has_meta(DIM_META)


func _dim_copy(original: EnemyData) -> EnemyData:
	if not _dim_copies.has(original):
		var copy := original.duplicate() as EnemyData
		copy.damage = original.damage * LightVariantRules.enemy_damage_factor(true)
		_dim_copies[original] = copy
	return _dim_copies[original]


func _is_bonus_met() -> bool:
	return LightVariantRules.torches_complete(get_lit_count(), torches.size())


func _on_finish() -> void:
	# The room is done: nobody fights in the light any more, every enemy keeps its own data.
	for enemy in get_living_enemies():
		set_dimmed(enemy, false)
	if bonus == Bonus.ACHIEVED:
		var centre := room.content_anchor.position if room.content_anchor != null else Vector2(room.tiles.room_size) * RoomTiles.TILE_WORLD * 0.5
		spawn_bonus_chests(centre)
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


func _on_torch_ignited(_torch: RoomTorch, _by: Node) -> void:
	var lit := get_lit_count()
	_apply_vision()
	if LightVariantRules.torches_complete(lit, torches.size()):
		if set_bonus(true):
			show_banner(DungeonTexts.t(&"VARIANT_TORCHES_ALL"), DungeonTexts.t(&"VARIANT_TORCHES_ALL_SUB"), BONUS_COLOR)
	elif _started:
		show_banner(DungeonTexts.t(&"VARIANT_TORCH_LIT"), DungeonTexts.t(&"VARIANT_TORCH_LIT_SUB", [torches.size() - lit]))


## Dark room: the wall torches go out, the light circle shrinks to what the torches allow.
func _darken_room() -> void:
	var props := room.get_node_or_null("Props")
	if props != null:
		for prop in props.get_children():
			if prop is Node2D and String(prop.name).begins_with("Torch"):
				(prop as Node2D).visible = false
	_vision_radius = RoomVariants.room_vision_radius(room)
	_apply_vision()


func _apply_vision() -> void:
	if _vision_radius < 0.0 or not is_inside_tree():
		return
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null:
		var factor := LightVariantRules.torch_vision_factor(get_lit_count(), torches.size())
		overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, _vision_radius * factor)


## Free tiles away from both doors.
func _candidates() -> Array[Vector2i]:
	var doors: Array[Vector2i] = [room.tiles.get_entrance_inside_tile(), room.tiles.get_exit_inside_tile()]
	var result: Array[Vector2i] = []
	for tile: Vector2i in VariantSpots.sorted_tiles(_free):
		if VariantSpots.is_clear_of(tile, doors, LightVariantRules.TORCH_DOOR_CLEARANCE):
			result.append(tile)
	return result
