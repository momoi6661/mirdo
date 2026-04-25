extends Resource
class_name InventorySlotStackResource

@export var item: ItemData
@export_range(0, 9999, 1) var amount: int = 0


func is_empty() -> bool:
	return item == null or amount <= 0


func clear() -> void:
	item = null
	amount = 0


func set_stack(new_item: ItemData, new_amount: int) -> void:
	item = new_item
	amount = maxi(0, new_amount)
	if amount <= 0:
		item = null
