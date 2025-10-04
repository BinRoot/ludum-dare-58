extends VBoxContainer

var item_data: ItemData
var item_count: int = 0

@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label

func set_item(data: ItemData, count: int):
	item_data = data
	item_count = count
	update_display()

func update_display():
	if item_data != null and is_node_ready():
		texture_rect.texture = item_data.icon
		label.text = str(item_count)
		visible = item_count > 0
