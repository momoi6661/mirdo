shader_type spatial;

// Object-level Mita-like world shader.
// This does NOT recolor the screen. It reshapes how each world mesh is lit:
// preserved clean albedo, capped whites, stepped lamp/shadow bands, and real shadow maps.
render_mode cull_disabled, depth_prepass_alpha, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = true;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.001) = 0.02;

uniform vec4 warm_light_color : source_color = vec4(1.0, 0.90, 0.80, 1.0);
uniform vec4 cool_shadow_color : source_color = vec4(0.58, 0.54, 0.66, 1.0);
uniform vec4 cream_highlight_color : source_color = vec4(0.90, 0.84, 0.76, 1.0);

uniform float texture_smoothing : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float color_steps : hint_range(2.0, 16.0, 1.0) = 8.0;
uniform float flatness : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform float warmth : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 0.96;
uniform float value_boost : hint_range(0.2, 2.0, 0.01) = 0.96;

uniform float shadow_cleanliness : hint_range(0.0, 1.0, 0.01) = 0.50;
uniform float shadow_floor : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float light_wrap : hint_range(0.0, 1.0, 0.01) = 0.20;
uniform float shade_threshold : hint_range(0.0, 1.0, 0.01) = 0.43;
uniform float shade_softness : hint_range(0.001, 0.6, 0.001) = 0.10;
uniform float light_contribution : hint_range(0.0, 2.0, 0.01) = 0.82;
uniform float ambient_lift : hint_range(0.0, 1.0, 0.01) = 0.02;

uniform float highlight_compress : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float highlight_start : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform float highlight_ceiling : hint_range(0.45, 1.0, 0.01) = 0.82;
uniform float rough_clean_surface : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float form_shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float shadow_receive_strength : hint_range(0.0, 1.0, 0.01) = 0.92;
uniform float self_lit_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_softness : hint_range(0.0, 1.0, 0.01) = 0.35;

varying vec3 world_normal;

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
	vec2 texel = max(fwidth(uv), vec2(0.0007));
	vec4 blur = center * 0.52;
	blur += texture(albedo_texture, uv + vec2(texel.x, 0.0)) * 0.12;
	blur += texture(albedo_texture, uv - vec2(texel.x, 0.0)) * 0.12;
	blur += texture(albedo_texture, uv + vec2(0.0, texel.y)) * 0.12;
	blur += texture(albedo_texture, uv - vec2(0.0, texel.y)) * 0.12;
	return mix(center, blur, texture_smoothing);
}

vec3 cap_high_luma(vec3 c) {
	float lum = max(luma_of(c), 0.001);
	float high = smoothstep(highlight_start, 1.0, lum);
	float capped_lum = min(lum, highlight_ceiling);
	vec3 capped = c * (capped_lum / lum);
	vec3 creamy = mix(capped, cream_highlight_color.rgb, high * 0.18);
	return mix(c, creamy, high * highlight_compress);
}

vec3 clean_base_color(vec3 c) {
	c = apply_saturation(c, saturation);
	c = quantize_soft(c, color_steps, flatness * 0.35);
	c = mix(c, c * warm_light_color.rgb, warmth * 0.22);
	c = cap_high_luma(c);
	return clamp(c * value_boost, vec3(0.0), vec3(1.0));
}

float form_shadow(vec3 n) {
	// Mita-like rooms are clean, but large vertical planes still need volume.
	// Vertical and downward-facing surfaces receive a stable object-space shade,
	// so white cabinets stop becoming flat white cards.
	float vertical = 1.0 - abs(n.y);
	float downward = smoothstep(0.05, -0.45, n.y);
	float side_shade = vertical * 0.65 + downward * 0.55;
	return mix(1.0, 0.70, clamp(side_shade, 0.0, 1.0) * form_shadow_strength);
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 tex = vec4(1.0);
	if (use_texture) {
		tex = sample_smoothed_albedo(UV);
	}
	vec4 src = tex * base_color;
	vec3 cleaned = clean_base_color(src.rgb);
	cleaned *= form_shadow(normalize(world_normal));

	ALBEDO = cleaned;
	ALPHA = src.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = rough_clean_surface;
	SPECULAR = 0.0;
	AO = mix(1.0, 0.82, form_shadow_strength * 0.35);
	AO_LIGHT_AFFECT = 0.35;
	EMISSION = cleaned * self_lit_amount + cleaned * ambient_lift * 0.08;
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndotl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	float shadowed_atten = mix(1.0, ATTENUATION, shadow_receive_strength);
	float lit = wrapped * shadowed_atten;

	float soft_band = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, lit);
	float hard_band = step(shade_threshold, lit);
	float band = mix(soft_band, hard_band, shadow_cleanliness * 0.45);
	float upper_band = smoothstep(0.70, 0.94, lit);

	float toon_light = mix(shadow_floor, 0.76, band);
	toon_light = mix(toon_light, 1.0, upper_band * 0.55);

	vec3 shade_tint = mix(cool_shadow_color.rgb, warm_light_color.rgb, band);
	float bright = smoothstep(highlight_start, 1.0, luma_of(ALBEDO));
	shade_tint = mix(shade_tint, cream_highlight_color.rgb, bright * 0.10);

	DIFFUSE_LIGHT += ALBEDO * shade_tint * LIGHT_COLOR * toon_light * light_contribution / PI;
}
