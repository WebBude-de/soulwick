shader_type canvas_item;
// Full-screen lighting pass: darkness with light circles (player + light sources, D-067, R6),
// coloured light from the sources, red screen edge on damage and a pulsing vignette at low HP.
// Reads the world below (screen texture) and writes it lit:
//   - the unlit environment is darkened by `darkness` (R6: about half visible in combat rooms),
//   - every light lifts the darkness ("screen" blend, overlapping circles merge without a crease),
//   - coloured lights tint what they touch and leave a faint haze in the dark (warm = safe,
//     cold = goal, red = danger).
// L1 ("Licht next level"), all in this one pass, no extra viewport:
//   - glow halo: every source draws an additive core in its colour (bloom around flames, lava,
//     crystals, projectiles), strength per light (light_halos),
//   - mist: faint world-locked haze drifting where source light falls,
//   - self-lit pixels: small bright, saturated details (lava cracks, flames, crystals, runes) resist
//     the darkness and glow a few pixels into their surroundings (12 taps on the cell raster). Only
//     details count (local contrast): large bright areas - additive door light cones, lit floor -
//     stay normal, so a soft cone never turns into a hard-edged glowing block (L1 rework 34.png).
//   - biome grading: shadows lifted towards the biome colour, highlights tinted, soft vignette into
//     the biome darkness.
// quality < 0.5 (option "Lichteffekte: Niedrig") skips halo, mist, grading and vignette.
// Pixel look: everything is computed on a coarse pixel grid and quantised into bands with ordered
// (Bayer) dithering on the falloff only. The raster is locked to the world (grid_offset), so the
// dither pattern scrolls with the floor instead of shimmering. The scene itself is read unfiltered:
// no sprite pixel is moved or blurred.

const int MAX_LIGHTS = 32;
const vec3 LUMA = vec3(0.299, 0.587, 0.114);

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform vec2 player_pos = vec2(640.0, 360.0);
uniform float vision_radius = 300.0;
uniform float softness = 150.0;
uniform vec4 dark_color : source_color = vec4(0.012, 0.008, 0.025, 1.0);
uniform int light_count = 0;
uniform vec4 lights[MAX_LIGHTS]; // xy = screen position, z = radius, w = intensity
uniform vec4 light_colors[MAX_LIGHTS]; // rgb = colour, a = tint strength
uniform float light_halos[MAX_LIGHTS]; // glow halo strength per light (0 = none)
// How much a coloured light tints the lit scene (multiplicative) and how much faint haze it leaves
// in the dark (additive). Both scaled by glow_amount (0 in daylight).
uniform float tint_strength = 0.6;
uniform float haze_strength = 0.1;
uniform float glow_amount : hint_range(0.0, 1.0) = 1.0;
// Lit areas are lifted a little above the plain scene, so the circles read against the half-dark
// environment (scaled by glow_amount like the colour).
uniform float light_boost = 0.15;
uniform float low_hp : hint_range(0.0, 1.0) = 0.0;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
// Size of one darkness pixel on screen (2 art pixels at the world scale of 2).
uniform float pixel_size = 4.0;
uniform float bands = 6.0;
// Canvas origin modulo the dither period, keeps the raster world-locked.
uniform vec2 grid_offset = vec2(0.0);
// L1: 1 = high (halo, mist, grading, vignette), 0 = low.
uniform float quality = 1.0;
// Glow halo: strength and core size as a share of the light radius.
uniform float halo_strength = 0.3;
uniform float halo_share = 0.42;
// Mist in the source light (world-locked: canvas origin and zoom turn screen px into world px).
uniform float mist_strength = 0.0;
uniform vec2 world_origin = vec2(0.0);
uniform float world_zoom = 1.0;
// Biome grading (BiomeGrade): shadow lift colour, highlight tint, overall amount, vignette.
uniform vec4 grade_shadow : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 grade_highlight : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float grade_amount = 0.0;
uniform float shadow_lift = 0.5;
uniform float highlight_mix = 0.5;
uniform float vignette = 0.0;
// Self-lit art: share of the darkness it keeps off, glow strength and glow reach in screen px.
// emissive_area: how strongly a bright neighbourhood switches the effect off (1 / share of the
// taps that may be bright before it is gone).
uniform float emissive_keep = 0.75;
uniform float emissive_area = 1.6;
uniform float emissive_glow = 0.5;
uniform float emissive_radius = 8.0;

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

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// How "self-lit" a colour is: bright and saturated (lava, flames, crystals), not white or grey.
float emissive(vec3 c) {
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float sat = (hi - lo) / max(hi, 0.001);
	return smoothstep(0.8, 1.0, hi) * smoothstep(0.42, 0.75, sat);
}

