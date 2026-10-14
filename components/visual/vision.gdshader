shader_type canvas_item;
// Full-screen overlay: darkness with light circles (player + light sources, D-067),
// red screen edge on damage and a pulsing vignette at low HP.
// Pixel look: the darkness is computed on a coarse pixel grid and quantised into bands with
// ordered (Bayer) dithering. Lights combine like "screen" blending, so overlapping circles merge
// smoothly instead of forming a crease where they meet. The raster is locked to the world
// (grid_offset), so the dither pattern scrolls with the floor instead of shimmering.

const int MAX_LIGHTS = 24;

uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform vec2 player_pos = vec2(640.0, 360.0);
uniform float vision_radius = 300.0;
uniform float softness = 150.0;
uniform vec4 dark_color : source_color = vec4(0.012, 0.008, 0.025, 1.0);
uniform int light_count = 0;
uniform vec4 lights[MAX_LIGHTS]; // xy = screen position, z = radius, w = intensity
uniform float low_hp : hint_range(0.0, 1.0) = 0.0;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
// Size of one darkness pixel on screen (2 art pixels at the world scale of 2).
uniform float pixel_size = 4.0;
uniform float bands = 6.0;
// Canvas origin modulo the dither period, keeps the raster world-locked.
uniform vec2 grid_offset = vec2(0.0);

float bayer4(vec2 cell) {
	int x = int(mod(cell.x, 4.0));
	int y = int(mod(cell.y, 4.0));
	int index = x + y * 4;
	// 4x4 Bayer matrix, values 0..15
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[index]) + 0.5) / 16.0;
}

float light_amount(vec2 p, vec2 center, float radius, float soft) {
	float d = distance(p, center);
	return 1.0 - smoothstep(max(radius - soft, 0.0), radius, d);
}

// Double beat ("lub-dub") once per period, 0..1. Same curve as post_process.gdshader.
float heartbeat(float t) {
	float p = fract(t / 0.95);
	return exp(-pow((p - 0.03) * 22.0, 2.0)) + 0.65 * exp(-pow((p - 0.24) * 22.0, 2.0));
}

void fragment() {
	vec2 cell = floor((UV * screen_size - grid_offset) / pixel_size);
	vec2 p = (cell + 0.5) * pixel_size + grid_offset;

	float flicker = 1.0 + 0.012 * sin(TIME * 7.0) + 0.008 * sin(TIME * 13.0);
	// "Screen" blend: remaining darkness is the product of what every light leaves dark.
	float remaining = 1.0 - light_amount(p, player_pos, vision_radius * flicker, softness);
	for (int i = 0; i < light_count; i++) {
		vec4 l = lights[i];
		remaining *= 1.0 - l.w * light_amount(p, l.xy, l.z, l.z * 0.7);
	}
	// Quantise the light falloff into bands with ordered dithering for a pixel-art gradient;
	// full darkness (remaining = 1) stays a solid colour.
	remaining = clamp(floor(remaining * bands + bayer4(cell) * step(remaining, 0.999)) / bands, 0.0, 1.0);
	float shade = darkness * remaining;

	vec2 centered = (UV - 0.5) * vec2(screen_size.x / screen_size.y, 1.0);
	float edge = smoothstep(0.45, 0.95, length(centered));
	float pulse = 0.35 + 0.65 * clamp(heartbeat(TIME), 0.0, 1.0);
	float red = clamp(low_hp * pulse * edge * 0.9 + hurt * edge * 0.8, 0.0, 1.0);
	red = floor(red * bands + bayer4(cell)) / bands;

	float alpha = max(shade, red * 0.8);
	vec3 color = mix(dark_color.rgb, vec3(0.55, 0.0, 0.04), red / max(red + shade, 0.0001));
	COLOR = vec4(color, alpha);
}
