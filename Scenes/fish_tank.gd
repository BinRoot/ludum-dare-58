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
var sell_preview_label: Label3D = null

# Static array to track all tanks (for collision detection)
static var all_tanks: Array[Node3D] = []

# Fish management
var contained_fish: Array[Node3D] = []

# Capacity system
@export var max_capacity: float = 100.0  # Maximum capacity before tank breaks
var current_capacity: float = 0.0  # Current capacity based on fish volumes
var capacity_bar: ProgressBar = null  # UI progress bar for capacity
var capacity_bar_container: Control = null  # Container for the progress bar

# Combine button system
var combine_buttons: Dictionary = {}  # Maps adjacent tank to button node

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

	# Check for adjacent tanks and create combine buttons
	_update_combine_buttons()

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

	# Clean up all combine buttons
	_cleanup_combine_buttons()

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

	# Create sell preview label (hidden by default)
	sell_preview_label = Label3D.new()
	sell_preview_label.text = ""
	sell_preview_label.font_size = 28
	sell_preview_label.modulate = Color(1.0, 1.0, 0.6)
	sell_preview_label.outline_modulate = Color.BLACK
	sell_preview_label.outline_size = 4
	sell_preview_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sell_preview_label.visible = false
	sell_preview_label.pixel_size = 0.03
	sell_preview_label.no_depth_test = true
	sell_preview_label.render_priority = 10
	# Position above tank center
	sell_preview_label.position = Vector3(0, tank_height + 0.6, 0)
	add_child(sell_preview_label)

	# Create capacity progress bar
	_create_capacity_bar()

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

	# Show/hide capacity bar based on hover state
	if capacity_bar_container:
		capacity_bar_container.visible = is_hovered and not is_dragging

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

		# If dropped over sell tile, execute sale
		if _is_over_sell_tile():
			_sell_this_tank()
		else:
			# Update combine buttons after moving
			_update_all_tanks_combine_buttons()

func _process(_delta):
	if is_dragging:
		var old_position = position
		_update_drag_position()
		# Update fish positions to follow the tank
		_update_fish_positions(old_position)
		# Update visual feedback based on collision state
		_update_drag_visual_feedback()

	# Update combine button positions every frame
	_update_combine_button_positions()

func _input(event: InputEvent):
	# Handle mouse button release globally (not just when over the tank)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_dragging:
				_end_drag()

func _update_drag_visual_feedback():
	# Check if current position would cause a collision
	var overlapping := _check_collision()
	if overlapping:
		material.albedo_color = Color(1.0, 0.3, 0.3, 0.4)
		_hide_sell_preview()
		return

	# Show green tint when valid placement
	material.albedo_color = Color(0.3, 1.0, 0.3, 0.4)

	# If hovering over sell tile, show price preview
	if _is_over_sell_tile():
		_show_sell_preview()
	else:
		_hide_sell_preview()

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
	# Hide preview when snapping/ending drag
	_hide_sell_preview()

func _update_grid_from_position():
	# Convert world position back to grid coordinates (for preview during drag)
	var local_pos = position - boundary_origin
	col = int((local_pos.x - (width * cell_size / 2.0)) / cell_size)
	row = int((local_pos.z - (height * cell_size / 2.0)) / cell_size)

func _is_over_sell_tile() -> bool:
	# Determine if current bounds overlap the configured sell tile cell
	var sell_row: int = Global.sell_tile_row
	var sell_col: int = Global.sell_tile_col
	var bounds: Dictionary = get_grid_bounds()
	return sell_row >= bounds.row and sell_row < bounds.row + bounds.height and sell_col >= bounds.col and sell_col < bounds.col + bounds.width

func _show_sell_preview():
	if sell_preview_label == null:
		return
	var price := Global.compute_tank_sell_value(contained_fish, self)
	sell_preview_label.text = "+" + str(price) + " clams"
	sell_preview_label.modulate = Color(0.9, 1.0, 0.6)
	sell_preview_label.visible = true

func _hide_sell_preview():
	if sell_preview_label:
		sell_preview_label.visible = false