// Banded value with ordered dithering (0 stays 0).
float band(float v, float steps, float dither) {
	return floor(v * steps + dither * step(0.001, v)) / steps;
}

void fragment() {
	vec3 scene = texture(screen_tex, SCREEN_UV).rgb;
	vec2 cell = floor((UV * screen_size - grid_offset) / pixel_size);
	vec2 p = (cell + 0.5) * pixel_size + grid_offset;
	float dither = bayer4(cell);
	bool high = quality > 0.5;

	float flicker = 1.0 + 0.012 * sin(TIME * 7.0) + 0.008 * sin(TIME * 13.0);
	// "Screen" blend: remaining darkness is the product of what every light leaves dark.
	float remaining = 1.0 - light_amount(p, player_pos, vision_radius * flicker, softness);
	vec3 glow = vec3(0.0);
	float glow_weight = 0.0;
	vec3 halo = vec3(0.0);
	for (int i = 0; i < light_count; i++) {
		vec4 l = lights[i];
		vec2 dv = p - l.xy;
		float d2 = dot(dv, dv);
		// Most pixels lie outside most lights: skip them early (30+ lights stay cheap).
		if (d2 >= l.z * l.z) {
			continue;
		}
		float d = sqrt(d2);
		float a = l.w * (1.0 - smoothstep(l.z * 0.3, l.z, d));
		remaining *= 1.0 - a;
		vec4 c = light_colors[i];
		// Colour falls off faster than the light itself: the tint hugs the source.
		float g = a * a * c.a;
		glow += c.rgb * g;
		glow_weight += g;
		if (high) {
			float k = max(1.0 - d / max(l.z * halo_share, 1.0), 0.0);
			halo += c.rgb * (k * k) * l.w * light_halos[i];
		}
	}
	// Quantise the light falloff into bands with ordered dithering for a pixel-art gradient;
	// full darkness (remaining = 1) stays a solid colour.
	remaining = clamp(floor(remaining * bands + dither * step(remaining, 0.999)) / bands, 0.0, 1.0);
	// Self-lit details: sample the neighbourhood once (high quality only).
	float e0 = 0.0;
	float detail = 0.0;
	vec3 eg = vec3(0.0);
	if (high && emissive_glow > 0.0) {
		e0 = emissive(scene);
		float ecover = 0.0;
		for (int k = 0; k < 8; k++) {
			float ang = float(k) * 0.7853982;
			vec3 c = texture(screen_tex, (p + vec2(cos(ang), sin(ang)) * emissive_radius) / screen_size).rgb;
			float e = emissive(c);
			eg += c * e;
			ecover += e;
		}
		for (int k = 0; k < 4; k++) {
			float ang = float(k) * 1.5707963 + 0.7853982;
			vec3 c = texture(screen_tex, (p + vec2(cos(ang), sin(ang)) * emissive_radius * 2.2) / screen_size).rgb;
			float e = emissive(c);
			eg += c * e * 0.6;
			ecover += e * 0.6;
		}
		eg /= 10.4;
		// 0 inside large bright areas (cones, lit floor), 1 around thin details (lava cracks).
		detail = clamp(1.0 - ecover / 10.4 * emissive_area, 0.0, 1.0);
	}
	float self_lit = e0 * emissive_keep * detail;
	float shade = darkness * remaining * (1.0 - self_lit);
	vec3 color = mix(scene, dark_color.rgb, shade) * (1.0 + light_boost * glow_amount * (1.0 - remaining));

	// Coloured light: normalised colour, banded strength (same raster as the darkness).
	vec3 hue = vec3(1.0);
	float strength = 0.0;
	if (glow_weight > 0.001 && glow_amount > 0.0) {
		hue = glow / glow_weight;
		strength = clamp(glow_weight, 0.0, 1.0);
		strength = floor(strength * bands + dither * step(0.001, strength) * step(strength, 0.999)) / bands;
		strength *= glow_amount;
		// Tint relative to white with the light's brightness kept: a warm light warms the floor
		// instead of just darkening its blue parts.
		vec3 tint = min(hue / max(dot(hue, LUMA), 0.05), vec3(2.0)) * 1.1;
		color *= mix(vec3(1.0), tint, tint_strength * strength);
		color += hue * haze_strength * strength;
	}

	if (high) {
		// Glow halo: additive core in the light's colour, banded finer than the darkness.
		float hs = max(max(halo.r, halo.g), halo.b);
		if (hs > 0.001 && glow_amount > 0.0) {
			float q = band(min(hs, 1.5), bands * 2.0, dither);
			color += (halo / hs) * q * halo_strength * glow_amount;
		}
		// Self-lit glow: small bright details spill a little light around them (on the cell raster,
		// blocky like the darkness). Not onto the bright pixels themselves and not around large
		// bright areas, so nothing blows out and no glow bleeds over the rock beside a cone.
		float es = max(max(eg.r, eg.g), eg.b) * (1.0 - e0) * detail;
		if (es > 0.001 && glow_amount > 0.0) {
			color += (eg / max(max(eg.r, eg.g), eg.b)) * band(min(es, 1.0), bands * 2.0, dither) * emissive_glow * glow_amount;
		}
		// Mist: slow world-locked haze where source light falls.
		if (mist_strength > 0.0 && strength > 0.0) {
			vec2 wp = (p - world_origin) / max(world_zoom, 0.01);
			float n = value_noise(wp * 0.011 + vec2(TIME * 0.05, TIME * 0.02)) * 0.65
				+ value_noise(wp * 0.027 - vec2(TIME * 0.035, -TIME * 0.015)) * 0.35;
			float m = smoothstep(0.4, 0.85, n) * strength * mist_strength;
			color += mix(vec3(1.0), hue, 0.5) * band(m, bands * 4.0, dither);
		}
		// Biome grading: lift the shadows towards the biome colour, tint the highlights.
		if (grade_amount > 0.0) {
			float l = dot(color, LUMA);
			float sh = 1.0 - smoothstep(0.0, 0.32, l);
			float hi = smoothstep(0.3, 0.85, l);
			color += grade_shadow.rgb * shadow_lift * sh * grade_amount;
			vec3 ht = min(grade_highlight.rgb / max(dot(grade_highlight.rgb, LUMA), 0.05), vec3(1.6));
			color *= mix(vec3(1.0), ht, hi * highlight_mix * grade_amount);
		}
		// Soft vignette into the biome darkness.
		if (vignette > 0.0) {
			vec2 centered_v = (UV - 0.5) * vec2(screen_size.x / screen_size.y, 1.0);
			float v = smoothstep(0.42, 1.05, length(centered_v)) * vignette;
			color = mix(color, dark_color.rgb, band(v, bands * 2.0, dither));
		}
	}

	vec2 centered = (UV - 0.5) * vec2(screen_size.x / screen_size.y, 1.0);
	float edge = smoothstep(0.45, 0.95, length(centered));
	float pulse = 0.35 + 0.65 * clamp(heartbeat(TIME), 0.0, 1.0);
	float red = clamp(low_hp * pulse * edge * 0.9 + hurt * edge * 0.8, 0.0, 1.0);
	red = floor(red * bands + dither) / bands;
	color = mix(color, vec3(0.55, 0.0, 0.04), red * 0.8);

	COLOR = vec4(color, 1.0);
}
