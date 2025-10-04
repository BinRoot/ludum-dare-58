extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var material: ShaderMaterial
var fish_ref: Node3D = null
var hex_radius: float = 2.0  # Must match the radius used in _ready
var is_hovered: bool = false

# Attach to a Node3D, or run in an editor utility script
func _ready():
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
	var static_body = StaticBody3D.new()
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

func set_fish(fish: Node3D):
	fish_ref = fish

func _process(_delta):
	if material:
		# Update hover highlight
		material.set_shader_parameter("hover_highlight", 1.0 if is_hovered else 0.0)

		if fish_ref:
			# Calculate if fish is near this tile
			var tile_pos = global_position
			var fish_pos = fish_ref.global_position

			# Calculate distance in x,z plane
			var dx = fish_pos.x - tile_pos.x
			var dz = fish_pos.z - tile_pos.z
			var dist_xz = sqrt(dx * dx + dz * dz)

			# Check if fish is within hex radius and near the tile's Y level
			var is_under = 0.0
			var y_diff = abs(fish_pos.y - tile_pos.y)
			if dist_xz < hex_radius and y_diff < 3.0:  # Within 3 units vertically
				# Calculate shadow intensity based on distance (center = darker, edge = lighter)
				is_under = 1.0 - (dist_xz / hex_radius)

			material.set_shader_parameter("fish_under", is_under)

func _on_mouse_entered():
	is_hovered = true

func _on_mouse_exited():
	is_hovered = false
