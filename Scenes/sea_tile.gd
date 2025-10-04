extends Node3D

signal fish_caught(fish: Node3D, tile: Node3D)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var material: ShaderMaterial
var fish_refs: Array[Node3D] = []  # Track multiple fish
var hex_radius: float = 2.0  # Must match the radius used in _ready
var is_hovered: bool = false
var has_net: bool = false
var net_visual: MeshInstance3D = null
var static_body: StaticBody3D = null
var caught_fish: Array[Node3D] = []  # Track fish that have already been caught
var celebration_tween: Tween = null
var original_y_position: float = 0.0

# Attach to a Node3D, or run in an editor utility script
func _ready():
	# Store the original Y position for celebration animation
	original_y_position = position.y
	var radius := 2            # hex face "radius" (center to corner)
	var length := 1.0           # how long you want it
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6     # <- hexagon
	mesh.rings = 10              # more segments for smoother waves
	mesh.cap_top = true
	mesh.cap_bottom = true
	#mesh.smooth_faces = false    # crisp, flat hex sides (no rounding)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	# Apply wave shader
	var shader = load("res://Scenes/sea_wave.gdshader")
	material = ShaderMaterial.new()
	material.shader = shader
	mi.set_surface_override_material(0, material)

	# Setup mouse input detection
	static_body = StaticBody3D.new()
	static_body.input_ray_pickable = true
	# Ensure it's on a collision layer that's checked
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	add_child(static_body)

	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = radius * 1.1  # Slightly larger for better detection
	shape.height = length * 1.5
	collision.shape = shape
	collision.position.y = 0.25  # Slightly above center
	static_body.add_child(collision)

	# Connect mouse signals
	static_body.mouse_entered.connect(_on_mouse_entered)
	static_body.mouse_exited.connect(_on_mouse_exited)
	static_body.input_event.connect(_on_input_event)

func add_fish(fish: Node3D):
	if fish and not fish in fish_refs:
		fish_refs.append(fish)

func _process(_delta):
	if material:
		# Update hover highlight
		material.set_shader_parameter("hover_highlight", 1.0 if is_hovered else 0.0)

		# Check all fish and use the maximum shadow effect
		var max_is_under = 0.0
		var tile_pos = global_position

		for fish_ref in fish_refs:
			if fish_ref:
				# Calculate if fish is near this tile
				var fish_pos = fish_ref.global_position

				# Calculate distance in x,z plane
				var dx = fish_pos.x - tile_pos.x
				var dz = fish_pos.z - tile_pos.z
				var dist_xz = sqrt(dx * dx + dz * dz)

				# Check if fish is within hex radius and near the tile's Y level
				var y_diff = abs(fish_pos.y - tile_pos.y)
				if dist_xz < hex_radius and y_diff < 3.0:  # Within 3 units vertically
					# Calculate shadow intensity based on distance (center = darker, edge = lighter)
					var is_under = 1.0 - (dist_xz / hex_radius)
					max_is_under = max(max_is_under, is_under)

					# Check if fish is caught by net
					if has_net and dist_xz < hex_radius * 0.7 and fish_ref not in caught_fish:  # Fish is in the center area
						caught_fish.append(fish_ref)
						fish_caught.emit(fish_ref, self)
						_celebrate_catch()

		material.set_shader_parameter("fish_under", max_is_under)

func _on_mouse_entered():
	is_hovered = true

func _on_mouse_exited():
	is_hovered = false

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click()

func _handle_click():
	if has_net:
		# Pick up the net
		pickup_net()
	else:
		# Try to place a net
		place_net()

func place_net() -> bool:
	if Global.use_item("net"):
		has_net = true
		_create_net_visual()
		return true
	return false

func pickup_net():
	if has_net:
		has_net = false
		caught_fish.clear()  # Reset caught fish list
		Global.add_item("net", 1)
		_remove_net_visual()

func consume_net():
	# Remove net without returning it to inventory (used when catching fish)
	if has_net:
		has_net = false
		caught_fish.clear()  # Reset caught fish list
		_remove_net_visual()

