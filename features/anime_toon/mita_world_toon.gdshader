shader_type spatial;

// Mita-like world shader: clean anime-room rendering for props/architecture.
// It is intentionally flatter than PBR: texture detail is softened, shadows are lifted,
// highlights are compressed, and lighting is wrapped so rooms feel warm and tidy.
render_mode cull_disabled, depth_prepass_alpha, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = true;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.001) = 0.02;

uniform vec4 warm_light_color : source_color = vec4(1.0, 0.88, 0.84, 1.0);
uniform vec4 cool_shadow_color : source_color = vec4(0.78, 0.70, 0.80, 1.0);
uniform vec4 cream_highlight_color : source_color = vec4(1.0, 0.93, 0.88, 1.0);

uniform float texture_smoothing : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float color_steps : hint_range(2.0, 16.0, 1.0) = 7.0;
uniform float flatness : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform float warmth : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 0.88;
uniform float value_boost : hint_range(0.2, 2.0, 0.01) = 1.06;

uniform float shadow_cleanliness : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float shadow_floor : hint_range(0.0, 1.0, 0.01) = 0.66;
uniform float light_wrap : hint_range(0.0, 1.0, 0.01) = 0.58;
uniform float shade_threshold : hint_range(0.0, 1.0, 0.01) = 0.36;
uniform float shade_softness : hint_range(0.001, 0.6, 0.001) = 0.22;
uniform float light_contribution : hint_range(0.0, 2.0, 0.01) = 0.62;
uniform float ambient_lift : hint_range(0.0, 1.0, 0.01) = 0.24;

uniform float highlight_compress : hint_range(0.0, 1.0, 0.01) = 0.46;
uniform float highlight_start : hint_range(0.0, 1.0, 0.01) = 0.68;
uniform float rough_clean_surface : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float edge_softness : hint_range(0.0, 1.0, 0.01) = 0.55;

float luma_of(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 apply_saturation(vec3 c, float amount) {
	float l = luma_of(c);
	return mix(vec3(l), c, amount);
}

vec3 quantize_soft(vec3 c, float steps, float amount) {
	vec3 q = floor(c * steps + 0.5) / steps;
	return mix(c, q, amount);
}

vec4 sample_smoothed_albedo(vec2 uv) {
	vec4 center = texture(albedo_texture, uv);
	vec2 texel = vec2(0.0012);
	// Small cross blur in UV space. This is deliberate: low-poly/PBR texture noise becomes
	// soft poster-like color fields without needing screen-space blur.
	vec4 blur = center * 0.44;
	blur += texture(albedo_texture, uv + vec2(texel.x, 0.0)) * 0.14;
	blur += texture(albedo_texture, uv - vec2(texel.x, 0.0)) * 0.14;
	blur += texture(albedo_texture, uv + vec2(0.0, texel.y)) * 0.14;
	blur += texture(albedo_texture, uv - vec2(0.0, texel.y)) * 0.14;
	return mix(center, blur, texture_smoothing);
}

vec3 clean_base_color(vec3 c) {
	c = apply_saturation(c, saturation);
	c = quantize_soft(c, color_steps, flatness * 0.45);
	float lum = luma_of(c);
	vec3 warm = mix(c, c * warm_light_color.rgb, warmth);
	vec3 creamy = mix(warm, cream_highlight_color.rgb, smoothstep(0.72, 1.0, lum) * highlight_compress * 0.28);
	vec3 shadow_lifted = mix(creamy, cool_shadow_color.rgb, (1.0 - lum) * shadow_cleanliness * 0.20);
	return clamp(shadow_lifted * value_boost, vec3(0.0), vec3(1.0));
}

void fragment() {
	vec4 tex = vec4(1.0);
	if (use_texture) {
		tex = sample_smoothed_albedo(UV);
	}
	vec4 src = tex * base_color;
	vec3 cleaned = clean_base_color(src.rgb);
	ALBEDO = cleaned;
	ALPHA = src.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;

	float bright = smoothstep(highlight_start, 1.0, luma_of(cleaned));
	EMISSION = cleaned * warm_light_color.rgb * ambient_lift * mix(1.0, 0.55, bright);
	ROUGHNESS = rough_clean_surface;
	SPECULAR = 0.0;
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndotl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	float attenuated = wrapped * ATTENUATION;
	float band = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, attenuated);

	float lifted_shadow = mix(0.35, shadow_floor, shadow_cleanliness);
	float toon_light = mix(lifted_shadow, 1.0, band);
	toon_light = mix(toon_light, 0.86, flatness * 0.22);

	vec3 shade_tint = mix(cool_shadow_color.rgb, warm_light_color.rgb, band * 0.55);
	vec3 light_tint = mix(shade_tint, warm_light_color.rgb, toon_light);
	float bright = smoothstep(highlight_start, 1.0, luma_of(ALBEDO));
	light_tint = mix(light_tint, cream_highlight_color.rgb, bright * highlight_compress * 0.35);

	DIFFUSE_LIGHT += ALBEDO * light_tint * LIGHT_COLOR * toon_light * light_contribution / PI;
}
