shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

// --- 基础贴图与颜色 ---
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;

// --- 卡通着色参数 ---
// 控制阴影的软硬程度（数值越小边缘越硬，典型的二次元赛璐璐风格通常在 0.01 - 0.05 之间）
uniform float shadow_softness : hint_range(0.0, 1.0) = 0.02;
// 控制受光面和背光面的颜色过渡阈值
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5;
// 阴影区域的颜色乘数（让阴影不只是变黑，而是带有特定的色调，比如偏蓝或偏紫）
uniform vec4 shadow_color : source_color = vec4(0.7, 0.7, 0.75, 1.0);

// --- 高光参数 ---
uniform float specular_size : hint_range(0.0, 1.0) = 0.1;
uniform float specular_softness : hint_range(0.0, 1.0) = 0.01;
uniform vec4 specular_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	// 顶点着色器部分保持默认
}

void fragment() {
	// 基础颜色采样
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	
	// 降低金属度和粗糙度的影响，因为我们要手动控制光照
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	// 计算光照方向和法线的点积 (N dot L)
	float NdotL = dot(NORMAL, LIGHT);
	
	// --- 漫反射 (卡通阴影) ---
	// 使用 smoothstep 创建硬边缘阴影
	// DIFFUSE_LIGHT 会受到 ATTENUATION (阴影衰减) 的影响
	float shadow_value = smoothstep(shadow_threshold - shadow_softness, shadow_threshold + shadow_softness, NdotL * ATTENUATION);
	
	// 混合受光颜色和阴影颜色
	vec3 diffuse_shading = mix(ALBEDO * shadow_color.rgb, ALBEDO * LIGHT_COLOR, shadow_value);
	DIFFUSE_LIGHT += diffuse_shading;

	// --- 高光 (卡通高光) ---
	// 计算半角向量 (Half Vector)
	vec3 H = normalize(VIEW + LIGHT);
	float NdotH = max(0.0, dot(NORMAL, H));
	
	// 创建高光硬边缘
	float specular_value = smoothstep(1.0 - specular_size - specular_softness, 1.0 - specular_size + specular_softness, NdotH);
	
	// 只有在受光面才显示高光
	specular_value *= shadow_value;
	
	SPECULAR_LIGHT += specular_color.rgb * LIGHT_COLOR * specular_value;
}
