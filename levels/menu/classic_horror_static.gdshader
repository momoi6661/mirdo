shader_type canvas_item;

uniform float snow_strength : hint_range(0.0, 1.0) = 0.34;
uniform float big_noise_strength : hint_range(0.0, 1.0) = 0.18;
uniform float horizontal_tear_strength : hint_range(0.0, 1.0) = 0.20;
uniform float green_tint : hint_range(0.0, 1.0) = 0.26;
uniform float red_tint : hint_range(0.0, 1.0) = 0.10;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.72;
uniform float silhouette_strength : hint_range(0.0, 1.0) = 0.24;
uniform float flicker_speed : hint_range(0.0, 20.0) = 8.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
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
	float t = TIME * flicker_speed;
	float row_jitter = hash(vec2(floor(uv.y * 180.0), floor(t))) - 0.5;
	float tear = step(0.985, hash(vec2(floor(uv.y * 95.0), floor(t * 0.42)))) * horizontal_tear_strength;
	vec2 noisy_uv = uv + vec2(row_jitter * 0.010 * horizontal_tear_strength + tear * 0.025, 0.0);

	float fine = hash(floor((noisy_uv + vec2(TIME * 0.11, TIME * -0.07)) * vec2(760.0, 430.0)));
	float coarse = noise(noisy_uv * vec2(95.0, 55.0) + vec2(TIME * 3.0, -TIME * 2.0));
	float snow = smoothstep(1.0 - snow_strength, 1.0, fine) * 0.78;
	snow += (coarse - 0.5) * big_noise_strength;

	float bands = smoothstep(0.82, 1.0, hash(vec2(floor(uv.y * 42.0), floor(t * 0.25)))) * 0.14;
	float face_shape = 1.0 - smoothstep(0.20, 0.42, distance(uv, vec2(0.30, 0.39)));
	face_shape *= smoothstep(0.78, 0.30, uv.y);
	float shoulder = 1.0 - smoothstep(0.18, 0.52, distance(uv, vec2(0.36, 0.76)));
	float silhouette = max(face_shape, shoulder * 0.55) * silhouette_strength;

	float vignette = smoothstep(0.22, 0.86, distance(uv, vec2(0.45, 0.50))) * vignette_strength;
	vec3 tint = vec3(0.20 * green_tint, 0.34 * green_tint, 0.24 * green_tint) + vec3(0.36 * red_tint, 0.02 * red_tint, 0.015 * red_tint);
	vec3 snow_color = vec3(snow) * (0.55 + green_tint * 0.55) + tint;
	vec3 dark = vec3(0.0) * vignette;
	vec3 silhouette_color = vec3(0.0, 0.012, 0.007) * silhouette;
	vec3 color = max(snow_color - vignette * 0.35 - silhouette * 0.42, vec3(0.0)) + silhouette_color + bands;
	float alpha = clamp(0.18 + snow_strength * 0.40 + vignette * 0.38 + silhouette * 0.30 + bands * 0.45, 0.0, 0.82);
	COLOR = vec4(color + dark, alpha);
}
