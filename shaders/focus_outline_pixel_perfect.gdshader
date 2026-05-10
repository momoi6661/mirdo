shader_type spatial;
render_mode cull_front, unshaded, blend_mix, depth_test_default, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform vec4 outline_color : source_color = vec4(1.0, 0.78, 0.22, 0.95);
uniform float outline_width : hint_range(0.0, 12.0, 0.25) = 3.0;

void vertex() {
	vec4 clip_position = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);
	float normal_len = length(clip_normal.xy);
	if (normal_len > 0.0001) {
		vec2 offset = clip_normal.xy / normal_len / VIEWPORT_SIZE * clip_position.w * outline_width * 2.0;
		clip_position.xy += offset;
	}
	POSITION = clip_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
