extends Node3D

# Grid properties
@export var grid_size: int = 5  # Uses Global.house_cell_size by default
@export var grid_color: Color = Color(0.8, 0.7, 1, 0.6)
@export var show_grid: bool = true
@export var bounds_shape: Node3D  # Reference to boundary (same as fish tanks)
@export var tank_cost: int = 20  # Cost of a tank in clams

var mesh_instance: MeshInstance3D
var cell_size: float = 1.0
var boundary_origin: Vector3 = Vector3.ZERO

# Interaction
var interaction_area: Area3D
var hovered_cell: Vector2i = Vector2i(-1, -1)
var cost_label: Label3D = null
var cost_icon: Sprite3D = null
var is_mouse_over_grid: bool = false
var hover_highlight: MeshInstance3D = null  # Visual highlight for hovered cell

# Sell tile visuals (now outside the grid)
var sell_zone: Area3D = null
var sell_marker: MeshInstance3D = null
var sell_label: Label3D = null
var sell_highlight: MeshInstance3D = null  # Highlight for when dragging tank over sell zone

# Signals
signal cell_clicked(row: int, col: int)

func _ready():
	grid_size = Global.house_cell_size
	# Sync exported cost with global config so all systems use the same value
	tank_cost = Global.tank_cost
	_calculate_cell_size_from_boundary()
	_position_at_boundary()
	_create_grid_visual()
	_setup_interaction()
	_create_cost_label()
	_create_hover_highlight()
	_create_sell_marker()

	# Connect to tank selection signals to hide/show sell label
	Global.fish_tank_selection_started.connect(_on_tank_selection_started)
	Global.fish_placed_in_tank.connect(_on_fish_placed)
	# Connect to growth sequence signals
	Global.growth_sequence_started.connect(_on_growth_sequence_started)
	Global.growth_sequence_ended.connect(_on_growth_sequence_ended)

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
	# Create coin icon (Sprite3D)
	cost_icon = Sprite3D.new()
	cost_icon.texture = load("res://coin.svg")
	cost_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cost_icon.pixel_size = 0.005  # Smaller pixel size for proper icon size
	cost_icon.no_depth_test = false
	cost_icon.render_priority = 10
	cost_icon.visible = false
	cost_icon.shaded = false  # Disable shading
	cost_icon.double_sided = true  # Render from both sides
	cost_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED  # Ensure proper alpha blending
	# Place on a separate visibility layer to avoid interaction with tank visuals
	cost_icon.layers = 2
	# Texture rect dimensions will be used directly with pixel_size scaling
	add_child(cost_icon)

	# Create cost label (just the number)
	cost_label = Label3D.new()
	cost_label.text = str(tank_cost)
	# Load and apply Modak font for numbers
	var modak_font = load("res://Modak-Regular.ttf")
	if modak_font:
		cost_label.font = modak_font
	cost_label.font_size = 48  # Larger font for better visibility
	cost_label.modulate = Color.YELLOW
	cost_label.outline_modulate = Color.BLACK
	cost_label.outline_size = 8
	cost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cost_label.visible = false
	cost_label.pixel_size = 0.035  # Larger pixel size so text is visible
	cost_label.no_depth_test = false
	cost_label.render_priority = 11  # Higher priority than icon so it renders on top
	cost_label.shaded = false  # Disable shading to prevent clipping issues
	cost_label.double_sided = true  # Render from both sides
	cost_label.alpha_cut = Label3D.ALPHA_CUT_DISABLED  # Ensure proper alpha blending
	# Place on a separate visibility layer to avoid interaction with tank visuals
	cost_label.layers = 2
	add_child(cost_label)
	print("Cost label created at grid position: ", global_position)