func _create_net_visual():
	if net_visual == null:
		net_visual = MeshInstance3D.new()

		# Use a cylinder mesh with very small height to create a circular disc
		var disc_mesh = CylinderMesh.new()
		disc_mesh.top_radius = hex_radius * 0.9  # Slightly smaller than hex
		disc_mesh.bottom_radius = hex_radius * 0.9
		disc_mesh.height = 0.02  # Very thin to appear flat
		disc_mesh.radial_segments = 32  # Smooth circle
		disc_mesh.rings = 8  # Subdivisions for net pattern
		disc_mesh.cap_top = true
		disc_mesh.cap_bottom = true
		net_visual.mesh = disc_mesh

		# Create a net-like material with grid pattern
		var net_material = StandardMaterial3D.new()
		net_material.albedo_color = Color(0.9, 0.9, 0.85, 1.0)
		net_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		net_material.cull_mode = BaseMaterial3D.CULL_DISABLED

		# Add UV-based grid pattern
		net_material.uv1_scale = Vector3(12, 12, 1)  # Repeat texture for grid effect
		net_material.metallic = 0.3
		net_material.roughness = 0.8

		# Create a simple procedural net texture with grid pattern
		var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))  # Transparent background

		# Draw grid lines for net pattern (thicker lines)
		for x in range(16):
			for y in range(16):
				if x == 0 or x == 1 or x == 14 or x == 15 or y == 0 or y == 1 or y == 14 or y == 15:
					img.set_pixel(x, y, Color(0.9, 0.9, 0.85, 1.0))

		var texture = ImageTexture.create_from_image(img)
		net_material.albedo_texture = texture
		net_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

		net_visual.set_surface_override_material(0, net_material)

		# Position it just above the water surface - NO rotation needed for horizontal
		net_visual.position = Vector3(0, 0.55, 0)
		# Cylinder is already oriented vertically, so it naturally lies flat on XZ plane
		add_child(net_visual)

func _remove_net_visual():
	if net_visual != null:
		net_visual.queue_free()
		net_visual = null

# Celebrate catching a fish with dramatic visual effects
func _celebrate_catch():
	# Cancel any existing celebration animation
	if celebration_tween and celebration_tween.is_running():
		celebration_tween.kill()

	# Create a new tween for the celebration animation
	celebration_tween = create_tween()
	celebration_tween.set_parallel(true)  # Run all animations at the same time

	# BOUNCE ANIMATION - rise up and settle down
	var bounce_height = 0.8
	celebration_tween.tween_property(self, "position:y", original_y_position + bounce_height, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	celebration_tween.tween_property(self, "position:y", original_y_position, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_ELASTIC).set_delay(0.3)

	# SCALE ANIMATION - pulse effect
	var original_scale = scale
	celebration_tween.tween_property(self, "scale", original_scale * 1.3, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	celebration_tween.tween_property(self, "scale", original_scale, 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_ELASTIC).set_delay(0.25)

	# COLOR FLASH - create a vibrant flash effect with shader or overlay
	_create_celebration_flash()

	# Clean up parallel mode for next animation
	celebration_tween.chain()

# Create a visual flash effect for celebration
func _create_celebration_flash():
	# Create a bright, colorful overlay mesh
	var flash_mesh = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = hex_radius * 1.2
	cylinder.bottom_radius = hex_radius * 1.2
	cylinder.height = 0.1
	cylinder.radial_segments = 6
	flash_mesh.mesh = cylinder

	# Create vibrant glowing material
	var flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.8, 0.2, 1.0)  # Golden yellow
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.9, 0.3)
	flash_material.emission_energy_multiplier = 3.0
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mesh.set_surface_override_material(0, flash_material)

	# Position it at the tile
	flash_mesh.position = Vector3(0, 0.6, 0)
	add_child(flash_mesh)

	# Animate the flash - grow and fade out
	var flash_tween = create_tween()
	flash_tween.set_parallel(true)

	# Scale up
	flash_tween.tween_property(flash_mesh, "scale", Vector3(1.5, 1.0, 1.5), 0.5).set_ease(Tween.EASE_OUT)

	# Fade out by animating the material's albedo alpha
	flash_tween.tween_property(flash_material, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_IN)

	# Color shift from gold to white to cyan
	flash_tween.tween_property(flash_material, "albedo_color", Color(0.3, 0.8, 1.0, 0.0), 0.5)
	flash_tween.tween_property(flash_material, "emission", Color(0.3, 0.9, 1.0), 0.5)

	# Clean up after animation
	flash_tween.chain()
	flash_tween.tween_callback(flash_mesh.queue_free)
