class_name RoomCatalog
extends Resource
## Combat room templates indexed by room kind, size class and biome (D-086, D-100).
## The generator (tools/generate_room_templates.py) writes one RoomTemplate resource per combat
## template (dungeon/rooms/templates/) and lists them in combat_catalog.tres, so a new template
## shows up in the game without touching dungeon.tscn. Extra scenes without a RoomTemplate (the
## DungeonManager export, tests) are described from their RoomController properties instead, read
## from the scene state without instantiating the room.

const DEFAULT_PATH := "res://dungeon/rooms/combat/combat_catalog.tres"
const KIND_PROPERTY := &"room_kind"
const SIZE_PROPERTY := &"room_size_class"

## Generated list of all combat templates (combat_catalog.tres).
@export var entries: Array[RoomTemplate] = []
## Extra template scenes without metadata resource (kind/size read from the scene).
@export var templates: Array[PackedScene] = []

static var _default: RoomCatalog = null

var _entries: Array[RoomTemplate] = []
var _indexed := false


## Catalog of the generated templates plus extra scenes (duplicates are ignored).
static func create(extra: Array[PackedScene] = []) -> RoomCatalog:
	var catalog := RoomCatalog.new()
	var generated := load_default()
	if generated != null:
		for entry in generated.get_entries():
			catalog.add_entry(entry)
	for scene in extra:
		catalog.add_template(scene)
	return catalog


## The generated catalog, loaded once (null if missing).
static func load_default() -> RoomCatalog:
	if _default == null and ResourceLoader.exists(DEFAULT_PATH):
		_default = load(DEFAULT_PATH) as RoomCatalog
	return _default


## RoomTemplate of a live room (by its scene path) in the generated catalog, null if unknown.
static func find_template_of(room: Node) -> RoomTemplate:
	var catalog := load_default()
	if catalog == null or room == null:
		return null
	return catalog.find_by_path(room.scene_file_path)


func add_entry(entry: RoomTemplate) -> void:
	_ensure_indexed()
	_add_entry(entry)


## Registers a template scene. kind/size -1 = read from the template itself (tests may override them).
func add_template(scene: PackedScene, kind := -1, size := -1) -> void:
	_ensure_indexed()
	if scene == null:
		return
	var known := find_by_path(scene.resource_path) if not scene.resource_path.is_empty() else null
	if known != null or _find_scene(scene) != null:
		return
	var info := read_template_info(scene)
	var entry := RoomTemplate.new()
	entry.id = StringName(scene.resource_path.get_file().get_basename())
	entry.scene = scene
	entry.room_kind = (kind if kind >= 0 else info.x) as RoomSequence.RoomKind
	entry.size_class = (size if size >= 0 else info.y) as RoomSequence.RoomSize
	_entries.append(entry)


func get_template_count() -> int:
	_ensure_indexed()
	return _entries.size()


func get_entries() -> Array[RoomTemplate]:
	_ensure_indexed()
	return _entries.duplicate()


func get_templates() -> Array[PackedScene]:
	_ensure_indexed()
	var scenes: Array[PackedScene] = []
	for entry in _entries:
		scenes.append(entry.scene)
	return scenes


func find_by_path(path: String) -> RoomTemplate:
	_ensure_indexed()
	if path.is_empty():
		return null
	for entry in _entries:
		if entry.scene != null and entry.scene.resource_path == path:
			return entry
	return null


func get_template(scene: PackedScene) -> RoomTemplate:
	_ensure_indexed()
	var entry := _find_scene(scene)
	if entry == null and scene != null:
		entry = find_by_path(scene.resource_path)
	return entry


## Kind of a registered template, -1 if unknown.
func get_kind_of(scene: PackedScene) -> int:
	var entry := get_template(scene)
	return int(entry.room_kind) if entry != null else -1


## Size class of a registered template, -1 if unknown.
func get_size_of(scene: PackedScene) -> int:
	var entry := get_template(scene)
	return int(entry.size_class) if entry != null else -1


func has_kind(kind: int, sizes: Array[RoomSequence.RoomSize], biome_id: StringName = &"", room_index := 0, entrance_side := -1) -> bool:
	return not _candidates(kind, sizes, biome_id, room_index, entrance_side).is_empty()


## A template scene of the wanted kind, see pick_template().
func pick(kind: int, sizes: Array[RoomSequence.RoomSize], rng: RandomNumberGenerator, biome_id: StringName = &"", room_index := 0, entrance_side := -1) -> PackedScene:
	var entry := pick_template(kind, sizes, rng, biome_id, room_index, entrance_side)
	return entry.scene if entry != null else null


## A template of the wanted kind in one of the allowed sizes (and allowed in the biome and the room,
## if given: RoomTemplate.min_room keeps the catacomb out of room 1), picked uniformly. Without such
## a template the room becomes a normal room (D-100), then any template of the allowed sizes, then
## any. Draws exactly one random number whenever a template exists; null only for an empty catalog.
## room_index 0 = no room filter. entrance_side (RoomTemplate.DoorSide, -1 = any): only templates
## with a door place on that wall (A10: a room entered from the west needs a west door); this filter
## holds through every fallback step except the very last one.
func pick_template(kind: int, sizes: Array[RoomSequence.RoomSize], rng: RandomNumberGenerator, biome_id: StringName = &"", room_index := 0, entrance_side := -1) -> RoomTemplate:
	_ensure_indexed()
	var any_size: Array[RoomSequence.RoomSize] = []
	var candidates := _candidates(kind, sizes, biome_id, room_index, entrance_side)
	if candidates.is_empty():
		candidates = _candidates(RoomSequence.RoomKind.NORMAL, sizes, biome_id, room_index, entrance_side)
	if candidates.is_empty():
		candidates = _candidates(-1, sizes, biome_id, room_index, entrance_side)
	if candidates.is_empty():
		candidates = _candidates(-1, any_size, biome_id, room_index, entrance_side)
	if candidates.is_empty():
		candidates = _candidates(-1, any_size, &"", 0, entrance_side)
	if candidates.is_empty():
		candidates = _candidates(-1, any_size, &"")
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## Vector2i(kind, size) stored in a template scene, following inherited scenes down to room_base.
## Values not set anywhere fall back to normal, S.
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
	return Vector2i(maxi(kind, RoomSequence.RoomKind.NORMAL), maxi(size, RoomSequence.RoomSize.S))


# kind -1 = any kind, empty sizes = any size, empty biome = any biome, room 0 = any room,
# entrance_side -1 = any wall.
func _candidates(kind: int, sizes: Array[RoomSequence.RoomSize], biome_id: StringName, room_index := 0, entrance_side := -1) -> Array[RoomTemplate]:
	_ensure_indexed()
	var result: Array[RoomTemplate] = []
	for entry in _entries:
		if kind >= 0 and int(entry.room_kind) != kind:
			continue
		if not sizes.is_empty() and not sizes.has(entry.size_class):
			continue
		if not entry.allows_biome(biome_id) or not entry.allows_room(room_index) or not entry.allows_entrance(entrance_side):
			continue
		result.append(entry)
	return result


func _find_scene(scene: PackedScene) -> RoomTemplate:
	for entry in _entries:
		if entry.scene == scene:
			return entry
	return null


func _ensure_indexed() -> void:
	if _indexed:
		return
	_indexed = true
	for entry in entries:
		_add_entry(entry)
	for scene in templates:
		add_template(scene)


func _add_entry(entry: RoomTemplate) -> void:
	if entry == null or entry.scene == null or _entries.has(entry):
		return
	if find_by_path(entry.scene.resource_path) != null:
		return
	_entries.append(entry)
