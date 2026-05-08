extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run_tests()
	if _failures.is_empty():
		print("[PASS] inventory storage rules")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _run_tests() -> void:
	_test_non_weapon_stacks_in_enabled_inventory()
	_test_weapon_never_stacks_in_enabled_inventory()
	_test_container_rejects_disallowed_category()
	_test_transfer_respects_target_category()
	_test_transfer_does_not_stack_weapons()
	_test_outing_loadout_stacks_non_weapons_only()
	_test_outing_commit_entries_and_shelter_return()


func _test_non_weapon_stacks_in_enabled_inventory() -> void:
	var water := load("res://resources/items/water_bottle.tres") as ItemData
	var inv := _make_inventory(4, true)
	var ok := inv.pickup_item(water, 3)
	_expect(ok, "食品应能一次放入启用堆叠的库存")
	var slot := inv.get_slot_data(0)
	_expect(slot.get("item") == water, "食品应进入第一个格子")
	_expect(int(slot.get("amount", 0)) == 3, "食品应按 MaxStackSize 堆叠到同一格")


func _test_weapon_never_stacks_in_enabled_inventory() -> void:
	var knife := load("res://resources/items/knife.tres") as ItemData
	var inv := _make_inventory(4, true)
	var ok := inv.pickup_item(knife, 2)
	_expect(ok, "多把武器可以放入多个格子")
	_expect(int(inv.get_slot_data(0).get("amount", 0)) == 1, "武器第一个格子数量必须是1")
	_expect(int(inv.get_slot_data(1).get("amount", 0)) == 1, "武器第二个格子数量必须是1")
	var moved := inv.move_item_between_slots(1, 0, 1)
	_expect(moved == 0, "武器不能通过同类移动堆叠到同一格")


func _test_container_rejects_disallowed_category() -> void:
	var food_container := _make_container_adapter(PackedStringArray(["food"]), true)
	var water := load("res://resources/items/water_bottle.tres") as ItemData
	var bandage := load("res://resources/items/bandage.tres") as ItemData
	_expect(food_container.insert_item(bandage, 1) == 0, "食品柜应拒绝 medical 物品")
	_expect(food_container.insert_item(water, 3) == 3, "食品柜应接收 food 物品")
	_expect(int(food_container.get_slot_data(0).get("amount", 0)) == 3, "食品柜启用堆叠后应能堆叠食品")


func _test_transfer_respects_target_category() -> void:
	var bandage := load("res://resources/items/bandage.tres") as ItemData
	var source := _make_inventory(2, true)
	source.set_slot_data(0, bandage, 1)
	var food_container := _make_container_adapter(PackedStringArray(["food"]), true)
	var moved := InventoryTransferService.transfer_between_storages(source, 0, food_container, 0, 1)
	_expect(moved == 0, "跨库存拖拽不能绕过柜子分类限制")
	_expect(source.get_slot_data(0).get("item") == bandage, "转移失败时来源物品应保留")
	_expect(food_container.get_slot_data(0).get("item") == null, "转移失败时目标格应保持为空")


func _test_transfer_does_not_stack_weapons() -> void:
	var knife := load("res://resources/items/knife.tres") as ItemData
	var source := _make_inventory(3, true)
	var target := _make_inventory(3, true)
	source.set_slot_data(0, knife, 1)
	target.set_slot_data(0, knife, 1)
	var moved := InventoryTransferService.transfer_between_storages(source, 0, target, 0, 1)
	_expect(moved == 0, "转移服务不能把武器堆叠到已有武器格")
	_expect(int(target.get_slot_data(0).get("amount", 0)) == 1, "目标武器格数量应保持1")


func _test_outing_loadout_stacks_non_weapons_only() -> void:
	var water := load("res://resources/items/water_bottle.tres") as ItemData
	var knife := load("res://resources/items/knife.tres") as ItemData
	var loadout := OutingLoadoutResource.new()
	loadout.slot_count = 12
	loadout.ensure_capacity()
	var water_entry := {
		"source_id": "food_cabinet",
		"source_name": "食品柜",
		"slot_index": 0,
		"item": water,
		"amount": 3,
	}
	_expect(loadout.add_from_entry(water_entry), "外出携带栏应能加入食品")
	_expect(loadout.add_from_entry(water_entry), "外出携带栏应能把同来源食品堆叠")
	_expect(loadout.get_used_slots() == 1, "同来源非武器堆叠后仍只占一格")
	_expect(loadout.get_selected_count_for_source_key("food_cabinet:0") == 2, "携带栏应按数量统计同来源堆叠")
	var weapon_entry := {
		"source_id": "equipment_rack",
		"source_name": "装备架",
		"slot_index": 2,
		"item": knife,
		"amount": 2,
	}
	_expect(loadout.add_from_entry(weapon_entry), "外出携带栏应能加入武器")
	_expect(loadout.add_from_entry(weapon_entry), "第二把同来源武器应进入新格")
	_expect(loadout.get_used_slots() == 3, "武器不能堆叠，应占两个独立格子")
	_expect(loadout.get_commit_keys().size() == 4, "提交键数量应等于已选物品总数量")
	var commit_entries: Array = loadout.get_commit_entries()
	_expect(commit_entries.size() == 4, "提交条目应逐件展开，供外出结算判断归还/消耗")


func _test_outing_commit_entries_and_shelter_return() -> void:
	var knife := load("res://resources/items/knife.tres") as ItemData
	var bandage := load("res://resources/items/bandage.tres") as ItemData
	var storage := InventoryStorageResource.new()
	storage.slot_count = 2
	storage.ensure_capacity()
	storage.get_slot(0).set_stack(knife, 1)
	storage.get_slot(1).set_stack(bandage, 2)

	var source := ShelterStorageSourceResource.new()
	source.source_id = &"test_cabinet"
	source.display_name = "测试柜"
	source.storage = storage
	source.include_in_outing_pool = true

	var shelter := ShelterInventoryResource.new()
	shelter.storage_sources = [source]

	var weapon_key := ShelterInventoryResource.make_entry_key("test_cabinet", 0)
	_expect(shelter.remove_one_from_entry(weapon_key), "外出提交应能从源格扣除武器")
	_expect(storage.get_slot(0).is_empty(), "扣除后武器源格应为空")
	_expect(shelter.add_one_to_entry(weapon_key, knife), "未消耗武器应能归还原源格")
	_expect(storage.get_slot(0).item == knife and int(storage.get_slot(0).amount) == 1, "归还后武器应回到原源格")

	var medical_key := ShelterInventoryResource.make_entry_key("test_cabinet", 1)
	_expect(shelter.remove_one_from_entry(medical_key), "外出提交应能从源格扣除医疗物品")
	_expect(int(storage.get_slot(1).amount) == 1, "医疗物品按消耗品扣除一件后应减少数量")


func _make_inventory(slot_count: int, stacking: bool) -> InventoryDataService:
	var storage := InventoryStorageResource.new()
	storage.slot_count = slot_count
	storage.ensure_capacity()
	var inv := InventoryDataService.new()
	inv.inventory_storage = storage
	inv.enable_item_stacking = stacking
	inv._ready()
	return inv


func _make_container_adapter(categories: PackedStringArray, stacking: bool) -> LootContainerDataAdapter:
	var storage := InventoryStorageResource.new()
	storage.slot_count = 4
	storage.ensure_capacity()
	var container := LootContainerComponent.new()
	container.container_size = 4
	container.inventory_storage = storage
	container.enable_item_stacking = stacking
	container.allowed_item_categories = categories
	container._ready()
	var adapter := LootContainerDataAdapter.new()
	adapter.bind_container(container)
	return adapter


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
