extends Node3D

# Grid properties
@export var grid_size: int = 5  # Uses Global.house_cell_size by default
@export var grid_color: Color = Color(0.8, 0.7, 1, 0.6)
@export var show_grid: bool = true
@export var bounds_shape: Node3D  # Reference to boundary (same as fish tanks)
@export var tank_cost: int = 5  # Cost of a tank in clams

var mesh_instance: MeshInstance3D
var cell_size: float = 1.0
var boundary_origin: Vector3 = Vector3.ZERO

# Interaction
var interaction_area: Area3D
var hovered_cell: Vector2i = Vector2i(-1, -1)
var cost_label: Label3D = null
var is_mouse_over_grid: bool = false

# Sell tile visuals
var sell_marker: MeshInstance3D = null
var sell_label: Label3D = null

# Signals
signal cell_clicked(row: int, col: int)

func _ready():
	grid_size = Global.house_cell_size
	_calculate_cell_size_from_boundary()
	_position_at_boundary()
	_create_grid_visual()
	_setup_interaction()
	_create_cost_label()
	_create_sell_marker()

	# Connect to tank selection signals to hide/show sell label
	Global.fish_tank_selection_started.connect(_on_tank_selection_started)
	Global.fish_placed_in_tank.connect(_on_fish_placed)

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

func _setup_interaction():
	# Create an Area3D for mouse interaction (better for input events)
	interaction_area = Area3D.new()
	interaction_area.input_ray_pickable = true
	interaction_area.collision_layer = 16  # Use layer 16 to avoid conflicts
	interaction_area.collision_mask = 0
	interaction_area.monitorable = false  # Don't need physics monitoring
	interaction_area.monitoring = false
	add_child(interaction_area)

	# Create collision shape covering the entire grid
	# Put it below the tanks so tank collision is detected first
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	var total_size_x = grid_size * cell_size
	var total_size_z = grid_size * cell_size
	shape.size = Vector3(total_size_x, 0.01, total_size_z)  # Very thin at ground level
	collision.shape = shape
	# Position it just at ground level
	collision.position = Vector3(total_size_x / 2.0, 0.005, total_size_z / 2.0)
	interaction_area.add_child(collision)

	# Set lower priority so tanks get input events first
	interaction_area.priority = -1

	# Connect signals
	interaction_area.input_event.connect(_on_input_event)
	interaction_area.mouse_entered.connect(_on_mouse_entered)
	interaction_area.mouse_exited.connect(_on_mouse_exited)

	print("Grid interaction setup - Area3D at:", interaction_area.global_position, " collision size:", shape.size)

func _create_cost_label():
	cost_label = Label3D.new()
	cost_label.text = "Cost: " + str(tank_cost) + " clams"
	cost_label.font_size = 32
	cost_label.modulate = Color.YELLOW
	cost_label.outline_modulate = Color.BLACK
	cost_label.outline_size = 4
	cost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cost_label.visible = false
	cost_label.pixel_size = 0.03  # Larger = more visible (was 0.01, now 0.005 which counterintuitively makes it bigger)
	cost_label.no_depth_test = true  # Always render on top
	cost_label.render_priority = 10  # Render after other objects
	add_child(cost_label)
	print("Cost label created at grid position: ", global_position)

func _create_sell_marker():
	# Visual indicator for the sell tile cell
	var col: int = Global.sell_tile_col
	var row: int = Global.sell_tile_row

	# Safety: clamp within grid
	col = clamp(col, 0, grid_size - 1)
	row = clamp(row, 0, grid_size - 1)

	# Create a flat plane marker
	sell_marker = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(cell_size * 0.9, cell_size * 0.9)
	sell_marker.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.84, 0.0, 0.45) # golden, semi-transparent
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sell_marker.set_surface_override_material(0, mat)

	# Position at the center of the sell tile cell (local space; grid is at boundary origin)
	sell_marker.position = Vector3(
		col * cell_size + cell_size / 2.0,
		0.02,
		row * cell_size + cell_size / 2.0
	)
	add_child(sell_marker)

	# Floating label above the marker
	sell_label = Label3D.new()
	sell_label.text = "Sell"
	sell_label.font_size = 24
	sell_label.modulate = Color(1.0, 0.95, 0.5)
	sell_label.outline_modulate = Color.BLACK
	sell_label.outline_size = 4
	sell_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sell_label.pixel_size = 0.03
	sell_label.no_depth_test = true
	sell_label.render_priority = 10
	sell_label.position = sell_marker.position + Vector3(0, 1.2, 0)
	add_child(sell_label)

func _on_mouse_entered():
	is_mouse_over_grid = true

func _on_mouse_exited():
	is_mouse_over_grid = false
	hovered_cell = Vector2i(-1, -1)
	if cost_label:
		cost_label.visible = false

func _on_input_event(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int):
	print("_on_input_event called, event type:", event.get_class())
	if event is InputEventMouseButton:
		print("Mouse button event - button:", event.button_index, " pressed:", event.pressed)
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Don't allow buying during tank selection mode
			if Global.is_selecting_tank:
				print("Cannot buy - tank selection mode active")
				return

			# Use hovered_cell if available (more reliable)
			if hovered_cell.x >= 0 and hovered_cell.y >= 0:
				var row = hovered_cell.y
				var col = hovered_cell.x

				# Check if this cell is occupied by a tank
				# If it is, don't handle the event - let it pass through to the tank
				if _is_cell_occupied(row, col):
					print("Cell occupied by tank - passing event through for tank interaction")
					return  # Don't consume the event

				print("Clicked on empty cell row:", row, " col:", col)
				_try_buy_tank(row, col)
			else:
				# Fallback: Convert world position to grid coordinates
				# event_position is relative to the collision shape center, not the grid origin
				# We need to account for the collision shape offset
				var total_size_x = grid_size * cell_size
				var total_size_z = grid_size * cell_size
				var shape_offset = Vector3(total_size_x / 2.0, 0, total_size_z / 2.0)
				var local_pos = event_position + global_position - (global_position + shape_offset)
				var col = int(local_pos.x / cell_size)
				var row = int(local_pos.z / cell_size)

				print("Clicked (fallback) on cell row:", row, " col:", col)

				# Check if within grid bounds
				if col >= 0 and col < grid_size and row >= 0 and row < grid_size:
					# Check if occupied before trying to buy
					if not _is_cell_occupied(row, col):
						_try_buy_tank(row, col)

