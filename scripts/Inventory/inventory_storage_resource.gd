extends Resource
class_name InventoryStorageResource

const SLOT_STACK_SCRIPT := preload("res://scripts/Inventory/inventory_slot_stack_resource.gd")

@export_range(1, 120, 1) var slot_count: int = 20
@export var slots: Array[InventorySlotStackResource] = []

@export_group("Shelter Source")
@export var source_id: StringName
@export var display_name: String = "储物点"
@export_enum("food", "medical", "material", "equipment", "temporary", "special") var source_kind: String = "material"
@export var include_in_outing_pool: bool = true
@export_multiline var notes: String = ""


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


func is_valid_source() -> bool:
	return not String(source_id).strip_edges().is_empty()
