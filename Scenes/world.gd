extends Node3D

# Hex grid parameters
@export var grid_width: int = 10
@export var grid_height: int = 10
@export var hex_radius: float = 2.0  # Must match the radius in sea_tile.gd
@export var pond_bounds: CollisionShape3D  # Reference to the pond bounds for spawning fish
@export var tank_area: Node3D  # Reference to the fish tank area for camera focus

# Preload scenes
var sea_tile_scene = preload("res://Scenes/sea_tile.tscn")
var fish_scene = preload("res://Scenes/fish.tscn")
var fish_tank_scene = preload("res://Scenes/fish_tank.tscn")
var sea_tiles: Array[Node3D] = []

# Camera animation
var original_camera_transform: Transform3D
var camera_tween: Tween = null
var fish_rotation_tween: Tween = null
var is_growth_sequence_active: bool = false

func _ready():
	# Allow the world to process even when paused (for camera animations)
	process_mode = Node.PROCESS_MODE_ALWAYS

	generate_hex_grid()
	update_fish_references()

	# Store original camera position
	var camera = get_viewport().get_camera_3d()
	if camera:
		original_camera_transform = camera.global_transform

	# Connect to fish placement signal to spawn new fish
	Global.fish_placed_in_tank.connect(_on_fish_placed_in_tank)

	# Connect to grid visualizer for tank purchases
	var grid_visualizer = get_node_or_null("GridVisualizer")
	if grid_visualizer and grid_visualizer.has_signal("cell_clicked"):
		grid_visualizer.cell_clicked.connect(_on_grid_cell_clicked)

func generate_hex_grid():
	var hex_width = hex_radius * 1.0
	var hex_height = hex_radius * sqrt(3.0)

	# Calculate offsets to center the grid
	var total_width = (grid_width - 1) * hex_width * 2 + hex_width
	var total_height = (grid_height - 1) * hex_height
	var offset_x = total_width / 2.0
	var offset_z = total_height / 2.0

	for row in range(grid_height):
		for col in range(grid_width):
			var tile = sea_tile_scene.instantiate()
			var x = col * hex_width * 2
			var z = row * hex_height
			if row % 2 == 1:
				x += hex_width

			# Center the grid around origin
			tile.position = Vector3(x - offset_x, 0, z - offset_z) - Vector3(30, 0, 5)
			add_child(tile)
			sea_tiles.append(tile)

			# Connect to fish caught signal
			tile.fish_caught.connect(_on_fish_caught)

# Find all fish in the scene and pass them to all tiles
func update_fish_references():
	# Find all nodes with the fish script
	var all_fish: Array[Node3D] = []
	_find_fish_recursive(self, all_fish)

	# Pass all fish to each tile
	for tile in sea_tiles:
		for fish_node in all_fish:
			tile.add_fish(fish_node)

# Recursively search for fish nodes
func _find_fish_recursive(node: Node, fish_list: Array[Node3D]):
	# Check if this node has the fish script
	if node.get_script() != null:
		var script_path = node.get_script().resource_path
		if script_path.ends_with("fish.gd"):
			fish_list.append(node as Node3D)

	# Check all children
	for child in node.get_children():
		_find_fish_recursive(child, fish_list)

func _on_fish_caught(fish: Node3D, tile: Node3D):
	print("Fish caught at tile: ", tile.position)

	# Remove all nets from all tiles and return 3 nets to inventory
	_remove_all_nets_and_return_to_inventory()


	# Show the fish close to camera and ask user to select a tank
	if fish:
		_show_fish_for_tank_selection(fish)

func _remove_all_nets_and_return_to_inventory():
	# Count how many nets are actually placed and remove them
	var nets_placed = 0
	for tile in sea_tiles:
		# Check if tile has a net (either fully placed or being cast)
		if tile.has_net or tile.is_casting_net:
			nets_placed += 1
		# Remove the net
		if tile.has_method("consume_net"):
			tile.consume_net()

	# Return only the nets that were actually placed
	if nets_placed > 0:
		Global.add_item("net", nets_placed)

func _show_fish_for_tank_selection(fish: Node3D):
	# Store the caught fish globally
	Global.caught_fish = fish
	Global.is_selecting_tank = true
	Global.fish_tank_selection_started.emit()

	# Pause the game world
	get_tree().paused = true

	# Completely disable surface behavior to prevent flickering
	if "is_surfacing" in fish:
		fish.is_surfacing = false
	if "surface_timer" in fish:
		fish.surface_timer = 0.0
	if "next_surface_time" in fish:
		fish.next_surface_time = 999999.0  # Set to very high value to prevent surfacing

	# Make the fish visible but hide it temporarily during camera transition
	fish.visible = false
	fish.is_moving = false

	# Stop the fish from moving around
	if fish.has_method("set_movement_enabled"):
		fish.set_movement_enabled(false)

	# Animate camera to tank area
	_animate_camera_to_tank_area(fish)