func _sell_this_tank():
	# Calculate value and award clams
	var value := Global.compute_tank_sell_value(contained_fish, self)
	Global.add_clams(value)

	# Free all contained fish
	for fish in contained_fish:
		if fish and is_instance_valid(fish):
			fish.queue_free()
	contained_fish.clear()

	# Remove from global list BEFORE checking game over
	# (otherwise queue_free won't have removed it yet and it will still be counted)
	all_tanks.erase(self)

	# Run game over check immediately in case deferred call is delayed
	Global.check_game_over()

	# Schedule game over check for next frame on Global (this node may be freed)
	Global.call_deferred("check_game_over")

	# Remove this tank from scene
	queue_free()

func _check_game_over_deferred():
	Global.call_deferred("check_game_over")

func _check_collision() -> bool:
	# Check if this tank overlaps with any other tank
	for tank in all_tanks:
		if tank == self:
			continue
		# Skip invalid or freed nodes
		if not is_instance_valid(tank):
			continue
		# Ensure we can read bounds from the other tank
		if tank is Node3D and tank.has_method("get_grid_bounds"):
			var other_bounds: Dictionary = tank.get_grid_bounds()
			var my_bounds: Dictionary = get_grid_bounds()
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
	# Safely read rectangle fields
	var r1_col: int = int(rect1.get("col", 0))
	var r1_row: int = int(rect1.get("row", 0))
	var r1_w: int = int(rect1.get("width", 0))
	var r1_h: int = int(rect1.get("height", 0))

	var r2_col: int = int(rect2.get("col", 0))
	var r2_row: int = int(rect2.get("row", 0))
	var r2_w: int = int(rect2.get("width", 0))
	var r2_h: int = int(rect2.get("height", 0))

	# Compute rectangle edges (right/bottom are exclusive bounds)
	var r1_right: int = r1_col + r1_w
	var r1_bottom: int = r1_row + r1_h
	var r2_right: int = r2_col + r2_w
	var r2_bottom: int = r2_row + r2_h

	# No overlap if one is completely to the left/right/above/below the other
	if r1_col >= r2_right or r2_col >= r1_right:
		return false
	if r1_row >= r2_bottom or r2_row >= r1_bottom:
		return false

	return true

# Add a fish to this tank
func add_fish(fish: Node3D):
	if not fish:
		return

	# Calculate fish volume and check capacity
	var fish_volume = _calculate_fish_volume(fish)
	var new_capacity = current_capacity + fish_volume

	# Add to our list of contained fish
	contained_fish.append(fish)
	current_capacity = new_capacity
	_update_capacity_bar()

	# Mark fish as being in a tank and store reference to this tank
	if "is_in_tank" in fish:
		fish.is_in_tank = true
	if "parent_tank" in fish:
		fish.parent_tank = self

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

	# Reset fish rotation to default orientation (identity rotation)
	# This clears any rotation applied during the showcase (360-degree rotation)
	fish.rotation = Vector3.ZERO
	fish.global_transform.basis = Basis.IDENTITY

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

	# Check if tank is over capacity
	if current_capacity > max_capacity:
		_break_tank()

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

# ===========================
# Capacity System Methods
# ===========================

# Create the capacity progress bar UI
func _create_capacity_bar():
	# Create a SubViewport to render the UI in 3D space (doubled size for better readability)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(600, 120)
	viewport.transparent_bg = true
	add_child(viewport)

	# Create container control
	capacity_bar_container = Control.new()
	capacity_bar_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(capacity_bar_container)

	# Create background panel (doubled size)
	var panel = Panel.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(560, 80)
	capacity_bar_container.add_child(panel)

	# Style the panel
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	style_box.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style_box.set_border_width_all(3)
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style_box)

	# Create progress bar (doubled size)
	capacity_bar = ProgressBar.new()
	capacity_bar.position = Vector2(30, 30)
	capacity_bar.size = Vector2(540, 60)
	capacity_bar.min_value = 0
	capacity_bar.max_value = 100
	capacity_bar.value = 0
	capacity_bar.show_percentage = false
	capacity_bar_container.add_child(capacity_bar)

	# Style the progress bar
	var progress_bg = StyleBoxFlat.new()
	progress_bg.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	progress_bg.corner_radius_top_left = 5
	progress_bg.corner_radius_top_right = 5
	progress_bg.corner_radius_bottom_left = 5
	progress_bg.corner_radius_bottom_right = 5
	capacity_bar.add_theme_stylebox_override("background", progress_bg)

	var progress_fill = StyleBoxFlat.new()
	progress_fill.bg_color = Color(0.3, 0.8, 0.3, 1.0)  # Green
	progress_fill.corner_radius_top_left = 5
	progress_fill.corner_radius_top_right = 5
	progress_fill.corner_radius_bottom_left = 5
	progress_fill.corner_radius_bottom_right = 5
	capacity_bar.add_theme_stylebox_override("fill", progress_fill)

	# Add label to show percentage text (larger font)
	var label = Label.new()
	label.position = Vector2(40, 40)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	capacity_bar_container.add_child(label)
	capacity_bar.set_meta("label", label)

	# Create a Sprite3D to display the viewport in 3D
	var sprite = Sprite3D.new()
	sprite.texture = viewport.get_texture()
	sprite.pixel_size = 0.01  # Increased from 0.003 to make it much larger
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.render_priority = 10
	# Position above the tank
	sprite.position = Vector3(0, tank_height + 0.5, -2.5)  # Raised higher too
	add_child(sprite)

	# Hide initially (show only on hover)
	capacity_bar_container.visible = false

