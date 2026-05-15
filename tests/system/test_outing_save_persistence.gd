extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_global_shelter_inventory_roundtrip()
	_test_global_outing_progress_roundtrip()
	_test_energy_bar_can_deposit_to_food_storage()
	await _test_empty_food_save_payload_does_not_wipe_shelter_runtime_defaults()
	_test_legacy_empty_food_global_payload_preserves_defaults()
	if _failures.is_empty():
		print("[PASS] outing save persistence")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

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

func _test_empty_food_save_payload_does_not_wipe_shelter_runtime_defaults() -> void:
	var global_node := root.get_node_or_null("Global")
	var owns_global := false
	if global_node == null:
		var global_script := load("res://scripts/global.gd") as Script
		global_node = global_script.new() as Node
		global_node.name = "Global"
		root.add_child(global_node)
		owns_global = true
	await process_frame
	global_node.reset_shelter_inventory_runtime()
	var water := load("res://resources/items/water_bottle.tres") as ItemData
	var food_storage := _get_storage(global_node, "food_cabinet")
	_expect(food_storage != null, "food_cabinet runtime storage should exist for save payload regression")
	var before := _count_storage_item(food_storage, water)
	_expect(before > 0, "food_cabinet template should start with water")

	var container_script := load("res://components/loot_container_component.gd") as Script
	var container := Node3D.new()
	container.set_script(container_script)
	container.set("container_size", 16)
	container.set("enable_item_stacking", true)
	container.set("use_shelter_inventory_runtime", true)
	container.set("shelter_source_id", &"food_cabinet")
	root.add_child(container)
	container.call("apply_inventory_save_payload", {
		"container_name": "食品柜",
		"container_size": 16,
		"enable_item_stacking": true,
		"slots": [],
	})
	var after := _count_storage_item(food_storage, water)
	_expect(after == before, "empty scene payload should not wipe shelter runtime food cabinet defaults")

	container.queue_free()
	if owns_global:
		global_node.queue_free()


func _test_legacy_empty_food_global_payload_preserves_defaults() -> void:
	var global_script := load("res://scripts/global.gd") as Script
	var global_node := global_script.new() as Node
	root.add_child(global_node)
	global_node.reset_shelter_inventory_runtime()
	var water := load("res://resources/items/water_bottle.tres") as ItemData
	var before := _count_storage_item(_get_storage(global_node, "food_cabinet"), water)
	_expect(before > 0, "food_cabinet default should contain water before legacy payload migration")

	global_node.apply_global_save_payload({
		"version": 2,
		"shelter_inventory": {
			"version": 1,
			"sources": [
				{
					"source_id": "food_cabinet",
					"display_name": "食品柜",
					"source_kind": "food",
					"include_in_outing_pool": true,
					"storage": {"slot_count": 16, "slots": []},
				},
			],
		},
	})
	var after := _count_storage_item(_get_storage(global_node, "food_cabinet"), water)
	_expect(after == before, "legacy empty global food cabinet payload should preserve template defaults")
	global_node.queue_free()

func _count_item(shelter: ShelterInventoryResource, item: ItemData) -> int:
	var total := 0
	for source in shelter.storage_sources:
		var storage := source as InventoryStorageResource
		if storage == null:
			continue
		total += _count_storage_item(storage, item)
	return total

func _count_storage_item(storage: InventoryStorageResource, item: ItemData) -> int:
	var total := 0
	if storage == null or item == null:
		return total
	storage.ensure_capacity()
	for i in range(storage.slot_count):
		var slot := storage.get_slot(i) as InventorySlotStackResource
		if slot != null and not slot.is_empty() and slot.item == item:
			total += int(slot.amount)
	return total

func _get_storage(global_node: Node, source_id: String) -> InventoryStorageResource:
	var inventory := global_node.call("get_shelter_inventory_runtime") as Resource
	if inventory == null:
		return null
	var sources: Array = inventory.get("storage_sources")
	for source_raw in sources:
		var source := source_raw as Resource
		if source == null:
			continue
		if String(source.get("source_id")) == source_id:
			return source as InventoryStorageResource
	return null

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
