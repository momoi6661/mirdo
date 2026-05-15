shader_type spatial;

// Inverted-hull anime outline with shader-side normal smoothing.
// Instead of pushing only along raw mesh NORMAL, it offsets in clip space using a
// blend of view-space normal and object-radial direction. This reduces cracks on
// hard normals, UV seams, and separated anime hair/clothing cards.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.055, 0.043, 0.055, 1.0);

// Screen-relative width. Smaller values are safer for anime hair/card meshes.
uniform float outline_width : hint_range(0.0, 0.02, 0.0001) = 0.0035;

// 0 = original mesh normal direction, 1 = radial direction from object center in screen/view space.
// Higher values reduce split outlines caused by hard/split normals.
uniform float normal_smooth_blend : hint_range(0.0, 1.0, 0.01) = 0.65;

// Prevent huge offsets when projected normal is almost zero.
uniform float min_direction_length : hint_range(0.0001, 0.1, 0.0001) = 0.002;

uniform float distance_fade_start = 4.0;
uniform float distance_fade_end = 18.0;
uniform float alpha : hint_range(0.0, 1.0, 0.01) = 1.0;

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
	if (length(offset_dir) < min_direction_length) {
		offset_dir = vec2(0.0, 1.0);
	}
	offset_dir = normalize(offset_dir);

	float view_dist = length(view_pos.xyz);
	float fade = 1.0 - smoothstep(distance_fade_start, distance_fade_end, view_dist);
	float final_width = outline_width * max(fade, 0.35);

	vec4 clip_pos = PROJECTION_MATRIX * view_pos;
	clip_pos.xy += offset_dir * final_width * clip_pos.w;
	POSITION = clip_pos;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * alpha;
}