# Calculate fish volume based on graph complexity
func _calculate_fish_volume(fish: Node3D) -> float:
	if not fish or not "graph" in fish:
		return 10.0  # Default volume if fish has no graph

	var graph = fish.graph
	if graph.size() == 0:
		return 10.0

	# Count unique nodes in the graph
	var nodes_set = {}
	for edge in graph:
		nodes_set[edge.x] = true
		nodes_set[edge.y] = true

	var num_nodes = nodes_set.size()
	var num_edges = graph.size()

	# Volume is based on graph complexity
	# More nodes and edges = more complex = larger volume
	var volume = (num_nodes * 5.0) + (num_edges * 3.0)

	return volume

# Update the capacity bar display
func _update_capacity_bar():
	if not capacity_bar:
		return

	var percentage = (current_capacity / max_capacity) * 100.0
	capacity_bar.value = percentage

	# Update label
	var label = capacity_bar.get_meta("label") as Label
	if label:
		label.text = "Capacity: %d%%" % int(percentage)

	# Change color based on capacity level
	var progress_fill = capacity_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if progress_fill:
		if percentage < 70:
			progress_fill.bg_color = Color(0.3, 0.8, 0.3, 1.0)  # Green
		elif percentage < 90:
			progress_fill.bg_color = Color(0.9, 0.9, 0.3, 1.0)  # Yellow
		else:
			progress_fill.bg_color = Color(0.9, 0.3, 0.3, 1.0)  # Red

# Recalculate total capacity from all contained fish
func recalculate_capacity():
	# Store old capacity for comparison
	var old_capacity = current_capacity

	# Reset capacity
	current_capacity = 0.0

	# Sum up volumes of all fish
	for fish in contained_fish:
		if fish and is_instance_valid(fish):
			var fish_volume = _calculate_fish_volume(fish)
			current_capacity += fish_volume
			print("  Fish volume: ", fish_volume)

	print("Tank capacity recalculated: ", old_capacity, " -> ", current_capacity, " (max: ", max_capacity, ")")

	# Update display
	_update_capacity_bar()

	# Check if tank should break
	if current_capacity > max_capacity:
		print("Tank over capacity! Breaking...")
		_break_tank()

# Break the tank when over capacity
func _break_tank():
	print("Tank breaking! Over capacity: ", current_capacity, "/", max_capacity)

	# Create breaking visual effect
	_create_tank_break_effect()

	# Kill all fish in the tank
	for fish in contained_fish:
		if fish and is_instance_valid(fish):
			_kill_fish(fish)

	# Clear the fish list
	contained_fish.clear()
	current_capacity = 0.0

	# Destroy the tank after a delay (let fish animations play)
	await get_tree().create_timer(3.0).timeout

	# Remove from global list BEFORE checking game over
	# (otherwise queue_free won't have removed it yet and it will still be counted)
	all_tanks.erase(self)

	# Run game over check immediately in case deferred call is delayed
	Global.check_game_over()

	# Schedule game over check for next frame on Global (this node may be freed)
	Global.call_deferred("check_game_over")

	queue_free()

