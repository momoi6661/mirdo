shader_type spatial;

// Current anime_toon occluded visibility pass.
// Draws only an outer anime x-ray outline where the normal character stencil is missing.
render_mode unshaded, blend_mix, cull_front, depth_draw_never, depth_test_inverted, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform vec4 outline_color : source_color = vec4(0.78, 0.55, 1.0, 0.78);
uniform float outline_width : hint_range(0.0, 0.04, 0.0005) = 0.006;
uniform float alpha : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform float pulse_strength : hint_range(0.0, 0.4, 0.01) = 0.04;
uniform float emission_strength : hint_range(0.0, 2.0, 0.01) = 0.35;
uniform float depth_offset : hint_range(-0.02, 0.02, 0.0005) = -0.001;
uniform float radial_blend : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float min_direction_length : hint_range(0.0001, 0.1, 0.0001) = 0.002;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 center_view_pos = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	vec2 normal_dir = view_normal.xy;
	vec2 radial_dir = view_pos.xy - center_view_pos.xy;
	if (length(normal_dir) < min_direction_length) {
		normal_dir = radial_dir;
	}
	if (length(radial_dir) < min_direction_length) {
		radial_dir = normal_dir;
	}
	vec2 offset_dir = mix(normalize(normal_dir), normalize(radial_dir), radial_blend);
	if (length(offset_dir) < min_direction_length) {
		offset_dir = vec2(0.0, 1.0);
	}
	offset_dir = normalize(offset_dir);

	POSITION = PROJECTION_MATRIX * view_pos;
	POSITION.xy += offset_dir * outline_width * POSITION.w;
	POSITION.z += depth_offset * POSITION.w;
}

void fragment() {
	float pulse = 1.0 + sin(TIME * 2.2) * pulse_strength;
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * emission_strength * pulse;
	ALPHA = outline_color.a * alpha * pulse;
}
