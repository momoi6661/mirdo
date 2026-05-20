shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float preset_b_mix : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_a : source_color = vec4(0.015, 0.015, 0.020, 1.0);
uniform vec4 tint_b : source_color = vec4(0.010, 0.010, 0.016, 1.0);
uniform float softness : hint_range(0.001, 0.4) = 0.075;
uniform float edge_width : hint_range(0.001, 0.3) = 0.05;
uniform float grain_strength : hint_range(0.0, 0.1) = 0.008;
uniform float band_strength : hint_range(0.0, 0.2) = 0.012;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.12;
uniform vec4 center_tint : source_color = vec4(0.86, 0.20, 0.52, 1.0);
uniform vec4 side_tint : source_color = vec4(0.42, 0.055, 0.25, 1.0);
uniform float gradient_mix : hint_range(0.0, 1.0) = 1.0;
uniform float spark_strength : hint_range(0.0, 0.5) = 0.12;
uniform float block_strength : hint_range(0.0, 0.5) = 0.10;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float soft_block(vec2 uv, vec2 grid_size, float threshold) {
	vec2 grid = floor(uv * grid_size);
	vec2 cell = fract(uv * grid_size) - 0.5;
	float seed = hash21(grid);
	vec2 drift = vec2(sin(TIME * (0.24 + seed) + seed * 6.28), cos(TIME * (0.20 + seed) + seed * 5.17)) * 0.16;
	vec2 half_size = vec2(0.09 + seed * 0.18, 0.05 + hash21(grid + 9.1) * 0.14);
	vec2 d = abs(cell - drift) - half_size;
	float outside = length(max(d, vec2(0.0)));
	float shape = 1.0 - smoothstep(0.0, 0.08, outside);
	float fade = 0.45 + 0.55 * sin(TIME * (0.95 + seed) + seed * 14.0);
	return shape * step(threshold, seed) * fade;
}

float spark_layer(vec2 uv, vec2 grid_size, float threshold, float radius) {
	vec2 grid = floor(uv * grid_size);
	vec2 local = fract(uv * grid_size) - 0.5;
	float seed = hash21(grid);
	vec2 drift = vec2(sin(TIME * (0.42 + seed) + seed * 6.28), cos(TIME * (0.32 + seed) + seed * 4.12)) * 0.18;
	float d = length(local - drift);
	float twinkle = 0.45 + 0.55 * sin(TIME * (1.0 + seed * 1.6) + seed * 12.0);
	return (1.0 - smoothstep(radius * 0.35, radius, d)) * step(threshold, seed) * twinkle;
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv * 2.0 - 1.0;

	float half_width = mix(0.0, 0.62, progress);
	float center_distance = abs(uv.x - 0.5);
	float mask_a = 1.0 - smoothstep(half_width - softness, half_width + softness, center_distance);

	float sweep_curve = uv.y + abs(uv.x - 0.5) * 0.20 + sin(uv.x * 8.0 + TIME * 0.45) * 0.015;
	float sweep_edge = mix(-0.20, 1.18, progress);
	float mask_b = 1.0 - smoothstep(sweep_edge - softness, sweep_edge + softness, sweep_curve);

	float mask = mix(mask_a, mask_b, preset_b_mix);
	vec4 tint = mix(tint_a, tint_b, preset_b_mix);
	float side = pow(abs(uv.x - 0.5) * 2.0, 1.65);
	vec3 gradient_rgb = mix(center_tint.rgb, side_tint.rgb, side);
	tint.rgb = mix(tint.rgb, gradient_rgb, gradient_mix);
	float breath = 0.5 + 0.5 * sin(TIME * 1.05);
	tint.rgb += center_tint.rgb * (1.0 - side) * breath * 0.075 * gradient_mix;

	float pulse = 0.5 + 0.5 * sin(TIME * 3.1);
	float pulse_mix = pulse * pulse_strength * 0.02;
	float blocks = (soft_block(uv + vec2(TIME * 0.010, -TIME * 0.018), vec2(18.0, 10.0), 0.80) * 0.70
		+ soft_block(uv + vec2(-TIME * 0.016, TIME * 0.010), vec2(32.0, 18.0), 0.90) * 0.45) * block_strength;
	float sparks = (spark_layer(uv + vec2(0.0, -TIME * 0.020), vec2(22.0, 12.0), 0.88, 0.075) * 0.70
		+ spark_layer(uv + vec2(TIME * 0.010, TIME * 0.012), vec2(38.0, 22.0), 0.94, 0.060) * 0.50) * spark_strength;
	float grain = (hash21(floor((uv + TIME * 0.02) * vec2(520.0, 300.0))) - 0.5) * 2.0;
	float bands = sin((uv.y * 44.0 + uv.x * 10.0) - TIME * 1.25) * 0.5 + 0.5;
	float radial = length(centered * vec2(0.90, 1.08));
	float vignette = 1.0 - smoothstep(0.35, 1.18, radial);

	float alpha = mask;
	alpha += grain * grain_strength * mask;
	alpha += (bands - 0.5) * band_strength * mask * preset_b_mix;
	alpha += pulse_mix * mask;
	alpha = clamp(alpha, 0.0, 1.0);

	vec3 base_rgb = tint.rgb * (1.0 + vignette * vignette_strength * mask);
	base_rgb += vec3(blocks) * vec3(0.95, 0.30, 0.58) * mask;
	base_rgb += vec3(sparks) * vec3(1.0, 0.58, 0.78) * mask;
	float edge_soft = clamp(abs(fwidth(mask)) * 12.0, 0.0, 1.0);
	vec3 final_rgb = base_rgb + vec3(0.02, 0.02, 0.025) * edge_soft * mask * 0.18;

	COLOR = vec4(final_rgb, alpha * tint.a);
}
