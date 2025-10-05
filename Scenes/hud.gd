extends CanvasLayer

@onready var inventory_container: HBoxContainer = $InventoryContainer
var inventory_item_scene: PackedScene = preload("res://Scenes/InventoryItem.tscn")
var inventory_items: Dictionary = {}  # item_id -> Array of InventoryItem nodes

var tank_selection_label: Label = null
var clams_container: HBoxContainer = null
var clams_icon: TextureRect = null
var clams_label: Label = null
var game_over_panel: Panel = null
var game_over_label: Label = null
var restart_button: Button = null
var win_panel: Panel = null
var win_label: Label = null
var win_restart_button: Button = null

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
	# Connect to game over signal
	Global.game_over.connect(_on_game_over)
	# Connect to win signal
	Global.game_won.connect(_on_game_won)
	# Connect to growth sequence signals
	Global.growth_sequence_started.connect(_on_growth_sequence_started)
	Global.growth_sequence_ended.connect(_on_growth_sequence_ended)

	# Create the tank selection label
	_create_tank_selection_label()
	# Create the clams label
	_create_clams_label()
	# Create the game over screen
	_create_game_over_screen()
	# Create the win screen
	_create_win_screen()

	# Initial update
	_on_inventory_changed()
	_on_clams_changed()

func _create_tank_selection_label():
	tank_selection_label = Label.new()
	tank_selection_label.text = "Give your fish a home!"
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
	# Hide the inventory container during tank selection
	if inventory_container:
		inventory_container.visible = false
	# Hide the clams display during tank selection
	if clams_container:
		clams_container.visible = false
	# Hide the combine buttons during tank selection
	_hide_combine_buttons()

func _on_fish_placed():
	if tank_selection_label:
		tank_selection_label.visible = false
	# Show the inventory container again after placing the fish
	if inventory_container:
		inventory_container.visible = true
	# Show the clams display again after placing the fish
	if clams_container:
		clams_container.visible = true
	# Show the combine buttons again after placing the fish
	_show_combine_buttons()

func _on_growth_sequence_started():
	# Hide inventory and money during growth sequence
	if inventory_container:
		inventory_container.visible = false
	if clams_container:
		clams_container.visible = false
	# Hide the combine buttons during growth sequence
	_hide_combine_buttons()

func _on_growth_sequence_ended():
	# Show inventory and money again after growth sequence
	if inventory_container:
		inventory_container.visible = true
	if clams_container:
		clams_container.visible = true
	# Show the combine buttons again after growth sequence
	_show_combine_buttons()

func _create_clams_label():
	# Create a container to hold the icon and number
	clams_container = HBoxContainer.new()
	clams_container.anchor_left = 1.0
	clams_container.anchor_right = 1.0
	clams_container.anchor_top = 0.0
	clams_container.anchor_bottom = 0.0
	clams_container.offset_left = -300
	clams_container.offset_top = 20
	clams_container.offset_right = -20
	clams_container.offset_bottom = 70
	add_child(clams_container)

	# Create the coin icon
	clams_icon = TextureRect.new()
	clams_icon.texture = load("res://coin.svg")
	clams_icon.custom_minimum_size = Vector2(48, 48)
	clams_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	clams_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clams_container.add_child(clams_icon)

	# Create the number label
	clams_label = Label.new()
	clams_label.text = "0"
	clams_label.add_theme_font_size_override("font_size", 32)
	clams_label.add_theme_color_override("font_color", Color.WHITE)
	clams_label.add_theme_color_override("font_outline_color", Color.BLACK)
	clams_label.add_theme_constant_override("outline_size", 4)
	clams_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clams_container.add_child(clams_label)

func _on_clams_changed():
	if clams_label:
		clams_label.text = str(Global.get_clams())

