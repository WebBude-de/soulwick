class_name SpriteFx
extends RefCounted
## Applies and drives sprite_fx.gdshader (flash, dissolve, outline) on a CanvasItem.

const SHADER: Shader = preload("res://components/visual/sprite_fx.gdshader")
const FLASH_TIME := 0.12


static func apply(item: CanvasItem) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	item.material = material
	return material


static func flash(item: CanvasItem, color := Color.WHITE, duration := FLASH_TIME) -> void:
	var material := item.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter(&"flash_color", color)
	var peak := GameOptions.get_flash_strength()
	material.set_shader_parameter(&"flash", peak)
	item.create_tween().tween_method(func(v: float) -> void: material.set_shader_parameter(&"flash", v), peak, 0.0, duration)


static func outline(item: CanvasItem, color: Color, pulse := 0.4) -> void:
	var material := item.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter(&"outline_color", color)
	material.set_shader_parameter(&"outline_pulse", pulse)


## Pixel dissolve, returns the tween so callers can chain (e.g. queue_free).
static func dissolve(item: CanvasItem, duration: float, edge := Color(1.0, 0.55, 0.2)) -> Tween:
	var material := item.material as ShaderMaterial
	var tween := item.create_tween()
	if material == null:
		tween.tween_property(item, "modulate:a", 0.0, duration)
		return tween
	material.set_shader_parameter(&"dissolve_edge", edge)
	tween.tween_method(func(v: float) -> void: material.set_shader_parameter(&"dissolve", v), 0.0, 1.0, duration)
	return tween
