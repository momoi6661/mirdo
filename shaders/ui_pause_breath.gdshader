shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint : source_color = vec4(1.0, 0.28, 0.58, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.16;
uniform float scan_strength : hint_range(0.0, 0.2) = 0.025;
uniform float motion_speed : hint_range(0.0, 2.0) = 0.32;
uniform float progress : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float time = TIME * motion_speed;
	float radial = 1.0 - smoothstep(0.16, 0.78, distance(uv, vec2(0.5, 0.48)));
	float breath = 0.5 + 0.5 * sin(time * 2.0 + uv.x * 2.2);
	float sweep = 0.5 + 0.5 * sin((uv.x * 1.7 + uv.y * 0.32) * 6.2831 + time * 2.4);
	float scan = 0.5 + 0.5 * sin(uv.y * 820.0 + TIME * 1.8);
	float grain = hash21(floor(uv * vec2(420.0, 240.0)) + floor(TIME * 2.0)) - 0.5;
	vec3 color = tint.rgb * (0.42 + 0.34 * sweep + 0.12 * breath);
	float alpha = (strength * radial * (0.26 + 0.74 * breath) + scan * scan_strength * radial) * progress;
	alpha += grain * 0.012 * radial;
	COLOR = vec4(color, max(alpha, 0.0));
}
