extends RefCounted
class_name InventoryTransferService

const TRANSFER_DEBUG := true


static func transfer_between_storages(
	source_storage: Object,
	source_slot: int,
	target_storage: Object,
	target_slot: int,
	requested_amount: int
) -> int:
	if source_storage == null or target_storage == null:
		return 0
	if requested_amount <= 0:
		return 0
	if not _supports_slot_access(source_storage) or not _supports_slot_access(target_storage):
		return 0

	var source_slot_count: int = int(source_storage.call("get_slot_count"))
	var target_slot_count: int = int(target_storage.call("get_slot_count"))
	if source_slot < 0 or source_slot >= source_slot_count:
		return 0
	if target_slot < 0 or target_slot >= target_slot_count:
		return 0

	if source_storage == target_storage:
		if source_storage.has_method("move_item_between_slots"):
			return int(source_storage.call("move_item_between_slots", source_slot, target_slot, requested_amount))
		return 0

	var source_before: Dictionary = _read_slot_data(source_storage, source_slot)
	var target_before: Dictionary = _read_slot_data(target_storage, target_slot)
	var source_item: ItemData = source_before.get("item", null) as ItemData
	var source_amount: int = int(source_before.get("amount", 0))
	var target_item: ItemData = target_before.get("item", null) as ItemData
	var target_amount: int = int(target_before.get("amount", 0))
	if source_item == null or source_amount <= 0:
		return 0
	if not storage_can_accept_item(target_storage, source_item):
		return 0

	var move_amount: int = mini(requested_amount, source_amount)
	var moved: int = 0
	var source_after: Dictionary = source_before.duplicate(true)
	var target_after: Dictionary = target_before.duplicate(true)

	if target_item == null or target_amount <= 0:
		var target_capacity: int = get_storage_max_stack_for_item(target_storage, source_item)
		moved = mini(move_amount, target_capacity)
		if moved <= 0:
			return 0
		source_after = _make_slot_dict(source_item, source_amount - moved)
		target_after = _make_slot_dict(source_item, moved)
	elif items_match(target_item, source_item):
		var available: int = maxi(0, get_storage_max_stack_for_item(target_storage, source_item) - target_amount)
		moved = mini(move_amount, available)
		if moved <= 0:
			return 0
		source_after = _make_slot_dict(source_item, source_amount - moved)
		target_after = _make_slot_dict(source_item, target_amount + moved)
	else:
		if move_amount < source_amount:
			return 0
		if not storage_can_accept_item(source_storage, target_item):
			return 0
		if target_amount > get_storage_max_stack_for_item(source_storage, target_item):
			return 0
		if source_amount > get_storage_max_stack_for_item(target_storage, source_item):
			return 0
		moved = source_amount
		source_after = _make_slot_dict(target_item, target_amount)
		target_after = _make_slot_dict(source_item, source_amount)

	if moved <= 0:
		return 0

	_begin_batch(source_storage)
	_begin_batch(target_storage)
	var commit_ok: bool = _commit_pair(
		source_storage,
		source_slot,
		source_before,
		source_after,
		target_storage,
		target_slot,
		target_before,
		target_after
	)
	_end_batch(target_storage)
	_end_batch(source_storage)

	if not commit_ok:
		if TRANSFER_DEBUG:
			print("[InvTransferService] commit_failed source_slot=", source_slot, " target_slot=", target_slot)
		return 0

	if TRANSFER_DEBUG:
		print("[InvTransferService] commit_ok source_slot=", source_slot, " target_slot=", target_slot, " moved=", moved)
	return moved


static func transfer_to_first_available(
	source_storage: Object,
	source_slot: int,
	target_storage: Object,
	requested_amount: int
) -> int:
	if source_storage == null or target_storage == null or requested_amount <= 0:
		return 0
	if not target_storage.has_method("get_slot_count"):
		return 0

	var source_data: Dictionary = _read_slot_data(source_storage, source_slot)
	var source_item: ItemData = source_data.get("item", null) as ItemData
	var source_amount: int = int(source_data.get("amount", 0))
	if source_item == null or source_amount <= 0:
		return 0

	var remaining: int = mini(requested_amount, source_amount)
	var slot_count: int = int(target_storage.call("get_slot_count"))
	var moved_total: int = 0

	for i in range(slot_count):
		if remaining <= 0:
			break
		var target_data: Dictionary = _read_slot_data(target_storage, i)
		var target_item: ItemData = target_data.get("item", null) as ItemData
		var target_amount: int = int(target_data.get("amount", 0))
		if not items_match(target_item, source_item) or target_amount <= 0:
			continue
		var moved_stack: int = transfer_between_storages(source_storage, source_slot, target_storage, i, remaining)
		if moved_stack <= 0:
			continue
		moved_total += moved_stack
		remaining -= moved_stack

	for i in range(slot_count):
		if remaining <= 0:
			break
		var target_data: Dictionary = _read_slot_data(target_storage, i)
		var target_item: ItemData = target_data.get("item", null) as ItemData
		var target_amount: int = int(target_data.get("amount", 0))
		if target_item != null and target_amount > 0:
			continue
		var moved_empty: int = transfer_between_storages(source_storage, source_slot, target_storage, i, remaining)
		if moved_empty <= 0:
			continue
		moved_total += moved_empty
		remaining -= moved_empty

	return moved_total


