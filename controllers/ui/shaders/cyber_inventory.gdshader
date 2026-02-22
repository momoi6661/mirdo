shader_type canvas_item;

uniform float scanline_count : hint_range(0.0, 1080.0) = 50.0;
uniform float scanline_speed : hint_range(0.0, 10.0) = 0.5;
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.003;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    float glitch_offset = 0.0;
    if (glitch_intensity > 0.0) {
        float noise = random(vec2(TIME * 15.0, uv.y));
        if (noise > 0.85) {
            glitch_offset = (random(vec2(TIME, uv.y)) - 0.5) * glitch_intensity * 0.1;
        }
    }
    vec2 final_uv = vec2(uv.x + glitch_offset, uv.y);
    float current_ca = chromatic_aberration + glitch_intensity * 0.02;
    float r = texture(SCREEN_TEXTURE, final_uv + vec2(current_ca, 0.0)).r;
    float g = texture(SCREEN_TEXTURE, final_uv).g;
    float b = texture(SCREEN_TEXTURE, final_uv + vec2(-current_ca, 0.0)).b;
    vec4 screen_color = vec4(r, g, b, 1.0);
    float scanline = sin(UV.y * scanline_count * 3.14159 - TIME * scanline_speed * 10.0);
    scanline = (scanline * 0.5 + 0.5) * 0.15 + 0.85; 
    float flash = glitch_intensity * 0.3; 
    COLOR = screen_color * vec4(vec3(scanline), 1.0) + vec4(flash, flash * 0.8, flash * 0.5, 0.0);
}
