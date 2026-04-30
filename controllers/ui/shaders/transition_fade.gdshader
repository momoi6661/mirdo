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

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv * 2.0 - 1.0;

	float radial = length(centered * vec2(0.90, 1.08));
	float radial_edge = mix(1.72, -0.18, progress);
	float mask_a = 1.0 - smoothstep(radial_edge - softness, radial_edge + softness, radial);

	float sweep_curve = uv.y + abs(uv.x - 0.5) * 0.20 + sin(uv.x * 8.0 + TIME * 0.45) * 0.015;
	float sweep_edge = mix(-0.20, 1.18, progress);
	float mask_b = 1.0 - smoothstep(sweep_edge - softness, sweep_edge + softness, sweep_curve);

	float mask = mix(mask_a, mask_b, preset_b_mix);
	vec4 tint = mix(tint_a, tint_b, preset_b_mix);

	float pulse = 0.5 + 0.5 * sin(TIME * 3.1);
	float pulse_mix = pulse * pulse_strength * 0.02;
	float grain = (hash21(floor((uv + TIME * 0.02) * vec2(720.0, 420.0))) - 0.5) * 2.0;
	float bands = sin((uv.y * 44.0 + uv.x * 10.0) - TIME * 1.25) * 0.5 + 0.5;
	float vignette = 1.0 - smoothstep(0.35, 1.18, radial);

	float alpha = mask;
	alpha += grain * grain_strength * mask;
	alpha += (bands - 0.5) * band_strength * mask * preset_b_mix;
	alpha += pulse_mix * mask;
	alpha = clamp(alpha, 0.0, 1.0);

	vec3 base_rgb = tint.rgb * (1.0 + vignette * vignette_strength * mask);
	float edge_soft = clamp(abs(fwidth(mask)) * 12.0, 0.0, 1.0);
	vec3 final_rgb = base_rgb + vec3(0.02, 0.02, 0.025) * edge_soft * mask * 0.18;

	COLOR = vec4(final_rgb, alpha * tint.a);
}
