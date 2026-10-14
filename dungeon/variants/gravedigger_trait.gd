class_name GravediggerTrait
extends Node2D
## "Totengräber" as a trait of the crypt (KONZEPT_RAEUME_V2 §2, D-120; before the variant of D-114):
## in crypt combat rooms some skeletons leave a bone heap when beaten. Destroyed within RISE_TIME s
## (walking over it, dashing through, any hit) it is gone for good; otherwise the skeleton stands up
## again with RISE_HEALTH_SHARE of its health - at most once. Its gold drops only on the final death.
## Which skeleton: one roll each (VariantRules.GRAVEDIGGER_SKELETON_CHANCE) with an own RNG from the
## dungeon seed and the room number, never a draw from the dungeon RNG (the dungeon of a seed stays
## the same). Not a room mode: any crypt combat room may have it, minigames too.
## How it works without touching enemy_base: a chosen skeleton gets a copy of its data whose death
## spawn is the bone heap (enemies/data/bone_heap.tres), so the heap arrives through the room's normal
## death-spawn tracking and keeps the room shut while it lies there. A heap that rises turns back into
## the skeleton (same node, original data).

signal heap_destroyed(heap: Enemy)
signal skeleton_rose(skeleton: Enemy)

const NODE_NAME := &"GravediggerTrait"
const BONE_HEAP_PATH := "res://enemies/data/bone_heap.tres"
const ORIGINAL_META := &"gravedigger_original_data"
const GOLD_META := &"gravedigger_gold"
const ROLLED_META := &"gravedigger_rolled"
const RISEN_META := &"gravedigger_risen"
const HEAP_COLOR := Color(0.85, 0.82, 0.72)
const RISE_COLOR := Color("#e0463a")

var room: RoomController = null

## Living heaps: heap -> seconds it lies there.
var _heaps: Dictionary[Enemy, float] = {}
var _rising: Dictionary[Enemy, bool] = {}
## Collision of a heap before it became passable: heap -> [layer, mask].
var _collision: Dictionary[Enemy, Array] = {}
var _heap_data: EnemyData = null
var _risen := 0
var _rng := RandomNumberGenerator.new()


## Hangs the trait onto a prepared crypt combat room (from GRAVEDIGGER_FROM_ROOM on); null otherwise.
static func attach_if_crypt(target: RoomController) -> GravediggerTrait:
	if target == null or not is_instance_valid(target) or not target.has_room_kind():
		return null
	if not VariantRules.has_gravedigger(target.room_index, int(RoomSequence.get_biome(target.room_index))):
		return null
	return attach(target)


## Hangs the trait onto a room (any biome; tests and tools). One per room.
static func attach(target: RoomController) -> GravediggerTrait:
	var existing := of(target)
	if existing != null:
		return existing
	var gravedigger := GravediggerTrait.new()
	gravedigger.name = NODE_NAME
	gravedigger.room = target
	gravedigger._rng.seed = derive_seed(target)
	gravedigger._heap_data = (load(BONE_HEAP_PATH) as EnemyData).duplicate() as EnemyData
	gravedigger._heap_data.sprite_frames = VariantArt.make_bone_heap_frames()
	target.add_child(gravedigger)
	target.enemy_container.child_entered_tree.connect(gravedigger._on_enemy_added)
	return gravedigger


static func of(target: Node) -> GravediggerTrait:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NodePath(NODE_NAME)) as GravediggerTrait


## Seed of the skeleton rolls: dungeon seed and room number (like SpawnSources.derive_seed).
static func derive_seed(target: RoomController) -> int:
	var dungeon_seed := 0
	if target.context != null and target.context.rng != null:
		dungeon_seed = target.context.rng.seed
	return hash([dungeon_seed, target.room_index, "gravedigger"])


func get_heaps() -> Array[Enemy]:
	var heaps: Array[Enemy] = []
	for heap: Variant in _heaps.keys():
		if is_instance_valid(heap) and not (heap as Enemy).is_dead():
			heaps.append(heap)
	return heaps


