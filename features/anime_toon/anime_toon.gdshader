shader_type spatial;

// Reusable lighting-aware anime toon shader for Godot 4.
// Key idea: keep texture/albedo in fragment(), then quantize real lights in light().
// This uses Godot's LIGHT_COLOR and ATTENUATION, so Directional/Omni/Spot lights affect the character.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = true;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform vec4 shade_color : source_color = vec4(0.58, 0.50, 0.58, 1.0);
uniform float shade_threshold : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float shade_softness : hint_range(0.001, 0.5, 0.001) = 0.06;
uniform float shadow_level : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float light_wrap : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float light_contribution : hint_range(0.0, 2.0, 0.01) = 1.0;

uniform vec4 ambient_color : source_color = vec4(0.72, 0.68, 0.76, 1.0);
uniform float ambient_lift : hint_range(0.0, 1.0, 0.01) = 0.10;

uniform vec4 rim_color : source_color = vec4(0.72, 0.82, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0, 0.01) = 0.10;
uniform float rim_threshold : hint_range(0.0, 1.0, 0.01) = 0.68;
uniform float rim_softness : hint_range(0.001, 0.5, 0.001) = 0.08;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 3.2;

// Anime characters often look bad when pure-white mouth/eye/cloth areas are lit like PBR.
// This softly compresses very bright texels toward a warm off-white without killing all highlights.
uniform float white_compress_start : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float white_compress_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform vec4 white_tint : source_color = vec4(0.86, 0.80, 0.82, 1.0);

uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.001) = 0.02;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 0.94;
uniform float value_boost : hint_range(0.0, 2.0, 0.01) = 0.98;

vec3 apply_saturation(vec3 color, float amount) {
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(gray), color, amount);
}

vec3 compress_white(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	float mask = smoothstep(white_compress_start, 1.0, luma);
	vec3 tinted = mix(color, color * white_tint.rgb, white_compress_strength);
	return mix(color, tinted, mask);
}

void fragment() {
	vec4 tex = vec4(1.0);
	if (use_texture) {
		tex = texture(albedo_texture, UV);
	}

	vec4 src = tex * base_color;
	vec3 albedo = apply_saturation(src.rgb, saturation) * value_boost;
	albedo = compress_white(albedo);
	ALBEDO = albedo;
	ALPHA = src.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;

	// Small fill so the character does not become totally black without direct light.
	// Direct light and shadows still come from light().
	EMISSION = ALBEDO * ambient_color.rgb * ambient_lift;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

float fresnel_term(vec3 normal, vec3 view, float power) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), power);
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndotl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	float attenuated = wrapped * ATTENUATION;

	float band = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, attenuated);
	float toon_light = mix(shadow_level, 1.0, band);
	vec3 toon_tint = mix(shade_color.rgb, vec3(1.0), toon_light);

	DIFFUSE_LIGHT += ALBEDO * toon_tint * LIGHT_COLOR * light_contribution / PI;

	float rim = fresnel_term(NORMAL, VIEW, rim_power);
	rim = smoothstep(rim_threshold, rim_threshold + rim_softness, rim) * band;
	SPECULAR_LIGHT += rim_color.rgb * rim * rim_strength * LIGHT_COLOR / PI;
}
