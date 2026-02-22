shader_type canvas_item;

// 非常纯净、高级的转场渐变着色器
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fade_color : source_color = vec4(0.01, 0.01, 0.015, 1.0); // 深邃的暗色调

void fragment() {
    // 简单的圆形向内坍缩/向外扩张的转场效果，比死板的透明度渐变更具动感
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    
    // 利用 smoothstep 制造一个边缘柔和的遮罩圈
    float mask = smoothstep(1.0 - fade, 1.0 - fade + 0.1, dist * 2.0);
    
    // 当 fade 为 1.0 时全黑，当 fade 为 0.0 时全透明
    COLOR = mix(vec4(0.0), fade_color, mask + fade);
    
    // 确保最终可以完全不透明覆盖
    COLOR.a = clamp(COLOR.a + fade, 0.0, 1.0);
}
