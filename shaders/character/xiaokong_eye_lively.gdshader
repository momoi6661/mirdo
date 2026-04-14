shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

group_uniforms Base;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = true;
uniform bool use_alpha_cut = true;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.33;

group_uniforms Tone;
uniform float base_saturation : hint_range(0.0, 2.0) = 1.05;
uniform float base_brightness : hint_range(0.5, 1.5) = 1.02;
uniform float soft_light_lift : hint_range(0.0, 0.2) = 0.025;
uniform float iris_saturation : hint_range(0.5, 2.0) = 1.25;
uniform float iris_brightness : hint_range(0.8, 1.5) = 1.10;
uniform float iris_mask_threshold : hint_range(0.0, 0.5) = 0.08;
uniform float iris_mask_softness : hint_range(0.01, 0.5) = 0.22;

group_uniforms Surface;
uniform float eye_roughness : hint_range(0.0, 1.0) = 0.36;
uniform float eye_specular : hint_range(0.0, 1.0) = 0.12;
uniform float overall_glow_strength : hint_range(0.0, 0.2) = 0.0;
uniform float iris_glow_strength : hint_range(0.0, 0.2) = 0.05;
uniform vec3 glow_tint : source_color = vec3(0.92, 0.97, 1.08);
uniform float edge_glance_lift : hint_range(0.0, 0.08) = 0.012;

float get_saturation(vec3 color) {
	float max_c = max(max(color.r, color.g), color.b);
	float min_c = min(min(color.r, color.g), color.b);
	return max_c - min_c;
}

void fragment() {
	vec4 tex = use_albedo_tex ? texture(albedo_tex, UV) : vec4(1.0);
	vec4 base = base_color * tex;
	if (use_alpha_cut && base.a < alpha_cutoff) {
		discard;
	}

	vec3 raw_color = max(base.rgb, vec3(0.0));
	float raw_luma = dot(raw_color, vec3(0.2126, 0.7152, 0.0722));
	float sat = get_saturation(raw_color);
	float darkness = 1.0 - clamp(raw_luma, 0.0, 1.0);

	float iris_mask = smoothstep(
		iris_mask_threshold,
		iris_mask_threshold + iris_mask_softness,
		sat + darkness * 0.18
	);

	vec3 toned = mix(vec3(raw_luma), raw_color, base_saturation);
	toned *= base_brightness;

	float toned_luma = dot(toned, vec3(0.2126, 0.7152, 0.0722));
	vec3 iris_toned = mix(vec3(toned_luma), toned, iris_saturation);
	iris_toned *= iris_brightness;

	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float glance = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);

	vec3 color = mix(toned, iris_toned, iris_mask);
	color += color * soft_light_lift * (0.45 + iris_mask * 0.55);
	color += glow_tint * (iris_mask * glance * edge_glance_lift);

	ALBEDO = clamp(color, 0.0, 1.0);
	METALLIC = 0.0;
	ROUGHNESS = clamp(eye_roughness, 0.02, 1.0);
	SPECULAR = clamp(eye_specular, 0.0, 1.0);
	EMISSION = clamp(
		color * glow_tint * (overall_glow_strength + iris_mask * iris_glow_strength),
		0.0,
		1.0
	);
	ALPHA = base.a;

	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
