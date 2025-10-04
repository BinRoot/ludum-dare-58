shader_type spatial;

uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_height : hint_range(0.0, 2.0) = 0.3;
uniform float wave_frequency : hint_range(0.0, 10.0) = 2.0;
uniform vec3 wave_direction = vec3(1.0, 0.0, 1.0);
uniform vec4 water_color : source_color = vec4(0.1, 0.3, 0.6, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.3;

void vertex() {
	// Get world position
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Create multiple wave patterns
	float wave1 = sin(world_pos.x * wave_frequency + TIME * wave_speed) * wave_height;
	float wave2 = cos(world_pos.z * wave_frequency * 0.7 + TIME * wave_speed * 1.3) * wave_height * 0.5;
	float wave3 = sin((world_pos.x + world_pos.z) * wave_frequency * 0.5 + TIME * wave_speed * 0.8) * wave_height * 0.3;

	// Combine waves
	float total_wave = wave1 + wave2 + wave3;

	// Apply wave to vertex Y position
	VERTEX.y += total_wave;
}

void fragment() {
	ALBEDO = water_color.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
}
