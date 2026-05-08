extends Resource
class_name ShelterInventoryResource

@export var storage_sources: Array[Resource] = []


func get_available_outing_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for source in storage_sources:
		if source == null or not bool(source.get("include_in_outing_pool")) or source.get("storage") == null:
			continue
		var storage := source.get("storage") as InventoryStorageResource
		storage.ensure_capacity()
		for slot_index in range(storage.slot_count):
			var slot := storage.get_slot(slot_index) as InventorySlotStackResource
			if slot == null or slot.is_empty():
				continue
			if slot.item == null or not slot.item.can_take_outing:
				continue
			entries.append({
				"key": make_entry_key(String(source.get("source_id")), slot_index),
				"source_id": String(source.get("source_id")),
				"source_name": String(source.get("display_name")),
				"source_kind": String(source.get("source_kind")),
				"source": source,
				"slot_index": slot_index,
				"item": slot.item,
				"amount": slot.amount,
				"category": slot.item.outing_category,
			})
	return entries


func get_entry_by_key(entry_key: String) -> Dictionary:
	for entry in get_available_outing_entries():
		if String(entry.get("key", "")) == entry_key:
			return entry
	return {}


func remove_one_from_entry(entry_key: String) -> bool:
	var entry := get_entry_by_key(entry_key)
	if entry.is_empty():
		return false
	var source := entry.get("source", null) as Resource
	if source == null or source.get("storage") == null:
		return false
	var storage := source.get("storage") as InventoryStorageResource
	var slot_index := int(entry.get("slot_index", -1))
	var slot := storage.get_slot(slot_index) as InventorySlotStackResource
	if slot == null or slot.is_empty():
		return false
	slot.amount -= 1
	if slot.amount <= 0:
		slot.clear()
	return true


func add_one_to_entry(entry_key: String, item: ItemData) -> bool:
	if item == null:
		return false
	var parts := entry_key.split(":")
	if parts.size() < 2:
		return false
	var source_id := String(parts[0])
	var slot_index := int(parts[1])
	var source := _get_source_by_id(source_id)
	if source == null or source.get("storage") == null:
		return false
	var storage := source.get("storage") as InventoryStorageResource
	storage.ensure_capacity()
	var slot := storage.get_slot(slot_index) as InventorySlotStackResource
	if slot == null:
		return false
	if slot.is_empty():
		slot.set_stack(item, 1)
		return true
	if slot.item != item:
		return false
	var max_stack := _get_max_stack_size(item)
	if slot.amount >= max_stack:
		return false
	slot.amount += 1
	return true


func count_total_outing_items() -> int:
	var total := 0
	for entry in get_available_outing_entries():
		total += int(entry.get("amount", 0))
	return total


func _get_source_by_id(source_id: String) -> Resource:
	for source in storage_sources:
		if source == null:
			continue
		if String(source.get("source_id")) == source_id:
			return source
	return null


func _get_max_stack_size(item: ItemData) -> int:
	if item == null:
		return 1
	if item.outing_category == "weapon":
		return 1
	return maxi(1, item.MaxStackSize)


static func make_entry_key(source_id: String, slot_index: int) -> String:
	return "%s:%d" % [source_id, slot_index]
