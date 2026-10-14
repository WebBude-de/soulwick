class_name GravediggerVariant
extends CombatVariant
## Variant "Totengräber" (KONZEPT_RAEUME §4.5, crypt only): a beaten skeleton leaves a bone heap.
## Destroyed within RISE_TIME s (walking over it, dashing through, any hit) it is gone for good;
## otherwise the skeleton stands up again with RISE_HEALTH_SHARE of its health - at most once. Its
## gold drops only on the final death (the heap carries it, the risen skeleton keeps it).
## How it works without touching enemy_base: skeletons of the room get a copy of their data whose
## death spawn is the bone heap (enemies/data/bone_heap.tres), so the heap arrives through the
## room's normal death-spawn tracking and keeps the room shut while it lies there. A heap that
## rises turns back into the skeleton (same node, original data). Skeletons are more frequent in
## this room (VariantEncounterGroup).

const BONE_HEAP: EnemyData = preload("res://enemies/data/bone_heap.tres")
const ORIGINAL_META := &"gravedigger_original_data"
const GOLD_META := &"gravedigger_gold"
const HEAP_COLOR := Color(0.85, 0.82, 0.72)

signal heap_destroyed(heap: Enemy)
signal skeleton_rose(skeleton: Enemy)

## Living heaps: heap -> seconds it lies there.
var _heaps: Dictionary[Enemy, float] = {}
var _rising: Dictionary[Enemy, bool] = {}
## Collision of a heap before it became passable: heap -> [layer, mask].
var _collision: Dictionary[Enemy, Array] = {}
var _heap_data: EnemyData = null
var _risen := 0


func _on_attach() -> void:
	_heap_data = BONE_HEAP.duplicate() as EnemyData
	_heap_data.sprite_frames = VariantArt.make_bone_heap_frames()


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	var factors: Dictionary[StringName, float] = {}
	for id in VariantRules.RISING_IDS:
		factors[id] = VariantRules.RISING_WEIGHT_FACTOR
	return VariantEncounterGroup.wrap(group, self, 1.0, factors)


func get_heap_count() -> int:
	return get_heaps().size()


func get_heaps() -> Array[Enemy]:
	var heaps: Array[Enemy] = []
	for heap: Variant in _heaps.keys():
		if is_instance_valid(heap) and not (heap as Enemy).is_dead():
			heaps.append(heap)
	return heaps


func get_risen_count() -> int:
	return _risen


func is_heap(enemy: Enemy) -> bool:
	return enemy != null and enemy.data == _heap_data


func _is_bonus_met() -> bool:
	return _risen == 0 or not VariantRules.GRAVEDIGGER_BONUS_NEEDS_NO_RISE


func _on_finish() -> void:
	if bonus == Bonus.ACHIEVED:
		var centre := room.content_anchor.position if room.content_anchor != null else Vector2(room.tiles.room_size) * RoomTiles.TILE_WORLD * 0.5
		spawn_bonus_chests(centre)
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


# --- Skeletons and heaps entering the room ---

func _on_enemy_added(enemy: Enemy) -> void:
	if enemy.data == null:
		return
	if enemy.data == _heap_data:
		_heaps[enemy] = 0.0
		enemy.ready.connect(_on_heap_ready.bind(enemy), CONNECT_ONE_SHOT)
		return
	if not VariantRules.can_rise(enemy.data.id) or enemy.has_meta(ORIGINAL_META):
		return
	# Before its _ready: the skeleton leaves a heap when it dies; its gold waits for the final death.
	var original := enemy.data
	var copy := original.duplicate() as EnemyData
	copy.death_spawn = _heap_data
	copy.death_spawn_count = 1
	enemy.data = copy
	enemy.set_meta(ORIGINAL_META, original)
	enemy.set_meta(GOLD_META, enemy.gold_drop)
	enemy.gold_drop = 0
	enemy.summoned.connect(_on_heap_left.bind(enemy))
	# Pushed into an abyss (A4): no heap is left, so the gold drops right away (at the rim).
	if enemy.has_signal(&"fell_into_pit"):
		enemy.connect(&"fell_into_pit", _on_skeleton_fell)


func _on_skeleton_fell(skeleton: Enemy) -> void:
	if is_instance_valid(skeleton) and skeleton.has_meta(GOLD_META):
		skeleton.gold_drop = int(skeleton.get_meta(GOLD_META))


