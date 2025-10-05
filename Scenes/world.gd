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
var fish_spotlight: SpotLight3D = null  # Spotlight for fish showcase

# Water mesh reference
var water_mesh: MeshInstance3D = null

func _ready():
	# Allow the world to process even when paused (for camera animations)
	process_mode = Node.PROCESS_MODE_ALWAYS

	generate_hex_grid()
	update_fish_references()

	# Setup water shader
	_setup_water_shader()

	# Store original camera position for later
	var camera = get_viewport().get_camera_3d()
	if camera:
		original_camera_transform = camera.global_transform

	# Connect to fish placement signal to spawn new fish
	Global.fish_placed_in_tank.connect(_on_fish_placed_in_tank)

	# Connect to grid visualizer for tank purchases
	var grid_visualizer = get_node_or_null("GridVisualizer")
	if grid_visualizer and grid_visualizer.has_signal("cell_clicked"):
		grid_visualizer.cell_clicked.connect(_on_grid_cell_clicked)

	# Set camera to tutorial position immediately (before showing anything)
	_set_camera_to_tutorial_view()

	# Create initial tank and run tutorial
	_initialize_game_start()

	# Set up periodic game over check
	_setup_game_over_check()

# Initialize the game with tank creation and tutorial
func _initialize_game_start():
	# Create initial tank with 3 fish
	await _create_initial_tank_with_fish()

	# Start tutorial sequence (waits for tutorial to complete)
	await _start_tutorial_sequence()

func _setup_game_over_check():
	# Check for game over every few seconds
	while true:
		await get_tree().create_timer(2.0).timeout
		if not Global.is_game_over:
			Global.check_game_over()

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
			tile.position = Vector3(x - offset_x, 0.5, z - offset_z) - Vector3(30, 0, 5)
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

# Setup the water shader for beach-like waves
func _setup_water_shader():
	# Find the water mesh in the scene (it's under Pond/CollisionShape3D/Water)
	var pond = get_node_or_null("Pond")
	if pond:
		var collision_shape = pond.get_node_or_null("CollisionShape3D")
		if collision_shape:
			water_mesh = collision_shape.get_node_or_null("Water")
			if water_mesh and water_mesh is MeshInstance3D:
				# Increase subdivisions for the water plane so waves are visible
				if water_mesh.mesh is PlaneMesh:
					var plane_mesh = water_mesh.mesh as PlaneMesh
					plane_mesh.subdivide_width = 50  # More subdivisions for smoother waves
					plane_mesh.subdivide_depth = 100  # More in the depth direction
					print("[World] Water plane subdivisions set to 50x100")

				# Load the sea wave shader
				var wave_shader = load("res://Scenes/sea_wave.gdshader")
				if wave_shader:
					# Create shader material
					var shader_material = ShaderMaterial.new()
					shader_material.shader = wave_shader

					# Set shader parameters for beach-like waves
					shader_material.set_shader_parameter("wave_speed", 1.2)
					shader_material.set_shader_parameter("wave_height", 0.15)
					shader_material.set_shader_parameter("wave_frequency", 3.0)
					shader_material.set_shader_parameter("wave_direction", Vector3(1.0, 0.0, 0.5))
					shader_material.set_shader_parameter("water_color", Color(0.07, 0.14, 0.47, 1.0))
					shader_material.set_shader_parameter("roughness", 0.3)

					# Apply the shader material to the water mesh
					water_mesh.material_override = shader_material

					print("[World] Water shader applied to pond mesh")
				else:
					push_warning("Could not load sea wave shader")
			else:
				push_warning("Water mesh not found under Pond/CollisionShape3D")

func _on_fish_caught(fish: Node3D, tile: Node3D):
	# Prevent catching multiple fish simultaneously - ignore if already processing a catch
	if Global.is_selecting_tank:
		return

	print("Fish caught at tile: ", tile.position)

	# Remove all nets from all tiles and return 3 nets to inventory
	_remove_all_nets_and_return_to_inventory()

	# First, zoom to the tile to appreciate the catch
	if fish and tile:
		_zoom_to_catch_then_show_fish(fish, tile)

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

func _zoom_to_catch_then_show_fish(fish: Node3D, tile: Node3D):
	# Pause the game world immediately
	get_tree().paused = true

	# Keep the fish visible throughout the entire sequence
	fish.visible = true
	fish.is_moving = false

	# Stop the fish from moving around
	if fish.has_method("set_movement_enabled"):
		fish.set_movement_enabled(false)

	# Disable automatic surface behavior to prevent the fish from auto-submerging
	if "is_surfacing" in fish:
		fish.is_surfacing = false
	if "surface_timer" in fish:
		fish.surface_timer = 0.0
	if "next_surface_time" in fish:
		fish.next_surface_time = 999999.0  # Set to very high value to prevent auto-surfacing

	# Snap the fish to the center of the hexagon tile and raise it
	var tile_center = tile.global_position
	fish.global_position = Vector3(tile_center.x, tile_center.y + 1.5, tile_center.z)

	# Make the fish pop its head out manually (apply the rotation without the timer logic)
	# We don't call _surface() because it would reset timers and trigger auto-submerge
	if "surface_look_angle" in fish:
		var current_basis: Basis = fish.global_transform.basis
		var look_up_rotation: Basis = Basis(Vector3.FORWARD, deg_to_rad(-fish.surface_look_angle))
		fish.global_transform.basis = current_basis * look_up_rotation

	# First, animate camera to the tile to appreciate the catch
	await _animate_camera_to_tile(tile, fish)

	# Wait a moment to appreciate the catch
	var appreciation_timer = get_tree().create_timer(1.0, true, true)  # process_always=true
	await appreciation_timer.timeout

	# Now continue with the tank selection
	_show_fish_for_tank_selection(fish)

