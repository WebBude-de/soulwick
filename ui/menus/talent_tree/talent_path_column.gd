class_name TalentPathColumn
extends Control
## One path of the talent tree view (KE8, Mockup 14): the candle branch from Ebene 1 down to the
## Schlussstein and the nodes of every Ebene in a row on it. The branch is lit up to the last open
## Ebene and dim below. Places TalentNodeButtons; their look comes from TalentTreeDialog.

## Gap between the nodes of one Ebene (mockup px).
const NODE_GAP := 2.0
## Gap between two Ebenen (mockup px).
const ROW_GAP := 3.0
const DIM_BRANCH := Color(1, 1, 1, 0.28)

var talent_path: StringName = &""
## Nodes by Ebene (index 0 = Ebene 1).
var rows: Array[Array] = []
## Highest open Ebene (0 = none), set by the dialog.
var open_rank := 1


static func create(path_id: StringName, tree: TalentTree) -> TalentPathColumn:
	var column := TalentPathColumn.new()
	column.talent_path = path_id
	column.name = "Path_%s" % path_id
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var widest := 1
	for rank in range(TalentDef.MIN_RANK, TalentDef.MAX_RANK + 1):
		var row: Array = []
		for talent in tree.get_rank_talents(path_id, rank):
			var node := TalentNodeButton.create(talent)
			column.add_child(node)
			row.append(node)
		widest = maxi(widest, row.size())
		column.rows.append(row)
	var node_size := TalentNodeButton.min_size()
	column.custom_minimum_size = Vector2(
		node_size.x * widest + UiKit.px(NODE_GAP) * (widest - 1),
		row_height() * TalentDef.MAX_RANK)
	return column


## Height of one Ebene (node, level line, gap).
static func row_height() -> float:
	return TalentNodeButton.frame_px() + UiKit.px(TalentNodeButton.LEVEL_LINE) + UiKit.px(ROW_GAP)


## Centre of the frame of Ebene rank (1..4) on the column's axis (local px).
func row_center(rank: int) -> Vector2:
	return Vector2(size.x * 0.5, row_height() * (rank - 1) + TalentNodeButton.frame_px() * 0.5)


func get_nodes() -> Array[TalentNodeButton]:
	var result: Array[TalentNodeButton] = []
	for row in rows:
		for node: TalentNodeButton in row:
			result.append(node)
	return result


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY:
		_place_nodes()


func _place_nodes() -> void:
	for index in rows.size():
		var row: Array = rows[index]
		if row.is_empty():
			continue
		var node_size: Vector2 = (row[0] as Control).custom_minimum_size
		var width := node_size.x * row.size() + UiKit.px(NODE_GAP) * (row.size() - 1)
		var x := (size.x - width) * 0.5
		for node: TalentNodeButton in row:
			node.position = Vector2(x, row_height() * index)
			node.size = node_size
			x += node_size.x + UiKit.px(NODE_GAP)
	queue_redraw()


func _draw() -> void:
	var tile := TalentTreeArt.branch(talent_path)
	var width := UiKit.art_px(TalentTreeArt.BRANCH_SIZE * 0.75, TalentTreeArt.BRANCH_SIZE)
	for rank in range(TalentDef.MIN_RANK, TalentDef.MAX_RANK):
		var top := row_center(rank)
		var bottom := row_center(rank + 1)
		var rect := Rect2(top.x - width * 0.5, top.y, width, bottom.y - top.y)
		var tint := Color.WHITE if rank + 1 <= open_rank else DIM_BRANCH
		draw_texture_rect(tile, rect, true, tint)
	# A twig across Ebenen with several nodes, so every node hangs on the branch.
	var colour := TalentTreeArt.path_color(talent_path)
	for index in rows.size():
		var row: Array = rows[index]
		if row.size() < 2:
			continue
		var first := (row[0] as Control).position.x + (row[0] as Control).size.x * 0.5
		var last := (row[-1] as Control).position.x + (row[-1] as Control).size.x * 0.5
		var y := row_center(index + 1).y
		var tint := colour if index + 1 <= open_rank else Color(colour, DIM_BRANCH.a)
		# Two art pixels thick on the UI grid (D-218).
		var pixel := float(UiKit.ART_SCALE)
		PixelDraw.rect(self, Rect2(first, y - pixel, last - first, pixel * 2.0), tint, pixel)
