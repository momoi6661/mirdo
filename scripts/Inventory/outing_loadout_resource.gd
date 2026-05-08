extends Resource
class_name OutingLoadoutResource

const LOADOUT_ENTRY_SCRIPT := preload("res://scripts/Inventory/outing_loadout_entry_resource.gd")

@export_range(1, 24, 1) var slot_count: int = 12
@export var entries: Array[Resource] = []


func ensure_capacity() -> void:
	slot_count = clampi(slot_count, 1, 24)
	while entries.size() < slot_count:
		entries.append(LOADOUT_ENTRY_SCRIPT.new() as Resource)
	while entries.size() > slot_count:
		entries.pop_back()
	for i in range(slot_count):
		if entries[i] == null:
			entries[i] = LOADOUT_ENTRY_SCRIPT.new() as Resource


func clear_all() -> void:
	ensure_capacity()
	for entry in entries:
		if entry != null:
			entry.clear()


func get_used_slots() -> int:
	ensure_capacity()
	var used := 0
	for entry in entries:
		if entry != null and not entry.is_empty():
			used += 1
	return used


func get_selected_count_for_source_key(source_key: String) -> int:
	ensure_capacity()
	var count := 0
	for entry in entries:
		if entry == null or entry.is_empty():
			continue
		if entry.get_source_key() == source_key:
			count += int(entry.amount)
	return count


func add_from_entry(entry: Dictionary) -> bool:
	ensure_capacity()
	var item := entry.get("item", null) as ItemData
	if item == null:
		return false
	var source_id := String(entry.get("source_id", ""))
	var source_name := String(entry.get("source_name", ""))
	var source_slot_index := int(entry.get("slot_index", -1))
	var source_key := ShelterInventoryResource.make_entry_key(source_id, source_slot_index)
	var available_amount := maxi(1, int(entry.get("amount", 1)))
	if get_selected_count_for_source_key(source_key) >= available_amount:
		return false

	for loadout_entry in entries:
		if loadout_entry == null or loadout_entry.is_empty():
			continue
		if loadout_entry.can_stack_one_more_from_source(source_key):
			return bool(loadout_entry.add_one_to_stack())

	for loadout_entry in entries:
		if loadout_entry == null or not loadout_entry.is_empty():
			continue
		loadout_entry.setup(
			item,
			source_id,
			source_name,
			source_slot_index,
			1
		)
		return true
	return false


func remove_at(slot_index: int) -> void:
	ensure_capacity()
	if slot_index < 0 or slot_index >= entries.size():
		return
	var entry := entries[slot_index] as Resource
	if entry != null:
		entry.clear()


func remove_one_at(slot_index: int) -> void:
	ensure_capacity()
	if slot_index < 0 or slot_index >= entries.size():
		return
	var entry := entries[slot_index] as Resource
	if entry == null:
		return
	if entry.has_method("remove_one_from_stack"):
		entry.call("remove_one_from_stack")
	else:
		entry.clear()


func get_total_item_count() -> int:
	ensure_capacity()
	var total := 0
	for entry in entries:
		if entry == null or entry.is_empty():
			continue
		total += int(entry.amount)
	return total


func get_selected_names() -> String:
	ensure_capacity()
	var names: Array[String] = []
	for entry in entries:
		if entry == null or entry.is_empty():
			continue
		if int(entry.amount) > 1:
			names.append("%s x%d" % [entry.item.ItemName, int(entry.amount)])
		else:
			names.append(entry.item.ItemName)
	return "无" if names.is_empty() else " / ".join(names)


func get_commit_keys() -> Array[String]:
	ensure_capacity()
	var keys: Array[String] = []
	for entry in entries:
		if entry == null or entry.is_empty():
			continue
		for i in range(int(entry.amount)):
			keys.append(entry.get_source_key())
	return keys


func get_commit_entries() -> Array[Dictionary]:
	ensure_capacity()
	var commit_entries: Array[Dictionary] = []
	for entry in entries:
		if entry == null or entry.is_empty():
			continue
		for i in range(int(entry.amount)):
			commit_entries.append({
				"source_key": entry.get_source_key(),
				"item": entry.item,
				"source_name": entry.source_name,
			})
	return commit_entries
