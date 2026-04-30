extends Node
class_name InventoryDataService

signal inventory_changed
signal slot_changed(slot_index: int)

const SAVE_VERSION := 3
const INVENTORY_STORAGE_SCRIPT := preload("res://scripts/Inventory/inventory_storage_resource.gd")

@export var inventory_storage: InventoryStorageResource
@export var initial_slot_configs: Array[SlotConfig] = []
@export var allow_saved_slot_count_override: bool = false
@export var enable_item_stacking: bool = false

var inventory_visible: bool = false
var _storage_runtime_initialized: bool = false
var _batch_update_depth: int = 0
var _pending_inventory_changed: bool = false
var _pending_slot_changes: Dictionary = {}


func _ready() -> void:
	_ensure_storage()
	_normalize_storage_slots()


func get_slot_count() -> int:
	_ensure_storage()
	return inventory_storage.slot_count


func get_slot_data(slot_index: int) -> Dictionary:
	var slot = _get_slot(slot_index)
	if slot == null or slot.is_empty():
		return _make_empty_slot_data()
	return {"item": slot.item, "amount": slot.amount}


func get_all_slots() -> Array[Dictionary]:
	_ensure_storage()
	var result: Array[Dictionary] = []
	for i in range(inventory_storage.slot_count):
		result.append(get_slot_data(i))
	return result


func has_item_in_slot(slot_index: int) -> bool:
	var slot = _get_slot(slot_index)
	return slot != null and not slot.is_empty()


func PickupItem(item: ItemData, amount: int = 1) -> bool:
	return pickup_item(item, amount)


func pickup_item(item: ItemData, amount: int = 1) -> bool:
	if item == null or amount <= 0:
		return false
	if not CanPickupItem(item, amount):
		return false

	_ensure_storage()
	var remaining: int = amount

	for i in range(inventory_storage.slot_count):
		if remaining <= 0:
			break
		var slot = _get_slot(i)
		if slot == null or slot.is_empty():
			continue
		if slot.item != item:
			continue
		var available: int = _available_stack_space(slot)
		if available <= 0:
			continue
		var add_amount: int = mini(available, remaining)
		slot.amount += add_amount
		remaining -= add_amount
		_emit_slot_changed(i)

	for i in range(inventory_storage.slot_count):
		if remaining <= 0:
			break
		var slot = _get_slot(i)
		if slot == null or not slot.is_empty():
			continue
		var add_amount: int = mini(_max_stack_size(item), remaining)
		slot.set_stack(item, add_amount)
		remaining -= add_amount
		_emit_slot_changed(i)

	_emit_inventory_changed()
	return remaining <= 0


func CanPickupItem(item: ItemData, amount: int = 1) -> bool:
	return can_pickup_item(item, amount)


func can_pickup_item(item: ItemData, amount: int = 1) -> bool:
	if item == null or amount <= 0:
		return false

	_ensure_storage()
	var available_space: int = 0
	for i in range(inventory_storage.slot_count):
		var slot = _get_slot(i)
		if slot == null:
			continue
		if slot.is_empty():
			available_space += _max_stack_size(item)
		elif slot.item == item:
			available_space += _available_stack_space(slot)
	return available_space >= amount


