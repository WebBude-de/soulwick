class_name DashedBox
extends Control
## Empty slot placeholder: dashed border one art pixel wide (#3b3650) with a centred muted caption
## (ui_spec shop.empty_slot, "kein 6. Angebot"). Pixel art (D-218): the dashes are whole UI art
## pixels (UiKit.ART_SCALE) on a grid centred in the box.

## Dash and gap length in art pixels.
const DASH := 4

var caption := "":
	set(value):
		caption = value
		if _label != null:
			_label.text = value

var _label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.text_label(caption, UiKit.SIZE_BODY, UiKit.COLOR_EMPTY_SLOT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)
	resized.connect(queue_redraw)


func _draw() -> void:
	var pixel := float(UiKit.ART_SCALE)
	var cells := Vector2i((size / pixel).floor())
	if cells.x < 2 or cells.y < 2:
		return
	# Centre the cell grid in the box, so the frame sits evenly on all sides.
	draw_set_transform(((size - Vector2(cells) * pixel) * 0.5).floor())
	paint_frame(self, cells, pixel)
	draw_set_transform(Vector2.ZERO)


## The dashed frame over cells (art pixels of size pixel) into item, top left at its origin.
static func paint_frame(item: Object, cells: Vector2i, pixel: float) -> void:
	var last := Vector2(cells - Vector2i.ONE) * pixel
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(last.x, 0.0), last, Vector2(0.0, last.y)]
	for i in 4:
		PixelDraw.dashed_line(item, corners[i], corners[(i + 1) % 4], UiKit.COLOR_LINE, DASH, DASH, 1, pixel)
