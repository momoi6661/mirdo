shader_type canvas_item;

uniform vec4 center_color : source_color = vec4(0.86, 0.20, 0.52, 1.0);
uniform vec4 side_color : source_color = vec4(0.42, 0.055, 0.25, 1.0);
uniform float side_falloff : hint_range(0.2, 4.0) = 1.65;
uniform float edge_darkness : hint_range(0.0, 0.5) = 0.055;
uniform float breath_strength : hint_range(0.0, 0.4) = 0.10;
uniform float spark_strength : hint_range(0.0, 0.5) = 0.18;
uniform float block_strength : hint_range(0.0, 0.5) = 0.16;
uniform float grain_strength : hint_range(0.0, 0.08) = 0.012;
uniform float motion_speed : hint_range(0.0, 4.0) = 0.36;

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

float soft_block(vec2 uv, vec2 grid_size, float t, float threshold) {
	vec2 grid = floor(uv * grid_size);
	vec2 cell = fract(uv * grid_size) - 0.5;
	float seed = hash(grid);
	vec2 drift = vec2(sin(t * (0.22 + seed) + seed * 6.28), cos(t * (0.20 + seed) + seed * 5.17)) * 0.16;
	vec2 half_size = vec2(0.10 + seed * 0.20, 0.055 + hash(grid + 9.1) * 0.16);
	vec2 d = abs(cell - drift) - half_size;
	float outside = length(max(d, vec2(0.0)));
	float shape = 1.0 - smoothstep(0.0, 0.08, outside);
	float fade = 0.45 + 0.55 * sin(t * (0.95 + seed) + seed * 14.0);
	return shape * step(threshold, seed) * fade;
}

float spark_layer(vec2 uv, vec2 grid_size, float t, float threshold, float radius) {
	vec2 grid = floor(uv * grid_size);
	vec2 local = fract(uv * grid_size) - 0.5;
	float seed = hash(grid);
	vec2 drift = vec2(sin(t * (0.42 + seed) + seed * 6.28), cos(t * (0.32 + seed) + seed * 4.12)) * 0.18;
	float d = length(local - drift);
	float twinkle = 0.45 + 0.55 * sin(t * (1.0 + seed * 1.6) + seed * 12.0);
	return (1.0 - smoothstep(radius * 0.35, radius, d)) * step(threshold, seed) * twinkle;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * motion_speed;
	float breath = sin(TIME * 1.05) * 0.5 + 0.5;

	float side = pow(abs(uv.x - 0.5) * 2.0, side_falloff);
	vec3 col = mix(center_color.rgb, side_color.rgb, side);
	float center_band = 1.0 - side;
	col += center_color.rgb * center_band * breath * breath_strength;
	col += vec3(0.035, 0.004, 0.020) * (0.5 + 0.5 * sin(TIME * 0.55));

	float fog = value_noise(vec2(uv.x * 2.0 + t * 0.08, uv.y * 1.2 - t * 0.05));
	col += center_color.rgb * (fog - 0.5) * 0.050;

	float edge = pow(abs(uv.x - 0.5) * 2.0, 2.4);
	col -= edge * edge_darkness;

	float blocks_a = soft_block(uv + vec2(t * 0.010, -t * 0.018), vec2(18.0, 10.0), TIME, 0.78);
	float blocks_b = soft_block(uv + vec2(-t * 0.016, t * 0.010), vec2(32.0, 18.0), TIME * 0.8, 0.88);
	float blocks = (blocks_a * 0.70 + blocks_b * 0.45) * block_strength;
	float spark_a = spark_layer(uv + vec2(0.0, -t * 0.020), vec2(22.0, 12.0), TIME, 0.86, 0.075);
	float spark_b = spark_layer(uv + vec2(t * 0.010, t * 0.012), vec2(38.0, 22.0), TIME * 0.75, 0.93, 0.060);
	float sparks = (spark_a * 0.70 + spark_b * 0.50) * spark_strength;
	float grain = (hash(floor((uv + vec2(t * 0.01, t * 0.012)) * vec2(460.0, 260.0))) - 0.5) * grain_strength;

	col += vec3(blocks) * vec3(0.95, 0.30, 0.58);
	col += vec3(sparks) * vec3(1.0, 0.58, 0.78);
	col += grain;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