func move_item_between_slots(from_slot_index: int, to_slot_index: int, amount: int = 0) -> int:
	if not _is_valid_slot(from_slot_index) or not _is_valid_slot(to_slot_index):
		return 0
	if from_slot_index == to_slot_index:
		return 0

	var from_slot = _get_slot(from_slot_index)
	var to_slot = _get_slot(to_slot_index)
	if from_slot == null or to_slot == null:
		return 0
	if from_slot.is_empty():
		return 0

	var move_amount: int = from_slot.amount
	if amount > 0:
		move_amount = clampi(amount, 1, from_slot.amount)

	if not to_slot.is_empty() and to_slot.item == from_slot.item:
		var available: int = _available_stack_space(to_slot)
		if available <= 0:
			return 0
		var stacked: int = mini(move_amount, available)
		to_slot.amount += stacked
		from_slot.amount -= stacked
		if from_slot.amount <= 0:
			from_slot.clear()
		_emit_slot_changed(from_slot_index)
		_emit_slot_changed(to_slot_index)
		_emit_inventory_changed()
		return stacked

	if to_slot.is_empty():
		to_slot.set_stack(from_slot.item, move_amount)
		from_slot.amount -= move_amount
		if from_slot.amount <= 0:
			from_slot.clear()
		_emit_slot_changed(from_slot_index)
		_emit_slot_changed(to_slot_index)
		_emit_inventory_changed()
		return move_amount

	if move_amount < from_slot.amount:
		return 0

	var temp_item: ItemData = to_slot.item
	var temp_amount: int = to_slot.amount
	to_slot.set_stack(from_slot.item, from_slot.amount)
	from_slot.set_stack(temp_item, temp_amount)
	_emit_slot_changed(from_slot_index)
	_emit_slot_changed(to_slot_index)
	_emit_inventory_changed()
	return move_amount


func remove_from_slot(slot_index: int, amount: int = 0) -> Dictionary:
	var slot = _get_slot(slot_index)
	if slot == null or slot.is_empty():
		return {"item": null, "amount": 0}

	var take_amount: int = slot.amount
	if amount > 0:
		take_amount = clampi(amount, 1, slot.amount)

	var removed_item: ItemData = slot.item
	slot.amount -= take_amount
	if slot.amount <= 0:
		slot.clear()

	_emit_slot_changed(slot_index)
	_emit_inventory_changed()
	return {"item": removed_item, "amount": take_amount}


func set_slot_data(slot_index: int, item: ItemData, amount: int) -> void:
	var slot = _get_slot(slot_index)
	if slot == null:
		return
	if item == null or amount <= 0:
		slot.clear()
	else:
		slot.set_stack(item, clampi(amount, 1, _max_stack_size(item)))
	_emit_slot_changed(slot_index)
	_emit_inventory_changed()


func clear_inventory() -> void:
	_ensure_storage()
	for i in range(inventory_storage.slot_count):
		var slot = _get_slot(i)
		if slot != null:
			slot.clear()
		_emit_slot_changed(i)
	_emit_inventory_changed()


func get_inventory_data() -> Dictionary:
	_ensure_storage()
	var serialized_slots: Array[Dictionary] = []
	for i in range(inventory_storage.slot_count):
		var slot = _get_slot(i)
		if slot == null or slot.is_empty():
			continue
		serialized_slots.append({
			"slot_id": i,
			"item_path": String(slot.item.resource_path),
			"amount": slot.amount,
		})

	return {
		"version": SAVE_VERSION,
		"enable_item_stacking": enable_item_stacking,
		"slot_count": inventory_storage.slot_count,
		"slots": serialized_slots,
	}


func load_inventory_data(data: Variant) -> void:
	clear_inventory()
	_ensure_storage()

	if data is Dictionary:
		var dict_data: Dictionary = data
		if dict_data.has("enable_item_stacking"):
			enable_item_stacking = bool(dict_data.get("enable_item_stacking", enable_item_stacking))
		if allow_saved_slot_count_override and dict_data.has("slot_count"):
			inventory_storage.slot_count = maxi(1, int(dict_data.get("slot_count", inventory_storage.slot_count)))
			inventory_storage.ensure_capacity()

		var slots_data: Array = dict_data.get("slots", [])
		_load_slot_array_data(slots_data)
		_emit_inventory_changed()
		return

	if data is Array:
		_load_slot_array_data(data)
		_emit_inventory_changed()


func build_inventory_save_payload() -> Dictionary:
	return get_inventory_data()


func apply_inventory_save_payload(payload: Variant) -> void:
	load_inventory_data(payload)


