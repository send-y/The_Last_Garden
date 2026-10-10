shader_type canvas_item;
render_mode unshaded;
uniform sampler2D light_mask : filter_linear, repeat_disable;
uniform vec2 world_origin;
uniform vec2 world_extent;
uniform float night_alpha = 0.0;

void fragment() {
	vec2 world_uv = (world_origin + UV * world_extent) / vec2(4096.0);
	float light = texture(light_mask, world_uv).r;
	COLOR = vec4(0.10, 0.13, 0.28, night_alpha * (1.0 - light));
}