func _try_buy_tank(row: int, col: int):
	print("=== _try_buy_tank called for row:", row, " col:", col, " ===")

	# Don't allow buying on the sell tile
	if row == Global.sell_tile_row and col == Global.sell_tile_col:
		print("Cannot buy tank on sell tile!")
		return

	# Check if cell is already occupied
	var is_occupied = _is_cell_occupied(row, col)
	print("Cell occupied check:", is_occupied)
	if is_occupied:
		print("Cell already occupied!")
		return

	# Check if player has enough clams
	var current_clams = Global.get_clams()
	print("Current clams:", current_clams, " Tank cost:", tank_cost)
	if current_clams < tank_cost:
		print("Not enough clams! Need ", tank_cost, " but have ", current_clams)
		return

	# Spend clams and emit signal to spawn tank
	print("Attempting to spend", tank_cost, "clams...")
	var spent = Global.spend_clams(tank_cost)
	print("Spend successful:", spent)
	if spent:
		print("Emitting cell_clicked signal for row:", row, " col:", col)
		cell_clicked.emit(row, col)
		print("Signal emitted, new clam balance:", Global.get_clams())

func _is_cell_occupied(row: int, col: int) -> bool:
	# Check if any fish tank overlaps with this cell
	# Access the static tank list from FishTank class
	var fish_tank_script = load("res://Scenes/fish_tank.gd")
	if fish_tank_script and "all_tanks" in fish_tank_script:
		var all_tanks = fish_tank_script.all_tanks
		for tank in all_tanks:
			if tank and is_instance_valid(tank) and tank.has_method("get_grid_bounds"):
				var bounds = tank.get_grid_bounds()
				# Check if this cell is within the tank's bounds
				if row >= bounds.row and row < bounds.row + bounds.height:
					if col >= bounds.col and col < bounds.col + bounds.width:
						return true
	return false

func _is_any_tank_dragging() -> bool:
	# Check if any tank is currently being dragged
	var fish_tank_script = load("res://Scenes/fish_tank.gd")
	if fish_tank_script and "all_tanks" in fish_tank_script:
		var all_tanks = fish_tank_script.all_tanks
		for tank in all_tanks:
			if tank and is_instance_valid(tank) and "is_dragging" in tank:
				if tank.is_dragging:
					return true
	return false

func _process(_delta):
	# Don't show cost label during tank selection mode
	if Global.is_selecting_tank:
		if cost_label:
			cost_label.visible = false
		return

	# Don't show cost label when a tank is being dragged
	if _is_any_tank_dragging():
		if cost_label:
			cost_label.visible = false
		return

	# Update hovered cell and cost label position using simple plane intersection
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)

	# Intersect with a plane at the grid's height
	var plane = Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(from, dir)

	if hit:
		# Convert to local position relative to grid origin
		var local_pos = hit - global_position
		var col = int(local_pos.x / cell_size)
		var row = int(local_pos.z / cell_size)


		# Check if within grid bounds
		if col >= 0 and col < grid_size and row >= 0 and row < grid_size:
			hovered_cell = Vector2i(col, row)

			# Update cost label
			if cost_label:
				# Position at center of hovered cell, elevated above the ground
				var cell_center = Vector3(
					col * cell_size + cell_size / 2.0,
					2.0,  # Raised higher so it's visible above tanks
					row * cell_size + cell_size / 2.0
				)
				cost_label.global_position = global_position + cell_center

				# Don't show cost label on sell tile or occupied cells
				if row == Global.sell_tile_row and col == Global.sell_tile_col:
					cost_label.visible = false
				elif not _is_cell_occupied(row, col):
					cost_label.text = "Cost: " + str(tank_cost) + " clams"
					if Global.get_clams() >= tank_cost:
						cost_label.modulate = Color.GREEN
					else:
						cost_label.modulate = Color.RED
					cost_label.visible = true
				else:
					cost_label.visible = false
		else:
			hovered_cell = Vector2i(-1, -1)
			if cost_label:
				cost_label.visible = false
	else:
		hovered_cell = Vector2i(-1, -1)
		if cost_label:
			cost_label.visible = false

func _unhandled_input(event: InputEvent):
	# Global click handler so empty cells can be purchased even if Area3D doesn't catch it
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Don't allow buying during tank selection mode
			if Global.is_selecting_tank:
				return

			# If we have a valid hovered cell and it's empty, try to buy
			if hovered_cell.x >= 0 and hovered_cell.y >= 0:
				var row = hovered_cell.y
				var col = hovered_cell.x
				if not _is_cell_occupied(row, col):
					_try_buy_tank(row, col)

func _on_tank_selection_started():
	# Hide the sell label and grid lines during tank selection
	if sell_label:
		sell_label.visible = false
	if sell_marker:
		sell_marker.visible = false
	if mesh_instance:
		mesh_instance.visible = false
	if cost_label:
		cost_label.visible = false

func _on_fish_placed():
	# Show the sell label and grid lines again after placing the fish
	if sell_label:
		sell_label.visible = true
	if sell_marker:
		sell_marker.visible = true
	if mesh_instance:
		mesh_instance.visible = true
