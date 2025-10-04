extends CanvasLayer

@onready var inventory_container: HBoxContainer = $InventoryContainer
var inventory_item_scene: PackedScene = preload("res://Scenes/InventoryItem.tscn")
var inventory_items: Dictionary = {}  # item_id -> Array of InventoryItem nodes

var tank_selection_label: Label = null
var clams_label: Label = null

func _ready():
	# Allow the HUD to continue processing while the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Connect to global inventory changes
	Global.inventory_changed.connect(_on_inventory_changed)
	# Connect to fish tank selection signals
	Global.fish_tank_selection_started.connect(_on_tank_selection_started)
	Global.fish_placed_in_tank.connect(_on_fish_placed)
	# Connect to clams changes
	Global.clams_changed.connect(_on_clams_changed)

	# Create the tank selection label
	_create_tank_selection_label()
	# Create the clams label
	_create_clams_label()

	# Initial update
	_on_inventory_changed()
	_on_clams_changed()

func _create_tank_selection_label():
	tank_selection_label = Label.new()
	tank_selection_label.text = "Click on a fish tank to place the fish!"
	tank_selection_label.add_theme_font_size_override("font_size", 24)
	tank_selection_label.add_theme_color_override("font_color", Color.YELLOW)
	tank_selection_label.add_theme_color_override("font_outline_color", Color.BLACK)
	tank_selection_label.add_theme_constant_override("outline_size", 4)
	tank_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tank_selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tank_selection_label.anchor_left = 0.5
	tank_selection_label.anchor_right = 0.5
	tank_selection_label.anchor_top = 0.1
	tank_selection_label.anchor_bottom = 0.1
	tank_selection_label.offset_left = -300
	tank_selection_label.offset_right = 300
	tank_selection_label.offset_top = -20
	tank_selection_label.offset_bottom = 20
	tank_selection_label.visible = false
	add_child(tank_selection_label)

func _on_tank_selection_started():
	if tank_selection_label:
		tank_selection_label.visible = true

func _on_fish_placed():
	if tank_selection_label:
		tank_selection_label.visible = false

func _create_clams_label():
	clams_label = Label.new()
	clams_label.text = "Clams: 0"
	clams_label.add_theme_font_size_override("font_size", 32)
	clams_label.add_theme_color_override("font_color", Color.WHITE)
	clams_label.add_theme_color_override("font_outline_color", Color.BLACK)
	clams_label.add_theme_constant_override("outline_size", 4)
	clams_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	clams_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	clams_label.anchor_left = 0.0
	clams_label.anchor_right = 0.0
	clams_label.anchor_top = 0.0
	clams_label.anchor_bottom = 0.0
	clams_label.offset_left = 20
	clams_label.offset_top = 20
	clams_label.offset_right = 300
	clams_label.offset_bottom = 60
	add_child(clams_label)

func _on_clams_changed():
	if clams_label:
		clams_label.text = "Clams: " + str(Global.get_clams())

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