# Create visual effect for tank breaking
func _create_tank_break_effect():
	# Flash the tank red
	if material:
		var tween = create_tween()
		tween.set_loops(3)
		tween.tween_property(material, "albedo_color", Color(1.0, 0.2, 0.2, 0.5), 0.2)
		tween.tween_property(material, "albedo_color", glass_color, 0.2)

	# Create shatter particles (simple version with multiple small pieces)
	for i in range(20):
		var shard = MeshInstance3D.new()
		var shard_mesh = BoxMesh.new()
		shard_mesh.size = Vector3(0.1, 0.1, 0.1)
		shard.mesh = shard_mesh

		var shard_material = StandardMaterial3D.new()
		shard_material.albedo_color = glass_color
		shard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shard.set_surface_override_material(0, shard_material)

		# Random position around tank
		shard.position = position + Vector3(
			randf_range(-width * cell_size / 2, width * cell_size / 2),
			randf_range(0, tank_height),
			randf_range(-height * cell_size / 2, height * cell_size / 2)
		)

		get_parent().add_child(shard)

		# Animate shard falling and fading
		var shard_tween = create_tween()
		shard_tween.set_parallel(true)
		shard_tween.tween_property(shard, "position:y", shard.position.y - 2.0, 1.0)
		shard_tween.tween_property(shard_material, "albedo_color:a", 0.0, 1.0)
		shard_tween.tween_property(shard, "rotation", Vector3(randf() * TAU, randf() * TAU, randf() * TAU), 1.0)
		shard_tween.chain()
		shard_tween.tween_callback(shard.queue_free)

# Animate fish death - float to heaven and fade out
func _kill_fish(fish: Node3D):
	if not fish or not is_instance_valid(fish):
		return

	print("Fish dying: ", fish.name)

	# Stop fish movement
	if "is_moving" in fish:
		fish.is_moving = false

	# Get fish material for fading
	var fish_material: ShaderMaterial = null
	if fish.has_node("MeshInstance3D"):
		var fish_mesh = fish.get_node("MeshInstance3D") as MeshInstance3D
		if fish_mesh:
			fish_material = fish_mesh.get_surface_override_material(0) as ShaderMaterial

	# Create death animation
	var death_tween = create_tween()
	death_tween.set_parallel(true)

	# Float upward (to heaven)
	var float_distance = 10.0
	death_tween.tween_property(fish, "global_position:y", fish.global_position.y + float_distance, 2.5).set_ease(Tween.EASE_OUT)

	# Rotate while floating
	death_tween.tween_property(fish, "rotation:y", fish.rotation.y + PI * 2, 2.5)

	# Fade out by adjusting the base color alpha if we have shader material
	if fish_material and fish_material.shader:
		var original_color = fish_material.get_shader_parameter("base_color") as Color
		if original_color:
			var transparent_color = Color(original_color.r, original_color.g, original_color.b, 0.0)
			death_tween.tween_property(fish_material, "shader_parameter/base_color", transparent_color, 2.5)

	# Scale down while floating
	death_tween.tween_property(fish, "scale", Vector3(0.1, 0.1, 0.1), 2.5).set_ease(Tween.EASE_IN)

	# Delete fish after animation
	death_tween.chain()
	death_tween.tween_callback(fish.queue_free)

# ===========================
# Combine Button System
# ===========================

# Check if two tanks share a side (are adjacent)
func _tanks_share_side(tank_a: Dictionary, tank_b: Dictionary) -> bool:
	var a_row: int = tank_a.row
	var a_col: int = tank_a.col
	var a_width: int = tank_a.width
	var a_height: int = tank_a.height

	var b_row: int = tank_b.row
	var b_col: int = tank_b.col
	var b_width: int = tank_b.width
	var b_height: int = tank_b.height

	# Check horizontal adjacency (side by side)
	# Tank B is to the right of Tank A
	if a_col + a_width == b_col:
		# Check if they share any rows
		var a_row_end = a_row + a_height
		var b_row_end = b_row + b_height
		if not (a_row >= b_row_end or b_row >= a_row_end):
			return true

	# Tank A is to the right of Tank B
	if b_col + b_width == a_col:
		var a_row_end = a_row + a_height
		var b_row_end = b_row + b_height
		if not (a_row >= b_row_end or b_row >= a_row_end):
			return true

	# Check vertical adjacency (one above/below the other)
	# Tank B is below Tank A
	if a_row + a_height == b_row:
		# Check if they share any columns
		var a_col_end = a_col + a_width
		var b_col_end = b_col + b_width
		if not (a_col >= b_col_end or b_col >= a_col_end):
			return true

	# Tank A is below Tank B
	if b_row + b_height == a_row:
		var a_col_end = a_col + a_width
		var b_col_end = b_col + b_width
		if not (a_col >= b_col_end or b_col >= a_col_end):
			return true

	return false

