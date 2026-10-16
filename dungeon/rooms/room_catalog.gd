class_name RoomCatalog
extends Resource
## Combat room templates indexed by room kind, size class and biome (D-086, D-100).
## The generator (tools/generate_room_templates.py) writes one RoomTemplate resource per combat
## template (dungeon/rooms/templates/) and lists them in combat_catalog.tres, so a new template
## shows up in the game without touching dungeon.tscn. Extra scenes without a RoomTemplate (the
## DungeonManager export, tests) are described from their RoomController properties instead, read
## from the scene state without instantiating the room.
## Room plans (R1, D-120): every template is built from a plan (dungeon/rooms/plans/). A plan is
## made for some biomes (RoomTemplate.allowed_biomes); without an explicit biome the room number
## decides it (biome_id_for_room), so a crypt room never gets a grotto plan. Mode plans (escort,
## flame, ...) are only drawn when their mode is asked for (R4); plain fights draw "clear" and
## "arena" plans. The weight of a plan scales its share. Boss, miniboss, rest and campfire plans
## live in a second catalog (PLANS_PATH, load_plans) with the helpers pick_plan()/find_boss_scene().
## Size L (plans "*_l", class L) is for groups of 3-4 players (D-084): clear, arena and every mode
## have L plans in every biome; a pick only gets them when its sizes ask for L.

const DEFAULT_PATH := "res://dungeon/rooms/combat/combat_catalog.tres"
## Boss, miniboss, rest and campfire plans (generator, RoomTemplate.role).
const PLANS_PATH := "res://dungeon/rooms/plan_catalog.tres"
## BiomeData.id per RoomSequence.Biome.
const BIOME_IDS: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const KIND_PROPERTY := &"room_kind"
const SIZE_PROPERTY := &"room_size_class"

## Generated list of all combat templates (combat_catalog.tres).
@export var entries: Array[RoomTemplate] = []
## Extra template scenes without metadata resource (kind/size read from the scene).
@export var templates: Array[PackedScene] = []

static var _default: RoomCatalog = null
static var _plans: RoomCatalog = null

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
		_default = _load_catalog(DEFAULT_PATH)
	return _default


## The generated catalog of boss, miniboss, rest and campfire plans, loaded once (null if missing).
static func load_plans() -> RoomCatalog:
	if _plans == null and ResourceLoader.exists(PLANS_PATH):
		_plans = _load_catalog(PLANS_PATH)
	return _plans


## Starts loading both catalogs, and with them every template scene, on worker threads (feedback
## 16.10.2026: the first dungeon entry stalled about 0.75 s on them). Call it early, while the village
## is shown; load_default()/load_plans() then take the result (waiting only if it is not done yet).
static func preload_in_background() -> void:
	for path in [DEFAULT_PATH, PLANS_PATH]:
		if not ResourceLoader.exists(path) or ResourceLoader.has_cached(path):
			continue
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path, "", true)


static func _load_catalog(path: String) -> RoomCatalog:
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var loaded := ResourceLoader.load_threaded_get(path) as RoomCatalog
		if loaded != null:
			return loaded
	return load(path) as RoomCatalog


## Biome id of a room number (RoomSequence.get_biome); &"" for room 0 (no filter).
static func biome_id_for_room(room_index: int) -> StringName:
	if room_index <= 0:
		return &""
	return BIOME_IDS[int(RoomSequence.get_biome(room_index))]


## A plan of role (RoomTemplate.ROLE_*) for the biome, for rest rooms also for special_type (-1 =
## any). rng null = the first fitting plan (no draw); otherwise one draw, weighted. Plans of other
## biomes only when the biome has none. null without any plan of the role.
static func pick_plan(role: StringName, biome_id: StringName, special_type := -1, rng: RandomNumberGenerator = null) -> RoomTemplate:
	var catalog := load_plans()
	if catalog == null:
		return null
	var fitting: Array[RoomTemplate] = []
	var any_biome: Array[RoomTemplate] = []
	for entry in catalog.get_entries():
		if entry.role != role or (special_type >= 0 and not entry.special_types.is_empty() and not entry.special_types.has(special_type)):
			continue
		any_biome.append(entry)
		if entry.allows_biome(biome_id):
			fitting.append(entry)
	if fitting.is_empty():
		fitting = any_biome
	if fitting.is_empty():
		return null
	if rng == null:
		return fitting[0]
	return _pick_weighted(fitting, rng)


## Boss room of a biome (R1: one floor plan per biome, 01_raumarten.md); null = none generated.
static func find_boss_scene(biome_id: StringName) -> PackedScene:
	var entry := pick_plan(RoomTemplate.ROLE_BOSS, biome_id)
	return entry.scene if entry != null else null