func _create_game_over_screen():
	# Create a semi-transparent dark panel that covers the screen
	game_over_panel = Panel.new()
	game_over_panel.anchor_left = 0.0
	game_over_panel.anchor_right = 1.0
	game_over_panel.anchor_top = 0.0
	game_over_panel.anchor_bottom = 1.0
	game_over_panel.visible = false

	# Style the panel
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	game_over_panel.add_theme_stylebox_override("panel", style_box)

	add_child(game_over_panel)

	# Create game over label
	game_over_label = Label.new()
	game_over_label.text = "GAME OVER\n\nYou're unable to buy any more tanks!"
	game_over_label.add_theme_font_size_override("font_size", 48)
	game_over_label.add_theme_color_override("font_color", Color.RED)
	game_over_label.add_theme_color_override("font_outline_color", Color.BLACK)
	game_over_label.add_theme_constant_override("outline_size", 8)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	game_over_label.anchor_left = 0.0
	game_over_label.anchor_right = 1.0
	game_over_label.anchor_top = 0.2
	game_over_label.anchor_bottom = 0.5

	game_over_panel.add_child(game_over_label)

	# Create restart button
	restart_button = Button.new()
	restart_button.text = "RESTART"
	restart_button.custom_minimum_size = Vector2(300, 80)
	restart_button.add_theme_font_size_override("font_size", 36)

	# Style the button
	var button_normal = StyleBoxFlat.new()
	button_normal.bg_color = Color(0.8, 0.2, 0.2, 0.9)
	button_normal.border_color = Color(1.0, 0.3, 0.3, 1.0)
	button_normal.set_border_width_all(3)
	button_normal.corner_radius_top_left = 10
	button_normal.corner_radius_top_right = 10
	button_normal.corner_radius_bottom_left = 10
	button_normal.corner_radius_bottom_right = 10
	restart_button.add_theme_stylebox_override("normal", button_normal)

	var button_hover = StyleBoxFlat.new()
	button_hover.bg_color = Color(1.0, 0.3, 0.3, 1.0)
	button_hover.border_color = Color(1.0, 0.5, 0.5, 1.0)
	button_hover.set_border_width_all(3)
	button_hover.corner_radius_top_left = 10
	button_hover.corner_radius_top_right = 10
	button_hover.corner_radius_bottom_left = 10
	button_hover.corner_radius_bottom_right = 10
	restart_button.add_theme_stylebox_override("hover", button_hover)

	var button_pressed = StyleBoxFlat.new()
	button_pressed.bg_color = Color(0.6, 0.1, 0.1, 1.0)
	button_pressed.border_color = Color(0.8, 0.2, 0.2, 1.0)
	button_pressed.set_border_width_all(3)
	button_pressed.corner_radius_top_left = 10
	button_pressed.corner_radius_top_right = 10
	button_pressed.corner_radius_bottom_left = 10
	button_pressed.corner_radius_bottom_right = 10
	restart_button.add_theme_stylebox_override("pressed", button_pressed)

	# Position the button horizontally centered, but lower vertically
	restart_button.anchor_left = 0.5
	restart_button.anchor_right = 0.5
	restart_button.anchor_top = 0.65
	restart_button.anchor_bottom = 0.65
	restart_button.offset_left = -150
	restart_button.offset_right = 150
	restart_button.offset_top = -40
	restart_button.offset_bottom = 40

	# Connect button signal
	restart_button.pressed.connect(_on_restart_pressed)

	game_over_panel.add_child(restart_button)

