shader_type canvas_item;

uniform float opacity : hint_range(0, 1) = 0.8;

void fragment() {
	COLOR = vec4(0.0, 0.0, 0.0, opacity);
}