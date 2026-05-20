extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	await process_frame
	_test_every_item_resource_has_saveable_world_scene()
	_test_shelter_best_storage_accepts_every_outing_item()
	_test_global_shelter_payload_roundtrips_every_item()
	await _test_player_inventory_save_component_roundtrip()
	if _failures.is_empty():
		print("[PASS] item save coverage")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_every_item_resource_has_saveable_world_scene() -> void:
	for item in _load_all_items():
		var scene_path := String(item.ItemModelScenePath).strip_edges()
		_expect(not scene_path.is_empty(), "%s should define ItemModelScenePath" % item.resource_path)
		_expect(ResourceLoader.exists(scene_path), "%s model scene missing: %s" % [item.resource_path, scene_path])
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var packed := load(scene_path) as PackedScene
		_expect(packed != null, "%s model scene should load" % item.resource_path)
		if packed == null:
			continue
		var node := packed.instantiate()
		_expect(node != null, "%s model scene should instantiate" % item.resource_path)
		if node == null:
			continue
		_expect(_find_save_component(node) != null, "%s world scene should include SaveComponent" % item.resource_path)
		_expect(_find_interactable_item(node) != null, "%s world scene should include InteractableItem" % item.resource_path)
		var found_item := _find_interactable_item(node)
		if found_item != null:
			var scene_item = found_item.get("item_data")
			_expect(scene_item == item, "%s world scene item_data should point back to this ItemData" % item.resource_path)
		node.queue_free()

func _test_shelter_best_storage_accepts_every_outing_item() -> void:
	for item in _load_all_items():
		if not item.can_take_outing:
			continue
		var shelter := load("res://resources/storage/shelter_inventory_default.tres").duplicate(true) as ShelterInventoryResource
		var expected_kind := _expected_source_kind(item)
		var before := _count_item_in_kind(shelter, item, expected_kind)
		var added := int(shelter.add_items_to_best_storage(item, _test_amount_for(item)))
		var after := _count_item_in_kind(shelter, item, expected_kind)
		_expect(added == _test_amount_for(item), "%s should be accepted by shelter storage" % item.resource_path)
		_expect(after == before + _test_amount_for(item), "%s should be routed into %s storage, not only return bag" % [item.resource_path, expected_kind])

func _test_global_shelter_payload_roundtrips_every_item() -> void:
	var global_script := load("res://scripts/global.gd") as Script
	var global_node := global_script.new() as Node
	global_node.name = "GlobalForItemCoverage"
	root.add_child(global_node)
	global_node.reset_shelter_inventory_runtime()
	var shelter := global_node.get_shelter_inventory_runtime() as ShelterInventoryResource
	var expected_counts := {}
	for item in _load_all_items():
		if not item.can_take_outing:
			continue
		var expected_kind := _expected_source_kind(item)
		var before := _count_item_in_kind(shelter, item, expected_kind)
		var amount := _test_amount_for(item)
		var added := int(shelter.add_items_to_best_storage(item, amount))
		_expect(added == amount, "%s should be inserted before global save" % item.resource_path)
		expected_counts[item.resource_path] = before + amount
	var payload: Dictionary = global_node.build_global_save_payload()
	global_node.reset_shelter_inventory_runtime()
	global_node.apply_global_save_payload(payload)
	var restored := global_node.get_shelter_inventory_runtime() as ShelterInventoryResource
	for item in _load_all_items():
		if not item.can_take_outing:
			continue
		var expected_kind := _expected_source_kind(item)
		var actual := _count_item_in_kind(restored, item, expected_kind)
		_expect(actual == int(expected_counts.get(item.resource_path, -1)), "%s should survive global save/load in %s storage" % [item.resource_path, expected_kind])
	global_node.queue_free()

func _test_player_inventory_save_component_roundtrip() -> void:
	var player := Node3D.new()
	player.name = "PlayerController"
	player.add_to_group("Player")
	root.add_child(player)
	var save_comp := SaveComponent.new()
	save_comp.name = "SaveComponent"
	save_comp.unique_id = "player_001"
	player.add_child(save_comp)
	var components := Node.new()
	components.name = "Components"
	player.add_child(components)
	var inv := InventoryDataService.new()
	inv.name = "InventoryDataService"
	inv.inventory_storage = InventoryStorageResource.new()
	inv.inventory_storage.slot_count = 12
	inv.inventory_storage.ensure_capacity()
	inv.enable_item_stacking = true
	components.add_child(inv)
	await process_frame
	var water := load("res://resources/items/water_bottle.tres") as ItemData
	var knife := load("res://resources/items/knife.tres") as ItemData
	_expect(inv.pickup_item(water, 3), "player inventory should accept stacked water before save")
	_expect(inv.pickup_item(knife, 1), "player inventory should accept weapon before save")
	var data := save_comp.get_save_data()
	inv.clear_inventory()
	_expect(inv.get_slot_data(0).get("item") == null, "player inventory should be clear before restore")
	save_comp.load_save_data(data)
	_expect(inv.get_slot_data(0).get("item") == water and int(inv.get_slot_data(0).get("amount", 0)) == 3, "player water stack should restore through SaveComponent")
	_expect(_inventory_contains(inv, knife, 1), "player weapon should restore through SaveComponent")
	player.queue_free()

func _load_all_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	var dir := DirAccess.open("res://resources/items")
	_expect(dir != null, "resources/items should be readable")
	if dir == null:
		return result
	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres"):
			continue
		var path := "res://resources/items/" + file_name
		var item := load(path) as ItemData
		_expect(item != null, "%s should load as ItemData" % path)
		if item != null:
			result.append(item)
	return result

func _find_save_component(root_node: Node) -> SaveComponent:
	if root_node is SaveComponent:
		return root_node as SaveComponent
	var direct := root_node.get_node_or_null("SaveComponent")
	if direct is SaveComponent:
		return direct as SaveComponent
	for child in root_node.find_children("*", "SaveComponent", true, false):
		if child is SaveComponent:
			return child as SaveComponent
	return null

func _find_interactable_item(root_node: Node) -> Node:
	if root_node is InteractableItem:
		return root_node
	for child in root_node.find_children("*", "InteractableItem", true, false):
		if child is InteractableItem:
			return child
	return null

func _expected_source_kind(item: ItemData) -> String:
	match item.outing_category:
		"food":
			return "food"
		"medical":
			return "medical"
		"material":
			return "material"
		"weapon", "tool", "special":
			return "equipment"
		_:
			return "temporary"

func _test_amount_for(item: ItemData) -> int:
	if item.outing_category == "weapon":
		return 1
	return mini(2, maxi(1, item.MaxStackSize))

func _count_item_in_kind(shelter: ShelterInventoryResource, item: ItemData, source_kind: String) -> int:
	var total := 0
	if shelter == null or item == null:
		return total
	for source in shelter.storage_sources:
		var storage := source as InventoryStorageResource
		if storage == null:
			continue
		if String(storage.source_kind) != source_kind:
			continue
		storage.ensure_capacity()
		for i in range(storage.slot_count):
			var slot := storage.get_slot(i) as InventorySlotStackResource
			if slot != null and not slot.is_empty() and slot.item == item:
				total += int(slot.amount)
	return total

func _inventory_contains(inv: InventoryDataService, item: ItemData, amount: int) -> bool:
	var total := 0
	for entry in inv.get_all_slots():
		if entry.get("item") == item:
			total += int(entry.get("amount", 0))
	return total >= amount

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
