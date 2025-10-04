extends Node3D

# Grid properties
@export var grid_size: int = 5  # Uses Global.house_cell_size by default
@export var grid_color: Color = Color(0.8, 0.7, 1, 0.6)
@export var show_grid: bool = true
@export var bounds_shape: Node3D  # Reference to boundary (same as fish tanks)

var mesh_instance: MeshInstance3D
var cell_size: float = 1.0
var boundary_origin: Vector3 = Vector3.ZERO

func _ready():
	grid_size = Global.house_cell_size
	_calculate_cell_size_from_boundary()
	_position_at_boundary()
	_create_grid_visual()

func _position_at_boundary():
	# Position the grid at the boundary's location
	if bounds_shape:
		global_position = boundary_origin

func _calculate_cell_size_from_boundary():
	if not bounds_shape:
		push_warning("GridVisualizer: No bounds_shape set! Using default cell_size of 1.0")
		cell_size = 1.0
		return

	var boundary_size = _get_boundary_size()
	if boundary_size == Vector3.ZERO:
		push_warning("GridVisualizer: Could not determine boundary size! Using default cell_size of 1.0")
		cell_size = 1.0
		return

	# Calculate cell size as boundary dimension divided by number of cells
	var cell_size_x = boundary_size.x / float(Global.house_cell_size)
	var cell_size_z = boundary_size.z / float(Global.house_cell_size)
	cell_size = (cell_size_x + cell_size_z) / 2.0  # Average for square-ish cells

	# Calculate the boundary origin (TOP-LEFT corner in world space)
	# Top-left = minimum X, minimum Z (from bird's eye view)
	var boundary_center = bounds_shape.global_position
	boundary_origin = Vector3(
		boundary_center.x - boundary_size.x / 2.0,
		boundary_center.y,
		boundary_center.z - boundary_size.z / 2.0
	)

func _get_boundary_size() -> Vector3:
	# Try to get size from various node types
	if bounds_shape is MeshInstance3D:
		var mesh = bounds_shape.mesh
		if mesh:
			var aabb = mesh.get_aabb()
			return aabb.size * bounds_shape.scale

	# Check for CollisionShape3D child
	for child in bounds_shape.get_children():
		if child is CollisionShape3D:
			var shape = child.shape
			if shape is BoxShape3D:
				return shape.size * child.scale * bounds_shape.scale
			elif shape is CylinderShape3D:
				var radius = shape.radius
				var cylinder_height = shape.height
				return Vector3(radius * 2, cylinder_height, radius * 2) * child.scale * bounds_shape.scale

	# If bounds_shape itself is a CollisionShape3D
	if bounds_shape is CollisionShape3D:
		var shape = bounds_shape.shape
		if shape is BoxShape3D:
			return shape.size * bounds_shape.scale

	return Vector3.ZERO

func _create_grid_visual():
	mesh_instance = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()
	mesh_instance.mesh = immediate_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = grid_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.set_surface_override_material(0, material)

	add_child(mesh_instance)

	# Draw grid lines on the z-x plane
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var total_size_x = grid_size * cell_size
	var total_size_z = grid_size * cell_size

	# Small y offset to prevent z-fighting with ground
	var y_offset = 0.01

	# Vertical lines (along Z axis)
	for i in range(grid_size + 1):
		var x = i * cell_size
		immediate_mesh.surface_add_vertex(Vector3(x, y_offset, 0))
		immediate_mesh.surface_add_vertex(Vector3(x, y_offset, total_size_z))

	# Horizontal lines (along X axis)
	for i in range(grid_size + 1):
		var z = i * cell_size
		immediate_mesh.surface_add_vertex(Vector3(0, y_offset, z))
		immediate_mesh.surface_add_vertex(Vector3(total_size_x, y_offset, z))

	immediate_mesh.surface_end()

	mesh_instance.visible = show_grid

func toggle_grid():
	show_grid = !show_grid
	if mesh_instance:
		mesh_instance.visible = show_grid