func _show_fish_for_tank_selection(fish: Node3D):
	# Store the caught fish globally
	Global.caught_fish = fish
	Global.is_selecting_tank = true
	Global.fish_tank_selection_started.emit()

	# Game is already paused and surface behavior already disabled from _zoom_to_catch_then_show_fish

	# Keep the fish visible during the transition
	fish.visible = true
	fish.is_moving = false

	# Animate camera to tank area (this will also animate the fish)
	_animate_camera_to_tank_area(fish)

# Called when a fish is placed in a tank - spawn a new one
func _on_fish_placed_in_tank():
	print("Spawning new fish in ocean...")

	# Stop the fish rotation tween if it's still running
	if fish_rotation_tween and fish_rotation_tween.is_running():
		fish_rotation_tween.kill()

	# Remove the spotlight
	_remove_fish_spotlight()

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

# Create an initial tank with 3 fish at game start
func _create_initial_tank_with_fish():
	print("Creating initial tank with 3 fish...")

	# Create a new fish tank at the center of the tank area
	var new_tank = fish_tank_scene.instantiate()

	# Set the tank's grid position to center (using Global.house_cell_size for centering)
	new_tank.row = floor(float(Global.house_cell_size) / 2.0)
	new_tank.col = floor(float(Global.house_cell_size) / 2.0)

	# Set the bounds reference
	new_tank.bounds_shape = tank_area

	# Add the tank to the scene
	add_child(new_tank)

	# Wait for the tank to be ready and positioned
	await get_tree().process_frame

	print("Initial tank created at position: ", new_tank.global_position)

	# Spawn 3 fish and add them to the tank
	for i in range(2):
		var new_fish = fish_scene.instantiate()

		# Set the bounds for the fish (will be updated when added to tank)
		new_fish.bounds_shape = pond_bounds

		# Position temporarily in the tank area
		new_fish.global_position = new_tank.global_position

		# Set initial age to 0 for new fish
		new_fish.age = 0

		# Add to the scene first
		add_child(new_fish)

		# Wait a frame for the fish to initialize
		await get_tree().process_frame

		# Now add the fish to the tank (this will position it correctly)
		new_tank.add_fish(new_fish)

		print("Fish ", i + 1, " added to initial tank")

	print("Initial tank setup complete with 3 fish")

# Start the tutorial sequence
func _start_tutorial_sequence():
	# Wait for everything to be initialized
	await get_tree().create_timer(0.5).timeout

	# Show tutorial UI (camera is already in position)
	Global.tutorial_started.emit()
	print("[Tutorial] Started - waiting for tank to be sold")

	# Wait for tutorial to complete (tank sold)
	await Global.tutorial_completed
	print("[Tutorial] Completed signal received")

	# Wait a moment before zooming out
	await get_tree().create_timer(1.0).timeout
	print("[Tutorial] Zooming camera back to original view")

	# Zoom camera back to original view
	_animate_camera_to_original()
	print("[Tutorial] Tutorial sequence finished")

# Set camera to tutorial view instantly (no animation)
func _set_camera_to_tutorial_view():
	var camera = get_viewport().get_camera_3d()
	if not camera or not tank_area:
		return

	# Calculate the center point between tank area and sell zone
	var grid_visualizer = get_node_or_null("GridVisualizer")
	var target_position = tank_area.global_position

	if grid_visualizer and grid_visualizer.has_method("get_sell_zone_bounds"):
		var sell_bounds = grid_visualizer.get_sell_zone_bounds()
		if not sell_bounds.is_empty():
			var sell_pos = sell_bounds["position"] as Vector3
			# Find midpoint between tank area and sell zone
			target_position = tank_area.global_position * 0.5 + sell_pos * 0.5

	# Camera position: above and slightly back from the target
	var camera_offset = Vector3(0, 9, 1)
	var target_camera_position = target_position + camera_offset

	# Calculate rotation to look at the target area
	var direction = (target_position - target_camera_position).normalized()
	var right = direction.cross(Vector3.UP).normalized()
	var up = right.cross(direction).normalized()
	var target_basis = Basis(right, up, -direction)

	# Set camera position and rotation instantly
	camera.global_position = target_camera_position
	camera.global_transform.basis = target_basis

	print("[Tutorial] Camera set to tutorial view")

