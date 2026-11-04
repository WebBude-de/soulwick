class_name DecorLayer
extends Node2D
## The placed decoration of one space (WK5 village, WK7 home) as DecorPieces, rebuilt from the save
## whenever the decoration changes (SaveManager.decor_changed). Standing pieces sort with the players
## (the layer is y-sorted inside the y-sorted world, SortLift), flat and wall pieces lie under them
## (flat_z, wall_z). Pieces of ids the catalog does not know are left out (they stay in the save).
## Koop: show_snapshot() shows another world's arrangement instead (a guest sees the host's village,
## view only); the save is never touched then.

signal rebuilt

var space: StringName = &""
var grid: DecorGrid = null
var flat_z := -3
var wall_z := -3
var _snapshot := PackedStringArray()
var _uses_snapshot := false
var _queued := false


func setup(layer_space: StringName, layer_grid: DecorGrid, layer_flat_z: int, layer_wall_z: int) -> void:
	space = layer_space
	grid = layer_grid
	flat_z = layer_flat_z
	wall_z = layer_wall_z
	y_sort_enabled = true
	if not SaveManager.decor_changed.is_connected(_queue_rebuild):
		SaveManager.decor_changed.connect(_queue_rebuild)
	rebuild()


func _exit_tree() -> void:
	if SaveManager.decor_changed.is_connected(_queue_rebuild):
		SaveManager.decor_changed.disconnect(_queue_rebuild)


func _queue_rebuild() -> void:
	if _queued or _uses_snapshot:
		return
	_queued = true
	rebuild.call_deferred()


## Placements shown right now ({id, cell, rot, index}).
func placements() -> Array[Dictionary]:
	return DecorState.parse_list(_snapshot) if _uses_snapshot else DecorState.placements(space)


func rebuild() -> void:
	_queued = false
	if grid == null:
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for entry in placements():
		var item := DecorCatalog.get_item(String(entry["id"]))
		if item == null or item.space != space or item.is_surface():
			continue
		var piece := DecorPiece.create(item, entry["cell"], int(entry["rot"]), grid)
		piece.index = int(entry["index"])
		add_child(piece)
		if item.is_flat():
			piece.z_index = flat_z
		elif item.is_wall():
			piece.z_index = wall_z
		else:
			SortLift.lift(piece)
	rebuilt.emit()


## Shows a snapshot's arrangement (DecorState.snapshot of the host) instead of the own save.
func show_snapshot(list: PackedStringArray) -> void:
	_snapshot = list.duplicate()
	_uses_snapshot = true
	rebuild()


## Back to the own save.
func show_own() -> void:
	_uses_snapshot = false
	_snapshot = PackedStringArray()
	rebuild()


func is_showing_snapshot() -> bool:
	return _uses_snapshot


func get_pieces() -> Array[DecorPiece]:
	var pieces: Array[DecorPiece] = []
	for child in get_children():
		if child is DecorPiece and not child.is_queued_for_deletion():
			pieces.append(child as DecorPiece)
	return pieces


## The piece of a placement index (null if not shown).
func get_piece(index: int) -> DecorPiece:
	for piece in get_pieces():
		if piece.index == index:
			return piece
	return null


## Footprints of every shown piece (world px), e.g. to clear the scattered flowers under them.
func covered_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for piece in get_pieces():
		rects.append(grid.rect_of(piece.item, piece.cell, piece.rot))
	return rects