func _create_hover_highlight():
	# Create a highlighted square mesh to show which cell is being hovered
	hover_highlight = MeshInstance3D.new()

	# Create a plane mesh the size of one cell
	var plane = PlaneMesh.new()
	plane.size = Vector2(cell_size * 0.95, cell_size * 0.95)  # Slightly smaller than cell
	hover_highlight.mesh = plane

	# Create a bright, semi-transparent material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.3, 0.4)  # Bright green with transparency
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	hover_highlight.set_surface_override_material(0, mat)

	# Position slightly above the grid to avoid z-fighting
	hover_highlight.visible = false
	hover_highlight.layers = 2  # Same layer as cost label/icon
	add_child(hover_highlight)
	print("Hover highlight created")

func _create_sell_marker():
	# Create sell zone OUTSIDE the grid (to the right side)
	var sell_zone_size = Vector3(cell_size * 1.5, 0.5, cell_size * 1.5)

	# Position sell zone to the right of the grid with some spacing
	var sell_zone_position = Vector3(
		- cell_size * 1.5,  # Right of the grid
		0.25,  # Slightly elevated
		grid_size * cell_size / 2.0  # Centered vertically
	)

	# Create Area3D for the sell zone
	sell_zone = Area3D.new()
	sell_zone.collision_layer = 32  # Use layer 32 for sell zone
	sell_zone.collision_mask = 0
	sell_zone.position = sell_zone_position
	add_child(sell_zone)

	# Add collision shape to the sell zone
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"  # Set the name so we can find it later
	var shape = BoxShape3D.new()
	shape.size = sell_zone_size
	collision.shape = shape
	sell_zone.add_child(collision)

	# Create visual marker (larger since it's outside the grid)
	sell_marker = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(sell_zone_size.x * 0.9, sell_zone_size.z * 0.9)
	sell_marker.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.84, 0.0, 0.45) # golden, semi-transparent
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sell_marker.set_surface_override_material(0, mat)

	sell_marker.position = Vector3(0, -0.23, 0)  # Relative to sell_zone
	sell_zone.add_child(sell_marker)

	# Floating label above the marker
	sell_label = Label3D.new()
	sell_label.text = "Sell\nHere"
	# Load and apply LostFish font
	var lost_fish_font = load("res://LostFish-5DOz.ttf")
	if lost_fish_font:
		sell_label.font = lost_fish_font
	sell_label.font_size = 32
	sell_label.modulate = Color(1.0, 0.95, 0.5)
	sell_label.outline_modulate = Color.BLACK
	sell_label.outline_size = 6
	sell_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sell_label.pixel_size = 0.035
	sell_label.no_depth_test = true
	sell_label.render_priority = 10
	sell_label.position = Vector3(0, 1.5, 0)  # Relative to sell_zone
	sell_label.visible = false  # Hidden by default, only show when dragging a tank
	sell_zone.add_child(sell_label)

	# Create a bright highlight for when tank is dragged over sell zone
	sell_highlight = MeshInstance3D.new()
	var highlight_plane = PlaneMesh.new()
	highlight_plane.size = Vector2(sell_zone_size.x * 0.85, sell_zone_size.z * 0.85)
	sell_highlight.mesh = highlight_plane

	var highlight_mat = StandardMaterial3D.new()
	highlight_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5)  # Bright red for selling
	highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	highlight_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	sell_highlight.set_surface_override_material(0, highlight_mat)

	sell_highlight.position = Vector3(0, -0.2, 0)  # Slightly above marker
	sell_highlight.visible = false  # Hidden by default
	sell_zone.add_child(sell_highlight)

# Helper function to get the sell zone's global bounds
func get_sell_zone_bounds() -> Dictionary:
	if not sell_zone:
		print("[GridViz] get_sell_zone_bounds: sell_zone is null!")
		return {}

	var zone_pos = sell_zone.global_position
	var zone_collision = sell_zone.get_node("CollisionShape3D") as CollisionShape3D
	if not zone_collision:
		print("[GridViz] get_sell_zone_bounds: collision shape not found!")
		return {}

	var shape = zone_collision.shape as BoxShape3D
	if not shape:
		print("[GridViz] get_sell_zone_bounds: shape is not BoxShape3D!")
		return {}

	var result = {
		"position": zone_pos,
		"size": shape.size
	}
	print("[GridViz] get_sell_zone_bounds: returning pos=", zone_pos, " size=", shape.size)
	return result

