extends CanvasLayer

@onready var inventory_container: HBoxContainer = $InventoryContainer
var inventory_item_scene: PackedScene = preload("res://Scenes/InventoryItem.tscn")
var inventory_items: Dictionary = {}  # item_id -> InventoryItem node

func _ready():
	# Connect to global inventory changes
	Global.inventory_changed.connect(_on_inventory_changed)
	# Initial update
	_on_inventory_changed()

func _on_inventory_changed():
	# Update or create inventory item displays for each item
	for item in Global.items:
		var count = Global.get_item_count(item.id)

		if item.id in inventory_items:
			# Update existing display
			inventory_items[item.id].set_item(item, count)
		else:
			# Create new inventory item display
			var inv_item = inventory_item_scene.instantiate()
			inventory_container.add_child(inv_item)
			inventory_items[item.id] = inv_item
			inv_item.set_item(item, count)