## The dying skeleton just created its heap (before the heap enters the tree).
func _on_heap_left(heap: Enemy, skeleton: Enemy) -> void:
	if heap == null or heap.data != _heap_data or not is_instance_valid(skeleton):
		return
	heap.set_meta(ORIGINAL_META, skeleton.get_meta(ORIGINAL_META))
	heap.gold_drop = int(skeleton.get_meta(GOLD_META, 0))


## After the heap's _ready: passable (walk over it) and destroyed by any hit.
func _on_heap_ready(heap: Enemy) -> void:
	if not is_instance_valid(heap):
		return
	_collision[heap] = [heap.collision_layer, heap.collision_mask]
	heap.collision_layer = 0
	heap.collision_mask = 0
	heap.hurtbox.hit_received.connect(_on_heap_hit.bind(heap))
	heap.died.connect(_on_heap_died)


# --- Rules over time ---

func _physics_process(delta: float) -> void:
	if not _finished:
		step(delta)


## Ages every heap, destroys stomped ones, raises the old ones (public for tests and tools).
func step(delta: float) -> void:
	var feet: Array[Vector2] = []
	for player in get_players():
		feet.append(player.get_feet_position())
	for heap in get_heaps():
		if heap.has_meta(&"gravedigger_risen"):
			continue
		var age: float = _heaps[heap] + delta
		_heaps[heap] = age
		if _is_stomped(heap, feet):
			destroy_heap(heap)
		elif VariantRules.should_rise(age):
			rise(heap)
		elif VariantRules.is_rising(age) and not _rising.has(heap):
			_begin_rise(heap)


## Decision: the heap is gone for good (its gold drops now).
func destroy_heap(heap: Enemy) -> bool:
	if not is_instance_valid(heap) or heap.is_dead() or heap.has_meta(&"gravedigger_risen"):
		return false
	heap.health.take_damage(INF)
	return true


## Decision: the skeleton stands up again with part of its health (same node, original data).
func rise(heap: Enemy) -> bool:
	if not is_instance_valid(heap) or heap.is_dead() or heap.has_meta(&"gravedigger_risen"):
		return false
	var original := heap.get_meta(ORIGINAL_META, null) as EnemyData
	if original == null:
		return false
	heap.set_meta(&"gravedigger_risen", true)
	_heaps.erase(heap)
	_rising.erase(heap)
	heap.data = original
	heap.apply_scaling(room.room_index, false)
	var maximum := heap.health.get_max_health()
	heap.health.take_damage(maximum - VariantRules.risen_health(maximum))
	var collision: Array = _collision.get(heap, [PhysicsLayers.ENEMIES, PhysicsLayers.WORLD | PhysicsLayers.PLAYER | PhysicsLayers.ENEMIES])
	heap.collision_layer = collision[0]
	heap.collision_mask = collision[1]
	_collision.erase(heap)
	heap.set_physics_process(true)
	_risen += 1
	skeleton_rose.emit(heap)
	if VariantRules.GRAVEDIGGER_BONUS_NEEDS_NO_RISE:
		set_bonus(false)
	if is_inside_tree():
		Burst.spawn(heap.get_parent(), heap.global_position, HEAP_COLOR, 16, 140.0)
		Sfx.play_at(self, &"slam", heap.global_position, -8.0)
		show_banner(DungeonTexts.t(&"VARIANT_GRAVEDIGGER_RISE"), "", LOST_COLOR)
	return true


func _begin_rise(heap: Enemy) -> void:
	_rising[heap] = true
	# The heap stops thinking; the bones visibly grow back together (readable warning, 1 s).
	heap.set_physics_process(false)
	var sprite := heap.get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null:
		return
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"rise"):
		sprite.speed_scale = 1.0
		sprite.play(&"rise")
	SpriteFx.flash(sprite, Color(1.0, 0.4, 0.3), VariantRules.RISE_ANIMATION_TIME)


func _is_stomped(heap: Enemy, feet: Array[Vector2]) -> bool:
	var base := heap.global_position + Player.FEET_OFFSET
	for point in feet:
		if VariantRules.is_stomped(point.distance_to(base)):
			return true
	return false


func _on_heap_hit(_result: DamageResult, _damage: DamageData, heap: Enemy) -> void:
	destroy_heap(heap)


func _on_heap_died(heap: Enemy) -> void:
	if heap.has_meta(&"gravedigger_risen"):
		return
	_heaps.erase(heap)
	_rising.erase(heap)
	_collision.erase(heap)
	heap_destroyed.emit(heap)
