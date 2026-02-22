shader_type canvas_item;

uniform float lod: hint_range(0.0, 5.0) = 2.5;
uniform vec4 mix_color: source_color = vec4(0.05, 0.05, 0.05, 0.6);
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment(){
    vec4 color = textureLod(SCREEN_TEXTURE, SCREEN_UV, lod);
    COLOR = mix(color, mix_color, mix_color.a);
}
