shader_type canvas_item;

uniform float transition : hint_range(0, 1) = 0.0;
uniform vec4 panel_color : source_color = vec4(0.08, 0.08, 0.08, 0.95);

void vertex() {
	float scale = 0.95 + 0.05 * transition;
	VERTEX *= scale;
	VERTEX.y -= (1.0 - transition) * 20.0;
}

void fragment() {
	vec4 final_color = panel_color;
	final_color.a *= transition;
	COLOR = final_color;
}