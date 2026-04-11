shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

group_uniforms Base;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = true;
uniform bool use_alpha_cut = true;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.35;

group_uniforms Tone;
uniform float albedo_saturation : hint_range(0.0, 2.0) = 1.08;
uniform float albedo_value : hint_range(0.5, 1.6) = 1.03;
uniform float midtone_gamma : hint_range(0.7, 1.3) = 0.94;

group_uniforms Surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.62;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular_level : hint_range(0.0, 2.0) = 0.30;
uniform float reflection_reduction : hint_range(0.0, 1.0) = 0.45;
uniform bool use_ao = false;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.42;
uniform bool use_normal_map = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(0.0, 4.0) = 1.0;

group_uniforms MaterialClass;
uniform float skin_profile : hint_range(0.0, 1.0) = 0.0;
uniform float cloth_profile : hint_range(0.0, 1.0) = 0.0;

group_uniforms Anime;
uniform float toon_strength : hint_range(0.0, 1.0) = 0.50;
uniform float band_count : hint_range(2.0, 8.0) = 4.0;
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.52;
uniform float shadow_softness : hint_range(0.001, 0.5) = 0.15;
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.58, 0.56);
uniform float wrap_light : hint_range(0.0, 1.0) = 0.14;
uniform float ambient_lift : hint_range(0.0, 1.0) = 0.06;
uniform float light_compress : hint_range(0.0, 1.0) = 0.58;

group_uniforms Skin;
uniform vec3 skin_scatter_tint : source_color = vec3(1.0, 0.54, 0.44);
uniform float skin_scatter_strength : hint_range(0.0, 1.0) = 0.12;
uniform float skin_scatter_power : hint_range(0.5, 8.0) = 2.3;
uniform vec3 skin_subdermal_tint : source_color = vec3(1.0, 0.42, 0.35);
uniform float skin_subdermal_strength : hint_range(0.0, 1.0) = 0.58;

group_uniforms Cloth;
uniform float cloth_weave_scale : hint_range(20.0, 260.0) = 120.0;
uniform float cloth_weave_strength : hint_range(0.0, 0.2) = 0.05;
uniform float cloth_roughness_boost : hint_range(0.0, 0.5) = 0.24;
uniform vec3 cloth_sheen_tint : source_color = vec3(1.0, 0.93, 0.88);
uniform float cloth_sheen_strength : hint_range(0.0, 1.0) = 0.14;
uniform float cloth_sheen_power : hint_range(1.0, 8.0) = 3.2;

group_uniforms Highlights;
uniform vec3 highlight_color : source_color = vec3(1.0, 0.95, 0.90);
uniform float highlight_strength : hint_range(0.0, 2.0) = 0.19;
uniform float highlight_threshold : hint_range(0.0, 1.0) = 0.80;
uniform float highlight_softness : hint_range(0.001, 0.4) = 0.08;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.025;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.68;
uniform float rim_softness : hint_range(0.001, 0.5) = 0.16;
uniform vec3 rim_color : source_color = vec3(1.0, 0.92, 0.88);

void fragment() {
	vec4 tex = use_albedo_tex ? texture(albedo_tex, UV) : vec4(1.0);
	vec4 base = base_color * tex;
	if (use_alpha_cut && base.a < alpha_cutoff) {
		discard;
	}

	vec3 color = base.rgb;
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, albedo_saturation);
	color *= albedo_value;
	ALBEDO = clamp(color, 0.0, 1.0);

	METALLIC = clamp(metallic, 0.0, 1.0);
	ROUGHNESS = clamp(roughness + reflection_reduction * 0.18, 0.05, 1.0);
	SPECULAR = specular_level * (1.0 - reflection_reduction);

	if (use_ao) {
		AO = texture(ao_tex, UV).r;
		AO_LIGHT_AFFECT = ao_light_affect;
	}

	if (use_normal_map) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}

	float cloth_mask = clamp(cloth_profile, 0.0, 1.0);
	if (cloth_mask > 0.001) {
		float sx = sin(UV.x * cloth_weave_scale * 6.2831853);
		float sy = sin(UV.y * cloth_weave_scale * 0.83 * 6.2831853);
		float weave = 0.5 + 0.5 * sx * sy;
		float weave_delta = (weave - 0.5) * 2.0;
		ALBEDO = clamp(ALBEDO * (1.0 + weave_delta * cloth_weave_strength * cloth_mask), 0.0, 1.0);
		ROUGHNESS = clamp(ROUGHNESS + cloth_roughness_boost * cloth_mask + (1.0 - weave) * 0.07 * cloth_mask, 0.05, 1.0);
		SPECULAR = mix(SPECULAR, SPECULAR * 0.55, cloth_mask);
	}
}

