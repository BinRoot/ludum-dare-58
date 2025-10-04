extends Node3D

# Hex grid parameters
@export var grid_width: int = 20
@export var grid_height: int = 20
@export var hex_radius: float = 2.0  # Must match the radius in sea_tile.gd

# Preload the sea tile scene
var sea_tile_scene = preload("res://Scenes/sea_tile.tscn")

func _ready():
	generate_hex_grid()

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
			tile.position = Vector3(x - offset_x, 0, z - offset_z)
			add_child(tile)
