shader_type canvas_item;
// Full-screen post-process between the world (incl. vision overlay) and the HUD.
// Chromatic aberration pulse on hits, wobble + double vision while stunned, blur and fog while
// blinded, desaturation + heartbeat pulse at low HP, death desaturation and optional film grain.
// All offsets are snapped to whole world pixels so the pixel art never swims.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_blur : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform vec2 screen_size = vec2(1280.0, 720.0);
// One world pixel on screen (2 art pixels at zoom 1 would be 4; 2 keeps effects fine-grained).
uniform float pixel_size = 2.0;
uniform float chroma : hint_range(0.0, 1.0) = 0.0;
uniform float stun : hint_range(0.0, 1.0) = 0.0;
uniform float blind : hint_range(0.0, 1.0) = 0.0;
uniform float low_hp : hint_range(0.0, 1.0) = 0.0;
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 0.2) = 0.0;
// Player position in viewport pixels (centre of heartbeat zoom and the clear spot while blind).
uniform vec2 focus = vec2(640.0, 360.0);
uniform vec4 fog_color : source_color = vec4(0.18, 0.12, 0.28, 1.0);

// Double beat ("lub-dub") once per period, 0..1. Same curve as vision.gdshader.
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

vec2 snap(vec2 offset_px) {
	return floor(offset_px / pixel_size + 0.5) * pixel_size;
}

void fragment() {
	vec2 p = SCREEN_UV * screen_size;
	vec2 cell = floor(p / pixel_size);

	// Heartbeat: a tiny zoom towards the player on every beat.
	float beat = heartbeat(TIME) * low_hp;
	vec2 offset = (focus - p) * 0.012 * beat;

	// Stun: rows of pixels sway sideways in a slow wave.
	float row = floor(p.y / (pixel_size * 3.0));
	offset.x += sin(row * 0.31 + TIME * 7.0) * 5.0 * stun;
	offset.y += sin(p.x * 0.012 + TIME * 4.3) * 2.0 * stun;
	vec2 uv = (p + snap(offset)) / screen_size;

	vec3 color = texture(screen_tex, uv).rgb;

	// Stun: drifting double image.
	vec2 ghost = snap(vec2(cos(TIME * 3.1), sin(TIME * 2.3)) * 9.0 * stun);
	color = mix(color, texture(screen_tex, uv + ghost / screen_size).rgb, 0.3 * stun);

	// Chromatic aberration, stronger towards the edges.
	vec2 radial = (p - screen_size * 0.5) / screen_size.y;
	float ca = chroma * 10.0 + stun * 3.0;
	vec2 split = snap(radial * ca * 2.0) / screen_size;
	if (ca > 0.0) {
		color.r = texture(screen_tex, uv + split).r;
		color.b = texture(screen_tex, uv - split).b;
	}

	// Blind: everything away from the player blurs and drowns in drifting fog.
	if (blind > 0.0) {
		float away = smoothstep(40.0, 260.0, distance(p, focus));
		vec3 blurred = textureLod(screen_blur, uv, 3.0).rgb;
		color = mix(color, blurred, blind * (0.15 + 0.85 * away));
		vec2 fog_cell = floor(p / (pixel_size * 4.0));
		float fog = value_noise(fog_cell * 0.09 + vec2(TIME * 0.35, TIME * 0.12));
		fog = floor(fog * 4.0 + hash(fog_cell) * 0.9) / 4.0;
		color = mix(color, fog_color.rgb, blind * (0.25 + 0.45 * fog) * (0.25 + 0.75 * away));
	}

	// Low HP / death: colours drain away, a little more on every heartbeat.
	float drain = clamp(low_hp * (0.35 + 0.25 * beat) + desaturate, 0.0, 1.0);
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luma) * vec3(1.0, 0.95, 0.95), drain);

	// Film grain: stable per pixel block, changes 12 times per second.
	if (grain > 0.0) {
		color += (hash(cell + floor(TIME * 12.0) * vec2(17.0, 31.0)) - 0.5) * grain;
	}
	COLOR = vec4(color, 1.0);
}
