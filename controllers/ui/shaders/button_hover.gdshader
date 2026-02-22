shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.2, 0.2, 0.2, 0.8);
uniform vec4 hover_color : source_color = vec4(0.35, 0.35, 0.35, 0.9);
uniform vec4 disabled_color : source_color = vec4(0.1, 0.1, 0.1, 0.6);
uniform float hover_amount : hint_range(0, 1) = 0.0;
uniform bool is_disabled = false;

void fragment() {
	vec4 final_color;
	
	if (is_disabled) {
		final_color = disabled_color;
	} else {
		final_color = mix(base_color, hover_color, hover_amount);
	}
	
	COLOR = final_color;
}