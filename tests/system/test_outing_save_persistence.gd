extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	_run_tests()
	if _failures.is_empty():
		print("[PASS] outing save persistence")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _run_tests() -> void:
	_test_global_shelter_inventory_roundtrip()
	_test_global_outing_progress_roundtrip()
	_test_energy_bar_can_deposit_to_food_storage()

func _test_global_shelter_inventory_roundtrip() -> void:
	var global_script := load("res://scripts/global.gd") as Script
	var global_node := global_script.new() as Node
	root.add_child(global_node)
	global_node.reset_shelter_inventory_runtime()
	var shelter := global_node.get_shelter_inventory_runtime() as ShelterInventoryResource
	var water := load("res://resources/items/water_bottle.tres") as ItemData
	var before := _count_item(shelter, water)
	var added := int(shelter.add_items_to_best_storage(water, 2))
	_expect(added == 2, "外出结算应能把水写入庇护所总库存")
	var payload: Dictionary = global_node.build_global_save_payload()
	global_node.reset_shelter_inventory_runtime()
	global_node.apply_global_save_payload(payload)
	var restored := global_node.get_shelter_inventory_runtime() as ShelterInventoryResource
	_expect(_count_item(restored, water) == before + 2, "保存/读取后外出获得的水应保留")
	global_node.queue_free()

func _test_global_outing_progress_roundtrip() -> void:
	var global_script := load("res://scripts/global.gd") as Script
	var global_node := global_script.new() as Node
	root.add_child(global_node)
	global_node.reset_outing_map_progress_runtime()
	var progress: Resource = global_node.get_outing_map_progress_runtime()
	progress.unlock_location("clinic")
	progress.record_success("residential")
	var payload: Dictionary = global_node.build_global_save_payload()
	global_node.reset_outing_map_progress_runtime()
	global_node.apply_global_save_payload(payload)
	var restored: Resource = global_node.get_outing_map_progress_runtime()
	_expect(restored.is_unlocked("clinic"), "保存/读取后新发现地点应仍然解锁")
	_expect(int(restored.successful_explore_counts.get("residential", 0)) == 1, "地点探索次数应保存")
	global_node.queue_free()

func _test_energy_bar_can_deposit_to_food_storage() -> void:
	var shelter := load("res://resources/storage/shelter_inventory_default.tres").duplicate(true) as ShelterInventoryResource
	var energy_bar := load("res://resources/items/energy_bar.tres") as ItemData
	var before := _count_item(shelter, energy_bar)
	var added := shelter.add_items_to_best_storage(energy_bar, 2)
	_expect(added == 2, "能量棒是外出食物奖励，应能进入食品柜而不是丢失")
	_expect(_count_item(shelter, energy_bar) == before + 2, "能量棒写入食品柜后数量应增加")

func _count_item(shelter: ShelterInventoryResource, item: ItemData) -> int:
	var total := 0
	for source in shelter.storage_sources:
		var storage := source as InventoryStorageResource
		if storage == null:
			continue
		storage.ensure_capacity()
		for i in range(storage.slot_count):
			var slot := storage.get_slot(i) as InventorySlotStackResource
			if slot != null and not slot.is_empty() and slot.item == item:
				total += int(slot.amount)
	return total

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
