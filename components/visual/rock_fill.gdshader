shader_type canvas_item;
// Dungeon tiles: turns the flat "wall top" colour into solid rock (irregular stones with dark
// cracks), computed in world space on the art-pixel grid, so rooms, their thick rock ring and
// overlapping neighbour rooms join seamlessly. All other tile pixels are drawn unchanged.

// The flat fill colour of the wall-top tile (#2c2840) and everything sharing it.
uniform vec4 base_color : source_color = vec4(0.1725, 0.1569, 0.251, 1.0);
// One art pixel in world units (32 px art drawn at scale 2).
uniform float art_pixel = 2.0;
// Average stone size in art pixels.
uniform float stone_size = 11.0;

varying vec2 world_pos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.5 && distance(tex.rgb, base_color.rgb) < 0.03) {
		vec2 pixel = floor(world_pos / art_pixel);
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
		// Per-stone shade in three steps, dark cracks between stones, rare speckles.
		float stone = floor(hash1(id) * 3.0);
		float shade = stone == 0.0 ? 0.9 : (stone == 1.0 ? 1.0 : 1.1);
		float crack = step(f2 - f1, 1.6 / stone_size);
		shade = mix(shade, 0.74, crack);
		shade += step(0.985, hash1(pixel)) * 0.14;
		// COLOR already holds texture * modulate (biome tint); only the shade is applied.
		COLOR.rgb *= shade;
	}
}
