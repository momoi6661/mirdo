extends Resource
class_name ShelterInventoryResource

@export var storage_sources: Array[Resource] = []


func get_available_outing_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for source in storage_sources:
		var storage := _get_storage_from_source(source)
		if source == null or storage == null or not bool(source.get("include_in_outing_pool")):
			continue
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
	var storage := _get_storage_from_source(source)
	if source == null or storage == null:
		return false
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
	var storage := _get_storage_from_source(source)
	if source == null or storage == null:
		return false
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


func add_items_to_return_bag(item: ItemData, amount: int) -> int:
	if item == null or amount <= 0:
		return 0
	var source := _get_source_by_id("temporary_return_bag")
	if source == null:
		source = _get_first_source_for_item(item)
	var storage := _get_storage_from_source(source)
	if source == null or storage == null:
		return 0
	storage.ensure_capacity()
	var remaining := amount
	var max_stack := _get_max_stack_size(item)

	for slot_index in range(storage.slot_count):
		if remaining <= 0:
			break
		var slot := storage.get_slot(slot_index) as InventorySlotStackResource
		if slot == null or slot.is_empty() or slot.item != item:
			continue
		var room := maxi(0, max_stack - int(slot.amount))
		if room <= 0:
			continue
		var add_amount := mini(room, remaining)
		slot.amount += add_amount
		remaining -= add_amount

	for slot_index in range(storage.slot_count):
		if remaining <= 0:
			break
		var slot := storage.get_slot(slot_index) as InventorySlotStackResource
		if slot == null or not slot.is_empty():
			continue
		var add_amount := mini(max_stack, remaining)
		slot.set_stack(item, add_amount)
		remaining -= add_amount
	return amount - remaining


func add_items_to_best_storage(item: ItemData, amount: int) -> int:
	if item == null or amount <= 0:
		return 0
	var preferred_sources := _get_preferred_sources_for_item(item)
	var remaining := amount
	for source in preferred_sources:
		if remaining <= 0:
			break
		remaining -= _insert_into_source_storage(source, item, remaining)
	if remaining > 0:
		remaining -= add_items_to_return_bag(item, remaining)
	return amount - remaining


func count_total_outing_items() -> int:
	var total := 0
	for entry in get_available_outing_entries():
		total += int(entry.get("amount", 0))
	return total


func _get_first_source_for_item(item: ItemData) -> Resource:
	var preferred_kind := _preferred_source_kind_for_item(item)
	for source in storage_sources:
		if source == null or _get_storage_from_source(source) == null:
			continue
		if String(source.get("source_kind")) == preferred_kind:
			return source
	for source in storage_sources:
		if source != null and _get_storage_from_source(source) != null:
			return source
	return null


func _get_preferred_sources_for_item(item: ItemData) -> Array[Resource]:
	var result: Array[Resource] = []
	if item == null:
		return result
	var preferred_kinds := _preferred_source_kinds_for_item(item)
	for source in storage_sources:
		if source == null or _get_storage_from_source(source) == null:
			continue
		if not preferred_kinds.has(String(source.get("source_kind"))):
			continue
		if _source_can_accept_item(source, item):
			result.append(source)
	return result


func _preferred_source_kinds_for_item(item: ItemData) -> Array[String]:
	if item == null:
		return ["temporary"]
	match item.outing_category:
		"food":
			return ["food"]
		"medical":
			return ["medical"]
		"material":
			return ["material"]
		"weapon", "tool", "special":
			return ["equipment"]
		_:
			return ["temporary"]


func _source_can_accept_item(source: Resource, item: ItemData) -> bool:
	if source == null or item == null:
		return false
	var source_id := String(source.get("source_id"))
	var kind := String(source.get("source_kind"))
	match kind:
		"food":
			return item.outing_category == "food" and item.inventory_tags.has("食品柜")
		"medical":
			return item.outing_category == "medical"
		"equipment":
			return item.outing_category in ["weapon", "tool", "special"]
		"material":
			return item.outing_category == "material"
		"temporary":
			return source_id == "temporary_return_bag"
		_:
			return item.outing_category == kind


func _insert_into_source_storage(source: Resource, item: ItemData, amount: int) -> int:
	if source == null or item == null or amount <= 0:
		return 0
	var storage := _get_storage_from_source(source)
	if storage == null:
		return 0
	storage.ensure_capacity()
	var remaining := amount
	var max_stack := _get_max_stack_size(item)

	for slot_index in range(storage.slot_count):
		if remaining <= 0:
			break
		var slot := storage.get_slot(slot_index) as InventorySlotStackResource
		if slot == null or slot.is_empty() or slot.item != item:
			continue
		var room := maxi(0, max_stack - int(slot.amount))
		if room <= 0:
			continue
		var add_amount := mini(room, remaining)
		slot.amount += add_amount
		remaining -= add_amount

	for slot_index in range(storage.slot_count):
		if remaining <= 0:
			break
		var slot := storage.get_slot(slot_index) as InventorySlotStackResource
		if slot == null or not slot.is_empty():
			continue
		var add_amount := mini(max_stack, remaining)
		slot.set_stack(item, add_amount)
		remaining -= add_amount
	return amount - remaining


func _get_storage_from_source(source: Resource) -> InventoryStorageResource:
	if source == null:
		return null
	return source as InventoryStorageResource


func _preferred_source_kind_for_item(item: ItemData) -> String:
	if item == null:
		return "temporary"
	match item.outing_category:
		"food":
			return "food"
		"medical":
			return "medical"
		"weapon", "tool", "special":
			return "equipment"
		_:
			return "material"


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