func _on_mouse_entered():
	is_mouse_over_grid = true

func _on_mouse_exited():
	is_mouse_over_grid = false
	hovered_cell = Vector2i(-1, -1)
	if cost_label:
		cost_label.visible = false
	if cost_icon:
		cost_icon.visible = false

func _on_input_event(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int):
	print("_on_input_event called, event type:", event.get_class())
	if event is InputEventMouseButton:
		print("Mouse button event - button:", event.button_index, " pressed:", event.pressed)
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Don't allow buying during tank selection mode
			if Global.is_selecting_tank:
				print("Cannot buy - tank selection mode active")
				return

			# Don't allow buying during tutorial
			if Global.is_tutorial_active:
				print("Cannot buy - tutorial mode active")
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

	# No need to check for sell tile anymore since it's outside the grid

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
		# Play buy sound
		Global.play_sfx(Global.SFX.SELECT_BUY)

		print("Emitting cell_clicked signal for row:", row, " col:", col)
		cell_clicked.emit(row, col)
		print("Signal emitted, new clam balance:", Global.get_clams())

		# Check for game over after spending money (deferred to next frame)
		Global.call_deferred("check_game_over")

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

func _is_tank_over_sell_zone() -> bool:
	# Check if any dragging tank is over the sell zone
	if not sell_zone:
		return false

	var sell_bounds = get_sell_zone_bounds()
	if sell_bounds.is_empty():
		return false

	var sell_pos = sell_bounds["position"] as Vector3
	var sell_size = sell_bounds["size"] as Vector3

	var fish_tank_script = load("res://Scenes/fish_tank.gd")
	if fish_tank_script and "all_tanks" in fish_tank_script:
		var all_tanks = fish_tank_script.all_tanks
		for tank in all_tanks:
			if tank and is_instance_valid(tank) and "is_dragging" in tank and tank.is_dragging:
				# Get tank bounds
				var tank_pos = tank.global_position
				var tank_width = tank.width * tank.cell_size if "width" in tank and "cell_size" in tank else 1.0
				var tank_height = tank.height * tank.cell_size if "height" in tank and "cell_size" in tank else 1.0

				var tank_half_width = tank_width / 2.0
				var tank_half_height = tank_height / 2.0

				# Calculate overlap
				var zone_half_x = sell_size.x * 0.5
				var zone_half_z = sell_size.z * 0.5

				var tank_left = tank_pos.x - tank_half_width
				var tank_right = tank_pos.x + tank_half_width
				var tank_top = tank_pos.z - tank_half_height
				var tank_bottom = tank_pos.z + tank_half_height

				var zone_left = sell_pos.x - zone_half_x
				var zone_right = sell_pos.x + zone_half_x
				var zone_top = sell_pos.z - zone_half_z
				var zone_bottom = sell_pos.z + zone_half_z

				# Check for overlap
				var separated = tank_left > zone_right or tank_right < zone_left or tank_top > zone_bottom or tank_bottom < zone_top
				if not separated:
					return true

	return false