## RoomTemplate of a live room (by its scene path) in the generated catalogs, null if unknown.
static func find_template_of(room: Node) -> RoomTemplate:
	if room == null:
		return null
	var catalog := load_default()
	var entry: RoomTemplate = catalog.find_by_path(room.scene_file_path) if catalog != null else null
	if entry == null and load_plans() != null:
		entry = load_plans().find_by_path(room.scene_file_path)
	return entry


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


func has_kind(kind: int, sizes: Array[RoomSequence.RoomSize], biome_id: StringName = &"", room_index := 0, entrance_side := -1, mode: StringName = &"") -> bool:
	return not _candidates(kind, sizes, _biome_or_room(biome_id, room_index), room_index, entrance_side, mode).is_empty()


## A template scene of the wanted kind, see pick_template().
func pick(kind: int, sizes: Array[RoomSequence.RoomSize], rng: RandomNumberGenerator, biome_id: StringName = &"", room_index := 0, entrance_side := -1, mode: StringName = &"") -> PackedScene:
	var entry := pick_template(kind, sizes, rng, biome_id, room_index, entrance_side, mode)
	return entry.scene if entry != null else null


## A template of the wanted kind in one of the allowed sizes (and allowed in the biome and the room,
## if given: RoomTemplate.min_room keeps the catacomb out of room 1), picked uniformly. Without such
## a template the room becomes a normal room (D-100), then any template of the allowed sizes, then
## any. Draws exactly one random number whenever a template exists; null only for an empty catalog.
## room_index 0 = no room filter. entrance_side (RoomTemplate.DoorSide, -1 = any): only templates
## with a door place on that wall (A10: a room entered from the west needs a west door); this filter
## holds through every fallback step except the very last one. biome_id &"" = the biome of
## room_index (R1). mode &"" = a plain fight (clear and arena plans); a mode (&"escort", ...) asks
## for the plans of that mode (R4). Candidates are weighted by RoomTemplate.weight (one draw).
## The fallback steps first try every size up to the largest allowed one (a single-player run never
## gets an L room for 3-4 players, D-084), only then any size.
func pick_template(kind: int, sizes: Array[RoomSequence.RoomSize], rng: RandomNumberGenerator, biome_id: StringName = &"", room_index := 0, entrance_side := -1, mode: StringName = &"") -> RoomTemplate:
	_ensure_indexed()
	var biome := _biome_or_room(biome_id, room_index)
	var candidates := _candidates(kind, sizes, biome, room_index, entrance_side, mode)
	if candidates.is_empty():
		candidates = _candidates(RoomSequence.RoomKind.NORMAL, sizes, biome, room_index, entrance_side, mode)
	if candidates.is_empty():
		candidates = _candidates(-1, sizes, biome, room_index, entrance_side, mode)
	var any_size: Array[RoomSequence.RoomSize] = []
	for limit in [sizes_up_to(sizes), any_size]:
		if not candidates.is_empty():
			break
		candidates = _candidates(-1, limit, biome, room_index, entrance_side, mode)
		if candidates.is_empty():
			candidates = _candidates(-1, limit, &"", 0, entrance_side, mode)
		if candidates.is_empty():
			candidates = _candidates(-1, limit, &"", 0, -1, mode)
		if candidates.is_empty():
			candidates = _candidates(-1, limit, &"", 0, -1, &"*")
	if candidates.is_empty():
		return null
	return _pick_weighted(candidates, rng)


## Every size class up to the largest of sizes (S, M for [M]; empty sizes = any size).
static func sizes_up_to(sizes: Array[RoomSequence.RoomSize]) -> Array[RoomSequence.RoomSize]:
	var result: Array[RoomSequence.RoomSize] = []
	if sizes.is_empty():
		return result
	var largest := 0
	for size in sizes:
		largest = maxi(largest, int(size))
	for size in largest + 1:
		result.append(size as RoomSequence.RoomSize)
	return result


## One draw over the candidates, weighted by RoomTemplate.weight (all zero = uniform).
static func _pick_weighted(candidates: Array[RoomTemplate], rng: RandomNumberGenerator) -> RoomTemplate:
	var total := 0.0
	for entry in candidates:
		total += maxf(entry.weight, 0.0)
	if total <= 0.0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var roll := rng.randf() * total
	for entry in candidates:
		roll -= maxf(entry.weight, 0.0)
		if roll < 0.0:
			return entry
	return candidates[candidates.size() - 1]


static func _biome_or_room(biome_id: StringName, room_index: int) -> StringName:
	return biome_id if biome_id != &"" else biome_id_for_room(room_index)


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
# entrance_side -1 = any wall, mode &"" = plain fights, &"*" = any mode.
func _candidates(kind: int, sizes: Array[RoomSequence.RoomSize], biome_id: StringName, room_index := 0, entrance_side := -1, mode: StringName = &"") -> Array[RoomTemplate]:
	_ensure_indexed()
	var result: Array[RoomTemplate] = []
	for entry in _entries:
		if kind >= 0 and int(entry.room_kind) != kind:
			continue
		if mode != &"*" and not entry.allows_mode(mode):
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
