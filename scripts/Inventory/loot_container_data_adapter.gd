extends InventoryDataService
class_name LootContainerDataAdapter

@export var container_path: NodePath
const ADAPTER_DEBUG := true

var _container: LootContainerComponent
var _pending_container_sync: bool = false


func _ready() -> void:
	_resolve_container()


func bind_container(container: LootContainerComponent) -> void:
	_container = container
	_notify_changed({})


func unbind_container() -> void:
	_container = null
	inventory_changed.emit()


func get_bound_container() -> LootContainerComponent:
	return _resolve_container()


func get_slot_count() -> int:
	var container := _resolve_container()
	if container == null:
		return 0
	return maxi(0, container.container_size)


func get_slot_data(slot_index: int) -> Dictionary:
	var slot := _get_storage_slot(slot_index)
	if ADAPTER_DEBUG and slot == null:
		var container := _resolve_container()
		var container_name: String = container.name if container != null else "null"
		var runtime_count: int = container.runtime_slots.size() if container != null else -1
		print("[LootAdapter] get_slot_data slot_null slot=", slot_index, " container=", container_name, " runtime_count=", runtime_count)
	if slot == null or slot.item == null or slot.amount <= 0:
		return {"item": null, "amount": 0}
	return {
		"item": slot.item,
		"amount": slot.amount,
	}


func get_all_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var slot_count: int = get_slot_count()
	for i in range(slot_count):
		result.append(get_slot_data(i))
	return result


func has_item_in_slot(slot_index: int) -> bool:
	var slot := _get_storage_slot(slot_index)
	return slot != null and slot.item != null and slot.amount > 0


func PickupItem(item: ItemData, amount: int = 1) -> bool:
	return pickup_item(item, amount)


func pickup_item(item: ItemData, amount: int = 1) -> bool:
	return insert_item(item, amount) == amount


func CanPickupItem(item: ItemData, amount: int = 1) -> bool:
	return can_pickup_item(item, amount)


func can_pickup_item(item: ItemData, amount: int = 1) -> bool:
	if item == null or amount <= 0:
		return false
	if not _container_can_accept_item(item):
		return false
	var available: int = _compute_available_space(item)
	return available >= amount


