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

# Sell zone config (grid coordinates inside the house grid)
var sell_tile_row: int = 0
var sell_tile_col: int = 0

# Utility: compute sell value for a tank given its contained fish colors
# Rules: 1 base clam for empty tank, +3 per fish, and x2 multiplier
# if all fish hues fall within a small hue range (same-color heuristic)
func compute_tank_sell_value(fish_list: Array) -> int:
	var base_value: int = 1
	var fish_count: int = 0
	var hues: Array = []

	for fish in fish_list:
		if fish and is_instance_valid(fish):
			fish_count += 1
			# Try to read a representative color; fall back to white
			var c: Color = Color(1, 1, 1)
			if "base_color" in fish:
				c = fish.base_color
			elif fish.has_method("get_color"):
				c = fish.get_color()
			hues.append(c.h)

	var value: int = base_value + (fish_count * 3)

	if fish_count > 1 and _hues_within_same_range(hues):
		value *= 2

	return value

# Determine if all hues are within a threshold when accounting for wrap-around
func _hues_within_same_range(hues: Array) -> bool:
	if hues.size() <= 1:
		return true

	# Sort hues for easier span checks
	hues.sort()
	var threshold: float = 0.08  # ~30 degrees on hue circle (0..1)

	# Direct span
	var span_direct: float = hues[hues.size() - 1] - hues[0]
	if span_direct <= threshold:
		return true

	# Wrapped span: map hues < first+threshold to +1 space to check wrap-around
	var wrapped: Array = []
	var base: float = hues[0]
	for h in hues:
		var hw: float = h
		if h < base:
			hw = h + 1.0
		wrapped.append(hw)
	wrapped.sort()
	var span_wrapped: float = wrapped[wrapped.size() - 1] - wrapped[0]
	return span_wrapped <= threshold

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
