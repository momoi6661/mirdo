shader_type spatial;

// Softer world outline than character outlines. It gives clean readable silhouettes
// without turning furniture/walls into heavy comic ink.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.18, 0.12, 0.15, 0.48);
uniform float outline_width : hint_range(0.0, 0.02, 0.0001) = 0.0014;
uniform float normal_smooth_blend : hint_range(0.0, 1.0, 0.01) = 0.88;
uniform float min_direction_length : hint_range(0.0001, 0.1, 0.0001) = 0.002;
uniform float distance_fade_start = 2.0;
uniform float distance_fade_end = 20.0;
uniform float alpha : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform float vertical_edge_bias : hint_range(0.0, 1.0, 0.01) = 0.25;

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
	vec2 offset_dir = mix(normalize(normal_dir), normalize(radial_dir), normal_smooth_blend);
	offset_dir.y = mix(offset_dir.y, offset_dir.y * 0.75, vertical_edge_bias);
	if (length(offset_dir) < min_direction_length) {
		offset_dir = vec2(0.0, 1.0);
	}
	offset_dir = normalize(offset_dir);

	float view_dist = length(view_pos.xyz);
	float fade = 1.0 - smoothstep(distance_fade_start, distance_fade_end, view_dist);
	float final_width = outline_width * max(fade, 0.25);
	vec4 clip_pos = PROJECTION_MATRIX * view_pos;
	clip_pos.xy += offset_dir * final_width * clip_pos.w;
	POSITION = clip_pos;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * alpha;
}
