shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform vec4 outline_color : source_color = vec4(1.0, 0.78, 0.22, 0.95);
uniform float outline_width : hint_range(0.0, 0.20, 0.001) = 0.035;
uniform float glow_strength : hint_range(0.0, 8.0, 0.05) = 1.4;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * glow_strength;
	ALPHA = outline_color.a;
}
