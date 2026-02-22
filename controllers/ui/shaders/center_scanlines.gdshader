shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float density : hint_range(0.0, 200.0) = 40.0;
uniform float speed : hint_range(0.0, 5.0) = 0.8;
uniform vec4 line_color : source_color = vec4(0.9, 0.7, 0.05, 0.4); // 偏黄色的条纹，匹配UI风格
uniform vec4 bg_color : source_color = vec4(0.02, 0.02, 0.02, 0.85); // 较深的背景色，透明度高不至于看不清

void fragment() {
    // 获取当前像素到屏幕垂直中心 (Y = 0.5) 的距离
    float dist_y = abs(UV.y - 0.5);
    
    // 制作水平方向的扫描线，随着时间(TIME)向屏幕中间(dist_y减小)收缩
    // dist_y + TIME * speed 可以让波形向中心移动
    float wave = sin((dist_y + TIME * speed) * density);
    
    // 将正弦波转换成锐利的条纹边缘
    float lines = smoothstep(0.8, 1.0, wave);
    
    // 将条纹颜色与背景底色混合
    vec4 final_color = mix(bg_color, line_color, lines);
    
    // 整体菜单淡入淡出的透明度控制
    final_color.a *= progress;
    
    COLOR = final_color;
}