func get_heap_count() -> int:
	return get_heaps().size()


func get_risen_count() -> int:
	return _risen


func is_heap(enemy: Enemy) -> bool:
	return enemy != null and enemy.data == _heap_data


## Will this skeleton leave a heap (it was rolled when it entered the room)?
func is_marked(enemy: Enemy) -> bool:
	return enemy != null and enemy.has_meta(ORIGINAL_META)


## Marks a skeleton for the trait whatever the roll (tests, tools). Before or after its _ready.
func mark(enemy: Enemy) -> void:
	if enemy == null or enemy.data == null or is_marked(enemy) or not VariantRules.can_rise(enemy.data.id):
		return
	enemy.set_meta(ROLLED_META, true)
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


# --- Skeletons and heaps entering the room ---

func _on_enemy_added(node: Node) -> void:
	var enemy := node as Enemy
	if enemy == null or enemy.data == null:
		return
	if enemy.data == _heap_data:
		_heaps[enemy] = 0.0
		enemy.ready.connect(_on_heap_ready.bind(enemy), CONNECT_ONE_SHOT)
		return
	if enemy.has_meta(ROLLED_META) or enemy.has_meta(ORIGINAL_META) or not VariantRules.can_rise(enemy.data.id):
		return
	enemy.set_meta(ROLLED_META, true)
	if VariantRules.skeleton_rises(enemy.data.id, _rng.randf()):
		mark(enemy)


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
	if not _heaps.is_empty():
		step(delta)


## Ages every heap, destroys stomped ones, raises the old ones (public for tests and tools).
func step(delta: float) -> void:
	var feet: Array[Vector2] = []
	if is_inside_tree():
		for node in EnemyTargeting.living_players(get_tree()):
			var player := node as Player
			if player != null:
				feet.append(player.get_feet_position())
	for heap in get_heaps():
		if heap.has_meta(RISEN_META):
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
	if not is_instance_valid(heap) or heap.is_dead() or heap.has_meta(RISEN_META):
		return false
	heap.health.take_damage(INF)
	return true


## Decision: the skeleton stands up again with part of its health (same node, original data).
func rise(heap: Enemy) -> bool:
	if not is_instance_valid(heap) or heap.is_dead() or heap.has_meta(RISEN_META):
		return false
	var original := heap.get_meta(ORIGINAL_META, null) as EnemyData
	if original == null:
		return false
	heap.set_meta(RISEN_META, true)
	_heaps.erase(heap)
	_rising.erase(heap)
	heap.data = original
	heap.apply_scaling(room.room_index if room != null else 1, false)
	var maximum := heap.health.get_max_health()
	heap.health.take_damage(maximum - VariantRules.risen_health(maximum))
	var collision: Array = _collision.get(heap, [PhysicsLayers.ENEMIES, PhysicsLayers.WORLD | PhysicsLayers.PLAYER | PhysicsLayers.ENEMIES])
	heap.collision_layer = collision[0]
	heap.collision_mask = collision[1]
	_collision.erase(heap)
	heap.set_physics_process(true)
	_risen += 1
	skeleton_rose.emit(heap)
	if is_inside_tree():
		Burst.spawn(heap.get_parent(), heap.global_position, HEAP_COLOR, 16, 140.0)
		Sfx.play_at(self, &"bone_rise", heap.global_position, -8.0)
		if room != null and room.context != null and room.context.ui != null and is_instance_valid(room.context.ui):
			room.context.ui.show_banner(DungeonTexts.t(&"VARIANT_GRAVEDIGGER_RISE"), DungeonTexts.t(&"VARIANT_GRAVEDIGGER_RISE_SUB"), RISE_COLOR)
	return true


func _begin_rise(heap: Enemy) -> void:
	_rising[heap] = true
	if is_inside_tree():
		Sfx.play_at(self, &"bone_rattle", heap.global_position, -8.0)
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
	if heap.has_meta(RISEN_META):
		return
	_heaps.erase(heap)
	_rising.erase(heap)
	_collision.erase(heap)
	heap_destroyed.emit(heap)
