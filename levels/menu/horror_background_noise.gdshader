shader_type canvas_item;

uniform float noise_amount : hint_range(0.0, 0.25) = 0.10;
uniform float vignette_power : hint_range(0.2, 3.0) = 1.15;
uniform float grime_opacity : hint_range(0.0, 1.0) = 0.62;
uniform float red_alarm_strength : hint_range(0.0, 0.5) = 0.16;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float dist = distance(uv, vec2(0.43, 0.50));
	float vignette = smoothstep(0.34, 0.96, dist);
	float grain = hash(floor((uv + vec2(TIME * 0.006, -TIME * 0.003)) * vec2(520.0, 300.0))) - 0.5;
	float grime = value_noise(uv * vec2(8.0, 4.8));
	float stains = smoothstep(0.48, 0.92, grime) * 0.22;
	float right_alarm = smoothstep(0.58, 1.0, uv.x) * (1.0 - smoothstep(0.08, 0.62, uv.y));
	vec3 cold_shadow = vec3(0.0, 0.0, 0.0) * vignette * vignette_power;
	vec3 dirty_brown = vec3(0.10, 0.075, 0.045) * stains;
	vec3 alarm_red = vec3(0.50, 0.035, 0.025) * right_alarm * red_alarm_strength;
	float alpha = clamp(vignette * 0.78 + stains + grime_opacity * 0.18, 0.0, 0.86);
	vec3 color = cold_shadow + dirty_brown + alarm_red + vec3(grain * noise_amount);
	COLOR = vec4(max(color, vec3(0.0)), alpha);
}
