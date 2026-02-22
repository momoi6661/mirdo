shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(1.0, 0.8, 0.0, 1.0);
uniform float outline_width : hint_range(0.01, 0.15) = 0.08;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	vec3 view_dir = normalize(VIEW);
	float rim = 1.0 - abs(dot(NORMAL, view_dir));
	float alpha = smoothstep(0.3, 0.7, rim);
	ALPHA = alpha * outline_color.a;
	ALBEDO = outline_color.rgb;
}
