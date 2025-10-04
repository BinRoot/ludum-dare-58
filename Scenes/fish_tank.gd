extends Node3D

# Tank dimensions in grid cells
@export var width: int = 1  # Width in cells
@export var height: int = 1  # Height in cells
@export var row: int = floor(Global.house_cell_size / 2)  # Grid row position
@export var col: int = floor(Global.house_cell_size / 2)  # Grid column position

# Visual properties
@export var tank_height: float = 1  # Visual height of the tank
@export var glass_color: Color = Color(0.4, 0.7, 0.9, 0.3)  # Semi-transparent blue
@export var frame_color: Color = Color(0.2, 0.2, 0.2, 1.0)  # Dark frame

# Reference to the region bounds (required for positioning and sizing)
@export var bounds_shape: Node3D  # Should have a CollisionShape3D child or be a MeshInstance3D

# Calculated properties
var cell_size: float = 1.0  # Calculated from boundary dimensions
var boundary_origin: Vector3 = Vector3.ZERO  # Bottom-left corner of the boundary

# Internal state
var is_dragging: bool = false
var is_hovered: bool = false
var drag_offset: Vector3 = Vector3.ZERO
var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var material: StandardMaterial3D
var frame_mesh_instance: MeshInstance3D
var water_mesh_instance: MeshInstance3D

# Static array to track all tanks (for collision detection)
static var all_tanks: Array[Node3D] = []

# Fish management
var contained_fish: Array[Node3D] = []

func _ready():
	# Allow fish tanks to be interactive even when the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Add this tank to the global list
	all_tanks.append(self)

	# Calculate cell size from boundary
	_calculate_cell_size_from_boundary()

	# Create the visual representation
	_create_tank_visual()

	# Setup mouse interaction
	_setup_interaction()

	# Update position based on grid coordinates
	update_position()

func _calculate_cell_size_from_boundary():
	if not bounds_shape:
		push_warning("FishTank: No bounds_shape set! Using default cell_size of 1.0")
		cell_size = 1.0
		return

	var boundary_size = _get_boundary_size()
	if boundary_size == Vector3.ZERO:
		push_warning("FishTank: Could not determine boundary size! Using default cell_size of 1.0")
		cell_size = 1.0
		return

	# Calculate cell size as boundary dimension divided by number of cells
	# Use the larger of width/height to determine cell size, or average them
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

func _exit_tree():
	# Remove from global list when deleted
	all_tanks.erase(self)

func _create_tank_visual():
	# Create the glass tank body
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(width * cell_size, tank_height, height * cell_size)
	mesh_instance.mesh = box_mesh

	# Create semi-transparent glass material
	material = StandardMaterial3D.new()
	material.albedo_color = glass_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.metallic = 0.3
	material.roughness = 0.1
	mesh_instance.set_surface_override_material(0, material)

	# Set render priority - render glass after water (higher number = rendered later)
	mesh_instance.sorting_offset = 1.0

	# Position the mesh so bottom is at y=0
	mesh_instance.position.y = tank_height / 2.0
	add_child(mesh_instance)

	# Create water fill
	_create_water()

	# Create frame outline
	_create_frame()

func _create_frame():
	# Create a darker frame around the edges
	frame_mesh_instance = MeshInstance3D.new()

	# Use ImmediateMesh to create custom frame geometry
	var immediate_mesh = ImmediateMesh.new()
	frame_mesh_instance.mesh = immediate_mesh

	var frame_material = StandardMaterial3D.new()
	frame_material.albedo_color = frame_color
	frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_mesh_instance.set_surface_override_material(0, frame_material)

	frame_mesh_instance.position.y = tank_height / 2.0
	add_child(frame_mesh_instance)

	# Draw frame lines
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, frame_material)

	var w = width * cell_size / 2.0
	var h = height * cell_size / 2.0
	var y_top = tank_height / 2.0
	var y_bot = -tank_height / 2.0

	# Bottom rectangle
	immediate_mesh.surface_add_vertex(Vector3(-w, y_bot, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_bot, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_bot, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_bot, h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_bot, h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_bot, h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_bot, h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_bot, -h))

	# Top rectangle
	immediate_mesh.surface_add_vertex(Vector3(-w, y_top, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_top, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_top, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_top, h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_top, h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_top, h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_top, h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_top, -h))

	# Vertical edges
	immediate_mesh.surface_add_vertex(Vector3(-w, y_bot, -h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_top, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_bot, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_top, -h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_bot, h))
	immediate_mesh.surface_add_vertex(Vector3(w, y_top, h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_bot, h))
	immediate_mesh.surface_add_vertex(Vector3(-w, y_top, h))

	immediate_mesh.surface_end()