static func drop_from_source(source_storage: Object, from_slot: int, requested_amount: int) -> Dictionary:
	if source_storage == null:
		return {"item": null, "amount": 0}
	if requested_amount <= 0:
		return {"item": null, "amount": 0}
	if not source_storage.has_method("remove_from_slot"):
		return {"item": null, "amount": 0}

	var removed_variant: Variant = source_storage.call("remove_from_slot", from_slot, requested_amount)
	if typeof(removed_variant) != TYPE_DICTIONARY:
		return {"item": null, "amount": 0}
	return removed_variant as Dictionary


static func get_storage_max_stack_for_item(storage: Object, item: ItemData) -> int:
	if item == null:
		return 1
	if item.outing_category == "weapon":
		return 1
	if storage == null:
		return 1

	if storage is LootContainerDataAdapter:
		var adapter := storage as LootContainerDataAdapter
		var container := adapter.get_bound_container()
		if container != null and not container.enable_item_stacking:
			return 1

	if storage is InventoryDataService:
		var inventory := storage as InventoryDataService
		if not inventory.enable_item_stacking:
			return 1

	return maxi(1, item.MaxStackSize)


static func storage_can_accept_item(storage: Object, item: ItemData) -> bool:
	if item == null:
		return false
	if storage == null:
		return false

	if storage.has_method("can_accept_item"):
		return bool(storage.call("can_accept_item", item))

	if storage is LootContainerDataAdapter:
		var adapter := storage as LootContainerDataAdapter
		var container := adapter.get_bound_container()
		if container != null and container.has_method("can_accept_item"):
			return bool(container.call("can_accept_item", item))

	return true


## 判断两个库存物品是否代表同一种物品。
## 不要只用 `==`：存档、容器和玩家库存可能从同一个 `.tres` 各自
## duplicate 出不同的 Resource 实例。比较资源路径，才能保证堆叠和转移一致。
static func items_match(left: ItemData, right: ItemData) -> bool:
	if left == right:
		return true
	if left == null or right == null:
		return false
	var left_path := String(left.resource_path).strip_edges()
	var right_path := String(right.resource_path).strip_edges()
	if not left_path.is_empty() and not right_path.is_empty():
		return left_path == right_path
	var left_name := String(left.ItemName).strip_edges().to_lower()
	var right_name := String(right.ItemName).strip_edges().to_lower()
	return not left_name.is_empty() and left_name == right_name


static func _supports_slot_access(storage: Object) -> bool:
	return (
		storage != null
		and storage.has_method("get_slot_count")
		and storage.has_method("get_slot_data")
		and storage.has_method("set_slot_data")
	)


static func _read_slot_data(storage: Object, slot_index: int) -> Dictionary:
	if storage == null or not storage.has_method("get_slot_data"):
		return {"item": null, "amount": 0}
	var slot_data_variant: Variant = storage.call("get_slot_data", slot_index)
	if typeof(slot_data_variant) != TYPE_DICTIONARY:
		return {"item": null, "amount": 0}
	return slot_data_variant as Dictionary


static func _make_slot_dict(item: ItemData, amount: int) -> Dictionary:
	if item == null or amount <= 0:
		return {"item": null, "amount": 0}
	return {"item": item, "amount": amount}


static func _begin_batch(storage: Object) -> void:
	if storage != null and storage.has_method("begin_batch_update"):
		storage.call("begin_batch_update")


static func _end_batch(storage: Object) -> void:
	if storage != null and storage.has_method("end_batch_update"):
		storage.call("end_batch_update")


static func _write_slot_dict(storage: Object, slot_index: int, slot_data: Dictionary) -> void:
	if storage == null or not storage.has_method("set_slot_data"):
		return
	var item: ItemData = slot_data.get("item", null) as ItemData
	var amount: int = int(slot_data.get("amount", 0))
	storage.call("set_slot_data", slot_index, item, amount)


static func _slot_equals(actual: Dictionary, expected: Dictionary) -> bool:
	var actual_item: ItemData = actual.get("item", null) as ItemData
	var expected_item: ItemData = expected.get("item", null) as ItemData
	var actual_amount: int = int(actual.get("amount", 0))
	var expected_amount: int = int(expected.get("amount", 0))
	return items_match(actual_item, expected_item) and actual_amount == expected_amount


static func _commit_pair(
	source_storage: Object,
	source_slot: int,
	source_before: Dictionary,
	source_after: Dictionary,
	target_storage: Object,
	target_slot: int,
	target_before: Dictionary,
	target_after: Dictionary
) -> bool:
	_write_slot_dict(source_storage, source_slot, source_after)
	_write_slot_dict(target_storage, target_slot, target_after)

	var source_verify: Dictionary = _read_slot_data(source_storage, source_slot)
	var target_verify: Dictionary = _read_slot_data(target_storage, target_slot)
	if _slot_equals(source_verify, source_after) and _slot_equals(target_verify, target_after):
		return true

	if TRANSFER_DEBUG:
		print(
			"[InvTransferService] verify_failed",
			" source_storage=", source_storage.get_class(),
			" target_storage=", target_storage.get_class(),
			" source_expected=", _slot_debug_string(source_after),
			" source_actual=", _slot_debug_string(source_verify),
			" target_expected=", _slot_debug_string(target_after),
			" target_actual=", _slot_debug_string(target_verify)
		)

	_write_slot_dict(source_storage, source_slot, source_before)
	_write_slot_dict(target_storage, target_slot, target_before)
	return false


static func _slot_debug_string(slot_data: Dictionary) -> String:
	var item: ItemData = slot_data.get("item", null) as ItemData
	var amount: int = int(slot_data.get("amount", 0))
	var item_path: String = "null"
	if item != null:
		item_path = item.resource_path
	return "{item=%s, amount=%d}" % [item_path, amount]
