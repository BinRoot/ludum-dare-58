shader_type spatial;
render_mode cull_disabled;

// Wiggle parameters
uniform float wiggle_amplitude : hint_range(0.0, 1.0) = 0.15;
uniform float wiggle_frequency : hint_range(0.1, 10.0) = 2.0;
uniform float wiggle_speed : hint_range(0.1, 5.0) = 1.5;
uniform float tail_amplification : hint_range(1.0, 5.0) = 2.5;
uniform vec4 base_color : source_color = vec4(0.78, 0.9, 1.0, 1.0);

void vertex() {
	// COLOR.rgb stores the binormal (wiggle direction) at this vertex
	// COLOR.a stores the body position (0 = tail, 1 = head)
	vec3 binormal_direction = COLOR.rgb;
	float body_position = COLOR.a;

	// Calculate wiggle strength - stronger at the tail
	float wiggle_strength = wiggle_amplitude * (1.0 - body_position) * tail_amplification;

	// Create traveling wave along the body
	float wave = sin(body_position * wiggle_frequency - TIME * wiggle_speed);

	// Apply wiggle along the binormal direction (side-to-side motion)
	// This is the correct direction for fish swimming motion
	VERTEX += binormal_direction * wave * wiggle_strength;

	// Optional: Add some vertical undulation for more natural movement
	// Use the normal for up/down motion
	float vertical_wave = sin(body_position * wiggle_frequency * 0.5 - TIME * wiggle_speed * 0.7);
	vec3 up_direction = normalize(cross(binormal_direction, normalize(VERTEX - MODEL_MATRIX[3].xyz)));
	VERTEX += up_direction * vertical_wave * wiggle_strength * 0.2;
}

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.65;
	METALLIC = 0.0;
}