void light() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(LIGHT);
	vec3 v = normalize(VIEW);

	float skin_mask = clamp(skin_profile, 0.0, 1.0);
	float cloth_mask = clamp(cloth_profile, 0.0, 1.0);

	float effective_wrap = clamp(wrap_light + 0.10 * skin_mask, 0.0, 1.0);
	float ndl = dot(n, l);
	float wrapped = clamp((ndl + effective_wrap) / (1.0 + effective_wrap), 0.0, 1.0);
	float effective_softness = mix(shadow_softness, min(0.24, shadow_softness * 1.35), skin_mask);
	float smooth_lit = smoothstep(
		shadow_threshold - effective_softness,
		shadow_threshold + effective_softness,
		wrapped
	);

	float bands = max(2.0, band_count);
	float banded_lit = floor(smooth_lit * (bands - 1.0) + 0.5) / (bands - 1.0);
	float toon_mix = toon_strength * mix(1.0, 0.78, skin_mask);
	float lit = mix(smooth_lit, banded_lit, toon_mix);
	float face_fill = pow(1.0 - max(dot(n, v), 0.0), 1.65) * 0.04 * skin_mask;
	lit = clamp(max(lit, ambient_lift + face_fill), 0.0, 1.0);
	float lit_curve = pow(lit, 0.90);

	vec3 diffuse_col = mix(ALBEDO * shadow_tint, ALBEDO, lit_curve);

	float skin_wrap = pow(clamp(1.0 - wrapped, 0.0, 1.0), skin_scatter_power) * skin_scatter_strength * skin_mask;
	float view_forward = pow(clamp(dot(-v, l), 0.0, 1.0), 2.2);
	float subdermal = skin_wrap * (0.35 + 0.65 * view_forward) * skin_subdermal_strength;
	float skin_fres = pow(1.0 - max(dot(n, v), 0.0), 1.8) * skin_mask * skin_scatter_strength * 0.40;
	diffuse_col += ALBEDO * skin_scatter_tint * (skin_wrap + skin_fres);
	diffuse_col += skin_subdermal_tint * subdermal * 0.28;

	vec3 compressed_light = LIGHT_COLOR / (LIGHT_COLOR + vec3(1.0));
	vec3 light_col = mix(LIGHT_COLOR, compressed_light, light_compress);

	vec3 h = normalize(l + v);
	float ndh = max(dot(n, h), 0.0);
	float rough = clamp(ROUGHNESS, 0.0, 1.0);
	float shininess = mix(22.0, 96.0, 1.0 - rough);
	float spec_raw = pow(ndh, shininess);
	float spec_step = smoothstep(
		highlight_threshold - highlight_softness,
		highlight_threshold + highlight_softness,
		spec_raw
	);
	float spec = spec_step * highlight_strength * SPECULAR_AMOUNT;
	spec *= smoothstep(0.14, 0.76, lit);
	spec *= (1.0 - cloth_mask * 0.45);
	spec *= mix(1.0, 0.42, skin_mask);
	spec *= mix(1.0, 0.82, rough);
	spec *= (1.0 - reflection_reduction * 0.55);
	spec *= mix(1.0, 1.0 - reflection_reduction * 0.55, skin_mask);

	float skin_soft_lobe = pow(ndh, mix(6.0, 18.0, 1.0 - rough));
	float skin_soft_spec = skin_soft_lobe * 0.012 * skin_mask * SPECULAR_AMOUNT * smoothstep(0.18, 0.88, lit);
	skin_soft_spec *= (1.0 - reflection_reduction * 0.70);
	spec += skin_soft_spec;

	float cloth_fres = pow(1.0 - max(dot(n, v), 0.0), cloth_sheen_power);
	float cloth_sheen = cloth_fres * cloth_sheen_strength * cloth_mask * smoothstep(0.08, 0.90, lit);
	cloth_sheen *= (1.0 - reflection_reduction * 0.65);
	vec3 cloth_sheen_col = mix(cloth_sheen_tint, ALBEDO, 0.35);

	float rim_raw = pow(1.0 - max(dot(n, v), 0.0), rim_power);
	float rim_step = smoothstep(
		rim_threshold - rim_softness,
		rim_threshold + rim_softness,
		rim_raw
	);
	float rim = rim_step * rim_strength * (0.35 + 0.65 * (1.0 - lit));
	rim *= (1.0 - cloth_mask * 0.60);
	rim *= mix(1.0, 0.60, skin_mask);
	rim *= (1.0 - reflection_reduction * 0.35);

	vec3 diff_final = pow(max(diffuse_col, vec3(0.0)), vec3(midtone_gamma));
	DIFFUSE_LIGHT += diff_final * light_col * ATTENUATION;
	SPECULAR_LIGHT += (highlight_color * spec + rim_color * rim + cloth_sheen_col * cloth_sheen) * light_col * ATTENUATION;
}
