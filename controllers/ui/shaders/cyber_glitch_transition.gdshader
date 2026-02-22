shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// 终端深色背景：极其厚重，让游戏画面难以看清，完美凸显 UI
uniform vec4 bg_color : source_color = vec4(0.015, 0.015, 0.018, 0.96);

// 伪随机数生成器 (用于生成科技感噪点和区块)
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void fragment() {
    // ---------------------------------------------------------
    // 1. 扭曲强度控制 (Glitch Intensity)
    // 动画中间(0.5)时扭曲最剧烈，两端(0和1)时恢复平静
    // ---------------------------------------------------------
    float glitch_intensity = sin(progress * 3.14159265);
    
    // ---------------------------------------------------------
    // 2. 屏幕横向信号撕裂 (Glitch Tearing)
    // ---------------------------------------------------------
    float strip_y = floor(UV.y * 60.0); // 将屏幕横向切割为 60 条
    // 基于时间、条带位置和扭曲强度计算随机水平偏移
    float strip_offset = (random(vec2(strip_y, TIME)) - 0.5) * 0.15 * glitch_intensity;
    
    vec2 distorted_uv = SCREEN_UV + vec2(strip_offset, 0.0);
    
    // ---------------------------------------------------------
    // 3. 色彩分离 (Chromatic Aberration) 模拟屏幕故障
    // ---------------------------------------------------------
    float color_shift = 0.04 * glitch_intensity * random(vec2(TIME, UV.y));
    float r = textureLod(SCREEN_TEXTURE, distorted_uv + vec2(color_shift, 0.0), 0.0).r;
    float g = textureLod(SCREEN_TEXTURE, distorted_uv, 0.0).g;
    float b = textureLod(SCREEN_TEXTURE, distorted_uv - vec2(color_shift, 0.0), 0.0).b;
    
    vec4 screen_color = vec4(r, g, b, 1.0);
    
    // 加入数字雪花噪点 (Digital Static Noise)
    float noise = random(UV + TIME) * glitch_intensity;
    screen_color.rgb += vec3(noise * 0.25);
    
    // ---------------------------------------------------------
    // 4. 计算目标背景 (暂停状态下的极暗背景)
    // ---------------------------------------------------------
    vec4 target_bg = mix(screen_color, bg_color, bg_color.a);
    // 在最终背景上叠加非常细微的终端水平条纹，增加质感
    float scanline = sin(UV.y * 1200.0) * 0.015;
    target_bg.rgb -= scanline;
    
    // ---------------------------------------------------------
    // 5. 核心：无透明度渐变的硬切过渡 (Digital Block Wipe)
    // ---------------------------------------------------------
    // 生成基于大区块和横向条纹的混合阈值图 (看起来像数字解码)
    float block_thresh = random(vec2(floor(UV.x * 30.0), floor(UV.y * 30.0)));
    float line_thresh = random(vec2(strip_y, 1.0));
    float combined_thresh = (block_thresh * 0.3 + line_thresh * 0.7);
    
    // step 函数实现“非0即1”的硬切！
    // 如果进度(progress)超过了该像素区块的随机阈值，瞬间变为目标背景
    float step_val = step(combined_thresh, progress);
    
    // 为了防止在开头或结尾有残留噪点，做边界净化
    if (progress < 0.02) step_val = 0.0;
    if (progress > 0.98) step_val = 1.0;
    
    // 根据硬切阈值混合原画面和暗背景（这里没有任何整体 alpha 透明度变化！）
    vec4 final_color = mix(screen_color, target_bg, step_val);
    
    // ---------------------------------------------------------
    // 6. 过渡边缘的科技电流特效
    // ---------------------------------------------------------
    // 找出刚刚好处于“正在切换边缘”的像素块，赋予高亮颜色 (匹配你的橘红 UI Color(0.9, 0.3, 0.05))
    float edge = step(combined_thresh, progress + 0.08) - step_val;
    final_color.rgb += vec3(0.9, 0.3, 0.05) * edge * glitch_intensity * 1.5;

    // 输出最终颜色，固定不透明度
    COLOR = vec4(final_color.rgb, 1.0);
    
    // 仅在进度完全归零（未暂停）时隐藏 Shader 以允许点击游戏内容
    if (progress == 0.0) {
        COLOR.a = 0.0;
    }
}
