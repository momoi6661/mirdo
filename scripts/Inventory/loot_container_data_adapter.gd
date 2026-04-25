extends InventoryDataService
class_name LootContainerDataAdapter

@export var container_path: NodePath

var _container: LootContainerComponent


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
	var slot := _get_slot(slot_index)
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
	var slot := _get_slot(slot_index)
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
	var available: int = _compute_available_space(item)
	return available >= amount


func insert_item(item: ItemData, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return 0
	var container := _resolve_container()
	if container == null:
		return 0

	var changed := {}
	var remaining: int = amount

	for i in range(container.container_size):
		if remaining <= 0:
			break
		var slot := _get_slot(i)
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
		var slot := _get_slot(i)
		if slot == null:
			continue
		if slot.item != null and slot.amount > 0:
			continue
		var add_amount: int = mini(_max_stack_size(item), remaining)
		slot.item = item
		slot.amount = add_amount
		remaining -= add_amount
		changed[i] = true

	_notify_changed(changed)
	return amount - remaining


func move_item_between_slots(from_slot_index: int, to_slot_index: int, amount: int = 0) -> int:
	if not _is_valid_slot(from_slot_index) or not _is_valid_slot(to_slot_index):
		return 0
	if from_slot_index == to_slot_index:
		return 0

	var from_slot := _get_slot(from_slot_index)
	var to_slot := _get_slot(to_slot_index)
	if from_slot == null or to_slot == null:
		return 0
	if from_slot.item == null or from_slot.amount <= 0:
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
			from_slot.item = null
			from_slot.amount = 0
		changed[from_slot_index] = true
		changed[to_slot_index] = true
		_notify_changed(changed)
		return stacked

	if to_slot.item == null or to_slot.amount <= 0:
		to_slot.item = from_slot.item
		to_slot.amount = move_amount
		from_slot.amount -= move_amount
		if from_slot.amount <= 0:
			from_slot.item = null
			from_slot.amount = 0
		changed[from_slot_index] = true
		changed[to_slot_index] = true
		_notify_changed(changed)
		return move_amount

	if move_amount < from_slot.amount:
		return 0

	var temp_item: ItemData = to_slot.item
	var temp_amount: int = to_slot.amount
	to_slot.item = from_slot.item
	to_slot.amount = from_slot.amount
	from_slot.item = temp_item
	from_slot.amount = temp_amount
	changed[from_slot_index] = true
	changed[to_slot_index] = true
	_notify_changed(changed)
	return move_amount


func remove_from_slot(slot_index: int, amount: int = 0) -> Dictionary:
	var slot := _get_slot(slot_index)
	if slot == null or slot.item == null or slot.amount <= 0:
		return {"item": null, "amount": 0}

	var take_amount: int = slot.amount
	if amount > 0:
		take_amount = clampi(amount, 1, slot.amount)

	var removed_item: ItemData = slot.item
	slot.amount -= take_amount
	if slot.amount <= 0:
		slot.item = null
		slot.amount = 0

	_notify_changed({slot_index: true})
	return {
		"item": removed_item,
		"amount": take_amount,
	}


func set_slot_data(slot_index: int, item: ItemData, amount: int) -> void:
	var slot := _get_slot(slot_index)
	if slot == null:
		return
	if item == null or amount <= 0:
		slot.item = null
		slot.amount = 0
	else:
		slot.item = item
		slot.amount = clampi(amount, 1, _max_stack_size(item))
	_notify_changed({slot_index: true})


func clear_inventory() -> void:
	var container := _resolve_container()
	if container == null:
		return
	var changed := {}
	for i in range(container.container_size):
		var slot := _get_slot(i)
		if slot == null:
			continue
		if slot.item != null or slot.amount > 0:
			slot.item = null
			slot.amount = 0
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
	var target_count: int = maxi(0, container.container_size)
	while container.runtime_slots.size() < target_count:
		var slot := SlotConfig.new()
		slot.slot_id = container.runtime_slots.size()
		slot.item = null
		slot.amount = 0
		container.runtime_slots.append(slot)
	if container.runtime_slots.size() > target_count:
		container.runtime_slots.resize(target_count)

	for i in range(container.runtime_slots.size()):
		var slot := container.runtime_slots[i] as SlotConfig
		if slot == null:
			slot = SlotConfig.new()
			container.runtime_slots[i] = slot
		slot.slot_id = i
		if slot.amount <= 0:
			slot.amount = 0
			slot.item = null


func _is_valid_slot(slot_index: int) -> bool:
	var container := _resolve_container()
	if container == null:
		return false
	return slot_index >= 0 and slot_index < container.container_size


func _get_slot(slot_index: int) -> SlotConfig:
	if not _is_valid_slot(slot_index):
		return null
	var container := _resolve_container()
	if container == null:
		return null
	return container.runtime_slots[slot_index] as SlotConfig


func _compute_available_space(item: ItemData) -> int:
	if item == null:
		return 0
	var container := _resolve_container()
	if container == null:
		return 0
	var total: int = 0
	for i in range(container.container_size):
		var slot := _get_slot(i)
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
	var container := _resolve_container()
	if container != null and not container.enable_item_stacking:
		return 1
	return maxi(1, item.MaxStackSize)


func _available_stack_space(slot: SlotConfig) -> int:
	if slot == null or slot.item == null or slot.amount <= 0:
		return 0
	return maxi(0, _max_stack_size(slot.item) - slot.amount)


func _notify_changed(changed_slots: Dictionary) -> void:
	if changed_slots.is_empty():
		return
	for slot_index in changed_slots.keys():
		slot_changed.emit(int(slot_index))
	inventory_changed.emit()

	var container := _resolve_container()
	if container != null and container.has_method("notify_runtime_slots_changed"):
		container.notify_runtime_slots_changed()
