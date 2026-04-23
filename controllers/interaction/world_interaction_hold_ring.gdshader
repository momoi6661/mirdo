shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, fog_disabled;

uniform vec4 ring_color : source_color = vec4(1.0, 0.56, 0.82, 0.45);
uniform vec4 fill_color : source_color = vec4(1.0, 0.88, 0.95, 0.95);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.58;
uniform float outer_radius : hint_range(0.0, 1.2) = 0.90;
uniform float edge_softness : hint_range(0.001, 0.2) = 0.035;
uniform float alpha_scale : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 centered_uv = UV * 2.0 - vec2(1.0);
	float radius = length(centered_uv);

	float outer_mask = smoothstep(outer_radius + edge_softness, outer_radius, radius);
	float inner_mask = 1.0 - smoothstep(inner_radius, inner_radius + edge_softness, radius);
	float ring_mask = clamp(outer_mask * inner_mask, 0.0, 1.0);
	if (ring_mask <= 0.0001) {
		discard;
	}

	float angle = atan(centered_uv.y, centered_uv.x);
	float normalized_clockwise = fract(0.25 - angle / (2.0 * PI));
	float fill_enabled = step(0.0001, progress);
	float fill_mask = fill_enabled * step(normalized_clockwise, progress);

	vec4 color = mix(ring_color, fill_color, fill_mask);
	float alpha = color.a * ring_mask * alpha_scale;
	if (alpha <= 0.0001) {
		discard;
	}

	ALBEDO = color.rgb;
	ALPHA = alpha;
	EMISSION = color.rgb * 0.4;
}
