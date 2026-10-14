shader_type canvas_item;
// Second biome look of a room between two biomes (campfire, A6): drawn over the first biome's
// tiles, visible only where a soft mask says "new biome". The mask runs along the world y axis
// from blend_from_y (0, old biome) to blend_to_y (1, new biome), with blotchy noise and an
// ordered dither on the art-pixel grid, so the floor changes like pixel art, not like a fade.
// The wall-top rock look is the same as rock_fill.gdshader (copied, keep both in sync).

uniform float blend_from_y = 0.0;
uniform float blend_to_y = -512.0;
// How far the noise pushes the border around (0 = straight dithered band).
uniform float noise_amount = 0.9;
// Size of the noise blotches in art pixels.
uniform float noise_scale = 7.0;

uniform vec4 base_color : source_color = vec4(0.1725, 0.1569, 0.251, 1.0);
uniform float art_pixel = 2.0;
uniform float stone_size = 11.0;

varying vec2 world_pos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 4x4 Bayer threshold in (0, 1).
float bayer4(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	int index = x + y * 4;
	int table[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(table[index]) + 0.5) / 16.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 pixel = floor(world_pos / art_pixel);
	float span = blend_to_y - blend_from_y;
	float t = span != 0.0 ? clamp((world_pos.y - blend_from_y) / span, 0.0, 1.0) : 1.0;
	// Noise only in the middle of the band: both ends stay exactly one biome.
	float blotch = value_noise(pixel / noise_scale) + 0.5 * value_noise(pixel / (noise_scale * 0.4));
	float mask = t + (blotch / 1.5 - 0.5) * noise_amount * 4.0 * t * (1.0 - t);
	if (mask <= bayer4(pixel)) {
		discard;
	}
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.5 && distance(tex.rgb, base_color.rgb) < 0.03) {
		vec2 g = (pixel + 0.5) / stone_size;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float f1 = 8.0;
		float f2 = 8.0;
		vec2 id = vec2(0.0);
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 nb = vec2(float(x), float(y));
				vec2 point = nb + 0.15 + 0.7 * hash2(cell + nb);
				float d = length(point - f);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					id = cell + nb;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
		float stone = floor(hash1(id) * 3.0);
		float shade = stone == 0.0 ? 0.9 : (stone == 1.0 ? 1.0 : 1.1);
		float crack = step(f2 - f1, 1.6 / stone_size);
		shade = mix(shade, 0.74, crack);
		shade += step(0.985, hash1(pixel)) * 0.14;
		COLOR.rgb *= shade;
	}
}
