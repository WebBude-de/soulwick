shader_type canvas_item;
// Per-sprite effects: hit flash, pixel dissolve on death, outline (elites, bosses) and the clothing
// colour of characters (same parameters as characters/character_tint.gdshader, set by CharacterData).

uniform sampler2D tint_mask : filter_nearest, repeat_disable;
uniform bool use_mask = false;
uniform vec4 tint_color : source_color = vec4(0.212, 0.565, 0.855, 1.0);
uniform vec4 base_color : source_color = vec4(0.212, 0.565, 0.855, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_edge : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float outline_pulse = 0.0;

// Modulate alpha (modulate * self_modulate) of the item: transparent texels lose it in COLOR, so
// the outline reads it from the vertex stage (an enemy hidden in the dark takes its outline along).
varying float modulate_alpha;

void vertex() {
	modulate_alpha = COLOR.a;
}

float pixel_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// In Godot 4 COLOR already is the texture colour times modulate. Multiplying it with the texture
	// again squared every colour (darker art, invisible outlines); the texture is only read for the
	// transparency tests below.
	vec4 c = COLOR;
	float texel_alpha = texture(TEXTURE, UV).a;
	// Clothing recolour keeps the light/shadow steps relative to the original tunic colour.
	if (use_mask && texture(tint_mask, UV).r > 0.5) {
		vec3 luma = vec3(0.299, 0.587, 0.114);
		float shade = dot(c.rgb, luma) / max(dot(base_color.rgb, luma), 0.001);
		c.rgb = clamp(tint_color.rgb * shade, 0.0, 1.0);
	}
	if (outline_color.a > 0.0 && texel_alpha < 0.1) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float around = texture(TEXTURE, UV + vec2(px.x, 0.0)).a + texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).a + texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		if (around > 0.0) {
			float pulse = 1.0 - outline_pulse * (0.5 + 0.5 * sin(TIME * 6.0));
			c = vec4(outline_color.rgb, outline_color.a * pulse * modulate_alpha);
		}
	}
	c.rgb = mix(c.rgb, flash_color.rgb, flash * step(0.01, c.a));
	if (dissolve > 0.0) {
		float h = pixel_hash(floor(UV / TEXTURE_PIXEL_SIZE));
		if (h < dissolve) {
			c.a = 0.0;
		} else if (h < dissolve + 0.12) {
			c.rgb = dissolve_edge.rgb;
		}
	}
	COLOR = c;
}