func _process(_delta):
	# Show sell label only when a tank is being dragged
	var tank_is_dragging = _is_any_tank_dragging()
	if sell_label:
		sell_label.visible = tank_is_dragging
	if sell_marker:
		sell_marker.visible = tank_is_dragging

	# Show sell highlight only when a tank is being dragged over the sell zone
	var tank_over_sell_zone = _is_tank_over_sell_zone()
	if sell_highlight:
		sell_highlight.visible = tank_over_sell_zone

	# Don't show cost label during tank selection mode
	if Global.is_selecting_tank:
		if cost_label:
			cost_label.visible = false
		if cost_icon:
			cost_icon.visible = false
		return

	# Don't show cost label during growth sequence
	if Global.is_growth_sequence_active:
		if cost_label:
			cost_label.visible = false
		if cost_icon:
			cost_icon.visible = false
		return

	# Don't show cost label during tutorial
	if Global.is_tutorial_active:
		if cost_label:
			cost_label.visible = false
		if cost_icon:
			cost_icon.visible = false
		if hover_highlight:
			hover_highlight.visible = false
		return

	# Don't show cost label when a tank is being dragged
	if tank_is_dragging:
		if cost_label:
			cost_label.visible = false
		if cost_icon:
			cost_icon.visible = false
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

			# Update cost label and icon
			if cost_label and cost_icon:
				# Position at center of hovered cell, elevated above the ground
				var cell_center = Vector3(
					col * cell_size + cell_size / 2.0,
					2.5,  # Raised higher so it's visible above tanks and grid
					row * cell_size + cell_size / 2.0
				)

				# Position icon to the left and label to the right with more spacing
				var icon_offset = Vector3(-1.3, 0.1, 0)  # Icon on the left, slightly elevated
				var label_offset = Vector3(1.0, 0.1, 0)  # Label further to the right with more space
				cost_icon.global_position = global_position + cell_center + icon_offset
				cost_label.global_position = global_position + cell_center + label_offset

				# Position hover highlight at cell center (on the ground)
				if hover_highlight:
					var highlight_pos = Vector3(
						col * cell_size + cell_size / 2.0,
						0.05,  # Slightly above ground to avoid z-fighting
						row * cell_size + cell_size / 2.0
					)
					hover_highlight.global_position = global_position + highlight_pos

				# Don't show cost label on occupied cells (no sell tile check needed)
				if not _is_cell_occupied(row, col):
					cost_label.text = str(tank_cost)
					if Global.get_clams() >= tank_cost:
						cost_label.modulate = Color.GREEN
					else:
						cost_label.modulate = Color.RED
					cost_label.visible = true
					cost_icon.visible = true
					if hover_highlight:
						hover_highlight.visible = true
				else:
					cost_label.visible = false
					cost_icon.visible = false
					if hover_highlight:
						hover_highlight.visible = false
		else:
			hovered_cell = Vector2i(-1, -1)
			if cost_label:
				cost_label.visible = false
			if cost_icon:
				cost_icon.visible = false
			if hover_highlight:
				hover_highlight.visible = false
	else:
		hovered_cell = Vector2i(-1, -1)
		if cost_label:
			cost_label.visible = false
		if cost_icon:
			cost_icon.visible = false
		if hover_highlight:
			hover_highlight.visible = false

func _unhandled_input(event: InputEvent):
	# Global click handler so empty cells can be purchased even if Area3D doesn't catch it
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Don't allow buying during tank selection mode
			if Global.is_selecting_tank:
				return

			# Don't allow buying during tutorial
			if Global.is_tutorial_active:
				return

			# If we have a valid hovered cell and it's empty, try to buy
			if hovered_cell.x >= 0 and hovered_cell.y >= 0:
				var row = hovered_cell.y
				var col = hovered_cell.x
				if not _is_cell_occupied(row, col):
					_try_buy_tank(row, col)

func _on_tank_selection_started():
	# Hide grid lines during tank selection (sell label controlled by _process)
	if mesh_instance:
		mesh_instance.visible = false
	if cost_label:
		cost_label.visible = false
	if cost_icon:
		cost_icon.visible = false
	if hover_highlight:
		hover_highlight.visible = false

func _on_fish_placed():
	# Show grid lines again after placing the fish (sell label controlled by _process)
	if mesh_instance:
		mesh_instance.visible = true

func _on_growth_sequence_started():
	# Hide grid elements during growth sequence (sell label controlled by _process)
	if mesh_instance:
		mesh_instance.visible = false
	if cost_label:
		cost_label.visible = false
	if cost_icon:
		cost_icon.visible = false
	if hover_highlight:
		hover_highlight.visible = false

func _on_growth_sequence_ended():
	# Show grid elements again after growth sequence (sell label controlled by _process)
	if mesh_instance:
		mesh_instance.visible = true
	# Note: cost_label and sell_label visibility is controlled by _process() based on state
