shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

uniform vec4 fill_color : source_color = vec4(0.22, 0.18, 0.32, 0.55);
uniform vec4 fill_color_2 : source_color = vec4(0.30, 0.24, 0.44, 0.55);
uniform vec4 outline_color : source_color = vec4(0.92, 0.85, 1.0, 0.9);
uniform vec4 glow_color : source_color = vec4(0.92, 0.84, 1.0, 0.35);
uniform float corner_radius : hint_range(0.0, 0.49) = 0.14;
uniform float outline_width : hint_range(0.0, 0.2) = 0.035;
uniform float feather : hint_range(0.0005, 0.08) = 0.01;
uniform float glow_width : hint_range(0.0, 0.25) = 0.05;
uniform float opacity_scale : hint_range(0.0, 2.0) = 1.0;
uniform float vertical_gradient_strength : hint_range(0.0, 1.0) = 0.32;

float rounded_rect_sdf(vec2 uv, float radius) {
	vec2 p = uv - vec2(0.5);
	vec2 b = vec2(0.5 - radius);
	vec2 q = abs(p) - b;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	float radius = clamp(corner_radius, 0.0, 0.49);
	float dist = rounded_rect_sdf(UV, radius);

	float fill_mask = smoothstep(feather, -feather, dist);
	float inner_mask = smoothstep(feather, -feather, dist + outline_width);
	float border_mask = clamp(fill_mask - inner_mask, 0.0, 1.0);

	float glow_outer = smoothstep(glow_width + feather, -feather, dist);
	float glow_mask = clamp(glow_outer - fill_mask, 0.0, 1.0);

	float grad_t = clamp(UV.y * (1.0 + vertical_gradient_strength), 0.0, 1.0);
	vec4 fill_mix = mix(fill_color_2, fill_color, grad_t);

	vec3 rgb = mix(fill_mix.rgb, outline_color.rgb, border_mask);
	rgb = mix(rgb, glow_color.rgb, glow_mask * glow_color.a);

	float alpha = fill_mix.a * fill_mask;
	alpha += outline_color.a * border_mask;
	alpha += glow_color.a * glow_mask;
	alpha *= opacity_scale;

	ALBEDO = rgb;
	EMISSION = rgb * (border_mask * 0.55 + glow_mask * 0.70);
	ALPHA = alpha;
}