# Animate camera to zoom to the tile where fish was caught
func _animate_camera_to_tile(tile: Node3D, fish: Node3D):
	var camera = get_viewport().get_camera_3d()
	if not camera or not tile:
		push_warning("Camera or tile not found!")
		return

	# Cancel any existing camera animation
	if camera_tween and camera_tween.is_running():
		camera_tween.kill()

	# Get the tile's position
	var tile_position = tile.global_position

	# Calculate a dramatic close-up viewing position
	# Position camera close and slightly above the tile, looking down at an angle
	var camera_offset = Vector3(2, 3, 2)  # Close, above, and to the side
	var target_camera_position = tile_position + camera_offset

	# Calculate the target rotation (basis) for looking at the fish/tile
	var look_at_position = fish.global_position if fish else tile_position
	var direction = (look_at_position - target_camera_position).normalized()
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

	# Animate camera to the tile
	camera_tween.tween_property(camera, "global_position", target_camera_position, 0.8)
	camera_tween.tween_property(camera, "global_transform:basis", target_basis, 0.8)

	# Wait for animation to complete
	await camera_tween.finished

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
	var camera_offset = Vector3(0, 16, 5)  # Above and behind
	var target_camera_position = tank_center + camera_offset

	# Calculate the target rotation (basis) for looking at tank center
	var direction = (tank_center - target_camera_position).normalized()
	var right = direction.cross(Vector3.UP).normalized()
	var up = right.cross(direction).normalized()
	var target_basis = Basis(right, up, -direction)  # -direction because camera looks down -Z

	# Calculate target fish position and rotation (before camera moves)
	var camera_forward = -target_basis.z
	var camera_right = target_basis.x
	var camera_up = target_basis.y

	# Calculate where the fish should end up
	var target_fish_position = target_camera_position + camera_forward * 5.0
	target_fish_position += camera_up * 0  # Move up
	target_fish_position -= camera_right * 3.5  # Move left

	# Calculate target fish rotation (facing camera)
	var direction_to_camera = (target_camera_position - target_fish_position).normalized()
	var fish_forward = direction_to_camera
	var fish_right = fish_forward.cross(Vector3.UP).normalized()
	var fish_up = fish_right.cross(fish_forward).normalized()
	var target_fish_basis = Basis(fish_forward, fish_up, fish_right)

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

	# Animate fish position and rotation in parallel with camera
	if fish:
		camera_tween.tween_property(fish, "global_position", target_fish_position, 1.0)
		camera_tween.tween_property(fish, "global_transform:basis", target_fish_basis, 1.0)

	# After animation completes, set up the spotlight and rotation
	camera_tween.chain()  # End parallel mode
	camera_tween.tween_callback(func():
		if camera and fish:
			# Create and position spotlight to illuminate the fish
			_create_fish_spotlight(camera, fish)

			# Animate the fish rotating 360 degrees to showcase it
			_rotate_fish_360(fish)
	)

# Create and position a spotlight to illuminate the fish
func _create_fish_spotlight(camera: Camera3D, fish: Node3D):
	# Remove any existing spotlight
	_remove_fish_spotlight()

	# Create a new spotlight
	fish_spotlight = SpotLight3D.new()

	# Configure spotlight properties BEFORE adding to scene
	fish_spotlight.light_energy = 16.0  # Increased brightness
	fish_spotlight.light_color = Color(1.0, 1.0, 0.95)  # Slightly warm white
	fish_spotlight.spot_range = 4096.0  # How far the light reaches
	fish_spotlight.spot_angle = 15.0  # Wider cone angle for better coverage
	fish_spotlight.spot_attenuation = 1.0  # How light fades with distance
	fish_spotlight.shadow_enabled = true  # Enable shadows for more dramatic effect

	# Add to the scene first
	add_child(fish_spotlight)

	# NOW position it at the camera location (after being in scene tree)
	fish_spotlight.global_position = camera.global_position

	# Make the spotlight look at the fish (must be done after adding to scene)
	fish_spotlight.look_at(fish.global_position, Vector3.UP)

	print("Fish spotlight created at camera position: ", camera.global_position)
	print("Fish spotlight looking at fish position: ", fish.global_position)
	print("Distance from spotlight to fish: ", camera.global_position.distance_to(fish.global_position))

# Remove the fish spotlight
func _remove_fish_spotlight():
	if fish_spotlight and is_instance_valid(fish_spotlight):
		fish_spotlight.queue_free()
		fish_spotlight = null
		print("Fish spotlight removed")

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

	# Remove the spotlight (if still present)
	_remove_fish_spotlight()

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
		# Emit signal to hide UI elements
		Global.is_growth_sequence_active = true
		Global.growth_sequence_started.emit()

		for fish in fish_to_grow:
			await _animate_camera_to_fish_and_grow(fish)

		# Emit signal to show UI elements again
		Global.is_growth_sequence_active = false
		Global.growth_sequence_ended.emit()

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
