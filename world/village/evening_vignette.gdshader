shader_type canvas_item;
// Evening light of the village (R7, 06_dorf.md): a soft vignette towards the darkness colour at the
// screen edges and a faint warm glow in the middle at dusk. Drawn below the VisionOverlay (which
// keeps the lamps' light islands), so the middle of the screen stays readable and only the edges
// sink into the evening. Pixel look like vision.gdshader: coarse grid, bands, ordered dithering.
// L1 ("Dorf wärmer"): the warm glow no longer fades out in full night - a lamp-lit hearth warmth
// stays in the middle (night_warmth, derived from edge_amount so VillageEvening needs no change),
// and the edge darkness leans a little towards a warm plum instead of pure blue (edge_warmth).

uniform vec4 dark_color : source_color = vec4(0.03, 0.04, 0.14, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
// Darkness at the very edge (0 = none) and warm tint in the middle (0 = none).
uniform float edge_amount = 0.0;
uniform float warm_amount = 0.0;
// Falloff from the centre, as a share of the half diagonal.
uniform float inner = 0.35;
uniform float outer = 1.05;
uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform float pixel_size = 4.0;
uniform float bands = 8.0;
// L1 (TESTWERTE): edge_amount at full night (VillageEvening.EDGE_AMOUNT), the warm glow kept at full
// night, its colour, and how far the edge darkness leans towards the plum colour.
uniform float edge_full = 0.6;
uniform float night_warmth = 0.08;
uniform vec4 night_warm_color : source_color = vec4(1.0, 0.66, 0.36, 1.0);
uniform float edge_warmth = 0.22;
uniform vec4 plum_color : source_color = vec4(0.12, 0.05, 0.1, 1.0);

float bayer4(vec2 cell) {
	int x = int(mod(cell.x, 4.0));
	int y = int(mod(cell.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[x + y * 4]) + 0.5) / 16.0;
}

void fragment() {
	vec2 cell = floor(SCREEN_UV * screen_size / pixel_size);
	vec2 uv = (cell + 0.5) * pixel_size / screen_size;
	vec2 aspect = vec2(screen_size.x / screen_size.y, 1.0);
	float d = length((uv - 0.5) * aspect) / length(aspect * 0.5);
	float v = smoothstep(inner, outer, d);
	float dither = bayer4(cell);
	float night = clamp(edge_amount / max(edge_full, 0.001), 0.0, 1.0);
	float k = clamp(floor(edge_amount * v * bands + dither * step(0.001, edge_amount * v)) / bands, 0.0, 1.0);
	// Dusk glow (warm_amount) and the hearth warmth that stays at night, whichever is stronger.
	float night_w = night_warmth * night;
	float w = clamp(max(warm_amount, night_w) * (1.0 - v), 0.0, 1.0);
	vec3 warm = warm_amount >= night_w ? warm_color.rgb : night_warm_color.rgb;
	vec3 edge_color = mix(dark_color.rgb, plum_color.rgb, edge_warmth * night);
	// Two layers in one "over" blend: first the warm glow, then the darkness on top.
	float a = 1.0 - (1.0 - w) * (1.0 - k);
	vec3 color = a > 0.0001 ? (warm * w * (1.0 - k) + edge_color * k) / a : vec3(0.0);
	COLOR = vec4(color, a);
}