func insert_item(item: ItemData, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return 0
	var container := _resolve_container()
	if container == null:
		return 0
	if not _container_can_accept_item(item):
		return 0

	var changed := {}
	var remaining: int = amount

	for i in range(container.container_size):
		if remaining <= 0:
			break
		var slot := _get_storage_slot(i)
		if slot == null or slot.item != item or slot.amount <= 0:
			continue
		var space: int = _available_stack_space(slot)
		if space <= 0:
			continue
		var add_amount: int = mini(space, remaining)
		slot.amount += add_amount
		remaining -= add_amount
		changed[i] = true

	for i in range(container.container_size):
		if remaining <= 0:
			break
		var slot := _get_storage_slot(i)
		if slot == null:
			continue
		if slot.item != null and slot.amount > 0:
			continue
		var add_amount: int = mini(_max_stack_size(item), remaining)
		slot.set_stack(item, add_amount)
		remaining -= add_amount
		changed[i] = true

	_notify_changed(changed)
	return amount - remaining


func move_item_between_slots(from_slot_index: int, to_slot_index: int, amount: int = 0) -> int:
	if not _is_valid_slot(from_slot_index) or not _is_valid_slot(to_slot_index):
		return 0
	if from_slot_index == to_slot_index:
		return 0

	var from_slot := _get_storage_slot(from_slot_index)
	var to_slot := _get_storage_slot(to_slot_index)
	if from_slot == null or to_slot == null:
		return 0
	if from_slot.item == null or from_slot.amount <= 0:
		return 0
	if not _container_can_accept_item(from_slot.item):
		return 0

	var move_amount: int = from_slot.amount
	if amount > 0:
		move_amount = clampi(amount, 1, from_slot.amount)

	var changed := {}
	if to_slot.item != null and to_slot.item == from_slot.item:
		var available: int = _available_stack_space(to_slot)
		if available <= 0:
			return 0
		var stacked: int = mini(move_amount, available)
		to_slot.amount += stacked
		from_slot.amount -= stacked
		if from_slot.amount <= 0:
			from_slot.clear()
		changed[from_slot_index] = true
		changed[to_slot_index] = true
		_notify_changed(changed)
		return stacked

	if to_slot.item == null or to_slot.amount <= 0:
		to_slot.set_stack(from_slot.item, move_amount)
		from_slot.amount -= move_amount
		if from_slot.amount <= 0:
			from_slot.clear()
		changed[from_slot_index] = true
		changed[to_slot_index] = true
		_notify_changed(changed)
		return move_amount

	if move_amount < from_slot.amount:
		return 0

	var temp_item: ItemData = to_slot.item
	var temp_amount: int = to_slot.amount
	to_slot.set_stack(from_slot.item, from_slot.amount)
	from_slot.set_stack(temp_item, temp_amount)
	changed[from_slot_index] = true
	changed[to_slot_index] = true
	_notify_changed(changed)
	return move_amount


func remove_from_slot(slot_index: int, amount: int = 0) -> Dictionary:
	var slot := _get_storage_slot(slot_index)
	if slot == null or slot.item == null or slot.amount <= 0:
		return {"item": null, "amount": 0}

	var take_amount: int = slot.amount
	if amount > 0:
		take_amount = clampi(amount, 1, slot.amount)

	var removed_item: ItemData = slot.item
	slot.amount -= take_amount
	if slot.amount <= 0:
		slot.clear()

	_notify_changed({slot_index: true})
	return {
		"item": removed_item,
		"amount": take_amount,
	}


func set_slot_data(slot_index: int, item: ItemData, amount: int) -> void:
	var slot := _get_storage_slot(slot_index)
	if ADAPTER_DEBUG:
		var container := _resolve_container()
		var container_name: String = container.name if container != null else "null"
		var runtime_count: int = container.runtime_slots.size() if container != null else -1
		var item_path: String = item.resource_path if item != null else "null"
		print("[LootAdapter] set_slot_data slot=", slot_index, " item=", item_path, " amount=", amount, " slot_null=", slot == null, " container=", container_name, " runtime_count=", runtime_count)
	if slot == null:
		return
	if item == null or amount <= 0:
		slot.clear()
	else:
		if not _container_can_accept_item(item):
			return
		var max_stack: int = _max_stack_size(item)
		slot.set_stack(item, clampi(amount, 1, max_stack))
	if ADAPTER_DEBUG:
		var verify_item_path: String = slot.item.resource_path if slot.item != null else "null"
		print("[LootAdapter] set_slot_data_applied slot=", slot_index, " verify_item=", verify_item_path, " verify_amount=", slot.amount)
	_notify_changed({slot_index: true})


func clear_inventory() -> void:
	var container := _resolve_container()
	if container == null:
		return
	var changed := {}
	for i in range(container.container_size):
		var slot := _get_storage_slot(i)
		if slot == null:
			continue
		if slot.item != null or slot.amount > 0:
			slot.clear()
			changed[i] = true
	_notify_changed(changed)


func _resolve_container() -> LootContainerComponent:
	if _container != null and is_instance_valid(_container):
		_ensure_runtime_slots(_container)
		return _container

	if container_path != NodePath():
		_container = get_node_or_null(container_path) as LootContainerComponent

	if _container != null and is_instance_valid(_container):
		_ensure_runtime_slots(_container)
		return _container

	return null


func _ensure_runtime_slots(container: LootContainerComponent) -> void:
	if container == null:
		return
	if container.has_method("_ensure_runtime_storage"):
		container.call("_ensure_runtime_storage")
	if container.runtime_slots.size() != maxi(0, container.container_size):
		if container.has_method("_rebuild_runtime_slots_from_storage"):
			container.call("_rebuild_runtime_slots_from_storage")


func _is_valid_slot(slot_index: int) -> bool:
	var container := _resolve_container()
	if container == null:
		return false
	return slot_index >= 0 and slot_index < container.container_size


func _get_storage_slot(slot_index: int) -> InventorySlotStackResource:
	if not _is_valid_slot(slot_index):
		if ADAPTER_DEBUG:
			var container := _resolve_container()
			var container_name: String = container.name if container != null else "null"
			var container_size_value: int = container.container_size if container != null else -1
			print("[LootAdapter] get_slot invalid slot=", slot_index, " container=", container_name, " container_size=", container_size_value)
		return null
	var container := _resolve_container()
	if container == null:
		if ADAPTER_DEBUG:
			print("[LootAdapter] get_storage_slot container_null slot=", slot_index)
		return null
	if container.has_method("_ensure_runtime_storage"):
		container.call("_ensure_runtime_storage")
	if container.get("_runtime_inventory_storage") == null:
		return null
	var storage = container.get("_runtime_inventory_storage") as InventoryStorageResource
	if storage == null:
		return null
	return storage.get_slot(slot_index) as InventorySlotStackResource


func _compute_available_space(item: ItemData) -> int:
	if item == null:
		return 0
	var container := _resolve_container()
	if container == null:
		return 0
	if not _container_can_accept_item(item):
		return 0
	var total: int = 0
	for i in range(container.container_size):
		var slot := _get_storage_slot(i)
		if slot == null:
			continue
		if slot.item == null or slot.amount <= 0:
			total += _max_stack_size(item)
		elif slot.item == item:
			total += _available_stack_space(slot)
	return total


func _max_stack_size(item: ItemData) -> int:
	if item == null:
		return 1
	if item.outing_category == "weapon":
		return 1
	var container := _resolve_container()
	if container != null and not container.enable_item_stacking:
		return 1
	return maxi(1, item.MaxStackSize)


func _available_stack_space(slot: InventorySlotStackResource) -> int:
	if slot == null or slot.item == null or slot.amount <= 0:
		return 0
	return maxi(0, _max_stack_size(slot.item) - slot.amount)


func _container_can_accept_item(item: ItemData) -> bool:
	var container := _resolve_container()
	if container == null:
		return false
	if container.has_method("can_accept_item"):
		return bool(container.call("can_accept_item", item))
	return true


func _notify_changed(changed_slots: Dictionary) -> void:
	if changed_slots.is_empty():
		return
	if _batch_update_depth > 0:
		for slot_index in changed_slots.keys():
			_pending_slot_changes[int(slot_index)] = true
		_pending_inventory_changed = true
		_pending_container_sync = true
		return
	for slot_index in changed_slots.keys():
		slot_changed.emit(int(slot_index))
	inventory_changed.emit()

	var container := _resolve_container()
	if container != null and container.has_method("notify_runtime_slots_changed"):
		container.notify_runtime_slots_changed()


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

	if _pending_container_sync:
		_pending_container_sync = false
		var container := _resolve_container()
		if container != null and container.has_method("notify_runtime_slots_changed"):
			container.notify_runtime_slots_changed()