func build_inventory_storage_resource() -> InventoryStorageResource:
	_ensure_storage()
	return inventory_storage.duplicate(true) as InventoryStorageResource


func apply_inventory_storage_resource(storage: InventoryStorageResource) -> void:
	if storage == null:
		return
	inventory_storage = storage.duplicate(true) as InventoryStorageResource
	_storage_runtime_initialized = true
	_ensure_storage()
	_normalize_storage_slots()
	_emit_inventory_changed()


func begin_batch_update() -> void:
	_batch_update_depth += 1


func end_batch_update() -> void:
	if _batch_update_depth <= 0:
		return
	_batch_update_depth -= 1
	if _batch_update_depth == 0:
		_flush_pending_notifications()


func _load_slot_array_data(slots_data: Array) -> void:
	for slot_data_raw in slots_data:
		if not (slot_data_raw is Dictionary):
			continue
		var slot_data: Dictionary = slot_data_raw
		var slot_id: int = int(slot_data.get("slot_id", -1))
		var item_path: String = String(slot_data.get("item_path", "")).strip_edges()
		var amount: int = int(slot_data.get("amount", 0))

		if not _is_valid_slot(slot_id):
			continue
		if item_path.is_empty() or amount <= 0:
			continue
		var item_resource := load(item_path) as ItemData
		if item_resource == null:
			continue
		set_slot_data(slot_id, item_resource, amount)


func _ensure_storage() -> void:
	if inventory_storage == null:
		inventory_storage = INVENTORY_STORAGE_SCRIPT.new()
	if not _storage_runtime_initialized:
		var runtime_storage := inventory_storage.duplicate(true) as InventoryStorageResource
		if runtime_storage == null:
			runtime_storage = INVENTORY_STORAGE_SCRIPT.new() as InventoryStorageResource
		inventory_storage = runtime_storage
		_storage_runtime_initialized = true
	inventory_storage.slot_count = maxi(1, inventory_storage.slot_count)
	inventory_storage.ensure_capacity()


func _normalize_storage_slots() -> void:
	_ensure_storage()
	for i in range(inventory_storage.slot_count):
		var slot := inventory_storage.get_slot(i) as InventorySlotStackResource
		if slot == null:
			continue
		if slot.item == null or slot.amount <= 0:
			slot.clear()
			continue
		slot.amount = clampi(slot.amount, 1, _max_stack_size(slot.item))


func _get_slot(slot_index: int):
	if not _is_valid_slot(slot_index):
		return null
	_ensure_storage()
	return inventory_storage.get_slot(slot_index)


func _is_valid_slot(slot_index: int) -> bool:
	_ensure_storage()
	return slot_index >= 0 and slot_index < inventory_storage.slot_count


func _max_stack_size(item: ItemData) -> int:
	if item == null:
		return 1
	if not enable_item_stacking:
		return 1
	return maxi(1, item.MaxStackSize)


func _available_stack_space(slot) -> int:
	if slot == null or slot.is_empty():
		return 0
	return maxi(0, _max_stack_size(slot.item) - slot.amount)


func _make_empty_slot_data() -> Dictionary:
	return {"item": null, "amount": 0}


func _emit_slot_changed(slot_index: int) -> void:
	if _batch_update_depth > 0:
		_pending_slot_changes[slot_index] = true
		return
	slot_changed.emit(slot_index)


func _emit_inventory_changed() -> void:
	if _batch_update_depth > 0:
		_pending_inventory_changed = true
		return
	inventory_changed.emit()


func _flush_pending_notifications() -> void:
	if not _pending_slot_changes.is_empty():
		var slot_indexes: Array = _pending_slot_changes.keys()
		slot_indexes.sort()
		for slot_index_variant in slot_indexes:
			slot_changed.emit(int(slot_index_variant))
	_pending_slot_changes.clear()

	if _pending_inventory_changed:
		_pending_inventory_changed = false
		inventory_changed.emit()
