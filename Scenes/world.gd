extends Node3D

# Hex grid parameters
@export var grid_width: int = 10
@export var grid_height: int = 10
@export var hex_radius: float = 2.0  # Must match the radius in sea_tile.gd

# Preload the sea tile scene
var sea_tile_scene = preload("res://Scenes/sea_tile.tscn")
var sea_tiles: Array[Node3D] = []

func _ready():
	generate_hex_grid()
	update_fish_references()

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
	# Consume the net from the tile (it was used to catch the fish)
	if tile:
		tile.consume_net()

	# Show the fish close to camera and ask user to select a tank
	if fish:
		_show_fish_for_tank_selection(fish)

func _show_fish_for_tank_selection(fish: Node3D):
	# Store the caught fish globally
	Global.caught_fish = fish
	Global.is_selecting_tank = true
	Global.fish_tank_selection_started.emit()

	# Pause the game world
	get_tree().paused = true

	# Make the fish visible and move it close to the camera
	fish.visible = true

	# Get the camera
	var camera = get_viewport().get_camera_3d()
	if camera:
		# Position fish in front of camera (closer view)
		var camera_forward = -camera.global_transform.basis.z
		var fish_position = camera.global_position + camera_forward * 5.0
		fish.global_position = fish_position

		# Make it face the camera
		fish.look_at(camera.global_position, Vector3.UP)

		# Stop the fish from moving around
		if fish.has_method("set_movement_enabled"):
			fish.set_movement_enabled(false)
		fish.is_moving = false
