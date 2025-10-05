extends Node

var house_cell_size: int = 5

# Item definitions
var net_item: ItemData
var items: Array[ItemData] = []

# Inventory tracking (item_id -> count)
var inventory: Dictionary = {}

# Money system
var clams: int = 0
signal clams_changed

# Game over state
var is_game_over: bool = false
signal game_over

# Economy config
var tank_cost: int = 20

# Signal to notify when inventory changes
signal inventory_changed

# Fish tank selection state
var caught_fish: Node3D = null
var is_selecting_tank: bool = false
signal fish_tank_selection_started
signal fish_placed_in_tank

# Global tracking of caught fish to prevent double-catching
var globally_caught_fish: Array[Node3D] = []

# Sell zone config (grid coordinates inside the house grid)
var sell_tile_row: int = 0
var sell_tile_col: int = 0

# Utility: compute sell value for a tank given its contained fish and tank reference
# Rules:
# 1. More fish = more money
# 2. Bigger fish = more money
# 3. 2 big fish > 1 small fish
# 4. Bigger tank = more money
func compute_tank_sell_value(fish_list: Array, tank: Node3D = null) -> int:
	var base_value: int = 1

	# Calculate tank size bonus (bigger tanks are worth more)
	var tank_size_bonus: float = 0.0
	if tank and "width" in tank and "height" in tank:
		var tank_area = tank.width * tank.height
		tank_size_bonus = tank_area * 2.0  # 2 clams per grid cell

	# Calculate total fish value based on size
	var fish_value: float = 0.0
	for fish in fish_list:
		if fish and is_instance_valid(fish):
			# Calculate fish size based on graph complexity (same method as tank capacity)
			var fish_size = _calculate_fish_size(fish)
			# Each unit of fish size is worth 0.5 clams
			fish_value += fish_size * 0.5

	# Total value = base + tank size + fish value
	var total_value: float = base_value + tank_size_bonus + fish_value

	return int(ceil(total_value))

# Calculate fish size based on graph complexity
func _calculate_fish_size(fish: Node3D) -> float:
	if not fish or not "graph" in fish:
		return 10.0  # Default size if fish has no graph

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

	# Size is based on graph complexity (same formula as tank volume calculation)
	# More nodes and edges = more complex = larger size
	var size = (num_nodes * 5.0) + (num_edges * 3.0)

	return size

func _ready():
	# Create the net item
	net_item = ItemData.new()
	net_item.id = "net"
	net_item.display_name = "Net"
	net_item.icon = load("res://icon.svg")
	items.append(net_item)

	# Start with 3 nets
	inventory["net"] = 3
	inventory_changed.emit()

	# Start with 15 clams
	clams = 15
	clams_changed.emit()

func use_item(item_id: StringName) -> bool:
	if inventory.get(item_id, 0) > 0:
		inventory[item_id] -= 1
		inventory_changed.emit()
		return true
	return false

func add_item(item_id: StringName, amount: int = 1):
	inventory[item_id] = inventory.get(item_id, 0) + amount
	inventory_changed.emit()

func get_item_count(item_id: StringName) -> int:
	return inventory.get(item_id, 0)

func get_item_data(item_id: StringName) -> ItemData:
	for item in items:
		if item.id == item_id:
			return item
	return null

# Money management functions
func add_clams(amount: int):
	clams += amount
	clams_changed.emit()

func spend_clams(amount: int) -> bool:
	if clams >= amount:
		clams -= amount
		clams_changed.emit()
		return true
	return false

func get_clams() -> int:
	return clams

# Check for game over condition
func check_game_over() -> bool:
	if is_game_over:
		return true

	# Load the fish tank script to access all_tanks
	var fish_tank_script = load("res://Scenes/fish_tank.gd")
	if not fish_tank_script or not "all_tanks" in fish_tank_script:
		return false

	var all_tanks = fish_tank_script.all_tanks
	var tank_count = 0

	# Count valid tanks
	for tank in all_tanks:
		if tank and is_instance_valid(tank):
			tank_count += 1

	# Robust fallback: if static list is empty, scan the scene tree
	if tank_count == 0:
		var root = get_tree().root
		if root:
			var nodes_to_check: Array = [root]
			while not nodes_to_check.is_empty():
				var node: Node = nodes_to_check.pop_back()
				if node and is_instance_valid(node) and node.get_script() != null:
					var script_path: String = node.get_script().resource_path
					if script_path.ends_with("Scenes/fish_tank.gd"):
						tank_count += 1
				for child in node.get_children():
					nodes_to_check.append(child)

	# Game over if no tanks and can't afford to buy one
	if tank_count == 0 and clams < tank_cost:
		is_game_over = true
		game_over.emit()
		return true

	return false
