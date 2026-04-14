shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 base_color : source_color = vec4(1.0, 0.94, 0.90, 1.0);
uniform sampler2D albedo_tex : source_color;
uniform bool use_albedo_tex = true;
uniform bool use_alpha_cut = true;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.33;
uniform float albedo_saturation : hint_range(0.0, 2.0) = 1.0;
uniform float albedo_value : hint_range(0.5, 1.5) = 1.03;
uniform float midtone_gamma : hint_range(0.5, 1.5) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.98;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular_level : hint_range(0.0, 1.0) = 0.0;
uniform float reflection_reduction : hint_range(0.0, 1.0) = 1.0;
uniform bool use_ao = false;
uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.0;
uniform bool use_normal_map = false;
uniform sampler2D normal_tex : hint_normal;
uniform float normal_scale : hint_range(0.0, 4.0) = 1.0;

uniform float skin_profile : hint_range(0.0, 1.0) = 1.0;
uniform float cloth_profile : hint_range(0.0, 1.0) = 0.0;
uniform float toon_strength : hint_range(0.0, 1.0) = 0.0;
uniform float band_count : hint_range(2.0, 8.0) = 4.0;
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float shadow_softness : hint_range(0.0, 0.5) = 0.28;
uniform vec3 shadow_tint : source_color = vec3(0.87, 0.80, 0.77);
uniform float wrap_light : hint_range(0.0, 1.0) = 0.12;
uniform float ambient_lift : hint_range(0.0, 0.25) = 0.015;
uniform float light_compress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 skin_scatter_tint : source_color = vec3(1.0, 0.62, 0.52);
uniform float skin_scatter_strength : hint_range(0.0, 1.0) = 0.0;
uniform float skin_scatter_power : hint_range(0.5, 8.0) = 2.0;
uniform vec3 skin_subdermal_tint : source_color = vec3(1.0, 0.5, 0.43);
uniform float skin_subdermal_strength : hint_range(0.0, 1.0) = 0.0;
uniform float face_normal_flatten : hint_range(0.0, 1.0) = 0.03;
uniform float skin_shadow_soften : hint_range(0.0, 1.0) = 0.0;
uniform float skin_specular_strength : hint_range(0.0, 1.0) = 0.0;

uniform float cloth_weave_scale : hint_range(1.0, 260.0) = 120.0;
uniform float cloth_weave_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cloth_roughness_boost : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cloth_sheen_tint : source_color = vec3(1.0);
uniform float cloth_sheen_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cloth_sheen_power : hint_range(0.1, 8.0) = 1.0;
uniform vec3 highlight_color : source_color = vec3(1.0);
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.0;
uniform float highlight_threshold : hint_range(0.0, 1.0) = 1.0;
uniform float highlight_softness : hint_range(0.0, 1.0) = 0.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
uniform float rim_power : hint_range(0.1, 8.0) = 1.0;
uniform float rim_threshold : hint_range(0.0, 1.0) = 1.0;
uniform float rim_softness : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(1.0);

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

	ALBEDO = clamp(pow(max(color, vec3(0.0)), vec3(midtone_gamma)), 0.0, 1.0);
	METALLIC = 0.0;
	ROUGHNESS = clamp(roughness, 0.94, 1.0);
	SPECULAR = 0.0;
	EMISSION = vec3(0.0);

	if (use_normal_map) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}

void light() {
	vec3 n = normalize(mix(NORMAL, VIEW, face_normal_flatten * skin_profile));
	vec3 l = normalize(LIGHT);

	float ndl = dot(n, l);
	float wrapped = clamp((ndl + wrap_light) / (1.0 + wrap_light), 0.0, 1.0);
	float visibility = smoothstep(-0.04, 0.12, ndl);
	float softness = max(shadow_softness, 0.001);
	float shadow = smoothstep(
		shadow_threshold - softness,
		shadow_threshold + softness,
		wrapped
	);

	vec3 diffuse_col = ALBEDO * mix(shadow_tint, vec3(1.0), shadow);
	float atten = ATTENUATION * visibility;
	DIFFUSE_LIGHT += diffuse_col * LIGHT_COLOR * atten;
}
