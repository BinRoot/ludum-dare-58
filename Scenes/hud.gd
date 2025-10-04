extends CanvasLayer

@onready var inventory_container: HBoxContainer = $InventoryContainer
var inventory_item_scene: PackedScene = preload("res://Scenes/InventoryItem.tscn")
var inventory_items: Dictionary = {}  # item_id -> Array of InventoryItem nodes

func _ready():
	# Connect to global inventory changes
	Global.inventory_changed.connect(_on_inventory_changed)
	# Initial update
	_on_inventory_changed()

func _on_inventory_changed():
	# Update inventory displays for each item type
	for item in Global.items:
		var count = Global.get_item_count(item.id)

		# Get or create the array for this item type
		if item.id not in inventory_items:
			inventory_items[item.id] = []

		var current_items: Array = inventory_items[item.id]
		var current_count = current_items.size()

		# Add more items if count increased
		while current_count < count:
			var inv_item = inventory_item_scene.instantiate()
			inventory_container.add_child(inv_item)
			inv_item.set_item(item)
			current_items.append(inv_item)
			current_count += 1

		# Remove items if count decreased
		while current_count > count:
			var inv_item = current_items.pop_back()
			inv_item.queue_free()
			current_count -= 1