# Check if combining two tanks would create a valid rectangle
func _can_combine_to_rectangle(tank_a: Dictionary, tank_b: Dictionary) -> bool:
	# First check if they share a side
	if not _tanks_share_side(tank_a, tank_b):
		return false

	# Get the bounding box of both tanks combined
	var min_row = min(tank_a.row, tank_b.row)
	var min_col = min(tank_a.col, tank_b.col)
	var max_row = max(tank_a.row + tank_a.height, tank_b.row + tank_b.height)
	var max_col = max(tank_a.col + tank_a.width, tank_b.col + tank_b.width)

	var combined_width = max_col - min_col
	var combined_height = max_row - min_row
	var combined_area = combined_width * combined_height

	# The actual area covered by both tanks
	var actual_area = (tank_a.width * tank_a.height) + (tank_b.width * tank_b.height)

	# If the combined area equals the actual area, it's a perfect rectangle
	return combined_area == actual_area

# Update combine buttons for all adjacent tanks
func _update_combine_buttons():
	# Clean up existing buttons first
	_cleanup_combine_buttons()

	# Find all adjacent tanks that can be combined
	for tank in all_tanks:
		if tank == self or not is_instance_valid(tank):
			continue

		if not tank.has_method("get_grid_bounds"):
			continue

		var my_bounds = get_grid_bounds()
		var other_bounds = tank.get_grid_bounds()

		# Check if we can combine these tanks
		if _can_combine_to_rectangle(my_bounds, other_bounds):
			# Create a combine button between them (only if not already created)
			if not combine_buttons.has(tank):
				_create_combine_button(tank)

# Create a combine button between this tank and another
func _create_combine_button(other_tank: Node3D):
	# Create a 2D button
	var button = Button.new()
	button.text = "+"
	button.custom_minimum_size = Vector2(40, 40)

	# Style the button
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(1.0, 0.8, 0.0, 0.9)  # Gold/yellow
	style_normal.border_color = Color(0.8, 0.6, 0.0, 1.0)
	style_normal.set_border_width_all(2)
	style_normal.corner_radius_top_left = 20
	style_normal.corner_radius_top_right = 20
	style_normal.corner_radius_bottom_left = 20
	style_normal.corner_radius_bottom_right = 20
	button.add_theme_stylebox_override("normal", style_normal)

	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(1.0, 1.0, 0.0, 1.0)  # Brighter yellow
	style_hover.border_color = Color(0.8, 0.6, 0.0, 1.0)
	style_hover.set_border_width_all(2)
	style_hover.corner_radius_top_left = 20
	style_hover.corner_radius_top_right = 20
	style_hover.corner_radius_bottom_left = 20
	style_hover.corner_radius_bottom_right = 20
	button.add_theme_stylebox_override("hover", style_hover)

	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.8, 0.6, 0.0, 1.0)  # Darker when pressed
	style_pressed.border_color = Color(0.6, 0.4, 0.0, 1.0)
	style_pressed.set_border_width_all(2)
	style_pressed.corner_radius_top_left = 20
	style_pressed.corner_radius_top_right = 20
	style_pressed.corner_radius_bottom_left = 20
	style_pressed.corner_radius_bottom_right = 20
	button.add_theme_stylebox_override("pressed", style_pressed)

	# Style the text
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))

	# Connect button press signal
	button.pressed.connect(_combine_with_tank.bind(other_tank))

	# Get or create the UI layer
	var ui_layer = _get_or_create_ui_layer()
	ui_layer.add_child(button)

	# Store reference with the 3D position for positioning
	var button_data = {
		"button": button,
		"other_tank": other_tank,
		"world_position": Vector3.ZERO  # Will be updated in _update_combine_button_positions
	}
	combine_buttons[other_tank] = button_data

	# Initial position update
	_update_combine_button_positions()

