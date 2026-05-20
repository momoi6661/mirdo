shader_type canvas_item;

uniform vec4 center_color : source_color = vec4(0.82, 0.18, 0.50, 1.0);
uniform vec4 side_color : source_color = vec4(0.36, 0.055, 0.22, 1.0);
uniform vec4 top_color : source_color = vec4(0.50, 0.085, 0.32, 1.0);
uniform float side_falloff : hint_range(0.2, 4.0) = 1.18;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.075;
uniform float pattern_strength : hint_range(0.0, 0.3) = 0.055;
uniform float motion_speed : hint_range(0.0, 4.0) = 0.42;
uniform float breath_strength : hint_range(0.0, 0.4) = 0.13;
uniform float spark_strength : hint_range(0.0, 0.5) = 0.20;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float spark_layer(vec2 uv, vec2 grid_size, float t, float threshold) {
	vec2 grid = floor(uv * grid_size);
	vec2 local = fract(uv * grid_size) - 0.5;
	float seed = hash(grid);
	vec2 drift = vec2(sin(t * (0.35 + seed) + seed * 6.28), cos(t * (0.28 + seed) + seed * 4.12)) * 0.18;
	float d = length(local - drift);
	float twinkle = 0.45 + 0.55 * sin(t * (1.0 + seed * 1.6) + seed * 12.0);
	return (1.0 - smoothstep(0.015, 0.085, d)) * step(threshold, seed) * twinkle;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * motion_speed;
	float breath = sin(TIME * 1.08) * 0.5 + 0.5;
	float side = pow(abs(uv.x - 0.5) * 2.0, side_falloff);
	float center_band = 1.0 - side;
	float vertical = smoothstep(0.0, 0.95, 1.0 - uv.y);

	vec3 col = mix(center_color.rgb, side_color.rgb, side);
	col = mix(col, top_color.rgb, vertical * 0.20);
	col += center_color.rgb * center_band * breath * breath_strength;

	float soft_wave = value_noise(vec2(uv.x * 2.2, uv.y * 1.1 + t * 0.16));
	col += center_color.rgb * (soft_wave - 0.5) * 0.045 * center_band;

	float vignette_x = pow(abs(uv.x - 0.5) * 2.0, 2.2);
	float vignette_y = pow(abs(uv.y - 0.5) * 2.0, 2.7) * 0.30;
	float vignette = clamp(vignette_x + vignette_y, 0.0, 1.0) * vignette_strength;

	float fine = hash(floor((uv + vec2(t * 0.010, -t * 0.008)) * vec2(210.0, 120.0)));
	float dust = step(0.965, fine) * pattern_strength * (0.55 + 0.45 * breath);
	float spark_a = spark_layer(uv + vec2(0.0, -t * 0.018), vec2(18.0, 10.0), TIME, 0.82);
	float spark_b = spark_layer(uv + vec2(t * 0.010, t * 0.012), vec2(30.0, 17.0), TIME * 0.8, 0.91);
	float sparks = (spark_a * 0.75 + spark_b * 0.55) * spark_strength;
	float grain = (hash(floor((uv + vec2(t * 0.01, t * 0.015)) * vec2(420.0, 240.0))) - 0.5) * 0.008;

	col += vec3(dust) * vec3(0.86, 0.30, 0.54);
	col += vec3(sparks) * vec3(1.0, 0.58, 0.78);
	col += grain;
	col -= vignette * 0.38;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