func _create_water():
	# Create water that fills the tank to 90%
	water_mesh_instance = MeshInstance3D.new()
	var water_box = BoxMesh.new()

	var water_fill_percent = 0.9
	var water_height = tank_height * water_fill_percent

	# Make water slightly smaller than tank to prevent z-fighting
	var water_inset = 0.02
	water_box.size = Vector3(
		width * cell_size - water_inset,
		water_height,
		height * cell_size - water_inset
	)
	water_mesh_instance.mesh = water_box

	# Create water material
	var water_material = StandardMaterial3D.new()
	water_material.albedo_color = Color(0.2, 0.5, 0.8, 0.6)  # Blue-ish water color
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Render both sides
	water_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS  # Always draw depth
	water_material.metallic = 0.1
	water_material.roughness = 0.2
	water_material.rim_enabled = true
	water_material.rim = 0.3
	water_material.rim_tint = 0.5
	water_mesh_instance.set_surface_override_material(0, water_material)

	# Set render priority - render water before glass (lower number = rendered first)
	water_mesh_instance.sorting_offset = -1.0

	# Position water so its bottom is at y=0
	# Center of water box should be at water_height / 2.0
	water_mesh_instance.position.y = water_height / 2.0

	add_child(water_mesh_instance)

func _setup_interaction():
	# Create static body for mouse picking
	static_body = StaticBody3D.new()
	static_body.input_ray_pickable = true
	static_body.collision_layer = 4  # Use layer 4 to avoid conflicts (sea tiles=1, others=2)
	static_body.collision_mask = 0
	add_child(static_body)

	# Create collision shape
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(width * cell_size, tank_height, height * cell_size)
	collision.shape = shape
	collision.position.y = tank_height / 2.0
	static_body.add_child(collision)

	# Connect signals
	static_body.mouse_entered.connect(_on_mouse_entered)
	static_body.mouse_exited.connect(_on_mouse_exited)
	static_body.input_event.connect(_on_input_event)

func update_position():
	# Convert grid coordinates to world position relative to boundary
	var local_x = col * cell_size + (width * cell_size / 2.0)
	var local_z = row * cell_size + (height * cell_size / 2.0)

	# Position relative to boundary origin
	var old_position = position
	position = boundary_origin + Vector3(local_x, 0, local_z)

	# Update fish positions if any fish are in the tank
	_update_fish_positions(old_position)

func _on_mouse_entered():
	is_hovered = true
	_update_hover_effect()

func _on_mouse_exited():
	if not is_dragging:
		is_hovered = false
		_update_hover_effect()

func _update_hover_effect():
	if material:
		# Special highlighting during tank selection mode
		if Global.is_selecting_tank and is_hovered:
			material.albedo_color = Color(0.3, 1.0, 0.3, 0.5)  # Green highlight
		elif is_hovered or is_dragging:
			material.albedo_color = glass_color * 1.3  # Brighten on hover
		else:
			material.albedo_color = glass_color

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check if we're in tank selection mode
				if Global.is_selecting_tank and Global.caught_fish:
					_place_caught_fish()
				else:
					_start_drag(event.position)
			else:
				if not Global.is_selecting_tank:
					_end_drag()

func _place_caught_fish():
	# Place the caught fish in this tank
	var fish = Global.caught_fish
	if fish:
		add_fish(fish)

		# Clear the global state
		Global.caught_fish = null
		Global.is_selecting_tank = false
		Global.fish_placed_in_tank.emit()

		# Unpause the game
		get_tree().paused = false

		print("Fish placed in tank at position: ", position)

func _start_drag(mouse_pos: Vector2):
	is_dragging = true

	# Calculate offset between mouse position and tank center
	var camera = get_viewport().get_camera_3d()
	if camera:
		var from = camera.project_ray_origin(mouse_pos)
		var dir = camera.project_ray_normal(mouse_pos)
		var plane = Plane(Vector3.UP, position.y)
		var hit = plane.intersects_ray(from, dir)
		if hit:
			drag_offset = position - hit

	_update_hover_effect()

func _end_drag():
	if is_dragging:
		is_dragging = false

		# Store previous position in case we need to revert
		var prev_row = row
		var prev_col = col

		# Snap to grid
		_snap_to_grid()

		# Check for collisions and revert if overlapping
		if _check_collision():
			print("Cannot place tank here - overlaps with another tank!")
			# Revert to previous position
			row = prev_row
			col = prev_col
			update_position()

		_update_hover_effect()

func _process(_delta):
	if is_dragging:
		var old_position = position
		_update_drag_position()
		# Update fish positions to follow the tank
		_update_fish_positions(old_position)
		# Update visual feedback based on collision state
		_update_drag_visual_feedback()

func _input(event: InputEvent):
	# Handle mouse button release globally (not just when over the tank)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_dragging:
				_end_drag()

func _update_drag_visual_feedback():
	# Check if current position would cause a collision
	if _check_collision():
		# Show red tint when overlapping
		material.albedo_color = Color(1.0, 0.3, 0.3, 0.4)
	else:
		# Show green tint when valid placement
		material.albedo_color = Color(0.3, 1.0, 0.3, 0.4)