# Called when a fish is placed in a tank - spawn a new one
func _on_fish_placed_in_tank():
	print("Spawning new fish in ocean...")

	# Stop the fish rotation tween if it's still running
	if fish_rotation_tween and fish_rotation_tween.is_running():
		fish_rotation_tween.kill()

	# Clear the global caught fish list (fish has been processed)
	Global.globally_caught_fish.clear()

	_spawn_new_fish()

	# Start the growth sequence for existing tank fish
	await _handle_fish_growth_sequence()

	# Animate camera back to original position after growth sequence
	_animate_camera_to_original()

# Spawn a new fish in the pond/ocean
func _spawn_new_fish():
	if not pond_bounds:
		push_warning("No pond_bounds set! Cannot spawn new fish.")
		return

	# Instantiate a new fish
	var new_fish = fish_scene.instantiate()

	# Set the bounds for the fish to swim in
	new_fish.bounds_shape = pond_bounds

	# Position the fish at a random location within the pond
	var spawn_position = _get_random_pond_position()
	new_fish.global_position = spawn_position

	# Add to the scene
	add_child(new_fish)

	# Register the fish with all sea tiles
	for tile in sea_tiles:
		tile.add_fish(new_fish)

	print("New fish spawned at: ", spawn_position)

# Get a random position within the pond bounds
func _get_random_pond_position() -> Vector3:
	if not pond_bounds:
		return Vector3.ZERO

	var shape = pond_bounds.shape
	if shape is BoxShape3D:
		var box = shape as BoxShape3D
		var size = box.size
		var random_pos = Vector3(
			randf_range(-size.x / 2.0, size.x / 2.0),
			randf_range(-size.y / 2.0, size.y / 2.0),
			randf_range(-size.z / 2.0, size.z / 2.0)
		)
		# Transform to world space
		return pond_bounds.global_transform * random_pos

	# Default fallback
	return pond_bounds.global_position

# Animate camera to look at the tank area
func _animate_camera_to_tank_area(fish: Node3D):
	var camera = get_viewport().get_camera_3d()
	if not camera or not tank_area:
		push_warning("Camera or tank_area not found!")
		return

	# Cancel any existing camera animation
	if camera_tween and camera_tween.is_running():
		camera_tween.kill()

	# Get the center of the tank area
	var tank_center = tank_area.global_position

	# Calculate a nice viewing position above and to the side of the tank area
	var camera_offset = Vector3(0, 12, 5)  # Above and behind
	var target_camera_position = tank_center + camera_offset

	# Calculate the target rotation (basis) for looking at tank center
	var direction = (tank_center - target_camera_position).normalized()
	var right = direction.cross(Vector3.UP).normalized()
	var up = right.cross(direction).normalized()
	var target_basis = Basis(right, up, -direction)  # -direction because camera looks down -Z

	# Create the tween for camera animation
	camera_tween = create_tween()
	camera_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # Work while paused
	camera_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # Continue during pause
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.set_parallel(true)  # Animate position and rotation simultaneously

	# Animate camera position and rotation together
	camera_tween.tween_property(camera, "global_position", target_camera_position, 1.0)
	camera_tween.tween_property(camera, "global_transform:basis", target_basis, 1.0)

	# After animation completes, show the fish
	camera_tween.chain()  # End parallel mode
	camera_tween.tween_callback(func():
		if camera and fish:
			# Show the fish in front of the camera after transition
			var camera_forward = -camera.global_transform.basis.z
			var camera_right = camera.global_transform.basis.x
			var camera_up = camera.global_transform.basis.y

			# Position fish in front, offset to top left
			var fish_position = camera.global_position + camera_forward * 5.0
			fish_position += camera_up * 2  # Move up
			fish_position -= camera_right * 3.5  # Move left

			fish.global_position = fish_position
			fish.visible = true

			# Make the fish face the camera directly
			# Since the fish mesh is oriented along X-axis after rotation (from fish.gd line 360),
			# we need to point the X-axis toward the camera
			var direction_to_camera = (camera.global_position - fish.global_position).normalized()

			# Calculate the basis for the fish to face the camera
			# X-axis (fish forward) points toward camera
			var fish_forward = direction_to_camera
			# Keep the fish upright (Y should roughly align with world up)
			var fish_right = fish_forward.cross(Vector3.UP).normalized()
			# Recalculate up to ensure orthogonality
			var fish_up = fish_right.cross(fish_forward).normalized()

			# Create the basis and apply to the fish
			fish.global_transform.basis = Basis(fish_forward, fish_up, fish_right)

			# Animate the fish rotating 360 degrees to showcase it
			_rotate_fish_360(fish)
	)

# Rotate the fish 360 degrees to showcase it
func _rotate_fish_360(fish: Node3D):
	if not fish:
		return

	# Stop any existing rotation tween
	if fish_rotation_tween and fish_rotation_tween.is_running():
		fish_rotation_tween.kill()

	# Create a tween to rotate the fish
	fish_rotation_tween = create_tween()
	fish_rotation_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # Work while paused
	fish_rotation_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # Continue during pause
	fish_rotation_tween.set_ease(Tween.EASE_IN_OUT)
	fish_rotation_tween.set_trans(Tween.TRANS_SINE)

	# Store the initial rotation
	var initial_rotation = fish.rotation

	# Rotate 360 degrees around the Y-axis (vertical)
	fish_rotation_tween.tween_property(fish, "rotation:y", initial_rotation.y + TAU, 2.0)

	# Loop the rotation continuously until the fish is placed in a tank
	fish_rotation_tween.set_loops()

