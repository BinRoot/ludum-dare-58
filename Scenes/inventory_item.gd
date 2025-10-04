extends TextureRect

var item_data: ItemData

func set_item(data: ItemData):
	item_data = data
	if item_data != null:
		texture = item_data.icon
