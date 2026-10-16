extends Control
## Biome progress under the room number (launch review P1-6, 16.10.2026): one pip per room of the
## current biome (RoomSequence.BOSS_INTERVAL rooms), with symbols for special rooms (diamond),
## minibosses (skull) and the boss (horned skull). Rooms behind the player are dimmed, the current
## room is bright with a mark below it, rooms ahead are hollow (symbols in their colour). At the
## campfire after a boss every pip counts as done.
## Look only: the room types come from RoomSequence (read only), the HUD pushes the room number
## (set_room). Every machine draws its own from the same room number (coop).
## Pixel art at KeyCap.HUD_PIXEL screen pixels per art pixel, with a one-pixel text shadow.
## No class_name (no global class cache entry needed): Hud and the tests preload it.

enum Kind { COMBAT, SPECIAL, MINIBOSS, BOSS }

## Shapes in art pixels ("#" = set). Plain rooms are small squares, symbols are 5 rows high.
const SHAPES := {
	Kind.COMBAT: ["###", "###", "###"],
	Kind.SPECIAL: ["..#..", ".###.", "#####", ".###.", "..#.."],
	Kind.MINIBOSS: [".###.", "#####", "#.#.#", "#####", ".#.#."],
	Kind.BOSS: ["##...##", ".#####.", ".#.#.#.", ".#####.", "..#.#.."],
}
## Plain room ahead: the square as a ring.
const COMBAT_AHEAD: Array[String] = ["###", "#.#", "###"]
const COLORS := {
	Kind.COMBAT: UiKit.COLOR_TEXT,
	Kind.SPECIAL: UiKit.COLOR_GOLD,
	Kind.MINIBOSS: UiKit.COLOR_EFFECT,
	Kind.BOSS: UiKit.COLOR_DANGER,
}
## Layout in art pixels: symbol rows, gap between pips, gap above the mark, mark height.
const ROWS := 5
const GAP := 1
const MARK_GAP := 1
const MARK_HEIGHT := 1
## Alpha of rooms behind the player and of symbols ahead (TESTWERTE).
const DONE_ALPHA := 0.45
const AHEAD_SYMBOL_ALPHA := 0.8
const SHADOW_ALPHA := 0.85

## Screen pixels per art pixel.
var pixel: int = KeyCap.HUD_PIXEL

var _room := 0
var _campfire := false
var _kinds: Array[int] = []
var _current := -1


func _init() -> void:
	name = "BiomeProgress"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_END
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Room number shown by the HUD; campfire = the rest after the biome's boss (all pips done).
func set_room(room_index: int, campfire := false) -> void:
	var room := maxi(1, room_index)
	if room == _room and campfire == _campfire and not _kinds.is_empty():
		return
	_room = room
	_campfire = campfire
	var first := first_room_of_biome(room)
	_kinds.clear()
	for i in RoomSequence.BOSS_INTERVAL:
		_kinds.append(kind_for(RoomSequence.get_room_type(first + i)))
	_current = -1 if campfire else room - first
	update_minimum_size()
	queue_redraw()


## Kind of every pip of the current biome, in room order.
func get_kinds() -> Array[int]:
	return _kinds.duplicate()


## Pip of the current room (0-based); -1 at the campfire.
func get_current_index() -> int:
	return _current


## First room number of the biome room_index belongs to (1, 16, 31, ...).
static func first_room_of_biome(room_index: int) -> int:
	return floori(float(maxi(1, room_index) - 1) / RoomSequence.BOSS_INTERVAL) * RoomSequence.BOSS_INTERVAL + 1


## Rooms from room_index to the next boss room (0 = this is the boss room).
static func rooms_until_boss(room_index: int) -> int:
	var room := maxi(1, room_index)
	return ceili(float(room) / RoomSequence.BOSS_INTERVAL) * RoomSequence.BOSS_INTERVAL - room


static func kind_for(room_type: RoomSequence.RoomType) -> Kind:
	match room_type:
		RoomSequence.RoomType.SPECIAL:
			return Kind.SPECIAL
		RoomSequence.RoomType.MINIBOSS:
			return Kind.MINIBOSS
		RoomSequence.RoomType.BOSS:
			return Kind.BOSS
	return Kind.COMBAT


static func shape_width(kind: int) -> int:
	return String((SHAPES[kind] as Array)[0]).length()


func _get_minimum_size() -> Vector2:
	if _kinds.is_empty():
		return Vector2.ZERO
	var width := 0
	for kind in _kinds:
		width += shape_width(kind)
	width += GAP * (_kinds.size() - 1)
	# +1: the shadow one art pixel to the right and below.
	return Vector2(width + 1, ROWS + MARK_GAP + MARK_HEIGHT + 1) * pixel


func _draw() -> void:
	var x := 0
	for i in _kinds.size():
		var kind := _kinds[i]
		var width := shape_width(kind)
		var rows: Array = SHAPES[kind]
		var color: Color = COLORS[kind]
		var done := _current < 0 or i < _current
		var current := i == _current
		if done:
			color = UiKit.COLOR_MUTED if kind == Kind.COMBAT else UiKit.COLOR_DISABLED
			color.a = DONE_ALPHA
		elif not current:
			if kind == Kind.COMBAT:
				rows = COMBAT_AHEAD
				color = UiKit.COLOR_MUTED
			else:
				color.a = AHEAD_SYMBOL_ALPHA
		var top := floori(float(ROWS - rows.size()) / 2.0)
		_draw_shape(rows, Vector2i(x, top), color)
		if current:
			var mark := Rect2(Vector2(x, ROWS + MARK_GAP) * pixel, Vector2(width, MARK_HEIGHT) * pixel)
			draw_rect(Rect2(mark.position + Vector2.ONE * pixel, mark.size), _shadow_color())
			draw_rect(mark, UiKit.COLOR_TEXT)
		x += width + GAP


func _draw_shape(rows: Array, origin: Vector2i, color: Color) -> void:
	# Shadow first, one art pixel to the bottom right, then the shape.
	for pass_index in 2:
		var offset := Vector2i.ONE if pass_index == 0 else Vector2i.ZERO
		var tint := _shadow_color(color.a) if pass_index == 0 else color
		for y in rows.size():
			var line := String(rows[y])
			for x in line.length():
				if line[x] == "#":
					draw_rect(Rect2(Vector2(origin + offset + Vector2i(x, y)) * pixel, Vector2.ONE * pixel), tint)


func _shadow_color(alpha := 1.0) -> Color:
	var shadow := UiKit.COLOR_SHADOW
	shadow.a = SHADOW_ALPHA * alpha
	return shadow