# Get or create a CanvasLayer for UI elements
func _get_or_create_ui_layer() -> CanvasLayer:
	# Try to find existing UI layer in the scene
	var root = get_tree().root
	for child in root.get_children():
		if child.name == "CombineButtonLayer":
			return child as CanvasLayer

	# Create new CanvasLayer if it doesn't exist
	var ui_layer = CanvasLayer.new()
	ui_layer.name = "CombineButtonLayer"
	ui_layer.layer = 100  # High layer to appear on top
	root.add_child(ui_layer)
	return ui_layer

# Update positions of all combine buttons
func _update_combine_button_positions():
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	for tank in combine_buttons.keys():
		if not is_instance_valid(tank):
			continue

		var button_data = combine_buttons[tank]
		var button = button_data.button

		if not is_instance_valid(button):
			continue

		# Calculate 3D world position (midpoint between tanks)
		var mid_position = (global_position + tank.global_position) / 2.0
		mid_position.y += tank_height / 2.0

		# Convert 3D position to 2D screen position
		var screen_pos = camera.unproject_position(mid_position)

		# Check if position is behind camera
		var cam_to_point = mid_position - camera.global_position
		if cam_to_point.dot(-camera.global_transform.basis.z) < 0:
			# Behind camera, hide button
			button.visible = false
			continue

		# Position button (center it on the point)
		button.position = screen_pos - button.size / 2.0
		button.visible = true

# Clean up all combine buttons
func _cleanup_combine_buttons():
	for button_data in combine_buttons.values():
		if button_data is Dictionary and button_data.has("button"):
			var button = button_data.button
			if is_instance_valid(button):
				button.queue_free()
	combine_buttons.clear()

# Combine this tank with another tank
func _combine_with_tank(other_tank: Node3D):
	if not is_instance_valid(other_tank):
		return

	if not other_tank.has_method("get_grid_bounds"):
		return

	var my_bounds = get_grid_bounds()
	var other_bounds = other_tank.get_grid_bounds()

	# Verify we can still combine (double-check)
	if not _can_combine_to_rectangle(my_bounds, other_bounds):
		return

	print("Combining tanks!")

	# Calculate new bounds
	var new_row = min(my_bounds.row, other_bounds.row)
	var new_col = min(my_bounds.col, other_bounds.col)
	var new_width = max(my_bounds.col + my_bounds.width, other_bounds.col + other_bounds.width) - new_col
	var new_height = max(my_bounds.row + my_bounds.height, other_bounds.row + other_bounds.height) - new_row

	# Combine all fish from both tanks
	var all_fish: Array[Node3D] = []
	all_fish.append_array(contained_fish)
	if other_tank.has_method("get") and "contained_fish" in other_tank:
		all_fish.append_array(other_tank.contained_fish)

	# Update this tank's dimensions
	width = new_width
	height = new_height
	row = new_row
	col = new_col

	# Update max capacity based on new size
	max_capacity = 100.0 * (width * height)

	# Recreate visuals with new dimensions
	_recreate_tank_visuals()

	# Update position
	update_position()

	# Clear fish list and re-add all fish
	contained_fish.clear()
	current_capacity = 0.0

	for fish in all_fish:
		if fish and is_instance_valid(fish):
			add_fish(fish)

	# Delete the other tank
	if is_instance_valid(other_tank):
		other_tank.queue_free()

	# Update combine buttons for all tanks
	_update_all_tanks_combine_buttons()

# Recreate tank visuals with new dimensions
func _recreate_tank_visuals():
	# Remove old visuals
	if mesh_instance:
		mesh_instance.queue_free()
	if frame_mesh_instance:
		frame_mesh_instance.queue_free()
	if water_mesh_instance:
		water_mesh_instance.queue_free()
	if static_body:
		static_body.queue_free()
	if capacity_bar:
		# Find and remove the viewport container
		for child in get_children():
			if child is SubViewport:
				child.queue_free()

	# Recreate everything
	_create_tank_visual()
	_setup_interaction()

# Update combine buttons for all tanks in the scene
func _update_all_tanks_combine_buttons():
	for tank in all_tanks:
		if is_instance_valid(tank) and tank.has_method("_update_combine_buttons"):
			tank._update_combine_buttons()