func _update_drag_position():
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	var plane = Plane(Vector3.UP, 0)
	var hit = plane.intersects_ray(from, dir)

	if hit:
		# Apply offset and update position
		var target_pos = hit + drag_offset
		position = target_pos

		# Update grid coordinates based on current position
		_update_grid_from_position()

func _snap_to_grid():
	# Convert world position to local position relative to boundary
	var local_pos = position - boundary_origin

	# Snap position to nearest grid cell
	col = int(round((local_pos.x - (width * cell_size / 2.0)) / cell_size))
	row = int(round((local_pos.z - (height * cell_size / 2.0)) / cell_size))

	# Clamp to valid range
	col = clamp(col, 0, Global.house_cell_size - width)
	row = clamp(row, 0, Global.house_cell_size - height)

	# Update position to snapped coordinates
	update_position()

func _update_grid_from_position():
	# Convert world position back to grid coordinates (for preview during drag)
	var local_pos = position - boundary_origin
	col = int((local_pos.x - (width * cell_size / 2.0)) / cell_size)
	row = int((local_pos.z - (height * cell_size / 2.0)) / cell_size)

func _check_collision() -> bool:
	# Check if this tank overlaps with any other tank
	for tank in all_tanks:
		if tank == self:
			continue

		if tank is Node3D and tank.has_method("get_grid_bounds"):
			var other_bounds = tank.get_grid_bounds()
			var my_bounds = get_grid_bounds()

			# Check rectangle overlap
			if _rectangles_overlap(my_bounds, other_bounds):
				return true

	return false

func get_grid_bounds() -> Dictionary:
	# Return the grid rectangle occupied by this tank
	return {
		"row": row,
		"col": col,
		"width": width,
		"height": height
	}

func _rectangles_overlap(rect1: Dictionary, rect2: Dictionary) -> bool:
	# Check if two rectangles overlap
	var r1_right = rect1.col + rect1.width
	var r1_bottom = rect1.row + rect1.height
	var r2_right = rect2.col + rect2.width
	var r2_bottom = rect2.row + rect2.height

	# No overlap if one is completely to the left/right/above/below the other
	if rect1.col >= r2_right or rect2.col >= r1_right:
		return false
	if rect1.row >= r2_bottom or rect2.row >= r1_bottom:
		return false

	return true

# Add a fish to this tank
func add_fish(fish: Node3D):
	if not fish:
		return

	# Add to our list of contained fish
	contained_fish.append(fish)

	# Create a collision shape for the tank bounds that the fish can use
	var tank_bounds = _create_tank_bounds()

	# Update fish properties to swim in this tank
	fish.bounds_shape = tank_bounds

	# Disable surface behavior since fish is now in a tank, not a pond
	if fish.has_method("set") and "is_surfacing" in fish:
		fish.is_surfacing = false
		fish.surface_timer = 0.0
		fish.next_surface_time = 999999.0  # Effectively disable surfacing

	# Position fish in the center of the tank at water level
	var water_fill_percent = 0.9
	var water_height = tank_height * water_fill_percent
	fish.global_position = global_position + Vector3(0, water_height * 0.5, 0)

	# Make fish visible and enable movement
	fish.visible = true
	fish.is_moving = true
	fish.is_surfacing = false

	# Adjust fish movement speed for tank size (slower in smaller tanks)
	if fish.has_method("set") and "move_speed" in fish:
		var tank_size = (width * cell_size + height * cell_size) / 2.0
		fish.move_speed = min(fish.move_speed, tank_size * 0.3)  # Scale speed to tank

	# Pick a new destination so the fish starts swimming
	if fish.has_method("_pick_new_destination"):
		fish._pick_new_destination()

# Create a bounds collision shape for the fish to swim within
func _create_tank_bounds() -> CollisionShape3D:
	var bounds = CollisionShape3D.new()
	var box = BoxShape3D.new()

	# Make the bounds significantly smaller than the tank so fish don't clip through walls
	# Use a larger inset to keep fish well away from glass
	var inset = 0.5
	box.size = Vector3(
		max(0.5, width * cell_size - inset),
		max(0.5, tank_height * 0.9 - inset),  # 90% for water fill
		max(0.5, height * cell_size - inset)
	)

	bounds.shape = box
	# Position bounds at the center of the water volume
	var water_fill_percent = 0.9
	var water_height = tank_height * water_fill_percent
	bounds.position = Vector3(0, water_height * 0.5, 0)  # Use local position relative to tank

	add_child(bounds)
	return bounds

# Update fish positions when the tank moves
func _update_fish_positions(old_tank_position: Vector3):
	if contained_fish.is_empty():
		return

	# Calculate the position delta
	var position_delta = position - old_tank_position

	# Move all fish by the same delta
	for fish in contained_fish:
		if fish and is_instance_valid(fish):
			fish.global_position += position_delta

			# If fish is currently moving to a target, update the target too
			if fish.has_method("get") and "current_target" in fish:
				fish.current_target += position_delta