# Animate camera back to original position
func _animate_camera_to_original():
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	# Cancel any existing camera animation
	if camera_tween and camera_tween.is_running():
		camera_tween.kill()

	# Create the tween for camera animation back
	camera_tween = create_tween()
	camera_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # Work while paused
	camera_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # Continue during pause
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.set_parallel(true)

	# Animate camera back to original position and rotation
	camera_tween.tween_property(camera, "global_position", original_camera_transform.origin, 1.0)
	camera_tween.tween_property(camera, "global_transform:basis", original_camera_transform.basis, 1.0)

# Called when a grid cell is clicked to buy a tank
func _on_grid_cell_clicked(row: int, col: int):
	print("=== Spawning new tank at row: ", row, " col: ", col, " ===")

	# Instantiate a new fish tank
	var new_tank = fish_tank_scene.instantiate()

	# Set the tank's grid position BEFORE adding to scene
	new_tank.row = row
	new_tank.col = col

	# Set the bounds reference (same as existing tank)
	new_tank.bounds_shape = tank_area

	if tank_area:
		print("Tank area position: ", tank_area.global_position)
	else:
		print("Tank area position: null")

	# Add to the scene
	add_child(new_tank)

	# Wait for the tank to be ready and positioned
	await get_tree().process_frame

	print("New tank spawned at world position: ", new_tank.global_position)
	print("Tank grid bounds: ", new_tank.get_grid_bounds() if new_tank.has_method("get_grid_bounds") else "no method")

# ======================
# Fish Growth System
# ======================

# Check if a number is a Fibonacci number
func _is_fibonacci(n: int) -> bool:
	if n < 1:
		return false
	# Generate Fibonacci numbers up to n
	var a = 1
	var b = 1
	if n == 1:
		return true
	while b < n:
		var temp = b
		b = a + b
		a = temp
	return b == n

# Get all fish from all tanks
func _get_all_tank_fish() -> Array[Node3D]:
	var all_fish: Array[Node3D] = []
	# Find all fish tank nodes
	for child in get_children():
		if child.has_method("get") and "contained_fish" in child:
			for fish in child.contained_fish:
				if fish and is_instance_valid(fish) and "is_in_tank" in fish and fish.is_in_tank:
					all_fish.append(fish)
	return all_fish

# Handle the growth sequence after placing a fish
func _handle_fish_growth_sequence() -> void:
	is_growth_sequence_active = true

	# Get all fish in tanks
	var tank_fish = _get_all_tank_fish()

	if tank_fish.is_empty():
		is_growth_sequence_active = false
		return

	# Increment age of all tank fish
	var fish_to_grow: Array[Node3D] = []
	for fish in tank_fish:
		if "age" in fish:
			fish.age += 1
			print("Fish age incremented to: ", fish.age)

			# Check if this fish should grow (Fibonacci age)
			if _is_fibonacci(fish.age):
				fish_to_grow.append(fish)
				print("Fish at Fibonacci age ", fish.age, " will grow!")

	# Animate camera to each growing fish and grow them
	if not fish_to_grow.is_empty():
		for fish in fish_to_grow:
			await _animate_camera_to_fish_and_grow(fish)

	is_growth_sequence_active = false

# Animate camera to a specific fish, grow it, then wait
func _animate_camera_to_fish_and_grow(fish: Node3D) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera or not fish:
		return

	print("Animating camera to growing fish...")

	# Cancel any existing camera animation
	if camera_tween and camera_tween.is_running():
		camera_tween.kill()

	# Calculate camera position to view this fish
	var fish_position = fish.global_position
	var camera_offset = Vector3(0, 3, 3)  # Above and behind the fish
	var target_camera_position = fish_position + camera_offset

	# Calculate the target rotation (basis) for looking at fish
	var direction = (fish_position - target_camera_position).normalized()
	var right = direction.cross(Vector3.UP).normalized()
	var up = right.cross(direction).normalized()
	var target_basis = Basis(right, up, -direction)

	# Create the tween for camera animation to fish
	camera_tween = create_tween()
	camera_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	camera_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.set_parallel(true)

	# Animate camera to fish
	camera_tween.tween_property(camera, "global_position", target_camera_position, 0.8)
	camera_tween.tween_property(camera, "global_transform:basis", target_basis, 0.8)

	# Wait for camera to arrive
	await camera_tween.finished

	# Grow the fish
	if fish.has_method("grow"):
		fish.grow()

	# Wait a moment to appreciate the growth (timer works during pause)
	var growth_timer = get_tree().create_timer(1.0, true, true)  # process_always=true, process_in_physics=true
	await growth_timer.timeout
