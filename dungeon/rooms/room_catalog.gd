class_name RoomCatalog
extends Resource
## Combat room templates indexed by room kind and size class (D-086).
## Every combat template carries its kind and size as exported properties of its RoomController
## root (written by tools/generate_room_templates.py); the catalog reads them from the scene state
## without instantiating the room. The generator also writes combat_catalog.tres next to the
## templates, so a new template shows up in the game without touching dungeon.tscn.

const DEFAULT_PATH := "res://dungeon/rooms/combat/combat_catalog.tres"
const KIND_PROPERTY := &"room_kind"
const SIZE_PROPERTY := &"room_size_class"

## Generated list of all combat templates (combat_catalog.tres).
@export var templates: Array[PackedScene] = []

var _scenes: Array[PackedScene] = []
var _kinds: Array[int] = []
var _sizes: Array[int] = []
var _indexed := false


## Catalog of the generated templates plus extra scenes (duplicates are ignored).
static func create(extra: Array[PackedScene] = []) -> RoomCatalog:
	var catalog := RoomCatalog.new()
	if ResourceLoader.exists(DEFAULT_PATH):
		var generated := load(DEFAULT_PATH) as RoomCatalog
		if generated != null:
			for scene in generated.templates:
				catalog.add_template(scene)
	for scene in extra:
		catalog.add_template(scene)
	return catalog


## Registers a template. kind/size -1 = read from the template itself (tests may override them).
func add_template(scene: PackedScene, kind := -1, size := -1) -> void:
	_ensure_indexed()
	_add(scene, kind, size)


func get_template_count() -> int:
	_ensure_indexed()
	return _scenes.size()


func get_templates() -> Array[PackedScene]:
	_ensure_indexed()
	return _scenes.duplicate()


## Kind of a registered template, -1 if unknown.
func get_kind_of(scene: PackedScene) -> int:
	_ensure_indexed()
	var i := _scenes.find(scene)
	return _kinds[i] if i >= 0 else -1


## Size class of a registered template, -1 if unknown.
func get_size_of(scene: PackedScene) -> int:
	_ensure_indexed()
	var i := _scenes.find(scene)
	return _sizes[i] if i >= 0 else -1


func has_kind(kind: int, sizes: Array[RoomSequence.RoomSize]) -> bool:
	return not _candidates(kind, sizes).is_empty()


## A template of the wanted kind in one of the allowed sizes, picked uniformly. Without such a
## template the room becomes an arena (D-086), then any template of the allowed sizes, then any.
## Draws exactly one random number whenever a template exists; null only for an empty catalog.
func pick(kind: int, sizes: Array[RoomSequence.RoomSize], rng: RandomNumberGenerator) -> PackedScene:
	_ensure_indexed()
	var candidates := _candidates(kind, sizes)
	if candidates.is_empty():
		candidates = _candidates(RoomSequence.RoomKind.ARENA, sizes)
	if candidates.is_empty():
		candidates = _candidates(-1, sizes)
	if candidates.is_empty():
		var any_size: Array[RoomSequence.RoomSize] = []
		candidates = _candidates(-1, any_size)
	if candidates.is_empty():
		return null
	return _scenes[candidates[rng.randi_range(0, candidates.size() - 1)]]


## Vector2i(kind, size) stored in a template, following inherited scenes down to room_base.
## Values not set anywhere fall back to the RoomController defaults (arena, S).
static func read_template_info(scene: PackedScene) -> Vector2i:
	var kind := -1
	var size := -1
	var state: SceneState = scene.get_state() if scene != null else null
	while state != null and (kind < 0 or size < 0):
		if state.get_node_count() == 0:
			break
		for i in state.get_node_property_count(0):
			var property := state.get_node_property_name(0, i)
			if property == KIND_PROPERTY and kind < 0:
				kind = int(state.get_node_property_value(0, i))
			elif property == SIZE_PROPERTY and size < 0:
				size = int(state.get_node_property_value(0, i))
		var base := state.get_base_scene_state()
		if base == null:
			var instance := state.get_node_instance(0)
			base = instance.get_state() if instance != null else null
		state = base
	return Vector2i(maxi(kind, RoomSequence.RoomKind.ARENA), maxi(size, RoomSequence.RoomSize.S))


# kind -1 = any kind, empty sizes = any size.
func _candidates(kind: int, sizes: Array[RoomSequence.RoomSize]) -> Array[int]:
	_ensure_indexed()
	var result: Array[int] = []
	for i in _scenes.size():
		if kind >= 0 and _kinds[i] != kind:
			continue
		if not sizes.is_empty() and not sizes.has(_sizes[i]):
			continue
		result.append(i)
	return result


func _ensure_indexed() -> void:
	if _indexed:
		return
	_indexed = true
	for scene in templates:
		_add(scene, -1, -1)


func _add(scene: PackedScene, kind: int, size: int) -> void:
	if scene == null or _scenes.has(scene):
		return
	if not scene.resource_path.is_empty():
		for known in _scenes:
			if known.resource_path == scene.resource_path:
				return
	var info := read_template_info(scene)
	_scenes.append(scene)
	_kinds.append(kind if kind >= 0 else info.x)
	_sizes.append(size if size >= 0 else info.y)
