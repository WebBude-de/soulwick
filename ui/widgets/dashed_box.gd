class_name DashedBox
extends Control
## Empty slot placeholder: 1 px dashed border (#3b3650) with a centred muted caption
## (ui_spec shop.empty_slot, "kein 6. Angebot").

const DASH := 4.0

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
	var width := maxf(1.0, UiKit.px(1))
	var dash := UiKit.px(DASH)
	var rect := Rect2(Vector2.ZERO, size).grow(-width * 0.5)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		var from: Vector2 = corners[i]
		var to: Vector2 = corners[(i + 1) % 4]
		var length := from.distance_to(to)
		var direction := (to - from) / maxf(0.001, length)
		var travelled := 0.0
		while travelled < length:
			var end := minf(travelled + dash, length)
			draw_line(from + direction * travelled, from + direction * end, UiKit.COLOR_LINE, width)
			travelled += dash * 2.0
