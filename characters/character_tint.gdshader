shader_type canvas_item;
// Recolours the clothing of a character sprite (HANDOUT "Koop-Einfärbung").
// tint_mask is a strip of the same size as the current animation sheet: white = clothing.
// The clothing keeps its light/shadow steps: each pixel is scaled by its brightness relative to
// base_color (the original tunic colour), so shadows stay darker than the main tone.

uniform sampler2D tint_mask : filter_nearest, repeat_disable;
uniform bool use_mask = false;
uniform vec4 tint_color : source_color = vec4(0.212, 0.565, 0.855, 1.0);
uniform vec4 base_color : source_color = vec4(0.212, 0.565, 0.855, 1.0);

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

void fragment() {
	// COLOR already is the texture colour times modulate; only the clothing is changed.
	if (use_mask && texture(tint_mask, UV).r > 0.5) {
		float shade = dot(COLOR.rgb, LUMA) / max(dot(base_color.rgb, LUMA), 0.001);
		COLOR.rgb = clamp(tint_color.rgb * shade, 0.0, 1.0);
	}
}