func _create_win_screen():
	# Create a semi-transparent dark panel that covers the screen
	win_panel = Panel.new()
	win_panel.anchor_left = 0.0
	win_panel.anchor_right = 1.0
	win_panel.anchor_top = 0.0
	win_panel.anchor_bottom = 1.0
	win_panel.visible = false

	# Style the panel with a golden tint
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.2, 0.1, 0.85)  # Dark green tint
	win_panel.add_theme_stylebox_override("panel", style_box)

	add_child(win_panel)

	# Create win label
	win_label = Label.new()
	win_label.text = "CONGRATULATIONS!\n\nYou built the ultimate aquarium!"
	win_label.add_theme_font_size_override("font_size", 48)
	win_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))  # Bright green
	win_label.add_theme_color_override("font_outline_color", Color.BLACK)
	win_label.add_theme_constant_override("outline_size", 8)
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	win_label.anchor_left = 0.0
	win_label.anchor_right = 1.0
	win_label.anchor_top = 0.15
	win_label.anchor_bottom = 0.5

	win_panel.add_child(win_label)

	# Create restart button
	win_restart_button = Button.new()
	win_restart_button.text = "PLAY AGAIN"
	win_restart_button.custom_minimum_size = Vector2(300, 80)
	win_restart_button.add_theme_font_size_override("font_size", 36)

	# Style the button with green theme
	var button_normal = StyleBoxFlat.new()
	button_normal.bg_color = Color(0.2, 0.8, 0.2, 0.9)
	button_normal.border_color = Color(0.3, 1.0, 0.3, 1.0)
	button_normal.set_border_width_all(3)
	button_normal.corner_radius_top_left = 10
	button_normal.corner_radius_top_right = 10
	button_normal.corner_radius_bottom_left = 10
	button_normal.corner_radius_bottom_right = 10
	win_restart_button.add_theme_stylebox_override("normal", button_normal)

	var button_hover = StyleBoxFlat.new()
	button_hover.bg_color = Color(0.3, 1.0, 0.3, 1.0)
	button_hover.border_color = Color(0.5, 1.0, 0.5, 1.0)
	button_hover.set_border_width_all(3)
	button_hover.corner_radius_top_left = 10
	button_hover.corner_radius_top_right = 10
	button_hover.corner_radius_bottom_left = 10
	button_hover.corner_radius_bottom_right = 10
	win_restart_button.add_theme_stylebox_override("hover", button_hover)

	var button_pressed = StyleBoxFlat.new()
	button_pressed.bg_color = Color(0.1, 0.6, 0.1, 1.0)
	button_pressed.border_color = Color(0.2, 0.8, 0.2, 1.0)
	button_pressed.set_border_width_all(3)
	button_pressed.corner_radius_top_left = 10
	button_pressed.corner_radius_top_right = 10
	button_pressed.corner_radius_bottom_left = 10
	button_pressed.corner_radius_bottom_right = 10
	win_restart_button.add_theme_stylebox_override("pressed", button_pressed)

	# Position the button horizontally centered, but lower vertically
	win_restart_button.anchor_left = 0.5
	win_restart_button.anchor_right = 0.5
	win_restart_button.anchor_top = 0.65
	win_restart_button.anchor_bottom = 0.65
	win_restart_button.offset_left = -150
	win_restart_button.offset_right = 150
	win_restart_button.offset_top = -40
	win_restart_button.offset_bottom = 40

	# Connect button signal (reuse the same restart function)
	win_restart_button.pressed.connect(_on_restart_pressed)

	win_panel.add_child(win_restart_button)

func _on_game_over():
	print("Game Over!")
	if game_over_panel:
		game_over_panel.visible = true
	# Pause the game
	get_tree().paused = true

func _on_game_won():
	print("You Win!")
	if win_panel:
		win_panel.visible = true
	# Pause the game
	get_tree().paused = true

func _on_restart_pressed():
	print("Restarting game...")
	# Reset the global state completely
	_reset_game_state()
	# Unpause and reload the scene
	get_tree().paused = false
	get_tree().reload_current_scene()

func _reset_game_state():
	# Reset game over flag
	Global.is_game_over = false
	# Reset win flag
	Global.has_won = false

	# Reset money to starting amount
	Global.clams = 15

	# Reset inventory to starting items
	Global.inventory.clear()
	Global.inventory["net"] = 3

	# Clear any caught fish state
	Global.caught_fish = null
	Global.is_selecting_tank = false
	Global.globally_caught_fish.clear()

func _hide_combine_buttons():
	# Find and hide the CombineButtonLayer
	var root = get_tree().root
	for child in root.get_children():
		if child.name == "CombineButtonLayer":
			child.visible = false
			return

func _show_combine_buttons():
	# Find and show the CombineButtonLayer
	var root = get_tree().root
	for child in root.get_children():
		if child.name == "CombineButtonLayer":
			child.visible = true
			return

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
