shader_type spatial;

uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_height : hint_range(0.0, 2.0) = 0.3;
uniform float wave_frequency : hint_range(0.0, 10.0) = 2.0;
uniform vec3 wave_direction = vec3(1.0, 0.0, 1.0);
uniform vec4 water_color : source_color = vec4(0.07, 0.14, 0.47, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float fish_under : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shadow_color : source_color = vec4(0.01, 0.02, 0.08, 1.0);
uniform float shadow_intensity : hint_range(0.0, 1.0) = 0.95;
uniform float hover_highlight : hint_range(0.0, 1.0) = 0.0;
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float border_width : hint_range(0.0, 1.0) = 0.15;

varying vec3 local_pos;

void vertex() {
	// Store local position for edge detection
	local_pos = VERTEX;

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

// Calculate distance to nearest hexagon edge
float hex_edge_distance(vec2 pos, float radius) {
	// A regular hexagon (flat-top orientation) can be defined by 3 pairs of parallel edges
	// We calculate distance to each of the 3 edge pairs and take the minimum

	// For a hexagon with circumradius 'radius', the apothem (perpendicular distance to edge) is:
	float apothem = radius * 0.866025; // cos(30°)

	// Define the 3 edge directions (normal vectors pointing inward)
	// For flat-top hexagon: horizontal edges and two diagonal edges at ±30° from vertical
	vec2 dir1 = vec2(0.0, 1.0);           // Horizontal edges (top/bottom)
	vec2 dir2 = vec2(0.866025, 0.5);      // Diagonal edges (right side)
	vec2 dir3 = vec2(-0.866025, 0.5);     // Diagonal edges (left side)

	// Calculate perpendicular distance to each pair of edges
	float dist1 = apothem - abs(dot(pos, dir1));
	float dist2 = apothem - abs(dot(pos, dir2));
	float dist3 = apothem - abs(dot(pos, dir3));

	// The minimum distance tells us how far we are from the nearest edge
	// Negative = inside, positive = outside
	float min_dist = min(min(dist1, dist2), dist3);

	// Return absolute distance from edge (0 = on edge, positive = away from edge)
	return abs(min_dist);
}

void fragment() {
	// Mix between normal water color and shadow color based on fish_under
	vec3 final_color = mix(water_color.rgb, shadow_color.rgb, fish_under * shadow_intensity);

	// Calculate edge highlighting for hover effect
	if (hover_highlight > 0.0) {
		// Get distance to hexagon edge in XZ plane
		vec2 xz = vec2(local_pos.x, local_pos.z);
		float edge_dist = hex_edge_distance(xz, 2.0); // radius is 2.0

		// Create a sharp border by using smoothstep
		float border_mask = 1.0 - smoothstep(0.0, border_width, edge_dist);

		// Apply highlight only to the border
		final_color = mix(final_color, highlight_color.rgb, hover_highlight * border_mask);
	}

	ALBEDO = final_color;
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
}
