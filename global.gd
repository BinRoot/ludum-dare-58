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

# Signal to notify when inventory changes
signal inventory_changed

# Fish tank selection state
var caught_fish: Node3D = null
var is_selecting_tank: bool = false
signal fish_tank_selection_started
signal fish_placed_in_tank

# Global tracking of caught fish to prevent double-catching
var globally_caught_fish: Array[Node3D] = []

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
