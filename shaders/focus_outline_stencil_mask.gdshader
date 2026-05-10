shader_type spatial;
render_mode unshaded, depth_draw_opaque, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 1;

void fragment() {
	ALPHA = 0.0;
}
