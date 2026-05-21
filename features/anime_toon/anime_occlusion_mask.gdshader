shader_type spatial;

// Current anime_toon visibility mask pass.
// It only writes the character shape into stencil/depth; visible color is ignored.
render_mode unshaded, depth_draw_opaque, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 1;

void fragment() {
	ALPHA = 0.0;
}
