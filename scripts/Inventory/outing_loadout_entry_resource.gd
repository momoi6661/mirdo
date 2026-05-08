extends Resource
class_name OutingLoadoutEntryResource

@export var item: ItemData
@export var amount: int = 1
@export var source_id: String = ""
@export var source_name: String = ""
@export var source_slot_index: int = -1


func is_empty() -> bool:
	return item == null or amount <= 0


func clear() -> void:
	item = null
	amount = 0
	source_id = ""
	source_name = ""
	source_slot_index = -1


func setup(new_item: ItemData, new_source_id: String, new_source_name: String, new_source_slot_index: int, new_amount: int = 1) -> void:
	item = new_item
	amount = clampi(new_amount, 1, get_max_stack_size())
	source_id = new_source_id
	source_name = new_source_name
	source_slot_index = new_source_slot_index


func get_source_key() -> String:
	return "%s:%d" % [source_id, source_slot_index]


func get_max_stack_size() -> int:
	if item == null:
		return 1
	if item.outing_category == "weapon":
		return 1
	return maxi(1, item.MaxStackSize)


func can_stack_one_more_from_source(source_key: String) -> bool:
	if is_empty():
		return false
	if get_source_key() != source_key:
		return false
	return amount < get_max_stack_size()


func add_one_to_stack() -> bool:
	if is_empty():
		return false
	if amount >= get_max_stack_size():
		return false
	amount += 1
	return true


func remove_one_from_stack() -> bool:
	if is_empty():
		return false
	amount -= 1
	if amount <= 0:
		clear()
	return true
