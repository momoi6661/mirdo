extends Resource
class_name InventoryStorageResource

const SLOT_STACK_SCRIPT := preload("res://scripts/Inventory/inventory_slot_stack_resource.gd")

@export_range(1, 120, 1) var slot_count: int = 20
@export var slots: Array[InventorySlotStackResource] = []


func ensure_capacity() -> void:
	slot_count = maxi(1, slot_count)
	while slots.size() < slot_count:
		slots.append(SLOT_STACK_SCRIPT.new() as InventorySlotStackResource)
	while slots.size() > slot_count:
		slots.pop_back()
	for i in range(slot_count):
		var slot := slots[i] as InventorySlotStackResource
		if slot == null:
			slots[i] = SLOT_STACK_SCRIPT.new() as InventorySlotStackResource


func get_slot(slot_index: int):
	if slot_index < 0 or slot_index >= slots.size():
		return null
	return slots[slot_index]


func clear_all() -> void:
	for slot in slots:
		if slot != null and slot.has_method("clear"):
			slot.clear()
